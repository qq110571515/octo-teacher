import XCTest
@testable import OctoTeacher

/// 覆盖 `MobileOfflineActionComposer`：六类入口的 kind/role 正确、脱敏、幂等、越权与反馈映射。
final class MobileOfflineActionComposerTests: XCTestCase {

    private let composer = MobileOfflineActionComposer(enqueuedAt: "2026-06-23T21:00:00Z")
    /// 一个像内部 ID 的 seed，用来断言它绝不出现在脱敏后的引用里。
    private let secretSeed = "11111111-2222-3333-4444-555555555555"

    private func enqueued(_ request: MobileOfflineMutationRequest) throws -> MobileOfflineMutation {
        let store = MobileOfflineOutboxStore()
        switch store.enqueue(request) {
        case .success(let mutation):
            return mutation
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
            throw error
        }
    }

    // MARK: - 六类入口的 kind / role / 状态

    func testChildTaskSubmissionMapsToPendingChildMutation() throws {
        let mutation = try enqueued(composer.childTaskSubmission(taskSeed: secretSeed, proofKindLabel: "文字证明"))
        XCTAssertEqual(mutation.kind, .childTaskSubmission)
        XCTAssertEqual(mutation.actorRole, .child)
        XCTAssertEqual(mutation.status, .pending)
        XCTAssertTrue(mutation.requiresServerVerification)
    }

    func testSchoolHomeworkSubmissionMapsToPendingChildMutation() throws {
        let mutation = try enqueued(composer.schoolHomeworkSubmission(homeworkSeed: secretSeed, subjectLabel: "语文"))
        XCTAssertEqual(mutation.kind, .schoolHomeworkSubmission)
        XCTAssertEqual(mutation.actorRole, .child)
        XCTAssertEqual(mutation.status, .pending)
        XCTAssertTrue(mutation.requiresServerVerification)
    }

    func testGuardianApprovalDraftStaysPendingAndNeverFinalizes() throws {
        let approve = try enqueued(composer.guardianApprovalDraft(submissionSeed: secretSeed, decision: .approve))
        XCTAssertEqual(approve.kind, .guardianApproval)
        XCTAssertEqual(approve.actorRole, .guardian)
        // 草稿只能停在 pending，绝不会变成「已落定」终态。
        XCTAssertEqual(approve.status, .pending)
        XCTAssertTrue(approve.requiresServerVerification)
    }

    func testRelativeCommentMapsToPendingRelativeMutation() throws {
        let mutation = try enqueued(composer.relativeComment(targetSeed: "family-feed", relativeSeed: "relative-self", message: "你今天很棒"))
        XCTAssertEqual(mutation.kind, .relativeComment)
        XCTAssertEqual(mutation.actorRole, .relative)
        XCTAssertEqual(mutation.status, .pending)
        XCTAssertTrue(mutation.requiresServerVerification)
    }

    func testRewardRequestMapsToPendingChildMutation() throws {
        let mutation = try enqueued(composer.rewardRequest(childSeed: secretSeed, minutes: 30))
        XCTAssertEqual(mutation.kind, .rewardRequest)
        XCTAssertEqual(mutation.actorRole, .child)
        XCTAssertEqual(mutation.status, .pending)
        XCTAssertTrue(mutation.requiresServerVerification)
    }

    func testDeviceReceiptIsLocalOnlyAndDoesNotRequireServerVerification() throws {
        let mutation = try enqueued(composer.deviceReceipt(commandSeed: secretSeed, grantedMinutes: 15))
        XCTAssertEqual(mutation.kind, .deviceReceipt)
        XCTAssertEqual(mutation.actorRole, .device)
        XCTAssertEqual(mutation.status, .pending)
        XCTAssertFalse(mutation.requiresServerVerification)
    }

    // MARK: - 脱敏

    func testComposedRefsRedactRawSeedsAndAreSafe() throws {
        let requests = [
            composer.childTaskSubmission(taskSeed: secretSeed, proofKindLabel: "图片占位"),
            composer.schoolHomeworkSubmission(homeworkSeed: secretSeed, subjectLabel: "数学"),
            composer.guardianApprovalDraft(submissionSeed: secretSeed, decision: .reject),
            composer.rewardRequest(childSeed: secretSeed, minutes: 15),
            composer.deviceReceipt(commandSeed: secretSeed, grantedMinutes: 15)
        ]
        for request in requests {
            let mutation = try enqueued(request)
            let refs = [mutation.actorPublicRef, mutation.subjectPublicRef, mutation.idempotencyKey]
            for ref in refs {
                XCTAssertFalse(ref.contains(secretSeed), "脱敏引用不应包含原始 seed：\(ref)")
                XCTAssertFalse(ref.isEmpty)
            }
            // 公开引用与摘要整体不得命中脱敏守卫，也不得出现敏感标记。
            let displayed = (refs + [mutation.summaryPreview]).joined(separator: " ")
            XCTAssertFalse(MobileSyncPayloadGuard.isUnsafe(displayed))
            for marker in ["taskId", "claimId", "Bearer ", "192.168."] {
                XCTAssertFalse(displayed.contains(marker), "不应泄露 \(marker)：\(displayed)")
            }
        }
    }

    // MARK: - 幂等

    func testSameLogicalActionReplaysIntoSameMutation() throws {
        let store = MobileOfflineOutboxStore()
        let first = store.enqueue(composer.childTaskSubmission(taskSeed: secretSeed, proofKindLabel: "文字证明"))
        let replay = store.enqueue(composer.childTaskSubmission(taskSeed: secretSeed, proofKindLabel: "文字证明"))

        guard case .success(let a) = first, case .success(let b) = replay else {
            return XCTFail("两次入队都应成功")
        }
        XCTAssertEqual(a.clientMutationRef, b.clientMutationRef)
        XCTAssertEqual(store.mutations.count, 1)
    }

    func testApproveAndRejectDraftsAreDistinctIdempotentEntries() throws {
        let store = MobileOfflineOutboxStore()
        _ = store.enqueue(composer.guardianApprovalDraft(submissionSeed: secretSeed, decision: .approve))
        _ = store.enqueue(composer.guardianApprovalDraft(submissionSeed: secretSeed, decision: .reject))
        // 同一提交的「建议通过」「建议驳回」是两个独立逻辑动作。
        XCTAssertEqual(store.mutations.count, 2)
        XCTAssertEqual(store.publicStatus.pendingCount, 2)
    }

    // MARK: - 越权与不安全负载仍被 outbox 拦截

    func testUnsafeRelativeMessageIsRejected() {
        let store = MobileOfflineOutboxStore()
        let request = composer.relativeComment(
            targetSeed: "family-feed",
            relativeSeed: "relative-self",
            message: "看这里 192.168.1.253 的私密链接"
        )
        guard case .failure(let error) = store.enqueue(request) else {
            return XCTFail("不安全留言应被拒绝")
        }
        XCTAssertEqual(error, .unsafePayload)
    }

    // MARK: - 入队反馈映射

    func testEnqueueFeedbackMapsSuccessAndFailure() {
        let store = MobileOfflineOutboxStore()
        let success = store.enqueue(composer.rewardRequest(childSeed: secretSeed, minutes: 15))
        XCTAssertEqual(
            MobileOfflineEnqueueFeedback.message(for: success, successText: "已加入离线队列"),
            "已加入离线队列"
        )

        let unsafe = store.enqueue(composer.relativeComment(
            targetSeed: "family-feed",
            relativeSeed: "relative-self",
            message: "Bearer sk-local-secret-token"
        ))
        XCTAssertEqual(
            MobileOfflineEnqueueFeedback.message(for: unsafe, successText: "不应出现"),
            MobileOfflineError.unsafePayload.localizedHint
        )
    }
}
