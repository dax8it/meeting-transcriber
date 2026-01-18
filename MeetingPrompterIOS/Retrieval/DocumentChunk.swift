import Foundation

nonisolated struct DocumentChunk: Identifiable, Codable {
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
}