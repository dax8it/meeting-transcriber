import AVFoundation

actor AudioCaptureService {
    static let shared = AudioCaptureService()
    
    private var audioEngine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private let bufferSizeInSeconds: Double = 24.0
    private let sampleRate: Double = 16000.0
    private var isCapturing = false
    
    private init() {}

    nonisolated private func resampleToTargetRate(_ samples: [Float], inputSampleRate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard inputSampleRate != sampleRate else { return samples }

        let ratio = inputSampleRate / sampleRate
        let outputCount = max(1, Int(Double(samples.count) / ratio))
        var output: [Float] = []
        output.reserveCapacity(outputCount)

        for outIndex in 0..<outputCount {
            let inputPosition = Double(outIndex) * ratio
            let i0 = Int(inputPosition)
            let i1 = min(i0 + 1, samples.count - 1)
            let frac = Float(inputPosition - Double(i0))

            let s0 = samples[i0]
            let s1 = samples[i1]
            output.append(s0 + (s1 - s0) * frac)
        }

        return output
    }
    
    func startCapture(onAudioBuffer: @escaping ([Float]) -> Void) throws {
        guard !isCapturing else { return }
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let hwFormat = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            let frameCount = UInt32(buffer.frameLength)
            guard let channelData = buffer.floatChannelData else { return }
            let channelCount = Int(buffer.format.channelCount)
            
            var rawSamples: [Float] = []
            rawSamples.reserveCapacity(Int(frameCount))

            for i in 0..<Int(frameCount) {
                var sum: Float = 0
                for ch in 0..<channelCount {
                    sum += channelData[ch][i]
                }
                rawSamples.append(sum / Float(channelCount))
            }

            let samples = self.resampleToTargetRate(rawSamples, inputSampleRate: buffer.format.sampleRate)
            
            Task {
                await self.addToBuffer(samples)
                onAudioBuffer(samples)
            }
        }
        
        try engine.start()
        audioEngine = engine
        isCapturing = true
    }
    
    func stopCapture() {
        guard isCapturing else { return }
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isCapturing = false
    }
    
    private func addToBuffer(_ samples: [Float]) {
        audioBuffer.append(contentsOf: samples)
        let maxBufferSize = Int(bufferSizeInSeconds * sampleRate)
        
        if audioBuffer.count > maxBufferSize {
            let removeCount = audioBuffer.count - maxBufferSize
            audioBuffer.removeFirst(removeCount)
        }
    }
    
    func getRecentBuffer(durationSeconds: Double) -> [Float] {
        let frameCount = Int(durationSeconds * sampleRate)
        let startIndex = max(0, audioBuffer.count - frameCount)
        return Array(audioBuffer[startIndex...])
    }
    
    func getFullBuffer() -> [Float] {
        return audioBuffer
    }
    
    func clearBuffer() {
        audioBuffer.removeAll()
    }
    
    func getRMSLevel(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(samples.count))
        return rms
    }
}
