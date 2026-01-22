import Foundation

actor FileStore {
    static let shared = FileStore()

    private init() {}

    private func documentsDirectory() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    private func meetingsBaseDirectory() throws -> URL {
        let base = try documentsDirectory().appendingPathComponent("Meetings", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func createSession(createdAt: Date = Date()) throws -> MeetingSession {
        let base = try meetingsBaseDirectory()

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: createdAt)

        let folderURL = base.appendingPathComponent("meeting_\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let audioURL = folderURL.appendingPathComponent("meeting_\(stamp).m4a", isDirectory: false)
        let transcriptURL = folderURL.appendingPathComponent("meeting_\(stamp)_transcript.txt", isDirectory: false)
        let summaryTextURL = folderURL.appendingPathComponent("meeting_\(stamp)_summary.txt", isDirectory: false)
        let summaryMarkdownURL = folderURL.appendingPathComponent("meeting_\(stamp)_summary.md", isDirectory: false)
        let ragDBURL = folderURL.appendingPathComponent("meeting_\(stamp)_rag_index.db", isDirectory: false)

        return MeetingSession(
            createdAt: createdAt,
            folderURL: folderURL,
            audioURL: audioURL,
            transcriptURL: transcriptURL,
            summaryURL: summaryTextURL,
            summaryMarkdownURL: summaryMarkdownURL,
            ragDBURL: ragDBURL
        )
    }

    func writeText(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        try data.write(to: url, options: [.atomic])
    }

    func writeTextReplacingItem(_ text: String, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        let tmpURL = dir.appendingPathComponent(".tmp-\(UUID().uuidString)", isDirectory: false)

        do {
            let data = Data(text.utf8)
            try data.write(to: tmpURL, options: [.atomic])

            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            throw error
        }
    }

    func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return String(decoding: data, as: UTF8.self)
    }

    func moveItem(from srcURL: URL, to destURL: URL) throws {
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: srcURL, to: destURL)
    }
}
