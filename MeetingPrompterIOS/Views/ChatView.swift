import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel

    init(session: MeetingSession) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    guard let lastID = viewModel.messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            if viewModel.isBusy {
                HStack {
                    ProgressView("Generating...")
                        .padding(.horizontal)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .background(AppTheme.background)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(AppTheme.background)
            }

            inputBar
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var inputBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                TextField("Message...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .disabled(viewModel.isBusy)
                    .onSubmit { viewModel.send() }

                Button {
                    if viewModel.voiceState.isRecording {
                        viewModel.stopRecordingAndTranscribe()
                    } else {
                        viewModel.startRecording()
                    }
                } label: {
                    Group {
                        if viewModel.voiceState.isTranscribing {
                            ProgressView()
                        } else {
                            Image(systemName: viewModel.voiceState.isRecording ? "stop.circle.fill" : "mic.fill")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                    .foregroundColor(AppTheme.ink)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isBusy || viewModel.voiceState.isTranscribing)
                .accessibilityLabel(viewModel.voiceState.isRecording ? "Stop recording" : "Start recording")

                Button {
                    viewModel.send()
                } label: {
                    Text("Send")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppTheme.actionGradient(tint: AppTheme.accent))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isBusy || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 10) {
                Text(voiceStatusText)
                    .font(.caption)
                    .foregroundColor(voiceStatusColor)

                Spacer(minLength: 0)

                Toggle("Speak replies (coming soon)", isOn: $viewModel.speakRepliesEnabled)
                    .font(.caption)
                    .disabled(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1),
            alignment: .top
        )
    }

    private var voiceStatusText: String {
        switch viewModel.voiceState {
        case .idle:
            return "Voice: Idle"
        case .recording:
            return "Voice: Recording"
        case .transcribing:
            return "Voice: Transcribing"
        case .error(let message):
            return "Voice error: \(message)"
        }
    }

    private var voiceStatusColor: Color {
        switch viewModel.voiceState {
        case .idle:
            return AppTheme.mutedInk
        case .recording:
            return AppTheme.ink
        case .transcribing:
            return AppTheme.mutedInk
        case .error:
            return .red
        }
    }
}
