import SwiftUI

struct RootView: View {
    let model = AppModel.shared

    var body: some View {
        ZStack {
            Fond()
            VStack(spacing: 0) {
                BarreHaute()
                contenu.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let card = model.selected {
                FicheMail(card: card).id(card.id).transition(.opacity).zIndex(2)
            }
            if let c = model.reglage {
                ReglagesClasseur(classeur: c, nouveau: model.reglageNouveau)
                    .id(c.id + (model.reglageNouveau ? "-nouveau" : ""))
                    .transition(.opacity)
                    .zIndex(2)
            }
            if let toast = model.toast {
                ToastView(toast: toast).transition(.scale(scale: 0.85).combined(with: .opacity)).zIndex(3)
            }
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 1180, minHeight: 760)
        .task { await model.bootstrap() }
    }

    @ViewBuilder private var contenu: some View {
        switch model.phase {
        case .demarrage: Demarrage()
        case .accueil: Accueil()
        case .decouverte: Decouverte()
        case .connexion, .lecture, .compris: Lecture()
        case .rangement, .termine: Tableau()
        case .erreur: Erreur()
        }
    }
}

struct Demarrage: View {
    var body: some View {
        VStack(spacing: 16) {
            Orbe(taille: 80, vivant: true)
            Text("J'ouvre Classeur…").font(.system(size: 15)).foregroundStyle(Theme.texte2)
        }
    }
}

struct BarreHaute: View {
    let model = AppModel.shared

    var body: some View {
        HStack(spacing: 10) {
            Text("Boîte de réception").font(.system(size: 14, weight: .bold))
            Text(sousTitre).font(.system(size: 12)).foregroundStyle(Theme.texte3)
            Spacer()
            HStack(spacing: 8) {
                Orbe(taille: 18, vivant: model.busy)
                Text(etat).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.violet.opacity(model.busy ? 0.55 : 0.25)))
            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
        .padding(.leading, 84)
        .padding(.trailing, 18)
        .frame(height: 52)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.trait).frame(height: 1) }
    }

    private var sousTitre: String {
        guard let total = model.totalBoite else { return "" }
        let lus = model.unread ?? 0
        return "\(Format.pluriel(total, "mail", "mails")) · " + (lus == 0 ? "0 non lu" : Format.pluriel(lus, "non lu", "non lus"))
    }

    private var etat: String {
        switch model.phase {
        case .demarrage: "Ouverture…"
        case .accueil: "Prêt"
        case .decouverte: model.etape == .edition ? "Tes classeurs" : "En cours…"
        case .connexion, .lecture, .compris, .rangement: "En cours…"
        case .termine: model.pendingReplies > 0 ? Format.pluriel(model.pendingReplies, "réponse à valider", "réponses à valider") : "Terminé"
        case .erreur: "Arrêté"
        }
    }
}

struct Accueil: View {
    @Bindable var model = AppModel.shared

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Orbe(taille: 104, vivant: true)
            Text("Classeur").font(.system(size: 46, weight: .heavy, design: .rounded))
            Text(sousTitre)
                .font(.system(size: 17))
                .foregroundStyle(Theme.texte2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
            if model.dejaTraites > 0 {
                Text("\(Format.pluriel(model.dejaTraites, "mail déjà traité sera repris", "mails déjà traités seront repris")) de ma mémoire, sans nouvelle analyse.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.texte3)
            }
            HStack(spacing: 8) {
                ForEach(model.ontologie) { c in
                    HStack(spacing: 6) {
                        Image(systemName: c.symbole).font(.system(size: 10, weight: .bold)).foregroundStyle(c.teinte)
                        Text(c.nom).font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(c.teinte.opacity(0.15)))
                    .overlay(Capsule().stroke(c.teinte.opacity(0.5), lineWidth: 1))
                }
            }
            Picker("Mails à traiter", selection: $model.porteeBoite) {
                Text("Mails non lus").tag(false)
                Text("Toute la boîte de réception").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 400)
            HStack(spacing: 12) {
                Button("Traiter tous mes mails") { model.start(ranger: true) }
                    .buttonStyle(BoutonPrincipal())
                    .frame(width: 260)
                    .keyboardShortcut(.defaultAction)
                Button("Analyser sans ranger") { model.start(ranger: false) }
                    .buttonStyle(BoutonSecondaire())
                Button("Modifier mes classeurs") { model.editerClasseurs() }
                    .buttonStyle(BoutonSecondaire())
            }
            if let run = model.lastRun, run.total > 0 {
                let pending = run.mails.filter { $0.action == "repondre" && $0.statut != "envoye" }.count
                if pending > 0 {
                    Button("Reprendre le dernier traitement · " + Format.pluriel(pending, "réponse à valider", "réponses à valider")) {
                        model.resume(run)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(hex: 0xC9BCFF))
                    .font(.system(size: 13, weight: .semibold))
                }
            }
            Spacer()
            Text("Les mails sont rangés dans des dossiers Classeur d'Apple Mail. Aucune réponse ne part sans ta validation.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.texte3)
                .padding(.bottom, 22)
        }
        .padding(.horizontal, 40)
    }

    private var sousTitre: String {
        if let error = model.unreadError { return error }
        guard let total = model.totalBoite, let n = model.unread else { return "Je regarde ta boîte de réception…" }
        if model.porteeBoite {
            return "\(Format.pluriel(total, "mail", "mails")) dans ta boîte de réception. Je les lis, je les range dans tes classeurs et je prépare tes réponses."
        }
        return n == 0
            ? "Aucun mail non lu. Choisis « Toute la boîte de réception » pour tout trier."
            : "\(Format.pluriel(n, "mail non lu", "mails non lus")). Je les lis, je les range et je prépare tes réponses."
    }
}

struct Erreur: View {
    let model = AppModel.shared

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color(hex: 0xFFB547))
            Text("Le traitement s'est arrêté").font(.system(size: 28, weight: .heavy, design: .rounded))
            Text(model.errorMessage)
                .font(.system(size: 14))
                .foregroundStyle(Theme.texte2)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 680)
            HStack(spacing: 12) {
                Button("Réessayer") { model.reessayer() }
                    .buttonStyle(BoutonPrincipal())
                    .frame(width: 160)
                if model.errorCode == "acces_disque" {
                    Button("Ouvrir Accès complet au disque") { model.openPrivacy("Privacy_AllFiles") }
                        .buttonStyle(BoutonSecondaire())
                }
                if model.errorCode == "compte_deconnecte" {
                    Button("Ouvrir Mail") { model.ouvrirDiagnosticMail() }
                        .buttonStyle(BoutonSecondaire())
                }
                if model.errorMessage.contains("Automatisation") {
                    Button("Ouvrir Automatisation") { model.openPrivacy("Privacy_Automation") }
                        .buttonStyle(BoutonSecondaire())
                }
                Button("Ouvrir la configuration") { model.openConfig() }
                    .buttonStyle(BoutonSecondaire())
                Button("Retour") { model.reset() }
                    .buttonStyle(BoutonSecondaire())
            }
        }
        .padding(40)
    }
}
