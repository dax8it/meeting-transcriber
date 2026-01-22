import Foundation

actor LiveTranscriptionService {
    static let shared = LiveTranscriptionService()

    private let asrService = ASRService.shared

    private let sampleRate: Int = 16_000
    private let chunkSeconds: Double = 2.0
    private let overlapSeconds: Double = 0.5

    private var buffer: [Float] = []
    private var transcript: String = ""

    private var inFlight: Task<Void, Never>?
    private var onUpdate: (@MainActor @Sendable (String) -> Void)?

    private init() {}

    func reset(onUpdate: (@MainActor @Sendable (String) -> Void)? = nil) {
        buffer.removeAll(keepingCapacity: true)
        transcript = ""
        inFlight?.cancel()
        inFlight = nil
        self.onUpdate = onUpdate
    }

    func setOnUpdate(_ onUpdate: (@MainActor @Sendable (String) -> Void)?) {
        self.onUpdate = onUpdate
    }

    func append(samples: [Float]) {
        guard !samples.isEmpty else { return }

        buffer.append(contentsOf: samples)

        let chunkSize = Int(chunkSeconds * Double(sampleRate))
        let overlap = Int(overlapSeconds * Double(sampleRate))
        let step = max(1, chunkSize - overlap)

        // Backpressure (MVP): if we are already transcribing, avoid queue growth.
        if inFlight != nil {
            if buffer.count > chunkSize {
                buffer = Array(buffer.suffix(chunkSize))
            }
            return
        }

        guard buffer.count >= chunkSize else { return }

        let chunk = Array(buffer.prefix(chunkSize))
        buffer.removeFirst(min(step, buffer.count))

        inFlight = Task { [weak self] in
            guard let self else { return }
            let chunkText = await self.asrService.transcribeChunk(samples: chunk)

            await self.handleChunkResult(chunkText)
        }
    }

    func finalize() async -> String {
        // Wait for any in-flight chunk.
        if let task = inFlight {
            _ = await task.result
            inFlight = nil
        }

        // Flush remaining audio (best-effort).
        let remaining = buffer
        buffer.removeAll(keepingCapacity: true)

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remaining.isEmpty else {
            return trimmedTranscript
        }

        let maxSize = Int(chunkSeconds * Double(sampleRate))
        let chunk = remaining.count > maxSize ? Array(remaining.suffix(maxSize)) : remaining
        let chunkText = await asrService.transcribeChunk(samples: chunk)
        handleChunkResult(chunkText)

        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleChunkResult(_ chunkText: String) {
        let cleaned = chunkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            inFlight = nil
            return
        }

        transcript = mergeTranscript(previous: transcript, next: cleaned)
        inFlight = nil

        if let onUpdate {
            let text = transcript
            Task { @MainActor in
                onUpdate(text)
            }
        }
    }

    private func mergeTranscript(previous: String, next: String) -> String {
        let prevWords = splitWords(previous)
        let nextWords = splitWords(next)

        guard !prevWords.isEmpty else { return next }
        guard !nextWords.isEmpty else { return previous }

        let maxOverlap = min(20, prevWords.count, nextWords.count)
        var overlap = 0

        if maxOverlap > 0 {
            for k in stride(from: maxOverlap, through: 1, by: -1) {
                let a = prevWords.suffix(k).map(normalizeWord)
                let b = nextWords.prefix(k).map(normalizeWord)
                if a == b {
                    overlap = k
                    break
                }
            }
        }

        let mergedWords = prevWords + nextWords.dropFirst(overlap)
        return mergedWords.joined(separator: " ")
    }

    private func splitWords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private func normalizeWord(_ word: String) -> String {
        word
            .lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
