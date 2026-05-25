import SwiftUI
import SwiftData

@main
struct VerifiAIAppApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(for: SavedArticle.self)
    }
}
