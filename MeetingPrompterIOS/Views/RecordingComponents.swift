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
    let countdownValue: Int?
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button {
                onToggle(!isRecording)
            } label: {
                ZStack {
                    Circle()
                        .stroke((isRecording ? Color.red : AppTheme.accent).opacity(0.30), lineWidth: 10)
                        .frame(width: 146, height: 146)
                        .scaleEffect(isRecording ? 1.0 : 0.94)

                    Circle()
                        .fill(isRecording ? Color.red : AppTheme.accent)
                        .frame(width: 116, height: 116)
                        .shadow(color: AppTheme.shadowStrong, radius: 16, x: 0, y: 10)

                    if let countdownValue {
                        Text("\(countdownValue)")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.80), value: isRecording)
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
            .accessibilityHint("Double tap to toggle meeting recording")
            .accessibilityAddTraits(.isButton)
            .frame(minWidth: 146, minHeight: 146)
            .contentShape(Circle())

            Text(buttonSubtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppTheme.mutedInk)
        }
    }

    private var buttonSubtitle: String {
        if let countdownValue {
            return "Starting in \(countdownValue)…"
        }
        return isRecording ? "Tap to stop" : "Tap to start"
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
        if status.contains("Starting") || status.contains("Preparing") {
            return .orange
        }
        if status.contains("Error") {
            return .red
        }
        return .green
    }
}
