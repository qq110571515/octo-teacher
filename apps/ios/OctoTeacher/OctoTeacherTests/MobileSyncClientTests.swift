import XCTest
@testable import OctoTeacher

/// 移动同步客户端消费壳测试。
///
/// 覆盖：snapshot 解析、脱敏负载、跨孩子权限拒绝、孩子越权审批、老师不可提交、
/// 重复提交、重复批准、成长积分不足、奖励会话运行态与开启，以及成长动态可见性过滤。
final class MobileSyncClientTests: XCTestCase {
    private let familyRef = "family:fam7a1c2"
    private let childARef = "child:c0a1b2c"
    private let childBRef = "child:c9z8y7x"

    private func makeClient() throws -> MobileSyncClient {
        try MobileSyncClient.makeMock()
    }

    private func guardianSession(authorized: [String] = []) -> MobileSyncSession {
        MobileSyncSession(
            actorPublicRef: "guardian:g100001",
            actorRole: .guardian,
            familyPublicRef: familyRef,
            authorizedChildPublicRefs: authorized
        )
    }

    private func childSession(_ childRef: String) -> MobileSyncSession {
        MobileSyncSession(
            actorPublicRef: childRef,
            actorRole: .child,
            familyPublicRef: familyRef,
            childPublicRef: childRef
        )
    }

    private func teacherSession(authorized: [String] = []) -> MobileSyncSession {
        MobileSyncSession(
            actorPublicRef: "teacher:t100001",
            actorRole: .teacher,
            familyPublicRef: familyRef,
            authorizedChildPublicRefs: authorized
        )
    }

    // MARK: - 解析

    /// 内置 mock snapshot 能被解析，且关键集合数量正确。
    func testMockSnapshotParses() throws {
        let snapshot = try MobileSyncSnapshot.mock()

        XCTAssertEqual(snapshot.schemaVersion, MobileSyncSnapshot.supportedSchemaVersion)
        XCTAssertEqual(snapshot.family.publicRef, familyRef)
        XCTAssertEqual(snapshot.children.count, 2)
        XCTAssertEqual(snapshot.tasks.count, 7)
        XCTAssertEqual(snapshot.submissions.count, 2)
        XCTAssertEqual(snapshot.rewardSessions.count, 2)
        XCTAssertEqual(snapshot.growthFeed.count, 3)
        XCTAssertEqual(snapshot.capabilities.count, 6)
    }

    /// 非法 JSON 解析为 contractInvalid。
    func testInvalidJSONThrowsContractInvalid() {
        let bad = Data("{ not valid json".utf8)
        XCTAssertThrowsError(try MobileSyncSnapshot.decode(from: bad)) { error in
            XCTAssertEqual(error as? MobileSyncError, .contractInvalid)
        }
    }

    /// snapshot 内所有公开引用都不含 token、路径或局域网地址（脱敏自检）。
    func testMockSnapshotContainsNoUnsafePayload() throws {
        let json = MobileSyncSnapshot.mockJSON
        XCTAssertFalse(MobileSyncPayloadGuard.isUnsafe(json), "mock snapshot 不应包含不安全负载")
    }

    // MARK: - 今日任务

    /// 孩子只看到自己当天的任务（昨天/别人任务被过滤）。
    func testTodayTasksReturnsOnlyOwnDatedTasks() throws {
        let client = try makeClient()
        let result = client.todayTasks(session: childSession(childARef), childPublicRef: childARef)

        guard case .success(let tasks) = result else { return XCTFail("应成功返回任务") }
        XCTAssertTrue(tasks.allSatisfy { $0.childPublicRef == childARef })
        XCTAssertTrue(tasks.allSatisfy { $0.plannedFor == "2026-06-23" })
        // 昨天的 task:t100004 不应出现。
        XCTAssertFalse(tasks.contains { $0.clientTaskRef == "task:t100004" })
    }

    /// 默认日期来自 snapshot.generatedAt，而不是写死某一天。
    func testTodayTasksDefaultDateComesFromSnapshotGeneratedAt() throws {
        var snapshot = try MobileSyncSnapshot.mock()
        snapshot.generatedAt = "2026-06-22T09:00:00Z"
        let client = MobileSyncClient(snapshot: snapshot)
        let result = client.todayTasks(session: childSession(childARef), childPublicRef: childARef)

        guard case .success(let tasks) = result else { return XCTFail("应成功返回任务") }
        XCTAssertEqual(tasks.map(\.clientTaskRef), ["task:t100004"])
    }

    // MARK: - 权限拒绝

    /// 孩子 A 不能读取孩子 B 的任务。
    func testChildCannotAccessOtherChildTasks() throws {
        let client = try makeClient()
        let result = client.todayTasks(session: childSession(childARef), childPublicRef: childBRef)
        XCTAssertEqual(result.failureError, .permissionDenied)
    }

    /// 家长只授权了孩子 A 时，不能访问孩子 B。
    func testGuardianScopedToAuthorizedChildren() throws {
        let client = try makeClient()
        let session = guardianSession(authorized: [childARef])
        XCTAssertEqual(
            client.creditBalance(session: session, childPublicRef: childBRef).failureError,
            .permissionDenied
        )
        // 授权范围内的孩子可以访问。
        guard case .success = client.creditBalance(session: session, childPublicRef: childARef) else {
            return XCTFail("授权孩子应可访问")
        }
    }

    /// 老师即使同属家庭，也必须有明确孩子授权才可读取。
    func testTeacherRequiresExplicitChildAuthorization() throws {
        let client = try makeClient()
        XCTAssertEqual(
            client.todayTasks(session: teacherSession(), childPublicRef: childARef).failureError,
            .permissionDenied
        )

        guard case .success(let tasks) = client.todayTasks(
            session: teacherSession(authorized: [childARef]),
            childPublicRef: childARef
        ) else {
            return XCTFail("老师显式授权后应可读取该孩子任务")
        }
        XCTAssertTrue(tasks.allSatisfy { $0.childPublicRef == childARef })
    }

    /// 不存在的孩子返回 childNotFound。
    func testUnknownChildReturnsNotFound() throws {
        let client = try makeClient()
        let result = client.creditBalance(session: guardianSession(), childPublicRef: "child:unknown")
        XCTAssertEqual(result.failureError, .childNotFound)
    }

    /// 孩子端不能批准任务（不能自己发成长积分）。
    func testChildCannotApprove() throws {
        let client = try makeClient()
        let result = client.approveTask(
            session: childSession(childARef),
            clientProofRef: "proof:p300005",
            decision: .approved,
            reasonCode: "ok"
        )
        XCTAssertEqual(result.failureError, .permissionDenied)
    }

    /// 老师不能替孩子提交证明。
    func testTeacherCannotSubmit() throws {
        let client = try makeClient()
        let result = client.submitTask(
            session: teacherSession(),
            clientTaskRef: "task:t100001",
            evidenceRefs: ["evidence:ref-1"],
            evidenceSummary: "已完成作业"
        )
        XCTAssertEqual(result.failureError, .permissionDenied)
    }

    // MARK: - 脱敏负载

    /// 提交证据中含 token/路径/局域网地址被拒绝为 unsafePayload。
    func testSubmitRejectsUnsafePayload() throws {
        let client = try makeClient()
        let unsafe = [
            "Bearer abc.def.ghi",
            "C:\\Users\\kid\\photo.png",
            "http://192.168.1.10/upload",
            "api_key=secret123"
        ]
        for sample in unsafe {
            let result = client.submitTask(
                session: childSession(childARef),
                clientTaskRef: "task:t100001",
                evidenceRefs: [],
                evidenceSummary: sample
            )
            XCTAssertEqual(result.failureError, .unsafePayload, "应拒绝不安全负载: \(sample)")
        }
    }

    // MARK: - 提交回执与重复提交

    /// 正常提交生成回执并把任务推进到 submitted。
    func testSubmitProducesReceiptAndAdvancesTask() throws {
        let client = try makeClient()
        let result = client.submitTask(
            session: childSession(childARef),
            clientTaskRef: "task:t100002",
            evidenceRefs: ["evidence:ref-2"],
            evidenceSummary: "朗读了十分钟绘本"
        )
        guard case .success(let receipt) = result else { return XCTFail("应成功提交") }
        XCTAssertEqual(receipt.clientTaskRef, "task:t100002")
        XCTAssertEqual(receipt.status, "submitted")
        XCTAssertEqual(client.snapshot.tasks.first { $0.clientTaskRef == "task:t100002" }?.status, .submitted)
    }

    /// 证据必填的任务，空证据被拒绝为 evidenceRequired。
    func testSubmitRequiresEvidenceWhenNeeded() throws {
        let client = try makeClient()
        let result = client.submitTask(
            session: childSession(childARef),
            clientTaskRef: "task:t100001",
            evidenceRefs: [],
            evidenceSummary: "   "
        )
        XCTAssertEqual(result.failureError, .evidenceRequired)
    }

    /// 已提交过的任务再次提交返回 duplicateSubmission。
    func testDuplicateSubmissionRejected() throws {
        let client = try makeClient()
        let result = client.submitTask(
            session: childSession(childARef),
            clientTaskRef: "task:t100005",
            evidenceRefs: ["evidence:ref-x"],
            evidenceSummary: "再交一次"
        )
        XCTAssertEqual(result.failureError, .duplicateSubmission)
    }

    /// 相同幂等键重复提交返回同一回执，不产生第二条提交。
    func testIdempotentSubmissionReturnsSameReceipt() throws {
        let client = try makeClient()
        let before = client.snapshot.submissions.count
        let key = "idem-key-1"
        let first = client.submitTask(
            session: childSession(childARef),
            clientTaskRef: "task:t100002",
            evidenceRefs: ["evidence:ref-2"],
            evidenceSummary: "朗读完成",
            idempotencyKey: key
        )
        let second = client.submitTask(
            session: childSession(childARef),
            clientTaskRef: "task:t100002",
            evidenceRefs: ["evidence:ref-2"],
            evidenceSummary: "朗读完成",
            idempotencyKey: key
        )
        guard case .success(let a) = first, case .success(let b) = second else {
            return XCTFail("两次提交都应成功")
        }
        XCTAssertEqual(a, b)
        XCTAssertEqual(client.snapshot.submissions.count, before + 1, "幂等提交只新增一条")
    }

    /// 同一个幂等键不能串到另一个任务，避免跨任务/跨孩子复用回执。
    func testIdempotencyKeyCannotBeReusedForDifferentTask() throws {
        let client = try makeClient()
        let key = "idem-key-reuse"
        guard case .success = client.submitTask(
            session: childSession(childARef),
            clientTaskRef: "task:t100002",
            evidenceRefs: ["evidence:ref-2"],
            evidenceSummary: "朗读完成",
            idempotencyKey: key
        ) else {
            return XCTFail("第一次提交应成功")
        }

        let result = client.submitTask(
            session: childSession(childARef),
            clientTaskRef: "task:t100001",
            evidenceRefs: ["evidence:ref-1"],
            evidenceSummary: "数学作业完成",
            idempotencyKey: key
        )
        XCTAssertEqual(result.failureError, .duplicateSubmission)
    }

    // MARK: - 审批结果与重复批准

    /// 家长批准提交后写入审批结果，并按类目把成长积分建议加入余额。
    func testGuardianApprovalGrantsCreditSuggestion() throws {
        let client = try makeClient()
        let beforeBalance = try XCTUnwrap(
            client.creditBalance(session: guardianSession(), childPublicRef: childARef).successValue
        )
        // task:t100005 是 exercise，建议 6 分。
        let result = client.approveTask(
            session: guardianSession(),
            clientProofRef: "proof:p300005",
            decision: .approved,
            reasonCode: "quality_ok"
        )
        guard case .success(let approval) = result else { return XCTFail("应批准成功") }
        XCTAssertEqual(approval.creditGrantSuggested, 6)

        let afterBalance = try XCTUnwrap(
            client.creditBalance(session: guardianSession(), childPublicRef: childARef).successValue
        )
        XCTAssertEqual(afterBalance.availableCredits, beforeBalance.availableCredits + 6)
        XCTAssertEqual(client.snapshot.tasks.first { $0.clientTaskRef == "task:t100005" }?.status, .verified)
    }

    /// 已批准的提交再次批准返回 duplicateApproval。
    func testDuplicateApprovalRejected() throws {
        let client = try makeClient()
        // proof:p300006 在 snapshot 中已是 accepted。
        let result = client.approveTask(
            session: guardianSession(),
            clientProofRef: "proof:p300006",
            decision: .approved,
            reasonCode: "quality_ok"
        )
        XCTAssertEqual(result.failureError, .duplicateApproval)
    }

    /// 驳回不发任何成长积分建议。
    func testRejectionGrantsNoCredit() throws {
        let client = try makeClient()
        let result = client.approveTask(
            session: guardianSession(),
            clientProofRef: "proof:p300005",
            decision: .rejected,
            reasonCode: "incomplete"
        )
        guard case .success(let approval) = result else { return XCTFail("驳回也应返回结果") }
        XCTAssertEqual(approval.creditGrantSuggested, 0)
        XCTAssertEqual(approval.decision, .rejected)
    }

    // MARK: - 奖励会话

    /// 读取奖励会话能拿到不同运行态（active / ended）。
    func testRewardSessionStatesAreReadable() throws {
        let client = try makeClient()
        let a = try XCTUnwrap(client.rewardSessions(session: guardianSession(), childPublicRef: childARef).successValue)
        XCTAssertEqual(a.first { $0.clientRewardSessionRef == "reward:r500001" }?.status, .active)
        let b = try XCTUnwrap(client.rewardSessions(session: guardianSession(), childPublicRef: childBRef).successValue)
        XCTAssertEqual(b.first { $0.clientRewardSessionRef == "reward:r500002" }?.status, .ended)
    }

    /// 孩子端不能开启奖励会话。
    func testChildCannotStartRewardSession() throws {
        let client = try makeClient()
        let result = client.startRewardSession(
            session: childSession(childARef),
            childPublicRef: childARef,
            rewardType: .screenTime,
            targetRef: "device-target:mock",
            plannedMinutes: 15
        )
        XCTAssertEqual(result.failureError, .permissionDenied)
    }

    /// 成长积分不足时不开会话、不扣成长积分。
    func testInsufficientCreditBlocksRewardSession() throws {
        let client = try makeClient()
        // 孩子 A 仅 8 成长积分，请求 15 分（成本 15）。
        let result = client.startRewardSession(
            session: guardianSession(),
            childPublicRef: childARef,
            rewardType: .screenTime,
            targetRef: "device-target:mock",
            plannedMinutes: 15
        )
        XCTAssertEqual(result.failureError, .insufficientCredit)
        XCTAssertEqual(
            client.creditBalance(session: guardianSession(), childPublicRef: childARef).successValue?.availableCredits,
            8,
            "成长积分不足不应扣减"
        )
    }

    /// 成长积分充足时开启 pending 会话，标记设备命令已排队，并从可用扣到 held。
    func testStartRewardSessionPendingAndHoldsCredit() throws {
        let client = try makeClient()
        let result = client.startRewardSession(
            session: guardianSession(),
            childPublicRef: childBRef,
            rewardType: .screenTime,
            targetRef: "device-target:mock",
            plannedMinutes: 20
        )
        guard case .success(let reward) = result else { return XCTFail("应成功开启") }
        XCTAssertEqual(reward.status, .pending)
        XCTAssertTrue(reward.deviceCommandQueued)

        let balance = try XCTUnwrap(
            client.creditBalance(session: guardianSession(), childPublicRef: childBRef).successValue
        )
        XCTAssertEqual(balance.availableCredits, 40)
        XCTAssertEqual(balance.heldCredits, 20)
    }

    /// 非法分钟数（<= 0）被拒绝。
    func testRewardSessionRejectsNonPositiveMinutes() throws {
        let client = try makeClient()
        let result = client.startRewardSession(
            session: guardianSession(),
            childPublicRef: childBRef,
            rewardType: .screenTime,
            targetRef: "device-target:mock",
            plannedMinutes: 0
        )
        XCTAssertEqual(result.failureError, .unsafePayload)
    }

    // MARK: - 成长动态可见性

    /// 默认返回孩子全部动态；按可见性过滤只返回匹配项。
    func testGrowthFeedVisibilityFilter() throws {
        let client = try makeClient()
        let all = try XCTUnwrap(client.growthFeed(session: childSession(childARef), childPublicRef: childARef).successValue)
        XCTAssertEqual(all.count, 2)

        let familyOnly = try XCTUnwrap(
            client.growthFeed(session: childSession(childARef), childPublicRef: childARef, visibility: .family).successValue
        )
        XCTAssertEqual(familyOnly.count, 1)
        XCTAssertEqual(familyOnly.first?.visibility, .family)
    }
}

// MARK: - Result 便捷断言

private extension Result where Failure == MobileSyncError {
    var failureError: MobileSyncError? {
        if case .failure(let error) = self { return error }
        return nil
    }

    var successValue: Success? {
        if case .success(let value) = self { return value }
        return nil
    }
}
