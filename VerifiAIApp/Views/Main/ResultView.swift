import SwiftUI
import AVFoundation
import Combine

// Administrador de Voz (Text to Speech)
class TTSManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func toggleSpeech(text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
        } else {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Error configurando el audio: \(error)")
            }
            
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "es-MX")
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0
            
            synthesizer.speak(utterance)
            isSpeaking = true
        }
    }
    
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}

// Vista Principal de Resultados
struct ResultView: View {
    let result: AnalysisResult
    
    @State private var selectedCategory: CategoryInfo? = nil
    @State private var shareableImage: Image?
    
    @StateObject private var ttsManager = TTSManager()
    
    let columnas = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    func colorForStandardMetric(_ score: Int) -> Color {
        if score >= 70 { return .green }
        else if score >= 40 { return .orange }
        else { return .red }
    }
    
    func colorForInvertedMetric(_ score: Int) -> Color {
        if score <= 30 { return .green }
        else if score <= 60 { return .orange }
        else { return .red }
    }
    
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    //Titular
                    Text(result.headline)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.deepNavy)
                        .padding(.horizontal, 20)
                        .multilineTextAlignment(.leading)
                    
                    //Imagen de Contexto
                    if let imageUrlString = result.imageUrl, let url = URL(string: imageUrlString) {
                        AsyncImage(url: url) { imagePhase in
                            switch imagePhase {
                            case .empty:
                                ProgressView().frame(maxWidth: .infinity).frame(height: 200)
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                                    .frame(maxWidth: .infinity).frame(height: 220)
                                    .clipped().cornerRadius(16).padding(.horizontal, 20)
                            case .failure:
                                EmptyView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .padding(.top, -8)
                    }
                    
                    // Análisis Detallado (Métricas)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "gauge.with.needle.fill")
                            Text("Análisis Detallado").font(.headline)
                        }
                        .padding(.horizontal, 20)
                        .foregroundColor(.deepNavy.opacity(0.7))
                        
                        LazyVGrid(columns: columnas, spacing: 16) {
                            ScoreCardView(title: "Veracidad", score: result.truthScore, icon: "checkmark.seal.fill", color: colorForStandardMetric(result.truthScore)) {
                                selectedCategory = CategoryInfo(title: "Veracidad", description: "Mide la exactitud factual. Coteja fechas, nombres y cifras con registros.", icon: "checkmark.seal.fill", color: colorForStandardMetric(result.truthScore))
                            }
                            
                            ScoreCardView(title: "Confiabilidad", score: result.reliabilityScore, icon: "shield.fill", color: colorForStandardMetric(result.reliabilityScore)) {
                                selectedCategory = CategoryInfo(title: "Confiabilidad", description: "Evalúa la reputación editorial y el historial de la fuente que publica la noticia.", icon: "shield.fill", color: colorForStandardMetric(result.reliabilityScore))
                            }
                            
                            ScoreCardView(title: "Consenso", score: result.consensusScore, icon: "person.3.fill", color: colorForStandardMetric(result.consensusScore)) {
                                selectedCategory = CategoryInfo(title: "Consenso", description: "Mide qué tanto coincide esta noticia con lo reportado por otros medios independientes.", icon: "person.3.fill", color: colorForStandardMetric(result.consensusScore))
                            }
                            
                            ScoreCardView(title: "Sesgo", score: result.biasScore, icon: "scale.3d", color: colorForInvertedMetric(result.biasScore)) {
                                selectedCategory = CategoryInfo(title: "Sesgo", description: "Analiza si el texto usa lenguaje cargado o intenta empujar una agenda.", icon: "scale.3d", color: colorForInvertedMetric(result.biasScore))
                            }
                            
                            ScoreCardView(title: "Sensacionalismo", score: result.sensationalismScore, icon: "exclamationmark.triangle.fill", color: colorForInvertedMetric(result.sensationalismScore)) {
                                selectedCategory = CategoryInfo(title: "Sensacionalismo", description: "Detecta si el titular o el texto buscan causar miedo o sorpresa exagerada.", icon: "exclamationmark.triangle.fill", color: colorForInvertedMetric(result.sensationalismScore))
                            }
                            
                            ScoreCardView(title: "Verificabilidad", score: result.factCheckableScore, icon: "magnifyingglass.circle.fill", color: colorForStandardMetric(result.factCheckableScore)) {
                                selectedCategory = CategoryInfo(title: "Verificabilidad", description: "Indica qué tan fácil es encontrar evidencia externa, nombres o documentos rastreables.", icon: "magnifyingglass.circle.fill", color: colorForStandardMetric(result.factCheckableScore))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Resumen del Veredicto
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Resumen").font(.headline).foregroundColor(.deepNavy)
                            Spacer()
                            Button(action: {
                                ttsManager.toggleSpeech(text: result.summary)
                            }) {
                                Image(systemName: ttsManager.isSpeaking ? "speaker.wave.2.circle.fill" : "speaker.wave.2.circle")
                                    .font(.title2)
                                    .foregroundColor(ttsManager.isSpeaking ? .green : .deepNavy.opacity(0.6))
                                    .scaleEffect(ttsManager.isSpeaking ? 1.1 : 1.0)
                                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: ttsManager.isSpeaking)
                            }
                        }
                        
                        Text(result.summary).font(.body).lineSpacing(6).foregroundColor(.deepNavy.opacity(0.85))
                    }
                    .padding(20).background(Color.white).cornerRadius(20)
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4).padding(.horizontal, 20)
                    
                    //FUENTES EN LABELS DESLIZABLES
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FUENTES CONSULTADAS")
                            .font(.caption2)
                            .fontWeight(.black)
                            .tracking(1.5)
                            .foregroundColor(.deepNavy.opacity(0.5))
                            .padding(.horizontal, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(result.sources, id: \.self) { fuente in
                                    Text(fuente)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.deepNavy)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.deepNavy.opacity(0.08))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 30)
                }
                .padding(.vertical)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let shareableImage = shareableImage {
                    ShareLink(item: shareableImage, preview: SharePreview("Análisis SafeGate", image: shareableImage)) {
                        Image(systemName: "square.and.arrow.up")
                            .fontWeight(.bold)
                            .foregroundColor(.deepNavy)
                    }
                }
            }
        }
        .onAppear {
            generateShareableImage()
            HapticManager.analysisFeedback(score: result.truthScore)
        }
        .onDisappear { ttsManager.stop() }
        .sheet(item: $selectedCategory) { category in
            VStack(spacing: 20) {
                Capsule().frame(width: 40, height: 6).foregroundColor(.gray.opacity(0.3)).padding(.top)
                Image(systemName: category.icon).font(.system(size: 40)).foregroundColor(category.color)
                Text(category.title).font(.title2).bold().foregroundColor(.deepNavy)
                
                ScrollView {
                    Text(category.description).font(.body).multilineTextAlignment(.center).padding(.horizontal, 24).foregroundColor(.deepNavy.opacity(0.8))
                }
                
                Button(action: { selectedCategory = nil }) {
                    Text("Entendido")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .contentShape(Rectangle())
                }
                .background(Color.deepNavy)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }
            .presentationDetents([.fraction(0.45), .medium])
            .presentationDragIndicator(.visible)
            .background(Color.appBackground.ignoresSafeArea())
        }
    }
    
    @MainActor
    private func generateShareableImage() {
        let renderer = ImageRenderer(content: ResultPrintableView(result: result))
        renderer.scale = UIScreen.main.scale * 2
        if let uiImage = renderer.uiImage {
            self.shareableImage = Image(uiImage: uiImage)
        }
    }
}

//Vista especial para exportar
struct ResultPrintableView: View {
    let result: AnalysisResult
    
    func colorForStandardMetric(_ score: Int) -> Color {
        if score >= 70 { return .green } else if score >= 40 { return .orange } else { return .red }
    }
    func colorForInvertedMetric(_ score: Int) -> Color {
        if score <= 30 { return .green } else if score <= 60 { return .orange } else { return .red }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Reporte de Análisis").font(.caption).fontWeight(.black).foregroundColor(.gray).textCase(.uppercase)
            
            Text(result.headline).font(.title2).fontWeight(.bold).foregroundColor(.deepNavy)
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                PrintableScoreCard(title: "Veracidad", score: result.truthScore, icon: "checkmark.seal.fill", color: colorForStandardMetric(result.truthScore))
                PrintableScoreCard(title: "Confiabilidad", score: result.reliabilityScore, icon: "shield.fill", color: colorForStandardMetric(result.reliabilityScore))
                PrintableScoreCard(title: "Consenso", score: result.consensusScore, icon: "person.3.fill", color: colorForStandardMetric(result.consensusScore))
                PrintableScoreCard(title: "Sesgo", score: result.biasScore, icon: "scale.3d", color: colorForInvertedMetric(result.biasScore))
                PrintableScoreCard(title: "Sensacionalismo", score: result.sensationalismScore, icon: "exclamationmark.triangle.fill", color: colorForInvertedMetric(result.sensationalismScore))
                PrintableScoreCard(title: "Verificabilidad", score: result.factCheckableScore, icon: "magnifyingglass.circle.fill", color: colorForStandardMetric(result.factCheckableScore))
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Veredicto").font(.headline).foregroundColor(.deepNavy)
                Text(result.summary).font(.body).lineSpacing(4).foregroundColor(.deepNavy.opacity(0.85))
            }
            .padding(16).background(Color.white).cornerRadius(16)
            
            if !result.sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FUENTES:").font(.caption2).fontWeight(.bold).foregroundColor(.gray)
                    Text(result.sources.joined(separator: " • ")).font(.caption2).foregroundColor(.deepNavy.opacity(0.6))
                }
            }
            
            VStack(spacing: 12) {
                Divider().padding(.bottom, 4)
                Image("AppLogo").resizable().scaledToFit().frame(height: 35).cornerRadius(8)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill").foregroundColor(.deepNavy)
                    Text("Verificado con").foregroundColor(.gray)
                    Text("SafeGate").fontWeight(.bold).foregroundColor(.deepNavy)
                }.font(.footnote)
            }
            .padding(.top, 10)
        }
        .padding(30).background(Color.appBackground).frame(width: 420)
    }
}

//Componentes de apoyo
struct PrintableScoreCard: View {
    let title: String; let score: Int; let icon: String; let color: Color
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.caption2).fontWeight(.semibold).foregroundColor(.deepNavy.opacity(0.6)).textCase(.uppercase)
            Text("\(score)%").font(.title3).fontWeight(.bold).foregroundColor(.deepNavy)
            Image(systemName: icon).foregroundColor(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).background(Color.white).cornerRadius(12)
    }
}

struct CategoryInfo: Identifiable {
    let id = UUID()
    let title: String; let description: String; let icon: String; let color: Color
}

struct ScoreCardView: View {
    let title: String; let score: Int; let icon: String; let color: Color; let action: () -> Void
    @State private var appearScale: CGFloat = 0.5
    @State private var breathingScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    Text(title).font(.caption).fontWeight(.semibold).foregroundColor(.deepNavy.opacity(0.6)).textCase(.uppercase).multilineTextAlignment(.center)
                    Text("\(score)%").font(.title2).fontWeight(.bold).foregroundColor(.deepNavy)
                    Image(systemName: icon).font(.title3).foregroundColor(color)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20).padding(.horizontal, 10)
                Image(systemName: "info.circle").font(.caption2).foregroundColor(.deepNavy.opacity(0.4)).padding(.top, 10).padding(.trailing, 10)
            }
            .background(Color.white).cornerRadius(18).shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(CardButtonStyle())
        .scaleEffect(appearScale * breathingScale)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)) { appearScale = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathingScale = 1.03 }
            }
        }
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed).opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}
