import SwiftUI

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
