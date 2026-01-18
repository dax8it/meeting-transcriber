import SwiftUI
import LeapSDK

@main
struct MeetingPrompteriOSApp: App {
    @StateObject private var viewModel = MainViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    Task {
                        await viewModel.initialize()
                    }
                }
        }
    }
}

@MainActor
class MainViewModel: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var transcript = ""
    @Published var answer = ""
    @Published var isInitializing = true
    
    enum AppStatus {
        case idle
        case recording
        case transcribing
        case answering
        case error(String)
    }
    
    private var asrModel: Leap?
    private var ragModel: Leap?
    
    func initialize() async {
        status = .idle
        
        do {
            // Try subdirectory first, fallback to bundle root
            var asrURL: URL?
            var ragURL: URL?
            
            if let url = Bundle.main.url(forResource: "LFM2.5-Audio-1.5B-Q4_0", withExtension: "gguf", subdirectory: "models/audio") {
                asrURL = url
            } else if let url = Bundle.main.url(forResource: "LFM2.5-Audio-1.5B-Q4_0", withExtension: "gguf") {
                print("[SimpleApp] ASR model found in bundle root fallback")
                asrURL = url
            }
            
            if let url = Bundle.main.url(forResource: "LFM2-1.2B-RAG-Q5_K_M", withExtension: "gguf", subdirectory: "models/text") {
                ragURL = url
            } else if let url = Bundle.main.url(forResource: "LFM2-1.2B-RAG-Q5_K_M", withExtension: "gguf") {
                print("[SimpleApp] RAG model found in bundle root fallback")
                ragURL = url
            }
            
            guard let asrURL = asrURL, let ragURL = ragURL else {
                status = .error("Model files not found")
                return
            }
            
            print("[SimpleApp] Loading ASR model from: \(asrURL.path)")
            asrModel = try await Leap.load(url: asrURL)
            print("[SimpleApp] Loading RAG model from: \(ragURL.path)")
            ragModel = try await Leap.load(url: ragURL)
            
            isInitializing = false
        } catch {
            status = .error("Failed to load models: \(error.localizedDescription)")
            isInitializing = false
        }
    }
    
    func startRecording() {
        status = .recording
        transcript = ""
        answer = ""
    }
    
    func stopRecording() async {
        status = .transcribing
        
        let finalTranscript = transcript
        
        if isQuestion(finalTranscript) {
            await generateAnswer(for: finalTranscript)
        } else {
            status = .idle
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
        status = .answering
        
        guard let model = ragModel else {
            answer = "Model not loaded"
            status = .error("Model not loaded")
            return
        }
        
        do {
            let prompt = """
            System: Answer the question based on the context.
            User: \(question)
            
            Context: You are a meeting assistant. Provide helpful, concise answers.
            """
            
            let response = try await performTextGeneration(model: model, prompt: prompt)
            answer = response
            status = .idle
        } catch {
            answer = "Error: \(error.localizedDescription)"
            status = .error(error.localizedDescription)
        }
    }
    
    private func performTextGeneration(model: Leap, prompt: String) async throws -> String {
        return ""
    }
}