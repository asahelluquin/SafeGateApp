import Foundation
import SwiftUI
import Combine
import SwiftData

@MainActor
class AnalyzeViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var result: AnalysisResult? = nil
    @Published var navigateToResult: Bool = false
    
    // Controla en qué paso de la animación del Checklist vamos (0 al 5)
    @Published var loadingStep: Int = 0
    
    // Almacena la imagen seleccionada por el usuario
    @Published var selectedImageData: Data? = nil
    
    // Servicios
    private let geminiService = AiVerificationService()
    private let scraperService = WebScraperService()
    
    func performAnalysis(text: String, modelContext: ModelContext) {
        // Validamos que haya algo que analizar (texto o imagen)
        guard !text.isEmpty || selectedImageData != nil else { return }
        
        isLoading = true
        errorMessage = nil
        result = nil
        navigateToResult = false
        loadingStep = 0 // Reiniciamos el contador del checklist
        
        Task {
            do {
                // PASO 0: Inicio del proceso
                withAnimation { self.loadingStep = 0 }
                try await Task.sleep(nanoseconds: 400_000_000)
                
                let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                var foundImageUrl: String? = nil
                
                // Esta variable contendrá lo que finalmente enviaremos a la IA
                // (Ya sea el texto plano del usuario o el contenido extraído de la URL)
                var textForAI = cleanedText
                
                //Preparando archivos y extrayendo contenido de red...
                withAnimation { self.loadingStep = 1 }
                
                if cleanedText.lowercased().hasPrefix("http") {
                    //Intentamos extraer la imagen de portada (og:image)
                    foundImageUrl = await scraperService.fetchOGImage(from: cleanedText)
                    
                    //Extraemos el contenido completo del artículo con Jina Reader
                    if let articleContent = await scraperService.fetchArticleContent(from: cleanedText) {
                        textForAI = """
                        URL DEL ARTÍCULO: \(cleanedText)
                        
                        CONTENIDO COMPLETO PARA ANALIZAR:
                        \(articleContent)
                        """
                        print("✅ Jina Reader entregó contenido")
                    }
                }
                try await Task.sleep(nanoseconds: 600_000_000)
                
                //Extrayendo contexto visual y razonamiento lógico...
                withAnimation { self.loadingStep = 2 }
                
                // Enviamos el 'textForAI' (que ahora tiene el contenido real de la noticia)
                let response = try await geminiService.analyzeNews(
                    text: textForAI.isEmpty ? nil : textForAI,
                    imageData: selectedImageData
                )
                
                //Verificando base histórica y cruzando datos oficiales...
                withAnimation { self.loadingStep = 3 }
                try await Task.sleep(nanoseconds: 800_000_000)
                
                // Armamos el objeto de resultado final
                let finalResponse = AnalysisResult(
                    headline: response.headline,
                    truthScore: response.truthScore,
                    reliabilityScore: response.reliabilityScore,
                    consensusScore: response.consensusScore,
                    biasScore: response.biasScore,
                    sensationalismScore: response.sensationalismScore,
                    factCheckableScore: response.factCheckableScore,
                    sources: response.sources,
                    summary: response.summary,
                    imageUrl: foundImageUrl // Usamos la imagen que scrapeamos si existe
                )
                
                //Calculando métricas de sesgo y veracidad...
                withAnimation { self.loadingStep = 4 }
                
                // Guardamos en la base de datos local (SwiftData)
                let articleToSave = SavedArticle(result: finalResponse)
                modelContext.insert(articleToSave)
                try modelContext.save()
                
                //Generando veredicto y guardando en historial...
                withAnimation { self.loadingStep = 5 }
                try await Task.sleep(nanoseconds: 500_000_000)
                
                //Actualizamos la UI para navegar al resultado
                self.result = finalResponse
                self.isLoading = false
                self.navigateToResult = true
                self.selectedImageData = nil
                
            } catch {
                self.isLoading = false
                self.errorMessage = "No se pudo completar el análisis. Verifica tu conexión o intenta de nuevo."
                print("❌ Error en el proceso: \(error)")
            }
        }
    }
}
