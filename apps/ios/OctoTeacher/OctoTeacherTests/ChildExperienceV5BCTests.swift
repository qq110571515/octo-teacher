import XCTest
@testable import OctoTeacher

/// v5 B/C 批回归：语音朗读、AI 验收初评、考试与千小时徽章。
final class ChildExperienceV5BCTests: XCTestCase {

    // MARK: - 语音朗读（B）

    func testSpeechLanguageDetection() {
        XCTAssertEqual(SpeechReader.languageCode(for: "读《夏洛的网》第1章"), "zh-CN")
        XCTAssertEqual(SpeechReader.languageCode(for: "Read chapter one"), "en-US")
    }

    func testReadAloudSettingDefaultsOffAndPersists() throws {
        let store = LocalFamilyStore()
        XCTAssertFalse(store.settings.resolvedReadAloud, "默认关闭，会认字的孩子界面干净")
        store.setReadAloud(true)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.settings?.resolvedReadAloud, true)
    }

    // MARK: - AI 验收初评（C）

    func testProofReviewerSupportsLearningContent() {
        let reading = TaskTemplate(
            id: UUID(), title: "读书", category: .learning, difficulty: .easy,
            rewardMinutes: 20, instructions: "", requiredProof: .text,
            reading: ReadingSpec(bookTitle: "夏洛的网", minMinutes: 30, chapterPlanText: "第1章")
        )
        let chore = TaskTemplate(
            id: UUID(), title: "倒垃圾", category: .home, difficulty: .easy,
            rewardMinutes: 10, instructions: "", requiredProof: .text
        )
        XCTAssertTrue(AIProofReviewer.supportsReview(reading))
        XCTAssertFalse(AIProofReviewer.supportsReview(chore), "家务不需要 AI 初评")
    }

    func testProofReviewerParse() {
        let review = AIProofReviewer.parse(
            #"{"confidence":0.8,"summary":"孩子复述了情节。","recommendation":"suggest_approve"}"#
        )
        XCTAssertEqual(review?.confidence, 0.8)
        XCTAssertEqual(review?.recommendation, "suggest_approve")
        // 非法建议值兜底为转家长判断。
        let fallback = AIProofReviewer.parse(#"{"confidence":2.0,"summary":"x","recommendation":"auto_pass"}"#)
        XCTAssertEqual(fallback?.recommendation, "needs_parent_judgment")
        XCTAssertEqual(fallback?.confidence, 1.0, "置信度夹紧 0-1")
        XCTAssertNil(AIProofReviewer.parse("不是JSON"))
    }

    func testAttachAIReviewPersists() throws {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]
        store.attachAIReview(
            AIReviewSummary(confidence: 0.7, summary: "有细节", recommendation: "suggest_approve"),
            to: assignment.id
        )
        XCTAssertEqual(store.assignments[0].aiReview?.summary, "有细节")

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.assignments[0].aiReview?.confidence, 0.7)
    }

    // MARK: - 学科映射与考试（C）

    func testSubjectMappingFromTasks() {
        let reading = TaskTemplate(
            id: UUID(), title: "读书", category: .learning, difficulty: .easy,
            rewardMinutes: 20, instructions: "", requiredProof: .text,
            reading: ReadingSpec(bookTitle: "书", minMinutes: 30, chapterPlanText: "")
        )
        XCTAssertEqual(LearningSubject.from(task: reading), .literature)

        let video = TaskTemplate(
            id: UUID(), title: "看视频", category: .learning, difficulty: .easy,
            rewardMinutes: 15, instructions: "", requiredProof: .text,
            video: VideoSpec(urlString: "https://youtu.be/x", platformLabel: "YouTube", minWatchMinutes: 15)
        )
        XCTAssertEqual(LearningSubject.from(task: video), .science)

        let chore = TaskTemplate(
            id: UUID(), title: "倒垃圾", category: .home, difficulty: .easy,
            rewardMinutes: 10, instructions: "", requiredProof: .text
        )
        XCTAssertNil(LearningSubject.from(task: chore))
    }

    func testApproveAccumulatesStudyMinutes() throws {
        let store = LocalFamilyStore()
        let assignment = try XCTUnwrap(
            store.assignNewTask(
                title: "读《夏洛的网》",
                instructions: "",
                category: .learning,
                rewardMinutes: 20,
                requiredProof: .text,
                reading: ReadingSpec(bookTitle: "夏洛的网", minMinutes: 45, chapterPlanText: "第1章")
            )
        )
        store.submit(assignment, text: "读完了")
        _ = store.approve(store.assignments.first { $0.id == assignment.id }!)

        let entry = store.progressEntry(subject: .literature, childId: store.activeChildId)
        XCTAssertEqual(entry.studyMinutes, 45, "阅读任务按最低阅读分钟计学时")
    }

    func testQuizRecordingIsIdempotentAndRewards() throws {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]
        let balanceBefore = store.child.rewardBalanceMinutes

        XCTAssertTrue(store.recordQuizResult(assignmentId: assignment.id, subject: .literature, correct: 8, total: 10))
        let entry = store.progressEntry(subject: .literature, childId: store.activeChildId)
        XCTAssertEqual(entry.quizPoints, 80)
        XCTAssertEqual(entry.studyMinutes, 48, "答对 8 题加成 48 分钟学时")
        XCTAssertEqual(entry.quizPassed, 1)
        XCTAssertEqual(store.child.rewardBalanceMinutes, balanceBefore + 8, "答对数即成长积分加成")
        XCTAssertTrue(store.hasTakenQuiz(for: assignment.id))
        XCTAssertEqual(
            ChildQuizResultCopy.summary(correct: 8, subject: .literature),
            "获得 8 成长积分，文学成长进度已更新。"
        )
        XCTAssertFalse(ChildQuizResultCopy.summary(correct: 8, subject: .literature).contains("分钟"))
        XCTAssertFalse(ChildQuizResultCopy.speakText(correct: 8, subject: .literature).contains("分钟"))

        XCTAssertFalse(
            store.recordQuizResult(assignmentId: assignment.id, subject: .literature, correct: 10, total: 10),
            "同一任务只能考一次，防刷分"
        )
    }

    func testBadgeLadderTiers() {
        XCTAssertNil(BadgeLadder.currentTier(hours: 5), "不足 10 小时没有徽章")
        XCTAssertEqual(BadgeLadder.currentTier(hours: 60)?.name, "入门")
        XCTAssertEqual(BadgeLadder.currentTier(hours: 1000)?.name, "诺贝尔级")
        XCTAssertEqual(BadgeLadder.nextTier(hours: 60)?.name, "小学者")
        XCTAssertNil(BadgeLadder.nextTier(hours: 1200), "到顶后没有下一档")
        XCTAssertEqual(BadgeLadder.tiers.last?.hours, 1000, "终极徽章按 1000 小时设计")
    }

    func testQuizGeneratorParseAndGuards() {
        let raw = """
        {"questions":[
            {"question":"夏洛是什么动物？","options":["蜘蛛","猪","鹅","老鼠"],
             "answerIndex":0,"explanation":"夏洛是一只蜘蛛，她在网上织字救了威尔伯。"},
            {"question":"坏题","options":["只有两个","选项"],"answerIndex":0,"explanation":""},
            {"question":"越界","options":["A","B","C","D"],"answerIndex":7,"explanation":""}
        ]}
        """
        let questions = AIQuizGenerator.parse(raw)
        XCTAssertEqual(questions.count, 1, "选项数不对或答案越界的题必须丢弃")
        XCTAssertEqual(questions[0].answerIndex, 0)
        XCTAssertTrue(questions[0].explanation.contains("蜘蛛"))
    }
}
