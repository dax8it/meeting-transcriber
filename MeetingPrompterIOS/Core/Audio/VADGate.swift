import Foundation

actor VADGate {
    private var isSpeechDetected = false
    private var silenceFrameCount = 0
    private let silenceThreshold: Float = 0.01
    private let hangoverFrames: Int = 20
    private let sampleRate: Double = 16000.0
    private let frameDuration: Double = 0.02
    
    func processSamples(_ samples: [Float]) -> Bool {
        let rms = calculateRMS(samples: samples)
        let hasSpeech = rms > silenceThreshold
        
        if hasSpeech {
            isSpeechDetected = true
            silenceFrameCount = 0
            return true
        } else {
            silenceFrameCount += 1
            
            if silenceFrameCount >= hangoverFrames {
                isSpeechDetected = false
                silenceFrameCount = 0
                return false
            }
            
            return isSpeechDetected
        }
    }
    
    func reset() {
        isSpeechDetected = false
        silenceFrameCount = 0
    }
    
    private func calculateRMS(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        
        return sqrt(sum / Float(samples.count))
    }
}