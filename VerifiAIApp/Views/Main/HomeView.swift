import SwiftUI
import SwiftData
import PhotosUI

struct HomeView: View {
    @State private var articleInput: String = ""
    
    // Conectamos nuestra vista con el ViewModel
    @StateObject private var viewModel = AnalyzeViewModel()
    // Instanciamos nuestro servicio de micrófono
    @StateObject private var speechRecognizer = SpeechRecognizer()
    
    // Accedemos al contexto de la base de datos para persistencia
    @Environment(\.modelContext) private var modelContext
    
    // Controlamos cuándo el teclado está activo
    @FocusState private var isInputFocused: Bool
    
    // Variables para manejo de imágenes
    @State private var showImageOptions = false
    @State private var showForensicsPicker = false
    @State private var forensicsSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var forensicsImageData: Data? = nil
    @State private var forensicsPreview: UIImage? = nil
    @State private var forensicsResult: ForensicsResult? = nil
    @State private var forensicsLoading = false
    @State private var showForensicsResult = false
    @State private var showImagePicker = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var previewImage: UIImage? = nil
    
    // Servicio forense
    private let forensicsService = ImageForensicsService()
    
    // Paleta de colores basada en la imagen
    let bgColor = Color(red: 248/255, green: 249/255, blue: 250/255)
    let cardBgColor = Color(red: 242/255, green: 242/255, blue: 244/255)
    let primaryNavy = Color(red: 13/255, green: 60/255, blue: 135/255)
    
    var body: some View {
        NavigationStack {
            ZStack {
                bgColor.ignoresSafeArea()
                
                //INTERFAZ PRINCIPAL
                VStack(alignment: .leading, spacing: 20) {
                    
                    //HEADER TIPO DASHBOARD
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Analizar Noticias")
                            .font(.system(size: 42, weight: .heavy, design: .default))
                            .foregroundColor(primaryNavy)
                        
                        Text("Escanea URLs, imagenes o titulares para analizar. Nuestro analizador disecciona la información, reputación de la fuente y patrones lingüísticos.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 10)
                    
                    // ÁREA PRINCIPAL DE ENTRADA
                    VStack(spacing: 16) {
                        HStack {
                            Text("FUENTE DE INFORMACIÓN")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(primaryNavy)
                                .kerning(1.2)
                            Spacer()
                        }
                        
                        // Campo de Texto y Micrófono
                        ZStack(alignment: .topLeading) {
                            if articleInput.isEmpty && !speechRecognizer.isRecording {
                                Text("Pega un enlace,imagen, titular o presiona el micrófono...")
                                    .foregroundColor(.gray.opacity(0.6))
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                            
                            TextEditor(text: $articleInput)
                                .frame(minHeight: 100, maxHeight: 150)
                                .scrollContentBackground(.hidden)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.black)
                                .cornerRadius(12)
                                .focused($isInputFocused)
                                .onChange(of: speechRecognizer.transcript) { newValue in
                                    if speechRecognizer.isRecording {
                                        articleInput = newValue
                                    }
                                }
                        }
                        
                        // Barra de herramientas: Pegar y Micrófono
                        HStack {
                            Button(action: {
                                if let string = UIPasteboard.general.string {
                                    articleInput = string
                                }
                            }) {
                                Image(systemName: "doc.on.clipboard")
                                    .foregroundColor(primaryNavy)
                                    .font(.system(size: 20))
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                if speechRecognizer.isRecording {
                                    speechRecognizer.stopTranscribing()
                                    isInputFocused = false
                                } else {
                                    isInputFocused = false
                                    speechRecognizer.startTranscribing()
                                }
                            }) {
                                ZStack {
                                    if speechRecognizer.isRecording {
                                        Circle()
                                            .fill(Color.red.opacity(0.3))
                                            .frame(width: 40, height: 40)
                                            .scaleEffect(speechRecognizer.isRecording ? 1.2 : 1.0)
                                            .animation(.easeInOut(duration: 0.8).repeatForever(), value: speechRecognizer.isRecording)
                                    }
                                    
                                    Image(systemName: speechRecognizer.isRecording ? "stop.fill" : "mic.fill")
                                        .foregroundColor(speechRecognizer.isRecording ? .red : primaryNavy)
                                        .font(.system(size: 20))
                                }
                            }
                        }
                        
                        // Vista previa de la imagen
                        if let image = previewImage {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 120)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                Button(action: {
                                    previewImage = nil
                                    viewModel.selectedImageData = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .padding(8)
                            }
                        }
                    }
                    .padding(20)
                    .background(cardBgColor)
                    .cornerRadius(20)
                    .padding(.horizontal, 24)
                    .onTapGesture {
                        isInputFocused = false
                    }
                    
                    // BOTONES DE ACCIÓN
                    VStack(spacing: 12) {
                        Button(action: {
                            isInputFocused = false
                            speechRecognizer.stopTranscribing()
                            viewModel.performAnalysis(text: articleInput, modelContext: modelContext)
                        }) {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView().tint(.white).padding(.trailing, 5)
                                } else {
                                    Image(systemName: "magnifyingglass.circle.fill")
                                }
                                Text(viewModel.isLoading ? "Analizando..." : "Analizar Ahora")
                                    .font(.headline)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background((articleInput.isEmpty && previewImage == nil) || viewModel.isLoading ? Color.gray : primaryNavy)
                            .cornerRadius(12)
                        }
                        .disabled((articleInput.isEmpty && previewImage == nil) || viewModel.isLoading)
                        
                        Button(action: {
                            isInputFocused = false
                            showImageOptions = true
                        }) {
                            Text(previewImage == nil ? "+ Adjuntar Imagen" : "Cambiar Imagen")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(primaryNavy)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 24)
                    }
                    
                    Spacer()
                }
                .onTapGesture {
                    isInputFocused = false
                }
                
                // NAVEGACIÓN OCULTA
                .navigationDestination(isPresented: $viewModel.navigateToResult) {
                    if let validResult = viewModel.result {
                        ResultView(result: validResult)
                            .onDisappear {
                                previewImage = nil
                                articleInput = ""
                            }
                    } else {
                        Text("Error al recuperar los resultados")
                    
                    // Botón de análisis forense de imagen
                    Button(action: { showForensicsPicker = true }) {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.badge.magnifyingglass")
                                .font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Analizar imagen")
                                    .font(.subheadline.bold())
                                Text("Detecta manipulaciones y contenido de IA")
                                    .font(.caption).opacity(0.8)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold)).opacity(0.6)
                        }
                        .foregroundColor(primaryNavy)
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(red: 13/255, green: 60/255, blue: 135/255).opacity(0.25), lineWidth: 1.5)
                                .background(Color(red: 13/255, green: 60/255, blue: 135/255).opacity(0.04))
                        )
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 24)
                    
                    if forensicsLoading {
                        HStack(spacing: 10) {
                            ProgressView().tint(primaryNavy)
                            Text("Analizando imagen...").font(.subheadline).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    }
                }
                .navigationDestination(isPresented: $showForensicsResult) {
                    if let result = forensicsResult {
                        ForensicsResultView(result: result)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Listo") {
                            isInputFocused = false
                        }
                        .fontWeight(.bold)
                        .opacity(0.0)
                        .frame(width: 0, height: 0)
                        .hidden()
                    }
                    
                    ToolbarItem(placement: .topBarLeading) {
                        HStack {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 35, height: 35)
                            Text("SafeGate").frame(width: 100).font(.headline).fontWeight(.bold).foregroundColor(primaryNavy)
                        }
                    }
                   
                }
                
                // TARJETA DE CARGA (CHECKLIST FLOTANTE)
                if viewModel.isLoading {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Analizando información...")
                            .font(.title3).fontWeight(.bold).foregroundColor(primaryNavy).padding(.bottom, 5)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            ChecklistRow(text: "Preparando archivos y texto...", isCompleted: viewModel.loadingStep >= 1)
                            ChecklistRow(text: "Extrayendo contexto...", isCompleted: viewModel.loadingStep >= 2)
                            ChecklistRow(text: "Analizando...", isCompleted: viewModel.loadingStep >= 3)
                            ChecklistRow(text: "Cruzando fuentes oficiales...", isCompleted: viewModel.loadingStep >= 4)
                            ChecklistRow(text: "Generando analisis...", isCompleted: viewModel.loadingStep >= 5)
                        }
                    }
                    .padding(30)
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(25)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                    .padding(.horizontal, 30)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: imageSourceType, previewImage: $previewImage, imageData: $viewModel.selectedImageData)
        }
        .sheet(isPresented: $showForensicsPicker) {
            ImagePicker(sourceType: forensicsSourceType, previewImage: $forensicsPreview, imageData: $forensicsImageData)
                .onDisappear {
                    guard let imgData = forensicsImageData else { return }
                    forensicsLoading = true
                    Task {
                        do {
                            let result = try await forensicsService.analyze(imageData: imgData)
                            await MainActor.run {
                                forensicsResult  = result
                                forensicsLoading = false
                                showForensicsResult = true
                                forensicsImageData = nil
                                forensicsPreview   = nil
                            }
                        } catch {
                            await MainActor.run { forensicsLoading = false }
                        }
                    }
                }
        }
        .confirmationDialog("Selecciona la imagen a analizar", isPresented: $showForensicsPicker, titleVisibility: .visible) {
            Button("Tomar Foto") { forensicsSourceType = .camera }
            Button("Elegir de la Galería") { forensicsSourceType = .photoLibrary }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("Selecciona una opción", isPresented: $showImageOptions, titleVisibility: .visible) {
            Button("Tomar Foto") {
                imageSourceType = .camera
                showImagePicker = true
            }
            Button("Elegir de la Galería") {
                imageSourceType = .photoLibrary
                showImagePicker = true
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

// COMPONENTES AUXILIARES

struct ChecklistRow: View {
    let text: String
    let isCompleted: Bool
    let primaryNavy = Color(red: 13/255, green: 60/255, blue: 135/255)
    
    var body: some View {
        HStack(spacing: 15) {
            ZStack {
                Circle()
                    .stroke(isCompleted ? primaryNavy : Color.gray.opacity(0.5), lineWidth: 2)
                    .frame(width: 24, height: 24)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(primaryNavy)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(isCompleted ? .primary : .secondary)
                .animation(.easeInOut, value: isCompleted)
            
            Spacer()
        }
    }
}

//ImagePicker Mejorado
struct ImagePicker: UIViewControllerRepresentable {
    var sourceType: UIImagePickerController.SourceType
    @Binding var previewImage: UIImage?
    @Binding var imageData: Data?
    
    @Environment(\.presentationMode) private var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        
        // APAGAMOS LA EDICIÓN: Esto evita que la interfaz se ponga "roñosa" o se trabe en el iPhone físico
        picker.allowsEditing = false
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            
            // Usamos la imagen original porque apagamos la edición
            if let image = info[.originalImage] as? UIImage {
                parent.previewImage = image
                
                //Reducimos el tamaño internamente para que no rompa la memoria o sature la API
                let resizedImage = resizeImage(image: image, targetSize: CGSize(width: 800, height: 800))
                parent.imageData = resizedImage.jpegData(compressionQuality: 0.7)
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        // Función auxiliar para achicar imágenes gigantes
        private func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
            let size = image.size
            let widthRatio  = targetSize.width  / size.width
            let heightRatio = targetSize.height / size.height
            
            // Mantener la proporción original
            let ratio = min(widthRatio, heightRatio)
            let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            
            let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: rect)
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return newImage ?? image
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: SavedArticle.self, inMemory: true)
}
