import Foundation
import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isInitializing = false
    @Published var isRecording = false
    @Published var transcript = ""
    @Published var isPartialTranscript = false
    @Published var answer: RAGAnswer?
    @Published var sources: [DocumentChunk] = []
    @Published var status: AppStatus = .idle
    @Published var errorMessage: String?
    
    private let leapManager = LeapModelManager.shared
    private let audioCapture = AudioCaptureService.shared
    private let asrService = ASRService.shared
    private let ragService = RAGService.shared
    private let docPackLoader = DocPackLoader.shared
    private let searchIndex = SearchIndex.shared
    private let pushToTalkController = PushToTalkController.shared
    
    enum AppStatus: String {
        case idle = "Ready"
        case transcribing = "Transcribing…"
        case searching = "Searching…"
        case answering = "Answering…"
        case processing = "Processing…"
        case error = "Error"
    }
    
    func initialize() async {
        isInitializing = true
        status = .processing
        
        do {
            let chunks = try await docPackLoader.loadBundledDocPack()
            try await searchIndex.initialize(chunks: chunks)
            
            status = .idle
        } catch {
            errorMessage = "Initialization failed: \(error.localizedDescription)"
            status = .error
        }
        
        isInitializing = false
    }
    
    func startRecording() {
        Task {
            isRecording = true
            status = .transcribing
            
            await pushToTalkController.startRecording { partialText in
                Task { @MainActor in
                    self.transcript = partialText
                    self.isPartialTranscript = true
                }
            }
        }
    }
    
    func stopRecording() async {
        isRecording = false
        status = .processing
        
        let fullTranscript = await pushToTalkController.stopRecording()
        
        Task { @MainActor in
            self.transcript = fullTranscript
            self.isPartialTranscript = false
        }
        
        if isQuestion(fullTranscript) {
            await processQuestion(fullTranscript)
        } else {
            status = .idle
        }
    }
    
    private func isQuestion(_ text: String) -> Bool {
        let lowercase = text.lowercased()
        let questionKeywords = ["what", "when", "where", "who", "why", "how", "can", "could", "should", "would", "is", "are", "do", "does", "did"]
        
        let hasQuestionWord = questionKeywords.contains { lowercase.hasPrefix($0) }
        let hasQuestionMark = text.contains("?")
        
        return hasQuestionWord || hasQuestionMark
    }
    
    private func processQuestion(_ question: String) async {
        status = .searching
        
        do {
            let answer = try await ragService.generateAnswer(question: question)
            
            Task { @MainActor in
                self.answer = answer
                self.sources = answer.sources
                self.status = .idle
            }
        } catch {
            errorMessage = "Failed to generate answer: \(error.localizedDescription)"
            status = .error
        }
    }
}

struct RAGAnswer {
    let question: String
    let answer: String
    let sources: [DocumentChunk]
}