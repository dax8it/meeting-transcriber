import Foundation
import SwiftUI
import Combine

@MainActor
class MainViewModel: ObservableObject {
    static let shared = MainViewModel()

    enum State {
        case idle
        case countdown
        case recording
        case paused
        case transcribing
        case searching
        case answering
        case done
        case error(Error)
    }

    func pauseRecording() {
        guard case .recording = appState else { return }

        stopRecordingTimer()
        appState = .paused

        Task {
            await audioCapture.stopCapture()
            await liveTranscription.pause()
            await audioFileRecorder.pauseRecording()
        }
    }

    func resumeRecording() {
        guard case .paused = appState else { return }

        appState = .recording
        let resumedStart = Date().addingTimeInterval(-Double(recordingElapsedSeconds))
        startRecordingTimer(startedAt: resumedStart)

        Task {
            await liveTranscription.resume()
            await audioFileRecorder.resumeRecording()

            do {
                try await audioCapture.startCapture { [weak self] samples in
                    guard let self else { return }
                    Task {
                        await self.liveTranscription.append(samples: samples)
                    }
                }
            } catch {
                await MainActor.run {
                    self.stopRecordingTimer()
                    self.appState = .error(error)
                }
            }
        }
    }

    private func startRecordingTimer(startedAt: Date) {
        recordingTimerTask?.cancel()
        recordingTimerTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let elapsed = Int(Date().timeIntervalSince(startedAt).rounded(.down))
                await MainActor.run {
                    self.recordingElapsedSeconds = max(0, elapsed)
                }

                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func stopRecordingTimer() {
        recordingTimerTask?.cancel()
        recordingTimerTask = nil
    }

    private func cancelRecordingCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        preRecordingCountdown = nil
    }

    var recordingElapsedDisplay: String {
        let seconds = max(0, recordingElapsedSeconds)
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    @Published var appState: State = .idle
    @Published var transcriptLive = ""
    @Published var transcriptFinal = ""
    @Published var answerText = ""
    @Published var sources: [DocumentChunk] = []
    @Published var questionText: String = ""
    @Published var isInitializing = false
    @Published var activeSession: MeetingSession? = nil
    @Published var preRecordingCountdown: Int? = nil
    @Published var recordingElapsedSeconds: Int = 0

    private let leapManager = LeapModelManager.shared
    private let ragService = RAGService.shared
    private let docPackLoader = DocPackLoader.shared
    private let searchIndex = SearchIndex.shared
    private let audioCapture = AudioCaptureService.shared
    private let liveTranscription = LiveTranscriptionService.shared
    private let taskQueue = TaskQueue.shared
    private let fileStore = FileStore.shared
    private let audioFileRecorder = AudioFileRecorder.shared
    private let summarizationService = SummarizationService.shared

    private var tempAudioURL: URL?
    private var recordingStartDate: Date?
    private var countdownTask: Task<Void, Never>?
    private var recordingTimerTask: Task<Void, Never>?

    private init() {}

    func initialize() async {
        guard case .idle = appState else { return }

        isInitializing = true

        do {
            let chunks = try await docPackLoader.loadBundledDocPack()
            try await searchIndex.initialize(chunks: chunks)

            appState = .idle
        } catch {
            appState = .error(error)
        }

        isInitializing = false
    }

    func startRecording() {
        guard case .idle = appState else { return }

        appState = .countdown
        activeSession = nil
        transcriptLive = ""
        transcriptFinal = ""
        answerText = ""
        sources = []
        recordingElapsedSeconds = 0
        preRecordingCountdown = 3

        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }

            for remaining in stride(from: 3, through: 1, by: -1) {
                await MainActor.run {
                    self.preRecordingCountdown = remaining
                }

                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }

            await MainActor.run {
                self.preRecordingCountdown = nil
            }

            await self.beginRecordingSession()
        }
    }

    private func beginRecordingSession() async {
        guard case .countdown = appState else { return }

        countdownTask = nil
        appState = .recording

        let speechReady = await ASRService.shared.prepareForTranscription()
        guard speechReady else {
            appState = .error(ASRError.modelNotLoaded)
            return
        }

        let startedAt = Date()
        do {
            let tmpURL = try makeTempAudioURL(createdAt: startedAt)
            self.tempAudioURL = tmpURL
            self.recordingStartDate = startedAt
            self.recordingElapsedSeconds = 0
            try await audioFileRecorder.startRecording(to: tmpURL)
            startRecordingTimer(startedAt: startedAt)
        } catch {
            self.appState = .error(error)
            return
        }

        await leapManager.unloadRAG()

        await liveTranscription.reset(onUpdate: { [weak self] text in
            self?.transcriptLive = text
        })

        do {
            try await audioCapture.startCapture { [weak self] samples in
                guard let self else { return }
                Task {
                    await self.liveTranscription.append(samples: samples)
                }
            }
        } catch {
            stopRecordingTimer()
            await audioFileRecorder.stopRecording()
            cleanupTempRecording(removeFile: true)
            appState = .error(error)
        }
    }

    // MVP Option 1: stopRecording ALWAYS stores "current meeting" transcript, never triggers RAG.
    func stopRecording() {
        if case .countdown = appState {
            cancelRecordingCountdown()
            appState = .idle
            return
        }

        let wasPaused = appState.isPaused
        guard appState.isRecording || wasPaused else {
            print("[MainViewModel] stopRecording called but not recording, ignoring")
            return
        }

        stopRecordingTimer()
        appState = .transcribing

        Task {
            await taskQueue.cancelCurrent()

            if !wasPaused {
                await audioCapture.stopCapture()
            }
            let fullTranscript = await liveTranscription.finalize()

            await audioFileRecorder.stopRecording()

            await MainActor.run {
                self.transcriptFinal = fullTranscript
                self.transcriptLive = ""
            }

            let trimmed = fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                cleanupTempRecording(removeFile: true)
                await MainActor.run { self.appState = .idle }
                return
            }

            do {
                try await searchIndex.setCurrentMeetingTranscript(trimmed)
                print("[MainViewModel] Current meeting transcript saved, length=\(trimmed.count)")

                // Phase A: persist a new session with transcript + placeholder summary.
                var session = try await fileStore.createSession(createdAt: Date())
                try await fileStore.writeText(trimmed + "\n", to: session.transcriptURL)
                try await fileStore.writeTextReplacingItem("Generating...\n", to: session.summaryURL)
                if let mdURL = session.summaryMarkdownURL {
                    try await fileStore.writeTextReplacingItem("Generating...\n", to: mdURL)
                }

                // Index meeting-scoped DB early so RAG can always include summary chunks later.
                do {
                    try await searchIndex.indexMeeting(session: session, transcript: trimmed, summary: "Generating...")
                } catch {
                    print("[MainViewModel] Failed to index meeting (initial): \(error)")
                }

                session.durationSeconds = Double(recordingElapsedSeconds)

                if let tmpURL = tempAudioURL, FileManager.default.fileExists(atPath: tmpURL.path) {
                    try await fileStore.moveItem(from: tmpURL, to: session.audioURL)
                }
                cleanupTempRecording()

                await MainActor.run { self.appState = .idle }
                await MainActor.run { self.activeSession = session }

                // Phase D: generate summary in background and overwrite summary files.
                let sessionID = session.id
                let summaryTextURL = session.summaryURL
                let summaryMarkdownURL = session.summaryMarkdownURL
                let transcriptForSummary = trimmed

                Task.detached(priority: .userInitiated) {
                    let summary = await SummarizationService.shared.summarize(transcript: transcriptForSummary)

                    do {
                        if summary.isEmpty {
                            try await FileStore.shared.writeTextReplacingItem("Summary generation failed.\n", to: summaryTextURL)
                            if let mdURL = summaryMarkdownURL {
                                try await FileStore.shared.writeTextReplacingItem("Summary generation failed.\n", to: mdURL)
                            }
                        } else {
                            // Share-stable: write .txt for sharing and also keep .md.
                            try await FileStore.shared.writeTextReplacingItem(summary + "\n", to: summaryTextURL)
                            if let mdURL = summaryMarkdownURL {
                                try await FileStore.shared.writeTextReplacingItem(summary + "\n", to: mdURL)
                            }
                        }
                    } catch {
                        print("[MainViewModel] Failed to write summary: \(error)")
                    }

                    // Refresh meeting-scoped index with final summary so summary chunks are always available to RAG.
                    do {
                        try await SearchIndex.shared.indexMeeting(session: session, transcript: transcriptForSummary, summary: summary)
                    } catch {
                        print("[MainViewModel] Failed to index meeting (final): \(error)")
                    }

                    NotificationCenter.default.post(
                        name: .meetingSessionArtifactsUpdated,
                        object: nil,
                        userInfo: ["sessionID": sessionID]
                    )
                }
            } catch {
                cleanupTempRecording(removeFile: true)
                await MainActor.run { self.appState = .error(error) }
            }
        }
    }

    private func cleanupTempRecording(removeFile: Bool = false) {
        if removeFile,
           let tmpURL = tempAudioURL,
           FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
        }
        tempAudioURL = nil
        recordingStartDate = nil
    }

    private func makeTempAudioURL(createdAt: Date) throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let tmpDir = docs.appendingPathComponent("Meetings/_tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let stamp = formatter.string(from: createdAt)
        let nonce = String(UUID().uuidString.prefix(8)).lowercased()

        return tmpDir.appendingPathComponent("recording_\(stamp)_\(nonce).m4a", isDirectory: false)
    }

    // MVP Option 1: Called from UI when user taps Ask.
    func askQuestion(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch appState {
        case .recording, .transcribing:
            return
        default:
            break
        }

        appState = .searching

        Task {
            await processQuestion(trimmed)
        }
    }

    private func processQuestion(_ question: String) async {
        do {
            // Prefer meeting-scoped index when we have an active session so we can always include summary chunks.
            let chunks: [DocumentChunk]
            if let session = self.activeSession {
                func isPlaceholderSummary(_ text: String) -> Bool {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty || t == "Generating..." || t == "Summary generation failed."
                }

                let retrieved = try await searchIndex.searchMeeting(session: session, query: question, topK: 8)
                let summaryText = (try? await fileStore.readText(from: session.summaryURL)) ?? ""
                let includeSummary = !isPlaceholderSummary(summaryText)
                let summaryChunks: [DocumentChunk] = includeSummary
                    ? ((try? await searchIndex.fetchMeetingChunks(session: session, title: "Summary", limit: 4)) ?? [])
                    : []

                // Stable ordering for citations: put retrieved first, then summary extras.
                var ordered: [DocumentChunk] = []
                ordered.reserveCapacity(retrieved.count + summaryChunks.count)
                ordered.append(contentsOf: retrieved)
                for sc in summaryChunks {
                    if !retrieved.contains(where: { $0.id == sc.id }) {
                        ordered.append(sc)
                    }
                }

                var deduped: [DocumentChunk] = []
                deduped.reserveCapacity(ordered.count)
                for c in ordered {
                    if !deduped.contains(where: { $0.id == c.id }) {
                        deduped.append(c)
                    }
                }
                chunks = deduped
            } else {
                chunks = try await searchIndex.searchCurrentMeeting(query: question, topK: 8)
            }

            print("[MainViewModel] askQuestion length=\(question.count), chunks=\(chunks.count)")

            guard !chunks.isEmpty else {
                await MainActor.run {
                    self.answerText = "Not enough evidence in sources."
                    self.sources = []
                    self.appState = .done
                }
                return
            }

            await MainActor.run { self.appState = .answering }

            let result = try await ragService.generateAnswer(question: question, chunks: chunks)

            await MainActor.run {
                self.answerText = result.answer
                self.sources = result.sources
                self.appState = .done
            }
        } catch {
            await MainActor.run { self.appState = .error(error) }
        }
    }

    func reset() {
        cancelRecordingCountdown()
        stopRecordingTimer()
        appState = .idle
        preRecordingCountdown = nil
        recordingElapsedSeconds = 0
        transcriptLive = ""
        transcriptFinal = ""
        answerText = ""
        sources = []
        questionText = ""
    }

    var statusText: String {
        switch appState {
        case .idle:
            return "Ready"
        case .countdown:
            if let countdown = preRecordingCountdown {
                return "Starting in \(countdown)..."
            }
            return "Preparing to record..."
        case .recording:
            return "Recording..."
        case .paused:
            return "Paused"
        case .transcribing:
            return "Transcribing..."
        case .searching:
            return "Searching..."
        case .answering:
            return "Answering..."
        case .done:
            return "Done"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
}

extension MainViewModel.State {
    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var isCountdown: Bool {
        if case .countdown = self { return true }
        return false
    }

    var isTranscribing: Bool {
        if case .transcribing = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
