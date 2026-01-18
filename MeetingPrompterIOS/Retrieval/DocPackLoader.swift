import Foundation

actor DocPackLoader {
    static let shared = DocPackLoader()
    
    private init() {}
    
    func loadBundledDocPack() async throws -> [DocumentChunk] {
        guard let url = Bundle.main.url(forResource: "docpack", withExtension: "json") else {
            throw DocPackLoadError.fileNotFound
        }
        
        let data = try Data(contentsOf: url)
        let docPack = try JSONDecoder().decode(DocPack.self, from: data)
        
        return docPack.chunks
    }
}

nonisolated struct DocPack: Codable {
    let version: String
    let chunks: [DocumentChunk]
}

enum DocPackLoadError: LocalizedError {
    case fileNotFound
    case invalidFormat
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Doc pack file not found in app bundle"
        case .invalidFormat:
            return "Invalid doc pack format"
        }
    }
}