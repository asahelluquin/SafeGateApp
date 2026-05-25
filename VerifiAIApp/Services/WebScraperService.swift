import Foundation

class WebScraperService {
    
    //Función original para extraer og:image
    func fetchOGImage(from urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            // Descargamos el HTML de la página como texto
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let htmlString = String(data: data, encoding: .utf8) else { return nil }
            
            // Usamos una "Regex" rápida para buscar el tag og:image
            let pattern = "<meta[^>]*property=[\"']og:image[\"'][^>]*content=[\"'](.*?)[\"']"
            
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: htmlString.utf16.count)
            
            if let match = regex.firstMatch(in: htmlString, options: [], range: range) {
                // Si encontramos coincidencia, extraemos el contenido del grupo 1
                if let contentRange = Range(match.range(at: 1), in: htmlString) {
                    let extractedUrl = String(htmlString[contentRange])
                    print("🖼️ Imagen encontrada con éxito: \(extractedUrl)")
                    return extractedUrl
                }
            }
            
        } catch {
            print("❌ Error scrapeando la imagen: \(error)")
        }
        
        return nil // No se encontró og:image o hubo error
    }
    
    //Función para extraer el artículo con Jina
    func fetchArticleContent(from urlString: String) async -> String? {
        // Limpiamos la URL para que no truene si tiene espacios o caracteres raros
        guard let encodedUrl = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://r.jina.ai/\(encodedUrl)") else {
            print("❌ URL inválida para Jina Reader")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        //Jina pide un header para que devuelva un formato más amigable para LLMs.
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            print("⏳ Extrayendo texto de la noticia con Jina...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("⚠️ No se recibió una respuesta HTTP válida de Jina.")
                return nil
            }
            
            if httpResponse.statusCode == 200 {
                // Convertimos la respuesta a un String (Suele venir en formato Markdown)
                if let articleText = String(data: data, encoding: .utf8) {
                    print("✅ Contenido de la noticia extraído exitosamente.")
                    return articleText
                }
            } else {
                print("⚠️ Jina respondió con código de error: \(httpResponse.statusCode)")
            }
            
        } catch {
            print("❌ Error de red extrayendo el contenido: \(error.localizedDescription)")
        }
        
        return nil
    }
}
