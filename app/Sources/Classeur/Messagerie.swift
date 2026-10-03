import AppKit

/// Messagerie dans laquelle Classeur ouvre les mails et les réponses préparées.
/// Sur Mac, Classeur lit la boîte d'Apple Mail : c'est donc Apple Mail qui ouvre les mails.
/// Outlook est la messagerie de la version Windows.
enum Messagerie: String, CaseIterable, Identifiable {
    case appleMail = "apple_mail"
    case outlook

    static let cle = "messagerie"

    static var enregistree: Messagerie {
        let choix = Messagerie(rawValue: UserDefaults.standard.string(forKey: cle) ?? "") ?? .appleMail
        return choix.disponible ? choix : .appleMail
    }

    var id: String { rawValue }

    var nom: String {
        switch self {
        case .appleMail: "Apple Mail"
        case .outlook: "Outlook"
        }
    }

    private var bundleId: String {
        switch self {
        case .appleMail: "com.apple.mail"
        case .outlook: "com.microsoft.Outlook"
        }
    }

    var installee: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil }

    var disponible: Bool { self == .appleMail && installee }

    var libelleMenu: String {
        switch self {
        case .appleMail: installee ? "Apple Mail" : "Apple Mail (introuvable sur ce Mac)"
        case .outlook: installee ? "Outlook (version Windows uniquement)" : "Outlook (non installé sur ce Mac)"
        }
    }

    var raisonIndisponible: String {
        switch self {
        case .appleMail: "Apple Mail est introuvable dans /System/Applications. Réinstalle macOS Mail pour utiliser Classeur."
        case .outlook: installee
            ? "Sur Mac, Classeur lit tes mails dans Apple Mail et les ouvre dans Apple Mail. Outlook est pris en charge par la version Windows."
            : "Outlook n'est pas installé sur ce Mac. Choisis Apple Mail dans le menu Messagerie."
        }
    }
}
