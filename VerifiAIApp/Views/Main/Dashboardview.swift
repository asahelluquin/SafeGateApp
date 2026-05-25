import SwiftUI
import Charts
import SwiftData

// MARK: - Período de filtro

enum DashboardPeriod: String, CaseIterable, Identifiable {
    case week  = "7 días"
    case month = "30 días"
    case all   = "Todo"
    var id: String { rawValue }
    var cutoff: Date? {
        let cal = Calendar.current
        switch self {
        case .week:  return cal.date(byAdding: .day, value: -7,  to: Date())
        case .month: return cal.date(byAdding: .day, value: -30, to: Date())
        case .all:   return nil
        }
    }
}

struct TrendPoint: Identifiable {
    let id = UUID(); let date: Date; let score: Int
}

struct RoundedCornerShape: Shape {
    let corners: UIRectCorner; let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Dashboard View

struct DashboardView: View {

    @Query(sort: \SavedArticle.date, order: .reverse) var all: [SavedArticle]
    @State private var period: DashboardPeriod = .month
    @State private var showShare = false
    @State private var shareText = ""

    var articles: [SavedArticle] {
        guard let cutoff = period.cutoff else { return all }
        return all.filter { $0.date >= cutoff }
    }

    var total:     Int { articles.count }
    var avgTruth:  Int { avg(\.truthScore) }
    var verified:  Int { articles.filter { $0.truthScore >= 70 }.count }
    var uncertain: Int { articles.filter { $0.truthScore >= 40 && $0.truthScore < 70 }.count }
    var fake:      Int { articles.filter { $0.truthScore < 40 }.count }

    var metrics: [(name: String, icon: String, value: Int, inverted: Bool)] {[
        ("Veracidad",      "checkmark.seal",                      avg(\.truthScore),          false),
        ("Confiabilidad",  "building.columns",                    avg(\.reliabilityScore),    false),
        ("Consenso",       "person.3",                            avg(\.consensusScore),      false),
        ("Verificabilidad","doc.text.magnifyingglass",            avg(\.factCheckableScore),  false),
        ("Sesgo",          "scale.3d",                            avg(\.biasScore),           true),
        ("Sensacionalismo","bolt.trianglebadge.exclamationmark",  avg(\.sensationalismScore), true),
    ]}

    var trendPoints: [TrendPoint] {
        let cal = Calendar.current
        return (0..<14).reversed().compactMap { ago -> TrendPoint? in
            guard let day  = cal.date(byAdding: .day, value: -ago, to: Date()),
                  let end  = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)) else { return nil }
            let start = cal.startOfDay(for: day)
            let list  = all.filter { $0.date >= start && $0.date < end }
            guard !list.isEmpty else { return nil }
            return TrendPoint(date: start, score: avgIn(list, \.truthScore))
        }
    }

    var topSources: [(name: String, count: Int)] {
        var freq: [String: Int] = [:]
        articles.flatMap(\.sources).forEach { freq[$0, default: 0] += 1 }
        return freq.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            if all.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        periodPicker
                        if articles.isEmpty {
                            noPeriodData
                        } else {
                            headerScore
                            statGrid
                            verdictBar
                            metricsSection
                            if trendPoints.count >= 2 { trendChart }
                            recentList
                            if !topSources.isEmpty { sourcesSection }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("Estadísticas")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareText = makeShareText()
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .fontWeight(.semibold).foregroundColor(.deepNavy)
                }
                .disabled(articles.isEmpty)
            }
        }
        .sheet(isPresented: $showShare) { ShareSheet(text: shareText) }
    }

    // MARK: - Secciones

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(DashboardPeriod.allCases) { p in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { period = p }
                } label: {
                    Text(p.rawValue)
                        .font(.system(size: 13, weight: period == p ? .bold : .medium))
                        .foregroundColor(period == p ? .white : .deepNavy)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(period == p ? Color.deepNavy : Color.clear)
                        .cornerRadius(10)
                }
            }
        }
        .padding(4)
        .background(Color.white).cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
    }

    private var headerScore: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.deepNavy.opacity(0.08), lineWidth: 10).frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: CGFloat(avgTruth) / 100)
                    .stroke(scoreColor(avgTruth), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 100, height: 100)
                    .animation(.easeOut(duration: 0.8), value: avgTruth)
                VStack(spacing: 1) {
                    Text("\(avgTruth)%").font(.system(size: 24, weight: .bold)).foregroundColor(scoreColor(avgTruth))
                    Text("veracidad").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(overallLabel).font(.headline).foregroundColor(.deepNavy)
                Text("\(total) artículo\(total == 1 ? "" : "s") analizados")
                    .font(.subheadline).foregroundColor(.secondary)
                HStack(spacing: 10) {
                    dot(.green,  "\(verified) V")
                    dot(.orange, "\(uncertain) I")
                    dot(.red,    "\(fake) F")
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white).cornerRadius(18)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MiniStat(icon: "checkmark.seal.fill",   color: .green,    label: "Verificadas",   value: "\(verified)",  sub: pct(verified))
            MiniStat(icon: "xmark.seal.fill",       color: .red,      label: "Poco fiables",  value: "\(fake)",      sub: pct(fake))
            MiniStat(icon: "questionmark.circle.fill", color: .orange, label: "Inciertas",     value: "\(uncertain)", sub: pct(uncertain))
            MiniStat(icon: "arrow.down.circle.fill",color: .deepNavy, label: "Score mínimo",  value: "\(articles.map(\.truthScore).min() ?? 0)%", sub: "registrado")
        }
    }

    private var verdictBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Distribución de veredictos", systemImage: "chart.bar.fill")
                .font(.headline).foregroundColor(.deepNavy)
            GeometryReader { g in
                HStack(spacing: 3) {
                    colorBar(.green,  g.size.width * CGFloat(verified)  / CGFloat(max(total,1)), [.topLeft,.bottomLeft])
                    colorBar(.orange, g.size.width * CGFloat(uncertain) / CGFloat(max(total,1)), [])
                    colorBar(.red,    g.size.width * CGFloat(fake)      / CGFloat(max(total,1)), [.topRight,.bottomRight])
                }
            }
            .frame(height: 16).animation(.easeOut(duration: 0.6), value: total)
            HStack(spacing: 16) {
                vLegend(.green,  "Verificadas",   verified)
                vLegend(.orange, "Inciertas",     uncertain)
                vLegend(.red,    "Poco fiables",  fake)
            }
        }
        .padding(18).background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Métricas de análisis", systemImage: "gauge.with.needle")
                .font(.headline).foregroundColor(.deepNavy)
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, m in
                MetricBar(name: m.name, icon: m.icon, value: m.value, inverted: m.inverted)
            }
        }
        .padding(18).background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tendencia de veracidad (14 días)", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline).foregroundColor(.deepNavy)
            Chart(trendPoints) { p in
                LineMark(x: .value("Día", p.date, unit: .day), y: .value("Score", p.score))
                    .foregroundStyle(Color.deepNavy).lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(x: .value("Día", p.date, unit: .day), y: .value("Score", p.score))
                    .foregroundStyle(Color.deepNavy).symbolSize(30)
                AreaMark(x: .value("Día", p.date, unit: .day), y: .value("Score", p.score))
                    .foregroundStyle(Color.deepNavy.opacity(0.07))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.system(size: 10))
                }
            }
            .frame(height: 130)
        }
        .padding(18).background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Últimos análisis", systemImage: "clock.fill")
                .font(.headline).foregroundColor(.deepNavy)
            ForEach(Array(articles.prefix(5))) { a in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(scoreColor(a.truthScore).opacity(0.2), lineWidth: 3)
                        Text("\(a.truthScore)").font(.system(size: 11, weight: .bold)).foregroundColor(scoreColor(a.truthScore))
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.headline).font(.subheadline.weight(.medium)).foregroundColor(.deepNavy).lineLimit(2)
                        Text(a.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundColor(.secondary)
                    }
                }
                if a.id != articles.prefix(5).last?.id { Divider() }
            }
        }
        .padding(18).background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Fuentes más analizadas", systemImage: "newspaper.fill")
                .font(.headline).foregroundColor(.deepNavy)
            ForEach(topSources, id: \.name) { s in
                HStack(spacing: 10) {
                    Text(s.name).font(.subheadline).foregroundColor(.deepNavy).lineLimit(1)
                    Spacer()
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 3).fill(Color.deepNavy.opacity(0.14))
                            .frame(width: max(g.size.width * CGFloat(s.count) / CGFloat(topSources.first?.count ?? 1), 6))
                    }
                    .frame(width: 80, height: 9)
                    Text("\(s.count)").font(.caption.bold()).foregroundColor(.deepNavy).frame(width: 20, alignment: .trailing)
                }
            }
        }
        .padding(18).background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4).padding(.bottom, 8)
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis.ascending").font(.system(size: 52)).foregroundColor(.deepNavy.opacity(0.3))
            Text("Sin datos aún").font(.title3.bold()).foregroundColor(.deepNavy)
            Text("Analiza noticias desde la pantalla principal y aquí verás tus estadísticas.")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
        }
    }

    private var noPeriodData: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.minus").font(.system(size: 40)).foregroundColor(.deepNavy.opacity(0.3))
            Text("Sin análisis en los últimos \(period.rawValue.lowercased())")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(30).frame(maxWidth: .infinity).background(Color.white).cornerRadius(16)
    }

    // MARK: - Helpers

    private func avg(_ kp: KeyPath<SavedArticle, Int>) -> Int { avgIn(articles, kp) }
    private func avgIn(_ list: [SavedArticle], _ kp: KeyPath<SavedArticle, Int>) -> Int {
        guard !list.isEmpty else { return 0 }
        return list.map { $0[keyPath: kp] }.reduce(0, +) / list.count
    }
    private func pct(_ n: Int) -> String {
        total > 0 ? "\(Int(Double(n) / Double(total) * 100))%" : "0%"
    }
    private func scoreColor(_ s: Int) -> Color { s >= 70 ? .green : s >= 40 ? .orange : .red }
    private var overallLabel: String {
        avgTruth >= 70 ? "Contenido mayormente verificado"
        : avgTruth >= 40 ? "Resultados mixtos"
        : "Alto índice de desinformación"
    }
    private func dot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(t).font(.caption2.bold()).foregroundColor(.secondary) }
    }
    private func colorBar(_ c: Color, _ w: CGFloat, _ corners: UIRectCorner) -> some View {
        RoundedCornerShape(corners: corners, radius: 5).fill(c).frame(width: max(w, 4))
    }
    private func vLegend(_ c: Color, _ label: String, _ n: Int) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundColor(.secondary)
                Text("\(n) (\(pct(n)))").font(.caption.bold()).foregroundColor(.deepNavy)
            }
        }
    }
    private func makeShareText() -> String {
        """
        📊 Mis estadísticas SafeGate (\(period.rawValue))
        🔍 Analizadas: \(total)
        ✅ Verificadas: \(verified) (\(pct(verified)))
        ❓ Inciertas: \(uncertain) (\(pct(uncertain)))
        ❌ Poco fiables: \(fake) (\(pct(fake)))
        📈 Score promedio: \(avgTruth)%
        """
    }
}

// MARK: - Subvistas reutilizables

struct MiniStat: View {
    let icon: String; let color: Color; let label: String; let value: String; let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(color)
            Text(value).font(.title2.bold()).foregroundColor(.deepNavy)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).foregroundColor(.secondary)
                Text(sub).font(.caption2).foregroundColor(color)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white).cornerRadius(14)
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
    }
}

struct MetricBar: View {
    let name: String; let icon: String; let value: Int; let inverted: Bool
    private var effective: Int { inverted ? 100 - value : value }
    private var barColor: Color { effective >= 70 ? .green : effective >= 40 ? .orange : .red }
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(.secondary)
                Text(name).font(.subheadline).foregroundColor(.deepNavy)
                Spacer()
                Text("\(value)%").font(.subheadline.bold()).foregroundColor(barColor)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.1)).frame(height: 7)
                    RoundedRectangle(cornerRadius: 4).fill(barColor)
                        .frame(width: g.size.width * CGFloat(value) / 100, height: 7)
                        .animation(.easeOut(duration: 0.7), value: value)
                }
            }
            .frame(height: 7)
        }
    }
}
