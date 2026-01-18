import Foundation
import SwiftUI
import Combine

@MainActor
class MainViewModel: ObservableObject {
    static let shared = MainViewModel()

    enum State {
        case idle
        case recording
        case transcribing
        case searching
        case answering
        case done
        case error(Error)
    }

    @Published var appState: State = .idle
    @Published var transcriptLive = ""
    @Published var transcriptFinal = ""
    @Published var answerText = ""
    @Published var sources: [DocumentChunk] = []
    @Published var questionText: String = ""
    @Published var isInitializing = false

    private let leapManager = LeapModelManager.shared
    private let ragService = RAGService.shared
    private let docPackLoader = DocPackLoader.shared
    private let searchIndex = SearchIndex.shared
    private let pushToTalkController = PushToTalkController.shared
    private let taskQueue = TaskQueue.shared

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

        appState = .recording
        transcriptLive = ""
        transcriptFinal = ""
        answerText = ""
        sources = []

        Task {
            await leapManager.unloadRAG()
            await pushToTalkController.startRecording { partialText in
                Task { @MainActor in
                    self.transcriptLive = partialText
                }
            }
        }
    }

    // MVP Option 1: stopRecording ALWAYS stores "current meeting" transcript, never triggers RAG.
    func stopRecording() {
        guard case .recording = appState else {
            print("[MainViewModel] stopRecording called but not recording, ignoring")
            return
        }

        appState = .transcribing

        Task {
            await taskQueue.cancelCurrent()
            let fullTranscript = await pushToTalkController.stopRecording()

            await MainActor.run {
                self.transcriptFinal = fullTranscript
                self.transcriptLive = ""
            }

            let trimmed = fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                await MainActor.run { self.appState = .idle }
                return
            }

            do {
                try await searchIndex.setCurrentMeetingTranscript(trimmed)
                print("[MainViewModel] Current meeting transcript saved, length=\(trimmed.count)")
                await MainActor.run { self.appState = .idle }
            } catch {
                await MainActor.run { self.appState = .error(error) }
            }
        }
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
            let chunks = try await searchIndex.searchCurrentMeeting(query: question, topK: 3)
            print("[MainViewModel] askQuestion length=\(question.count), chunks=\(chunks.count)")

            guard !chunks.isEmpty else {
                await MainActor.run {
                    self.answerText = "No current meeting transcript is indexed yet. Record a meeting first."
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
        appState = .idle
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
        case .recording:
            return "Recording..."
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

    var isTranscribing: Bool {
        if case .transcribing = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
