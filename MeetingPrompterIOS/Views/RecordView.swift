import SwiftUI

struct RecordView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VStack(spacing: 18) {
            RecordingHeaderView()

            if viewModel.isInitializing {
                ProgressView("Loading models...")
                    .padding()
            } else {
                TranscriptView(viewModel: viewModel)

                PushToTalkButton(
                    isRecording: Binding(
                        get: { viewModel.appState.isRecording || viewModel.appState.isCountdown || viewModel.appState.isPaused },
                        set: { _ in }
                    ),
                    countdownValue: viewModel.preRecordingCountdown,
                    onToggle: { isRecording in
                        if isRecording {
                            viewModel.startRecording()
                        } else {
                            viewModel.stopRecording()
                        }
                    }
                )

                if viewModel.appState.isRecording || viewModel.appState.isPaused {
                    Button {
                        if viewModel.appState.isPaused {
                            viewModel.resumeRecording()
                        } else {
                            viewModel.pauseRecording()
                        }
                    } label: {
                        Label(
                            viewModel.appState.isPaused ? "Resume" : "Pause",
                            systemImage: viewModel.appState.isPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(viewModel.appState.isPaused ? AppTheme.accent : .orange)
                    .accessibilityHint("Temporarily pause or resume transcript capture")
                }

                StatusIndicator(status: viewModel.statusText)
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .background(AppTheme.background.ignoresSafeArea())
        .tint(AppTheme.accent)
        .navigationTitle("Transcribe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
