import Foundation

// MARK: - Scope y Estado (tipos compartidos)

enum GeographicScope: String, CaseIterable, Identifiable {
    case internacional = "Internacional"
    case nacional      = "Nacional"
    case local         = "Local"
    var id:   String { rawValue }
    var icon: String {
        switch self {
        case .internacional: return "globe.americas.fill"
        case .nacional:      return "flag.fill"
        case .local:         return "location.fill"
        }
    }
}

enum MexicanState: String, CaseIterable, Identifiable {
    case aguascalientes    = "Aguascalientes"
    case bajaCalifornia    = "Baja California"
    case bajaCaliforniaSur = "Baja California Sur"
    case campeche          = "Campeche"
    case chiapas           = "Chiapas"
    case chihuahua         = "Chihuahua"
    case cdmx              = "Ciudad de México"
    case coahuila          = "Coahuila"
    case colima            = "Colima"
    case durango           = "Durango"
    case guanajuato        = "Guanajuato"
    case guerrero          = "Guerrero"
    case hidalgo           = "Hidalgo"
    case jalisco           = "Jalisco"
    case estadoDeMexico    = "Estado de México"
    case michoacan         = "Michoacán"
    case morelos           = "Morelos"
    case nayarit           = "Nayarit"
    case nuevoLeon         = "Nuevo León"
    case oaxaca            = "Oaxaca"
    case puebla            = "Puebla"
    case queretaro         = "Querétaro"
    case quintanaRoo       = "Quintana Roo"
    case sanLuisPotosi     = "San Luis Potosí"
    case sinaloa           = "Sinaloa"
    case sonora            = "Sonora"
    case tabasco           = "Tabasco"
    case tamaulipas        = "Tamaulipas"
    case tlaxcala          = "Tlaxcala"
    case veracruz          = "Veracruz"
    case yucatan           = "Yucatán"
    case zacatecas         = "Zacatecas"
    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .cdmx: return "🏙️"; case .jalisco: return "🌵"
        case .nuevoLeon: return "⛰️"; case .yucatan: return "🏛️"
        case .chihuahua: return "🐴"; case .veracruz: return "⚓️"
        case .oaxaca: return "🎨"; case .puebla: return "🌶️"
        case .sinaloa: return "🌊"; case .sonora: return "☀️"
        case .quintanaRoo: return "🏝️"; case .guanajuato: return "🏺"
        case .michoacan: return "🦋"; case .guerrero: return "🦅"
        case .tabasco: return "🐊"; case .campeche: return "🏰"
        default: return "📍"
        }
    }
}

// MARK: - Feed Definition

struct RSSFeedDefinition {
    let url: String; let sourceName: String
    let category: NewsCategory; let scope: GeographicScope
    let state: MexicanState?
    init(url: String, sourceName: String, category: NewsCategory = .general,
         scope: GeographicScope, state: MexicanState? = nil) {
        self.url = url; self.sourceName = sourceName
        self.category = category; self.scope = scope; self.state = state
    }
}

// MARK: - RSS Parser

private class RSSParser: NSObject, XMLParserDelegate {
    var articles: [NewsArticle] = []
    private var inItem = false, buf = "", el = ""
    private var t = "", d = "", l = "", dt = ""
    private var img: String?, src: String?
    let defSource: String; let cat: NewsCategory; let scope: GeographicScope

    init(_ source: String, _ category: NewsCategory, _ scope: GeographicScope) {
        defSource = source; cat = category; self.scope = scope
    }

    func parser(_ p: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName qn: String?, attributes a: [String:String] = [:]) {
        self.el = el; buf = ""
        if el == "item" || el == "entry" { inItem = true; t=""; d=""; l=""; dt=""; img=nil; src=nil }
        guard inItem else { return }
        if el == "enclosure", let tp = a["type"], tp.hasPrefix("image"), let u = a["url"] { img = img ?? u }
        if (el == "media:content" || el == "media:thumbnail"), let u = a["url"] { img = img ?? u }
        if el == "link", let h = a["href"] { l = l.isEmpty ? h : l }
    }

    func parser(_ p: XMLParser, foundCharacters s: String) { guard inItem else { return }; buf += s }
    func parser(_ p: XMLParser, foundCDATA data: Data) { guard inItem else { return }; buf += String(data: data, encoding: .utf8) ?? "" }

    func parser(_ p: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        guard inItem else { return }
        let v = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = v.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                     .replacingOccurrences(of: "&amp;", with: "&")
                     .replacingOccurrences(of: "&lt;", with: "<")
                     .replacingOccurrences(of: "&gt;", with: ">")
                     .replacingOccurrences(of: "&nbsp;", with: " ")
                     .trimmingCharacters(in: .whitespacesAndNewlines)
        switch el {
        case "title":   if t.isEmpty { t = clean }
        case "description", "summary": if d.isEmpty { d = String(clean.prefix(240)) }
        case "content:encoded": if d.isEmpty { d = String(clean.prefix(240)) }
        case "link":    if l.isEmpty && v.hasPrefix("http") { l = v }
        case "guid":    if l.isEmpty && v.hasPrefix("http") { l = v }
        case "source":  if src == nil && !clean.isEmpty { src = clean }
        case "pubDate","published","updated","dc:date": if dt.isEmpty { dt = v }
        case "item","entry":
            guard !t.isEmpty, l.hasPrefix("http") else { inItem = false; return }
            var art = NewsArticle(source: NewsSource(name: src ?? defSource), title: t,
                                  description: d.isEmpty ? nil : d, url: l,
                                  urlToImage: img, publishedAt: normalizeDate(dt))
            art.category = cat; art.scope = scope
            articles.append(art); inItem = false
        default: break
        }
        buf = ""
    }

    private func normalizeDate(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        for opts: ISO8601DateFormatter.Options in [[.withInternetDateTime],[.withInternetDateTime,.withFractionalSeconds]] {
            iso.formatOptions = opts; if let d = iso.date(from: raw) { return iso.string(from: d) }
        }
        let rfc = DateFormatter(); rfc.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, dd MMM yyyy HH:mm:ss Z","EEE, d MMM yyyy HH:mm:ss Z",
                    "dd MMM yyyy HH:mm:ss Z","EEE, dd MMM yyyy HH:mm:ss zzz"] {
            rfc.dateFormat = fmt; if let d = rfc.date(from: raw) { return ISO8601DateFormatter().string(from: d) }
        }
        return nil
    }
}

// MARK: - RSS Feed Service

class RSSFeedService {

    // ─────────────────────────────────────────────────────────────
    // FEEDS ESTÁTICOS VERIFICADOS — solo los más fiables
    // ─────────────────────────────────────────────────────────────

    static let allStatic: [RSSFeedDefinition] = internacional + nacional + localStatic

    static let internacional: [RSSFeedDefinition] = [
        .init(url: "https://feeds.bbci.co.uk/mundo/rss.xml",     sourceName: "BBC Mundo",           scope: .internacional),
        .init(url: "https://rss.dw.com/xml/rss-es-all",          sourceName: "DW Español",          scope: .internacional),
        .init(url: "https://www.france24.com/es/rss",             sourceName: "France 24",           scope: .internacional),
        .init(url: "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/portada",
                                                                   sourceName: "El País",             scope: .internacional),
        .init(url: "https://es.euronews.com/rss",                 sourceName: "Euronews ES",         scope: .internacional),
        .init(url: "https://www.infobae.com/feeds/rss/",          sourceName: "Infobae",             scope: .internacional),
        .init(url: "https://www.publico.es/rss",                  sourceName: "Público ES",          scope: .internacional),
        .init(url: "https://www.bbc.com/news/world/rss.xml",      sourceName: "BBC World",           scope: .internacional),
        .init(url: "https://feeds.feedburner.com/TechCrunch",     sourceName: "TechCrunch",          category: .tecnologia, scope: .internacional),
        .init(url: "https://www.theverge.com/rss/index.xml",      sourceName: "The Verge",           category: .tecnologia, scope: .internacional),
        .init(url: "https://www.marca.com/rss/portada.xml",       sourceName: "Marca",               category: .deportes,  scope: .internacional),
        .init(url: "https://as.com/rss/",                         sourceName: "AS Deportes",         category: .deportes,  scope: .internacional),
        .init(url: "https://www.scientificamerican.com/feed/rss/",sourceName: "Scientific American", category: .ciencia,   scope: .internacional),
        .init(url: "https://www.nationalgeographic.com.es/feed",  sourceName: "National Geographic", category: .ciencia,   scope: .internacional),
        .init(url: "https://www.muyinteresante.es/feed",          sourceName: "Muy Interesante",     category: .ciencia,   scope: .internacional),
        .init(url: "https://www.webconsultas.com/rss.xml",        sourceName: "WebConsultas",        category: .salud,     scope: .internacional),
        .init(url: "https://www.expansion.com/rss/portada.xml",   sourceName: "Expansión ES",        category: .negocios,  scope: .internacional),
    ]

    static let nacional: [RSSFeedDefinition] = [
        .init(url: "https://aristeguinoticias.com/feed/",         sourceName: "Aristegui Noticias",  scope: .nacional),
        .init(url: "https://www.animalpolitico.com/feed",         sourceName: "Animal Político",     scope: .nacional),
        .init(url: "https://www.proceso.com.mx/rss/",             sourceName: "Proceso",             scope: .nacional),
        .init(url: "https://www.jornada.com.mx/rss/ultimas.xml",  sourceName: "La Jornada",          scope: .nacional),
        .init(url: "https://www.milenio.com/rss",                 sourceName: "Milenio",             scope: .nacional),
        .init(url: "https://lasillarota.com/feed",                sourceName: "La Silla Rota",       scope: .nacional),
        .init(url: "https://www.eluniversal.com.mx/rss.xml",      sourceName: "El Universal",        scope: .nacional),
        .init(url: "https://www.excelsior.com.mx/rss",            sourceName: "Excélsior",           scope: .nacional),
        .init(url: "https://www.sdpnoticias.com/feed/",           sourceName: "SDP Noticias",        scope: .nacional),
        .init(url: "https://www.24horas.mx/feed/",                sourceName: "24 Horas MX",         scope: .nacional),
        .init(url: "https://www.elheraldo.mx/rss",                sourceName: "El Heraldo MX",       scope: .nacional),
        .init(url: "https://www.xataka.com.mx/feed",              sourceName: "Xataka México",       category: .tecnologia, scope: .nacional),
        .init(url: "https://hipertextual.com/feed",               sourceName: "Hipertextual",        category: .tecnologia, scope: .nacional),
        .init(url: "https://www.fayerwayer.com/feed/",            sourceName: "FayerWayer",          category: .tecnologia, scope: .nacional),
        .init(url: "https://www.eleconomista.com.mx/rss",         sourceName: "El Economista",       category: .negocios,  scope: .nacional),
        .init(url: "https://www.elfinanciero.com.mx/rss/",        sourceName: "El Financiero",       category: .negocios,  scope: .nacional),
        .init(url: "https://expansion.mx/rss",                    sourceName: "Expansión MX",        category: .negocios,  scope: .nacional),
        .init(url: "https://www.forbes.com.mx/feed/",             sourceName: "Forbes México",       category: .negocios,  scope: .nacional),
        .init(url: "https://www.record.com.mx/rss",               sourceName: "Récord",              category: .deportes,  scope: .nacional),
        .init(url: "https://www.mediotiempo.com/rss",             sourceName: "Mediotiempo",         category: .deportes,  scope: .nacional),
        .init(url: "https://www.esto.com.mx/rss",                 sourceName: "Esto",                category: .deportes,  scope: .nacional),
        .init(url: "https://www.cancha.mx/feed/",                 sourceName: "Cancha MX",           category: .deportes,  scope: .nacional),
        .init(url: "https://www.salud.com.mx/feed/",              sourceName: "Salud.com.mx",        category: .salud,     scope: .nacional),
        .init(url: "https://saludiario.com/feed/",                sourceName: "Saludiario",          category: .salud,     scope: .nacional),
        .init(url: "https://www.quien.com/feed/",                 sourceName: "¿Quién?",             category: .entretenimiento, scope: .nacional),
        .init(url: "https://www.tvnotas.com.mx/feed",             sourceName: "TV Notas",            category: .entretenimiento, scope: .nacional),
        .init(url: "https://www.milenio.com/rss/espectaculos",    sourceName: "Milenio Espect.",     category: .entretenimiento, scope: .nacional),
    ]

    static let localStatic: [RSSFeedDefinition] = [
        // Jalisco
        .init(url: "https://www.informador.mx/rss",               sourceName: "El Informador",       scope: .local, state: .jalisco),
        .init(url: "https://ntrgdl.com/feed/",                    sourceName: "NTR Guadalajara",     scope: .local, state: .jalisco),
        .init(url: "https://www.milenio.com/rss/jalisco",         sourceName: "Milenio Jalisco",     scope: .local, state: .jalisco),
        // CDMX
        .init(url: "https://lasillarota.com/feed",                sourceName: "Silla Rota CDMX",     scope: .local, state: .cdmx),
        .init(url: "https://www.chilango.com/feed/",              sourceName: "Chilango",            scope: .local, state: .cdmx),
        // Nuevo León
        .init(url: "https://www.milenio.com/rss/monterrey",       sourceName: "Milenio Monterrey",   scope: .local, state: .nuevoLeon),
        // Puebla
        .init(url: "https://e-consulta.com/feed/",                sourceName: "e-consulta Puebla",   scope: .local, state: .puebla),
        // Veracruz
        .init(url: "https://www.alcalorpolitico.com/feed",        sourceName: "Al Calor Político",   scope: .local, state: .veracruz),
        // Guanajuato
        .init(url: "https://www.am.com.mx/rss",                   sourceName: "AM León",             scope: .local, state: .guanajuato),
        // Chihuahua
        .init(url: "https://diario.mx/rss",                       sourceName: "El Diario",           scope: .local, state: .chihuahua),
        // Sinaloa
        .init(url: "https://www.noroeste.com.mx/rss",             sourceName: "Noroeste",            scope: .local, state: .sinaloa),
        // Sonora
        .init(url: "https://www.elimparcialsonora.com/feed/",     sourceName: "El Imparcial Sonora", scope: .local, state: .sonora),
        // Yucatán
        .init(url: "https://sipse.com/rss/",                      sourceName: "Sipse Yucatán",       scope: .local, state: .yucatan),
        // Oaxaca
        .init(url: "https://elimparcial.com/feed/",               sourceName: "El Imparcial Oaxaca", scope: .local, state: .oaxaca),
        // Coahuila
        .init(url: "https://www.vanguardia.com.mx/rss",           sourceName: "Vanguardia",          scope: .local, state: .coahuila),
        // Tamaulipas
        .init(url: "https://www.elmanana.com.mx/rss",             sourceName: "El Mañana",           scope: .local, state: .tamaulipas),
        // Quintana Roo
        .init(url: "https://www.novedadesqroo.com.mx/rss",        sourceName: "Novedades Q.Roo",     scope: .local, state: .quintanaRoo),
        // Michoacán
        .init(url: "https://www.lavozdemichoacan.com.mx/feed/",   sourceName: "Voz de Michoacán",    scope: .local, state: .michoacan),
        // Querétaro
        .init(url: "https://ntrnoticias.com/feed/",               sourceName: "NTR Querétaro",       scope: .local, state: .queretaro),
    ]

    // MARK: - Fetch

    func fetchFeed(_ feed: RSSFeedDefinition) async -> [NewsArticle] {
        guard let url = URL(string: feed.url) else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse,
                  (200...299).contains(http.statusCode), !data.isEmpty else { return [] }
            let parser = RSSParser(feed.sourceName, feed.category, feed.scope)
            let xml    = XMLParser(data: data)
            xml.delegate = parser
            xml.shouldProcessNamespaces = false
            xml.parse()
            let result = Array(parser.articles.prefix(12))
            if !result.isEmpty { print("📰 \(feed.sourceName): \(result.count)") }
            return result
        } catch { return [] }
    }

    func fetchAll(_ feeds: [RSSFeedDefinition]) async -> [NewsArticle] {
        await withTaskGroup(of: [NewsArticle].self) { group in
            for feed in feeds { group.addTask { await self.fetchFeed(feed) } }
            var all: [NewsArticle] = []
            for await arts in group { all.append(contentsOf: arts) }
            return all
        }
    }

    func fetchScope(_ scope: GeographicScope, state: MexicanState? = nil) async -> [NewsArticle] {
        switch scope {
        case .internacional: return await fetchAll(Self.internacional)
        case .nacional:      return await fetchAll(Self.nacional)
        case .local:
            guard let s = state else { return [] }
            return await fetchAll(Self.localStatic.filter { $0.state == s })
        }
    }
}
