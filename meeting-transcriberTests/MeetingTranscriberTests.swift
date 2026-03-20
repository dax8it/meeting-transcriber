import XCTest
@testable import meeting_transcriber

final class MeetingTranscriberTests: XCTestCase {
    func testCreateSessionUsesUniqueFolderNameForSameTimestamp() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try await FileStore.shared.createSession(createdAt: fixedDate)
        let second = try await FileStore.shared.createSession(createdAt: fixedDate)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.folderURL, second.folderURL)

        try? await FileStore.shared.deleteSession(first)
        try? await FileStore.shared.deleteSession(second)
    }

    func testListSessionsPreservesTimestampFromSessionName() async throws {
        let expectedDate = Date(timeIntervalSince1970: 1_700_000_123.456)
        let session = try await FileStore.shared.createSession(createdAt: expectedDate)

        let sessions = try await FileStore.shared.listSessions()
        guard let loaded = sessions.first(where: { $0.id == session.id }) else {
            XCTFail("Expected to find created session in listSessions()")
            try? await FileStore.shared.deleteSession(session)
            return
        }

        XCTAssertLessThan(abs(loaded.createdAt.timeIntervalSince(expectedDate)), 1.0)
        try? await FileStore.shared.deleteSession(session)
    }
}
