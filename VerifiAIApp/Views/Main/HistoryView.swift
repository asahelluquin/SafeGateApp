import SwiftUI
import SwiftData

//Paleta de Colores Personalizada
extension Color {
    static let appBackground = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let deepNavy = Color(red: 0.04, green: 0.17, blue: 0.37)
    static let verifiedBg = Color.cyan.opacity(0.3)
    static let highRiskBg = Color.red.opacity(0.15)
}

struct HistoryView: View {
    @Query(sort: \SavedArticle.date, order: .reverse) var articles: [SavedArticle]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                
                if articles.isEmpty {
                    ContentUnavailableView(
                        "Sin historial",
                        systemImage: "clock.badge.exclamationmark",
                        description: Text("Las noticias que analices aparecerán aquí.")
                    )
                } else {
                    List {
                        ForEach(articles) { article in
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
                                
                                CardContentView(article: article)
                                    .padding(16)
                                
                                NavigationLink(destination: ResultView(result: article.toAnalysisResult())) {
                                    EmptyView()
                                }
                                .opacity(0)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                        .onDelete(perform: deleteArticles)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Historial")
        }
    }
    
    private func deleteArticles(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(articles[index])
        }
    }
}

//Componente: Contenido de la Tarjeta
struct CardContentView: View {
    var article: SavedArticle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            //Criterio + Porcentaje (Sin badges de estado)
            HStack(alignment: .lastTextBaseline) {
                // Etiqueta del criterio (Discreta)
                Text("VERACIDAD")
                    .font(.caption2)
                    .fontWeight(.black)
                    .foregroundColor(.secondary)
                
                Spacer()

                Text("\(article.truthScore)%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(article.truthScore > 70 ? .deepNavy : .red)
            }
            
            //Título de la noticia
            Text(article.headline)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.deepNavy)
                .lineLimit(2)
            
            //Pie de tarjeta: Fecha + Flecha
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                    Text(article.date.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }
}
