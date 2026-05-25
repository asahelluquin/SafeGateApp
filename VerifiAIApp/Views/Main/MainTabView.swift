import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var tabSeleccionada = 1
    
    // Leemos la variable del modo oscuro para aplicarla a TODA la app
    @AppStorage("isDarkMode") private var isDarkMode = false
    
    var body: some View {
        TabView(selection: $tabSeleccionada) {
            
            //Pestaña Izquierda, ponemos la vista que creamos
            HistoryView()
                .tabItem {
                    Label("Historial", systemImage: "clock.fill")
                }
                .tag(0)
            
            //Pestaña Central: Pantalla Principal
            HomeView()
                .tabItem {
                    Label("Principal", systemImage: "house.fill")
                }
                .tag(1)
            //Pestaña Tendencias
            TrendingView()
                .tabItem {
                    Label("Tendencias", systemImage: "flame.fill")
                }
                .tag(3)
            //Pestaña Opciones
            OptionsView()
                .tabItem {
                    Label("Opciones", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: SavedArticle.self, inMemory: true)
}
