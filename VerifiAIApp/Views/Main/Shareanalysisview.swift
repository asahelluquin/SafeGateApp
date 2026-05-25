import SwiftUI

// MARK: - Share Analysis View
// Vista que aparece cuando el usuario comparte algo con SafeGate.
// Hace un análisis rápido con Gemini REST (sin SDK, sin dependencias extra).
//
// ⚠️ PON AQUÍ TU GEMINI KEY — es el mismo valor que tienes en APIKeys.swift
private let geminiKey = "AIzaSyCLUVm8qCbqUvX38NoPjublTTxUS49qgDM"

struct ShareAnalysisView: View {

    let sharedContent: String
    let onDismiss:     () -> Void

    @State private var phase:   AnalysisPhase = .loading
    @State private var result:  QuickResult?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Handle indicator
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 16)

            // Header
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2).foregroundColor(Color(red: 15/255, green: 52/255, blue: 112/255))
                Text("SafeGate")
                    .font(.headline).foregroundColor(Color(red: 15/255, green: 52/255, blue: 112/255))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            Divider()

            // Content
            Group {
                switch phase {
                case .loading:
                    loadingView
                case .done:
                    if let r = result { resultView(r) } else { errorView }
                case .error:
                    errorView
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer(minLength: 20)

            // Abrir en app completa
            if phase == .done, let r = result {
                openInAppButton(r)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
        }
        .background(Color(UIColor.systemBackground))
        .task { await analyze() }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
                .tint(Color(red: 15/255, green: 52/255, blue: 112/255))
            Text("Analizando contenido…")
                .font(.subheadline).foregroundColor(.secondary)
            if sharedContent.lowercased().hasPrefix("http") {
                Text(sharedContent)
                    .font(.caption2).foregroundColor(.secondary.opacity(0.6))
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Result

    private func resultView(_ r: QuickResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {

            // Score principal
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(r.scoreColor.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(r.truthScore) / 100)
                        .stroke(r.scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(r.truthScore)%")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(r.scoreColor)
                        Text("veracidad")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 6) {
                    Text(r.veredicto)
                        .font(.headline)
                        .foregroundColor(r.scoreColor)
                    Text(r.headline)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                }
            }

            // Resumen
            Text(r.summary)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Error

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36)).foregroundColor(.orange)
            Text("No se pudo completar el análisis")
                .font(.subheadline).foregroundColor(.primary)
            Text("Verifica tu conexión e intenta de nuevo desde la app.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Abrir en app

    private func openInAppButton(_ r: QuickResult) -> some View {
        Button {
            // Deep link a la app principal
            let encoded = sharedContent.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "safegate://verify?content=\(encoded)") {
                _ = url  // La app maneja el deep link en App.swift
            }
            onDismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.app")
                Text("Ver análisis completo en SafeGate")
                    .font(.subheadline.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(red: 15/255, green: 52/255, blue: 112/255))
            .foregroundColor(.white)
            .cornerRadius(14)
        }
    }

    // MARK: - Análisis con Gemini REST

    private func analyze() async {
        guard !sharedContent.isEmpty, !geminiKey.isEmpty,
              geminiKey != "AQUI_VA_TU_GEMINI_KEY" else {
            phase = .error; return
        }

        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(geminiKey)"
        guard let url = URL(string: endpoint) else { phase = .error; return }

        let prompt = """
        Eres un verificador de noticias profesional. Analiza el siguiente contenido:

        \(sharedContent)

        Responde SOLO con un JSON válido, sin markdown:
        {
          "headline": "Titular neutral corto (máx 12 palabras)",
          "truthScore": 0,
          "summary": "Una sola oración directa sobre si es verdad o no (máx 25 palabras)"
        }

        truthScore: 0-39 = falso o sin evidencia, 40-69 = incierto, 70-100 = verificado.
        """

        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "tools": [["google_search": [:]]],
            "generationConfig": ["temperature": 0.1]
        ]

        do {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 20

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                phase = .error; return
            }

            if let json      = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let content   = candidates.first?["content"] as? [String: Any],
               let parts     = content["parts"] as? [[String: Any]],
               var text      = parts.first?["text"] as? String {

                text = text
                    .replacingOccurrences(of: "```json", with: "")
                    .replacingOccurrences(of: "```",     with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
                    text = String(text[start...end])
                }

                if let resultData = text.data(using: .utf8),
                   let parsed = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
                    let score   = parsed["truthScore"] as? Int    ?? 0
                    let headline = parsed["headline"]  as? String ?? "Análisis completado"
                    let summary  = parsed["summary"]   as? String ?? ""
                    result = QuickResult(truthScore: score, headline: headline, summary: summary)
                    phase  = .done
                    return
                }
            }
            phase = .error
        } catch {
            phase = .error
        }
    }
}

// MARK: - Modelos

enum AnalysisPhase: Equatable { case loading, done, error }

struct QuickResult {
    let truthScore: Int
    let headline:   String
    let summary:    String

    var scoreColor: Color {
        truthScore >= 70 ? .green : truthScore >= 40 ? .orange : .red
    }
    var veredicto: String {
        truthScore >= 70 ? "Verificado" : truthScore >= 40 ? "Incierto" : "Poco confiable"
    }
}
