import SwiftUI

struct AIDisclosureSheetView: View {
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Text("AI Disclosure")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.ink)

                Text("This app uses AI to generate transcripts, summaries, and answers. You are interacting with an AI system, not a human.")
                    .font(.body)
                    .foregroundColor(AppTheme.mutedInk)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 6)

            Button {
                onAcknowledge()
            } label: {
                Text("I Understand")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.medium])
        .background(AppTheme.background.ignoresSafeArea())
    }
}

#Preview {
    AIDisclosureSheetView(onAcknowledge: {})
}
