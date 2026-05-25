import UIKit
import SwiftUI

// MARK: - Share Extension Entry Point
//
// CONFIGURACIÓN EN XCODE (pasos necesarios):
//
// 1. File → New → Target → iOS → Share Extension → "SafeGateShare"
// 2. Reemplaza el ShareViewController.swift generado con este archivo
// 3. Agrega ShareAnalysisView.swift al target "SafeGateShare"
// 4. En el Info.plist del target SafeGateShare, reemplaza NSExtensionActivationRule con:
//
//    <key>NSExtensionActivationRule</key>
//    <dict>
//        <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
//        <integer>1</integer>
//        <key>NSExtensionActivationSupportsText</key>
//        <integer>1</integer>
//    </dict>
//
// 5. En Build Phases del target SafeGateShare, asegúrate de que
//    ShareAnalysisView.swift esté en "Compile Sources"

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extractContent { [weak self] content in
            guard let self else { return }
            let analysisView = ShareAnalysisView(
                sharedContent: content,
                onDismiss: { self.extensionContext?.completeRequest(returningItems: nil) }
            )
            let host = UIHostingController(rootView: analysisView)
            self.addChild(host)
            self.view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: self.view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
            ])
            host.didMove(toParent: self)
        }
    }

    // Extrae URL o texto del contexto de la extensión
    private func extractContent(completion: @escaping (String) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion("")
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {

                // Primero intentamos URL (Safari, Chrome, etc.)
                if provider.hasItemConformingToTypeIdentifier("public.url") {
                    provider.loadItem(forTypeIdentifier: "public.url", options: nil) { data, _ in
                        DispatchQueue.main.async {
                            if let url = data as? URL {
                                completion(url.absoluteString)
                            } else if let urlString = data as? String {
                                completion(urlString)
                            }
                        }
                    }
                    return
                }

                // Si no hay URL, tomamos texto plano (WhatsApp, Notas, etc.)
                if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                    provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { data, _ in
                        DispatchQueue.main.async {
                            completion((data as? String) ?? "")
                        }
                    }
                    return
                }
            }
        }
        completion("")
    }
}
