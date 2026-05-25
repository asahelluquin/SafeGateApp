import Foundation
import SwiftData

@Model
class SavedArticle {
    var id: UUID
    var headline: String
    var truthScore: Int
    var reliabilityScore: Int
    var consensusScore: Int
    var biasScore: Int
    var sensationalismScore: Int
    var factCheckableScore: Int
    var sources: [String]
    var summary: String
    var imageUrl: String?
    var date: Date
    
    init(result: AnalysisResult) {
        self.id = UUID()
        self.headline = result.headline
        self.truthScore = result.truthScore
        self.reliabilityScore = result.reliabilityScore
        self.consensusScore = result.consensusScore
        self.biasScore = result.biasScore
        self.sensationalismScore = result.sensationalismScore
        self.factCheckableScore = result.factCheckableScore
        self.sources = result.sources
        self.summary = result.summary
        self.imageUrl = result.imageUrl
        self.date = Date()
    }
    
    // Función de ayuda para convertir el artículo guardado de vuelta al formato de la vista
    func toAnalysisResult() -> AnalysisResult {
        return AnalysisResult(
            headline: self.headline,
            truthScore: self.truthScore,
            reliabilityScore: self.reliabilityScore,
            consensusScore: self.consensusScore,
            biasScore: self.biasScore,
            sensationalismScore: self.sensationalismScore,
            factCheckableScore: self.factCheckableScore,
            sources: self.sources,
            summary: self.summary,
            imageUrl: self.imageUrl
        )
    }
}
