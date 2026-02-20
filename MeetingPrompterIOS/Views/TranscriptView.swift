import SwiftUI

struct TranscriptView: View {
    @ObservedObject var viewModel: MainViewModel

    private let bottomAnchor = "transcript-bottom"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript")
                    .font(.headline)
                    .foregroundColor(AppTheme.ink)
                
                if !viewModel.transcriptLive.isEmpty {
                    Text("(live)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                if let countdown = viewModel.preRecordingCountdown {
                    Text("Start \(countdown)…")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.surfaceAlt)
                        .clipShape(Capsule())
                } else if viewModel.appState.isRecording {
                    Text("Rec \(viewModel.recordingElapsedDisplay)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.surfaceAlt)
                        .clipShape(Capsule())
                } else if viewModel.appState.isPaused {
                    Text("Paused \(viewModel.recordingElapsedDisplay)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.surfaceAlt)
                        .clipShape(Capsule())
                }
                
                Spacer()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(displayedTranscript.isEmpty ? "No transcript yet..." : displayedTranscript)
                        .font(.body)
                        .foregroundColor(displayedTranscript.isEmpty ? AppTheme.mutedInk : AppTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.surface)

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .onAppear {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
                .onChange(of: displayedTranscript) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
            }
            .frame(minHeight: 260, maxHeight: 320)
            .scrollContentBackground(.hidden)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, 0)
        .background(AppTheme.background)
    }

    private var displayedTranscript: String {
        if !viewModel.transcriptLive.isEmpty {
            return viewModel.transcriptLive
        }
        return viewModel.transcriptFinal
    }
}
