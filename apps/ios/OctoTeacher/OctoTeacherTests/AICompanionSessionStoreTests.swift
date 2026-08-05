import XCTest
@testable import OctoTeacher

final class AICompanionSessionStoreTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func guardianSnapshot(messages: [AICompanionMessage]) -> AICompanionSnapshot {
        AICompanionSnapshotBuilder().build(
            viewerRole: .guardian,
            input: AICompanionInput(
                childName: "孩子",
                mode: .emotion,
                nextTaskTitle: "完成阅读",
                messages: messages
            )
        )
    }

    func testPersistsRedactedSessionAcrossStoreReload() throws {
        let directory = try tempDirectory()
        let persistence = FileAICompanionSessionPersistence(directory: directory)
        let childId = UUID()
        let message = AICompanionMessage(freeText: "我今天很难过")

        let store = AICompanionSessionStore(persistence: persistence)
        store.append(
            childId: childId,
            mode: .emotion,
            latestMessage: message,
            guardianSnapshot: guardianSnapshot(messages: [message]),
            createdAt: Date(timeIntervalSince1970: 10)
        )

        let reloaded = AICompanionSessionStore(persistence: persistence)
        let record = try XCTUnwrap(reloaded.latestRecord(for: childId))
        XCTAssertEqual(record.latestIntent, .emotionalSupport)
        XCTAssertEqual(record.mode, .emotion)
        XCTAssertFalse(record.storesRawTranscript)
        XCTAssertFalse(record.callsNetwork)
        XCTAssertFalse(record.givesFinalAnswer)
        XCTAssertFalse(String(describing: record).contains("我今天很难过"))
        let persistedText = try String(contentsOf: persistence.fileURL, encoding: .utf8)
        XCTAssertFalse(persistedText.contains("我今天很难过"))
    }

    func testLatestRecordSortsByCreatedAt() throws {
        let directory = try tempDirectory()
        let persistence = FileAICompanionSessionPersistence(directory: directory)
        let childId = UUID()
        let store = AICompanionSessionStore(persistence: persistence)
        let old = AICompanionMessage(preset: .whatNow)
        let new = AICompanionMessage(preset: .needAdult)

        store.append(
            childId: childId,
            mode: .nextStep,
            latestMessage: old,
            guardianSnapshot: guardianSnapshot(messages: [old]),
            createdAt: Date(timeIntervalSince1970: 10)
        )
        store.append(
            childId: childId,
            mode: .emotion,
            latestMessage: new,
            guardianSnapshot: guardianSnapshot(messages: [new]),
            createdAt: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(store.latestRecord(for: childId)?.latestIntent, .askTrustedAdult)
    }

    func testCorruptPersistenceFallsBackToEmptyRecords() throws {
        let directory = try tempDirectory()
        let persistence = FileAICompanionSessionPersistence(directory: directory)
        try Data("not-json".utf8).write(to: persistence.fileURL)

        let store = AICompanionSessionStore(persistence: persistence)
        XCTAssertTrue(store.records.isEmpty)
    }

    func testTrimsRecordsPerChildToRecentLimit() throws {
        let directory = try tempDirectory()
        let persistence = FileAICompanionSessionPersistence(directory: directory)
        let childId = UUID()
        let store = AICompanionSessionStore(persistence: persistence)

        for index in 0..<(AICompanionSessionStore.maxRecordsPerChild + 5) {
            let message = AICompanionMessage(preset: .whatNow)
            store.append(
                childId: childId,
                mode: .nextStep,
                latestMessage: message,
                guardianSnapshot: guardianSnapshot(messages: [message]),
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        let records = store.records(for: childId)
        XCTAssertEqual(records.count, AICompanionSessionStore.maxRecordsPerChild)
        XCTAssertEqual(records.first?.createdAt, Date(timeIntervalSince1970: Double(AICompanionSessionStore.maxRecordsPerChild + 4)))
    }
}
