import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @ObservedObject private var mainViewModel = MainViewModel.shared
    @AppStorage("voiceQAEnabled") private var voiceQAEnabled: Bool = false
    @AppStorage("speakAnswersEnabled") private var speakAnswersEnabled: Bool = false
    @State private var isHoldingPTT = false
    @State private var pttAutoStopTask: Task<Void, Never>? = nil

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
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            viewModel.speakRepliesEnabled = speakAnswersEnabled
        }
        .onChange(of: speakAnswersEnabled) { _, newValue in
            viewModel.speakRepliesEnabled = newValue
        }
        .onDisappear {
            pttAutoStopTask?.cancel()
            pttAutoStopTask = nil
        }
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

                if voiceQAEnabled {
                    pttButton
                }

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

                Toggle("Speak answers", isOn: $speakAnswersEnabled)
                    .font(.caption)
                    .disabled(!voiceQAEnabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 1),
            alignment: .top
        )
    }

    private var voiceStatusText: String {
        if !voiceQAEnabled {
            return "Voice Q&A: Off"
        }
        if mainViewModel.appState.isRecording {
            return "Voice Q&A unavailable while recording"
        }

        switch viewModel.voiceState {
        case .idle:
            return "Voice: Idle"
        case .listening:
            return "Voice: Listening"
        case .transcribing:
            return "Voice: Transcribing"
        case .thinking:
            return "Voice: Thinking"
        case .speaking:
            return "Voice: Speaking"
        case .error(let message):
            return "Voice error: \(message)"
        }
    }

    private var voiceStatusColor: Color {
        if !voiceQAEnabled || mainViewModel.appState.isRecording {
            return AppTheme.mutedInk
        }

        switch viewModel.voiceState {
        case .idle:
            return AppTheme.mutedInk
        case .listening:
            return AppTheme.ink
        case .transcribing, .thinking, .speaking:
            return AppTheme.mutedInk
        case .error:
            return .red
        }
    }

    private var pttButton: some View {
        let meetingRecordingActive = mainViewModel.appState.isRecording
        let disabled = viewModel.isBusy || viewModel.voiceState.isTranscribing || meetingRecordingActive

        return Button(action: {}) {
            Group {
                if viewModel.voiceState.isTranscribing {
                    ProgressView()
                } else {
                    Image(systemName: viewModel.voiceState.isListening ? "waveform.circle.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundColor(AppTheme.ink)
            .frame(width: 40, height: 40)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel("Push to talk")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isHoldingPTT else { return }
                    isHoldingPTT = true
                    startPTT()
                }
                .onEnded { _ in
                    isHoldingPTT = false
                    stopPTT()
                }
        )
    }

    private func startPTT() {
        pttAutoStopTask?.cancel()
        viewModel.startRecording(isMeetingRecording: mainViewModel.appState.isRecording)
        pttAutoStopTask = Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await MainActor.run {
                if viewModel.voiceState.isListening {
                    stopPTT()
                }
            }
        }
    }

    private func stopPTT() {
        pttAutoStopTask?.cancel()
        pttAutoStopTask = nil
        viewModel.stopRecordingAndTranscribe()
    }
}
