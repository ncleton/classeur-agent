import SwiftUI

/// Premier lancement et édition : le kanban des classeurs imaginés à partir d'un échantillon de mails.
struct Decouverte: View {
    let model = AppModel.shared
    @Namespace private var vol

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            entete
            Pile(vol: vol)
                .frame(height: 78)
            if model.ontologie.isEmpty {
                Imagination()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(model.colonnesAffichees) { c in
                        ColonneClasseur(classeur: c, vol: vol)
                            .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(24)
    }

    private var entete: some View {
        HStack(alignment: .top, spacing: 16) {
            Orbe(taille: 46, vivant: model.etape != .edition)
            VStack(alignment: .leading, spacing: 5) {
                Text(titre)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .contentTransition(.opacity)
                Text(sousTitre)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.texte2)
            }
            Spacer()
            if model.etape == .edition {
                HStack(spacing: 10) {
                    Button("Ajouter un classeur") { model.nouveauClasseur() }
                        .buttonStyle(BoutonSecondaire())
                        .disabled(model.ontologie.count >= 8)
                    Button("Reclasser l'échantillon") { model.reclasser() }
                        .buttonStyle(BoutonSecondaire())
                        .overlay(alignment: .topTrailing) {
                            if model.ontologieModifiee {
                                Circle().fill(Color(hex: 0xFFB547)).frame(width: 10, height: 10).offset(x: 3, y: -3)
                            }
                        }
                    Button("Valider mes classeurs") { model.validerClasseurs() }
                        .buttonStyle(BoutonPrincipal())
                        .frame(width: 210)
                }
            }
        }
    }

    private var titre: String {
        switch model.etape {
        case .lecture: "Je lis tes mails"
        case .imagination: "J'imagine tes classeurs"
        case .classement: "Je range l'échantillon"
        case .edition: "Voici tes classeurs"
        }
    }

    private var sousTitre: String {
        let n = model.echantillon.count
        switch model.etape {
        case .lecture: return "Je prends un échantillon de ta boîte de réception pour comprendre ce que tu reçois."
        case .imagination: return "\(Format.pluriel(n, "mail lu", "mails lus")). Je cherche les grandes familles qui structurent ta boîte."
        case .classement: return "Chaque mail rejoint le classeur dont la définition lui correspond le mieux."
        case .edition:
            return model.ontologieModifiee
                ? "Tes classeurs ont changé. Reclasse l'échantillon pour voir le nouveau rangement."
                : "\(Format.pluriel(n, "mail rangé", "mails rangés")). Ouvre les réglages d'une colonne pour définir ce qu'elle contient."
        }
    }
}

struct Pile: View {
    let model = AppModel.shared
    let vol: Namespace.ID

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Boîte de réception")
                    .font(.system(size: 13, weight: .bold))
                Text(model.pile.isEmpty ? "Tout est rangé" : Format.pluriel(model.pile.count, "mail à ranger", "mails à ranger"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.texte3)
                    .contentTransition(.numericText())
            }
            .frame(width: 150, alignment: .leading)
            if model.pile.isEmpty && model.echantillon.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Lecture de ta boîte de réception…")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.texte3)
                }
            }
            HStack(spacing: -118) {
                ForEach(Array(model.pile.prefix(10).enumerated()), id: \.element) { index, id in
                    if let item = model.echantillon.first(where: { $0.id == id }) {
                        MiniCarte(item: item, couleur: .white, confiance: nil)
                            .frame(width: 168)
                            .matchedGeometryEffect(id: id, in: vol)
                            .zIndex(Double(20 - index))
                            .rotationEffect(.degrees(Double(index) * 0.6))
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.trait, lineWidth: 1))
    }
}

struct Imagination: View {
    var body: some View {
        VStack(spacing: 14) {
            Orbe(taille: 70, vivant: true)
            Text("Je compare les expéditeurs, les sujets et ce que chaque mail attend de toi.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.texte2)
        }
    }
}

struct MiniCarte: View {
    let item: InboxItem
    let couleur: Color
    let confiance: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(couleur.opacity(0.9))
                Text(Format.nom(item.de))
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let confiance {
                    Text(Format.pourcent(confiance))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0xFF9A7A))
                }
            }
            Text(item.objet)
                .font(.system(size: 11))
                .foregroundStyle(Theme.texte2)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0x3A2BD8)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

/// Rend toute la tuile cliquable, avec la main au survol, pour ouvrir le mail dans Apple Mail.
struct OuvreDansMail: ViewModifier {
    let id: String?
    var aide: String? = nil
    let action: () -> Void
    @State private var survol = false

    func body(content: Content) -> some View {
        content
            .brightness(survol ? 0.07 : 0)
            .scaleEffect(survol ? 1.015 : 1)
            .animation(.easeOut(duration: 0.12), value: survol)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onTapGesture(perform: action)
            .onHover { dedans in
                guard dedans != survol else { return }
                survol = dedans
                if let id {
                    if dedans { AppModel.shared.survol = id } else if AppModel.shared.survol == id { AppModel.shared.survol = nil }
                }
                if dedans { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear { if survol { NSCursor.pop(); survol = false } }
            .help(aide ?? "Ouvrir dans \(AppModel.shared.messagerie.nom)")
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(aide ?? "Ouvre ce mail dans \(AppModel.shared.messagerie.nom)")
            .accessibilityAction { action() }
    }
}

extension View {
    func ouvreDansMail(id: String? = nil, aide: String? = nil, _ action: @escaping () -> Void) -> some View {
        modifier(OuvreDansMail(id: id, aide: aide, action: action))
    }
}

/// Menu du clic droit d'un mail : ouvrir, déplacer vers un autre classeur, supprimer.
struct MenuMail: View {
    let id: String
    let classeurActuel: String
    let messageId: String?
    let phaseTraitement: Bool
    let model = AppModel.shared

    var body: some View {
        Button("Ouvrir dans \(model.messagerie.nom)") { model.ouvrirDansMail(messageId) }
        if phaseTraitement, let card = model.cards.first(where: { $0.id == id }), card.action == "repondre", !card.reponse.isEmpty {
            Button("Répondre dans \(model.messagerie.nom) avec la réponse préparée") { model.repondreDansMail(card) }
        }
        if phaseTraitement, let card = model.cards.first(where: { $0.id == id }), card.action == "transferer", card.statut != "transfere", !card.transfertEmail.isEmpty {
            Button("Transférer à \(card.transfertEmail)") { model.transfer(card) }
        }
        Menu("Déplacer vers") {
            ForEach(model.colonnesAffichees.filter { $0.id != classeurActuel }) { c in
                Button(c.nom) {
                    if phaseTraitement { model.deplacerCarte(id, vers: c.id) } else { model.deplacerEchantillon(id, vers: c.id) }
                }
            }
        }
        Divider()
        Button("Supprimer", role: .destructive) { model.supprimer(id) }
    }
}

struct ColonneClasseur: View {
    let classeur: Classeur
    let vol: Namespace.ID
    let model = AppModel.shared
    private let maxCartes = 9
    @State private var survolDepot = false

    var body: some View {
        let ids = model.colonnes[classeur.id] ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: classeur.symbole)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(classeur.teinte)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(classeur.teinte.opacity(0.18)))
                Text(classeur.nom)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(ids.count)")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(classeur.teinte)
                    .contentTransition(.numericText())
                if !classeur.estVirtuel {
                    Button { model.ouvrirReglages(classeur) } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Réglages du classeur « \(classeur.nom) »")
                    .disabled(model.etape != .edition)
                }
            }
            Text(classeur.definition)
                .font(.system(size: 11))
                .foregroundStyle(Theme.texte3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(classeur.actionLibelle.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(classeur.teinte.opacity(0.9))
            VStack(spacing: 6) {
                ForEach(ids.prefix(maxCartes), id: \.self) { id in
                    if let item = model.echantillon.first(where: { $0.id == id }) {
                        let aff = model.affectations[id]
                        MiniCarte(item: item, couleur: classeur.teinte, confiance: aff?.incertain == true ? aff?.confiance : nil)
                            .overlay(alignment: .bottomTrailing) {
                                if aff?.manuel == true {
                                    Image(systemName: "hand.point.up.left.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(classeur.teinte)
                                        .padding(6)
                                        .help("Classé à la main")
                                }
                            }
                            .ouvreDansMail(id: id) { model.ouvrirDansMail(item.messageId) }
                            .contextMenu { MenuMail(id: id, classeurActuel: classeur.id, messageId: item.messageId, phaseTraitement: false) }
                            .draggable(id) {
                                MiniCarte(item: item, couleur: classeur.teinte, confiance: nil).frame(width: 200)
                            }
                            .matchedGeometryEffect(id: id, in: vol)
                    }
                }
            }
            if ids.count > maxCartes {
                Text("+ \(ids.count - maxCartes) autres")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.texte3)
                    .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(survolDepot ? 0.12 : 0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(classeur.teinte.opacity(survolDepot ? 1 : 0.35), lineWidth: survolDepot ? 2 : 1)
                .shadow(color: survolDepot ? classeur.teinte : .clear, radius: 10)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .dropDestination(for: String.self) { ids, _ in
            guard model.etape == .edition else { return false }
            for id in ids { model.deplacerEchantillon(id, vers: classeur.id) }
            return true
        } isTargeted: { dedans in
            withAnimation(.easeOut(duration: 0.15)) { survolDepot = dedans && model.etape == .edition }
        }
    }
}

/// Réglages d'un classeur : sa définition dans l'ontologie, son action et son dossier.
struct ReglagesClasseur: View {
    let model = AppModel.shared
    @State private var draft: Classeur
    @State private var inclure: String
    @State private var exclure: String
    @State private var exemples: String
    private let nouveau: Bool

    init(classeur: Classeur, nouveau: Bool) {
        _draft = State(initialValue: classeur)
        _inclure = State(initialValue: classeur.inclure.joined(separator: "\n"))
        _exclure = State(initialValue: classeur.exclure.joined(separator: "\n"))
        _exemples = State(initialValue: classeur.exemples.joined(separator: "\n"))
        self.nouveau = nouveau
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { model.fermerReglages() }
            HStack(alignment: .top, spacing: 18) {
                formulaire
                if !nouveau { echantillon.frame(width: 320) }
            }
            .padding(24)
            .frame(maxWidth: 1080, maxHeight: 700)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x23179E)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
            .shadow(color: Theme.violet.opacity(0.5), radius: 30)
            .padding(30)
        }
    }

    private var formulaire: some View {
        VStack(alignment: .leading, spacing: 14) {
            Etiquette(texte: nouveau ? "Nouveau classeur" : "Réglages du classeur")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Nom du classeur", text: $draft.nom)
                        .textFieldStyle(.plain)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .padding(.vertical, 4)
                    Champ(titre: "Définition", aide: "Ce que ce classeur contient et pourquoi il existe. Jev s'en sert pour décider.") {
                        Editeur(texte: $draft.definition, hauteur: 64)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Champ(titre: "Ce qui y entre", aide: "Un critère par ligne.") { Editeur(texte: $inclure, hauteur: 92) }
                        Champ(titre: "Ce qui n'y entre pas", aide: "Un critère par ligne, avec le classeur où vont ces mails.") { Editeur(texte: $exclure, hauteur: 92) }
                    }
                    Champ(titre: "Exemples", aide: "Des mails typiques, un par ligne.") { Editeur(texte: $exemples, hauteur: 64) }
                    Champ(titre: "Action", aide: aideAction) {
                        Picker("Action", selection: $draft.action) {
                            Text("Répondre").tag("repondre")
                            Text("Transférer").tag("transferer")
                            Text("Ranger").tag("ranger")
                            Text("Archiver").tag("archiver")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    if draft.action == "transferer" {
                        Champ(titre: "Transférer à", aide: "Adresse du destinataire.") {
                            Saisie(texte: $draft.transfertEmail, placeholder: "compta@cabinet.fr")
                        }
                        Toggle("Transférer automatiquement, sans validation", isOn: $draft.transfertAuto)
                            .toggleStyle(.switch)
                            .font(.system(size: 13))
                    }
                    Champ(titre: "Dossier Apple Mail", aide: "Créé sous « Classeur/ » dans chaque compte concerné.") {
                        HStack(spacing: 4) {
                            Text("Classeur/").font(.system(size: 13)).foregroundStyle(Theme.texte3)
                            Saisie(texte: $draft.dossier, placeholder: draft.nom.isEmpty ? "Nom du dossier" : draft.nom)
                        }
                    }
                    Champ(titre: "Couleur et icône", aide: nil) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                ForEach(Theme.couleurs, id: \.self) { nom in
                                    Circle()
                                        .fill(Theme.palette[nom] ?? .white)
                                        .frame(width: 22, height: 22)
                                        .overlay(Circle().stroke(.white, lineWidth: draft.couleur == nom ? 2 : 0))
                                        .onTapGesture { draft.couleur = nom }
                                }
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 10), alignment: .leading, spacing: 6) {
                                ForEach(Theme.symboles, id: \.self) { symbole in
                                    Image(systemName: symbole)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(draft.symbole == symbole ? draft.teinte : Theme.texte2)
                                        .frame(width: 30, height: 30)
                                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(draft.symbole == symbole ? 0.16 : 0.05)))
                                        .onTapGesture { draft.symbole = symbole }
                                }
                            }
                        }
                    }
                }
                .padding(.trailing, 6)
            }
            if let erreur = model.reglageErreur ?? validation {
                Text(erreur)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: 0xFFB4A8))
            }
            HStack(spacing: 10) {
                if !nouveau {
                    Button("Supprimer ce classeur") { model.supprimer(draft) }
                        .buttonStyle(BoutonSecondaire())
                        .disabled(model.ontologie.count <= 2)
                }
                Spacer()
                Button("Annuler") { model.fermerReglages() }
                    .buttonStyle(BoutonSecondaire())
                    .keyboardShortcut(.cancelAction)
                Button("Enregistrer") { model.enregistrer(final) }
                    .buttonStyle(BoutonPrincipal())
                    .frame(width: 180)
                    .disabled(validation != nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var echantillon: some View {
        let ids = model.colonnes[draft.id] ?? []
        return VStack(alignment: .leading, spacing: 10) {
            Etiquette(texte: "Dans ce classeur")
            Text(Format.pluriel(ids.count, "mail de l'échantillon", "mails de l'échantillon"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.texte2)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(ids, id: \.self) { id in
                        if let item = model.echantillon.first(where: { $0.id == id }) {
                            MiniCarte(item: item, couleur: draft.teinte, confiance: model.affectations[id]?.confiance)
                                .ouvreDansMail { model.ouvrirDansMail(item.messageId) }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.18)))
    }

    private var aideAction: String {
        switch draft.action {
        case "repondre": "Classeur prépare une réponse que tu valides avant l'envoi. Les mails restent non lus."
        case "transferer": "Le mail part chez le destinataire indiqué, après ta validation ou automatiquement."
        case "archiver": "Le mail est marqué lu et rangé hors de la boîte de réception."
        default: "Le mail est marqué lu et rangé dans le dossier du classeur."
        }
    }

    private var final: Classeur {
        var c = draft
        c.nom = c.nom.trimmingCharacters(in: .whitespaces)
        c.definition = c.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        c.inclure = lignes(inclure)
        c.exclure = lignes(exclure)
        c.exemples = lignes(exemples)
        c.dossier = c.dossier.trimmingCharacters(in: .whitespaces).isEmpty ? c.nom : c.dossier.trimmingCharacters(in: .whitespaces)
        if c.action != "transferer" { c.transfertEmail = ""; c.transfertAuto = false }
        return c
    }

    private var validation: String? {
        if draft.nom.trimmingCharacters(in: .whitespaces).isEmpty { return "Donne un nom à ce classeur." }
        if draft.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Écris la définition du classeur : c'est elle qui guide le classement." }
        if draft.action == "transferer" && !draft.transfertEmail.contains("@") { return "Indique l'adresse vers laquelle transférer." }
        let dossier = final.dossier.lowercased()
        if model.ontologie.contains(where: { $0.id != draft.id && $0.dossier.lowercased() == dossier }) { return "Un autre classeur utilise déjà le dossier « \(final.dossier) »." }
        return nil
    }

    private func lignes(_ texte: String) -> [String] {
        texte.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

struct Champ<Contenu: View>: View {
    let titre: String
    let aide: String?
    @ViewBuilder let contenu: () -> Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titre.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(Theme.texte2)
            contenu()
            if let aide {
                Text(aide).font(.system(size: 11)).foregroundStyle(Theme.texte3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Editeur: View {
    @Binding var texte: String
    let hauteur: CGFloat

    var body: some View {
        TextEditor(text: $texte)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(height: hauteur)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

struct Saisie: View {
    @Binding var texte: String
    let placeholder: String

    var body: some View {
        TextField(placeholder, text: $texte)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}
