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

    private func sessionTimestamp(createdAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return formatter.string(from: createdAt)
    }

    private func createdAtFromSessionName(_ name: String, fallback: Date) -> Date {
        let payload = String(name.dropFirst("meeting_".count))

        let withMillis = DateFormatter()
        withMillis.locale = Locale(identifier: "en_US_POSIX")
        withMillis.timeZone = TimeZone(secondsFromGMT: 0)
        withMillis.dateFormat = "yyyyMMdd_HHmmss_SSS"

        let withoutMillis = DateFormatter()
        withoutMillis.locale = Locale(identifier: "en_US_POSIX")
        withoutMillis.timeZone = TimeZone(secondsFromGMT: 0)
        withoutMillis.dateFormat = "yyyyMMdd_HHmmss"

        if payload.count >= 19 {
            let stampWithMillis = String(payload.prefix(19))
            if let parsed = withMillis.date(from: stampWithMillis) {
                return parsed
            }
        }

        if payload.count >= 15 {
            let stampNoMillis = String(payload.prefix(15))
            if let parsed = withoutMillis.date(from: stampNoMillis) {
                return parsed
            }
        }

        return fallback
    }

    func createSession(createdAt: Date = Date()) throws -> MeetingSession {
        let base = try meetingsBaseDirectory()
        let stamp = sessionTimestamp(createdAt: createdAt)
        var folderName = "meeting_\(stamp)_\(String(UUID().uuidString.prefix(8)).lowercased())"
        var folderURL = base.appendingPathComponent(folderName, isDirectory: true)
        while FileManager.default.fileExists(atPath: folderURL.path) {
            folderName = "meeting_\(stamp)_\(String(UUID().uuidString.prefix(8)).lowercased())"
            folderURL = base.appendingPathComponent(folderName, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let audioURL = folderURL.appendingPathComponent("\(folderName).m4a", isDirectory: false)
        let transcriptURL = folderURL.appendingPathComponent("\(folderName)_transcript.txt", isDirectory: false)
        let summaryTextURL = folderURL.appendingPathComponent("\(folderName)_summary.txt", isDirectory: false)
        let summaryMarkdownURL = folderURL.appendingPathComponent("\(folderName)_summary.md", isDirectory: false)
        let ragDBURL = folderURL.appendingPathComponent("\(folderName)_rag_index.db", isDirectory: false)

        return MeetingSession(
            id: folderName,
            createdAt: createdAt,
            folderURL: folderURL,
            audioURL: audioURL,
            transcriptURL: transcriptURL,
            summaryURL: summaryTextURL,
            summaryMarkdownURL: summaryMarkdownURL,
            ragDBURL: ragDBURL
        )
    }

    func listSessions() throws -> [MeetingSession] {
        let base = try meetingsBaseDirectory()
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .creationDateKey]
        let urls = try fm.contentsOfDirectory(at: base, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])

        var sessions: [MeetingSession] = []
        sessions.reserveCapacity(urls.count)

        for url in urls {
            let name = url.lastPathComponent
            guard name.hasPrefix("meeting_") else { continue }

            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isDirectory == true else { continue }

            let fallbackDate = values?.creationDate ?? Date()
            let createdAt = createdAtFromSessionName(name, fallback: fallbackDate)

            let audioURL = url.appendingPathComponent("\(name).m4a", isDirectory: false)
            let transcriptURL = url.appendingPathComponent("\(name)_transcript.txt", isDirectory: false)
            let summaryTextURL = url.appendingPathComponent("\(name)_summary.txt", isDirectory: false)
            let summaryMarkdownURL = url.appendingPathComponent("\(name)_summary.md", isDirectory: false)
            let ragDBURL = url.appendingPathComponent("\(name)_rag_index.db", isDirectory: false)

            let mdURL: URL? = fm.fileExists(atPath: summaryMarkdownURL.path) ? summaryMarkdownURL : nil

            sessions.append(
                MeetingSession(
                    id: name,
                    createdAt: createdAt,
                    folderURL: url,
                    audioURL: audioURL,
                    transcriptURL: transcriptURL,
                    summaryURL: summaryTextURL,
                    summaryMarkdownURL: mdURL,
                    ragDBURL: ragDBURL
                )
            )
        }

        sessions.sort { $0.createdAt > $1.createdAt }
        return sessions
    }

    func deleteSession(_ session: MeetingSession) throws {
        try FileManager.default.removeItem(at: session.folderURL)
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
