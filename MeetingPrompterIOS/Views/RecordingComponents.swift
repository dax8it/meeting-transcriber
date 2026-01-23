import SwiftUI

struct RecordingHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcribe")
                .font(.largeTitle)
                .fontWeight(.black)
                .foregroundColor(AppTheme.ink)

            Text("Tap the mic to start recording.")
                .font(.subheadline)
                .foregroundColor(AppTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
}

struct PushToTalkButton: View {
    @Binding var isRecording: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isRecording)
        } label: {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : AppTheme.accent)
                    .frame(width: 104, height: 104)
                    .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 10)
                    .animation(.spring(response: 0.30, dampingFraction: 0.78), value: isRecording)

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

struct StatusIndicator: View {
    let status: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status)
                .font(.caption)
                .foregroundColor(AppTheme.mutedInk)
        }
        .padding(.bottom)
    }

    private var statusColor: Color {
        if status.contains("Loading") || status.contains("Processing") || status.contains("Generating") {
            return .orange
        }
        if status.contains("Error") {
            return .red
        }
        return .green
    }
}
