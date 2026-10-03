import AppKit
import CoreServices
import SwiftUI

/// Prérequis de Classeur sur ce Mac, relus en continu : l'utilisateur peut retirer une autorisation à tout moment.
@MainActor
@Observable
final class Prerequis {
    static let shared = Prerequis()
    static let cleTermine = "classeur.configuration.terminee"

    enum Etat: Equatable { case inconnu, verification, ok, manquant(String) }
    enum Etape: Int, CaseIterable, Identifiable {
        case mails, pilotage, codex, cle
        var id: Int { rawValue }
        var titre: String {
            switch self {
            case .mails: "Lire vos mails"
            case .pilotage: "Ranger dans Mail"
            case .codex: "Codex"
            case .cle: "Clé Jev"
            }
        }
        var symbole: String {
            switch self {
            case .mails: "tray.full.fill"
            case .pilotage: "folder.fill.badge.gearshape"
            case .codex: "sparkles"
            case .cle: "key.fill"
            }
        }
    }

    var mails: Etat = .inconnu
    var pilotage: Etat = .inconnu
    var codex: Etat = .inconnu
    var cle: Etat = .inconnu
    var cleLien: URL?
    var codexChemin: String?
    var connexionCodex = false
    var pilotageRefuse = false
    private var surveillance: Task<Void, Never>?

    func etat(_ etape: Etape) -> Etat {
        switch etape {
        case .mails: mails
        case .pilotage: pilotage
        case .codex: codex
        case .cle: cle
        }
    }

    var toutEstPret: Bool { Etape.allCases.allSatisfy { etat($0) == .ok } }

    /// Vérifications locales, sans réseau ni fenêtre système.
    func verifierLocal() async {
        await verifierDiagnostic()
        verifierPilotage(demander: false)
    }

    func verifierDiagnostic() async {
        do {
            try await Engine.run(["diagnostic"]) { event in
                guard event.event == "diagnostic" else { return }
                if let mail = event.accesMail {
                    self.mails = !mail.lisible
                        ? .manquant("Classeur n'a pas encore accès à vos mails.")
                        : mail.comptes ? .ok : .manquant("Apple Mail n'a aucun compte sur ce Mac. Ajoutez votre compte dans Mail, puis revenez ici.")
                }
                if let codex = event.codex {
                    self.codexChemin = codex.chemin
                    self.codex = !codex.installe
                        ? .manquant("Codex n'est pas installé sur ce Mac.")
                        : codex.connecte ? .ok : .manquant("Codex est installé mais pas connecté à votre compte ChatGPT.")
                }
            }
        } catch {
            mails = .manquant(error.localizedDescription)
        }
    }

    /// Autorisation d'envoyer des événements Apple à Mail (Réglages Système > Automatisation).
    func verifierPilotage(demander: Bool) {
        let mailOuvert = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
        guard mailOuvert || demander else {
            if pilotage == .inconnu { pilotage = .manquant("Autorisez Classeur à ranger vos mails dans Mail.") }
            return
        }
        if demander { pilotage = .verification }
        Task {
            if !mailOuvert { await Self.ouvrirMailEnArrierePlan() }
            let statut = await Task.detached { Self.permissionMail(demander: demander) }.value
            switch statut {
            case noErr:
                pilotage = .ok
                pilotageRefuse = false
            case OSStatus(errAEEventNotPermitted):
                pilotageRefuse = true
                pilotage = .manquant("macOS a refusé à Classeur le droit de piloter Mail.")
            default:
                pilotage = .manquant("Autorisez Classeur à ranger vos mails dans Mail.")
            }
        }
    }

    nonisolated static func permissionMail(demander: Bool) -> OSStatus {
        let cible = NSAppleEventDescriptor(bundleIdentifier: "com.apple.mail")
        return AEDeterminePermissionToAutomateTarget(cible.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), demander)
    }

    static func ouvrirMailEnArrierePlan() async {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.mail") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        try? await Task.sleep(for: .seconds(2))
    }

    /// La clé est demandée à LibreAgent comme lors d'un vrai classement.
    func verifierCle() async {
        cle = .verification
        cleLien = nil
        do {
            var presente = false
            try await Engine.run(["verifier-cle"]) { event in
                if event.event == "cle" { presente = true }
                if event.event == "erreur" { self.cle = .manquant(event.message ?? "La clé Jev n'a pas été transmise.") }
            }
            if presente { cle = .ok }
        } catch let EngineError.libreagent(message, lien) {
            cle = .manquant(message)
            cleLien = lien
        } catch {
            cle = .manquant(error.localizedDescription)
        }
    }

    /// Ouvre la connexion ChatGPT de Codex dans le navigateur, puis relit l'état.
    func connecterCodex() {
        guard let chemin = codexChemin, !connexionCodex else { return }
        connexionCodex = true
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: chemin)
            process.arguments = ["login"]
            process.environment = Engine.environment()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                await Task.detached { process.waitUntilExit() }.value
            } catch {
                codex = .manquant("Impossible de lancer la connexion de Codex : \(error.localizedDescription)")
            }
            connexionCodex = false
            await verifierDiagnostic()
        }
    }

    func surveiller(_ etape: @escaping () -> Etape) {
        surveillance?.cancel()
        surveillance = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                switch etape() {
                case .mails: if self.mails != .ok { await self.verifierDiagnostic() }
                case .pilotage: if self.pilotage != .ok && self.pilotage != .verification { self.verifierPilotage(demander: false) }
                case .codex: if self.codex != .ok && !self.connexionCodex { await self.verifierDiagnostic() }
                case .cle: break
                }
            }
        }
    }

    func arreter() {
        surveillance?.cancel()
        surveillance = nil
    }

    static func ouvrirReglages(_ ancre: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(ancre)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Relance Classeur : certaines autorisations ne s'appliquent qu'au prochain démarrage.
    static func relancer() {
        let aide = Process()
        aide.executableURL = URL(fileURLWithPath: "/bin/sh")
        aide.arguments = ["-c", "sleep 0.8; exec /usr/bin/open -n \"$1\"", "classeur-relance", Bundle.main.bundleURL.path]
        if (try? aide.run()) != nil { NSApp.terminate(nil) }
    }
}

struct EcranConfiguration: View {
    let prerequis = Prerequis.shared
    let model = AppModel.shared
    /// Faux uniquement pour les captures : l'état affiché est alors celui préparé par le test.
    var verifier = true
    @State var etape: Prerequis.Etape = .mails

    var body: some View {
        HStack(spacing: 0) {
            barreEtapes
            Rectangle().fill(Theme.trait).frame(width: 1)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 1000, height: 600)
        .panneau(24)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.18)))
        .task {
            guard verifier else { return }
            await prerequis.verifierLocal()
            if prerequis.cle == .inconnu { await prerequis.verifierCle() }
            etape = Prerequis.Etape.allCases.first { prerequis.etat($0) != .ok } ?? .cle
            prerequis.surveiller { etape }
        }
        .onDisappear { prerequis.arreter() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if verifier { Task { await prerequis.verifierLocal() } }
        }
    }

    private var barreEtapes: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text("Bienvenue dans Classeur").font(.system(size: 21, weight: .bold, design: .rounded))
                Text("Quatre réglages, une seule fois.").font(.system(size: 13)).foregroundStyle(Theme.texte3)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Prerequis.Etape.allCases) { item in ligneEtape(item) }
            }
            Spacer()
        }
        .padding(28)
        .frame(width: 260, alignment: .topLeading)
        .background(Color.white.opacity(0.03))
    }

    private func ligneEtape(_ item: Prerequis.Etape) -> some View {
        let ok = prerequis.etat(item) == .ok
        return Button { withAnimation(.easeInOut(duration: 0.2)) { etape = item } } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle().fill(ok ? Color(hex: 0x6BF2A8).opacity(0.9) : etape == item ? Theme.violet : Color.white.opacity(0.1))
                        .frame(width: 30, height: 30)
                    Image(systemName: ok ? "checkmark" : item.symbole)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ok ? Color(hex: 0x10351F) : .white)
                }
                Text(item.titre).font(.system(size: 14, weight: etape == item ? .semibold : .regular))
                    .foregroundStyle(etape == item ? .white : Theme.texte2)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(etape == item ? Color.white.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Etiquette(texte: "Étape \(etape.rawValue + 1) sur \(Prerequis.Etape.allCases.count)")
                Spacer()
            }
            Group {
                switch etape {
                case .mails: etapeMails
                case .pilotage: etapePilotage
                case .codex: etapeCodex
                case .cle: etapeCle
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            Spacer(minLength: 0)
            navigation
        }
        .padding(32)
    }

    private func entete(_ titre: String, _ texte: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(titre).font(.system(size: 26, weight: .bold, design: .rounded))
                if ok { Pastille(texte: "Fait", couleur: Color(hex: 0x6BF2A8)) }
            }
            Text(texte).font(.system(size: 14)).foregroundStyle(Theme.texte2).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func message(_ etat: Prerequis.Etat) -> some View {
        switch etat {
        case .manquant(let texte):
            Text(texte).font(.system(size: 13)).foregroundStyle(Color(hex: 0xFFB547)).fixedSize(horizontal: false, vertical: true)
        case .verification:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Vérification…").font(.system(size: 13)).foregroundStyle(Theme.texte3) }
        default: EmptyView()
        }
    }

    private var etapeMails: some View {
        VStack(alignment: .leading, spacing: 18) {
            entete("Lire vos mails", "Classeur lit les mails d'Apple Mail directement sur ce Mac. macOS exige pour cela l'accès complet au disque. Rien ne quitte votre Mac, à part le texte envoyé au modèle qui analyse chaque mail.", ok: prerequis.mails == .ok)
            if prerequis.mails != .ok {
                HStack(alignment: .center, spacing: 18) {
                    VStack(spacing: 6) {
                        Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                            .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                            .help("Faites glisser Classeur dans la liste des Réglages")
                        Text("Classeur").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.texte3)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Ouvrez les Réglages avec le bouton ci-dessous.").font(.system(size: 13))
                        Text("2. Activez Classeur dans la liste. S'il n'y figure pas, faites glisser cette icône dans la liste.").font(.system(size: 13))
                        Text("3. Revenez ici : l'étape se valide toute seule.").font(.system(size: 13))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Theme.texte2)
                }
                .padding(16)
                .panneau(14)
                message(prerequis.mails)
                HStack(spacing: 12) {
                    Button("Ouvrir les Réglages") { Prerequis.ouvrirReglages("Privacy_AllFiles") }
                        .buttonStyle(BoutonPrincipal()).frame(width: 220)
                    Button("Relancer Classeur") { Prerequis.relancer() }
                        .buttonStyle(BoutonSecondaire())
                        .help("Si l'accès est activé mais que l'étape reste orange")
                }
            }
        }
    }

    private var etapePilotage: some View {
        VStack(alignment: .leading, spacing: 18) {
            entete("Ranger dans Mail", "Pour créer vos classeurs dans Mail, y déplacer les mails et envoyer les réponses que vous validez, Classeur pilote l'application Mail. macOS vous demande votre accord une seule fois.", ok: prerequis.pilotage == .ok)
            if prerequis.pilotage != .ok {
                message(prerequis.pilotage)
                HStack(spacing: 12) {
                    if prerequis.pilotageRefuse {
                        Button("Ouvrir les Réglages") { Prerequis.ouvrirReglages("Privacy_Automation") }
                            .buttonStyle(BoutonPrincipal()).frame(width: 220)
                        Text("Dans Automatisation, ouvrez Classeur et activez Mail.").font(.system(size: 13)).foregroundStyle(Theme.texte3)
                    } else {
                        Button("Autoriser Classeur à piloter Mail") { prerequis.verifierPilotage(demander: true) }
                            .buttonStyle(BoutonPrincipal()).frame(width: 300)
                            .disabled(prerequis.pilotage == .verification)
                    }
                }
            }
        }
    }

    private var etapeCodex: some View {
        VStack(alignment: .leading, spacing: 18) {
            entete("Codex", "Codex rédige les réponses avec votre compte ChatGPT. La connexion se fait dans votre navigateur.", ok: prerequis.codex == .ok)
            if prerequis.codex != .ok {
                message(prerequis.codex)
                HStack(spacing: 12) {
                    if prerequis.codexChemin == nil {
                        Button("Télécharger Codex") { NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex")!) }
                            .buttonStyle(BoutonPrincipal()).frame(width: 220)
                    } else {
                        Button(prerequis.connexionCodex ? "Connexion dans le navigateur…" : "Se connecter à ChatGPT") { prerequis.connecterCodex() }
                            .buttonStyle(BoutonPrincipal()).frame(width: 280)
                            .disabled(prerequis.connexionCodex)
                    }
                }
            }
        }
    }

    private var etapeCle: some View {
        VStack(alignment: .leading, spacing: 18) {
            entete("Clé Jev", "Jev classe vos mails. Sa clé est enregistrée dans LibreAgent quand vous ajoutez l'agent Classeur, puis transmise à Classeur à chaque classement, sans jamais être écrite sur ce Mac.", ok: prerequis.cle == .ok)
            if prerequis.cle != .ok {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Obtenir votre clé").font(.system(size: 13, weight: .bold))
                    Text("1. Ouvrez console.typesafe.ai et créez votre compte TypeSafe, ou connectez-vous.")
                    Text("2. Dans la console, créez une nouvelle clé API, par exemple nommée « Classeur ».")
                    Text("3. Copiez-la tout de suite : la console peut ne l'afficher qu'une fois.")
                    Text("4. Cliquez sur « Enregistrer ma clé dans LibreAgent », collez-la et choisissez de la garder pour vous ou de la partager.")
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.texte2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panneau(14)
            }
            if prerequis.toutEstPret {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundStyle(Color(hex: 0x6BF2A8))
                    Text("Tout est prêt. Classeur va lire un échantillon de vos mails pour vous proposer vos classeurs.")
                        .font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .panneau(14)
            } else if prerequis.cle != .ok {
                message(prerequis.cle)
                HStack(spacing: 12) {
                    Button("Ouvrir console.typesafe.ai") { NSWorkspace.shared.open(URL(string: "https://console.typesafe.ai")!) }
                        .buttonStyle(BoutonSecondaire()).fixedSize()
                    if let lien = prerequis.cleLien {
                        Button("Enregistrer ma clé dans LibreAgent") { NSWorkspace.shared.open(lien) }
                            .buttonStyle(BoutonPrincipal()).fixedSize()
                    }
                    Button("Vérifier") { Task { await prerequis.verifierCle() } }
                        .buttonStyle(BoutonSecondaire()).fixedSize()
                        .disabled(prerequis.cle == .verification)
                }
            }
        }
    }

    private var navigation: some View {
        HStack {
            if etape.rawValue > 0 {
                Button("Précédent") { withAnimation { etape = Prerequis.Etape(rawValue: etape.rawValue - 1)! } }
                    .buttonStyle(BoutonSecondaire())
            }
            Spacer()
            if let suivante = Prerequis.Etape(rawValue: etape.rawValue + 1) {
                Button("Continuer") { withAnimation { etape = suivante } }
                    .buttonStyle(BoutonPrincipal()).frame(width: 160)
                    .disabled(prerequis.etat(etape) != .ok)
            } else {
                Button("Commencer") { model.terminerConfiguration() }
                    .buttonStyle(BoutonPrincipal()).frame(width: 180)
                    .disabled(!prerequis.toutEstPret)
            }
        }
    }
}
