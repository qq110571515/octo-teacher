import XCTest
@testable import OctoTeacher

/// P1 自由选择模式 + P2 档案/语言/记忆摘要的回归测试。
final class FreeChoiceAndMemoryTests: XCTestCase {

    // MARK: - P1 自由选择

    /// 默认自由模式：所有任务从布置起就解锁，孩子任意选择。
    func testAllStepsUnlockedByDefault() {
        let store = LocalFamilyStore()
        XCTAssertEqual(store.growthPack.resolvedSequencing, .free)
        for step in store.growthPack.steps {
            XCTAssertTrue(store.isStepUnlocked(step), "\(step.title) 不应被锁定")
            XCTAssertNotEqual(store.progress(for: step), .locked)
        }
    }

    /// 顺序模式仍可按包开启（未来闯关型成长包）。
    func testSequentialModeStillAvailableAsOptIn() {
        let store = LocalFamilyStore()
        store.growthPack.sequencing = .sequential

        let steps = store.steps(for: store.activeChildId)
        XCTAssertTrue(store.isStepUnlocked(steps[0]))
        XCTAssertFalse(store.isStepUnlocked(steps[1]), "顺序模式下第二步应锁定")

        // 批准第一步后第二步解锁。
        let first = store.assignment(for: steps[0])!
        store.submit(first, text: "完成")
        _ = store.approve(store.assignments.first { $0.id == first.id }!)
        XCTAssertTrue(store.isStepUnlocked(steps[1]))
    }

    /// 旧持久化数据（无 sequencing 字段）解码后默认自由模式。
    func testLegacyGrowthPackDecodesAsFree() throws {
        let json = """
        {"id":"\(UUID().uuidString)","title":"包","summary":"s","steps":[]}
        """
        let pack = try JSONDecoder().decode(GrowthPack.self, from: Data(json.utf8))
        XCTAssertEqual(pack.resolvedSequencing, .free)
    }

    func testTodayCompletionCounts() {
        let store = LocalFamilyStore()
        XCTAssertEqual(store.todayCompletion.total, 3)
        XCTAssertEqual(store.todayCompletion.done, 0)

        let first = store.assignments[0]
        store.submit(first, text: "完成")
        _ = store.approve(store.assignments[0])
        XCTAssertEqual(store.todayCompletion.done, 1)
    }

    // MARK: - P2 档案与语言

    func testUpdateChildProfileWithInterestsAndNotes() {
        let store = LocalFamilyStore()
        XCTAssertTrue(
            store.updateChildProfile(
                childId: store.child.id,
                name: "乐乐",
                age: 9,
                dailyLimitMinutes: 90,
                interests: ["恐龙", " 乐高 ", ""],
                parentNotes: "刚开始学拼音"
            )
        )
        XCTAssertEqual(store.child.resolvedInterests, ["恐龙", "乐高"], "兴趣应去空白与空项")
        XCTAssertEqual(store.child.parentNotes, "刚开始学拼音")
    }

    func testLegacyChildProfileDecodesWithoutNewFields() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"乐乐","age":9,"dailyLimitMinutes":60,"rewardBalanceMinutes":10}
        """
        let profile = try JSONDecoder().decode(ChildProfile.self, from: Data(json.utf8))
        XCTAssertTrue(profile.resolvedInterests.isEmpty)
        XCTAssertNil(profile.parentNotes)
    }

    func testFamilyLanguageSettingSurvivesRoundTrip() throws {
        let store = LocalFamilyStore()
        store.setFamilyLanguage(.bilingual)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(store.snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: data)
        XCTAssertEqual(decoded.settings?.language, .bilingual)
    }

    // MARK: - P2 记忆摘要

    func testDigestContainsProfileAndHistory() throws {
        let store = LocalFamilyStore()
        store.updateChildProfile(
            childId: store.child.id,
            name: "乐乐",
            age: 9,
            dailyLimitMinutes: 60,
            interests: ["恐龙"],
            parentNotes: "怕黑"
        )
        // 完成一个阅读任务。
        let reading = try XCTUnwrap(
            store.assignNewTask(
                title: "读《夏洛的网》第 1 次",
                instructions: "",
                category: .learning,
                rewardMinutes: 20,
                requiredProof: .text,
                reading: ReadingSpec(bookTitle: "夏洛的网", minMinutes: 30, chapterPlanText: "第1-2章")
            )
        )
        store.submit(reading, text: "这是孩子的证明原文不应出现在摘要里")
        _ = store.approve(store.assignments.first { $0.id == reading.id }!)

        let digest = ChildMemoryDigestBuilder.digest(for: store.child.id, store: store)

        XCTAssertTrue(digest.contains("乐乐"))
        XCTAssertTrue(digest.contains("9 岁"))
        XCTAssertTrue(digest.contains("恐龙"))
        XCTAssertTrue(digest.contains("怕黑"))
        XCTAssertTrue(digest.contains("夏洛的网"))
        XCTAssertTrue(digest.contains("第1-2章"))
        // 隐私红线：证明正文绝不进摘要。
        XCTAssertFalse(digest.contains("证明原文"), "孩子的证明正文泄露进了记忆摘要")
    }

    func testDigestListsOpenTasksForDeduplication() {
        let store = LocalFamilyStore()
        let digest = ChildMemoryDigestBuilder.digest(for: store.child.id, store: store)
        // 种子任务未完成，应出现在"避免重复"清单里。
        XCTAssertTrue(digest.contains("避免重复"))
        XCTAssertTrue(digest.contains("阅读 15 分钟"))
    }

    func testDigestIsScopedToOneChild() throws {
        let store = LocalFamilyStore()
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 6))
        store.assignNewTask(
            title: "妹妹专属任务",
            instructions: "",
            category: .home,
            rewardMinutes: 10,
            requiredProof: .text,
            childId: second.id
        )
        let firstDigest = ChildMemoryDigestBuilder.digest(for: store.children[0].id, store: store)
        XCTAssertFalse(firstDigest.contains("妹妹专属任务"), "记忆摘要不能混入其他孩子的任务")
    }
}
