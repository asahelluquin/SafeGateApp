import Foundation
import ImageIO

// MARK: - Modelos de resultado forense

struct ForensicsResult {
    let riskScore:            Int              // 0–100
    let verdict:              ForensicsVerdict
    let manipulationSignals:  [ForensicSignal]
    let authenticSignals:     [String]
    let aiLikelihood:         String           // nula / baja / media / alta
    let aiIndicators:         [String]
    let summary:              String
    let exif:                 EXIFData?
}

enum ForensicsVerdict: String {
    case authentic    = "AUTÉNTICA"
    case suspicious   = "SOSPECHOSA"
    case manipulated  = "MANIPULADA"
    case aiGenerated  = "GENERADA POR IA"

    var label: String {
        switch self {
        case .authentic:   return "Imagen auténtica"
        case .suspicious:  return "Imagen sospechosa"
        case .manipulated: return "Imagen manipulada"
        case .aiGenerated: return "Generada por IA"
        }
    }
    var icon: String {
        switch self {
        case .authentic:   return "checkmark.seal.fill"
        case .suspicious:  return "exclamationmark.triangle.fill"
        case .manipulated: return "scissors"
        case .aiGenerated: return "cpu.fill"
        }
    }
    var color: String {  // nombre del color del sistema
        switch self {
        case .authentic:   return "green"
        case .suspicious:  return "orange"
        case .manipulated: return "red"
        case .aiGenerated: return "purple"
        }
    }
}

struct ForensicSignal: Identifiable {
    let id = UUID()
    let type:        String
    let description: String
    let severity:    SignalSeverity
}

enum SignalSeverity: String {
    case high   = "alta"
    case medium = "media"
    case low    = "baja"

    var label: String {
        switch self { case .high: return "Alta"; case .medium: return "Media"; case .low: return "Baja" }
    }
    var icon: String {
        switch self { case .high: return "exclamationmark.2"; case .medium: return "exclamationmark"; case .low: return "info.circle" }
    }
}

// MARK: - Datos EXIF

struct EXIFData {
    let make:        String?   // Fabricante de la cámara (Apple, Samsung…)
    let model:       String?   // Modelo del dispositivo
    let software:    String?   // Software que procesó la imagen
    let dateTime:    String?   // Fecha y hora original de captura
    let hasGPS:      Bool      // Si tiene coordenadas GPS
    let pixelWidth:  Int?
    let pixelHeight: Int?
    let colorModel:  String?

    var hasMetadata: Bool {
        make != nil || model != nil || software != nil || dateTime != nil
    }

    var formattedDate: String? {
        guard let dt = dateTime else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let date = f.date(from: dt) {
            let out = DateFormatter()
            out.locale = Locale(identifier: "es_MX")
            out.dateStyle = .medium
            out.timeStyle = .short
            return out.string(from: date)
        }
        return dt
    }

    var resolution: String? {
        guard let w = pixelWidth, let h = pixelHeight else { return nil }
        return "\(w) × \(h) px"
    }
}

// MARK: - Servicio forense

class ImageForensicsService {

    private let geminiKey = APIKeys.gemini
    private let baseURL   = "https://generativelanguage.googleapis.com/v1beta/models"

    // MARK: - Análisis completo

    func analyze(imageData: Data) async throws -> ForensicsResult {

        // Las dos fases corren en paralelo para ahorrar tiempo
        async let exifTask    = Task { extractEXIF(from: imageData) }
        async let geminiTask  = analyzeWithGemini(imageData: imageData)

        let exifData     = await exifTask.value
        let geminiResult = try await geminiTask

        return ForensicsResult(
            riskScore:           geminiResult.riskScore,
            verdict:             geminiResult.verdict,
            manipulationSignals: geminiResult.manipulationSignals,
            authenticSignals:    geminiResult.authenticSignals,
            aiLikelihood:        geminiResult.aiLikelihood,
            aiIndicators:        geminiResult.aiIndicators,
            summary:             geminiResult.summary,
            exif:                exifData
        )
    }

    // MARK: - Extracción de EXIF

    private func extractEXIF(from data: Data) -> EXIFData? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props  = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        let tiff   = props["{TIFF}"]   as? [String: Any]
        let exif   = props["{Exif}"]   as? [String: Any]
        let gps    = props["{GPS}"]    as? [String: Any]

        let make      = tiff?["Make"]     as? String
        let model     = tiff?["Model"]    as? String
        let software  = tiff?["Software"] as? String

        // Fecha preferida: la de captura original
        let dateTime = exif?["DateTimeOriginal"] as? String
                    ?? tiff?["DateTime"]         as? String

        let hasGPS    = gps != nil && !(gps?.isEmpty ?? true)
        let width     = props["PixelWidth"]  as? Int
        let height    = props["PixelHeight"] as? Int
        let colorModel = props["ColorModel"] as? String

        // Si no hay ningún dato útil devolvemos nil (puede ser screenshot sin EXIF)
        let hasData = make != nil || model != nil || software != nil || dateTime != nil
        guard hasData || width != nil else { return nil }

        return EXIFData(
            make:        make,
            model:       model,
            software:    software,
            dateTime:    dateTime,
            hasGPS:      hasGPS,
            pixelWidth:  width,
            pixelHeight: height,
            colorModel:  colorModel
        )
    }

    // MARK: - Análisis Gemini Vision

    private func analyzeWithGemini(imageData: Data) async throws -> GeminiForensicsResponse {

        let endpoint = "\(baseURL)/gemini-2.5-flash:generateContent?key=\(geminiKey)"
        guard let url = URL(string: endpoint) else {
            throw ForensicsError.invalidURL
        }

        let base64 = imageData.base64EncodedString()

        // Prompt forense especializado — pide JSON estructurado
        let prompt = """
        Eres un perito forense digital experto en autenticidad de imágenes.
        Analiza esta imagen y busca ESPECÍFICAMENTE las siguientes señales:

        ── MANIPULACIÓN DIGITAL ──
        • Inconsistencias de iluminación o sombras entre elementos
        • Bordes artificiales, halos o seamlines alrededor de objetos
        • Artefactos de compresión anómalos o localizados en zonas específicas
        • Diferencias de nitidez, resolución o ruido entre regiones de la imagen
        • Clonado de zonas (repetición de texturas o patrones idénticos)
        • Inconsistencias de perspectiva o escala

        ── GENERACIÓN POR IA ──
        • Manos con dedos malformados, extras o faltantes
        • Texto dentro de la imagen ilegible, deformado o sin sentido
        • Fondo con artefactos, patrones repetitivos o transiciones anómalas
        • Proporciones anatómicas incorrectas
        • Superficies con texturas artificialmente perfectas o simétricas
        • Ojos o rasgos faciales con inconsistencias sutiles

        ── SEÑALES AUTÉNTICAS ──
        • Ruido de cámara uniforme y natural en toda la imagen
        • Aberraciones ópticas típicas (vignetting, distorsión de lente)
        • Bokeh y desenfoque naturales en los bordes apropiados
        • Iluminación consistente con la escena

        IMPORTANTE: Si la imagen es un screenshot, infografía, gráfica o documento,
        indícalo en el veredicto como "AUTÉNTICA" pero señala que no es fotografía real.

        DEVUELVE ÚNICAMENTE JSON VÁLIDO, sin markdown:
        {
          "riskScore": 0,
          "verdict": "AUTÉNTICA|SOSPECHOSA|MANIPULADA|GENERADA POR IA",
          "manipulationSignals": [
            {"type": "nombre_corto", "description": "descripción específica", "severity": "alta|media|baja"}
          ],
          "authenticSignals": ["señal auténtica 1", "señal auténtica 2"],
          "aiLikelihood": "nula|baja|media|alta",
          "aiIndicators": ["indicador 1"],
          "summary": "Resumen profesional de 2-3 oraciones sobre el veredicto y las señales encontradas"
        }

        riskScore: 0-20 = auténtica, 21-50 = sospechosa, 51-80 = manipulada, 81-100 = casi certeza de manipulación/IA.
        """

        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                    ["text": prompt]
                ]
            ]],
            "generationConfig": ["temperature": 0.1]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody  = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 25

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let errText = String(data: data, encoding: .utf8) {
                print("❌ Gemini Forensics error: \(errText)")
            }
            throw ForensicsError.apiError
        }

        return try parseGeminiResponse(data: data)
    }

    // MARK: - Parseo de respuesta

    private func parseGeminiResponse(data: Data) throws -> GeminiForensicsResponse {
        guard let json     = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content  = candidates.first?["content"] as? [String: Any],
              let parts    = content["parts"] as? [[String: Any]],
              var text     = parts.first?["text"] as? String else {
            throw ForensicsError.parseError
        }

        // Limpiar markdown si Gemini lo agrega
        text = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```",     with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }

        guard let jsonData = text.data(using: .utf8),
              let parsed   = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ForensicsError.parseError
        }

        let riskScore = parsed["riskScore"] as? Int ?? 0
        let verdictStr = parsed["verdict"]  as? String ?? "SOSPECHOSA"
        let verdict: ForensicsVerdict = {
            switch verdictStr {
            case "AUTÉNTICA":        return .authentic
            case "MANIPULADA":       return .manipulated
            case "GENERADA POR IA":  return .aiGenerated
            default:                 return .suspicious
            }
        }()

        // Señales de manipulación
        let rawSignals = parsed["manipulationSignals"] as? [[String: Any]] ?? []
        let signals = rawSignals.compactMap { s -> ForensicSignal? in
            guard let desc = s["description"] as? String else { return nil }
            let type     = s["type"]     as? String ?? "general"
            let sevStr   = s["severity"] as? String ?? "media"
            let severity: SignalSeverity = sevStr == "alta" ? .high : sevStr == "media" ? .medium : .low
            return ForensicSignal(type: type, description: desc, severity: severity)
        }

        return GeminiForensicsResponse(
            riskScore:           riskScore,
            verdict:             verdict,
            manipulationSignals: signals,
            authenticSignals:    parsed["authenticSignals"] as? [String]  ?? [],
            aiLikelihood:        parsed["aiLikelihood"]     as? String ?? "nula",
            aiIndicators:        parsed["aiIndicators"]     as? [String]  ?? [],
            summary:             parsed["summary"]          as? String ?? ""
        )
    }
}

// MARK: - Tipos internos

private struct GeminiForensicsResponse {
    let riskScore:           Int
    let verdict:             ForensicsVerdict
    let manipulationSignals: [ForensicSignal]
    let authenticSignals:    [String]
    let aiLikelihood:        String
    let aiIndicators:        [String]
    let summary:             String
}

enum ForensicsError: LocalizedError {
    case invalidURL, apiError, parseError
    var errorDescription: String? {
        switch self {
        case .invalidURL:  return "URL de API inválida"
        case .apiError:    return "Error al conectar con el servicio de análisis"
        case .parseError:  return "Error procesando el resultado del análisis"
        }
    }
}
