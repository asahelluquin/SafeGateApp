import SwiftUI

struct OptionsView: View {
    // @AppStorage guarda el idioma en la memoria del iPhone.
    // Si cierras la app, recordará si lo dejaste en Inglés o Español.
    @AppStorage("selectedLanguage") private var idiomaSeleccionado = "Español"

    let idiomas = ["Español", "English"]
    
    // Control para la alerta de borrado
    @State private var mostrarAlertaBorrar = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Fondo base de la app
                Color.appBackground.ignoresSafeArea()
                
                Form {
                    // SECCIÓN 1: Preferencias
                    Section {
                        Picker(selection: $idiomaSeleccionado) {
                            ForEach(idiomas, id: \.self) { idioma in
                                Text(idioma).tag(idioma)
                            }
                        } label: {
                            Label {
                                Text("Idioma de Resultados")
                                    .foregroundColor(.deepNavy)
                            } icon: {
                                Image(systemName: "globe")
                                    .foregroundColor(.deepNavy)
                            }
                        }
                        .tint(.deepNavy)
                    } header: {
                        Text("Preferencias")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.deepNavy.opacity(0.6))
                    }
                    .listRowBackground(Color.white)

                    // SECCIÓN ESTADÍSTICAS
                    Section {
                        NavigationLink(destination: DashboardView()) {
                            Label {
                                Text("Mis Estadísticas")
                                    .foregroundColor(.deepNavy)
                            } icon: {
                                Image(systemName: "chart.bar.xaxis")
                                    .foregroundColor(.deepNavy)
                            }
                        }
                    } header: {
                        Text("Análisis Personal")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.deepNavy.opacity(0.6))
                    }
                    .listRowBackground(Color.white)
                    
                    // SECCIÓN 2: Almacenamiento
                    Section {
                        Button(action: {
                            mostrarAlertaBorrar = true
                        }) {
                            Label {
                                Text("Borrar Historial de Análisis")
                                    .foregroundColor(.red)
                            } icon: {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        .alert("¿Borrar historial?", isPresented: $mostrarAlertaBorrar) {
                            Button("Cancelar", role: .cancel) { }
                            Button("Borrar", role: .destructive) {
                                // Aquí irá la lógica de SwiftData más adelante
                                print("Historial borrado")
                            }
                        } message: {
                            Text("Esta acción no se puede deshacer y eliminará todas las noticias que has guardado.")
                        }
                    } header: {
                        Text("Almacenamiento y Datos")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.deepNavy.opacity(0.6))
                    }
                    .listRowBackground(Color.white)
                    
                    // SECCIÓN 3: Legal y Tecnología
                    Section {
                        NavigationLink(destination: Text("SafeGate no es un simple buscador de noticias; es un ecosistema avanzado de auditoría de información que utiliza una arquitectura multi-agente para diseccionar la veracidad de lo que lees en tiempo real.").padding()) {
                            Label {
                                Text("Acerca de la IA")
                                    .foregroundColor(.deepNavy)
                            } icon: {
                                Image(systemName: "cpu")
                                    .foregroundColor(.deepNavy)
                            }
                        }
                        
                        NavigationLink(destination:
                            ScrollView {
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("Aviso de Privacidad")
                                        .font(.title2.bold())
                                        .foregroundColor(.deepNavy)
                                    
                                    Text("Última actualización: Abril 2026")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Divider()
                                    
                                    Text("Privacidad por Diseño")
                                        .fontWeight(.bold)
                                    Text("En SafeGate, tus datos no salen de tu control. El procesamiento de IA se realiza en tiempo real y el historial reside únicamente en tu iPhone.")
                                    
                                    Text("Proveedores de IA")
                                        .fontWeight(.bold)
                                    Text("Utilizamos las APIs de Google y xAI para el análisis. Ninguno de estos proveedores utiliza tus consultas para entrenar modelos externos.")
                                    
                                    Text("Tus Derechos")
                                        .fontWeight(.bold)
                                    Text("Puedes borrar tu historial en cualquier momento. SafeGate no recolecta telemetría ni datos de identificación personal.")
                                }
                                .padding()
                            }
                            .background(Color.appBackground)
                        ) {
                            Label("Aviso de Privacidad", systemImage: "hand.raised.fill")
                                .foregroundColor(.deepNavy)
                        }
                    } header: {
                        Text("Legal & Tecnología")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.deepNavy.opacity(0.6))
                    }
                    .listRowBackground(Color.white)
                    
                    // SECCIÓN 4: Firma
                    Section {
                        EmptyView() // Invisible, solo para el footer
                    } footer: {
                        VStack(spacing: 8) {
                            Image(systemName: "terminal.fill")
                                .font(.title)
                                .foregroundColor(.deepNavy.opacity(0.4))
                                .padding(.bottom, 4)
                            
                            Text("Desarrollado con ❤️ para el Hackathon 2026")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            
                            Text("© Derechos reservados tacos de barbacoa")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.deepNavy.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .multilineTextAlignment(.center)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Opciones")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        Text("SafeGate")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.deepNavy)
                        
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                }
            }
        }
    }
}

#Preview {
    OptionsView()
}
