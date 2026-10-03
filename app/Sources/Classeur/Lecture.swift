import SwiftUI

struct Lecture: View {
    let model = AppModel.shared

    var body: some View {
        HStack(spacing: 0) {
            ListeBoite()
                .frame(width: 370)
                .background(Color.black.opacity(0.18))
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.trait).frame(width: 1) }
            PanneauIA()
                .padding(24)
        }
    }
}

struct ListeBoite: View {
    let model = AppModel.shared

    var body: some View {
        if model.inbox.isEmpty {
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Connexion à Apple Mail…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.texte3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.inbox) { item in
                            LigneBoite(item: item, classeur: model.classes[item.id].map { model.classeur($0) }, active: model.lastAnalysedId == item.id)
                                .id(item.id)
                                .contentShape(Rectangle())
                                .ouvreDansMail { model.ouvrirDansMail(item.messageId) }
                        }
                    }
                }
                .onChange(of: model.lastAnalysedId) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }
}

struct LigneBoite: View {
    let item: InboxItem
    let classeur: Classeur?
    let active: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(Format.nom(item.de))
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Spacer()
                Text(Format.heure(item.date))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.texte3)
            }
            Text(item.objet)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(item.apercu)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.texte3)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let classeur {
                    Pastille(texte: classeur.nom, couleur: classeur.teinte)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(active ? Theme.violet.opacity(0.35) : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }
}

struct PanneauIA: View {
    let model = AppModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Orbe(taille: 50, vivant: model.phase != .compris)
                VStack(alignment: .leading, spacing: 5) {
                    Text(titre)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .contentTransition(.opacity)
                    Text(sousTitre)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.texte2)
                }
            }
            HStack(spacing: 14) {
                Progression(valeur: model.total == 0 ? 0 : Double(model.lus) / Double(model.total))
                Text("\(model.lus) / \(model.total) lus")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            if model.phase == .compris {
                Synthese()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                Spacer()
            } else {
                Spacer()
                VStack(spacing: 8) {
                    ForEach(Array(model.feed.enumerated()), id: \.element.id) { index, card in
                        LigneFlux(card: card)
                            .opacity(1 - Double(index) * 0.11)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.violet.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.trait, lineWidth: 1))
    }

    private var titre: String {
        switch model.phase {
        case .connexion: "J'ouvre ta boîte"
        case .compris: "Compris."
        default: "Je lis tes mails"
        }
    }

    private var sousTitre: String {
        switch model.phase {
        case .connexion: "Je me connecte à Apple Mail et je récupère tes mails."
        case .compris: model.titre
        default: "Un par un. Qui écrit, pourquoi, et ce que ça demande de toi."
        }
    }
}

struct Progression: View {
    var valeur: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xCFC3FF), .white], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * valeur))
                    .shadow(color: .white.opacity(0.7), radius: 6)
                    .animation(.easeOut(duration: 0.4), value: valeur)
            }
        }
        .frame(height: 6)
    }
}

struct LigneFlux: View {
    let card: MailCard
    let model = AppModel.shared

    var body: some View {
        let classeur = model.classeur(card.classeur)
        HStack(spacing: 10) {
            Circle().fill(.white).frame(width: 6, height: 6)
            (Text(card.expediteur).bold() + Text(" · " + card.ligne).foregroundColor(Theme.texte2))
                .font(.system(size: 13))
                .lineLimit(2)
            Spacer(minLength: 8)
            Pastille(texte: classeur.nom, couleur: classeur.teinte)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

struct Synthese: View {
    let model = AppModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(Format.pluriel(model.total, "mail compris", "mails compris")).")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
            if model.repris > 0 {
                Text("\(Format.pluriel(model.repris, "mail déjà traité a été repris", "mails déjà traités ont été repris")) de ma mémoire, sans nouvelle analyse.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.texte2)
            }
            HStack(spacing: 8) {
                Circle().fill(.white).frame(width: 7, height: 7)
                Text(model.ranger ? "Je range tout." : "Je les classe, sans rien déplacer dans Apple Mail.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.texte2)
            }
        }
    }
}
