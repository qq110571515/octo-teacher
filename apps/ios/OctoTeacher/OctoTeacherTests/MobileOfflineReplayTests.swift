import XCTest
@testable import OctoTeacher

/// 离线队列「本地 mock 同步重放与冲突回填」层的确定性单元测试。
///
/// 覆盖四态（confirmed / needsGuardianReview / conflict / rolledBack）、家长闸门强制降级、
/// 冲突/回滚回填进 outbox、聚合报告、按类型过滤、脱敏与确定性。
final class MobileOfflineReplayTests: XCTestCase {

    private let engine = MobileOfflineReplayEngine()

    // MARK: - helpers

    /// 入队一条请求并返回已入队的 mutation（断言成功）。
    @discardableResult
    private func enqueue(
        _ store: MobileOfflineOutboxStore,
        kind: MobileOfflineMutationKind,
        actorRole: MobileOfflineActorRole,
        idempotencyKey: String,
        summary: String = "演示动作"
    ) throws -> MobileOfflineMutation {
        let request = MobileOfflineMutationRequest(
            kind: kind,
            actorRole: actorRole,
            actorPublicRef: "actor-\(actorRole.rawValue)-demo",
            subjectPublicRef: "subject-\(kind.rawValue)-demo",
            summary: summary,
            idempotencyKey: idempotencyKey
        )
        switch store.enqueue(request) {
        case .success(let mutation):
            return mutation
        case .failure(let error):
            XCTFail("入队应成功，得到 \(error)")
            throw error
        }
    }

    private func result(
        _ report: MobileOfflineReplayReport,
        for ref: String
    ) -> MobileOfflineReplayResult? {
        report.results.first { $0.clientMutationRef == ref }
    }

    // MARK: - confirmed

    func testSubmissionsAndDeviceReceiptDefaultToConfirmed() throws {
        let store = MobileOfflineOutboxStore()
        let task = try enqueue(store, kind: .childTaskSubmission, actorRole: .child, idempotencyKey: "k-task")
        let homework = try enqueue(store, kind: .schoolHomeworkSubmission, actorRole: .child, idempotencyKey: "k-hw")
        let receipt = try enqueue(store, kind: .deviceReceipt, actorRole: .device, idempotencyKey: "k-receipt")

        let report = engine.replay(mutations: store.mutations)

        XCTAssertEqual(result(report, for: task.clientMutationRef)?.status, .confirmed)
        XCTAssertEqual(result(report, for: homework.clientMutationRef)?.status, .confirmed)
        XCTAssertEqual(result(report, for: receipt.clientMutationRef)?.status, .confirmed)
        // 设备回执文案明确「不代表真实解锁」。
        XCTAssertTrue(result(report, for: receipt.clientMutationRef)?.message.contains("不代表真实解锁") ?? false)
    }

    func testConfirmedDoesNotFinalizeOutboxState() throws {
        // 关键安全断言：confirmed 只是「收到」，绝不在 outbox 把动作落定为任何终态。
        let store = MobileOfflineOutboxStore()
        let task = try enqueue(store, kind: .childTaskSubmission, actorRole: .child, idempotencyKey: "k-task")
        let replayStore = MobileOfflineReplayStore()

        let report = replayStore.replay(outbox: store)

        XCTAssertEqual(result(report, for: task.clientMutationRef)?.status, .confirmed)
        // outbox 仍停在 pending（没有 confirmed/verified 这种落定态）。
        XCTAssertEqual(store.mutations.first?.status, .pending)
        XCTAssertEqual(store.publicStatus.pendingCount, 1)
    }

    // MARK: - 家长闸门强制降级

    func testGuardianGatedKindsAlwaysNeedReviewEvenWhenServerConfirms() throws {
        let store = MobileOfflineOutboxStore()
        let approval = try enqueue(store, kind: .guardianApproval, actorRole: .guardian, idempotencyKey: "k-approval")
        let comment = try enqueue(store, kind: .relativeComment, actorRole: .relative, idempotencyKey: "k-comment")
        let reward = try enqueue(store, kind: .rewardRequest, actorRole: .child, idempotencyKey: "k-reward")

        // 即便 mock 服务端账本对这三条都裁决 confirm，引擎也强制降级为 needsGuardianReview。
        let directive = MobileOfflineReplayDirective(verdicts: [
            "k-approval": .confirm,
            "k-comment": .confirm,
            "k-reward": .confirm
        ])
        let report = engine.replay(mutations: store.mutations, directive: directive)

        XCTAssertEqual(result(report, for: approval.clientMutationRef)?.status, .needsGuardianReview)
        XCTAssertEqual(result(report, for: comment.clientMutationRef)?.status, .needsGuardianReview)
        XCTAssertEqual(result(report, for: reward.clientMutationRef)?.status, .needsGuardianReview)
        // 成长积分兑换请求文案明确不解锁、不扣成长积分。
        let rewardMessage = result(report, for: reward.clientMutationRef)?.message ?? ""
        XCTAssertTrue(rewardMessage.contains("不解锁"))
        XCTAssertTrue(rewardMessage.contains("不扣成长积分"))
    }

    // MARK: - 冲突 / 回滚 + 回填

    func testConflictVerdictBackfillsOutboxAsConflict() throws {
        let store = MobileOfflineOutboxStore()
        let task = try enqueue(store, kind: .childTaskSubmission, actorRole: .child, idempotencyKey: "k-task")
        let replayStore = MobileOfflineReplayStore()

        let directive = MobileOfflineReplayDirective(verdicts: ["k-task": .conflict(.staleVersion)])
        let report = replayStore.replay(outbox: store, directive: directive)

        let r = result(report, for: task.clientMutationRef)
        XCTAssertEqual(r?.status, .conflict)
        XCTAssertEqual(r?.conflictReason, .staleVersion)
        // 回填进 outbox。
        XCTAssertEqual(store.mutations.first?.status, .conflict)
        XCTAssertEqual(store.publicStatus.conflictCount, 1)
    }

    func testRollbackVerdictBackfillsOutboxAsRolledBack() throws {
        let store = MobileOfflineOutboxStore()
        let task = try enqueue(store, kind: .childTaskSubmission, actorRole: .child, idempotencyKey: "k-task")
        let replayStore = MobileOfflineReplayStore()

        let directive = MobileOfflineReplayDirective(verdicts: ["k-task": .rollback(.supersededByGuardian)])
        let report = replayStore.replay(outbox: store, directive: directive)

        let r = result(report, for: task.clientMutationRef)
        XCTAssertEqual(r?.status, .rolledBack)
        XCTAssertEqual(r?.conflictReason, .supersededByGuardian)
        XCTAssertEqual(store.mutations.first?.status, .rolledBack)
        XCTAssertEqual(store.publicStatus.rolledBackCount, 1)
    }

    func testExistingOutboxConflictAndRollbackAreCarriedThrough() throws {
        let store = MobileOfflineOutboxStore()
        let conflicting = try enqueue(store, kind: .childTaskSubmission, actorRole: .child, idempotencyKey: "k-c")
        let rolled = try enqueue(store, kind: .schoolHomeworkSubmission, actorRole: .child, idempotencyKey: "k-r")
        _ = store.markConflict(clientMutationRef: conflicting.clientMutationRef, reason: .alreadyResolved)
        _ = store.rollback(clientMutationRef: rolled.clientMutationRef, reason: .supersededByGuardian)

        let report = engine.replay(mutations: store.mutations)

        XCTAssertEqual(result(report, for: conflicting.clientMutationRef)?.status, .conflict)
        XCTAssertEqual(result(report, for: rolled.clientMutationRef)?.status, .rolledBack)
    }

    // MARK: - 报告聚合 + 过滤

    func testReportAggregatesAllFourStates() throws {
        let store = MobileOfflineOutboxStore()
        try enqueue(store, kind: .childTaskSubmission, actorRole: .child, idempotencyKey: "k1")     // confirmed
        try enqueue(store, kind: .rewardRequest, actorRole: .child, idempotencyKey: "k2")           // needsReview
        try enqueue(store, kind: .schoolHomeworkSubmission, actorRole: .child, idempotencyKey: "k3") // conflict
        try enqueue(store, kind: .deviceReceipt, actorRole: .device, idempotencyKey: "k4")          // rolledBack

        let directive = MobileOfflineReplayDirective(verdicts: [
            "k3": .conflict(.duplicateReplay),
            "k4": .rollback(.alreadyResolved)
        ])
        let report = engine.replay(mutations: store.mutations, directive: directive)

        XCTAssertEqual(report.confirmedCount, 1)
        XCTAssertEqual(report.needsReviewCount, 1)
        XCTAssertEqual(report.conflictCount, 1)
        XCTAssertEqual(report.rolledBackCount, 1)
        XCTAssertTrue(report.hasAttention)
        XCTAssertFalse(report.isEmpty)
    }

    func testEmptyReportHeadlineAndFilter() {
        let report = MobileOfflineReplayReport.empty
        XCTAssertTrue(report.isEmpty)
        XCTAssertEqual(report.headline, "还没有可重放的离线动作")
        XCTAssertFalse(report.hasAttention)
    }

    func testResultsFilteringByKind() throws {
        let store = MobileOfflineOutboxStore()
        try enqueue(store, kind: .childTaskSubmission, actorRole: .child, idempotencyKey: "k1")
        try enqueue(store, kind: .relativeComment, actorRole: .relative, idempotencyKey: "k2")

        let report = engine.replay(mutations: store.mutations)

        let onlyComments = report.results(for: [.relativeComment])
        XCTAssertEqual(onlyComments.count, 1)
        XCTAssertEqual(onlyComments.first?.kind, .relativeComment)
        XCTAssertEqual(onlyComments.first?.status, .needsGuardianReview)
    }

    // MARK: - 脱敏 + 确定性

    func testReplayDisplayTextIsRedacted() throws {
        let store = MobileOfflineOutboxStore()
        try enqueue(store, kind: .childTaskSubmission, actorRole: .child, idempotencyKey: "k1")
        try enqueue(store, kind: .rewardRequest, actorRole: .child, idempotencyKey: "k2")
        try enqueue(store, kind: .schoolHomeworkSubmission, actorRole: .child, idempotencyKey: "k3")

        let directive = MobileOfflineReplayDirective(verdicts: ["k3": .conflict(.staleVersion)])
        let report = engine.replay(mutations: store.mutations, directive: directive)

        let displayed = ([report.headline] + report.results.flatMap {
            [$0.clientMutationRef, $0.kindLabel, $0.actorLabel, $0.message, $0.nextStep, $0.status.label]
        }).joined(separator: " ")

        XCTAssertFalse(MobileSyncPayloadGuard.isUnsafe(displayed))
        for marker in ["child:", "family:", "school:", "teacher:", "device:", "taskId", "claimId", "Bearer ", "192.168."] {
            XCTAssertFalse(displayed.contains(marker), "不应泄露 \(marker): \(displayed)")
        }
    }

    func testReplayIsDeterministic() throws {
        let directive = MobileOfflineReplayDirective(verdicts: ["k2": .conflict(.staleVersion)])

        func runOnce() -> MobileOfflineReplayReport {
            let store = MobileOfflineOutboxStore()
            _ = try? enqueue(store, kind: .childTaskSubmission, actorRole: .child, idempotencyKey: "k1")
            _ = try? enqueue(store, kind: .schoolHomeworkSubmission, actorRole: .child, idempotencyKey: "k2")
            return engine.replay(mutations: store.mutations, directive: directive)
        }

        XCTAssertEqual(runOnce(), runOnce())
    }
}
