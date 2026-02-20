import SwiftUI

struct ChatBubble: View {
    let message: ChatMessage
    let audioShareURL: URL?

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            Group {
                if message.role == .assistant {
                    MarkdownRenderer(text: message.text)
                } else {
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            .foregroundColor(message.role == .user ? .white : AppTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            Text(timestampString(message.timestamp))
                .font(.caption2)
                .foregroundColor(AppTheme.mutedInk)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant,
               let audioShareURL {
                ShareLink(item: audioShareURL) {
                    Label("Share audio", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if message.role == .assistant, let sources = message.sources, !sources.isEmpty {
                DisclosureGroup("Sources") {
                    SourcesView(sources: sources)
                }
                .font(.subheadline)
                .tint(AppTheme.accent)
            }
        }
    }

    private var bubbleBackground: some View {
        Group {
            if message.role == .user {
                AppTheme.actionGradient(tint: AppTheme.accent)
            } else {
                AppTheme.surfaceAlt
            }
        }
    }

    private func timestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
