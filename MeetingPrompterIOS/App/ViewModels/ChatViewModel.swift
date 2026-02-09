import AVFoundation
import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    enum VoiceState: Equatable {
        case idle
        case listening
        case transcribing
        case thinking
        case speaking
        case error(String)

        var isListening: Bool {
            if case .listening = self { return true }
            return false
        }

        var isTranscribing: Bool {
            if case .transcribing = self { return true }
            return false
        }
    }

    enum ChatVoiceError: LocalizedError {
        case microphonePermissionDenied
        case recordingUnavailable

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone permission denied"
            case .recordingUnavailable:
                return "Unable to start recording"
            }
        }
    }

    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isBusy: Bool = false
    @Published var errorMessage: String? = nil

    @Published var voiceState: VoiceState = .idle
    @Published var speakRepliesEnabled: Bool = false

    let session: MeetingSession

    private let chatStore = ChatStore.shared
    private let fileStore = FileStore.shared
    private let searchIndex = SearchIndex.shared
    private let ragService = RAGService.shared
    private let audioCapture = AudioCaptureService.shared
    private let asrService = ASRService.shared
    private let ttsService = TTSService.shared

    private let maxHistoryMessages = 10
    private let maxPersistedSources = 8

    private var lastVoiceSamples: [Float] = []
    private var audioSessionSnapshot: (category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)?

    init(session: MeetingSession) {
        self.session = session
        Task { await loadHistoryAndIndex() }
    }

    func startRecording(isMeetingRecording: Bool = false) {
        guard !isBusy else { return }
        guard !voiceState.isListening && !voiceState.isTranscribing else { return }
        guard !isMeetingRecording else {
            voiceState = .error("Voice Q&A unavailable while recording")
            return
        }

        print("[ChatVoice] start")
        voiceState = .listening

        Task {
            do {
                try await ensureMicrophonePermission()
                try await configureAudioSessionForRecordingIfNeeded()
                await audioCapture.clearBuffer()
                try await audioCapture.startCapture { _ in }
            } catch {
                print("[ChatVoice] start failed: \(error)")
                voiceState = .error(error.localizedDescription)
                await audioCapture.stopCapture()
                await audioCapture.clearBuffer()
                await restoreAudioSessionIfNeeded()
            }
        }
    }

    func stopRecordingAndTranscribe() {
        guard voiceState.isListening else { return }

        print("[ChatVoice] stop → transcribing")
        voiceState = .transcribing

        Task {
            await audioCapture.stopCapture()
            let samples = await audioCapture.getFullBuffer()
            await audioCapture.clearBuffer()
            lastVoiceSamples = samples
            await restoreAudioSessionIfNeeded()

            guard !samples.isEmpty else {
                print("[ChatVoice] empty buffer")
                voiceState = .error("No speech detected")
                return
            }

            let transcript = await asrService.transcribe(samples: samples)
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[ChatVoice] transcript len=\(trimmed.count)")

            guard !trimmed.isEmpty else {
                print("[ChatVoice] empty transcript")
                voiceState = .error("No speech detected")
                return
            }

            inputText = trimmed
            print("[ChatVoice] auto-send")
            send()
        }
    }

    func send() {
        let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isBusy else { return }
        let voiceOriginated = voiceState.isTranscribing
        if voiceOriginated {
            voiceState = .thinking
        }

        print("[Chat] send len=\(q.count)")

        errorMessage = nil
        isBusy = true
        inputText = ""

        let userMessage = ChatMessage(role: .user, text: q, sessionID: session.id)
        messages.append(userMessage)

        let afterUserSnapshot = messages
        Task {
            do {
                try await chatStore.saveMessages(afterUserSnapshot, for: session)
                print("[Chat] saved=\(afterUserSnapshot.count)")
            } catch {
                print("[Chat] save failed: \(error)")
            }

            defer { self.isBusy = false }

            do {
                // Retrieve evidence from the meeting-scoped index.
                let retrieved = (try? await searchIndex.searchMeeting(session: session, query: q, topK: 10)) ?? []
                let summaryChunks = (try? await searchIndex.fetchMeetingChunks(session: session, title: "Summary", limit: 4)) ?? []

                var mergedByID: [String: DocumentChunk] = [:]
                for c in retrieved { mergedByID[c.id] = c }
                for c in summaryChunks { mergedByID[c.id] = c }
                let mergedChunks = Array(mergedByID.values)

                print("[Chat] retrieved=\(retrieved.count), merged=\(mergedChunks.count)")

                guard !mergedChunks.isEmpty else {
                    let fallbackAnswer = "Not enough evidence in sources."
                    let assistant = ChatMessage(
                        role: .assistant,
                        text: fallbackAnswer,
                        sources: nil,
                        sessionID: session.id
                    )
                    self.messages.append(assistant)
                    try? await chatStore.saveMessages(self.messages, for: self.session)
                    await self.speakAssistantAnswerIfNeeded(fallbackAnswer)
                    if voiceOriginated {
                        self.voiceState = .idle
                    }
                    print("[Chat] saved=\(self.messages.count)")
                    return
                }

                // Stable ordering: retrieved first, then summary extras.
                let ordered = retrieved + summaryChunks.filter { sc in
                    !retrieved.contains(where: { $0.id == sc.id })
                }
                let deduped = ordered.reduce(into: [DocumentChunk]()) { acc, c in
                    if !acc.contains(where: { $0.id == c.id }) { acc.append(c) }
                }

                let composedPrompt = self.buildComposedPrompt(currentQuestion: q)
                let result = try await ragService.generateAnswer(question: composedPrompt, chunks: deduped)
                let cappedSources = Array(result.sources.prefix(self.maxPersistedSources))

                let assistant = ChatMessage(
                    role: .assistant,
                    text: result.answer,
                    sources: cappedSources.isEmpty ? nil : cappedSources,
                    sessionID: session.id
                )
                self.messages.append(assistant)
                await self.speakAssistantAnswerIfNeeded(result.answer)
                if voiceOriginated {
                    self.voiceState = .idle
                }

                let afterAssistantSnapshot = self.messages
                try await self.chatStore.saveMessages(afterAssistantSnapshot, for: self.session)
                print("[Chat] saved=\(afterAssistantSnapshot.count)")
            } catch {
                self.errorMessage = error.localizedDescription
                if voiceOriginated {
                    self.voiceState = .error(error.localizedDescription)
                }
                print("[Chat] send failed: \(error)")
            }
        }
    }

    // MARK: - Private

    private func loadHistoryAndIndex() async {
        self.messages = await chatStore.loadMessages(for: session)
        try? await indexMeetingIfNeeded()
    }

    private func ensureMicrophonePermission() async throws {
        let allowed: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { ok in
                    cont.resume(returning: ok)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    cont.resume(returning: ok)
                }
            }
        }

        if !allowed {
            throw ChatVoiceError.microphonePermissionDenied
        }
    }

    private func speakAssistantAnswerIfNeeded(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard speakRepliesEnabled, !trimmed.isEmpty else { return }
        voiceState = .speaking
        await ttsService.speak(trimmed)
        if case .speaking = voiceState {
            voiceState = .idle
        }
    }

    private func configureAudioSessionForRecordingIfNeeded() async throws {
        let session = AVAudioSession.sharedInstance()

        if audioSessionSnapshot == nil {
            audioSessionSnapshot = (session.category, session.mode, session.categoryOptions)
        }

        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: [.notifyOthersOnDeactivation])
    }

    private func restoreAudioSessionIfNeeded() async {
        guard let snapshot = audioSessionSnapshot else { return }
        audioSessionSnapshot = nil

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            try session.setCategory(snapshot.category, mode: snapshot.mode, options: snapshot.options)
        } catch {
            print("[ChatVoice] restore audio session failed: \(error)")
        }
    }

    private func indexMeetingIfNeeded() async throws {
        func isPlaceholderSummary(_ text: String) -> Bool {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t == "Generating..." || t == "Summary generation failed."
        }

        let transcriptText = (try? await fileStore.readText(from: session.transcriptURL)) ?? ""

        let rawSummary: String
        if let mdURL = session.summaryMarkdownURL {
            rawSummary = (try? await fileStore.readText(from: mdURL)) ?? ""
        } else {
            rawSummary = (try? await fileStore.readText(from: session.summaryURL)) ?? ""
        }

        let summaryText = isPlaceholderSummary(rawSummary) ? "" : rawSummary
        try await searchIndex.indexMeeting(session: session, transcript: transcriptText, summary: summaryText)
    }

    private func buildComposedPrompt(currentQuestion: String) -> String {
        let system = "Answer using ONLY the provided meeting excerpts. Cite sources like [S1]. If the excerpts do not contain the answer, say: Not enough evidence in sources."

        let historyMessages = Array(messages.dropLast().suffix(maxHistoryMessages))
        let historyBlock = historyMessages.map { msg in
            switch msg.role {
            case .user:
                return "User: \(msg.text)"
            case .assistant:
                return "Assistant: \(msg.text)"
            }
        }.joined(separator: "\n")

        if historyBlock.isEmpty {
            return """
            SYSTEM:
            \(system)

            QUESTION:
            \(currentQuestion)
            """
        }

        return """
        SYSTEM:
        \(system)

        CHAT HISTORY:
        \(historyBlock)

        QUESTION:
        \(currentQuestion)
        """
    }
}
