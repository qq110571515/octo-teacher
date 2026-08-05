import XCTest
@testable import OctoTeacher

/// 家庭荣誉墙 / 成长故事线同意入口测试。
///
/// 覆盖 B48 iOS 入口边界：三层可见性、家长同意门禁、撤回传播、公开脱敏、
/// 亲友只读，以及快照无发布、无通知、无上传、无成长积分、无 AI/网络副作用。
final class FamilyHonorStorylineConsentTests: XCTestCase {

    private func store() -> FamilyGrowthAchievementStore {
        FamilyGrowthAchievementStore()
    }

    private func builder() -> FamilyHonorStorylineConsentBuilder {
        FamilyHonorStorylineConsentBuilder(store: store())
    }

    private func card(
        seed: String,
        kind: FamilyGrowthCardKind = .honorWall,
        visibility: FamilyGrowthCardVisibility,
        lifecycle: FamilyGrowthLifecycle,
        allowsRelative: Bool = false
    ) -> FamilyGrowthCard {
        FamilyGrowthCard(
            id: UUID(),
            internalSeed: seed,
            kind: kind,
            title: "测试荣誉",
            summary: "这是一条已脱敏的测试摘要。",
            occurredLabel: "本周",
            visibility: visibility,
            lifecycle: lifecycle,
            supportiveCopy: "保持自己的节奏就很好。",
            nextStep: "由家长确认下一步。",
            tags: ["测试", "成长"],
            allowsRelative: allowsRelative,
            reactionCount: 8,
            approvedCommentCount: 3,
            ratings: nil
        )
    }

    func testGuardianSeesAllLayersAndConsentControls() {
        let snapshot = builder().snapshot(for: .guardian)

        XCTAssertEqual(snapshot.role, .guardian)
        XCTAssertEqual(snapshot.nodes.count, store().cards.count)
        XCTAssertTrue(snapshot.nodes.contains { $0.layer == .privateFamily })
        XCTAssertTrue(snapshot.nodes.contains { $0.layer == .relativeVisible })
        XCTAssertTrue(snapshot.nodes.contains { $0.layer == .publicRedacted })
        XCTAssertTrue(snapshot.nodes.allSatisfy(\.showsConsentControls))
        XCTAssertTrue(snapshot.findings.contains { $0.code == .guardianConsentRequired && $0.actionRequired })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .withdrawalPropagated })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .frozenOrBlockedHidden && $0.actionRequired })
    }

    func testRelativeCannotSeePrivatePendingWithdrawnOrBlocked() {
        let snapshot = builder().snapshot(for: .relative)

        XCTAssertFalse(snapshot.nodes.isEmpty)
        XCTAssertTrue(snapshot.nodes.allSatisfy { $0.lifecycle == .published })
        XCTAssertTrue(snapshot.nodes.allSatisfy { $0.layer == .relativeVisible })
        XCTAssertTrue(snapshot.nodes.allSatisfy { $0.consentState == .ready })
        XCTAssertTrue(snapshot.nodes.allSatisfy { !$0.showsConsentControls })
        XCTAssertTrue(snapshot.nodes.allSatisfy { !$0.showsWithdrawalReason })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .relativeBoundaryApplied })
    }

    func testPublicViewerOnlySeesPublicRedactedPublishedNodes() {
        let customStore = FamilyGrowthAchievementStore(cards: [
            card(seed: "explicit-public", visibility: .publicShare, lifecycle: .published),
            card(seed: "explicit-private", visibility: .privateOnly, lifecycle: .published),
            card(seed: "explicit-public-pending", visibility: .publicShare, lifecycle: .pending),
            card(seed: "explicit-relative", visibility: .relatives, lifecycle: .published, allowsRelative: true)
        ])
        let snapshot = FamilyHonorStorylineConsentBuilder(store: customStore).snapshot(for: .publicViewer)

        XCTAssertEqual(snapshot.nodes.count, 1)
        for node in snapshot.nodes {
            XCTAssertEqual(node.layer, .publicRedacted)
            XCTAssertEqual(node.lifecycle, .published)
            XCTAssertEqual(node.consentState, .ready)
            XCTAssertTrue(node.summary.contains("公开脱敏摘要"))
            XCTAssertEqual(node.reactionCount, 0)
            XCTAssertEqual(node.approvedCommentCount, 0)
            XCTAssertFalse(node.showsConsentControls)
            XCTAssertFalse(node.showsWithdrawalReason)
        }
        XCTAssertTrue(snapshot.findings.contains { $0.code == .publicRedactionApplied })
    }

    func testPendingWithdrawnBlockedProduceFindingsAndNoSideEffects() {
        let snapshot = builder().snapshot(for: .guardian)
        let summary = snapshot.publicSummary
        let releaseGate = snapshot.releaseGate

        XCTAssertTrue(snapshot.nodes.contains { $0.consentState == .needsGuardianConsent })
        XCTAssertTrue(snapshot.nodes.contains { $0.consentState == .withdrawn })
        XCTAssertTrue(snapshot.nodes.contains { $0.consentState == .blocked })
        XCTAssertEqual(releaseGate.status, .blocked)
        XCTAssertEqual(releaseGate.primaryReason, .sourceEntry)
        XCTAssertEqual(releaseGate.publishCandidateCount, 0)
        XCTAssertEqual(releaseGate.evidenceChecklist.count, 4)
        XCTAssertTrue(releaseGate.evidenceChecklist.contains { $0.title == "阻断来源" && $0.status == .blocked })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .guardianConsentRequired })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .withdrawalPropagated })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .frozenOrBlockedHidden })
        XCTAssertFalse(summary.publishesHonorWall)
        XCTAssertFalse(summary.mutatesStoryline)
        XCTAssertFalse(summary.grantsBadge)
        XCTAssertFalse(summary.writesLedger)
        XCTAssertFalse(summary.unlocksDevice)
        XCTAssertFalse(summary.uploadsMedia)
        XCTAssertFalse(summary.sendsNotification)
        XCTAssertFalse(summary.callsNetwork)
        XCTAssertFalse(summary.callsAIProvider)
        XCTAssertFalse(releaseGate.writesStoryline)
        XCTAssertFalse(releaseGate.publishesHonorWall)
        XCTAssertFalse(releaseGate.notifiesRelatives)
        XCTAssertFalse(releaseGate.grantsCredit)
        XCTAssertFalse(releaseGate.awardsBadges)
        XCTAssertFalse(releaseGate.unlocksDevice)
        XCTAssertFalse(releaseGate.callsNetwork)
        XCTAssertFalse(releaseGate.callsAIProvider)
    }

    func testReleaseGateReadyWhenAllVisibleSourcesArePublishedAndConsented() {
        let customStore = FamilyGrowthAchievementStore(cards: [
            card(seed: "ready-family", visibility: .family, lifecycle: .published),
            card(seed: "ready-relative", visibility: .relatives, lifecycle: .published, allowsRelative: true),
            card(seed: "ready-public", visibility: .publicShare, lifecycle: .published)
        ])

        let guardian = FamilyHonorStorylineConsentBuilder(store: customStore).snapshot(for: .guardian)
        let relative = FamilyHonorStorylineConsentBuilder(store: customStore).snapshot(for: .relative)

        XCTAssertEqual(guardian.releaseGate.status, .ready)
        XCTAssertEqual(guardian.releaseGate.primaryReason, .sourceEntry)
        XCTAssertEqual(guardian.releaseGate.readySourceCount, 3)
        XCTAssertEqual(guardian.releaseGate.publishCandidateCount, 3)
        XCTAssertEqual(guardian.releaseGate.manualGateCount, 0)
        XCTAssertEqual(guardian.releaseGate.blockedCount, 0)
        XCTAssertEqual(guardian.releaseGate.evidenceChecklist.count, 4)
        XCTAssertTrue(guardian.releaseGate.evidenceChecklist.contains { $0.title == "已同意来源" && $0.status == .ready })
        XCTAssertTrue(guardian.releaseGate.evidenceChecklist.allSatisfy { $0.publicEvidenceRef.hasPrefix("story-proof:") })
        XCTAssertTrue(guardian.releaseGate.nextAction.contains("不发布"))

        XCTAssertEqual(relative.releaseGate.status, .ready)
        XCTAssertEqual(relative.releaseGate.publishCandidateCount, relative.nodes.count)
        XCTAssertTrue(relative.nodes.allSatisfy { $0.lifecycle == .published })
    }

    func testReleaseGateManualGateForPendingOrWithdrawnSources() {
        let pendingStore = FamilyGrowthAchievementStore(cards: [
            card(seed: "ready-one", visibility: .family, lifecycle: .published),
            card(seed: "pending-one", visibility: .family, lifecycle: .pending)
        ])
        let withdrawnStore = FamilyGrowthAchievementStore(cards: [
            card(seed: "ready-one", visibility: .family, lifecycle: .published),
            card(seed: "withdrawn-one", visibility: .family, lifecycle: .withdrawn)
        ])

        let pending = FamilyHonorStorylineConsentBuilder(store: pendingStore).snapshot(for: .guardian)
        let withdrawn = FamilyHonorStorylineConsentBuilder(store: withdrawnStore).snapshot(for: .guardian)

        XCTAssertEqual(pending.releaseGate.status, .manualGate)
        XCTAssertEqual(pending.releaseGate.primaryReason, .guardianConsent)
        XCTAssertEqual(pending.releaseGate.publishCandidateCount, 1)
        XCTAssertTrue(pending.releaseGate.evidenceChecklist.contains { $0.title == "家长同意" && $0.status == .manualGate })
        XCTAssertTrue(pending.releaseGate.nextAction.contains("同意范围"))

        XCTAssertEqual(withdrawn.releaseGate.status, .manualGate)
        XCTAssertEqual(withdrawn.releaseGate.primaryReason, .revocationPropagation)
        XCTAssertEqual(withdrawn.releaseGate.publishCandidateCount, 1)
        XCTAssertTrue(withdrawn.releaseGate.evidenceChecklist.contains { $0.title == "撤回传播" && $0.status == .manualGate })
        XCTAssertTrue(withdrawn.releaseGate.childCopy.contains("保护你的选择"))
    }

    func testPublicRefsAreStableAndDoNotLeakInternalSeeds() {
        let first = builder().snapshot(for: .guardian)
        let second = builder().snapshot(for: .guardian)
        let serialized = [
            first.familyPublicRef,
            first.childPublicRef,
            first.nodes.map(\.publicNodeRef).joined(separator: " "),
            first.nodes.map(\.sourceCardPublicRef).joined(separator: " "),
            first.nodes.map(\.title).joined(separator: " "),
            first.nodes.map(\.summary).joined(separator: " "),
            first.releaseGate.title,
            first.releaseGate.guardianSummary,
            first.releaseGate.childCopy,
            first.releaseGate.nextAction,
            first.releaseGate.evidenceChecklist.map(\.publicEvidenceRef).joined(separator: " "),
            first.releaseGate.evidenceChecklist.map(\.title).joined(separator: " "),
            first.releaseGate.evidenceChecklist.map(\.summary).joined(separator: " "),
            first.findings.map(\.publicFindingRef).joined(separator: " ")
        ].joined(separator: " ")

        XCTAssertEqual(first.familyPublicRef, second.familyPublicRef)
        XCTAssertEqual(first.childPublicRef, second.childPublicRef)
        XCTAssertEqual(first.nodes.map(\.publicNodeRef), second.nodes.map(\.publicNodeRef))
        XCTAssertTrue(first.familyPublicRef.hasPrefix("family:"))
        XCTAssertTrue(first.childPublicRef.hasPrefix("child:"))

        for raw in [
            "storyline-month",
            "honor-reading-star",
            "honor-helper-pending",
            "journal-withdrawn",
            "journal-blocked",
            "honor-public-share"
        ] {
            XCTAssertFalse(serialized.contains(raw), "同意入口不得暴露 internalSeed：\(raw)")
        }
    }

    func testSnapshotDisplayPayloadPassesMobileSyncGuard() {
        for role in FamilyHonorStorylineConsentViewerRole.allCases {
            let snapshot = builder().snapshot(for: role)
            XCTAssertFalse(snapshot.hasUnsafeDisplayPayload, "\(role.label) 视角不得展示不安全负载")
        }
    }

    func testChildViewUsesFriendlyCopyAndNoAdultControls() {
        let snapshot = builder().snapshot(for: .child)

        XCTAssertEqual(snapshot.nodes.count, store().cards.count)
        XCTAssertTrue(snapshot.nodes.allSatisfy { !$0.showsConsentControls })
        XCTAssertTrue(snapshot.nodes.allSatisfy { !$0.showsWithdrawalReason })
        XCTAssertTrue(snapshot.findings.contains { $0.code == .childFriendlyCopyApplied })
        XCTAssertFalse(snapshot.findings.contains { $0.actionRequired })

        guard let blocked = snapshot.nodes.first(where: { $0.consentState == .blocked }) else {
            return XCTFail("应存在孩子可见的阻断保护说明")
        }
        XCTAssertTrue(blocked.summary.contains("保护"))
    }
}
