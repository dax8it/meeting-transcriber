import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.965, green: 0.965, blue: 0.985)
    static let surface = Color.white
    static let surfaceAlt = Color(red: 0.94, green: 0.94, blue: 0.965)

    static let ink = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let mutedInk = Color(red: 0.32, green: 0.34, blue: 0.38)

    static let accent = Color(red: 0.10, green: 0.33, blue: 0.64)
    static let charcoal = Color(red: 0.10, green: 0.11, blue: 0.14)

    static let cardRadius: CGFloat = 18

    static func actionGradient(tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                charcoal,
                charcoal.opacity(0.92),
                tint.opacity(0.70),
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
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
    }
}
