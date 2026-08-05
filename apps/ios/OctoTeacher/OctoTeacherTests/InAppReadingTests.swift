import XCTest
@testable import OctoTeacher

/// v5G 回归：App 内阅读内容与进度跟进。
final class InAppReadingTests: XCTestCase {

    private func readingAssignment(_ store: LocalFamilyStore) -> TaskAssignment {
        store.assignNewTask(
            title: "读《夏洛的网》第 1 次",
            instructions: "",
            category: .learning,
            rewardMinutes: 20,
            requiredProof: .text,
            reading: ReadingSpec(bookTitle: "夏洛的网", minMinutes: 60, chapterPlanText: "第1-2章")
        )!
    }

    func testContentGeneratorParse() {
        let raw = #"{"title":"威尔伯得救了","content":"\#(String(repeating: "小猪威尔伯的故事。", count: 20))"}"#
        let parsed = AIReadingContentGenerator.parse(raw)
        XCTAssertEqual(parsed?.title, "威尔伯得救了")
        XCTAssertNotNil(parsed?.content)

        XCTAssertNil(AIReadingContentGenerator.parse(#"{"content":"太短"}"#), "过短内容视为失败")
        XCTAssertNil(AIReadingContentGenerator.parse("不是JSON"))
    }

    func testUpdateReadingContentCachesOnAssignment() throws {
        let store = LocalFamilyStore()
        let assignment = readingAssignment(store)
        store.updateReadingContent("这是生成的阅读内容。", for: assignment.id)

        let updated = try XCTUnwrap(store.assignments.first { $0.id == assignment.id })
        XCTAssertEqual(updated.task.reading?.inAppContent, "这是生成的阅读内容。")

        // 持久化 round-trip。
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.assignments.last?.task.reading?.inAppContent, "这是生成的阅读内容。")
    }

    func testRecordReadingSecondsAccumulates() throws {
        let store = LocalFamilyStore()
        let assignment = readingAssignment(store)

        store.recordReadingSeconds(120, for: assignment.id)
        store.recordReadingSeconds(45, for: assignment.id)
        store.recordReadingSeconds(0, for: assignment.id)
        store.recordReadingSeconds(-5, for: assignment.id)

        let updated = try XCTUnwrap(store.assignments.first { $0.id == assignment.id })
        XCTAssertEqual(updated.readingSecondsSpent, 165, "累计且忽略非法值")
    }

    func testBookReadingProgressPersistsFontRateAndPosition() throws {
        let store = LocalFamilyStore()
        let book = store.addBook(title: "彼得潘", fileName: "book-peter.txt", format: "txt", pageCount: 1, charCount: 12_000)
        let assignment = try XCTUnwrap(store.assignNewTask(
            title: "读《彼得潘》第 1 次",
            instructions: "",
            category: .learning,
            rewardMinutes: 20,
            requiredProof: .text,
            reading: ReadingSpec(
                bookTitle: "彼得潘",
                minMinutes: 60,
                chapterPlanText: "第 1 段",
                importedBookId: book.id,
                pageStart: 0,
                pageEnd: 4_000
            )
        ))

        store.updateReadingProgress(
            childId: store.child.id,
            bookId: book.id,
            assignmentId: assignment.id,
            lastPage: nil,
            lastCharacterOffset: 1_800,
            fontSize: 24,
            speechRate: 1.3,
            secondsDelta: 95
        )

        let progress = try XCTUnwrap(store.readingProgress(
            childId: store.child.id,
            bookId: book.id,
            assignmentId: assignment.id
        ))
        XCTAssertEqual(progress.lastCharacterOffset, 1_800)
        XCTAssertEqual(progress.fontSize, 24)
        XCTAssertEqual(progress.speechRate, 1.3)
        XCTAssertEqual(progress.totalSeconds, 95)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        let decodedProgress = try XCTUnwrap(decoded.bookReadingProgress?.first)
        XCTAssertEqual(decodedProgress.bookId, book.id)
        XCTAssertEqual(decodedProgress.assignmentId, assignment.id)
        XCTAssertEqual(decodedProgress.lastCharacterOffset, 1_800)
    }

    func testReadingTaskGroupingKeepsImportedBookChaptersTogether() throws {
        let store = LocalFamilyStore()
        let book = store.addBook(title: "彼得兔", fileName: "peter-rabbit.epub", format: "epub", pageCount: 24, charCount: 8_000)
        var first = try XCTUnwrap(store.assignNewTask(
            title: "读《彼得兔》第 1 次",
            instructions: "",
            category: .learning,
            rewardMinutes: 20,
            requiredProof: .text,
            reading: ReadingSpec(
                bookTitle: "彼得兔",
                minMinutes: 20,
                chapterPlanText: "第 1 段",
                importedBookId: book.id
            )
        ))
        let second = try XCTUnwrap(store.assignNewTask(
            title: "读《彼得兔》第 2 次",
            instructions: "",
            category: .learning,
            rewardMinutes: 20,
            requiredProof: .text,
            reading: ReadingSpec(
                bookTitle: "彼得兔",
                minMinutes: 20,
                chapterPlanText: "第 2 段",
                importedBookId: book.id
            )
        ))
        first.status = .approved

        XCTAssertEqual(ReadingTaskGrouping.key(for: first), ReadingTaskGrouping.key(for: second))
        XCTAssertEqual(ReadingTaskGrouping.title(for: first), "彼得兔")
        XCTAssertEqual(ReadingTaskGrouping.progressText(for: [first, second]), "1/2")
        XCTAssertEqual(ReadingTaskGrouping.totalReward(for: [first, second]), 40)
    }

    func testReadingProgressCopyKeepsExactTimeForReaders() {
        XCTAssertEqual(
            ChildReadingProgressCopy.label(seconds: 125, targetMinutes: 15, isPreReader: false),
            "已读 2 分 05 秒"
        )
        XCTAssertEqual(
            ChildReadingProgressCopy.label(seconds: -5, targetMinutes: 15, isPreReader: false),
            "已读 0 分 00 秒"
        )
    }

    func testReadingProgressCopyUsesStarsForPreReaders() {
        XCTAssertEqual(
            ChildReadingProgressCopy.label(seconds: 0, targetMinutes: 10, isPreReader: true),
            "阅读星星 ☆☆☆☆☆ 刚开始"
        )
        XCTAssertEqual(
            ChildReadingProgressCopy.label(seconds: 60, targetMinutes: 10, isPreReader: true),
            "阅读星星 ⭐️☆☆☆☆ 继续读"
        )
        XCTAssertEqual(
            ChildReadingProgressCopy.label(seconds: 600, targetMinutes: 10, isPreReader: true),
            "阅读星星 ⭐️⭐️⭐️⭐️⭐️ 今天读够啦"
        )
        XCTAssertFalse(
            ChildReadingProgressCopy.label(seconds: 60, targetMinutes: 10, isPreReader: true).contains("分钟")
        )
        XCTAssertFalse(
            ChildReadingProgressCopy.label(seconds: 60, targetMinutes: 10, isPreReader: true).contains("秒")
        )
    }

    func testLegacyReadingSpecDecodesWithoutContent() throws {
        let json = #"{"bookTitle":"小王子","minMinutes":30,"chapterPlanText":"第1章"}"#
        let spec = try JSONDecoder().decode(ReadingSpec.self, from: Data(json.utf8))
        XCTAssertNil(spec.inAppContent)
    }

    func testElectronicBookAssignmentRequiresAReadyFile() {
        XCTAssertFalse(ReadingAssignmentBookPolicy.canAssign(
            fileIsReady: false,
            hasRemoteHTTPSSource: true,
            familyConnected: false
        ))
        XCTAssertTrue(ReadingAssignmentBookPolicy.canAssign(
            fileIsReady: true,
            hasRemoteHTTPSSource: false,
            familyConnected: false
        ))
    }

    func testCrossDeviceElectronicBookAssignmentRequiresHTTPSDownloadSource() {
        XCTAssertFalse(ReadingAssignmentBookPolicy.canAssign(
            fileIsReady: true,
            hasRemoteHTTPSSource: false,
            familyConnected: true
        ))
        XCTAssertTrue(ReadingAssignmentBookPolicy.canAssign(
            fileIsReady: true,
            hasRemoteHTTPSSource: true,
            familyConnected: true
        ))
    }
}
