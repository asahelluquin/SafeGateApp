import UIKit

// MARK: - Haptic Manager
// Centraliza toda la retroalimentación táctil de la app.
// Usar: HapticManager.analysisFeedback(score: result.truthScore)

struct HapticManager {

    /// Vibración al recibir el resultado del análisis.
    /// - score < 40  → Doble golpe fuerte (falso / poco confiable)
    /// - score 40-69 → Golpe medio (resultado ambiguo)
    /// - score ≥ 70  → Notificación de éxito (verificado)
    static func analysisFeedback(score: Int) {
        switch score {
        case ..<40:
            // Noticias falsas o poco confiables: doble impacto pesado
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                generator.impactOccurred(intensity: 0.85)
            }

        case 40..<70:
            // Resultado incierto: impacto medio único
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()

        default:
            // Noticia verificada: patrón de éxito
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Toque suave para interacciones de UI (botones, chips)
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Toque de selección (chips de categoría, etc.)
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
