import XCTest
@testable import OctoTeacher

/// v5F 回归：任务表情图标匹配、语音证明（人人可用）、清理边界。
final class VoiceProofAndIconTests: XCTestCase {

    private func task(_ title: String, category: TaskCategory = .home, instructions: String = "") -> TaskTemplate {
        TaskTemplate(
            id: UUID(), title: title, category: category, difficulty: .easy,
            rewardMinutes: 10, instructions: instructions, requiredProof: .text
        )
    }

    // MARK: - 表情图标匹配

    func testConcreteEmojiForCommonTasks() {
        XCTAssertEqual(TaskIconProvider.emoji(for: task("按时上床睡觉")), "😴")
        XCTAssertEqual(TaskIconProvider.emoji(for: task("自己刷牙")), "🪥")
        XCTAssertEqual(TaskIconProvider.emoji(for: task("洗脸洗手")), "🧼")
        XCTAssertEqual(TaskIconProvider.emoji(for: task("自己穿衣服")), "👕")
        XCTAssertEqual(TaskIconProvider.emoji(for: task("整理书包")), "🎒")
        XCTAssertEqual(TaskIconProvider.emoji(for: task("倒垃圾")), "🗑️")
        XCTAssertEqual(TaskIconProvider.emoji(for: task("给爷爷打电话", category: .family)), "📞")
        XCTAssertEqual(TaskIconProvider.emoji(for: task("练琴 20 分钟", category: .creative)), "🎹")
    }

    func testPreReaderSemanticSymbolsForFirstStageCommonTasks() {
        XCTAssertEqual(TaskIconProvider.icon(for: task("按时上床睡觉")).systemImageName, "moon.zzz.fill")
        XCTAssertEqual(TaskIconProvider.icon(for: task("自己刷牙")).systemImageName, "sparkles")
        XCTAssertEqual(TaskIconProvider.icon(for: task("洗脸洗手")).systemImageName, "drop.fill")
        XCTAssertEqual(TaskIconProvider.icon(for: task("自己穿衣服")).systemImageName, "tshirt.fill")
        XCTAssertEqual(TaskIconProvider.icon(for: task("整理书包")).systemImageName, "backpack.fill")
        XCTAssertEqual(TaskIconProvider.icon(for: task("倒垃圾")).systemImageName, "trash.fill")
        XCTAssertEqual(TaskIconProvider.icon(for: task("收拾房间")).systemImageName, "sparkles")
        XCTAssertEqual(TaskIconProvider.icon(for: task("户外踢球", category: .health)).systemImageName, "figure.run")

        XCTAssertEqual(TaskIconProvider.icon(for: task("练琴 20 分钟", category: .creative)).emoji, "🎹")
        XCTAssertNil(TaskIconProvider.icon(for: task("练琴 20 分钟", category: .creative)).assetName)
    }

    func testEnglishChildTasksKeepTheSameSemanticIcons() {
        XCTAssertEqual(TaskIconProvider.icon(for: task("Read for 15 minutes", category: .learning)).systemImageName, "book.closed.fill")
        XCTAssertEqual(TaskIconProvider.icon(for: task("Tidy your desk", category: .learning)).systemImageName, "sparkles")
        XCTAssertEqual(TaskIconProvider.icon(for: task("Brush teeth")).systemImageName, "sparkles")
        XCTAssertEqual(TaskIconProvider.icon(for: task("Go to bed on time", category: .health)).systemImageName, "moon.zzz.fill")
        XCTAssertEqual(TaskIconProvider.icon(for: task("Draw a story picture", category: .creative)).systemImageName, "paintbrush.pointed.fill")
    }

    func testTranslatedDisplayTitleDrivesTheVisibleTaskIcon() {
        let genericCloudTask = task("成长任务", category: .learning)

        XCTAssertEqual(
            TaskIconProvider.icon(for: genericCloudTask, displayTitle: "Tidy your desk").systemImageName,
            "sparkles"
        )
    }

    func testVisibleTaskTitleWinsOverIncidentalWordsInInstructions() {
        let tidyTask = TaskTemplate(
            id: UUID(),
            title: "整理书桌",
            category: .home,
            difficulty: .easy,
            rewardMinutes: 15,
            instructions: "把书桌整理到可以写作业或阅读的状态，拍一张照片给爸爸妈妈看。",
            requiredProof: .photo
        )

        XCTAssertEqual(
            TaskIconProvider.icon(for: tidyTask, displayTitle: "Tidy your desk").systemImageName,
            "sparkles"
        )
    }

    func testReadingAndVideoIconsTakePriority() {
        var reading = task("任务")
        reading.reading = ReadingSpec(bookTitle: "书", minMinutes: 30, chapterPlanText: "")
        XCTAssertEqual(TaskIconProvider.emoji(for: reading), "📖")
        XCTAssertEqual(TaskIconProvider.icon(for: reading).systemImageName, "book.closed.fill")

        var video = task("任务")
        video.video = VideoSpec(urlString: "https://x", platformLabel: "YouTube", minWatchMinutes: 15)
        XCTAssertEqual(TaskIconProvider.emoji(for: video), "▶")
        XCTAssertEqual(TaskIconProvider.icon(for: video).systemImageName, "play.rectangle.fill")
        XCTAssertNil(TaskIconProvider.icon(for: video).assetName)
    }

    func testCategoryFallbackWhenNoKeywordMatches() {
        XCTAssertEqual(TaskIconProvider.emoji(for: task("神秘任务", category: .school)), "🏫")
        XCTAssertEqual(TaskIconProvider.emoji(for: task("神秘任务", category: .health)), "🏃")
        XCTAssertNil(TaskIconProvider.icon(for: task("神秘任务", category: .school)).assetName)
        XCTAssertEqual(TaskIconProvider.icon(for: task("神秘任务", category: .health)).systemImageName, "figure.run")
    }

    // MARK: - 语音证明

    func testAudioCountsAsTextProofContent() {
        var proof = ProofDraft.empty
        XCTAssertFalse(proof.hasContent)
        proof.audioFileName = "proof-voice-x.m4a"
        XCTAssertTrue(proof.hasContent, "不认字的幼儿可以只用语音当证明")
    }

    func testLegacyProofDecodesWithoutAudioField() throws {
        let json = """
        {"kind":"text","text":"完成了","status":"submitted"}
        """
        let proof = try JSONDecoder().decode(ProofDraft.self, from: Data(json.utf8))
        XCTAssertNil(proof.audioFileName)
        XCTAssertTrue(proof.hasContent)
    }

    func testVoiceStoreSaveAndDelete() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-tests-\(UUID().uuidString)", isDirectory: true)
        let store = ProofVoiceStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).m4a")
        try Data("fake-audio".utf8).write(to: tmp)

        let fileName = try XCTUnwrap(store.save(fromTemporary: tmp))
        XCTAssertNotNil(store.url(fileName: fileName), "保存后能取回")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "临时文件应清掉")

        store.delete(fileName: fileName)
        XCTAssertNil(store.url(fileName: fileName))
    }

    func testAudioProofSurvivesSubmitAndRoundTrip() throws {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]
        let proof = ProofDraft(
            kind: .text, text: "", photoPlaceholderName: nil,
            audioFileName: "proof-voice-abc.m4a", status: .submitted
        )
        store.submit(assignment, proof: proof)
        XCTAssertEqual(store.assignments[0].status, .submitted, "纯语音证明可以提交")

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.assignments[0].proof.audioFileName, "proof-voice-abc.m4a")
    }
}
