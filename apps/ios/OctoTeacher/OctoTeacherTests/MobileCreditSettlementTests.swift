import XCTest
@testable import OctoTeacher

/// 成长积分结算建议层（B28 桥接在 iOS 的本地 mock）的确定性单元测试。
///
/// 覆盖：六状态裁决与优先级、各 finding、ledger-neutral 护栏恒为 false、展示分组、
/// 装配器把离线重放 + 本地 store 投影成建议、脱敏与确定性，以及关键安全断言
/// （亲友鼓励/冲突/设备失败/离线回滚/撤权/缺关联 hold 绝不 proposed）。
final class MobileCreditSettlementTests: XCTestCase {

    private let engine = MobileCreditSettlementEngine()
    private let account = MobileCreditSettlementAccount(
        childSeed: MobileCreditSettlementAssembler.accountChildSeed,
        familySeed: MobileCreditSettlementAssembler.accountFamilySeed
    )

    // MARK: - helpers

    private func input(
        seed: String = "p1",
        kind: MobileCreditSettlementKind = .earn,
        source: MobileCreditSettlementSource = .offlineAction,
        amount: Int = 15,
        key: String = "k1",
        actor: MobileCreditSettlementActorRole = .child,
        childSeed: String? = nil,
        familySeed: String? = nil,
        sessionState: MobileCreditSettlementSessionState = .active,
        holdExpired: Bool = false,
        teacher: MobileCreditSettlementConclusion? = nil,
        guardian: MobileCreditSettlementConclusion? = nil,
        relatedHoldPresent: Bool = true,
        offlineReplayed: Bool = false,
        offlineConflict: Bool = false,
        offlineRolledBack: Bool = false,
        deviceFailed: Bool = false,
        probe: [String] = []
    ) -> MobileCreditSettlementProposalInput {
        MobileCreditSettlementProposalInput(
            proposalSeed: seed,
            kind: kind,
            source: source,
            childSeed: childSeed ?? account.childSeed,
            familySeed: familySeed ?? account.familySeed,
            amount: amount,
            idempotencyKey: key,
            actorRole: actor,
            sessionState: sessionState,
            holdExpired: holdExpired,
            teacherConclusion: teacher,
            guardianConclusion: guardian,
            relatedHoldPresent: relatedHoldPresent,
            offlineReplayed: offlineReplayed,
            offlineConflict: offlineConflict,
            offlineRolledBack: offlineRolledBack,
            deviceFailed: deviceFailed,
            redactionProbe: probe
        )
    }

    private func build(_ inputs: [MobileCreditSettlementProposalInput]) -> MobileCreditSettlementReport {
        engine.build(account: account, proposals: inputs)
    }

    private func only(_ inputs: [MobileCreditSettlementProposalInput]) -> MobileCreditSettlementProposal {
        let report = build(inputs)
        return report.proposals[0]
    }

    // MARK: - proposed（可建议）

    func testEarnBecomesProposable() {
        let p = only([input(kind: .earn)])
        XCTAssertEqual(p.status, .proposed)
        XCTAssertEqual(p.displayGroup, .proposable)
        XCTAssertEqual(p.amountLabel, "15 成长积分")
        XCTAssertFalse(p.amountLabel.contains("分钟"))
        XCTAssertTrue(p.actionRequired)
    }

    func testHoldBecomesFrozen() {
        let p = only([input(kind: .hold, source: .rewardRequest, amount: 30)])
        XCTAssertEqual(p.status, .proposed)
        XCTAssertEqual(p.displayGroup, .frozen)
    }

    func testReleaseBecomesRefundSuggestion() {
        let p = only([input(kind: .release, source: .deviceRewardLifecycle, relatedHoldPresent: true)])
        XCTAssertEqual(p.status, .proposed)
        XCTAssertEqual(p.displayGroup, .refundSuggestion)
    }

    // MARK: - 护栏恒为 false（账本中立）

    func testProposalNeverWritesLedgerOrUnlocks() {
        let report = build([input(kind: .earn), input(seed: "p2", kind: .hold, key: "k2")])
        for proposal in report.proposals {
            XCTAssertFalse(proposal.writesLedger)
            XCTAssertFalse(proposal.unlocksDevice)
            XCTAssertFalse(proposal.modifiesSchoolHomework)
            XCTAssertFalse(proposal.sendsNotification)
        }
        XCTAssertFalse(report.publicSummary.writesLedger)
        XCTAssertFalse(report.publicSummary.unlocksDevice)
    }

    // MARK: - blocked

    func testCrossChildFamilyMismatchIsBlocked() {
        let p = only([input(childSeed: "other-child")])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(p.displayGroup, .blocked)
        XCTAssertFalse(p.actionRequired)
        XCTAssertEqual(build([input(childSeed: "other-child")]).findings.first?.code, .crossChildFamilyMismatch)
    }

    func testNonPositiveAmountIsBlocked() {
        XCTAssertEqual(only([input(amount: 0)]).status, .blocked)
        XCTAssertEqual(only([input(amount: -5)]).status, .blocked)
        XCTAssertEqual(build([input(amount: 0)]).findings.first?.code, .invalidAmount)
    }

    func testUnsafePayloadIsBlocked() {
        let p = only([input(probe: ["Bearer abc123"])])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(probe: ["192.168.1.10"])]).findings.first?.code, .unsafePayload)
    }

    func testRevokedSessionIsBlocked() {
        let p = only([input(sessionState: .revoked)])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(sessionState: .revoked)]).findings.first?.code, .revokedActionBlocked)
    }

    func testRolledBackOfflineActionIsBlockedNeverProposed() {
        // 安全核心：离线回滚绝不结算为可用成长积分。
        let p = only([input(offlineRolledBack: true)])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertNotEqual(p.status, .proposed)
        XCTAssertEqual(build([input(offlineRolledBack: true)]).findings.first?.code, .rollbackRequired)
    }

    func testMissingRelatedHoldIsBlocked() {
        for kind in [MobileCreditSettlementKind.spend, .release, .refund] {
            let p = only([input(kind: kind, relatedHoldPresent: false)])
            XCTAssertEqual(p.status, .blocked, "\(kind) 无关联 hold 应阻断")
        }
        // earn / hold 不受影响。
        XCTAssertEqual(only([input(kind: .earn, relatedHoldPresent: false)]).status, .proposed)
    }

    // MARK: - duplicate / expired

    func testDuplicateIdempotencyKeyIsProjectedAsDuplicate() {
        let report = build([
            input(seed: "a", key: "same"),
            input(seed: "b", key: "same")
        ])
        XCTAssertEqual(report.proposals[0].status, .proposed)
        XCTAssertEqual(report.proposals[1].status, .duplicate)
        XCTAssertFalse(report.proposals[1].actionRequired)
    }

    func testOfflineReplayedIsDuplicate() {
        XCTAssertEqual(only([input(offlineReplayed: true)]).status, .duplicate)
    }

    func testExpiredHoldIsExpired() {
        let p = only([input(kind: .hold, holdExpired: true)])
        XCTAssertEqual(p.status, .expired)
        XCTAssertTrue(p.retryable)
    }

    // MARK: - conflict / review_required

    func testTeacherGuardianConflictNeedsReview() {
        let p = only([input(teacher: .approved, guardian: .rejected)])
        XCTAssertEqual(p.status, .conflict)
        XCTAssertEqual(p.displayGroup, .reviewRequired)
        XCTAssertNotEqual(p.status, .proposed)
    }

    func testOfflineConflictNeedsReview() {
        let p = only([input(offlineConflict: true)])
        XCTAssertEqual(p.status, .conflict)
        XCTAssertEqual(build([input(offlineConflict: true)]).findings.first?.code, .offlineConflictReview)
    }

    func testRelativeEncouragementOnlyReviewNeverProposed() {
        // 安全核心：亲友鼓励只能成为待审核建议。
        let p = only([input(kind: .earn, source: .relativeEncouragement, actor: .relative)])
        XCTAssertEqual(p.status, .reviewRequired)
        XCTAssertNotEqual(p.status, .proposed)
    }

    func testDeviceFailureBecomesRefundReview() {
        let p = only([input(deviceFailed: true)])
        XCTAssertEqual(p.status, .reviewRequired)
        XCTAssertEqual(build([input(deviceFailed: true)]).findings.first?.code, .deviceFailureRefundReview)
    }

    // MARK: - 优先级

    func testMismatchTakesPriorityOverEverything() {
        // 即便又是冲突又是回滚，账户不匹配优先 blocked。
        let p = only([input(childSeed: "x", teacher: .approved, guardian: .rejected, offlineRolledBack: true)])
        XCTAssertEqual(p.status, .blocked)
        XCTAssertEqual(build([input(childSeed: "x", teacher: .approved, guardian: .rejected, offlineRolledBack: true)]).findings.first?.code, .crossChildFamilyMismatch)
    }

    // MARK: - 摘要

    func testSummaryCountsAndTotals() {
        let report = build([
            input(seed: "earn1", kind: .earn, amount: 15, key: "k1"),                 // proposed
            input(seed: "earn2", kind: .earn, amount: 10, key: "k2"),                 // proposed
            input(seed: "rev", source: .relativeEncouragement, key: "k3", actor: .relative), // review
            input(seed: "blk", key: "k4", offlineRolledBack: true)                    // blocked
        ])
        XCTAssertEqual(report.publicSummary.proposalCount, 4)
        XCTAssertEqual(report.publicSummary.proposedCount, 2)
        XCTAssertEqual(report.publicSummary.reviewRequiredCount, 1)
        XCTAssertEqual(report.publicSummary.blockedCount, 1)
        XCTAssertEqual(report.publicSummary.totalProposedAmount, 25)
        XCTAssertTrue(report.hasAttention)
    }

    func testEmptyReport() {
        XCTAssertTrue(MobileCreditSettlementReport.empty.isEmpty)
        XCTAssertEqual(MobileCreditSettlementReport.empty.headline, "暂无结算建议")
        XCTAssertFalse(MobileCreditSettlementReport.empty.hasAttention)
    }

    // MARK: - 脱敏 + 确定性

    func testOutputIsRedacted() {
        let report = build([
            input(seed: "child-secret-001", kind: .earn, key: "k1"),
            input(seed: "device-token-xyz", kind: .hold, key: "k2"),
            input(seed: "p3", source: .relativeEncouragement, key: "k3", actor: .relative)
        ])
        let displayed = ([report.headline] + report.proposals.flatMap {
            [$0.publicProposalRef, $0.childPublicRef, $0.accountPublicRef, $0.reason, $0.scopeLabel, $0.kindLabel, $0.statusLabel, $0.sourceLabel]
        }).joined(separator: " ")

        XCTAssertFalse(MobileSyncPayloadGuard.isUnsafe(displayed))
        for marker in ["child-secret", "device-token", "taskId", "claimId", "Bearer ", "192.168.", "family-", "ledger-"] {
            XCTAssertFalse(displayed.contains(marker), "不应泄露 \(marker)：\(displayed)")
        }
        XCTAssertFalse(MobileCreditSettlementEngine.reportLeaks(report))
    }

    func testBuildIsDeterministic() {
        let inputs = [
            input(seed: "a", kind: .earn, key: "k1"),
            input(seed: "b", kind: .hold, key: "k2"),
            input(seed: "c", source: .relativeEncouragement, key: "k3", actor: .relative)
        ]
        XCTAssertEqual(build(inputs), build(inputs))
    }

    // MARK: - 装配器 + 集成（基于离线重放与本地 store）

    func testAssemblerProjectsOfflineMockIntoAllDisplayGroups() {
        // 用内置离线 mock + 确定性 allClear 重放，再装配结算建议。
        let outbox = MobileOfflineOutboxStore.mock()
        let replay = MobileOfflineReplayStore()
        replay.replay(outbox: outbox)

        let settlement = MobileCreditSettlementStore()
        let report = settlement.refresh(
            offlineReport: replay.report,
            family: LocalFamilyStore(),
            schoolFamily: SchoolFamilyStore(),
            screenTime: MockScreenTimeController()
        )

        XCTAssertFalse(report.isEmpty)
        // 默认离线 mock 应覆盖五个展示分组中的关键安全态。
        XCTAssertFalse(report.proposals(in: .proposable).isEmpty, "应有可建议（任务赚取）")
        XCTAssertFalse(report.proposals(in: .frozen).isEmpty, "应有冻结（成长积分兑换请求）")
        XCTAssertFalse(report.proposals(in: .reviewRequired).isEmpty, "应有待审核（亲友鼓励/冲突）")
        XCTAssertFalse(report.proposals(in: .blocked).isEmpty, "应有已阻断（离线回滚）")
        XCTAssertFalse(report.proposals(in: .refundSuggestion).isEmpty, "应有退款/回滚建议（设备回执释放）")

        // 关键安全断言：没有任何亲友鼓励或回滚动作被结算为可建议成长积分。
        for proposal in report.proposals where proposal.source == .relativeEncouragement {
            XCTAssertEqual(proposal.status, .reviewRequired)
        }
        XCTAssertFalse(MobileCreditSettlementEngine.reportLeaks(report))
    }

    func testAssemblerDeviceSessionProducesFrozenAndRelease() {
        let screenTime = MockScreenTimeController()
        let base = Date(timeIntervalSince1970: 1_000_000)
        // 开一个会话再由家长提前结束，产生未用分钟收据。
        _ = try? screenTime.startSession(minutes: 30, now: base)
        _ = screenTime.endSessionByParent(now: base.addingTimeInterval(60)) // 用 1 分钟，未用 29

        let settlement = MobileCreditSettlementStore()
        let report = settlement.refresh(
            offlineReport: .empty,
            family: LocalFamilyStore(),
            schoolFamily: SchoolFamilyStore(),
            screenTime: screenTime
        )
        // 会话已结束，无 active hold；应有一条释放建议（退款/回滚分组）。
        XCTAssertTrue(report.proposals(in: .frozen).isEmpty)
        let releases = report.proposals.filter { $0.kind == .release }
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.amount, 29)
        XCTAssertEqual(releases.first?.displayGroup, .refundSuggestion)
        XCTAssertFalse(releases.first?.unlocksDevice ?? true)
    }

    func testAssemblerActiveSessionProducesFrozenHold() {
        let screenTime = MockScreenTimeController()
        _ = try? screenTime.startSession(minutes: 20, now: Date(timeIntervalSince1970: 1_000_000))

        let settlement = MobileCreditSettlementStore()
        let report = settlement.refresh(
            offlineReport: .empty,
            family: LocalFamilyStore(),
            schoolFamily: SchoolFamilyStore(),
            screenTime: screenTime
        )
        let holds = report.proposals.filter { $0.kind == .hold }
        XCTAssertEqual(holds.count, 1)
        XCTAssertEqual(holds.first?.amount, 20)
        XCTAssertEqual(holds.first?.displayGroup, .frozen)
    }
}
