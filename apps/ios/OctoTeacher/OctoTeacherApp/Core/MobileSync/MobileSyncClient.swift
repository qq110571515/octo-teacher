import Foundation

/// 移动同步客户端消费壳。
///
/// 把一个本地 mock snapshot 当作只读初始态消费，并在本地复现 mobile-sync-api 的
/// 用例语义：今日任务、任务提交回执、家长审批结果、成长积分余额、奖励会话与家庭成长动态。
///
/// 安全边界（与 CLAUDE.md 一致）：
/// - 不接真实网络、云 API、数据库、登录、支付、AI、推送、HealthKit、FamilyControls。
/// - 权限在本地裁决：孩子端不能批准任务、不能发成长积分、不能开奖励会话、不能跨孩子访问。
/// - 所有引用都是脱敏公开引用；提交/审批负载经 `MobileSyncPayloadGuard` 过滤。
/// - 奖励会话的 `deviceCommandQueued` 只是命令排队标志，绝不在此真正解锁设备。
final class MobileSyncClient {
    private(set) var snapshot: MobileSyncSnapshot

    /// 已使用过的幂等键 -> 已生成的提交回执，保证重复提交幂等。
    private var idempotentSubmissions: [String: MobileSyncSubmission] = [:]

    init(snapshot: MobileSyncSnapshot) {
        self.snapshot = snapshot
    }

    /// 用内置 mock snapshot 构造一个消费壳。
    static func makeMock() throws -> MobileSyncClient {
        MobileSyncClient(snapshot: try MobileSyncSnapshot.mock())
    }

    /// 用内置 mock 构造，解析失败回退到空 snapshot。供 UI 层无需 try 即可安全持有。
    static func makeMockOrEmpty() -> MobileSyncClient {
        MobileSyncClient(snapshot: (try? MobileSyncSnapshot.mock()) ?? .empty)
    }

    /// 从外部 JSON 数据构造（仍是本地数据，不接网络）。
    static func decode(from data: Data) throws -> MobileSyncClient {
        MobileSyncClient(snapshot: try MobileSyncSnapshot.decode(from: data))
    }

    // MARK: - 权限裁决

    private func child(forPublicRef publicRef: String) -> MobileSyncSnapshot.Child? {
        snapshot.children.first { $0.publicRef == publicRef }
    }

    /// 会话能否访问指定孩子。
    private func isAllowed(_ session: MobileSyncSession, child: MobileSyncSnapshot.Child) -> Bool {
        guard session.familyPublicRef == child.familyPublicRef else { return false }
        switch session.actorRole {
        case .child:
            return session.childPublicRef == child.publicRef
        case .guardian:
            if session.authorizedChildPublicRefs.isEmpty { return true }
            return session.authorizedChildPublicRefs.contains(child.publicRef)
        case .teacher:
            guard !session.authorizedChildPublicRefs.isEmpty else { return false }
            return session.authorizedChildPublicRefs.contains(child.publicRef)
        }
    }

    /// 解析会话请求的目标孩子：显式 childPublicRef 优先，否则回退到孩子会话自身。
    private func resolveChild(
        _ session: MobileSyncSession,
        childPublicRef: String?
    ) -> Result<MobileSyncSnapshot.Child, MobileSyncError> {
        let targetRef = childPublicRef ?? session.childPublicRef
        guard let ref = targetRef, let child = child(forPublicRef: ref) else {
            return .failure(.childNotFound)
        }
        guard isAllowed(session, child: child) else {
            return .failure(.permissionDenied)
        }
        return .success(child)
    }

    // MARK: - 今日任务

    /// 读取某个孩子在指定日期的今日任务。默认按 snapshot.generatedAt 当天过滤。
    func todayTasks(
        session: MobileSyncSession,
        childPublicRef: String? = nil,
        plannedFor: String? = nil
    ) -> Result<[MobileSyncTask], MobileSyncError> {
        switch resolveChild(session, childPublicRef: childPublicRef) {
        case .failure(let error):
            return .failure(error)
        case .success(let child):
            let targetDate = plannedFor ?? String(snapshot.generatedAt.prefix(10))
            let tasks = snapshot.tasks.filter {
                $0.childPublicRef == child.publicRef && $0.plannedFor == targetDate
            }
            return .success(tasks)
        }
    }

    // MARK: - 任务提交回执

    /// 提交任务证明，返回提交回执。
    /// 覆盖：脱敏、权限、老师不可提交、重复提交、证据必填、幂等。
    func submitTask(
        session: MobileSyncSession,
        clientTaskRef: String,
        evidenceRefs: [String],
        evidenceSummary: String,
        idempotencyKey: String? = nil,
        submittedAt: String = "2026-06-23T21:00:00Z"
    ) -> Result<MobileSyncSubmission, MobileSyncError> {
        if MobileSyncPayloadGuard.isUnsafe(evidenceRefs + [evidenceSummary]) {
            return .failure(.unsafePayload)
        }
        guard let index = snapshot.tasks.firstIndex(where: { $0.clientTaskRef == clientTaskRef }) else {
            return .failure(.taskNotFound)
        }
        let task = snapshot.tasks[index]
        guard let child = child(forPublicRef: task.childPublicRef), isAllowed(session, child: child) else {
            return .failure(.permissionDenied)
        }
        if session.actorRole == .teacher {
            return .failure(.permissionDenied)
        }

        if let key = idempotencyKey, let existing = idempotentSubmissions[key] {
            if existing.clientTaskRef == clientTaskRef && existing.childPublicRef == task.childPublicRef {
                return .success(existing)
            }
            return .failure(.duplicateSubmission)
        }

        let alreadySubmitted = task.status == .submitted
            || task.status == .verified
            || task.hasSubmittedProof
            || snapshot.submissions.contains { $0.clientTaskRef == clientTaskRef }
        if alreadySubmitted {
            return .failure(.duplicateSubmission)
        }

        let trimmedSummary = evidenceSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedRefs = evidenceRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if task.requiresEvidence && cleanedRefs.isEmpty && trimmedSummary.isEmpty {
            return .failure(.evidenceRequired)
        }

        let proofRef = "proof:client-\(snapshot.submissions.count + 1)"
        let submission = MobileSyncSubmission(
            clientProofRef: proofRef,
            clientTaskRef: clientTaskRef,
            childPublicRef: task.childPublicRef,
            status: "submitted",
            submittedAt: submittedAt,
            evidenceSummaryPreview: String(trimmedSummary.prefix(160))
        )
        snapshot.submissions.append(submission)
        snapshot.tasks[index].status = .submitted
        snapshot.tasks[index].hasSubmittedProof = true

        if let key = idempotencyKey {
            idempotentSubmissions[key] = submission
        }
        return .success(submission)
    }

    // MARK: - 家长审批结果

    /// 家长/老师对一条提交做审批。孩子端被拒绝。覆盖：权限、脱敏、重复批准、成长积分建议入账。
    func approveTask(
        session: MobileSyncSession,
        clientProofRef: String,
        decision: MobileSyncApprovalDecision,
        reasonCode: String,
        decidedAt: String = "2026-06-23T21:00:00Z"
    ) -> Result<MobileSyncApproval, MobileSyncError> {
        if session.actorRole == .child {
            return .failure(.permissionDenied)
        }
        if MobileSyncPayloadGuard.isUnsafe(reasonCode) {
            return .failure(.unsafePayload)
        }
        guard let proofIndex = snapshot.submissions.firstIndex(where: { $0.clientProofRef == clientProofRef }) else {
            return .failure(.proofNotFound)
        }
        let proof = snapshot.submissions[proofIndex]
        guard let child = child(forPublicRef: proof.childPublicRef), isAllowed(session, child: child) else {
            return .failure(.permissionDenied)
        }
        guard let taskIndex = snapshot.tasks.firstIndex(where: { $0.clientTaskRef == proof.clientTaskRef }) else {
            return .failure(.taskNotFound)
        }

        let duplicate = proof.status == "accepted"
            || snapshot.approvals.contains { $0.clientProofRef == clientProofRef && $0.decision == .approved }
        if duplicate {
            return .failure(.duplicateApproval)
        }

        let task = snapshot.tasks[taskIndex]
        let amount = decision == .approved ? Self.creditAmount(for: task.category) : 0
        let approval = MobileSyncApproval(
            clientDecisionRef: "decision:client-\(snapshot.approvals.count + 1)",
            clientProofRef: clientProofRef,
            clientTaskRef: proof.clientTaskRef,
            childPublicRef: proof.childPublicRef,
            decision: decision,
            reasonCode: reasonCode.trimmingCharacters(in: .whitespacesAndNewlines),
            decidedAt: decidedAt,
            creditGrantSuggested: amount
        )
        snapshot.approvals.append(approval)

        switch decision {
        case .approved:
            snapshot.submissions[proofIndex].status = "accepted"
            snapshot.tasks[taskIndex].status = .verified
        case .rejected, .needsRevision:
            snapshot.submissions[proofIndex].status = decision.rawValue
            snapshot.tasks[taskIndex].status = .submitted
        }

        if amount > 0, let balanceIndex = snapshot.creditBalances.firstIndex(where: { $0.childPublicRef == proof.childPublicRef }) {
            snapshot.creditBalances[balanceIndex].availableCredits += amount
            snapshot.creditBalances[balanceIndex].totalEarnedCredits += amount
            snapshot.creditBalances[balanceIndex].capturedAt = decidedAt
        }
        return .success(approval)
    }

    private static func creditAmount(for category: MobileSyncTaskCategory) -> Int {
        switch category {
        case .homework: return 10
        case .exercise: return 6
        case .learning: return 5
        default: return 4
        }
    }

    // MARK: - 成长积分余额

    /// 读取某个孩子的成长积分余额快照。
    func creditBalance(
        session: MobileSyncSession,
        childPublicRef: String? = nil
    ) -> Result<MobileSyncCreditBalance, MobileSyncError> {
        switch resolveChild(session, childPublicRef: childPublicRef) {
        case .failure(let error):
            return .failure(error)
        case .success(let child):
            if let balance = snapshot.creditBalances.first(where: { $0.childPublicRef == child.publicRef }) {
                return .success(balance)
            }
            let zero = MobileSyncCreditBalance(
                childPublicRef: child.publicRef,
                availableCredits: 0,
                heldCredits: 0,
                spentCredits: 0,
                totalEarnedCredits: 0,
                expiringSoonCredits: 0,
                usableScopes: ["parent_approval_required"],
                capturedAt: snapshot.generatedAt
            )
            return .success(zero)
        }
    }

    // MARK: - 奖励会话

    /// 读取某个孩子的奖励会话列表（含 active/ended 等运行态）。
    func rewardSessions(
        session: MobileSyncSession,
        childPublicRef: String? = nil
    ) -> Result<[MobileSyncRewardSession], MobileSyncError> {
        switch resolveChild(session, childPublicRef: childPublicRef) {
        case .failure(let error):
            return .failure(error)
        case .success(let child):
            return .success(snapshot.rewardSessions.filter { $0.childPublicRef == child.publicRef })
        }
    }

    /// 开启一个奖励会话。只有家长可开；覆盖：权限、脱敏、非法分钟、成长积分不足。
    /// 成功只生成 `pending` 会话并标记 `deviceCommandQueued`，不真正解锁设备。
    func startRewardSession(
        session: MobileSyncSession,
        childPublicRef: String? = nil,
        rewardType: MobileSyncRewardType,
        targetRef: String,
        plannedMinutes: Int,
        costCredits: Int? = nil
    ) -> Result<MobileSyncRewardSession, MobileSyncError> {
        if session.actorRole != .guardian {
            return .failure(.permissionDenied)
        }
        if plannedMinutes <= 0 || MobileSyncPayloadGuard.isUnsafe(targetRef) {
            return .failure(.unsafePayload)
        }
        let child: MobileSyncSnapshot.Child
        switch resolveChild(session, childPublicRef: childPublicRef) {
        case .failure(let error):
            return .failure(error)
        case .success(let resolved):
            child = resolved
        }

        let cost = costCredits ?? plannedMinutes
        guard let balanceIndex = snapshot.creditBalances.firstIndex(where: { $0.childPublicRef == child.publicRef }) else {
            return .failure(.insufficientCredit)
        }
        if snapshot.creditBalances[balanceIndex].availableCredits < cost {
            return .failure(.insufficientCredit)
        }

        let sequence = snapshot.rewardSessions.count + 1
        let rewardSession = MobileSyncRewardSession(
            clientRewardSessionRef: "reward:client-\(sequence)",
            childPublicRef: child.publicRef,
            rewardType: rewardType,
            plannedMinutes: plannedMinutes,
            status: .pending,
            creditHoldPublicRef: "hold:client-\(sequence)",
            deviceCommandQueued: true
        )
        snapshot.creditBalances[balanceIndex].availableCredits -= cost
        snapshot.creditBalances[balanceIndex].heldCredits += cost
        snapshot.creditBalances[balanceIndex].capturedAt = snapshot.generatedAt
        snapshot.rewardSessions.append(rewardSession)
        return .success(rewardSession)
    }

    // MARK: - 家庭成长动态

    /// 读取某个孩子的家庭成长动态。可按可见性过滤（脱敏/隐私边界）。
    func growthFeed(
        session: MobileSyncSession,
        childPublicRef: String? = nil,
        visibility: MobileSyncVisibility? = nil
    ) -> Result<[MobileSyncGrowthFeedItem], MobileSyncError> {
        switch resolveChild(session, childPublicRef: childPublicRef) {
        case .failure(let error):
            return .failure(error)
        case .success(let child):
            let items = snapshot.growthFeed
                .filter { $0.childPublicRef == child.publicRef }
                .filter { visibility == nil || $0.visibility == visibility }
            return .success(items)
        }
    }
}
