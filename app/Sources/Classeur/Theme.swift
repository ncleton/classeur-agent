import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Theme {
    static let haut = Color(hex: 0x2C1FD8)
    static let bas = Color(hex: 0x150B78)
    static let violet = Color(hex: 0x7B5CFF)
    static let violetFonce = Color(hex: 0x5B3EF0)
    static let carte = Color.white.opacity(0.07)
    static let trait = Color.white.opacity(0.14)
    static let texte2 = Color.white.opacity(0.78)
    static let texte3 = Color.white.opacity(0.55)

    static let palette: [String: Color] = [
        "violet": Color(hex: 0xA996FF),
        "cyan": Color(hex: 0x5AD8FF),
        "ambre": Color(hex: 0xFFB547),
        "citron": Color(hex: 0xE4E36F),
        "bleu": Color(hex: 0x7FA8FF),
        "vert": Color(hex: 0x6BF2A8),
        "rose": Color(hex: 0xFF8FC7),
        "corail": Color(hex: 0xFF9A7A),
    ]
    static let couleurs = ["violet", "cyan", "ambre", "citron", "bleu", "vert", "rose", "corail"]
    static let symboles = [
        "arrowshape.turn.up.left.fill", "arrowshape.turn.up.right.fill", "doc.text.fill", "signature",
        "archivebox.fill", "person.2.fill", "cart.fill", "calendar", "briefcase.fill", "creditcard.fill",
        "megaphone.fill", "bell.fill", "building.columns.fill", "shippingbox.fill", "star.fill",
        "exclamationmark.bubble.fill", "newspaper.fill", "lock.fill", "wrench.and.screwdriver.fill", "heart.fill",
    ]
}

struct Fond: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.haut, Theme.bas], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: 0x6B4BFF, opacity: 0.45), .clear], center: .topTrailing, startRadius: 10, endRadius: 700)
            Etoiles()
        }
        .ignoresSafeArea()
    }
}

struct Etoiles: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 42
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(UInt32.max >> 1)
            }
            for _ in 0..<170 {
                let x = next() * size.width
                let y = next() * size.height
                let r = 0.4 + next() * 1.2
                let a = 0.15 + next() * 0.5
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

struct Orbe: View {
    var taille: CGFloat
    var vivant: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: [.white, Color(hex: 0xE0D6FF), Color(hex: 0x9C82FF), Color(hex: 0x5B3EF0)],
                center: UnitPoint(x: 0.35, y: 0.3),
                startRadius: 1,
                endRadius: taille * 0.75
            ))
            .frame(width: taille, height: taille)
            .shadow(color: Color(hex: 0xB9A6FF).opacity(0.8), radius: pulse ? taille * 0.45 : taille * 0.22)
            .scaleEffect(pulse ? 1.05 : 1)
            .onAppear { animer() }
            .onChange(of: vivant) { _, _ in animer() }
    }

    private func animer() {
        if vivant {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        } else {
            withAnimation(.easeOut(duration: 0.4)) { pulse = false }
        }
    }
}

struct Pastille: View {
    var texte: String
    var couleur: Color

    var body: some View {
        Text(texte)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(couleur)
            .background(Capsule().fill(couleur.opacity(0.15)))
            .overlay(Capsule().stroke(couleur.opacity(0.55), lineWidth: 1))
    }
}

struct Panneau: ViewModifier {
    var rayon: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: rayon, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: rayon, style: .continuous).stroke(Theme.trait, lineWidth: 1))
    }
}

extension View {
    func panneau(_ rayon: CGFloat = 18) -> some View { modifier(Panneau(rayon: rayon)) }
}

struct BoutonPrincipal: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x8C6CFF), Theme.violetFonce], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
            .shadow(color: Theme.violet.opacity(0.6), radius: configuration.isPressed ? 4 : 12)
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}

struct BoutonSecondaire: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
    }
}

struct Etiquette: View {
    var texte: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.white).frame(width: 7, height: 7).shadow(color: .white, radius: 4)
            Text(texte.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.texte2)
        }
    }
}
