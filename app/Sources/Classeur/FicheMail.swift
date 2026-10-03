import SwiftUI

struct FicheMail: View {
    let card: MailCard
    let model = AppModel.shared
    @State private var brouillon: String
    @State private var edition = false

    init(card: MailCard) {
        self.card = card
        _brouillon = State(initialValue: card.reponse)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { model.close() }
            HStack(alignment: .top, spacing: 18) {
                recu
                droite
            }
            .frame(maxWidth: 1180, maxHeight: 660)
            .padding(36)
            .overlay(alignment: .topTrailing) {
                Button { model.close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(18)
            }
        }
    }

    private var recu: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Etiquette(texte: "Le mail reçu")
                Spacer()
                Button("Ouvrir dans Mail") { model.ouvrirDansMail(card.messageId) }
                    .buttonStyle(BoutonSecondaire())
                    .controlSize(.small)
            }
            Text(card.objet)
                .font(.system(size: 21, weight: .heavy))
                .lineLimit(2)
            VStack(alignment: .leading, spacing: 3) {
                Text("De : \(card.de)")
                Text("À : \(card.a.joined(separator: ", ")) · \(Format.longue(card.date))")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.texte2)
            .textSelection(.enabled)
            Rectangle().fill(Theme.trait).frame(height: 1)
            ScrollView {
                Text(Format.lisible(card.texte ?? ""))
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0x1E1396).opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.trait, lineWidth: 1))
    }

    @ViewBuilder private var droite: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch card.action {
            case "repondre": reponse
            case "transferer": transfert
            default: action
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: 0x3524D9).opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.22), lineWidth: 1))
        .shadow(color: Theme.violet.opacity(0.55), radius: 24)
    }

    private var current: MailCard { model.cards.first { $0.id == card.id } ?? card }

    @ViewBuilder private var reponse: some View {
        let envoyee = current.statut == "envoye"
        Etiquette(texte: envoyee ? "Réponse envoyée" : "Réponse préparée par Classeur")
        Text(card.objet.lowercased().hasPrefix("re:") ? card.objet : "Re: \(card.objet)")
            .font(.system(size: 21, weight: .heavy))
            .lineLimit(2)
        Text("À : \(card.de)")
            .font(.system(size: 12))
            .foregroundStyle(Theme.texte2)
        Rectangle().fill(Theme.trait).frame(height: 1)
        Group {
            if edition {
                TextEditor(text: $brouillon)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.2)))
            } else {
                ScrollView {
                    Text(envoyee ? current.reponse : brouillon)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxHeight: .infinity)
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 10))
            Text("Rédigée à partir du mail et de vos derniers échanges · tu valides, Mail envoie")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.texte3)
        if let error = model.sheetError {
            Text(error)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0xFFB4A8))
                .textSelection(.enabled)
        }
        if !envoyee {
            HStack(spacing: 10) {
                Button { edition.toggle() } label: {
                    Label(edition ? "Terminer" : "Modifier", systemImage: edition ? "checkmark" : "pencil")
                }
                .buttonStyle(BoutonSecondaire())
                Button { model.send(card, body: brouillon) } label: {
                    HStack(spacing: 8) {
                        if model.sending { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "envelope") }
                        Text(model.sending ? "Envoi…" : "Envoyer")
                    }
                }
                .buttonStyle(BoutonPrincipal())
                .disabled(model.sending || brouillon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder private var transfert: some View {
        let fait = current.statut == "transfere"
        Etiquette(texte: fait ? "Transféré" : "Transfert proposé")
        Text("À : \(card.transfertEmail)")
            .font(.system(size: 21, weight: .heavy))
        Text(card.ligne)
            .font(.system(size: 14))
            .foregroundStyle(Theme.texte2)
        Spacer()
        if let error = model.sheetError {
            Text(error).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: 0xFFB4A8))
        }
        if !fait {
            Button { model.transfer(card) } label: {
                HStack(spacing: 8) {
                    if model.sending { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "arrowshape.turn.up.right") }
                    Text(model.sending ? "Transfert…" : "Transférer à \(card.transfertEmail)")
                }
            }
            .buttonStyle(BoutonPrincipal())
            .disabled(model.sending)
        }
    }

    @ViewBuilder private var action: some View {
        let classeur = model.classeur(card.classeur)
        Etiquette(texte: classeur.estVirtuel ? "À vérifier" : "Ce que j'en ai fait")
        Text(card.ligne)
            .font(.system(size: 19, weight: .heavy))
        Pastille(texte: classeur.nom, couleur: classeur.teinte)
        Text(texteAction(classeur))
            .font(.system(size: 13))
            .foregroundStyle(Theme.texte2)
        Spacer()
    }

    private func texteAction(_ classeur: Classeur) -> String {
        if classeur.estVirtuel {
            let suggestion = card.suggestion.map { model.classeur($0).nom } ?? "aucun classeur"
            return "Le classement n'était pas assez sûr (\(Format.pourcent(card.confiance)), suggestion : \(suggestion)). Le mail reste dans ta boîte de réception."
        }
        return model.ranger
            ? "Rangé dans le dossier « \(card.dossier) » d'Apple Mail."
            : "Serait rangé dans « \(card.dossier) ». Mode analyse : rien n'a été déplacé."
    }
}

struct ToastView: View {
    let toast: Toast
    @State private var anneau = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.6), lineWidth: 2)
                .frame(width: 300, height: 300)
                .scaleEffect(anneau ? 1.5 : 0.55)
                .opacity(anneau ? 0 : 0.9)
            HStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .heavy))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 2))
                VStack(alignment: .leading, spacing: 3) {
                    Text(toast.titre).font(.system(size: 19, weight: .heavy))
                    Text(toast.detail).font(.system(size: 12)).foregroundStyle(Theme.texte2)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: 0x3A2BE0)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: Theme.violet.opacity(0.7), radius: 26)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.3)) { anneau = true }
        }
    }
}
