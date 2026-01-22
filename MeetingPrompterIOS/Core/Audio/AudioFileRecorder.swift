import AVFoundation
import Foundation

actor AudioFileRecorder {
    static let shared = AudioFileRecorder()

    private var recorder: AVAudioRecorder?
    private var url: URL?

    private init() {}

    enum RecorderError: LocalizedError {
        case microphonePermissionDenied
        case failedToStart

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone permission denied"
            case .failedToStart:
                return "Failed to start audio recording"
            }
        }
    }

    func startRecording(to url: URL) async throws {
        try await ensureMicrophonePermission()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: [.notifyOthersOnDeactivation])

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = false
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw RecorderError.failedToStart
        }

        self.recorder = recorder
        self.url = url
    }

    func stopRecording() {
        recorder?.stop()
        recorder = nil
    }

    func currentURL() -> URL? {
        url
    }

    private func ensureMicrophonePermission() async throws {
        let allowed: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { ok in
                    cont.resume(returning: ok)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { ok in
                    cont.resume(returning: ok)
                }
            }
        }
        if !allowed {
            throw RecorderError.microphonePermissionDenied
        }
    }
}
