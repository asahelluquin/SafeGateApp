import Foundation

class NewsAPIVerificationService {

    // ✅ La key viene de APIKeys.swift — edítala allá, no aquí
    private let apiKey = APIKeys.newsAPI
    private let baseURL = "https://newsapi.org/v2/everything"

    func searchRelatedArticles(query: String) async -> NewsVerificationContext {

        let cleanQuery = query
            .components(separatedBy: .whitespacesAndNewlines)
            .prefix(8)
            .joined(separator: " ")

        guard !cleanQuery.isEmpty,
              var components = URLComponents(string: baseURL) else {
            return .empty
        }

        components.queryItems = [
            URLQueryItem(name: "q",        value: cleanQuery),
            URLQueryItem(name: "language", value: "es"),
            URLQueryItem(name: "sortBy",   value: "relevancy"),
            URLQueryItem(name: "pageSize", value: "5"),
            URLQueryItem(name: "apiKey",   value: apiKey)
        ]

        guard let url = components.url else { return .empty }

        do {
            print("🔍 NewsAPI buscando: \"\(cleanQuery)\"")
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("⚠️ NewsAPI respondió con error.")
                return .empty
            }

            let decoded = try JSONDecoder().decode(NewsAPIResponse.self, from: data)
            let validArticles = decoded.articles.filter {
                $0.title != nil && $0.title != "[Removed]" && $0.source?.name != nil
            }

            guard !validArticles.isEmpty else {
                print("ℹ️ NewsAPI no encontró artículos relevantes.")
                return .empty
            }

            print("✅ NewsAPI encontró \(validArticles.count) artículos.")
            return NewsVerificationContext(articles: validArticles)

        } catch {
            print("❌ Error en NewsAPI: \(error.localizedDescription)")
            return .empty
        }
    }
}

// MARK: - Modelos de datos

struct NewsAPIResponse: Codable {
    let status: String
    let totalResults: Int?
    let articles: [NewsAPIArticle]
}

struct NewsAPIArticle: Codable {
    let source: NewsAPISource?
    let title: String?
    let description: String?
    let url: String?
    let publishedAt: String?
}

struct NewsAPISource: Codable {
    let name: String?
}

// MARK: - Contexto de verificación

struct NewsVerificationContext {
    let articles: [NewsAPIArticle]

    static let empty = NewsVerificationContext(articles: [])

    var isEmpty: Bool { articles.isEmpty }

    var formattedForPrompt: String {
        guard !isEmpty else {
            return "NewsAPI no encontró cobertura periodística de esta noticia."
        }
        var lines = ["NewsAPI encontró \(articles.count) artículo(s) relacionado(s):"]
        for (i, article) in articles.enumerated() {
            let source      = article.source?.name ?? "Fuente desconocida"
            let title       = article.title ?? "Sin título"
            let description = article.description ?? "Sin descripción disponible."
            let date        = formatDate(article.publishedAt)
            lines.append("""
            [\(i + 1)] Fuente: \(source) | Fecha: \(date)
                Titular: \(title)
                Descripción: \(description)
            """)
        }
        return lines.joined(separator: "\n")
    }

    var sourceNames: [String] {
        articles.compactMap { $0.source?.name }.filter { !$0.isEmpty }
    }

    private func formatDate(_ isoString: String?) -> String {
        guard let iso = isoString else { return "Fecha desconocida" }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.locale = Locale(identifier: "es_MX")
            display.dateStyle = .medium
            return display.string(from: date)
        }
        return iso
    }
}
