import XCTest
@testable import OctoTeacher

/// 成长证据链申诉时间线层（B30 契约在 iOS 的本地 mock）的确定性单元测试。
///
/// 覆盖：九类事件、链状态裁决与优先级、角色边界、老师/家长冲突、亲友复核、成长积分冻结/释放/阻断、
/// 申诉发起/恢复/驳回、撤销传播、缺 hash、prevHash 断链、重复证明、跨孩子复用、重复幂等、
/// 公开可见性、脱敏与确定性、护栏恒为 false，以及装配器把本地 store 折入证据链的集成。
final class GrowthEvidenceTimelineTests: XCTestCase {

    private let engine = GrowthEvidenceTimelineEngine()
    private let familySeed = GrowthEvidenceTimelineAssembler.accountFamilySeed
    private let childSeed = GrowthEvidenceTimelineAssembler.accountChildSeed

    // MARK: - helpers

    private func event(
        seed: String = "e1",
        kind: GrowthEvidenceTimelineEventKind = .childSubmitted,
        role: GrowthEvidenceTimelineActorRole = .child,
        occurredAt: String = "2026-06-20T08:00:00Z",
        proofSeed: String? = nil,
        appealSeed: String? = nil,
        creditSuggestionSeed: String? = nil,
        hash: String? = "h",
        prevHash: String? = nil,
        decision: GrowthEvidenceTimelineDecision? = nil,
        teacherConclusion: GrowthEvidenceTimelineDecision? = nil,
        guardianConclusion: GrowthEvidenceTimelineDecision? = nil,
        guardianReview: GrowthEvidenceTimelineGuardianReview? = nil,
        visibility: GrowthEvidenceTimelineVisibility? = nil,
        creditAmount: Int = 0,
        idempotencyKey: String? = nil,
        revocation: GrowthEvidenceTimelineRevocation? = nil,
        childSeedOverride: String? = nil,
        probe: [String] = []
    ) -> GrowthEvidenceTimelineEventInput {
        GrowthEvidenceTimelineEventInput(
            eventSeed: seed,
            kind: kind,
            occurredAt: occurredAt,
            familySeed: familySeed,
            childSeed: childSeedOverride ?? childSeed,
            actorRole: role,
            actorSeed: "actor",
            title: "证据事件",
            proofSeed: proofSeed,
            appealSeed: appealSeed,
            creditSuggestionSeed: creditSuggestionSeed,
            hash: hash,
            prevHash: prevHash,
            decision: decision,
            teacherConclusion: teacherConclusion,
            guardianConclusion: guardianConclusion,
            guardianReview: guardianReview,
            visibility: visibility,
            creditAmount: creditAmount,
            idempotencyKey: idempotencyKey,
            revocation: revocation,
            redactionProbe: probe
        )
    }

    private func build(
        _ events: [GrowthEvidenceTimelineEventInput],
        existingProofs: [String] = [],
        existingKeys: [String] = []
    ) -> GrowthEvidenceTimelineReport {
        let input = GrowthEvidenceTimelineCaseInput(
            familySeed: familySeed,
            childSeed: childSeed,
            caseSeed: "case",
            existingProofSeeds: existingProofs,
            existingIdempotencyKeys: existingKeys,
            events: events
        )
        return engine.build(input, caseTitle: "测试案件", caseSummary: "摘要")
    }

    private func only(_ events: [GrowthEvidenceTimelineEventInput]) -> GrowthEvidenceTimelineNode {
        build(events).nodes[0]
    }

    private func fullyPropagated() -> GrowthEvidenceTimelineRevocation {
        GrowthEvidenceTimelineRevocation(timelineHidden: true, creditBlocked: true, feedWithdrawn: true,
                                         homeworkMarkedRevoked: true, relativeVisibilityRevoked: true)
    }

    // MARK: - 基本节点

    func testChildSubmittedIsAccepted() {
        let node = only([event(kind: .childSubmitted, role: .child)])
        XCTAssertEqual(node.status, .accepted)
        XCTAssertFalse(node.hiddenFromPublic)
        XCTAssertTrue(node.hashPresent)
    }

    func testTeacherVerifiedIsAccepted() {
        XCTAssertEqual(only([event(kind: .teacherVerified, role: .teacher)]).status, .accepted)
    }

    // MARK: - 缺 hash / 不安全负载

    func testMissingHashIsBlocked() {
        let node = only([event(hash: nil)])
        XCTAssertEqual(node.status, .blocked)
        XCTAssertTrue(node.hiddenFromPublic)
        XCTAssertEqual(build([event(hash: nil)]).findings.contains { $0.code == .missingHash }, true)
    }

    func testUnsafePayloadIsBlocked() {
        XCTAssertEqual(only([event(probe: ["Bearer abc12345"])]).status, .blocked)
        XCTAssertTrue(build([event(probe: ["192.168.1.10"])]).findings.contains { $0.code == .unsafePayload })
    }

    // MARK: - 角色边界

    func testRelativeCannotVerify() {
        let node = only([event(kind: .teacherVerified, role: .relative)])
        XCTAssertEqual(node.status, .blocked)
        XCTAssertTrue(build([event(kind: .teacherVerified, role: .relative)]).findings.contains { $0.code == .relativePermissionBlocked })
    }

    func testChildCannotConfirmAsGuardian() {
        let node = only([event(kind: .guardianConfirmed, role: .child)])
        XCTAssertEqual(node.status, .blocked)
        XCTAssertTrue(build([event(kind: .guardianConfirmed, role: .child)]).findings.contains { $0.code == .roleBoundaryViolation })
    }

    func testChildCanOpenAppeal() {
        XCTAssertEqual(only([event(kind: .appealOpened, role: .child, appealSeed: "a")]).status, .frozen)
    }

    // MARK: - 老师/家长冲突

    func testTeacherGuardianConflict() {
        let node = only([event(kind: .guardianConfirmed, role: .guardian, teacherConclusion: .approved, guardianConclusion: .returned)])
        XCTAssertEqual(node.status, .conflict)
        XCTAssertTrue(node.hiddenFromPublic)
        XCTAssertTrue(build([event(kind: .guardianConfirmed, role: .guardian, teacherConclusion: .approved, guardianConclusion: .rejected)])
            .findings.contains { $0.code == .teacherGuardianConflict })
    }

    // MARK: - 亲友鼓励

    func testRelativeEncouragePendingNeedsReview() {
        let node = only([event(kind: .relativeEncouraged, role: .relative, guardianReview: .pending)])
        XCTAssertEqual(node.status, .reviewRequired)
        XCTAssertTrue(node.hiddenFromPublic)
        XCTAssertTrue(build([event(kind: .relativeEncouraged, role: .relative, guardianReview: .pending)])
            .findings.contains { $0.code == .relativeReviewRequired })
    }

    func testRelativeEncourageApprovedEntersTimeline() {
        let report = build([event(kind: .relativeEncouraged, role: .relative, guardianReview: .approved, visibility: .family)])
        XCTAssertEqual(report.nodes[0].status, .accepted)
        XCTAssertEqual(report.publicTimeline.count, 1)
        XCTAssertEqual(report.publicTimeline[0].visibility, .family)
    }

    // MARK: - 成长积分建议

    func testCreditSuggestedAlignedIsReleased() {
        let report = build([event(kind: .creditSuggested, role: .system, creditSuggestionSeed: "c",
                                  teacherConclusion: .approved, guardianConclusion: .approved, creditAmount: 10)])
        XCTAssertEqual(report.nodes[0].status, .released)
        XCTAssertEqual(report.creditControls.first?.state, .released)
        XCTAssertEqual(report.creditControls.first?.amount, 10)
        XCTAssertTrue(report.findings.contains { $0.code == .creditReleaseAllowed })
    }

    func testCreditSuggestedNotAlignedIsFrozen() {
        let report = build([event(kind: .creditSuggested, role: .system, creditSuggestionSeed: "c",
                                  teacherConclusion: .approved, creditAmount: 8)])
        XCTAssertEqual(report.nodes[0].status, .frozen)
        XCTAssertEqual(report.creditControls.first?.state, .frozen)
        XCTAssertTrue(report.findings.contains { $0.code == .creditFreezeRequired })
    }

    // MARK: - 申诉

    func testAppealOpenedFreezesCredit() {
        let report = build([event(kind: .appealOpened, role: .guardian, appealSeed: "a", creditAmount: 8)])
        XCTAssertEqual(report.nodes[0].status, .frozen)
        XCTAssertEqual(report.appealDecisions.first?.state, .open)
        XCTAssertTrue(report.appealDecisions.first?.actionRequired ?? false)
        XCTAssertEqual(report.creditControls.first?.state, .frozen)
    }

    func testAppealRestored() {
        let report = build([event(kind: .appealResolved, role: .guardian, appealSeed: "a", decision: .restored, creditAmount: 8)])
        XCTAssertEqual(report.nodes[0].status, .restored)
        XCTAssertEqual(report.appealDecisions.first?.state, .restored)
        XCTAssertEqual(report.appealDecisions.first?.creditState, .released)
        XCTAssertEqual(report.creditControls.first?.state, .released)
        XCTAssertTrue(report.findings.contains { $0.code == .appealRestored })
    }

    func testAppealRejectedKeepsCreditBlocked() {
        let report = build([event(kind: .appealResolved, role: .guardian, appealSeed: "a", decision: .rejected, creditAmount: 8)])
        XCTAssertEqual(report.nodes[0].status, .rejected)
        XCTAssertEqual(report.appealDecisions.first?.state, .rejected)
        XCTAssertEqual(report.creditControls.first?.state, .blocked)
        XCTAssertTrue(report.findings.contains { $0.code == .appealRejected })
    }

    // MARK: - 撤销传播

    func testRevocationNotPropagatedNeedsAction() {
        let partial = GrowthEvidenceTimelineRevocation(timelineHidden: true, creditBlocked: true, feedWithdrawn: false,
                                                       homeworkMarkedRevoked: false, relativeVisibilityRevoked: false)
        let node = only([event(kind: .revoked, role: .guardian, proofSeed: "p", revocation: partial)])
        XCTAssertEqual(node.status, .revoked)
        XCTAssertTrue(node.actionRequired)
        XCTAssertTrue(build([event(kind: .revoked, role: .guardian, proofSeed: "p", revocation: partial)])
            .findings.contains { $0.code == .revocationNotPropagated })
    }

    func testRevocationFullyPropagatedNoAction() {
        let node = only([event(kind: .revoked, role: .guardian, proofSeed: "p", revocation: fullyPropagated())])
        XCTAssertEqual(node.status, .revoked)
        XCTAssertFalse(node.actionRequired)
        // 撤销阻断下游成长积分。
        XCTAssertEqual(build([event(kind: .revoked, role: .guardian, proofSeed: "p", revocation: fullyPropagated())])
            .creditControls.first?.state, .blocked)
    }

    // MARK: - 链校验

    func testPrevHashMismatchIsBlocked() {
        let report = build([
            event(seed: "a", occurredAt: "2026-06-20T08:00:00Z", hash: "h1"),
            event(seed: "b", occurredAt: "2026-06-20T08:01:00Z", hash: "h2", prevHash: "wrong")
        ])
        XCTAssertEqual(report.nodes[0].status, .accepted)
        XCTAssertEqual(report.nodes[1].status, .blocked)
        XCTAssertTrue(report.findings.contains { $0.code == .prevHashMismatch })
    }

    func testMatchingPrevHashChains() {
        let report = build([
            event(seed: "a", occurredAt: "2026-06-20T08:00:00Z", hash: "h1"),
            event(seed: "b", occurredAt: "2026-06-20T08:01:00Z", hash: "h2", prevHash: "h1")
        ])
        XCTAssertEqual(report.nodes[1].status, .accepted)
        XCTAssertEqual(report.nodes[1].prevPublicEventRef, report.nodes[0].publicEventRef)
    }

    // MARK: - 重复 / 跨孩子证明

    func testDuplicateProofIsBlocked() {
        let report = build([event(seed: "a", proofSeed: "shared")], existingProofs: ["shared"])
        XCTAssertEqual(report.nodes[0].status, .blocked)
        XCTAssertTrue(report.findings.contains { $0.code == .duplicateProof })
    }

    func testCrossChildScopeIsBlocked() {
        let report = build([event(childSeedOverride: "other-child")])
        XCTAssertEqual(report.nodes[0].status, .blocked)
        XCTAssertTrue(report.findings.contains { $0.code == .crossChildProofReuse })
    }

    // MARK: - 重复幂等

    func testDuplicateIdempotencyIsReplay() {
        let report = build([event(seed: "a", kind: .creditSuggested, role: .system,
                                  teacherConclusion: .approved, guardianConclusion: .approved,
                                  idempotencyKey: "k")], existingKeys: ["k"])
        XCTAssertEqual(report.nodes[0].status, .duplicate)
        XCTAssertTrue(report.nodes[0].hiddenFromPublic)
        XCTAssertTrue(report.creditControls.isEmpty)
        XCTAssertTrue(report.findings.contains { $0.code == .duplicateIdempotency })
    }

    // MARK: - 公开可见性

    func testBlockedNodeNeverEntersPublicTimeline() {
        let report = build([event(hash: nil, visibility: .public)])
        XCTAssertTrue(report.publicTimeline.isEmpty)
    }

    func testTimelinePublishedDefaultsToFamily() {
        let report = build([event(kind: .timelinePublished, role: .guardian)])
        XCTAssertEqual(report.publicTimeline.first?.visibility, .family)
    }

    // MARK: - 护栏恒为 false

    func testGuardrailsAlwaysFalse() {
        let report = build([
            event(seed: "a", kind: .creditSuggested, role: .system, teacherConclusion: .approved, guardianConclusion: .approved, creditAmount: 10),
            event(seed: "b", kind: .appealOpened, role: .guardian, appealSeed: "ap", creditAmount: 5)
        ])
        for node in report.nodes {
            XCTAssertFalse(node.writesLedger)
            XCTAssertFalse(node.modifiesHomework)
            XCTAssertFalse(node.publishesTimeline)
            XCTAssertFalse(node.notifiesRelatives)
            XCTAssertFalse(node.storesRawMedia)
            XCTAssertFalse(node.unlocksDevice)
        }
        for control in report.creditControls {
            XCTAssertFalse(control.writesLedger)
            XCTAssertFalse(control.unlocksDevice)
        }
        XCTAssertFalse(report.publicSummary.writesLedger)
        XCTAssertFalse(report.publicSummary.publishesTimeline)
        XCTAssertFalse(report.publicSummary.notifiesRelatives)
    }

    // MARK: - CHAIN_OK / 摘要

    func testChainOkWhenNoBlocker() {
        let report = build([event(kind: .childSubmitted, role: .child)])
        XCTAssertTrue(report.findings.contains { $0.code == .chainOk })
    }

    func testNoChainOkWhenBlocker() {
        let report = build([event(hash: nil)])
        XCTAssertFalse(report.findings.contains { $0.code == .chainOk })
    }

    func testSummaryCounts() {
        let report = build([
            event(seed: "a", kind: .creditSuggested, role: .system, occurredAt: "2026-06-20T08:00:00Z",
                  creditSuggestionSeed: "c1", hash: "h1", teacherConclusion: .approved, guardianConclusion: .approved),
            event(seed: "b", kind: .appealOpened, role: .guardian, occurredAt: "2026-06-20T08:01:00Z",
                  appealSeed: "ap", hash: "h2", prevHash: "h1", creditAmount: 5)
        ])
        XCTAssertEqual(report.publicSummary.eventCount, 2)
        XCTAssertEqual(report.publicSummary.appealCount, 1)
        XCTAssertEqual(report.publicSummary.creditReleasedCount, 1)
        XCTAssertEqual(report.publicSummary.creditFrozenCount, 1)
    }

    // MARK: - 脱敏 + 确定性

    func testOutputIsRedacted() {
        let report = build([
            event(seed: "child-secret-001", proofSeed: "proof-leak-xyz"),
            event(seed: "ledger-leak-3", kind: .appealOpened, role: .guardian, occurredAt: "2026-06-20T08:01:00Z", appealSeed: "appeal-secret")
        ])
        var displayed = [report.caseTitle, report.caseSummary, report.childHeadline, report.parentHeadline]
        for node in report.nodes {
            displayed.append(contentsOf: [node.publicEventRef, node.prevPublicEventRef ?? "", node.childPublicRef,
                                          node.proofPublicRef ?? "", node.appealPublicRef ?? "", node.reason, node.nextStep])
        }
        let joined = displayed.joined(separator: " ")
        XCTAssertFalse(MobileSyncPayloadGuard.isUnsafe(displayed))
        for marker in ["child-secret", "proof-leak", "ledger-leak", "appeal-secret", "taskId", "claimId", "Bearer ", "192.168.", "family-", "homework-"] {
            XCTAssertFalse(joined.contains(marker), "不应泄露 \(marker)：\(joined)")
        }
        XCTAssertFalse(GrowthEvidenceTimelineEngine.reportLeaks(report))
    }

    func testRedactionFallbackBlocksColonStyleInternalRefs() {
        let input = GrowthEvidenceTimelineCaseInput(
            familySeed: familySeed, childSeed: childSeed, caseSeed: "case",
            events: [event(seed: "safe")]
        )
        let report = engine.build(input, caseTitle: "child:raw-secret", caseSummary: "family:raw-secret")
        XCTAssertEqual(report.nodes.count, 1)
        XCTAssertEqual(report.nodes[0].status, .blocked)
        XCTAssertTrue(report.findings.contains { $0.code == .publicSummaryLeak })
        XCTAssertFalse(GrowthEvidenceTimelineEngine.reportLeaks(report))
    }

    func testBuildIsDeterministic() {
        let events = [
            event(seed: "a", occurredAt: "2026-06-20T08:00:00Z", hash: "h1"),
            event(seed: "b", kind: .appealOpened, role: .guardian, occurredAt: "2026-06-20T08:01:00Z", appealSeed: "ap", hash: "h2", prevHash: "h1")
        ]
        XCTAssertEqual(build(events), build(events))
    }

    // MARK: - 装配器 + 集成

    func testAssemblerCoversAllEventKindsAndParentGroups() {
        let store = GrowthEvidenceTimelineStore()
        let report = store.refresh(family: LocalFamilyStore(), schoolFamily: SchoolFamilyStore(),
                                   runtime: GrowthEvidenceTimelineRuntimeContext(proposableCount: 2, totalSuggestedCredit: 18))

        XCTAssertFalse(report.isEmpty)

        // 覆盖全部九类事件。
        let kinds = Set(report.nodes.map { $0.kind })
        for kind in GrowthEvidenceTimelineEventKind.allCases {
            XCTAssertTrue(kinds.contains(kind), "应覆盖事件类型 \(kind.label)")
        }

        // 家长分组都应非空。
        XCTAssertFalse(report.conflictNodes.isEmpty, "应有冲突")
        XCTAssertFalse(report.appealNodes.isEmpty, "应有申诉")
        XCTAssertFalse(report.revocationNodes.isEmpty, "应有撤销")
        XCTAssertFalse(report.relativePendingNodes.isEmpty, "应有亲友待复核")
        XCTAssertFalse(report.blockedNodes.isEmpty, "应有已阻断")

        // 成长积分控制三态都应出现。
        XCTAssertGreaterThan(report.publicSummary.creditReleasedCount, 0)
        XCTAssertGreaterThan(report.publicSummary.creditFrozenCount, 0)
        XCTAssertGreaterThan(report.publicSummary.creditBlockedCount, 0)

        // 公开时间线只含未隐藏、非阻断节点。
        for item in report.publicTimeline {
            XCTAssertNotEqual(item.status, .blocked)
            XCTAssertNotEqual(item.status, .conflict)
        }

        XCTAssertFalse(GrowthEvidenceTimelineEngine.reportLeaks(report))
    }

    func testAssemblerFoldsSubmittedLocalDataAsChildSubmitted() {
        let family = LocalFamilyStore()
        let school = SchoolFamilyStore()
        let submitted = family.assignments.filter { $0.status == .submitted }.count
            + school.homeworks.filter { $0.status == .submitted }.count
        let report = GrowthEvidenceTimelineStore().refresh(family: family, schoolFamily: school)
        let folded = report.nodes.filter { $0.title.contains("待复核提交") }
        XCTAssertEqual(folded.count, submitted)
    }

    func testAssemblerIsDeterministic() {
        let family = LocalFamilyStore()
        let school = SchoolFamilyStore()
        let runtime = GrowthEvidenceTimelineRuntimeContext(proposableCount: 1, totalSuggestedCredit: 10)
        let r1 = GrowthEvidenceTimelineStore().refresh(family: family, schoolFamily: school, runtime: runtime)
        let r2 = GrowthEvidenceTimelineStore().refresh(family: family, schoolFamily: school, runtime: runtime)
        XCTAssertEqual(r1, r2)
    }

    func testEmptyReport() {
        XCTAssertTrue(GrowthEvidenceTimelineReport.empty.isEmpty)
        XCTAssertEqual(GrowthEvidenceTimelineReport.empty.childHeadline, "暂无成长证据节点")
        XCTAssertFalse(GrowthEvidenceTimelineReport.empty.hasAttention)
    }
}
