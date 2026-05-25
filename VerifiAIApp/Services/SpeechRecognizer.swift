import Foundation
import Speech
import AVFoundation
import Combine

class SpeechRecognizer: ObservableObject {
    // Usamos el idioma español de México 
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es_MX"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    // Variables que la interfaz observará para actualizarse
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    
    func startTranscribing() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                if authStatus == .authorized {
                    self.transcribe()
                } else {
                    print("Permisos de voz denegados por el usuario.")
                }
            }
        }
    }
    
    private func transcribe() {
        do {
            // Cancelamos cualquier tarea anterior por si acaso
            recognitionTask?.cancel()
            recognitionTask = nil
            
            // Configuramos la sesión de audio del iPhone
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            
            let node = audioEngine.inputNode
            let recordingFormat = node.outputFormat(forBus: 0)
            
            // "Enganchamos" el micrófono para capturar el audio
            node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            DispatchQueue.main.async {
                self.isRecording = true
                self.transcript = "" // Limpiamos el texto al empezar a hablar
            }
            
            // Iniciamos la traducción de voz a texto
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { result, error in
                if let result = result {
                    DispatchQueue.main.async {
                        self.transcript = result.bestTranscription.formattedString
                    }
                }
                
                if error != nil || result?.isFinal == true {
                    self.stopTranscribing()
                }
            }
        } catch {
            print("Error al iniciar el motor de audio: \(error.localizedDescription)")
            self.stopTranscribing()
        }
    }
    
    func stopTranscribing() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
        }
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        recognitionRequest = nil
        recognitionTask = nil
    }
}
