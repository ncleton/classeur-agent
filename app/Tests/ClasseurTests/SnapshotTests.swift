import AppKit
import SwiftUI
import XCTest
@testable import Classeur

/// Rend les écrans de Classeur hors écran à partir de données réelles enregistrées par le moteur.
/// CLASSEUR_SNAPSHOT_HOME=<dossier Classeur> CLASSEUR_SNAPSHOT_RUN=<traiter.jsonl> CLASSEUR_SNAPSHOT_OUT=<dossier> swift test
@MainActor
final class SnapshotTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func testRenderScreens() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["CLASSEUR_SNAPSHOT_HOME"], let runEvents = env["CLASSEUR_SNAPSHOT_RUN"], let outDir = env["CLASSEUR_SNAPSHOT_OUT"] else {
            throw XCTSkip("CLASSEUR_SNAPSHOT_HOME, CLASSEUR_SNAPSHOT_RUN et CLASSEUR_SNAPSHOT_OUT sont requis.")
        }
        let out = URL(fileURLWithPath: outDir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let model = AppModel.shared

        struct Onto: Decodable { let classeurs: [Classeur] }
        struct Sample: Decodable { let mails: [InboxItem]; let affectations: [String: Affectation] }
        let onto = try decoder.decode(Onto.self, from: Data(contentsOf: URL(fileURLWithPath: home + "/ontologie.json")))
        let sample = try decoder.decode(Sample.self, from: Data(contentsOf: URL(fileURLWithPath: home + "/echantillon.json")))
        XCTAssertGreaterThanOrEqual(onto.classeurs.count, 2)
        XCTAssertEqual(sample.mails.count, sample.affectations.count, "Chaque mail de l'échantillon doit avoir un classeur.")

        model.unread = 0
        model.totalBoite = 160
        model.ontologie = onto.classeurs
        model.echantillon = sample.mails
        model.phase = .decouverte

        // Classement en cours : une partie de la pile est déjà rangée.
        let moitie = sample.mails.count / 2
        model.affectations = [:]
        model.colonnes = [:]
        for item in sample.mails.prefix(moitie) {
            let a = sample.affectations[item.id]!
            model.affectations[item.id] = a
            model.colonnes[a.classeur, default: []].insert(item.id, at: 0)
        }
        model.pile = sample.mails.dropFirst(moitie).map(\.id)
        model.etape = .classement
        try snap("1-decouverte-classement", out)

        // Classement terminé : le kanban des classeurs.
        for item in sample.mails.dropFirst(moitie) {
            let a = sample.affectations[item.id]!
            model.affectations[item.id] = a
            model.colonnes[a.classeur, default: []].insert(item.id, at: 0)
        }
        model.pile = []
        model.etape = .edition
        try snap("2-classeurs", out)

        model.reglageNouveau = false
        model.reglage = onto.classeurs[1]
        try snap("3-reglages-classeur", out)
        model.reglage = nil

        // Traitement réel enregistré par le moteur.
        let events = try String(contentsOfFile: runEvents, encoding: .utf8)
            .split(separator: "\n")
            .map { try decoder.decode(EngineEvent.self, from: Data($0.utf8)) }
        let run = try XCTUnwrap(events.last(where: { $0.event == "termine" })?.run)
        model.inbox = run.mails.map { InboxItem(id: $0.id, de: $0.de, objet: $0.objet, date: $0.date, apercu: String(($0.texte ?? "").prefix(120))) }
        model.total = run.total
        let half = run.mails.prefix(run.total / 2)
        model.analysed = Dictionary(uniqueKeysWithValues: half.map { ($0.id, $0) })
        model.classes = Dictionary(uniqueKeysWithValues: half.map { ($0.id, $0.classeur) })
        model.feed = Array(half.reversed())
        model.lus = half.count
        model.lastAnalysedId = half.last?.id
        model.phase = .lecture
        try snap("4-lecture", out)

        model.compteurs = run.compteurs
        model.titre = run.titre
        model.lus = run.total
        model.ranger = true
        model.phase = .compris
        try snap("5-compris", out)

        model.cards = run.mails
        model.visible = Set(run.mails.map(\.id))
        model.runId = run.id
        model.phase = .termine
        try snap("6-termine", out)

        model.errorMessage = "Apple Mail ne peut plus lire le mot de passe de ton compte : le trousseau « session » de macOS est verrouillé, donc Mail n'arrive pas à se connecter au serveur pour créer ou remplir les dossiers. Clique sur « Déverrouiller le trousseau », saisis le mot de passe de ta session Mac, puis relance le traitement."
        model.errorCode = "trousseau_verrouille"
        model.phase = .erreur
        try snap("7-erreur-compte", out)
    }

    /// CLASSEUR_SNAPSHOT_OUT=<dossier> swift test --filter testRenderConfiguration
    func testRenderConfiguration() throws {
        guard let outDir = ProcessInfo.processInfo.environment["CLASSEUR_SNAPSHOT_OUT"] else {
            throw XCTSkip("CLASSEUR_SNAPSHOT_OUT est requis.")
        }
        let out = URL(fileURLWithPath: outDir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let prerequis = Prerequis.shared
        AppModel.shared.phase = .configuration

        prerequis.mails = .manquant("Classeur n'a pas encore accès à vos mails.")
        prerequis.pilotage = .manquant("Autorisez Classeur à ranger vos mails dans Mail.")
        prerequis.codex = .ok
        prerequis.cle = .manquant("Clés API manquantes pour l'agent « Classeur » : TYPESAFE_API_KEY (Clé Jev).")
        try snap("8-configuration-mails", out, configuration: EcranConfiguration(verifier: false, etape: .mails))

        prerequis.mails = .ok
        prerequis.pilotage = .ok
        prerequis.cleLien = URL(string: "https://libreagent.example/agents/1/keys")
        try snap("9-configuration-cle", out, configuration: EcranConfiguration(verifier: false, etape: .cle))

        prerequis.cle = .ok
        try snap("10-configuration-prete", out, configuration: EcranConfiguration(verifier: false, etape: .cle))
    }

    private func snap(_ name: String, _ out: URL, configuration: EcranConfiguration? = nil) throws {
        let model = AppModel.shared
        let view = ZStack {
            Fond()
            VStack(spacing: 0) {
                BarreHaute()
                Group {
                    switch model.phase {
                    case .demarrage: Demarrage()
                    case .configuration: configuration ?? EcranConfiguration(verifier: false)
                    case .accueil: Accueil()
                    case .decouverte: Decouverte()
                    case .connexion, .lecture, .compris: Lecture()
                    case .rangement, .termine: Tableau()
                    case .erreur: Erreur()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let c = model.reglage { ReglagesClasseur(classeur: c, nouveau: model.reglageNouveau) }
        }
        .preferredColorScheme(.dark)

        let size = NSSize(width: 1440, height: 880)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(1.4))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent("\(name).png"))
    }
}
