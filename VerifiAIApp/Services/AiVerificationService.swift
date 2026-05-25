import Foundation
import GoogleGenerativeAI

class AiVerificationService {

    // ✅ Las keys vienen de APIKeys.swift — edítalas allá, no aquí
    private let geminiApiKey = APIKeys.gemini
    private let xAIApiKey   = APIKeys.grok

    private let jsonModel: GenerativeModel
    private let newsAPIService = NewsAPIVerificationService()
    private let geminiRESTBase = "https://generativelanguage.googleapis.com/v1beta/models"

    init() {
        let jsonConfig = GenerationConfig(
            temperature: 0.1,
            responseMIMEType: "application/json"
        )
        self.jsonModel = GenerativeModel(
            name: "gemini-2.5-flash",
            apiKey: geminiApiKey,
            generationConfig: jsonConfig
        )
    }

    // MARK: - Agente 1: Grok
    private func fetchGrokContext(query: String) async -> String {
        guard !xAIApiKey.isEmpty, xAIApiKey != "AQUI_VA_TU_GROK_KEY" else {
            return "Contexto de redes sociales no disponible."
        }
        guard let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
            return "Error de URL."
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(xAIApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",    forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "grok-beta",
            "max_tokens": 300,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    Eres un monitor de redes sociales en tiempo real.
                    Busca si el evento descrito está siendo reportado en X (Twitter).
                    Responde brevemente: ¿quién lo reporta?, ¿hay desmentidos?
                    Si no tienes datos específicos, dilo claramente. No inventes.
                    """
                ],
                ["role": "user", "content": "Busca información reciente sobre: \(query)"]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return "Sin contexto de redes sociales."
            }
            if let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices  = json["choices"] as? [[String: Any]],
               let message  = choices.first?["message"] as? [String: Any],
               let content  = message["content"] as? String {
                return content
            }
        } catch {
            print("❌ Error Grok: \(error.localizedDescription)")
        }
        return "Sin respuesta de redes sociales."
    }

    // MARK: - Agente 2: Gemini REST con Google Search Grounding
    private func fetchGroundedFacts(query: String, imageData: Data?) async -> String {
        guard !geminiApiKey.isEmpty, geminiApiKey != "AQUI_VA_TU_GEMINI_KEY" else {
            return "Grounding no disponible: falta Gemini API Key."
        }

        let endpoint = "\(geminiRESTBase)/gemini-2.5-flash:generateContent?key=\(geminiApiKey)"
        guard let url = URL(string: endpoint) else { return "Error construyendo URL de Gemini." }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var parts: [[String: Any]] = [
            ["text": """
            Eres un fact-checker profesional con acceso a búsqueda web en tiempo real.
            Verifica la siguiente noticia buscando en internet ahora mismo.

            NOTICIA A VERIFICAR:
            \(query)

            Responde en español con:
            1. ¿Lo confirman medios reconocidos? ¿Cuáles encontraste?
            2. ¿Hay desmentidos o correcciones publicadas?
            3. ¿Es reciente o una noticia antigua que está recirculando?
            4. ¿Nivel de confianza en su veracidad? (Alto / Medio / Bajo) y por qué.

            Sé específico. Si no encuentras información, dilo claramente.
            """]
        ]

        if let data = imageData {
            parts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": data.base64EncodedString()
                ]
            ])
        }

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "tools": [["google_search": [:]]],
            "generationConfig": ["temperature": 0.1]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            print("🌐 Gemini buscando en Google (grounding activo)...")
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else { return "Error de red en Gemini REST." }

            if http.statusCode != 200 {
                if let errorText = String(data: data, encoding: .utf8) {
                    print("❌ Gemini REST error \(http.statusCode): \(errorText)")
                }
                return "Gemini no pudo buscar en internet (código \(http.statusCode))."
            }

            if let json       = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let content    = candidates.first?["content"] as? [String: Any],
               let parts      = content["parts"] as? [[String: Any]] {
                let fullText = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !fullText.isEmpty {
                    print("✅ Grounding completado.")
                    return fullText
                }
            }
        } catch {
            print("❌ Error Gemini REST: \(error.localizedDescription)")
        }
        return "No se pudo obtener contexto de búsqueda web."
    }

    // MARK: - Síntesis Final: Gemini SDK → JSON
    private func synthesizeToJSON(
        originalContent: String,
        groundedFacts:   String,
        grokContext:     String,
        newsAPIContext:  NewsVerificationContext,
        imageData:       Data?,
        today:           String
    ) async throws -> AnalysisResult {

        let newsAPIBlock = newsAPIContext.isEmpty
            ? "NewsAPI no encontró cobertura periodística específica de esta noticia."
            : "COBERTURA EN MEDIOS (NewsAPI):\n\(newsAPIContext.formattedForPrompt)"

        var parts: [ModelContent.Part] = []
        if let data = imageData { parts.append(.data(mimetype: "image/jpeg", data)) }

        let prompt = """
        Hoy es \(today).

        Eres un equipo de analistas de información. Con base en la investigación ya realizada,
        produce el veredicto final estructurado en JSON.

        ════════════════════════════════════════
        CONTENIDO ORIGINAL DEL USUARIO:
        \(originalContent)

        ════════════════════════════════════════
        INVESTIGACIÓN WEB EN TIEMPO REAL:
        \(groundedFacts)

        ════════════════════════════════════════
        TENDENCIAS EN REDES SOCIALES:
        \(grokContext)

        ════════════════════════════════════════
        \(newsAPIBlock)

        ════════════════════════════════════════
        RÚBRICA DE CALIFICACIÓN (0 a 100):

        truthScore:
          90-100 → Confirmado por múltiples medios serios con detalles concretos
          60-89  → Indicios sólidos, pero sin confirmación completa
          30-59  → Información parcial o sin cobertura periodística clara
          0-29   → Desmentido, sin evidencia alguna, o claramente falso

        reliabilityScore (evalúa la FUENTE, no el contenido):
          90-100 → Medio establecido o fuente oficial
          60-89  → Medio local o especializado con historial verificable
          30-59  → Fuente no identificada o con historial mixto
          0-29   → Red social, blog anónimo, cadena de mensajería

        consensusScore:
          100 → Amplia cobertura de múltiples medios independientes
          50  → Pocos medios lo reportan
          0   → Fuente única o aislada

        biasScore:
          100 → Lenguaje muy cargado, emocional, polarizante
          0   → Redacción neutral y objetiva

        sensationalismScore:
          100 → Clickbait severo, exageración extrema
          0   → Descripción factual y mesurada

        factCheckableScore:
          100 → Incluye fechas, lugares, nombres, cifras verificables
          0   → Vago, sin datos concretos

        REGLA CRÍTICA: Si no hay evidencia que confirme la noticia, truthScore DEBE ser bajo (0-40).

        FORMATO DEL SUMMARY:
        - COMIENZA EXACTAMENTE CON: "A fecha de hoy (\(today)):"
        - Tono periodístico profesional en español
        - Menciona fuentes específicas encontradas (o su ausencia)
        - Máximo 4 oraciones
        - NUNCA menciones herramientas de IA, APIs ni procesos internos

        DEVUELVE SOLO JSON VÁLIDO. SIN MARKDOWN. SIN TEXTO EXTRA.

        {
          "headline": "Titular neutral e informativo del análisis",
          "truthScore": 0,
          "reliabilityScore": 0,
          "consensusScore": 0,
          "biasScore": 0,
          "sensationalismScore": 0,
          "factCheckableScore": 0,
          "sources": ["fuentes reales encontradas"],
          "summary": "A fecha de hoy (\(today)): ...",
          "imageUrl": null
        }
        """

        parts.append(.text(prompt))
        let requestContent = ModelContent(role: "user", parts: parts)

        print("📊 Sintetizando veredicto final en JSON...")
        let response = try await jsonModel.generateContent([requestContent])

        guard var responseText = response.text else {
            throw NSError(domain: "ParseError", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Gemini no devolvió texto"])
        }

        responseText = responseText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = responseText.firstIndex(of: "{"),
           let end   = responseText.lastIndex(of: "}") {
            responseText = String(responseText[start...end])
        }

        guard let jsonData = responseText.data(using: .utf8) else {
            throw NSError(domain: "ParseError", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Error convirtiendo respuesta a Data"])
        }

        do {
            var result = try JSONDecoder().decode(AnalysisResult.self, from: jsonData)

            if !newsAPIContext.isEmpty {
                var merged = result.sources
                for source in newsAPIContext.sourceNames where !merged.contains(source) {
                    merged.append(source)
                }
                result = AnalysisResult(
                    headline: result.headline,
                    truthScore: result.truthScore,
                    reliabilityScore: result.reliabilityScore,
                    consensusScore: result.consensusScore,
                    biasScore: result.biasScore,
                    sensationalismScore: result.sensationalismScore,
                    factCheckableScore: result.factCheckableScore,
                    sources: merged,
                    summary: result.summary,
                    imageUrl: result.imageUrl
                )
            }
            return result

        } catch {
            print("❌ JSON que causó error:\n\(responseText)")
            throw NSError(domain: "ParseError", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Error decodificando JSON: \(error.localizedDescription)"])
        }
    }

    // MARK: - Orquestador principal
    func analyzeNews(text: String?, imageData: Data?) async throws -> AnalysisResult {

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateStyle = .full
        let today = formatter.string(from: Date())

        let query = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !query.isEmpty || imageData != nil else {
            throw NSError(domain: "InputError", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No hay contenido para analizar"])
        }

        print("\n🚀 Iniciando análisis multi-agente...")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⏳ Fase 1: Grok + Gemini Grounding + NewsAPI en paralelo...")

        async let grokTask      = fetchGrokContext(query: query)
        async let groundingTask = fetchGroundedFacts(query: query, imageData: imageData)
        async let newsAPITask   = newsAPIService.searchRelatedArticles(query: query)

        let (grokContext, groundedFacts, newsAPIContext) = await (grokTask, groundingTask, newsAPITask)

        print("✅ Fase 1 completa.")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⏳ Fase 2: Sintetizando veredicto final...")

        let result = try await synthesizeToJSON(
            originalContent: query,
            groundedFacts:   groundedFacts,
            grokContext:     grokContext,
            newsAPIContext:  newsAPIContext,
            imageData:       imageData,
            today:           today
        )

        print("✅ Análisis completo.")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        return result
    }
}
