import SwiftUI

struct Tableau: View {
    let model = AppModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Orbe(taille: 46, vivant: model.phase == .rangement)
                VStack(alignment: .leading, spacing: 5) {
                    Text(titre).font(.system(size: 30, weight: .heavy, design: .rounded))
                    Text(sousTitre).font(.system(size: 14)).foregroundStyle(Theme.texte2)
                }
                Spacer()
                if model.phase == .termine {
                    Button("Nouveau traitement") { model.reset() }.buttonStyle(BoutonSecondaire())
                }
            }
            if model.phase == .termine && model.total == 0 {
                VStack(spacing: 10) {
                    Image(systemName: "tray").font(.system(size: 44, weight: .light))
                    Text("Rien à traiter pour l'instant.").font(.system(size: 18, weight: .semibold))
                }
                .foregroundStyle(Theme.texte2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(colonnes) { c in Colonne(classeur: c) }
                }
                .frame(maxHeight: .infinity)
                if model.phase == .termine {
                    Bilan()
                        .frame(maxWidth: .infinity)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(26)
    }

    private var colonnes: [Classeur] {
        model.colonnesAffichees.filter { !$0.estVirtuel || model.count($0.id) > 0 || model.phase == .termine }
    }

    private var titre: String {
        if model.phase == .rangement { return model.ranger ? "Je range" : "Je classe" }
        if model.total == 0 { return "Ta boîte est déjà à jour." }
        return model.ranger
            ? "\(Format.pluriel(model.total, "mail lu", "mails lus")), compris et rangés"
            : "\(Format.pluriel(model.total, "mail lu", "mails lus")) et compris"
    }

    private var sousTitre: String {
        if model.phase == .rangement { return "Chaque mail à sa place. Tu n'as rien à faire." }
        if model.total == 0 { return "Aucun mail ne correspond à la sélection." }
        let pending = model.pendingReplies
        let reste = pending == 0 ? "Aucune réponse à valider." : "Il te reste \(Format.pluriel(pending, "réponse", "réponses")) à valider."
        return model.ranger ? "\(reste) Tout le reste est fait." : "\(reste) Rien n'a été déplacé dans Apple Mail."
    }
}

struct Colonne: View {
    let classeur: Classeur
    let model = AppModel.shared
    @State private var tout = false
    @State private var survolDepot = false

    var body: some View {
        let cards = model.cards.filter { $0.classeur == classeur.id && $0.statut != "supprime" && model.visible.contains($0.id) }
        let shown = tout ? cards : Array(cards.prefix(6))
        let actif = model.activeColumn == classeur.id
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: classeur.symbole)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(classeur.teinte)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(classeur.teinte.opacity(0.18)))
                Text(classeur.nom).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Spacer()
                Text("\(cards.count)")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundStyle(classeur.teinte)
                    .contentTransition(.numericText())
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(shown) { card in
                        Carte(card: card, classeur: classeur)
                            .onTapGesture { model.open(card) }
                            .onHover { dedans in
                                if dedans { model.survol = card.id } else if model.survol == card.id { model.survol = nil }
                            }
                            .contextMenu { MenuMail(id: card.id, classeurActuel: card.classeur, messageId: card.messageId, phaseTraitement: true) }
                            .draggable(card.id) {
                                Carte(card: card, classeur: classeur).frame(width: 220)
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.4, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -60)),
                                removal: .opacity
                            ))
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            if cards.count > 6 {
                Button(tout ? "Réduire" : "+ \(cards.count - 6) autres") {
                    withAnimation(.easeInOut(duration: 0.25)) { tout.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.texte3)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(actif || survolDepot ? 0.11 : 0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(actif ? Color(hex: 0x7FE3FF) : classeur.teinte.opacity(survolDepot ? 1 : 0.3), lineWidth: actif || survolDepot ? 2 : 1)
                .shadow(color: actif ? Color(hex: 0x7FE3FF) : (survolDepot ? classeur.teinte : .clear), radius: 10)
        )
        .animation(.easeInOut(duration: 0.25), value: actif)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .dropDestination(for: String.self) { ids, _ in
            guard model.phase == .termine else { return false }
            for id in ids { model.deplacerCarte(id, vers: classeur.id) }
            return true
        } isTargeted: { dedans in
            withAnimation(.easeOut(duration: 0.15)) { survolDepot = dedans && model.phase == .termine }
        }
    }
}

struct Carte: View {
    let card: MailCard
    let classeur: Classeur
    @State private var survol = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.expediteur).font(.system(size: 13, weight: .bold)).lineLimit(1)
            Text(card.objetCourt).font(.system(size: 12)).foregroundStyle(Theme.texte2).lineLimit(1)
            Pastille(texte: pastille, couleur: couleur).padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(survol ? 0.13 : 0.08)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(classeur.teinte).frame(width: 3).padding(.vertical, 8)
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { survol = $0 }
    }

    private var pastille: String {
        switch (card.action, card.statut) {
        case ("repondre", "envoye"): "Envoyée"
        case ("transferer", "transfere"): "Transféré"
        case ("transferer", _): "Transfert à valider"
        case (Classeur.aVerifierId, _): "À vérifier" + (card.confiance.map { " · \(Format.pourcent($0))" } ?? "")
        default: card.etiquette
        }
    }

    private var couleur: Color {
        card.statut == "envoye" || card.statut == "transfere" ? Color(hex: 0x6BF2A8) : classeur.teinte
    }
}

struct Bilan: View {
    let model = AppModel.shared

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .heavy))
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2))
            VStack(alignment: .leading, spacing: 3) {
                Text(model.ranger
                     ? "\(Format.pluriel(model.total, "mail traité", "mails traités")) et rangé\(model.total > 1 ? "s" : "")"
                     : Format.pluriel(model.total, "mail analysé", "mails analysés"))
                    .font(.system(size: 17, weight: .heavy))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.texte2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.violet.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
        .shadow(color: Theme.violet.opacity(0.5), radius: 18)
    }

    private var detail: String {
        model.colonnesAffichees
            .map { ($0, model.count($0.id)) }
            .filter { $0.1 > 0 }
            .map { "\($0.1) \($0.0.nom)" }
            .joined(separator: " · ")
    }
}
