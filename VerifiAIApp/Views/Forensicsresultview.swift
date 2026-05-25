import SwiftUI

// MARK: - Vista de resultado forense

struct ForensicsResultView: View {

    let result: ForensicsResult
    @Environment(\.dismiss) private var dismiss

    private var verdictColor: Color {
        switch result.verdict {
        case .authentic:   return .green
        case .suspicious:  return .orange
        case .manipulated: return .red
        case .aiGenerated: return .purple
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                verdictHeader
                riskGauge
                summaryCard
                if !result.manipulationSignals.isEmpty { manipulationSection }
                if !result.authenticSignals.isEmpty    { authenticSection    }
                aiSection
                if let exif = result.exif              { exifSection(exif)   }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Análisis de imagen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .fontWeight(.semibold).foregroundColor(.deepNavy)
                }
            }
        }
    }

    // MARK: - Header con veredicto

    private var verdictHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: result.verdict.icon)
                .font(.system(size: 44))
                .foregroundColor(verdictColor)

            Text(result.verdict.label)
                .font(.title2.bold())
                .foregroundColor(verdictColor)

            Text("Análisis forense completado")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(verdictColor.opacity(0.3), lineWidth: 1.5)
                )
        )
        .shadow(color: verdictColor.opacity(0.12), radius: 12, x: 0, y: 6)
    }

    // MARK: - Medidor de riesgo

    private var riskGauge: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Nivel de riesgo", systemImage: "gauge.with.needle")
                    .font(.headline).foregroundColor(.deepNavy)
                Spacer()
                Text("\(result.riskScore)/100")
                    .font(.headline).foregroundColor(riskColor)
            }

            GeometryReader { g in
                ZStack(alignment: .leading) {
                    // Gradiente de fondo
                    LinearGradient(
                        colors: [.green, .yellow, .orange, .red],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(height: 12).cornerRadius(6)

                    // Indicador de posición
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 3)
                        .frame(width: 20, height: 20)
                        .offset(x: (g.size.width - 20) * CGFloat(result.riskScore) / 100)
                        .animation(.easeOut(duration: 0.8), value: result.riskScore)
                }
            }
            .frame(height: 20)

            HStack {
                Text("Sin riesgo").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Text("Riesgo máximo").font(.caption2).foregroundColor(.secondary)
            }

            // Descripción del nivel
            Text(riskDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(18)
        .background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    // MARK: - Resumen

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Conclusión del análisis", systemImage: "doc.text.magnifyingglass")
                .font(.headline).foregroundColor(.deepNavy)
            Text(result.summary)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineSpacing(4)
        }
        .padding(18)
        .background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    // MARK: - Señales de manipulación

    private var manipulationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Señales de manipulación detectadas", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundColor(.red)

            ForEach(result.manipulationSignals) { signal in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: signal.severity.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(severityColor(signal.severity))
                        .frame(width: 24)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(signal.type.capitalized)
                                .font(.subheadline.bold()).foregroundColor(.primary)
                            Spacer()
                            Text("Severidad \(signal.severity.label)")
                                .font(.caption2)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(severityColor(signal.severity).opacity(0.12))
                                .foregroundColor(severityColor(signal.severity))
                                .cornerRadius(6)
                        }
                        Text(signal.description)
                            .font(.caption).foregroundColor(.secondary).lineSpacing(3)
                    }
                }
                .padding(12)
                .background(Color.red.opacity(0.03))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.1), lineWidth: 0.5))
            }
        }
        .padding(18)
        .background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    // MARK: - Señales auténticas

    private var authenticSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Señales de autenticidad", systemImage: "checkmark.shield.fill")
                .font(.headline).foregroundColor(.green)

            ForEach(result.authenticSignals, id: \.self) { signal in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green).font(.system(size: 14))
                    Text(signal).font(.subheadline).foregroundColor(.primary)
                }
            }
        }
        .padding(18)
        .background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    // MARK: - Sección IA

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Probabilidad de generación por IA", systemImage: "cpu.fill")
                .font(.headline).foregroundColor(.purple)

            HStack(spacing: 12) {
                Text(result.aiLikelihood.capitalized)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(aiColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Probabilidad de ser").font(.caption).foregroundColor(.secondary)
                    Text("generada por IA").font(.caption.bold()).foregroundColor(.secondary)
                }
                Spacer()
            }

            if !result.aiIndicators.isEmpty {
                Divider()
                Text("Indicadores detectados:").font(.caption).foregroundColor(.secondary)
                ForEach(result.aiIndicators, id: \.self) { indicator in
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundColor(.purple)
                        Text(indicator).font(.caption).foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    // MARK: - Metadata EXIF

    private func exifSection(_ exif: EXIFData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Metadatos de la imagen (EXIF)", systemImage: "info.circle.fill")
                .font(.headline).foregroundColor(.deepNavy)

            if !exif.hasMetadata {
                Text("Sin metadatos EXIF — puede ser screenshot o imagen procesada.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    exifRow("Dispositivo",   exif.make.map { "\($0) \(exif.model ?? "")" } ?? exif.model)
                    exifRow("Software",      exif.software)
                    exifRow("Fecha captura", exif.formattedDate)
                    exifRow("Resolución",    exif.resolution)
                    exifRow("Color",         exif.colorModel)
                    exifRow("GPS",           exif.hasGPS ? "Coordenadas presentes" : "Sin datos GPS")
                }
            }
        }
        .padding(18)
        .background(Color.white).cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
        .padding(.bottom, 8)
    }

    private func exifRow(_ label: String, _ value: String?) -> some View {
        Group {
            if let value = value, !value.isEmpty {
                HStack {
                    Text(label).font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Text(value).font(.subheadline.weight(.medium)).foregroundColor(.deepNavy).multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
    }

    // MARK: - Helpers

    private var riskColor: Color {
        result.riskScore < 20 ? .green : result.riskScore < 50 ? .orange : .red
    }

    private var aiColor: Color {
        switch result.aiLikelihood {
        case "nula":  return .green
        case "baja":  return .yellow
        case "media": return .orange
        default:      return .red
        }
    }

    private func severityColor(_ s: SignalSeverity) -> Color {
        switch s { case .high: return .red; case .medium: return .orange; case .low: return .yellow }
    }

    private var riskDescription: String {
        switch result.riskScore {
        case 0..<20:  return "No se detectaron señales significativas de manipulación."
        case 20..<50: return "Se encontraron indicios menores que podrían ser artefactos naturales."
        case 50..<80: return "Se detectaron señales claras de posible edición o manipulación digital."
        default:      return "Alta probabilidad de que esta imagen haya sido modificada o generada artificialmente."
        }
    }

    private var shareText: String {
        """
        🔍 Análisis forense SafeGate

        Veredicto: \(result.verdict.label)
        Nivel de riesgo: \(result.riskScore)/100

        \(result.summary)

        Señales detectadas: \(result.manipulationSignals.count)
        Probabilidad IA: \(result.aiLikelihood.capitalized)
        """
    }
}
