import Foundation

// Esta estructura representa lo que nosotros le enviaremos a la API
struct ArticleRequest: Codable {
    let content: String // Aquí irá el texto o enlace que el usuario pegue en el TextField
}
