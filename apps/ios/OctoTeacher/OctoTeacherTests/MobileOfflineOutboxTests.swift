import XCTest
@testable import OctoTeacher

final class MobileOfflineOutboxTests: XCTestCase {

    private func childTaskRequest(
        summary: String = "阅读任务证明待同步",
        idempotencyKey: String = "idem-reading-1"
    ) -> MobileOfflineMutationRequest {
        MobileOfflineMutationRequest(
            kind: .childTaskSubmission,
            actorRole: .child,
            actorPublicRef: "actor-child-demo",
            subjectPublicRef: "subject-task-reading",
            summary: summary,
            idempotencyKey: idempotencyKey
        )
    }

    private func success(_ result: Result<MobileOfflineMutation, MobileOfflineError>) throws -> MobileOfflineMutation {
        switch result {
        case .success(let mutation):
            return mutation
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
            throw error
        }
    }

    private func failure(_ result: Result<MobileOfflineMutation, MobileOfflineError>) -> MobileOfflineError? {
        switch result {
        case .success:
            XCTFail("Expected failure")
            return nil
        case .failure(let error):
            return error
        }
    }

    func testEnqueueChildTaskSubmissionAsPendingLocalOnlyMutation() throws {
        let store = MobileOfflineOutboxStore()

        let mutation = try success(store.enqueue(childTaskRequest()))

        XCTAssertEqual(mutation.kind, .childTaskSubmission)
        XCTAssertEqual(mutation.status, .pending)
        XCTAssertTrue(mutation.requiresServerVerification)
        XCTAssertEqual(store.publicStatus.pendingCount, 1)
        XCTAssertEqual(store.publicStatus.conflictCount, 0)
    }

    func testIdempotentReplayReturnsExistingMutation() throws {
        let store = MobileOfflineOutboxStore()
        let first = try success(store.enqueue(childTaskRequest()))
        let replay = try success(store.enqueue(childTaskRequest()))

        XCTAssertEqual(replay.clientMutationRef, first.clientMutationRef)
        XCTAssertEqual(store.mutations.count, 1)
    }

    func testDuplicateReplayWithDifferentPayloadIsRejected() throws {
        let store = MobileOfflineOutboxStore()
        _ = try success(store.enqueue(childTaskRequest(summary: "第一次提交")))

        let error = failure(store.enqueue(childTaskRequest(summary: "第二次提交")))

        XCTAssertEqual(error, .duplicateReplay)
        XCTAssertEqual(store.mutations.count, 1)
    }

    func testExistingEnqueueResultFindsEquivalentMutationWithoutMutating() throws {
        let store = MobileOfflineOutboxStore()
        let first = try success(store.enqueue(childTaskRequest()))

        let existing = store.existingEnqueueResult(for: childTaskRequest())

        guard case .success(let replay)? = existing else {
            return XCTFail("应找到等价的已入队请求")
        }
        XCTAssertEqual(replay.clientMutationRef, first.clientMutationRef)
        XCTAssertEqual(store.mutations.count, 1)
    }

    func testExistingEnqueueResultPreservesConflictAndRollbackStateWithoutMutating() throws {
        let store = MobileOfflineOutboxStore()
        let conflict = try success(store.enqueue(childTaskRequest(idempotencyKey: "idem-conflict")))
        let rollback = try success(store.enqueue(childTaskRequest(idempotencyKey: "idem-rollback")))
        _ = store.markConflict(clientMutationRef: conflict.clientMutationRef, reason: .staleVersion)
        _ = store.rollback(clientMutationRef: rollback.clientMutationRef, reason: .supersededByGuardian)

        let existingConflict = store.existingEnqueueResult(
            for: childTaskRequest(idempotencyKey: "idem-conflict")
        )
        let existingRollback = store.existingEnqueueResult(
            for: childTaskRequest(idempotencyKey: "idem-rollback")
        )

        guard case .success(let conflictReplay)? = existingConflict,
              case .success(let rollbackReplay)? = existingRollback else {
            return XCTFail("应保留已存在 mutation 的运行态")
        }
        XCTAssertEqual(conflictReplay.status, .conflict)
        XCTAssertEqual(conflictReplay.conflictReason, .staleVersion)
        XCTAssertEqual(rollbackReplay.status, .rolledBack)
        XCTAssertEqual(rollbackReplay.conflictReason, .supersededByGuardian)
        XCTAssertEqual(store.mutations.count, 2)
    }

    func testTaskSubmissionOutboxAttentionCopyUsesNeutralFallbackWithoutReason() {
        let detail = TaskSubmissionOutboxAttentionCopy.detail(reason: nil)

        XCTAssertTrue(detail.contains("同步遇到小问题"))
        XCTAssertTrue(detail.contains("请让大人稍后检查同步状态"))
        XCTAssertTrue(detail.contains("任务证明本机仍保留"))
        XCTAssertTrue(detail.contains("大人确认前不会发放成长积分"))
        XCTAssertFalse(detail.contains(MobileOfflineConflictReason.alreadyResolved.hint))
        XCTAssertFalse(detail.contains(MobileOfflineConflictReason.alreadyResolved.nextStep))
    }

    func testTaskSubmissionOutboxAttentionCopyKeepsSpecificReasonWhenAvailable() {
        let reasons: [MobileOfflineConflictReason] = [
            .duplicateReplay,
            .staleVersion,
            .alreadyResolved,
            .supersededByGuardian
        ]

        for reason in reasons {
            let detail = TaskSubmissionOutboxAttentionCopy.detail(reason: reason)

            XCTAssertTrue(detail.contains(reason.hint), "Missing hint for \(reason)")
            XCTAssertTrue(detail.contains(reason.nextStep), "Missing next step for \(reason)")
            XCTAssertTrue(detail.contains("任务证明本机仍保留"), "Missing local proof promise for \(reason)")
            XCTAssertTrue(detail.contains("大人确认前不会发放成长积分"), "Missing credit gate for \(reason)")
        }
    }

    func testExistingEnqueueResultReportsDuplicateConflictWithoutMutating() throws {
        let store = MobileOfflineOutboxStore()
        _ = try success(store.enqueue(childTaskRequest(summary: "第一次提交")))

        let existing = store.existingEnqueueResult(for: childTaskRequest(summary: "第二次提交"))

        guard case .failure(let error)? = existing else {
            return XCTFail("应把同幂等键不同内容识别成重复冲突")
        }
        XCTAssertEqual(error, .duplicateReplay)
        XCTAssertEqual(store.mutations.count, 1)
    }

    func testExistingEnqueueResultReturnsNilWhenRequestWasNeverQueued() {
        let store = MobileOfflineOutboxStore()

        XCTAssertNil(store.existingEnqueueResult(for: childTaskRequest()))
        XCTAssertTrue(store.mutations.isEmpty)
    }

    func testChildCannotQueueApprovalAndRelativeCannotQueueRewardRequest() {
        let store = MobileOfflineOutboxStore()
        let childApproval = MobileOfflineMutationRequest(
            kind: .guardianApproval,
            actorRole: .child,
            actorPublicRef: "actor-child-demo",
            subjectPublicRef: "subject-proof-demo",
            summary: "孩子不能自批",
            idempotencyKey: "idem-child-approval"
        )
        let relativeReward = MobileOfflineMutationRequest(
            kind: .rewardRequest,
            actorRole: .relative,
            actorPublicRef: "actor-relative-demo",
            subjectPublicRef: "subject-reward-demo",
            summary: "亲友不能发起成长积分兑换请求",
            idempotencyKey: "idem-relative-reward"
        )

        XCTAssertEqual(failure(store.enqueue(childApproval)), .permissionDenied)
        XCTAssertEqual(failure(store.enqueue(relativeReward)), .permissionDenied)
    }

    func testForbiddenEffectsAndUnsafePayloadsAreRejected() {
        let store = MobileOfflineOutboxStore()
        var directCredit = childTaskRequest()
        directCredit.declaredEffect = .grantCredit
        var unsafe = childTaskRequest(idempotencyKey: "idem-unsafe")
        unsafe.summary = "Uploaded D:\\private\\proof.png with Bearer sk-local-secret from 192.168.1.253 and taskId"

        XCTAssertEqual(failure(store.enqueue(directCredit)), .forbiddenEffect)
        XCTAssertEqual(failure(store.enqueue(unsafe)), .unsafePayload)
    }

    func testConflictAndRollbackProduceRedactedPublicStatusAndHints() throws {
        let store = MobileOfflineOutboxStore()
        let pending = try success(store.enqueue(childTaskRequest(idempotencyKey: "idem-pending")))
        let rollback = try success(store.enqueue(childTaskRequest(summary: "需要回滚", idempotencyKey: "idem-rollback")))

        _ = store.markConflict(clientMutationRef: pending.clientMutationRef, reason: .staleVersion)
        _ = store.rollback(clientMutationRef: rollback.clientMutationRef, reason: .alreadyResolved)

        XCTAssertEqual(store.publicStatus.pendingCount, 0)
        XCTAssertEqual(store.publicStatus.conflictCount, 1)
        XCTAssertEqual(store.publicStatus.rolledBackCount, 1)
        XCTAssertTrue(store.publicStatus.hasAttention)
        XCTAssertEqual(store.conflictHints.count, 2)
        XCTAssertTrue(store.conflictHints.contains { $0.reason == .staleVersion && !$0.rolledBack })
        XCTAssertTrue(store.conflictHints.contains { $0.reason == .alreadyResolved && $0.rolledBack })

        let displayed = ([store.publicStatus.headline] + store.conflictHints.flatMap {
            [$0.clientMutationRef, $0.kindLabel, $0.actorLabel, $0.message, $0.nextStep]
        }).joined(separator: " ")
        XCTAssertFalse(MobileSyncPayloadGuard.isUnsafe(displayed))
        for marker in ["child:", "family:", "device:", "taskId", "claimId", "Bearer ", "192.168."] {
            XCTAssertFalse(displayed.contains(marker), "不应泄露 \(marker): \(displayed)")
        }
    }

    func testCleanOutboxHasSafeFallbackStatus() {
        let store = MobileOfflineOutboxStore()

        XCTAssertEqual(store.publicStatus, .clean)
        XCTAssertEqual(store.publicStatus.headline, "全部已同步")
        XCTAssertTrue(store.conflictHints.isEmpty)
    }

    func testDeviceReceiptIsLocalOnlyAndDoesNotRequireServerVerification() throws {
        let store = MobileOfflineOutboxStore()
        let receipt = MobileOfflineMutationRequest(
            kind: .deviceReceipt,
            actorRole: .device,
            actorPublicRef: "actor-device-demo",
            subjectPublicRef: "subject-device-command-demo",
            summary: "设备本地回执待同步",
            idempotencyKey: "idem-device-receipt"
        )

        let mutation = try success(store.enqueue(receipt))

        XCTAssertFalse(mutation.requiresServerVerification)
        XCTAssertEqual(mutation.status, .pending)
    }
}
