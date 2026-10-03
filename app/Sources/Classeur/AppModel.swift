import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Phase { case demarrage, accueil, decouverte, connexion, lecture, compris, rangement, termine, erreur }
    enum EtapeDecouverte { case lecture, imagination, classement, edition }
    enum Action { case decouverte, reclassement, traitement(Bool) }

    var phase: Phase = .demarrage
    @ObservationIgnored private var derniereAction: Action = .decouverte

    // MARK: Classeurs (ontologie) et échantillon
    var ontologie: [Classeur] = []
    var etape: EtapeDecouverte = .lecture
    var echantillon: [InboxItem] = []
    var pile: [String] = []
    var colonnes: [String: [String]] = [:]
    var affectations: [String: Affectation] = [:]
    var ontologieModifiee = false
    var reglage: Classeur?
    var reglageNouveau = false
    var reglageErreur: String?
    @ObservationIgnored private var tampon: [String: Affectation] = [:]
    @ObservationIgnored private var moteurTermine = false
    @ObservationIgnored private var animateur: Task<Void, Never>?

    // MARK: Traitement
    var ranger = true
    var porteeBoite = true
    var total = 0
    var lus = 0
    var inbox: [InboxItem] = []
    var classes: [String: String] = [:]
    var analysed: [String: MailCard] = [:]
    var feed: [MailCard] = []
    var lastAnalysedId: String?
    var compteurs: [String: Int] = [:]
    var titre = ""
    var cards: [MailCard] = []
    var visible: Set<String> = []
    var activeColumn: String?
    var runId: String?
    var errorMessage = ""
    var errorCode = ""
    var unread: Int?
    var totalBoite: Int?
    var dejaTraites = 0
    var repris = 0
    var survol: String?
    var unreadError: String?
    var selected: MailCard?
    var toast: Toast?
    var sending = false
    var sheetError: String?
    var lastRun: RunPayload?

    @ObservationIgnored private var process: Process?

    var busy: Bool { [.connexion, .lecture, .compris, .rangement].contains(phase) || (phase == .decouverte && etape != .edition) }

    var pendingReplies: Int {
        cards.filter { $0.action == "repondre" && $0.statut != "envoye" && $0.statut != "supprime" }.count
    }

    func classeur(_ id: String) -> Classeur {
        if let found = ontologie.first(where: { $0.id == id }) { return found }
        if let found = lastRun?.classeurs?.first(where: { $0.id == id }) { return found }
        return id == Classeur.aVerifierId ? .aVerifier : Classeur(
            id: id, nom: id, definition: "", inclure: [], exclure: [], exemples: [], action: "ranger",
            dossier: id, couleur: "bleu", symbole: "archivebox.fill", transfertEmail: "", transfertAuto: false
        )
    }

    /// Colonnes affichées : les classeurs, puis « À vérifier ».
    var colonnesAffichees: [Classeur] { ontologie + [.aVerifier] }

    func count(_ id: String) -> Int { cards.filter { $0.classeur == id && $0.statut != "supprime" }.count }

    // MARK: Démarrage

    func bootstrap() async {
        await chargerOntologie()
        if ontologie.isEmpty {
            demarrerDecouverte()
        } else {
            phase = .accueil
        }
        await refreshUnread()
        await loadLast()
    }

    func chargerOntologie() async {
        do {
            try await Engine.run(["ontologie"]) { event in
                if event.event == "ontologie" { self.appliquer(event) }
            }
        } catch {
            fail(error.localizedDescription, code: "moteur")
        }
    }

    private func appliquer(_ event: EngineEvent) {
        ontologie = event.classeurs ?? []
        if let sample = event.echantillon { echantillon = sample }
        if let aff = event.affectations {
            affectations = aff
            var cols: [String: [String]] = [:]
            for item in echantillon {
                if let a = aff[item.id] { cols[a.classeur, default: []].append(item.id) }
            }
            colonnes = cols
            pile = echantillon.map(\.id).filter { aff[$0] == nil }
        }
        if let v = event.version, let s = event.versionEchantillon { ontologieModifiee = v != s }
    }

    func refreshUnread() async {
        do {
            try await Engine.run(["compter"]) { event in
                if event.event == "compte" {
                    self.unread = event.nonLus
                    self.totalBoite = event.total
                    self.dejaTraites = event.dejaTraites ?? 0
                    self.unreadError = nil
                    NSApp.dockTile.badgeLabel = (event.nonLus ?? 0) > 0 ? "\(event.nonLus ?? 0)" : nil
                } else if event.event == "erreur" {
                    self.unread = nil
                    self.unreadError = event.message
                }
            }
        } catch {
            unread = nil
            unreadError = error.localizedDescription
        }
    }

    func loadLast() async {
        try? await Engine.run(["dernier"]) { event in
            if event.event == "dernier" { self.lastRun = event.run }
        }
    }

    // MARK: Découverte des classeurs

    func demarrerDecouverte() {
        guard !busy else { return }
        derniereAction = .decouverte
        animateur?.cancel()
        tampon = [:]
        moteurTermine = false
        ontologie = []
        echantillon = []
        pile = []
        colonnes = [:]
        affectations = [:]
        ontologieModifiee = false
        etape = .lecture
        phase = .decouverte
        lancer(["decouvrir"])
    }

    func editerClasseurs() {
        guard !busy else { return }
        Task {
            await chargerOntologie()
            if ontologie.isEmpty { demarrerDecouverte(); return }
            etape = .edition
            phase = .decouverte
        }
    }

    func reclasser() {
        guard !busy, !echantillon.isEmpty else { return }
        derniereAction = .reclassement
        animateur?.cancel()
        tampon = [:]
        moteurTermine = false
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
            pile = echantillon.map(\.id)
            colonnes = [:]
            affectations = [:]
        }
        etape = .classement
        lancer(["reclasser"])
    }

    func validerClasseurs() {
        guard !ontologie.isEmpty else { return }
        phase = .accueil
    }

    private func lancer(_ args: [String]) {
        Task {
            do {
                try await Engine.run(args, onStart: { self.process = $0 }) { event in
                    await self.handleDecouverte(event)
                }
            } catch {
                self.fail(error.localizedDescription, code: "moteur")
            }
            self.process = nil
        }
    }

    private func handleDecouverte(_ event: EngineEvent) async {
        switch event.event {
        case "phase":
            switch event.phase {
            case "lecture": etape = .lecture
            case "imagination": withAnimation(.easeInOut(duration: 0.4)) { etape = .imagination }
            case "classement": withAnimation(.easeInOut(duration: 0.4)) { etape = .classement }
            default: break
            }
        case "debut":
            let mails = event.mails ?? []
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                echantillon = mails
                pile = mails.map(\.id)
            }
        case "ontologie":
            let proposes = event.classeurs ?? []
            for c in proposes {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { ontologie.append(c) }
                await pause(0.35)
            }
            await pause(0.5)
        case "classe":
            guard let id = event.id, let cid = event.classeur else { return }
            tampon[id] = Affectation(classeur: cid, suggestion: event.suggestion, confiance: event.confiance, incertain: event.incertain ?? false)
            demarrerAnimateur()
        case "termine":
            moteurTermine = true
            demarrerAnimateur()
        case "erreur":
            animateur?.cancel()
            fail(event.message ?? "Erreur inconnue du moteur.", code: event.code ?? "")
        default:
            break
        }
    }

    /// Fait voler les mails de la pile vers leur colonne, dans l'ordre de la pile.
    private func demarrerAnimateur() {
        guard animateur == nil else { return }
        animateur = Task { @MainActor in
            defer { self.animateur = nil }
            while !Task.isCancelled {
                guard let first = pile.first else { break }
                if let aff = tampon.removeValue(forKey: first) {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                        pile.removeFirst()
                        affectations[first] = aff
                        colonnes[aff.classeur, default: []].insert(first, at: 0)
                    }
                    await pause(pile.count > 40 ? 0.07 : 0.11)
                } else if moteurTermine {
                    fail("Le classement s'est terminé sans décision pour le mail \(first).", code: "classement_incomplet")
                    return
                } else {
                    await pause(0.05)
                }
            }
            if pile.isEmpty && moteurTermine {
                ontologieModifiee = false
                withAnimation(.easeInOut(duration: 0.4)) { etape = .edition }
            }
        }
    }

    // MARK: Réglages d'un classeur

    func ouvrirReglages(_ c: Classeur) {
        reglageErreur = nil
        reglageNouveau = false
        withAnimation(.easeOut(duration: 0.2)) { reglage = c }
    }

    func nouveauClasseur() {
        reglageErreur = nil
        reglageNouveau = true
        withAnimation(.easeOut(duration: 0.2)) { reglage = .nouveau() }
    }

    func fermerReglages() {
        withAnimation(.easeIn(duration: 0.15)) { reglage = nil }
    }

    func enregistrer(_ draft: Classeur) {
        var liste = ontologie
        if reglageNouveau {
            liste.append(draft)
        } else if let index = liste.firstIndex(where: { $0.id == draft.id }) {
            liste[index] = draft
        }
        persister(liste) { self.fermerReglages() }
    }

    func supprimer(_ c: Classeur) {
        persister(ontologie.filter { $0.id != c.id }) { self.fermerReglages() }
    }

    private func persister(_ liste: [Classeur], ok: @escaping @MainActor () -> Void) {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(["classeurs": liste]), let json = String(data: data, encoding: .utf8) else {
            reglageErreur = "Impossible de préparer les classeurs pour l'enregistrement."
            return
        }
        Task {
            var succes = false
            do {
                try await Engine.run(["ontologie", "--enregistrer"], input: json) { event in
                    if event.event == "ontologie" {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                            self.ontologie = event.classeurs ?? []
                        }
                        self.ontologieModifiee = true
                        succes = true
                    } else if event.event == "erreur" {
                        self.reglageErreur = event.message
                    }
                }
            } catch {
                reglageErreur = error.localizedDescription
            }
            if succes { ok() }
        }
    }

    // MARK: Traitement de la boîte

    func start(ranger: Bool, retraiter: Bool = false) {
        guard !busy else { return }
        if ontologie.isEmpty {
            demarrerDecouverte()
            return
        }
        if !porteeBoite, unread == 0 {
            fail("Ta boîte de réception ne contient aucun mail non lu. Choisis « Toute la boîte de réception » pour trier les mails déjà lus.", code: "aucun_non_lu")
            return
        }
        self.ranger = ranger
        derniereAction = .traitement(ranger)
        phase = .connexion
        total = 0
        lus = 0
        inbox = []
        classes = [:]
        analysed = [:]
        feed = []
        lastAnalysedId = nil
        compteurs = [:]
        titre = ""
        cards = []
        visible = []
        activeColumn = nil
        runId = nil
        selected = nil
        repris = 0
        var args = ["traiter", "--portee", porteeBoite ? "boite" : "non_lus"]
        if !ranger { args.append("--sans-rangement") }
        if retraiter { args.append("--retraiter") }
        Task {
            do {
                try await Engine.run(args, onStart: { self.process = $0 }) { event in
                    await self.handle(event)
                }
            } catch {
                self.fail(error.localizedDescription, code: "moteur")
            }
            self.process = nil
            await self.refreshUnread()
        }
    }

    func cancel() {
        process?.terminate()
    }

    func reset() {
        phase = ontologie.isEmpty ? .demarrage : .accueil
        Task { await bootstrap() }
    }

    func resume(_ run: RunPayload) {
        cards = run.mails
        visible = Set(run.mails.map(\.id))
        compteurs = run.compteurs
        titre = run.titre
        runId = run.id
        total = run.total
        ranger = run.range ?? true
        phase = .termine
    }

    func fail(_ message: String, code: String) {
        errorMessage = message
        errorCode = code
        phase = .erreur
    }

    func reessayer() {
        switch derniereAction {
        case .decouverte:
            phase = .demarrage
            demarrerDecouverte()
        case .reclassement:
            phase = .decouverte
            etape = .edition
            reclasser()
        case .traitement(let r):
            phase = .accueil
            start(ranger: r)
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func reveal(_ ids: [String], step: Double = 0.07) async {
        for id in ids {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { _ = visible.insert(id) }
            await pause(step)
        }
    }

    private func handle(_ event: EngineEvent) async {
        switch event.event {
        case "phase":
            if event.phase == "connexion" {
                runId = event.runId
                phase = .connexion
            } else if event.phase == "rangement" {
                withAnimation(.easeInOut(duration: 0.5)) { phase = .rangement }
                await pause(0.6)
            }
        case "debut":
            total = event.total ?? 0
            inbox = event.mails ?? []
            repris = 0
            withAnimation(.easeInOut(duration: 0.4)) { phase = .lecture }
        case "mail":
            guard let card = event.mail else { return }
            lus = event.lus ?? lus + 1
            if event.deja == true { repris += 1 }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                analysed[card.id] = card
                classes[card.id] = card.classeur
                lastAnalysedId = card.id
                feed.insert(card, at: 0)
                if feed.count > 7 { feed.removeLast() }
            }
            await pause(event.deja == true ? 0.04 : 0.12)
        case "compris":
            compteurs = event.compteurs ?? [:]
            titre = event.titre ?? ""
            cards = inbox.compactMap { analysed[$0.id] }
            withAnimation(.easeInOut(duration: 0.5)) { phase = .compris }
            await pause(2.6)
        case "transfert":
            if let id = event.id, let index = cards.firstIndex(where: { $0.id == id }) {
                cards[index].statut = event.statut ?? cards[index].statut
            }
        case "range":
            guard let cid = event.classeur else { return }
            activeColumn = cid
            await reveal(cards.filter { $0.classeur == cid }.map(\.id))
            activeColumn = nil
        case "termine":
            guard let run = event.run else { return }
            runId = run.id
            total = run.total
            compteurs = run.compteurs
            titre = run.titre
            if run.total == 0 {
                cards = []
                phase = .termine
                return
            }
            cards = run.mails
            if phase != .rangement {
                withAnimation(.easeInOut(duration: 0.5)) { phase = .rangement }
                await pause(0.5)
            }
            for c in colonnesAffichees {
                let restants = cards.filter { $0.classeur == c.id && !visible.contains($0.id) }.map(\.id)
                guard !restants.isEmpty else { continue }
                activeColumn = c.id
                await reveal(restants, step: 0.05)
            }
            activeColumn = nil
            visible = Set(cards.map(\.id))
            lastRun = run
            withAnimation(.easeInOut(duration: 0.5)) { phase = .termine }
        case "erreur":
            fail(event.message ?? "Erreur inconnue du moteur.", code: event.code ?? "")
        default:
            break
        }
    }

    // MARK: Validation des réponses

    func open(_ card: MailCard) {
        sheetError = nil
        withAnimation(.easeOut(duration: 0.2)) { selected = card }
    }

    func close() {
        guard !sending else { return }
        withAnimation(.easeIn(duration: 0.15)) { selected = nil }
    }

    func send(_ card: MailCard, body: String) {
        guard let runId, !sending else { return }
        sending = true
        sheetError = nil
        Task {
            do {
                try await Engine.run(["envoyer", "--run", runId, "--mail", card.id], input: body) { event in
                    if event.event == "envoye" {
                        self.markSent(card.id, body: body)
                    } else if event.event == "erreur" {
                        self.sheetError = event.message
                    }
                }
            } catch {
                sheetError = error.localizedDescription
            }
            sending = false
        }
    }

    func transfer(_ card: MailCard) {
        guard let runId, !sending else { return }
        sending = true
        sheetError = nil
        Task {
            do {
                try await Engine.run(["transferer", "--run", runId, "--mail", card.id]) { event in
                    if event.event == "transfere" {
                        if let index = self.cards.firstIndex(where: { $0.id == card.id }) {
                            self.cards[index].statut = "transfere"
                        }
                        self.selected = nil
                        self.show(Toast(titre: "Transféré à \(card.transfertEmail)", detail: "Parti à \(Format.maintenant())"))
                    } else if event.event == "erreur" {
                        self.sheetError = event.message
                    }
                }
            } catch {
                sheetError = error.localizedDescription
            }
            sending = false
        }
    }

    private func markSent(_ id: String, body: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].statut = "envoye"
        cards[index].reponse = body
        let name = Format.nom(cards[index].de)
        withAnimation(.easeIn(duration: 0.15)) { selected = nil }
        let left = pendingReplies
        show(Toast(
            titre: "Envoyée à \(name)",
            detail: "Réponse partie à \(Format.maintenant()) · " + (left == 0 ? "plus rien à valider" : Format.pluriel(left, "restante à valider", "restantes à valider"))
        ))
    }

    private func show(_ toast: Toast) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { self.toast = toast }
        Task {
            await pause(3.2)
            if self.toast == toast {
                withAnimation(.easeOut(duration: 0.3)) { self.toast = nil }
            }
        }
    }

    // MARK: Réglages système

    func openConfig() {
        Task {
            do {
                try await Engine.run(["config"]) { event in
                    if let path = event.chemin { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                }
            } catch {
                fail(error.localizedDescription, code: "moteur")
            }
        }
    }

    func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    func ouvrirDiagnosticMail() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mail.app"))
    }

    // MARK: Suppression

    /// Supprime le mail survolé (touche Effacer) ou désigné (clic droit).
    func supprimer(_ id: String) {
        if phase == .decouverte, etape == .edition {
            supprimerEchantillon(id)
        } else if phase == .termine {
            supprimerCarte(id)
        }
    }

    private func supprimerEchantillon(_ id: String) {
        guard let avant = affectations[id], let item = echantillon.first(where: { $0.id == id }) else { return }
        let positionColonne = colonnes[avant.classeur]?.firstIndex(of: id) ?? 0
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            colonnes[avant.classeur]?.removeAll { $0 == id }
            affectations[id] = nil
        }
        if survol == id { survol = nil }
        Task {
            let erreur = await executerSuppression(["supprimer", "--mail", id])
            if let erreur {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    var liste = colonnes[avant.classeur] ?? []
                    liste.insert(id, at: min(positionColonne, liste.count))
                    colonnes[avant.classeur] = liste
                    affectations[id] = avant
                }
                show(Toast(titre: "Suppression annulée", detail: erreur))
            } else {
                echantillon.removeAll { $0.id == id }
                show(Toast(titre: "Mail supprimé", detail: "\(Format.nom(item.de)) est dans la corbeille d'Apple Mail."))
            }
        }
    }

    private func supprimerCarte(_ id: String) {
        guard let runId, let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let avant = cards[index]
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { cards[index].statut = "supprime" }
        if survol == id { survol = nil }
        Task {
            let erreur = await executerSuppression(["supprimer", "--mail", id, "--run", runId])
            guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
            if let erreur {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { cards[i] = avant }
                show(Toast(titre: "Suppression annulée", detail: erreur))
            } else {
                show(Toast(titre: "Mail supprimé", detail: "\(Format.nom(avant.de)) est dans la corbeille d'Apple Mail."))
            }
        }
    }

    private func executerSuppression(_ args: [String]) async -> String? {
        var erreur: String?
        var confirme = false
        do {
            try await Engine.run(args) { event in
                if event.event == "supprime" { confirme = true }
                if event.event == "erreur" { erreur = event.message }
            }
        } catch {
            erreur = error.localizedDescription
        }
        if erreur == nil && !confirme { erreur = "Le moteur n'a pas confirmé la suppression." }
        return erreur
    }

    // MARK: Glisser-déposer

    /// Corrige à la main le classeur d'un mail de l'échantillon.
    func deplacerEchantillon(_ id: String, vers cible: String) {
        guard etape == .edition, let avant = affectations[id], avant.classeur != cible else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            colonnes[avant.classeur]?.removeAll { $0 == id }
            colonnes[cible, default: []].insert(id, at: 0)
            affectations[id] = Affectation(classeur: cible, suggestion: avant.suggestion, confiance: avant.confiance, incertain: false, manuel: true)
        }
        Task {
            var erreur: String?
            do {
                try await Engine.run(["corriger", "--mail", id, "--classeur", cible]) { event in
                    if event.event == "erreur" { erreur = event.message }
                }
            } catch {
                erreur = error.localizedDescription
            }
            if let erreur {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    colonnes[cible]?.removeAll { $0 == id }
                    colonnes[avant.classeur, default: []].insert(id, at: 0)
                    affectations[id] = avant
                }
                show(Toast(titre: "Déplacement annulé", detail: erreur))
            } else {
                show(Toast(titre: "Classé dans « \(classeur(cible).nom) »", detail: "Correction enregistrée : elle sera conservée au prochain reclassement."))
            }
        }
    }

    /// Déplace un mail traité vers un autre classeur, et dans Apple Mail si le traitement a rangé.
    func deplacerCarte(_ id: String, vers cible: String) {
        guard phase == .termine, let runId, let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let avant = cards[index]
        guard avant.classeur != cible else { return }
        if avant.statut == "envoye" || avant.statut == "transfere" {
            show(Toast(titre: "Déplacement impossible", detail: "Ce mail a déjà été envoyé ou transféré."))
            return
        }
        let destination = classeur(cible)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            cards[index].classeur = cible
            cards[index].action = destination.estVirtuel ? Classeur.aVerifierId : destination.action
        }
        Task {
            var erreur: String?
            var mise: MailCard?
            do {
                try await Engine.run(["deplacer", "--run", runId, "--mail", id, "--classeur", cible]) { event in
                    if event.event == "deplace" { mise = event.mail }
                    if event.event == "erreur" { erreur = event.message }
                }
            } catch {
                erreur = error.localizedDescription
            }
            guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
            if let mise, erreur == nil {
                let complete = MailCard(
                    id: mise.id, classeur: mise.classeur, action: mise.action, suggestion: mise.suggestion,
                    confiance: mise.confiance, expediteur: mise.expediteur, objetCourt: mise.objetCourt,
                    ligne: mise.ligne, etiquette: mise.etiquette, urgent: mise.urgent, reponse: mise.reponse,
                    statut: mise.statut, dossier: mise.dossier, transfertEmail: mise.transfertEmail,
                    compte: mise.compte, boite: mise.boite, messageId: mise.messageId, de: mise.de, a: mise.a,
                    date: mise.date, objet: mise.objet, texte: cards[i].texte
                )
                cards[i] = complete
                compteurs = Dictionary(grouping: cards, by: \.classeur).mapValues(\.count)
                show(Toast(
                    titre: "Déplacé dans « \(destination.nom) »",
                    detail: ranger ? "Le mail a aussi été déplacé dans Apple Mail." : "Mode analyse : rien n'a été déplacé dans Apple Mail."
                ))
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { cards[i] = avant }
                show(Toast(titre: "Déplacement annulé", detail: erreur ?? "Le moteur n'a pas confirmé le déplacement."))
            }
        }
    }

    /// Ouvre le mail dans Apple Mail grâce à son Message-ID (lien message://).
    func ouvrirDansMail(_ messageId: String?) {
        let brut = (messageId ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "<> \n"))
        var autorises = CharacterSet.urlPathAllowed
        autorises.remove(charactersIn: "+=/?&#%")
        guard !brut.isEmpty,
              let encode = brut.addingPercentEncoding(withAllowedCharacters: autorises),
              let url = URL(string: "message://%3C\(encode)%3E") else {
            show(Toast(titre: "Impossible d'ouvrir ce mail", detail: "Apple Mail ne fournit pas son identifiant."))
            return
        }
        if !NSWorkspace.shared.open(url) {
            show(Toast(titre: "Impossible d'ouvrir ce mail", detail: "Apple Mail n'a pas accepté le lien vers ce message."))
        }
    }
}
