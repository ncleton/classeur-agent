import Foundation
import SwiftUI

/// Un classeur : un concept de l'ontologie de la boîte mail, avec sa définition et son action.
struct Classeur: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var nom: String
    var definition: String
    var inclure: [String]
    var exclure: [String]
    var exemples: [String]
    var action: String
    var dossier: String
    var couleur: String
    var symbole: String
    var transfertEmail: String
    var transfertAuto: Bool

    static let aVerifierId = "a_verifier"

    static let aVerifier = Classeur(
        id: aVerifierId, nom: "À vérifier",
        definition: "Les mails pour lesquels le classement n'est pas assez sûr. Ils restent dans ta boîte de réception pour que tu tranches.",
        inclure: [], exclure: [], exemples: [], action: aVerifierId, dossier: "",
        couleur: "corail", symbole: "questionmark.circle.fill", transfertEmail: "", transfertAuto: false
    )

    static func nouveau() -> Classeur {
        Classeur(
            id: "", nom: "", definition: "", inclure: [], exclure: [], exemples: [], action: "ranger",
            dossier: "", couleur: "bleu", symbole: "archivebox.fill", transfertEmail: "", transfertAuto: false
        )
    }

    var teinte: Color { Theme.palette[couleur] ?? Theme.palette["violet"]! }
    var estVirtuel: Bool { id == Classeur.aVerifierId }

    var actionLibelle: String {
        switch action {
        case "repondre": "Préparer une réponse"
        case "transferer": "Transférer"
        case "ranger": "Ranger"
        case "archiver": "Archiver"
        default: "Laisser dans la boîte"
        }
    }
}

struct Affectation: Decodable, Equatable {
    let classeur: String
    let suggestion: String?
    let confiance: Double?
    let incertain: Bool
    var manuel: Bool? = nil
}

struct MailCard: Decodable, Identifiable, Equatable {
    let id: String
    var classeur: String
    var action: String
    let suggestion: String?
    let confiance: Double?
    let expediteur: String
    let objetCourt: String
    var ligne: String
    var etiquette: String
    let urgent: Bool
    var reponse: String
    var statut: String
    var dossier: String
    var transfertEmail: String
    let compte: String
    let boite: String
    let messageId: String
    let de: String
    let a: [String]
    let date: String
    let objet: String
    let texte: String?
}

struct InboxItem: Decodable, Identifiable, Equatable {
    let id: String
    let de: String
    let objet: String
    let date: String
    let apercu: String
    var messageId: String?
}

struct RunPayload: Decodable {
    let id: String
    let portee: String?
    let range: Bool?
    let total: Int
    let mails: [MailCard]
    let compteurs: [String: Int]
    let titre: String
    let classeurs: [Classeur]?
}

struct EngineEvent: Decodable {
    let event: String
    let phase: String?
    let etape: String?
    let runId: String?
    let total: Int?
    let lus: Int?
    let mail: MailCard?
    let mails: [InboxItem]?
    let compteurs: [String: Int]?
    let titre: String?
    let proprietaire: String?
    let classeur: String?
    let suggestion: String?
    let confiance: Double?
    let incertain: Bool?
    let nombre: Int?
    let dossier: String?
    let run: RunPayload?
    let classeurs: [Classeur]?
    let echantillon: [InboxItem]?
    let affectations: [String: Affectation]?
    let version: Int?
    let versionEchantillon: Int?
    let message: String?
    let code: String?
    let nonLus: Int?
    let dejaTraites: Int?
    let deja: Bool?
    let id: String?
    let le: String?
    let statut: String?
    let chemin: String?
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let titre: String
    let detail: String
}

enum Format {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ value: String) -> Date? { iso.date(from: value) }

    static func heure(_ value: String) -> String {
        guard let d = date(value) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "dd/MM"
        return f.string(from: d)
    }

    static func longue(_ value: String) -> String {
        guard let d = date(value) else { return value }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM 'à' HH:mm"
        return f.string(from: d)
    }

    static func maintenant() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    static func nom(_ from: String) -> String {
        if let range = from.range(of: "<") {
            let name = from[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !name.isEmpty { return name }
            return from[range.upperBound...].replacingOccurrences(of: ">", with: "")
        }
        return from
    }

    static func pluriel(_ n: Int, _ singulier: String, _ pluriel: String) -> String {
        "\(n) " + (n > 1 ? pluriel : singulier)
    }

    static func pourcent(_ value: Double?) -> String {
        guard let value else { return "" }
        return "\(Int((value * 100).rounded())) %"
    }

    /// Raccourcit les liens de suivi interminables pour garder le mail lisible.
    static func lisible(_ texte: String) -> String {
        var result = texte
        let rules: [(String, String)] = [
            ("<https?://[^>\\s]{60,}>", ""),
            ("https?://([^/\\s]+)[^\\s]{70,}", "[lien $1]"),
            ("\\n{3,}", "\n\n"),
        ]
        for (pattern, template) in rules {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
