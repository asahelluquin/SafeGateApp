import Foundation

struct AnalysisResult: Codable {
    let headline: String
    let truthScore: Int
    let reliabilityScore: Int
    let consensusScore: Int
    let biasScore: Int
    let sensationalismScore: Int
    let factCheckableScore: Int
    let sources: [String]
    let summary: String
    let imageUrl: String?
}

