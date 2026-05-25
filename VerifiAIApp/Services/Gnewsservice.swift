import Foundation

// MARK: - GNews Response Models

struct GNewsResponse: Codable {
    let totalArticles: Int
    let articles: [GNewsArticle]
}

struct GNewsArticle: Codable {
    let title:       String
    let description: String?
    let content:     String?
    let url:         String
    let image:       String?
    let publishedAt: String
    let source:      GNewsSource
}

struct GNewsSource: Codable {
    let name: String
    let url:  String
}

// MARK: - GNews Service

/// GNews API — filtro geográfico real por país, idioma y búsqueda por palabras clave.
/// Es la fuente más precisa para noticias locales de México.
///
/// Plan Free (sin tarjeta de crédito):
///   • 100 requests/día
///   • 10 artículos por request
///   • Búsqueda en 60+ idiomas y 40+ países
///
/// Documentación: https://gnews.io/docs/v4
class GNewsService {

    private let apiKey  = APIKeys.gNews
    private let baseURL = "https://gnews.io/api/v4"

    // GNews topic → NewsCategory
    // Usamos los topics nativos de GNews para máxima relevancia
    private let topicMap: [(topic: String, category: NewsCategory)] = [
        ("nation",         .general),
        ("business",       .negocios),
        ("technology",     .tecnologia),
        ("sports",         .deportes),
        ("health",         .salud),
        ("science",        .ciencia),
        ("entertainment",  .entretenimiento),
    ]

    private var isConfigured: Bool {
        !apiKey.isEmpty && apiKey != "AQUI_VA_TU_GNEWS_KEY"
    }

    // MARK: - Top Headlines por tema (Nacional / Internacional)

    /// Descarga top headlines nacionales o internacionales por categoría
    func fetchTopHeadlines(scope: GeographicScope) async -> [NewsArticle] {
        guard isConfigured else {
            print("⚠️ GNews: API key no configurada")
            return []
        }

        return await withTaskGroup(of: [NewsArticle].self) { group in
            for (topic, category) in topicMap {
                group.addTask {
                    await self.fetchTopic(topic: topic, scope: scope, category: category)
                }
            }
            // También traemos general/nation
            group.addTask {
                await self.fetchTopic(topic: scope == .internacional ? "world" : "nation",
                                      scope: scope, category: .general)
            }
            var all: [NewsArticle] = []
            for await arts in group { all.append(contentsOf: arts) }
            return all
        }
    }

    private func fetchTopic(topic: String, scope: GeographicScope,
                             category: NewsCategory) async -> [NewsArticle] {
        var components = URLComponents(string: "\(baseURL)/top-headlines")!
        components.queryItems = [
            URLQueryItem(name: "token",    value: apiKey),
            URLQueryItem(name: "lang",     value: "es"),
            URLQueryItem(name: "country",  value: scope == .internacional ? "" : "mx"),
            URLQueryItem(name: "topic",    value: topic),
            URLQueryItem(name: "max",      value: "10"),
            URLQueryItem(name: "nullable", value: "image,description"),
        ].filter { !($0.value?.isEmpty ?? true) }

        guard let url = components.url else { return [] }

        return await fetch(url: url, scope: scope, category: category)
    }

    // MARK: - Búsqueda local por estado + municipio

    /// Descarga noticias locales para un estado y ciudad específicos.
    /// Esta es la función más importante para precisión geográfica.
    func fetchLocal(state: MexicanState, city: String?) async -> [NewsArticle] {
        guard isConfigured else { return [] }

        var allArticles: [NewsArticle] = []

        // ── Estrategia multi-query para máxima cobertura ──────
        //
        // GNews busca en título Y descripción de artículos.
        // Construimos queries específicos de más a menos granular:
        //
        // 1. Municipio + Estado (más preciso)
        // 2. Solo municipio
        // 3. Estado solo (mayor volumen)
        // 4. Por categoría + Estado

        var queries: [(query: String, category: NewsCategory)] = []

        if let city = city {
            queries.append(("\"\(city)\" \(state.rawValue)", .general))
            queries.append(("\(city) noticias", .general))
        }

        queries.append(("\(state.rawValue) noticias hoy", .general))
        queries.append(("\(state.rawValue) política gobierno", .general))
        queries.append(("\(state.rawValue) seguridad", .general))
        queries.append(("\(state.rawValue) economía negocios", .negocios))
        queries.append(("\(state.rawValue) deportes", .deportes))
        queries.append(("\(state.rawValue) salud", .salud))

        let results = await withTaskGroup(of: [NewsArticle].self) { group in
            for (query, cat) in queries {
                group.addTask {
                    await self.fetchSearch(query: query, scope: .local, category: cat)
                }
            }
            var all: [NewsArticle] = []
            for await arts in group { all.append(contentsOf: arts) }
            return all
        }

        allArticles.append(contentsOf: results)
        return allArticles
    }

    // MARK: - Búsqueda genérica

    private func fetchSearch(query: String, scope: GeographicScope,
                              category: NewsCategory) async -> [NewsArticle] {
        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "token",   value: apiKey),
            URLQueryItem(name: "q",       value: query),
            URLQueryItem(name: "lang",    value: "es"),
            URLQueryItem(name: "country", value: "mx"),
            URLQueryItem(name: "max",     value: "10"),
            URLQueryItem(name: "sortby",  value: "publishedAt"),
            URLQueryItem(name: "nullable",value: "image,description"),
        ]
        guard let url = components.url else { return [] }
        return await fetch(url: url, scope: scope, category: category)
    }

    // MARK: - Fetch base

    private func fetch(url: URL, scope: GeographicScope,
                        category: NewsCategory) async -> [NewsArticle] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else { return [] }

            if http.statusCode == 403 {
                print("❌ GNews: API key inválida o límite diario alcanzado")
                return []
            }
            guard http.statusCode == 200 else {
                print("⚠️ GNews HTTP \(http.statusCode) para \(url)")
                return []
            }

            let decoded = try JSONDecoder().decode(GNewsResponse.self, from: data)
            print("✅ GNews [\(category.label)]: \(decoded.articles.count) artículos")

            return decoded.articles.map { gnArticle in
                var article = NewsArticle(
                    source:      NewsSource(name: gnArticle.source.name),
                    title:       gnArticle.title,
                    description: gnArticle.description,
                    url:         gnArticle.url,
                    urlToImage:  gnArticle.image,
                    publishedAt: gnArticle.publishedAt
                )
                article.category = category
                article.scope    = scope
                return article
            }

        } catch {
            print("❌ GNews error: \(error.localizedDescription)")
            return []
        }
    }
}
