import SwiftUI
import SwiftData
import Combine 

// MARK: - Colores

extension Color {
    static let arbiterNavy = Color(red: 15/255, green: 52/255, blue: 112/255)
}

// MARK: - Modelos

struct NewsResponse: Codable { let articles: [NewsArticle] }

struct NewsArticle: Codable, Identifiable {
    var id: String { url ?? UUID().uuidString }
    let source: NewsSource?; let title: String?; let description: String?
    let url: String?; let urlToImage: String?; let publishedAt: String?
    var category: NewsCategory    = .general
    var scope:    GeographicScope = .nacional
    enum CodingKeys: String, CodingKey {
        case source, title, description, url, urlToImage, publishedAt
    }
}

struct NewsSource: Codable { let name: String? }

// MARK: - Categorías

enum NewsCategory: String, CaseIterable, Identifiable {
    case todas="todas", general="general", tecnologia="technology"
    case negocios="business", deportes="sports", salud="health"
    case ciencia="science", entretenimiento="entertainment"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .todas: return "Todas"; case .general: return "General"
        case .tecnologia: return "Tecnología"; case .negocios: return "Negocios"
        case .deportes: return "Deportes"; case .salud: return "Salud"
        case .ciencia: return "Ciencia"; case .entretenimiento: return "Entretenimiento"
        }
    }
    var icon: String {
        switch self {
        case .todas: return "square.grid.2x2"; case .general: return "newspaper"
        case .tecnologia: return "cpu"; case .negocios: return "chart.line.uptrend.xyaxis"
        case .deportes: return "figure.run"; case .salud: return "heart.text.square"
        case .ciencia: return "atom"; case .entretenimiento: return "film"
        }
    }
    var color: Color {
        switch self {
        case .todas, .general:  return .arbiterNavy
        case .tecnologia:       return Color(red: 0.13, green: 0.55, blue: 0.96)
        case .negocios:         return Color(red: 0.10, green: 0.60, blue: 0.40)
        case .deportes:         return Color(red: 0.92, green: 0.30, blue: 0.18)
        case .salud:            return Color(red: 0.82, green: 0.20, blue: 0.52)
        case .ciencia:          return Color(red: 0.42, green: 0.25, blue: 0.85)
        case .entretenimiento:  return Color(red: 0.93, green: 0.52, blue: 0.08)
        }
    }
}

// MARK: - Feed Manager

@MainActor
class TrendingFeedManager: ObservableObject {
    @Published var allArticles:      [NewsArticle] = []
    @Published var isFetching        = true
    @Published var selectedScope:    GeographicScope = .nacional
    @Published var selectedCategory: NewsCategory    = .todas

    @AppStorage("selectedStateRaw") var selectedStateRaw: String = ""
    var manualState: MexicanState? {
        get { MexicanState(rawValue: selectedStateRaw) }
        set { selectedStateRaw = newValue?.rawValue ?? "" }
    }

    private let rss     = RSSFeedService()
    private let gnews   = GNewsService()
    private let newsAPI = APIKeys.newsAPI

    var filteredArticles: [NewsArticle] {
        allArticles.filter { a in
            guard let t = a.title, !t.isEmpty, t != "[Removed]" else { return false }
            return a.scope == selectedScope
                && (selectedCategory == .todas || a.category == selectedCategory)
        }
    }

    // MARK: - Carga principal

    func load(scope: GeographicScope, lm: LocationManager) async {
        isFetching = true
        let state  = lm.detectedState ?? manualState
        let city   = lm.searchCity

        switch scope {
        case .internacional:
            async let rssTask   = rss.fetchScope(.internacional)
            async let gnewsTask = gnews.fetchTopHeadlines(scope: .internacional)
            async let apiTask   = fetchNewsAPI(scope: .internacional)
            let (r, g, a) = await (rssTask, gnewsTask, apiTask)
            merge(r + g + a, scope: .internacional)

        case .nacional:
            async let rssTask   = rss.fetchScope(.nacional)
            async let gnewsTask = gnews.fetchTopHeadlines(scope: .nacional)
            async let apiTask   = fetchNewsAPI(scope: .nacional)
            let (r, g, a) = await (rssTask, gnewsTask, apiTask)
            merge(r + g + a, scope: .nacional)

        case .local:
            guard let state = state else { isFetching = false; return }
            async let gnewsLocal = gnews.fetchLocal(state: state, city: city)
            async let rssLocal   = rss.fetchScope(.local, state: state)
            async let apiLocal   = fetchNewsAPI(scope: .local, state: state, city: city)
            let (g, r, a) = await (gnewsLocal, rssLocal, apiLocal)
            merge(g + r + a, scope: .local)
        }

        isFetching = false
    }

    // MARK: - Merge con deduplicación

    private func merge(_ new: [NewsArticle], scope: GeographicScope) {
        var base = allArticles.filter { $0.scope != scope }
        var seen = Set(base.compactMap { $0.url })
        let unique = new.filter { a in
            guard let u = a.url, !seen.contains(u) else { return false }
            seen.insert(u); return true
        }
        base.append(contentsOf: unique)
        base.sort { iso($0.publishedAt) > iso($1.publishedAt) }
        allArticles = base
    }

    // MARK: - NewsAPI complementario

    private func fetchNewsAPI(scope: GeographicScope,
                               state: MexicanState? = nil,
                               city: String? = nil) async -> [NewsArticle] {
        guard !newsAPI.isEmpty, newsAPI != "AQUI_VA_TU_NEWSAPI_KEY" else { return [] }
        return await withTaskGroup(of: [NewsArticle].self) { group in
            for cat in NewsCategory.allCases where cat != .todas {
                group.addTask { await self.newsAPIQuery(cat, scope: scope, state: state, city: city) }
            }
            var all: [NewsArticle] = []
            for await arts in group { all.append(contentsOf: arts) }
            return all
        }
    }

    private func newsAPIQuery(_ cat: NewsCategory, scope: GeographicScope,
                               state: MexicanState?, city: String?) async -> [NewsArticle] {
        var q: String
        switch scope {
        case .internacional: q = cat.label + " mundo"
        case .nacional:      q = cat.label + " México"
        case .local:
            q = cat.label
            if let c = city  { q += " \(c)" }
            if let s = state { q += " \(s.rawValue)" }
        }
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://newsapi.org/v2/everything?q=\(enc)&language=es&sortBy=publishedAt&pageSize=10&apiKey=\(newsAPI)") else { return [] }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let h = resp as? HTTPURLResponse, h.statusCode == 200 else { return [] }
            return try JSONDecoder().decode(NewsResponse.self, from: data).articles.compactMap { a in
                guard let t = a.title, t != "[Removed]" else { return nil }
                var art = a; art.category = cat; art.scope = scope; return art
            }
        } catch { return [] }
    }

    private func iso(_ s: String?) -> Date {
        guard let s else { return .distantPast }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.date(from: s) ?? .distantPast
    }
}

// MARK: - Vista Principal

struct TrendingView: View {
    @StateObject private var fm  = TrendingFeedManager()
    @StateObject private var lm  = LocationManager()
    @StateObject private var vm  = AnalyzeViewModel()
    @Environment(\.modelContext) private var modelContext
    @State private var showPicker = false

    var activeState: MexicanState? { lm.detectedState ?? fm.manualState }
    var activeCity:  String?       { lm.searchCity }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    ScopeBar(selected: $fm.selectedScope, lm: lm, activeState: activeState)
                        .onChange(of: fm.selectedScope) { _, scope in
                            if scope == .local && activeState == nil { lm.requestDetection() }
                            Task { await fm.load(scope: scope, lm: lm) }
                        }

                    if fm.selectedScope == .local {
                        LocationBanner(lm: lm, state: activeState, city: activeCity,
                                       onDetect: { lm.requestDetection() },
                                       onManual: { showPicker = true },
                                       onClear:  { lm.clearLocation(); fm.selectedStateRaw = "" })
                    }

                    CategoryChips(selected: $fm.selectedCategory).padding(.vertical, 8)
                    Divider().opacity(0.25)


                    contentView
                }
                if vm.isLoading { AnalysisOverlay() }
            }
            .navigationTitle("Tendencias")
            .toolbar { toolbarItems }
            .task { await fm.load(scope: .nacional, lm: lm) }
            .onChange(of: lm.detectedState) { _, _ in
                if fm.selectedScope == .local {
                    Task { await fm.load(scope: .local, lm: lm) }
                }
            }
            .sheet(isPresented: $showPicker) {
                StatePicker(selected: $fm.selectedStateRaw) {
                    showPicker = false
                    Task { await fm.load(scope: .local, lm: lm) }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { vm.result != nil }, set: { if !$0 { vm.result = nil } }
            )) {
                if let r = vm.result { ResultView(result: r) }
            }
        }
    }

    @ViewBuilder
    var contentView: some View {
        if fm.isFetching {
            Spacer()
            VStack(spacing: 12) {
                ProgressView().tint(.arbiterNavy).scaleEffect(1.2)
                Text(fm.selectedScope == .local && activeCity != nil
                     ? "Buscando noticias de \(activeCity!)…"
                     : "Cargando noticias…")
                    .font(.subheadline).foregroundColor(.secondary)

            }
            Spacer()
        } else if fm.selectedScope == .local && activeState == nil {
            NoLocationView(onDetect: { lm.requestDetection() }, onManual: { showPicker = true })
        } else if fm.filteredArticles.isEmpty {
            Spacer()
            ContentUnavailableView("Sin noticias",
                systemImage: fm.selectedScope.icon,
                description: Text("Desliza hacia abajo para actualizar o cambia el filtro."))
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    HStack {
                        let loc = activeCity.map { "\($0)\(activeState.map { ", \($0.rawValue)" } ?? "")" }
                                  ?? activeState?.rawValue ?? ""
                        Text("\(fm.filteredArticles.count) noticias\(loc.isEmpty ? "" : " · \(loc)")")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20).padding(.top, 12)

                    ForEach(fm.filteredArticles) { article in
                        ArticleCard(article: article) {
                            vm.performAnalysis(text: article.url ?? article.title ?? "",
                                               modelContext: modelContext)
                        }
                    }
                    Spacer().frame(height: 20)
                }
            }
            .refreshable { await fm.load(scope: fm.selectedScope, lm: lm) }
        }
    }

    @ToolbarContentBuilder
    var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                if fm.selectedScope == .local {
                    Button { showPicker = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "map").font(.system(size: 11, weight: .bold))
                            Text(activeState?.rawValue ?? "Estado")
                                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.arbiterNavy.opacity(0.09))
                        .foregroundColor(.arbiterNavy).clipShape(Capsule())
                    }
                }
                Button { Task { await fm.load(scope: fm.selectedScope, lm: lm) } } label: {
                    Image(systemName: "arrow.clockwise").fontWeight(.semibold).foregroundColor(.arbiterNavy)
                }.disabled(fm.isFetching)
            }
        }
    }
}

// MARK: - Subvistas

struct ScopeBar: View {
    @Binding var selected: GeographicScope
    let lm: LocationManager; let activeState: MexicanState?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GeographicScope.allCases) { scope in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selected = scope }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 5) {
                            if scope == .local && lm.isLocating {
                                ProgressView().scaleEffect(0.65).tint(.arbiterNavy)
                            } else {
                                Image(systemName: scope.icon).font(.system(size: 12, weight: .bold))
                            }
                            Text(scope == .local
                                 ? (lm.searchCity ?? activeState?.rawValue ?? "Local")
                                 : scope.rawValue)
                            .font(.system(size: 13, weight: .bold)).lineLimit(1)
                        }
                        .foregroundColor(selected == scope ? .arbiterNavy : .secondary)
                        Rectangle().fill(selected == scope ? Color.arbiterNavy : Color.clear)
                            .frame(height: 2).cornerRadius(1)
                    }
                }.frame(maxWidth: .infinity).buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }
}

struct LocationBanner: View {
    let lm: LocationManager; let state: MexicanState?; let city: String?
    let onDetect: () -> Void; let onManual: () -> Void; let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if lm.isLocating {
                ProgressView().tint(.arbiterNavy)
                Text("Detectando ubicación…").font(.caption).foregroundColor(.secondary)
                Spacer()
            } else if let err = lm.locationError {
                Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                Text(err).font(.caption2).foregroundColor(.secondary).lineLimit(2)
                Spacer()
                Button("Manual", action: onManual).font(.caption.bold()).foregroundColor(.arbiterNavy)
            } else if let state = state {
                Image(systemName: "location.fill").font(.system(size: 11)).foregroundColor(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text(city.map { "\($0), \(state.rawValue)" } ?? state.rawValue)
                        .font(.caption.bold()).foregroundColor(.arbiterNavy)
                    Text("Noticias actualizadas en tiempo real").font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary.opacity(0.4))
                }
            } else {
                Image(systemName: "location.slash").foregroundColor(.secondary)
                Text("Sin ubicación").font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("GPS", action: onDetect).font(.caption.bold()).foregroundColor(.arbiterNavy)
                Button("Manual", action: onManual).font(.caption.bold()).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
    }
}

struct CategoryChips: View {
    @Binding var selected: NewsCategory
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewsCategory.allCases) { cat in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selected = cat }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cat.icon).font(.system(size: 11, weight: .bold))
                            Text(cat.label).font(.system(size: 13, weight: selected == cat ? .bold : .medium))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(selected == cat ? cat.color : Color(UIColor.secondarySystemGroupedBackground))
                        .foregroundColor(selected == cat ? .white : .secondary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(selected == cat ? Color.clear : Color.gray.opacity(0.2), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16)
        }
    }
}

struct ArticleCard: View {
    let article: NewsArticle; let onVerify: () -> Void
    private var timeAgo: String {
        guard let iso = article.publishedAt else { return "" }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        guard let d = f.date(from: iso) else { return "" }
        let diff = Date().timeIntervalSince(d)
        if diff < 3600  { return "Hace \(max(1, Int(diff/60))) min" }
        if diff < 86400 { return "Hace \(Int(diff/3600)) h" }
        return "Hace \(Int(diff/86400)) d"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: article.category.icon).font(.system(size: 9, weight: .black))
                    Text(article.category.label.uppercased()).font(.system(size: 9, weight: .black))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(article.category.color.opacity(0.12))
                .foregroundColor(article.category.color).clipShape(Capsule())
                Text(article.source?.name ?? "Fuente").font(.system(size: 11, weight: .bold))
                    .foregroundColor(.arbiterNavy).lineLimit(1)
                Spacer()
                if !timeAgo.isEmpty { Text(timeAgo).font(.system(size: 11)).foregroundColor(.secondary) }
            }.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            if let img = article.urlToImage, let url = URL(string: img) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let i): i.resizable().aspectRatio(contentMode: .fill).frame(height: 175).clipped()
                    case .empty: Rectangle().fill(Color.gray.opacity(0.07)).frame(height: 175)
                            .overlay(ProgressView().tint(.secondary))
                    default: EmptyView()
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(article.title ?? "").font(.system(size: 15, weight: .bold))
                    .foregroundColor(.arbiterNavy).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if let d = article.description, !d.isEmpty {
                    Text(d).font(.system(size: 13)).foregroundColor(.secondary).lineLimit(2)
                }
                HStack {
                    if let us = article.url, let url = URL(string: us) {
                        Link(destination: url) {
                            HStack(spacing: 3) {
                                Text("Leer nota")
                                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                            }.font(.caption.weight(.medium)).foregroundColor(.arbiterNavy.opacity(0.55))
                        }
                    }
                    Spacer()
                    Button(action: onVerify) {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles").font(.system(size: 11, weight: .bold))
                            Text("Verificar").font(.system(size: 13, weight: .bold))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color.arbiterNavy).foregroundColor(.white).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(14)
        }
        .background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
    }
}

struct NoLocationView: View {
    let onDetect: () -> Void; let onManual: () -> Void
    var body: some View {
        Spacer()
        VStack(spacing: 20) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 52)).foregroundColor(.arbiterNavy.opacity(0.3))
            Text("Noticias de tu zona").font(.title2.bold()).foregroundColor(.arbiterNavy)
            Text("Activa tu ubicación para ver noticias verificadas de tu municipio y estado.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 28)
            VStack(spacing: 12) {
                Button(action: onDetect) {
                    Label("Usar mi ubicación GPS", systemImage: "location.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.arbiterNavy).foregroundColor(.white).cornerRadius(14)
                }
                Button(action: onManual) {
                    Label("Seleccionar estado", systemImage: "map")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.arbiterNavy.opacity(0.08)).foregroundColor(.arbiterNavy).cornerRadius(14)
                }
            }.padding(.horizontal, 28)
        }
        Spacer()
    }
}

struct StatePicker: View {
    @Binding var selected: String; let onDone: () -> Void
    @State private var search = ""
    var filtered: [MexicanState] {
        search.isEmpty ? MexicanState.allCases : MexicanState.allCases.filter { $0.rawValue.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            List(filtered) { state in
                Button { selected = state.rawValue; onDone() } label: {
                    HStack(spacing: 12) {
                        Text(state.emoji).font(.title2)
                        Text(state.rawValue).font(.body).foregroundColor(.primary)
                        Spacer()
                        if selected == state.rawValue {
                            Image(systemName: "checkmark").fontWeight(.bold).foregroundColor(.arbiterNavy)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Buscar estado…")
            .navigationTitle("Selecciona tu estado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar", action: onDone).foregroundColor(.arbiterNavy)
                }
            }
        }
    }
}

struct AnalysisOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(.arbiterNavy).scaleEffect(1.3)
                Text("Analizando noticia…").font(.subheadline.bold()).foregroundColor(.arbiterNavy)
                Text("Consultando fuentes en tiempo real").font(.caption).foregroundColor(.secondary)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white)
                .shadow(color: .black.opacity(0.10), radius: 20))
        }
    }
}
