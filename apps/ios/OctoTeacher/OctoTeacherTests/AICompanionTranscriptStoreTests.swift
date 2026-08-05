import XCTest
@testable import OctoTeacher

final class AICompanionTranscriptStoreTests: XCTestCase {
    func testTranscriptPersistsAndRestoresPerChild() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-\(UUID().uuidString)")
        let persistence = FileAICompanionTranscriptPersistence(directory: directory)
        let childA = UUID()
        let childB = UUID()

        let store = AICompanionTranscriptStore(persistence: persistence)
        store.append(
            AICompanionTranscriptEntry(role: .child, text: "我想聊恐龙", origin: .childText),
            childId: childA
        )
        store.append(
            AICompanionTranscriptEntry(role: .companion, text: "我们聊三角龙。", origin: .companionCloud),
            childId: childA
        )
        store.append(
            AICompanionTranscriptEntry(role: .child, text: "我想读书", origin: .childText),
            childId: childB
        )

        let restored = AICompanionTranscriptStore(persistence: persistence)
        XCTAssertEqual(restored.recentEntries(for: childA).map(\.text), ["我想聊恐龙", "我们聊三角龙。"])
        XCTAssertEqual(restored.recentEntries(for: childB).map(\.text), ["我想读书"])
    }

    func testTranscriptCapsEntriesAndCloudContextIsClipped() {
        let childId = UUID()
        let store = AICompanionTranscriptStore()
        let start = Date()

        for index in 0..<(AICompanionTranscriptStore.maxEntriesPerChild + 5) {
            store.append(
                AICompanionTranscriptEntry(
                    role: .child,
                    text: "第 \(index) 条很长很长很长很长很长很长很长很长很长很长很长很长很长",
                    timestamp: start.addingTimeInterval(Double(index)),
                    origin: .childText
                ),
                childId: childId,
                now: start.addingTimeInterval(Double(index))
            )
        }

        let entries = store.recentEntries(
            for: childId,
            limit: AICompanionTranscriptStore.maxEntriesPerChild,
            now: start.addingTimeInterval(Double(AICompanionTranscriptStore.maxEntriesPerChild + 4))
        )
        XCTAssertEqual(entries.count, AICompanionTranscriptStore.maxEntriesPerChild)
        XCTAssertEqual(entries.first?.text.hasPrefix("第 5 条"), true)

        let context = store.recentCloudContextLines(
            for: childId,
            now: start.addingTimeInterval(Double(AICompanionTranscriptStore.maxEntriesPerChild + 4))
        )
        XCTAssertLessThanOrEqual(context.count, AICompanionTranscriptStore.maxCloudContextLines)
        XCTAssertTrue(context.allSatisfy { $0.count <= AICompanionTranscriptStore.maxCloudContextCharacters + 8 })
    }
}

final class ParentAICompanionCoachStoreTests: XCTestCase {
    func testParentCoachTranscriptAndMemoryPersistPerChild() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("parent-coach-\(UUID().uuidString)")
        let persistence = FileParentAICompanionCoachPersistence(directory: directory)
        let childA = UUID()
        let childB = UUID()

        let store = ParentAICompanionCoachStore(persistence: persistence)
        store.append(
            ParentAICompanionCoachEntry(role: .parent, text: "孩子一直刷短视频怎么办", origin: .parentText),
            childId: childA
        )
        store.append(
            ParentAICompanionCoachEntry(role: .coach, text: "先约定一个 10 分钟替代活动。", origin: .coachCloud),
            childId: childA
        )
        store.apply(
            ParentAICompanionCoachMemoryUpdate(
                parentGoals: ["减少无效屏幕时间"],
                usefulStrategies: ["先共情再约定一个可执行小步骤"],
                boundaryNotes: ["不用羞辱推动孩子"],
                summary: "家长正在调整屏幕时间冲突"
            ),
            childId: childA
        )
        store.append(
            ParentAICompanionCoachEntry(role: .parent, text: "想培养阅读", origin: .parentText),
            childId: childB
        )

        let restored = ParentAICompanionCoachStore(persistence: persistence)
        XCTAssertEqual(restored.recentEntries(for: childA).map(\.text), ["孩子一直刷短视频怎么办", "先约定一个 10 分钟替代活动。"])
        XCTAssertEqual(restored.recentEntries(for: childB).map(\.text), ["想培养阅读"])
        XCTAssertEqual(restored.memory(for: childA).conversationCount, 1)
        XCTAssertTrue(restored.memory(for: childA).parentGoals.contains("减少无效屏幕时间"))
    }

    func testParentCoachCloudContextClipsAndFiltersUnsafeContent() {
        let childId = UUID()
        let store = ParentAICompanionCoachStore()

        store.append(
            ParentAICompanionCoachEntry(
                role: .parent,
                text: "api_key sk-test-secret 这段不应进入上下文",
                origin: .parentText
            ),
            childId: childId
        )
        store.append(
            ParentAICompanionCoachEntry(
                role: .coach,
                text: "把晚睡问题拆成刷牙、上床、关灯三个步骤，并且明天复盘。",
                origin: .coachLocal
            ),
            childId: childId
        )

        let context = store.recentCloudContextLines(for: childId)
        XCTAssertEqual(context.count, 1)
        XCTAssertFalse(context.joined().contains("sk-test"))
        XCTAssertTrue(context.joined().contains("晚睡"))
        XCTAssertTrue(context.allSatisfy { $0.count <= ParentAICompanionCoachStore.maxCloudContextCharacters + 8 })
    }
}
