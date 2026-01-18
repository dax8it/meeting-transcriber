import SwiftUI
import LeapSDK

@main
struct MeetingPrompteriOSApp: App {
    @StateObject private var viewModel = MeetingViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}

@MainActor
class MeetingViewModel: ObservableObject {
    @Published var status = "Ready"
    @Published var transcript = ""
    @Published var answer = ""
    @Published var isRecording = false
    @Published var isInitializing = true
    
    private var asrModel: Leap?
    private var ragModel: Leap?
    
    init() {
        Task {
            await loadModels()
        }
    }
    
    func loadModels() async {
        isInitializing = true
        status = "Loading models..."
        
        do {
            // Try subdirectory first, fallback to bundle root
            var asrURL: URL?
            var ragURL: URL?
            
            if let url = Bundle.main.url(forResource: "LFM2.5-Audio-1.5B-Q4_0", withExtension: "gguf", subdirectory: "models/audio") {
                asrURL = url
            } else if let url = Bundle.main.url(forResource: "LFM2.5-Audio-1.5B-Q4_0", withExtension: "gguf") {
                print("[MeetingViewModel] ASR model found in bundle root fallback")
                asrURL = url
            }
            
            if let url = Bundle.main.url(forResource: "LFM2-1.2B-RAG-Q5_K_M", withExtension: "gguf", subdirectory: "models/text") {
                ragURL = url
            } else if let url = Bundle.main.url(forResource: "LFM2-1.2B-RAG-Q5_K_M", withExtension: "gguf") {
                print("[MeetingViewModel] RAG model found in bundle root fallback")
                ragURL = url
            }
            
            guard let asrURL = asrURL, let ragURL = ragURL else {
                status = "Error: Model files not found"
                isInitializing = false
                return
            }
            
            print("[MeetingViewModel] Loading ASR model from: \(asrURL.path)")
            asrModel = try await Leap.load(url: asrURL)
            print("[MeetingViewModel] Loading RAG model from: \(ragURL.path)")
            ragModel = try await Leap.load(url: ragURL)
            
            status = "Ready"
            isInitializing = false
        } catch {
            status = "Error: \(error.localizedDescription)"
            isInitializing = false
        }
    }
    
    func startRecording() {
        isRecording = true
        status = "Recording..."
        transcript = ""
        answer = ""
    }
    
    func stopRecording() {
        isRecording = false
        status = "Processing..."
        
        Task {
            await processTranscript(transcript)
        }
    }
    
    private func processTranscript(_ text: String) async {
        guard !text.isEmpty else {
            status = "Ready"
            return
        }
        
        if isQuestion(text) {
            await generateAnswer(for: text)
        } else {
            status = "Ready"
        }
    }
    
    private func isQuestion(_ text: String) -> Bool {
        let lowercase = text.lowercased()
        let questionWords = ["what", "when", "where", "who", "why", "how", "can", "could", "should", "would", "is", "are", "do", "does", "did"]
        
        let hasQuestionWord = questionWords.contains { lowercase.hasPrefix($0) }
        let hasQuestionMark = text.contains("?")
        
        return hasQuestionWord || hasQuestionMark
    }
    
    private func generateAnswer(for question: String) async {
        guard let model = ragModel else {
            status = "Error: Model not loaded"
            return
        }
        
        status = "Generating answer..."
        
        do {
            let prompt = """
            Answer this question based on the context.
            Question: \(question)
            
            Context: You are a helpful meeting assistant.
            """
            
            let response = try await generateText(model: model, prompt: prompt)
            answer = response
            status = "Ready"
        } catch {
            answer = "Error: \(error.localizedDescription)"
            status = "Error"
        }
    }
    
    private func generateText(model: Leap, prompt: String) async throws -> String {
        return ""
    }
}