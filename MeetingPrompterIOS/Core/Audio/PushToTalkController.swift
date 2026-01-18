import Foundation

actor PushToTalkController {
    static let shared = PushToTalkController()
    
    private let audioCapture = AudioCaptureService.shared
    private let asrService = ASRService.shared
    private let vadGate = VADGate()
    
    private var isRecording = false
    private var partialTranscriptUpdateTask: Task<Void, Never>?
    private var onTranscriptUpdate: ((String) -> Void)?
    
    private let partialTranscriptInterval: TimeInterval = 1.5
    private let lastTranscript = ""
    
    private init() {}
    
    func startRecording(onTranscriptUpdate: @escaping (String) -> Void) async {
        guard !isRecording else { return }
        
        print("[PushToTalk] Starting recording...")
        self.onTranscriptUpdate = onTranscriptUpdate
        isRecording = true
        
        do {
            try await audioCapture.startCapture { [weak self] samples in
                guard let self = self else { return }
                Task {
                    _ = await self.vadGate.processSamples(samples)
                }
            }
            
            startPartialTranscriptUpdates()
        } catch {
            print("Failed to start audio capture: \(error)")
            isRecording = false
        }
    }
    
    func stopRecording() async -> String {
        guard isRecording else { return lastTranscript }
        
        isRecording = false
        partialTranscriptUpdateTask?.cancel()
        partialTranscriptUpdateTask = nil
        
        await audioCapture.stopCapture()
        await vadGate.reset()
        
        let fullBuffer = await audioCapture.getFullBuffer()
        print("[PushToTalk] Got full buffer with \(fullBuffer.count) samples, transcribing...")
        let fullTranscript = await asrService.transcribe(samples: fullBuffer)
        print("[PushToTalk] Transcription result: \(fullTranscript)")
        
        onTranscriptUpdate = nil
        await audioCapture.clearBuffer()
        
        return fullTranscript
    }
    
    private func startPartialTranscriptUpdates() {
        partialTranscriptUpdateTask = Task {
            while !Task.isCancelled && isRecording {
                try? await Task.sleep(nanoseconds: UInt64(partialTranscriptInterval * 1_000_000_000))
                
                guard !Task.isCancelled else { break }
                
                let recentBuffer = await audioCapture.getRecentBuffer(durationSeconds: 4.0)
                let partialText = await asrService.transcribe(samples: recentBuffer)
                
                let transcriptCallback = onTranscriptUpdate
                await MainActor.run {
                    transcriptCallback?(partialText)
                }
            }
        }
    }
}