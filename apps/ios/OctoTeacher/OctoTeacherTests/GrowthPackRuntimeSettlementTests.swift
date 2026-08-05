import XCTest
@testable import OctoTeacher

/// 成长包运行结算层（B29 结算契约在 iOS 的本地 mock）的确定性单元测试。
///
/// 覆盖：七状态阶段裁决与优先级、七类活动、各 finding、ledger-neutral 护栏恒为 false、
/// 家长展示分组、装配器把本地 store 投影成运行步骤、脱敏与确定性，以及关键安全断言
/// （未审核证明/失败测验/老师退回/申诉中/年龄不适配/内容被拒/重复/作废/账户不匹配绝不可建议）。
final class GrowthPackRuntimeSettlementTests: XCTestCase {

    private let engine = GrowthPackRuntimeSettlementEngine()
    private let account = GrowthRuntimeAccount(
        childSeed: GrowthPackRuntimeAssembler.accountChildSeed,
        familySeed: GrowthPackRuntimeAssembler.accountFamilySeed
    )

    // MARK: - helpers

    private func input(
        seed: String = "s1",
        kind: GrowthRuntimeActivityKind = .basicHabit,
        stage: GrowthRuntimeStage = .verified,
        requiredProofCount: Int = 1,
        submittedProofCount: Int = 1,
        proofStatus: GrowthRuntimeProofStatus = .approved,
        verificationOutcome: GrowthRuntimeVerificationOutcome = .approved,
        credit: Int = 10,
        key: String = "k1",
        quizPassed: Bool? = nil,
        teacherReview: GrowthRuntimeVerificationOutcome? = nil,
        moderationStatus: GrowthRuntimeContentReviewStatus = .notRequired,
        ageAppropriate: Bool = true,
        appealOpen: Bool = false,
        duplicate: Bool = false,
        partOfAcceptedPlan: Bool = true,
        childSeed: String? = nil,
        familySeed: String? = nil,
        probe: [String] = []
    ) -> GrowthRuntimeStepInput {
        GrowthRuntimeStepInput(
            stepSeed: seed,
            packSeed: "pack",
            childSeed: childSeed ?? account.childSeed,
            familySeed: familySeed ?? account.familySeed,
            title: "成长步骤",
            order: 1,
            kind: kind,
            stage: stage,
            requiredProofCount: requiredProofCount,
            submittedProofCount: submittedProofCount,
            proofStatus: proofStatus,
            verificationOutcome: verificationOutcome,
            suggestedCredit: credit,
            idempotencyKey: key,
            quizPassed: quizPassed,
            teacherReview: teacherReview,
            moderationStatus: moderationStatus,
            ageAppropriate: ageAppropriate,
            appealOpen: appealOpen,
            duplicate: duplicate,
            partOfAcceptedPlan: partOfAcceptedPlan,
            redactionProbe: probe
        )
    }

    private func build(_ inputs: [GrowthRuntimeStepInput]) -> GrowthRuntimeSettlementReport {
        engine.build(account: account, packTitle: "测试包", packSummary: "摘要", steps: inputs)
    }

    private func only(_ inputs: [GrowthRuntimeStepInput]) -> GrowthRuntimeStepProjection {
        build(inputs).steps[0]
    }

    // MARK: - 可建议（verified + 证明齐备）

    func testVerifiedHabitBecomesCreditSuggested() {
        let p = only([input(kind: .basicHabit, stage: .verified)])
        XCTAssertEqual(p.status, .creditSuggested)
        XCTAssertEqual(p.parentGroup, .proposable)
        XCTAssertTrue(p.actionRequired)
        XCTAssertEqual(p.settlement.suggestedCredit, 10)
        XCTAssertEqual(p.settlement.suggestedCreditLabel, "10 成长积分")
        XCTAssertFalse(p.settlement.suggestedCreditLabel.contains("分钟"))
        XCTAssertEqual(p.suggestedNextStage, .credited)
    }

    func testVerifiedExerciseProofBecomesCreditSuggested() {
        let p = only([input(kind: .exerciseExternalProof, stage: .verified, credit: 12)])
        XCTAssertEqual(p.status, .creditSuggested)
        XCTAssertEqual(p.settlement.suggestedCredit, 12)
    }

    func testPassedQuizBecomesCreditSuggested() {
        let p = only([input(kind: .quiz, stage: .verified, quizPassed: true)])
        XCTAssertEqual(p.status, .creditSuggested)
    }

    func testCompositePackHasTwoAbilitySuggestions() {
        let p = only([input(kind: .compositeGrowthPack, stage: .verified, credit: 20)])
        XCTAssertEqual(p.status, .creditSuggested)
        XCTAssertEqual(p.settlement.abilitySuggestionCount, 2)
    }

    // MARK: - 护栏恒为 false（账本中立）

    func testProjectionNeverWritesLedgerOrGrantsBadge() {
        let report = build([input(kind: .basicHabit), input(seed: "s2", kind: .quiz, key: "k2", quizPassed: true)])
        for step in report.steps {
            XCTAssertFalse(step.writesLedger)
            XCTAssertFalse(step.grantsBadge)
            XCTAssertFalse(step.updatesAbilityCard)
            XCTAssertFalse(step.modifiesTaskState)
            XCTAssertFalse(step.publishesHonorWall)
            XCTAssertFalse(step.settlement.writesLedger)
            XCTAssertFalse(step.settlement.grantsBadge)
        }
        XCTAssertFalse(report.publicSummary.writesLedger)
        XCTAssertFalse(report.publicSummary.grantsBadge)
    }

    // MARK: - 阶段状态机

    func testPlannedStaysPlanned() {
        let p = only([input(stage: .planned)])
        XCTAssertEqual(p.status, .planned)
        XCTAssertNil(p.parentGroup)
        XCTAssertEqual(p.settlement.suggestedCredit, 0)
    }

    func testSubmittedNeedsReview() {
        let p = only([input(stage: .submitted)])
        XCTAssertEqual(p.status, .reviewRequired)
        XCTAssertEqual(p.parentGroup, .reviewRequired)
        XCTAssertTrue(p.retryable)
        XCTAssertEqual(build([input(stage: .submitted)]).findings.first?.code, .verificationPending)
    }

    func testCreditedIsAlreadyCredited() {
        let p = only([input(stage: .credited)])
        XCTAssertEqual(p.status, .alreadyCredited)
        XCTAssertNil(p.parentGroup)
        XCTAssertEqual(p.settlement.suggestedCredit, 0)
    }

    func testVoidedIsVoided() {
        let p = only([input(stage: .voided)])
        XCTAssertEqual(p.status, .voided)
        XCTAssertNil(p.parentGroup)
    }

    func testAppealedIsAppealingNeverCredited() {
        let p = only([input(stage: .appealed, appealOpen: true)])
        XCTAssertEqual(p.status, .reviewRequired)
        XCTAssertTrue(p.isAppealing)
        XCTAssertEqual(p.parentGroup, .appealing)
        XCTAssertNotEqual(p.status, .creditSuggested)
        XCTAssertEqual(build([input(stage: .appealed, appealOpen: true)]).findings.first?.code, .appealOpen)
    }

    // MARK: - 阻断（verified 链路）

    func testMissingProofIsBlocked() {
        let p = only([input(stage: .verified, submittedProofCount: 0, proofStatus: .missing)])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(p.parentGroup, .blocked)
        XCTAssertEqual(build([input(stage: .verified, submittedProofCount: 0, proofStatus: .missing)]).findings.first?.code, .missingProof)
    }

    func testRejectedProofIsBlocked() {
        let p = only([input(stage: .verified, proofStatus: .rejected)])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(stage: .verified, proofStatus: .rejected)]).findings.first?.code, .proofRejected)
    }

    func testFailedQuizIsBlockedNeverCredited() {
        let p = only([input(kind: .quiz, stage: .verified, quizPassed: false)])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertNotEqual(p.status, .creditSuggested)
        XCTAssertEqual(build([input(kind: .quiz, stage: .verified, quizPassed: false)]).findings.first?.code, .failedQuiz)
    }

    func testTeacherReturnedIsBlocked() {
        let p = only([input(kind: .schoolHomework, stage: .verified, teacherReview: .returned)])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(kind: .schoolHomework, stage: .verified, teacherReview: .returned)]).findings.first?.code, .teacherReturned)
    }

    func testRejectedVerificationIsBlocked() {
        let p = only([input(stage: .verified, verificationOutcome: .rejected)])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(stage: .verified, verificationOutcome: .rejected)]).findings.first?.code, .verificationRejected)
    }

    func testAgeInappropriateIsBlocked() {
        let p = only([input(stage: .verified, ageAppropriate: false)])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(stage: .verified, ageAppropriate: false)]).findings.first?.code, .ageInappropriate)
    }

    func testContentRejectedIsBlocked() {
        let p = only([input(kind: .creativeUpload, stage: .verified, moderationStatus: .rejected)])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(kind: .creativeUpload, stage: .verified, moderationStatus: .rejected)]).findings.first?.code, .contentRejected)
    }

    func testContentPendingNeedsReview() {
        let p = only([input(kind: .mediaLearning, stage: .verified, moderationStatus: .pending)])
        XCTAssertEqual(p.status, .reviewRequired)
        XCTAssertEqual(p.parentGroup, .reviewRequired)
        XCTAssertEqual(build([input(kind: .mediaLearning, stage: .verified, moderationStatus: .pending)]).findings.first?.code, .contentReviewRequired)
    }

    func testCrossChildFamilyMismatchIsBlocked() {
        let p = only([input(childSeed: "other-child")])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(childSeed: "other-child")]).findings.first?.code, .crossChildFamilyMismatch)
    }

    func testUnknownRuntimeTaskIsBlocked() {
        let p = only([input(partOfAcceptedPlan: false)])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(partOfAcceptedPlan: false)]).findings.first?.code, .unknownRuntimeTask)
    }

    func testUnsafePayloadIsBlocked() {
        let p = only([input(probe: ["Bearer abc12345"])])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(probe: ["192.168.1.10"])]).findings.first?.code, .unsafePayload)
    }

    // MARK: - 重复幂等

    func testDuplicateIdempotencyKeyIsDuplicate() {
        let report = build([
            input(seed: "a", key: "same"),
            input(seed: "b", key: "same")
        ])
        XCTAssertEqual(report.steps[0].status, .creditSuggested)
        XCTAssertEqual(report.steps[1].status, .duplicate)
        XCTAssertNil(report.steps[1].parentGroup)
    }

    func testExplicitDuplicateFlagIsDuplicate() {
        XCTAssertEqual(only([input(duplicate: true)]).status, .duplicate)
    }

    // MARK: - 优先级

    func testMismatchTakesPriorityOverEverything() {
        let p = only([input(stage: .verified, proofStatus: .rejected, quizPassed: false, childSeed: "x")])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(stage: .verified, proofStatus: .rejected, childSeed: "x")]).findings.first?.code, .crossChildFamilyMismatch)
    }

    // MARK: - 摘要 / 家长分组

    func testSummaryCountsAndTotals() {
        let report = build([
            input(seed: "c1", kind: .basicHabit, stage: .verified, credit: 10, key: "k1"),  // creditSuggested
            input(seed: "c2", kind: .exerciseExternalProof, stage: .verified, credit: 12, key: "k2"), // creditSuggested
            input(seed: "r1", stage: .submitted, key: "k3"),                                // reviewRequired
            input(seed: "a1", stage: .appealed, key: "k4", appealOpen: true),               // appealing
            input(seed: "b1", kind: .quiz, stage: .verified, key: "k5", quizPassed: false)  // blocked
        ])
        XCTAssertEqual(report.publicSummary.stepCount, 5)
        XCTAssertEqual(report.publicSummary.creditSuggestedCount, 2)
        XCTAssertEqual(report.publicSummary.reviewRequiredCount, 2) // submitted + appealed 都是 reviewRequired 状态
        XCTAssertEqual(report.publicSummary.appealingCount, 1)
        XCTAssertEqual(report.publicSummary.blockedCount, 1)
        XCTAssertEqual(report.publicSummary.totalSuggestedCredit, 22)
        XCTAssertTrue(report.hasAttention)
        XCTAssertEqual(report.steps(in: GrowthRuntimeParentGroup.proposable).count, 2)
        XCTAssertEqual(report.steps(in: GrowthRuntimeParentGroup.appealing).count, 1)
        XCTAssertEqual(report.steps(in: GrowthRuntimeParentGroup.blocked).count, 1)
    }

    func testEmptyReport() {
        XCTAssertTrue(GrowthRuntimeSettlementReport.empty.isEmpty)
        XCTAssertEqual(GrowthRuntimeSettlementReport.empty.childHeadline, "暂无成长包步骤")
        XCTAssertFalse(GrowthRuntimeSettlementReport.empty.hasAttention)
    }

    // MARK: - 脱敏 + 确定性

    func testOutputIsRedacted() {
        let report = build([
            input(seed: "child-secret-001", kind: .basicHabit, key: "k1"),
            input(seed: "pack-token-xyz", kind: .quiz, stage: .verified, key: "k2", quizPassed: true),
            input(seed: "ledger-leak-3", stage: .appealed, key: "k3", appealOpen: true)
        ])
        let displayed = ([report.packTitle, report.packSummary, report.childHeadline, report.parentHeadline]
            + report.steps.flatMap {
                [$0.publicStepRef, $0.publicPackRef, $0.childPublicRef, $0.title, $0.reason,
                 $0.nextStep, $0.proofRequirementLabel, $0.kindLabel, $0.stageLabel, $0.statusLabel,
                 $0.settlement.scopeLabel]
            }).joined(separator: " ")

        XCTAssertFalse(MobileSyncPayloadGuard.isUnsafe(displayed))
        for marker in ["child-secret", "pack-token", "ledger-leak", "taskId", "claimId", "Bearer ", "192.168.", "family-", "homework-"] {
            XCTAssertFalse(displayed.contains(marker), "不应泄露 \(marker)：\(displayed)")
        }
        XCTAssertFalse(GrowthPackRuntimeSettlementEngine.reportLeaks(report))
    }

    func testRedactionFallbackBlocksColonStyleInternalRefs() {
        let report = engine.build(
            account: account,
            packTitle: "child:raw-secret",
            packSummary: "family:raw-secret",
            steps: [input(seed: "safe", kind: .basicHabit, key: "k1")]
        )

        XCTAssertEqual(report.steps.count, 1)
        XCTAssertEqual(report.steps[0].status, .blocked)
        XCTAssertEqual(report.findings.first?.code, .publicSummaryLeak)
        XCTAssertFalse(GrowthPackRuntimeSettlementEngine.reportLeaks(report))
        let displayed = ([report.packTitle, report.packSummary, report.childHeadline, report.parentHeadline]
            + report.steps.flatMap { [$0.title, $0.reason, $0.nextStep, $0.publicStepRef, $0.publicPackRef, $0.childPublicRef] }
            + report.findings.map(\.message)).joined(separator: " ")
        XCTAssertFalse(displayed.contains("child:raw-secret"))
        XCTAssertFalse(displayed.contains("family:raw-secret"))
    }

    func testBuildIsDeterministic() {
        let inputs = [
            input(seed: "a", kind: .basicHabit, key: "k1"),
            input(seed: "b", kind: .quiz, stage: .verified, key: "k2", quizPassed: true),
            input(seed: "c", stage: .appealed, key: "k3", appealOpen: true)
        ]
        XCTAssertEqual(build(inputs), build(inputs))
    }

    // MARK: - 装配器 + 集成（基于内置 mock + 本地 store）

    func testAssemblerCoversAllActivityKindsAndParentGroups() {
        let store = GrowthPackRuntimeStore()
        let report = store.refresh(family: LocalFamilyStore(), schoolFamily: SchoolFamilyStore())

        XCTAssertFalse(report.isEmpty)

        // 覆盖全部七类活动。
        let kinds = Set(report.steps.map { $0.kind })
        for kind in GrowthRuntimeActivityKind.allCases {
            XCTAssertTrue(kinds.contains(kind), "应覆盖活动类型 \(kind.label)")
        }

        // 家长四类摘要都应非空。
        XCTAssertFalse(report.steps(in: .proposable).isEmpty, "应有可建议")
        XCTAssertFalse(report.steps(in: .reviewRequired).isEmpty, "应有待审核")
        XCTAssertFalse(report.steps(in: .blocked).isEmpty, "应有已阻断")
        XCTAssertFalse(report.steps(in: .appealing).isEmpty, "应有申诉中")

        // 关键安全断言：失败测验/老师退回/缺证明/申诉中绝不被结算为可建议。
        for step in report.steps where step.status == .creditSuggested {
            XCTAssertFalse(step.isAppealing)
            XCTAssertEqual(step.fromStage, .verified)
        }
        XCTAssertFalse(GrowthPackRuntimeSettlementEngine.reportLeaks(report))
    }

    func testAssemblerFoldsSubmittedAssignmentsAsReview() {
        // LocalFamilyStore 默认含已提交任务时，应折入为待复核步骤。
        let family = LocalFamilyStore()
        let submittedCount = family.assignments.filter { $0.status == .submitted }.count
        let store = GrowthPackRuntimeStore()
        let report = store.refresh(family: family, schoolFamily: SchoolFamilyStore())
        let assignmentSteps = report.steps.filter { $0.title.hasPrefix("任务：") }
        XCTAssertEqual(assignmentSteps.count, submittedCount)
        for step in assignmentSteps {
            XCTAssertEqual(step.status, .reviewRequired)
        }
    }

    func testAssemblerIsDeterministic() {
        // 同一数据源实例（相同任务/作业 UUID）重复装配应恒定输出。
        let family = LocalFamilyStore()
        let school = SchoolFamilyStore()
        let r1 = GrowthPackRuntimeStore().refresh(family: family, schoolFamily: school)
        let r2 = GrowthPackRuntimeStore().refresh(family: family, schoolFamily: school)
        XCTAssertEqual(r1, r2)
    }
}
