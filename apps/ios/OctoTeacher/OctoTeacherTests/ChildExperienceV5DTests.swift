import XCTest
@testable import OctoTeacher

/// v5D 回归：视频类别扩容、学科映射、自适应题量、每日底薪、月度花费、任务报表。
final class ChildExperienceV5DTests: XCTestCase {

    private func dateOf(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - 视频类别与学科映射

    func testVideoCategoryCatalogIsRich() {
        let categories = VideoCategory.allCases
        XCTAssertGreaterThanOrEqual(categories.count, 30, "至少 30 个类别")
        XCTAssertEqual(Set(categories.map(\.rawValue)).count, categories.count, "类别不能重名")
        for category in categories {
            XCTAssertFalse(category.ageHint.isEmpty, "\(category.rawValue) 缺适龄提示")
        }
        // 每个学科都有类别覆盖。
        let coveredSubjects = Set(categories.map(\.subject))
        XCTAssertEqual(coveredSubjects, Set(LearningSubject.allCases), "八大学科都应有视频类别")
    }

    func testVideoSubjectRawDrivesBadgeSubject() {
        let musicVideo = TaskTemplate(
            id: UUID(), title: "认识钢琴", category: .learning, difficulty: .easy,
            rewardMinutes: 15, instructions: "", requiredProof: .text,
            video: VideoSpec(
                urlString: "https://youtu.be/x", platformLabel: "YouTube",
                minWatchMinutes: 15, subjectRaw: LearningSubject.music.rawValue
            )
        )
        XCTAssertEqual(LearningSubject.from(task: musicVideo), .music, "视频按所选类别计入学科")

        let legacyVideo = TaskTemplate(
            id: UUID(), title: "旧视频", category: .learning, difficulty: .easy,
            rewardMinutes: 15, instructions: "", requiredProof: .text,
            video: VideoSpec(urlString: "https://youtu.be/y", platformLabel: "YouTube", minWatchMinutes: 15)
        )
        XCTAssertEqual(LearningSubject.from(task: legacyVideo), .science, "旧数据无学科时回退科学")
    }

    func testVideoSubjectSurvivesRoundTrip() throws {
        let store = LocalFamilyStore()
        store.assignNewTask(
            title: "看历史视频", instructions: "", category: .learning,
            rewardMinutes: 15, requiredProof: .text,
            video: VideoSpec(
                urlString: "https://youtu.be/h", platformLabel: "YouTube",
                minWatchMinutes: 20, subjectRaw: LearningSubject.history.rawValue
            )
        )
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.assignments.last?.task.video?.subjectRaw, "history")
    }

    // MARK: - 自适应题量

    func testQuizQuestionCountScalesWithMinutes() {
        XCTAssertEqual(AIQuizGenerator.questionCount(forMinutes: 0), 5, "下限 5 题")
        XCTAssertEqual(AIQuizGenerator.questionCount(forMinutes: 15), 10)
        XCTAssertEqual(AIQuizGenerator.questionCount(forMinutes: 60), 25)
        XCTAssertEqual(AIQuizGenerator.questionCount(forMinutes: 300), 30, "上限 30 题")
        XCTAssertTrue(AIQuizGenerator.systemPrompt(language: .chinese, count: 12).contains("出 12 题"))
    }

    func testQuizPromptUsesVerifiedLearningContent() {
        let task = TaskTemplate(
            id: UUID(),
            title: "读《彼得潘》第一章",
            category: .learning,
            difficulty: .easy,
            rewardMinutes: 20,
            instructions: "读完后做小测。",
            requiredProof: .text,
            reading: ReadingSpec(bookTitle: "彼得潘", minMinutes: 20, chapterPlanText: "第一章"),
            verification: .reading(questionCount: 5, contentKind: .story)
        )

        let prompt = AIQuizGenerator.userPrompt(
            task: task,
            childAge: 8,
            contentExcerpt: "温迪听到窗外有声音，彼得潘飞进了房间。"
        )

        XCTAssertTrue(prompt.contains("真实学习内容摘录"))
        XCTAssertTrue(prompt.contains("彼得潘飞进了房间"))
    }

    func testVideoLearningAnalyzerParsesSummaryAndRetellTargets() {
        let raw = #"{"summary":"视频讲水循环。","retellTargets":["蒸发","云形成","下雨"]}"#
        let parsed = AIVideoLearningAnalyzer.parse(raw)
        XCTAssertTrue(parsed?.contains("视频讲水循环") == true)
        XCTAssertTrue(parsed?.contains("蒸发") == true)
    }

    // MARK: - 每日底薪

    func testDailyAllowanceCreditsOncePerDay() {
        let store = LocalFamilyStore()
        var policy = FamilyExchangePolicy.default
        policy.allowanceCycle = .daily
        policy.baseMonthlyAllowance = 2
        store.exchangePolicies[store.activeChildId] = policy

        let day = dateOf(2026, 7, 4)
        store.creditMonthlyAllowancesIfNeeded(now: day)
        store.creditMonthlyAllowancesIfNeeded(now: day)
        XCTAssertEqual(store.moneyLedger.filter { $0.kind == .baseAllowance }.count, 1, "同日只入一次")
        XCTAssertEqual(store.moneyLedger.first?.note, "今日基础零花钱")

        store.creditMonthlyAllowancesIfNeeded(now: dateOf(2026, 7, 5))
        XCTAssertEqual(store.moneyLedger.filter { $0.kind == .baseAllowance }.count, 2, "第二天再入一次")
    }

    // MARK: - 月度花费总览

    func testMonthlySpendingSummary() throws {
        let store = LocalFamilyStore()
        let childId = store.activeChildId
        store.child.rewardBalanceMinutes = 200

        // 积分兑换 ¥3。
        _ = try XCTUnwrap(store.requestPocketMoneyExchange(points: 30))
        // 家长调整 +¥5。
        _ = store.adjustPocketMoney(childId: childId, amount: 5, note: "帮忙搬东西")
        // 愿望：定价 50 分并兑换。
        let wish = try XCTUnwrap(store.submitWish(title: "小玩具"))
        _ = store.priceWish(wish.id, points: 50)
        XCTAssertTrue(store.redeemWish(wish.id))

        let summary = store.monthlySpendingSummary(for: childId)
        XCTAssertEqual(summary.exchangedMoney, 3)
        XCTAssertEqual(summary.adjustments, 5)
        XCTAssertEqual(summary.wishPointsSpent, 50)
    }

    func testWishListCopyShowsChildGapAndParentLifecycle() {
        let wish = WishListItem(
            id: UUID(),
            childId: UUID(),
            title: "恐龙书",
            note: "",
            status: .priced,
            pricePoints: 50,
            createdAt: Date()
        )

        XCTAssertEqual(
            ChildWishListCopy.statusLine(for: wish, availablePoints: 20),
            "需要 50 成长积分 · 还差 30 成长积分"
        )
        XCTAssertEqual(
            ChildWishListCopy.statusLine(for: wish, availablePoints: 55),
            "需要 50 成长积分 · 可以兑换啦"
        )
        XCTAssertTrue(ChildWishListCopy.speakText(for: wish, availablePoints: 20).contains("还差 30 成长积分"))
        XCTAssertEqual(
            ParentWishListCopy.statusLine(for: wish, availablePoints: 20),
            "已定价 50 成长积分；孩子当前还差 30 成长积分。"
        )
        XCTAssertTrue(ParentWishListCopy.nextStepLine(for: wish, availablePoints: 20).contains("继续引导孩子完成任务"))
        XCTAssertTrue(ParentWishListCopy.nextStepLine(for: wish, availablePoints: 55).contains("兑换愿望"))
        XCTAssertTrue(ParentWishListCopy.isInProgress(wish))
    }

    // MARK: - 任务报表

    func testTaskStatsAggregatesByCategoryAndRange() throws {
        let store = LocalFamilyStore()
        // 清空种子，布置可控数据。
        store.applyFamilySetup(childName: "乐乐", dailyLimitMinutes: 60, keepStarterTasks: false)

        let learn = try XCTUnwrap(store.assignNewTask(
            title: "读书", instructions: "", category: .learning,
            rewardMinutes: 15, requiredProof: .text
        ))
        _ = store.assignNewTask(
            title: "倒垃圾", instructions: "", category: .home,
            rewardMinutes: 10, requiredProof: .text
        )
        store.submit(learn, text: "读完了")
        _ = store.approve(store.assignments.first { $0.id == learn.id }!)

        let stats = store.taskStats(for: store.activeChildId, range: .day)
        let learning = try XCTUnwrap(stats.first { $0.category == .learning })
        XCTAssertEqual(learning.done, 1)
        XCTAssertEqual(learning.total, 1)
        let home = try XCTUnwrap(stats.first { $0.category == .home })
        XCTAssertEqual(home.done, 0)
        XCTAssertEqual(home.total, 1)
        // 没布置过的类别不出现。
        XCTAssertNil(stats.first { $0.category == .school })

        // 周/月范围也包含今天的数据。
        XCTAssertFalse(store.taskStats(for: store.activeChildId, range: .week).isEmpty)
        XCTAssertFalse(store.taskStats(for: store.activeChildId, range: .month).isEmpty)
    }
}
