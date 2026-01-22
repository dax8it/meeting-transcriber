import Foundation
import GRDB

actor SearchIndex {
    static let shared = SearchIndex()

    private var dbQueue: DatabaseQueue?
    private var isInitialized = false

    // Per-meeting persisted indexes (one DB per MeetingSession)
    private var meetingDBs: [String: DatabaseQueue] = [:]

    // MVP Option 1: In-memory mirror of current meeting chunks
    private var currentMeetingChunks: [DocumentChunk] = []

    private init() {}

    nonisolated private static func ensureSchema(db: Database) throws {
        try db.execute(sql: "DROP TABLE IF EXISTS chunks_fts")
        try db.execute(sql: "DROP TABLE IF EXISTS chunks")

        try db.create(table: "chunks") { t in
            t.column("id", .text).primaryKey()
            t.column("title", .text).notNull()
            t.column("sectionPath", .text).notNull()
            t.column("text", .text).notNull()
            t.column("metadata", .text)
        }

        try db.create(virtualTable: "chunks_fts", using: FTS5()) { t in
            t.column("title")
            t.column("sectionPath")
            t.column("text")
            t.synchronize(withTable: "chunks")
        }
    }

    func initialize(chunks: [DocumentChunk]) async throws {
        guard !isInitialized else { return }

        let dbPath = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("search_index.db")
            .path

        let dbQueue = try DatabaseQueue(path: dbPath)
        self.dbQueue = dbQueue

        try await dbQueue.write { db in
            try Self.ensureSchema(db: db)

            for chunk in chunks {
                let metadataJSON = try JSONEncoder().encode(chunk.metadata)
                let metadataString = String(data: metadataJSON, encoding: .utf8) ?? "{}"

                try db.execute(
                    sql: "INSERT INTO chunks (id, title, sectionPath, text, metadata) VALUES (?, ?, ?, ?, ?)",
                    arguments: [chunk.id, chunk.title, chunk.sectionPath, chunk.text, metadataString]
                )
            }
        }

        isInitialized = true
    }

    func search(query: String, topK: Int) async throws -> [DocumentChunk] {
        guard let dbQueue, isInitialized else {
            throw SearchIndexError.notInitialized
        }

        return try await search(query: query, topK: topK, dbQueue: dbQueue)
    }

    private func search(query: String, topK: Int, dbQueue: DatabaseQueue) async throws -> [DocumentChunk] {

        let sanitizedQuery = sanitizeFTS5Query(query)
        guard !sanitizedQuery.isEmpty else {
            return []
        }

        let results: [Row] = try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT c.id, c.title, c.sectionPath, c.text, c.metadata, bm25(chunks_fts) as score
                FROM chunks c
                JOIN chunks_fts ON c.rowid = chunks_fts.rowid
                WHERE chunks_fts MATCH ?
                ORDER BY score
                LIMIT ?
                """,
                arguments: [sanitizedQuery, topK]
            )
        }

        return results.compactMap { row in
            guard let id = row["id"] as? String,
                  let title = row["title"] as? String,
                  let sectionPath = row["sectionPath"] as? String,
                  let text = row["text"] as? String,
                  let metadataString = row["metadata"] as? String,
                  let metadataData = metadataString.data(using: .utf8),
                  let metadata = try? JSONDecoder().decode([String: String].self, from: metadataData) else {
                return nil
            }

            return DocumentChunk(
                id: id,
                title: title,
                sectionPath: sectionPath,
                text: text,
                metadata: metadata
            )
        }
    }

    // MARK: - Meeting-scoped index

    func indexMeeting(session: MeetingSession, transcript: String, summary: String) async throws {
        let meetingQueue = try await meetingDB(for: session)

        let transcriptChunks = chunk(text: transcript, title: "Transcript", type: "transcript", meetingID: session.id)
        let summaryChunks = chunk(text: summary, title: "Summary", type: "summary", meetingID: session.id)
        let allChunks = transcriptChunks + summaryChunks

        try await meetingQueue.write { db in
            try Self.ensureSchema(db: db)

            for chunk in allChunks {
                let metadataJSON = try JSONEncoder().encode(chunk.metadata)
                let metadataString = String(data: metadataJSON, encoding: .utf8) ?? "{}"

                try db.execute(
                    sql: "INSERT INTO chunks (id, title, sectionPath, text, metadata) VALUES (?, ?, ?, ?, ?)",
                    arguments: [chunk.id, chunk.title, chunk.sectionPath, chunk.text, metadataString]
                )
            }
        }
    }

    func searchMeeting(session: MeetingSession, query: String, topK: Int) async throws -> [DocumentChunk] {
        let meetingQueue = try await meetingDB(for: session)
        return try await search(query: query, topK: topK, dbQueue: meetingQueue)
    }

    func fetchMeetingChunks(session: MeetingSession, title: String, limit: Int) async throws -> [DocumentChunk] {
        let meetingQueue = try await meetingDB(for: session)
        let rows: [Row] = try meetingQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT id, title, sectionPath, text, metadata
                FROM chunks
                WHERE title = ?
                ORDER BY rowid
                LIMIT ?
                """,
                arguments: [title, limit]
            )
        }

        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let title = row["title"] as? String,
                  let sectionPath = row["sectionPath"] as? String,
                  let text = row["text"] as? String,
                  let metadataString = row["metadata"] as? String,
                  let metadataData = metadataString.data(using: .utf8),
                  let metadata = try? JSONDecoder().decode([String: String].self, from: metadataData) else {
                return nil
            }

            return DocumentChunk(
                id: id,
                title: title,
                sectionPath: sectionPath,
                text: text,
                metadata: metadata
            )
        }
    }

    private func meetingDB(for session: MeetingSession) async throws -> DatabaseQueue {
        if let q = meetingDBs[session.id] {
            return q
        }
        let q = try DatabaseQueue(path: session.ragDBURL.path)
        meetingDBs[session.id] = q
        return q
    }

    private func chunk(text: String, title: String, type: String, meetingID: String?) -> [DocumentChunk] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let parts = trimmed.components(separatedBy: .newlines)
        var chunks: [DocumentChunk] = []
        chunks.reserveCapacity(parts.count)

        var idx = 1
        for part in parts {
            let p = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !p.isEmpty else { continue }

            var md: [String: String] = [
                "type": type,
                "doc_type": type,
                "chunk_index": String(idx),
            ]
            if let meetingID {
                md["meeting_id"] = meetingID
            }

            chunks.append(
                DocumentChunk(
                    title: title,
                    sectionPath: "Part \(idx)",
                    text: p,
                    metadata: md
                )
            )
            idx += 1
        }
        return chunks
    }

    // MVP Option 1: Overwrite index with the current meeting transcript
    func setCurrentMeetingTranscript(_ text: String) async throws {
        guard let dbQueue, isInitialized else {
            throw SearchIndexError.notInitialized
        }

        // MVP-simple chunking: split by newlines, keep non-empty paragraphs.
        let paragraphs = text.components(separatedBy: .newlines)
        var chunks: [DocumentChunk] = []
        chunks.reserveCapacity(paragraphs.count)

        for (index, paragraph) in paragraphs.enumerated() {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            chunks.append(
                DocumentChunk(
                    title: "Current Meeting Transcript",
                    sectionPath: "Paragraph \(index + 1)",
                    text: trimmed,
                    metadata: [
                        "type": "current_meeting",
                        "doc_type": "transcript",
                        "chunk_index": String(index + 1),
                    ]
                )
            )
        }

        let meetingChunks = chunks
        currentMeetingChunks = meetingChunks

        try await dbQueue.write { db in
            // Overwrite any previous dataset (docpack or prior meeting).
            try db.execute(sql: "DELETE FROM chunks")

            for chunk in meetingChunks {
                let metadataJSON = try JSONEncoder().encode(chunk.metadata)
                let metadataString = String(data: metadataJSON, encoding: .utf8) ?? "{}"

                try db.execute(
                    sql: "INSERT INTO chunks (id, title, sectionPath, text, metadata) VALUES (?, ?, ?, ?, ?)",
                    arguments: [chunk.id, chunk.title, chunk.sectionPath, chunk.text, metadataString]
                )
            }
        }

        print("[SearchIndex] Current meeting transcript indexed, chunks=\(meetingChunks.count)")
    }

    // MVP Option 1: Search only against current meeting transcript
    func searchCurrentMeeting(query: String, topK: Int) async throws -> [DocumentChunk] {
        print("[SearchIndex] searchCurrentMeeting queryLen=\(query.count), topK=\(topK)")

        guard !currentMeetingChunks.isEmpty else {
            print("[SearchIndex] No current meeting transcript indexed")
            return []
        }

        return try await search(query: query, topK: topK)
    }
}

enum SearchIndexError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Search index not initialized"
        }
    }
}

private func sanitizeFTS5Query(_ query: String) -> String {
    let words = query
        .components(separatedBy: .whitespacesAndNewlines)
        .map { word in
            word.filter { $0.isLetter || $0.isNumber }
        }
        .filter { !$0.isEmpty }

    guard !words.isEmpty else { return "" }
    return words.joined(separator: " OR ")
}
