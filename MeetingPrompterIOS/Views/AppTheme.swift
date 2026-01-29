import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let backgroundElevated = Color(red: 0.09, green: 0.10, blue: 0.13)
    static let surface = Color(red: 0.12, green: 0.13, blue: 0.16)
    static let surfaceAlt = Color(red: 0.16, green: 0.17, blue: 0.21)

    static let ink = Color(red: 0.94, green: 0.95, blue: 0.98)
    static let mutedInk = Color(red: 0.63, green: 0.67, blue: 0.72)

    static let accent = Color(red: 0.30, green: 0.69, blue: 0.72)
    static let charcoal = Color(red: 0.08, green: 0.09, blue: 0.12)

    static let hairline = Color.white.opacity(0.08)
    static let divider = Color.white.opacity(0.12)
    static let shadowSoft = Color.black.opacity(0.35)
    static let shadowStrong = Color.black.opacity(0.55)

    static let cardRadius: CGFloat = 18

    static func actionGradient(tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                charcoal,
                charcoal.opacity(0.92),
                tint.opacity(0.28),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct HomeActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.82))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(16)
        .background(AppTheme.actionGradient(tint: tint))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(AppTheme.hairline, lineWidth: 1)
        )
        .shadow(color: AppTheme.shadowSoft, radius: 14, x: 0, y: 8)
    }
}
