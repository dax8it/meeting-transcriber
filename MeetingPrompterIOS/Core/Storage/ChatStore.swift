import Foundation

actor ChatStore {
    static let shared = ChatStore()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    func loadMessages(for session: MeetingSession) async -> [ChatMessage] {
        let url = chatFileURL(for: session)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([ChatMessage].self, from: data)
        } catch {
            print("[Chat] load failed: \(error)")
            return []
        }
    }

    func saveMessages(_ messages: [ChatMessage], for session: MeetingSession) async throws {
        let url = chatFileURL(for: session)
        try FileManager.default.createDirectory(at: session.folderURL, withIntermediateDirectories: true)

        let data = try encoder.encode(messages)
        try data.write(to: url, options: [.atomic])
    }

    nonisolated func chatFileURL(for session: MeetingSession) -> URL {
        session.folderURL.appendingPathComponent("chat.json", isDirectory: false)
    }
}
