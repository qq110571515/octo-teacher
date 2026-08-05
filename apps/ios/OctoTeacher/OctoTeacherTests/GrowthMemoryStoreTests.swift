import XCTest
@testable import OctoTeacher

final class GrowthMemoryStoreTests: XCTestCase {
    func testGrowthMemoryPersistsAndBuildsDigest() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("growth-memory-\(UUID().uuidString)")
        let persistence = FileGrowthMemoryPersistence(directory: directory)
        let childId = UUID()

        let store = GrowthMemoryStore(persistence: persistence)
        store.record(
            GrowthMemoryEventFactory.readingProgress(
                childId: childId,
                bookTitle: "夏洛的网",
                minutes: 20
            )
        )
        store.record(
            GrowthMemoryEventFactory.quizResult(
                childId: childId,
                subjectLabel: "数学",
                correctCount: 4,
                totalCount: 5
            )
        )
        store.record(GrowthMemoryEventFactory.wishPreference(childId: childId, wish: "想要恐龙书"))

        let restored = GrowthMemoryStore(persistence: persistence)
        XCTAssertEqual(restored.events(for: childId).count, 3)

        let digest = restored.digest(for: childId)
        XCTAssertEqual(digest.totalEventCount, 3)
        XCTAssertEqual(digest.kindCounts[GrowthMemoryEventKind.readingProgress.rawValue], 1)
        XCTAssertTrue(digest.promptSummary.contains("growth_event_count=3"))
        XCTAssertTrue(digest.promptSummary.contains("夏洛的网"))
        XCTAssertTrue(digest.interestHints.contains { $0.contains("想要恐龙书") })
    }

    func testDigestFiltersUnsafeRawContentAndCapsEvents() {
        let childId = UUID()
        let store = GrowthMemoryStore()

        store.record(
            GrowthMemoryEvent(
                childId: childId,
                kind: .aiChatSummary,
                summary: "file://private/photo.png 这段不应进入摘要"
            )
        )
        for index in 0..<(GrowthMemoryStore.maxEventsPerChild + 3) {
            store.record(
                GrowthMemoryEvent(
                    childId: childId,
                    kind: .aiChatSummary,
                    summary: "安全摘要 \(index)",
                    occurredAt: Date(timeIntervalSince1970: Double(index))
                )
            )
        }

        XCTAssertEqual(store.events(for: childId).count, GrowthMemoryStore.maxEventsPerChild)
        let digest = store.digest(for: childId)
        XCTAssertFalse(digest.promptSummary.contains("file://"))
        XCTAssertLessThanOrEqual(digest.recentHighlights.count, GrowthMemoryStore.maxDigestHighlights)
    }
}
