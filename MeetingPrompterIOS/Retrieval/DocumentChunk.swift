import Foundation

nonisolated struct DocumentChunk: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let sectionPath: String
    let text: String
    let metadata: [String: String]
    
    nonisolated init(id: String = UUID().uuidString, title: String, sectionPath: String, text: String, metadata: [String: String] = [:]) {
        self.id = id
        self.title = title
        self.sectionPath = sectionPath
        self.text = text
        self.metadata = metadata
    }

    var docTitle: String {
        title
    }

    var docType: String {
        metadata["doc_type"] ?? metadata["type"] ?? "unknown"
    }

    var meetingID: String? {
        metadata["meeting_id"]
    }

    var chunkIndex: Int? {
        guard let raw = metadata["chunk_index"] else { return nil }
        return Int(raw)
    }
}
