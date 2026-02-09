import AVFoundation
import Foundation

@MainActor
final class TTSService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = TTSService()

    private let synthesizer = AVSpeechSynthesizer()
    private var completionContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            completionContinuation = cont
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        completionContinuation?.resume()
        completionContinuation = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.completionContinuation?.resume()
            self.completionContinuation = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.completionContinuation?.resume()
            self.completionContinuation = nil
        }
    }
}
