import Foundation

actor LiveTranscriptionService {
    static let shared = LiveTranscriptionService()

    private let asrService = ASRService.shared

    private let sampleRate: Int = 16_000
    private let chunkSeconds: Double = 2.0
    private let overlapSeconds: Double = 0.5
    private let asrChunkTimeoutNanoseconds: UInt64 = 8_000_000_000

    private var buffer: [Float] = []
    private var transcript: String = ""
    private var isTranscribing = false
    private var isPaused = false

    private var currentASRTask: Task<Void, Never>?
    private var onUpdate: (@MainActor @Sendable (String) -> Void)?

    private init() {}

    func reset(onUpdate: (@MainActor @Sendable (String) -> Void)? = nil) {
        currentASRTask?.cancel()
        currentASRTask = nil
        isTranscribing = false
        isPaused = false
        buffer.removeAll(keepingCapacity: true)
        transcript = ""
        self.onUpdate = onUpdate
    }

    func setOnUpdate(_ onUpdate: (@MainActor @Sendable (String) -> Void)?) {
        self.onUpdate = onUpdate
    }

    func append(samples: [Float]) {
        guard !samples.isEmpty, !isPaused else { return }

        buffer.append(contentsOf: samples)

        let chunkSize = Int(chunkSeconds * Double(sampleRate))
        let overlapSize = Int(overlapSeconds * Double(sampleRate))

        guard buffer.count >= chunkSize && !isTranscribing else { return }

        let chunk = Array(buffer.prefix(chunkSize))
        let removeCount = max(1, chunkSize - overlapSize)
        if removeCount >= buffer.count {
            buffer.removeAll(keepingCapacity: true)
        } else {
            buffer.removeFirst(removeCount)
        }

        isTranscribing = true

        let updateCallback = onUpdate

        currentASRTask = Task.detached { [weak self] in
            guard let self else { return }
            let text = await self.transcribeChunkWithTimeout(chunk)

            guard !Task.isCancelled else {
                await self.markTranscriptionComplete()
                return
            }

            await self.handleResult(text, callback: updateCallback)
        }
    }

    private func waitForTaskCompletion(_ task: Task<Void, Never>, timeoutNanoseconds: UInt64) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await task.result
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func shouldDropRepeatedLowInformationChunk(_ text: String) -> Bool {
        let nextWords = normalizedWords(from: text)
        guard nextWords.count == 1, let token = nextWords.first, token.count >= 2 else {
            return false
        }

        let priorWords = normalizedWords(from: transcript)
        guard priorWords.count >= 2 else { return false }
        let tail = priorWords.suffix(2)
        return tail.allSatisfy { $0 == token }
    }

    private func normalizedWords(from text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isWhitespace })
            .map { token in
                token
                    .lowercased()
                    .trimmingCharacters(in: .punctuationCharacters)
            }
            .filter { !$0.isEmpty }
    }

    func stop() {
        currentASRTask?.cancel()
        currentASRTask = nil
        isTranscribing = false
        isPaused = false
        buffer.removeAll(keepingCapacity: true)
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func finalize() async -> String {
        if let task = currentASRTask {
            let didFinish = await waitForTaskCompletion(task, timeoutNanoseconds: 8_000_000_000)
            if !didFinish {
                task.cancel()
            }
            currentASRTask = nil
        }

        let remaining = buffer
        buffer.removeAll(keepingCapacity: true)
        isTranscribing = false
        isPaused = false

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remaining.isEmpty else { return trimmed }

        let text = await transcribeChunkWithTimeout(remaining)
        return (transcript + " " + text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func transcribeChunkWithTimeout(_ samples: [Float]) async -> String {
        guard !samples.isEmpty else { return "" }

        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await self.asrService.transcribeChunk(samples: samples)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: self.asrChunkTimeoutNanoseconds)
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            if result == nil {
                print("[LiveTranscription] ASR chunk timed out")
            }
            return result ?? ""
        }
    }

    private func markTranscriptionComplete() {
        isTranscribing = false
    }

    private func handleResult(_ text: String, callback: (@MainActor @Sendable (String) -> Void)?) {
        isTranscribing = false
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        if shouldDropRepeatedLowInformationChunk(cleaned) {
            print("[LiveTranscription] Dropping repeated low-information chunk: '\(cleaned)'")
            return
        }

        transcript = merge(previous: transcript, next: cleaned)

        if let callback {
            let currentTranscript = transcript
            Task { @MainActor in callback(currentTranscript) }
        }
    }

    private func merge(previous: String, next: String) -> String {
        let prev = previous.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let nxt = next.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !prev.isEmpty, !nxt.isEmpty else { return prev.isEmpty ? next : previous }

        let maxOverlap = min(20, prev.count, nxt.count)
        var overlap = 0
        for k in stride(from: maxOverlap, through: 1, by: -1) {
            if prev.suffix(k).map({ $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }) ==
               nxt.prefix(k).map({ $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }) {
                overlap = k
                break
            }
        }
        return (prev + nxt.dropFirst(overlap)).joined(separator: " ")
    }
}
