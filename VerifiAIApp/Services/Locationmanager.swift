import Foundation
import CoreLocation
import Combine 

// MARK: - Location Manager

@MainActor
class LocationManager: NSObject, ObservableObject {

    @Published var authStatus:    CLAuthorizationStatus = .notDetermined
    @Published var detectedState: MexicanState?
    @Published var detectedCity:  String?       // municipio/ciudad
    @Published var isLocating:    Bool   = false
    @Published var locationError: String? = nil

    /// Nombre a usar en búsquedas de noticias (municipio si existe, si no estado)
    var searchCity: String? { detectedCity }

    /// Texto completo para mostrar en UI
    var displayText: String {
        switch (detectedCity, detectedState) {
        case (let c?, let s?): return "\(c), \(s.rawValue)"
        case (nil, let s?):    return s.rawValue
        case (let c?, nil):    return c
        default:               return ""
        }
    }

    private let manager  = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate        = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authStatus = manager.authorizationStatus
    }

    // MARK: - Pública

    func requestDetection() {
        locationError = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startLocating()
        case .denied, .restricted:
            locationError = "Permiso denegado. Actívalo en Configuración › SafeGate › Ubicación."
        @unknown default: break
        }
    }

    func clearLocation() {
        detectedState = nil
        detectedCity  = nil
        locationError = nil
    }

    // MARK: - Privada

    private func startLocating() {
        guard !isLocating else { return }
        isLocating = true
        manager.requestLocation()
    }

    private func reverseGeocode(_ location: CLLocation) async {
        do {
            // preferredLocale en español → nombres en español
            let placemarks = try await geocoder.reverseGeocodeLocation(
                location,
                preferredLocale: Locale(identifier: "es_MX")
            )
            guard let p = placemarks.first else {
                locationError = "No se pudo identificar la ubicación."
                isLocating = false
                return
            }

            // Jerarquía para el municipio:
            // locality             → Ciudad/municipio principal (ej: "Guadalajara")
            // subAdministrativeArea → Municipio alternativo (ej: "Tala")
            // subLocality          → Colonia/barrio (muy granular, no siempre disponible)
            detectedCity = p.locality ?? p.subAdministrativeArea

            // Estado
            if let area = p.administrativeArea {
                detectedState = MexicanState.from(clName: area)
                if detectedState == nil {
                    // Fallback: a veces CLGeocoder retorna el código postal como área
                    locationError = "Estado '\(area)' no reconocido. Selecciónalo manualmente."
                }
            } else {
                locationError = "No se pudo determinar el estado."
            }

            if !displayText.isEmpty {
                print("📍 Ubicación: \(displayText)")
            }

        } catch {
            locationError = "Error de geocodificación. Verifica tu conexión."
        }
        isLocating = false
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                self.startLocating()
            } else if manager.authorizationStatus == .denied {
                self.isLocating    = false
                self.locationError = "Permiso denegado. Actívalo en Configuración › SafeGate."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        Task { @MainActor in await self.reverseGeocode(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            self.isLocating    = false
            if let clErr = error as? CLError, clErr.code == .denied {
                self.locationError = "Permiso denegado."
            } else {
                self.locationError = "No se pudo obtener tu ubicación. ¿Tienes señal GPS?"
            }
        }
    }
}

// MARK: - MexicanState mapping

extension MexicanState {

    static func from(clName raw: String) -> MexicanState? {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                   .lowercased()
                   .folding(options: .diacriticInsensitive, locale: .current)

        // Coincidencia directa con el rawValue
        if let direct = MexicanState.allCases.first(where: {
            $0.rawValue.lowercased()
             .folding(options: .diacriticInsensitive, locale: .current) == n
        }) { return direct }

        // Tabla de palabras clave incluyendo municipios conocidos
        let table: [(keys: [String], state: MexicanState)] = [
            (["ciudad de mexico","cdmx","df","distrito federal","mexico city",
              "cuauhtemoc","iztapalapa","gustavo a","miguel hidalgo",
              "benito juarez","coyoacan","xochimilco","tlahuac",
              "azcapotzalco","tlalpan","alvaro obregon","milpa alta",
              "venustiano carranza","la magdalena"],                          .cdmx),
            (["estado de mexico","estado de mexique","mexico state",
              "ecatepec","nezahualcoyotl","toluca","naucalpan",
              "tlalnepantla","chimalhuacan","texcoco","chalco"],              .estadoDeMexico),
            (["jalisco","guadalajara","zapopan","tlaquepaque","tonala",
              "puerto vallarta","lagos de moreno","tepatitlan",
              "tala","ameca","ocotlan","tlajomulco","el salto",
              "san pedro tlaquepaque","chapala","la barca"],                 .jalisco),
            (["nuevo leon","monterrey","san nicolas","apodaca",
              "general escobedo","santa catarina","guadalupe nl",
              "san pedro garza","juarez nl","garcia nl"],                    .nuevoLeon),
            (["baja california sur","bcs","la paz","los cabos",
              "cabo san lucas","san jose del cabo","loreto bcs"],            .bajaCaliforniaSur),
            (["baja california","tijuana","mexicali","ensenada",
              "tecate","rosarito","san quintin"],                            .bajaCalifornia),
            (["campeche","ciudad del carmen","champoton"],                   .campeche),
            (["chiapas","tuxtla gutierrez","san cristobal","tapachula",
              "comitan","palenque","ocosingo"],                              .chiapas),
            (["chihuahua","ciudad juarez","juarez chi","delicias",
              "hidalgo del parral","cuauhtemoc chi","casas grandes",
              "nuevo casas grandes"],                                        .chihuahua),
            (["coahuila","saltillo","torreon","monclova","piedras negras",
              "acuna","ciudad acuna"],                                       .coahuila),
            (["colima","manzanillo","tecomán"],                              .colima),
            (["durango","victoria de durango","gomez palacio",
              "lerdo dgo"],                                                  .durango),
            (["guanajuato","leon","irapuato","celaya","salamanca",
              "silao","san miguel de allende","guanajuato city",
              "acambaro"],                                                   .guanajuato),
            (["guerrero","acapulco","chilpancingo","zihuatanejo",
              "iguala","taxco"],                                             .guerrero),
            (["hidalgo","pachuca","tulancingo","tula","actopan"],           .hidalgo),
            (["michoacan","morelia","lazaro cardenas","zamora",
              "uruapan","apatzingan","zitacuaro"],                          .michoacan),
            (["morelos","cuernavaca","cuautla","jiutepec",
              "temixco","yautepec"],                                        .morelos),
            (["nayarit","tepic","bahia de banderas","bucerías",
              "compostela","san blas"],                                      .nayarit),
            (["oaxaca","santa lucia","salina cruz","juchitan",
              "tuxtepec","huajuapan","tehuantepec"],                        .oaxaca),
            (["puebla","san andres cholula","cholula","tehuacan",
              "atlixco","izucar","huejotzingo"],                            .puebla),
            (["queretaro","el marques","san juan del rio",
              "corregidora","pedro escobedo"],                               .queretaro),
            (["quintana roo","cancun","playa del carmen","cozumel",
              "tulum","chetumal","solidaridad","isla mujeres","benito juarez qr",
              "bacalar"],                                                    .quintanaRoo),
            (["san luis potosi","slp","ciudad valles","matehuala",
              "rioverde","soledad de graciano"],                             .sanLuisPotosi),
            (["sinaloa","culiacan","mazatlan","los mochis",
              "guasave","guamuchil","navolato"],                            .sinaloa),
            (["sonora","hermosillo","ciudad obregon","nogales",
              "navojoa","guaymas","san luis rio colorado",
              "caborca"],                                                    .sonora),
            (["tabasco","villahermosa","centro tab","comalcalco",
              "cardenas tab","paraiso tab"],                                 .tabasco),
            (["tamaulipas","reynosa","matamoros","nuevo laredo",
              "tampico","victoria tam","ciudad mante","altamira"],          .tamaulipas),
            (["tlaxcala","apizaco","huamantla","calpulalpan"],              .tlaxcala),
            (["veracruz","xalapa","coatzacoalcos","boca del rio",
              "minatitlan","poza rica","tuxpan","cordoba","orizaba",
              "veracruz city","san andres tuxtla"],                         .veracruz),
            (["yucatan","merida","valladolid","tizimin",
              "progreso","uman","kanasín"],                                 .yucatan),
            (["zacatecas","guadalupe zac","fresnillo",
              "jerez","rio grande","zacatecas city"],                       .zacatecas),
            (["aguascalientes","jesus maria","calvillo",
              "pabellon de arteaga"],                                       .aguascalientes),
        ]

        for (keys, state) in table {
            if keys.contains(where: { n.contains($0) }) { return state }
        }
        return nil
    }
}
