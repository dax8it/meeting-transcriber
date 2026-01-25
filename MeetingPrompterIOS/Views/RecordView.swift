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

                Spacer()

                PushToTalkButton(
                    isRecording: Binding(
                        get: { viewModel.appState.isRecording },
                        set: { _ in }
                    ),
                    onToggle: { isRecording in
                        if isRecording {
                            viewModel.startRecording()
                        } else {
                            viewModel.stopRecording()
                        }
                    }
                )

                StatusIndicator(status: viewModel.statusText)
            }
        }
        .padding(20)
        .background(AppTheme.background.ignoresSafeArea())
        .tint(AppTheme.ink)
        .navigationTitle("Transcribe")
        .navigationBarTitleDisplayMode(.inline)
    }
}
