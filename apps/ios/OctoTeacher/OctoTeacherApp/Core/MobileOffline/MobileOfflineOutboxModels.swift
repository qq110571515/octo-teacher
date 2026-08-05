import Foundation
import Observation

/// iOS 离线同步 outbox 的本地契约模型。
///
/// 承接平台共享契约 B22（mobile-offline-sync / 离线同步队列与冲突契约）的 view 语义，
/// 把「离线待同步、重放保护、冲突/回滚提示、脱敏公开状态」映射成 iOS 本地可消费、
/// 可测试的模型。设计约束（与 CLAUDE.md 一致）：
///
/// - 这是一个**本地壳**：孩子/家长/老师/亲友/设备的动作只进入本地 outbox，
///   绝不接真实网络、云 API、数据库、队列、登录、支付、AI、推送或真实设备控制。
/// - outbox 只持有脱敏公开引用（`kind:token` 形式），绝不持有真实
///   child/family/school/teacher/relative/device/ref、token、路径、局域网地址、
///   taskId、claimId 或完整内部 ID。
/// - outbox **没有任何「已落定」终态**：任何 mutation 最多停在
///   pending / conflict / rolledBack，绝不会在本地把任务标成已验证、把成长积分发出去、
///   把审批落定或解锁设备。这从结构上保证「孩子不能用离线队列绕过家长/老师验证」、
///   「亲友离线动作不会直接发成长积分或解锁设备」。

// MARK: - 角色

/// 可以向离线 outbox 投递动作的角色。
enum MobileOfflineActorRole: String, Codable, Equatable, CaseIterable {
    case child
    case guardian
    case teacher
    case relative
    case device

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .teacher: return "老师"
        case .relative: return "亲友"
        case .device: return "设备"
        }
    }

    /// 双语角色名：中文孩子看中文，英文孩子看英文。
    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .child: return "Child"
        case .guardian: return "Parent"
        case .teacher: return "Teacher"
        case .relative: return "Relative"
        case .device: return "Device"
        }
    }
}

// MARK: - 动作类型

/// 离线 outbox 支持的本地 mutation 类型。每种都对应一个明确的发起角色，
/// 角色与类型的授权矩阵在 `allowedRoles` 中收口，越权一律拒绝。
enum MobileOfflineMutationKind: String, Codable, Equatable, CaseIterable {
    /// 孩子任务提交（提交证明，待家长/老师验证）。
    case childTaskSubmission = "child_task_submission"
    /// 学校作业提交（提交证明，待验证）。
    case schoolHomeworkSubmission = "school_homework_submission"
    /// 家长审批（家长/老师对一条提交做裁决；只入队，不在本地落定）。
    case guardianApproval = "guardian_approval"
    /// 亲友评论（待家长审核后才可见；不发成长积分、不解锁设备）。
    case relativeComment = "relative_comment"
    /// 成长积分兑换请求（孩子发起请求，需家长开启；本地不发放、不解锁）。
    case rewardRequest = "reward_request"
    /// 设备回执（设备侧对一条命令的本地确认；只记录，不代表真实解锁）。
    case deviceReceipt = "device_receipt"

    /// 允许发起该类型的角色集合（授权矩阵）。
    ///
    /// 关键边界：
    /// - 审批只允许家长/老师，孩子与亲友都不可，防止用离线队列自批/绕过验证。
    /// - 成长积分兑换请求只允许孩子发起（请求语义），不允许亲友，亲友不可借此发成长积分/解锁。
    var allowedRoles: Set<MobileOfflineActorRole> {
        switch self {
        case .childTaskSubmission: return [.child]
        case .schoolHomeworkSubmission: return [.child]
        case .guardianApproval: return [.guardian, .teacher]
        case .relativeComment: return [.relative]
        case .rewardRequest: return [.child]
        case .deviceReceipt: return [.device]
        }
    }

    /// 该类型最终是否仍需服务端/家长流程验证才能落定。
    ///
    /// 除设备回执（纯本地确认）外都为 true：离线壳只负责排队，绝不在本地把它们落定。
    var requiresServerVerification: Bool {
        switch self {
        case .deviceReceipt: return false
        default: return true
        }
    }

    var label: String {
        switch self {
        case .childTaskSubmission: return "任务提交"
        case .schoolHomeworkSubmission: return "作业提交"
        case .guardianApproval: return "家长审批"
        case .relativeComment: return "亲友评论"
        case .rewardRequest: return "成长积分兑换请求"
        case .deviceReceipt: return "设备回执"
        }
    }

    /// 双语类型名：中文孩子看中文，英文孩子看英文。
    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .childTaskSubmission: return "Task hand-in"
        case .schoolHomeworkSubmission: return "Homework hand-in"
        case .guardianApproval: return "Parent approval"
        case .relativeComment: return "Relative comment"
        case .rewardRequest: return "Growth Points request"
        case .deviceReceipt: return "Device receipt"
        }
    }

    var systemImage: String {
        switch self {
        case .childTaskSubmission: return "checklist"
        case .schoolHomeworkSubmission: return "tray.and.arrow.up"
        case .guardianApproval: return "checkmark.seal"
        case .relativeComment: return "text.bubble"
        case .rewardRequest: return "gift"
        case .deviceReceipt: return "iphone.badge.checkmark"
        }
    }
}

// MARK: - 声明意图

/// mutation 声明的本地意图。离线壳只接受 `localQueueOnly`：任何试图在离线态
/// 直接发成长积分、解锁设备或落定审批的请求都会被拒绝（`forbiddenEffect`）。
enum MobileOfflineEffect: String, Codable, Equatable {
    /// 仅本地排队，等服务端/家长流程裁决（唯一被接受的意图）。
    case localQueueOnly = "local_queue_only"
    /// 试图直接发放成长积分 —— 离线壳一律拒绝。
    case grantCredit = "grant_credit"
    /// 试图直接解锁设备 —— 离线壳一律拒绝。
    case unlockDevice = "unlock_device"
    /// 试图直接把审批落定为终态 —— 离线壳一律拒绝。
    case finalizeApproval = "finalize_approval"
}

// MARK: - 状态

/// 离线 mutation 的运行态。注意：没有任何「已落定/已验证/已发成长积分」终态。
enum MobileOfflineMutationStatus: String, Codable, Equatable {
    /// 待同步：已入本地队列，等联网后上传。
    case pending
    /// 冲突：服务端裁决与本地不一致，需人工/家长处理（本地乐观变更可能已回滚）。
    case conflict
    /// 已回滚：本地乐观变更已撤销。
    case rolledBack = "rolled_back"

    var label: String {
        switch self {
        case .pending: return "待同步"
        case .conflict: return "有冲突"
        case .rolledBack: return "已回滚"
        }
    }

    /// 双语状态名：中文孩子看中文，英文孩子看英文。
    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .pending: return "Waiting to sync"
        case .conflict: return "Has a conflict"
        case .rolledBack: return "Rolled back"
        }
    }
}

// MARK: - 冲突原因

/// 冲突/回滚原因。文案均为脱敏的人类可读说明，不含任何真实标识。
enum MobileOfflineConflictReason: String, Codable, Equatable {
    /// 重放：相同幂等键但负载不同。
    case duplicateReplay = "duplicate_replay"
    /// 本地版本落后于服务端。
    case staleVersion = "stale_version"
    /// 服务端已处理（如已被验证/已审批）。
    case alreadyResolved = "already_resolved"
    /// 已被家长侧操作覆盖。
    case supersededByGuardian = "superseded_by_guardian"

    var hint: String {
        switch self {
        case .duplicateReplay: return "检测到重复提交，已保留先到的一条"
        case .staleVersion: return "本地内容已过期，云端有更新的版本"
        case .alreadyResolved: return "这条已经在其它设备处理过了"
        case .supersededByGuardian: return "家长已在另一处做了处理"
        }
    }

    var nextStep: String {
        switch self {
        case .duplicateReplay: return "无需重复操作，等同步完成即可"
        case .staleVersion: return "联网刷新后再提交一次"
        case .alreadyResolved: return "可直接查看最新结果"
        case .supersededByGuardian: return "以家长侧的最新处理为准"
        }
    }

    /// 双语冲突提示：中文孩子看中文，英文孩子看英文（面向儿童，简短友好）。
    func hint(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return hint }
        switch self {
        case .duplicateReplay: return "This was handed in twice, so we kept the first one"
        case .staleVersion: return "This copy is out of date — the cloud has a newer version"
        case .alreadyResolved: return "This was already handled on another device"
        case .supersededByGuardian: return "A parent already took care of this somewhere else"
        }
    }

    /// 双语下一步建议：中文孩子看中文，英文孩子看英文。
    func nextStep(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return nextStep }
        switch self {
        case .duplicateReplay: return "No need to do it again — just wait for the sync to finish"
        case .staleVersion: return "Refresh once you are online, then hand it in again"
        case .alreadyResolved: return "You can check the latest result now"
        case .supersededByGuardian: return "Go with what your parent decided"
        }
    }
}

// MARK: - 错误

/// 入队/裁决错误码。
enum MobileOfflineError: String, Error, Equatable {
    /// 角色无权发起该类型（如孩子试图审批、亲友试图请求奖励）。
    case permissionDenied = "permission_denied"
    /// 负载命中脱敏守卫（token、路径、局域网地址等）。
    case unsafePayload = "unsafe_payload"
    /// 声明了越权意图（直接发成长积分/解锁设备/落定审批）。
    case forbiddenEffect = "forbidden_effect"
    /// 相同幂等键但负载不同（重放保护拒绝）。
    case duplicateReplay = "duplicate_replay"
    /// 关键标识为空（actor / subject / 幂等键）。
    case emptyIdentifier = "empty_identifier"
    /// 找不到目标 mutation（裁决时）。
    case mutationNotFound = "mutation_not_found"
}

// MARK: - 入队请求

/// 一次离线 mutation 的入队请求草稿。调用方只填脱敏公开引用与摘要，
/// 由 outbox 校验、脱敏裁决并分配 client mutation 引用。
struct MobileOfflineMutationRequest: Equatable {
    var kind: MobileOfflineMutationKind
    var actorRole: MobileOfflineActorRole
    var actorPublicRef: String
    /// 目标公开引用（孩子/任务/作业/会话/设备命令的脱敏引用）。
    var subjectPublicRef: String
    var summary: String
    var idempotencyKey: String
    /// 声明意图，默认仅本地排队；越权意图会被拒绝。
    var declaredEffect: MobileOfflineEffect
    var enqueuedAt: String

    init(
        kind: MobileOfflineMutationKind,
        actorRole: MobileOfflineActorRole,
        actorPublicRef: String,
        subjectPublicRef: String,
        summary: String,
        idempotencyKey: String,
        declaredEffect: MobileOfflineEffect = .localQueueOnly,
        enqueuedAt: String = "2026-06-23T21:00:00Z"
    ) {
        self.kind = kind
        self.actorRole = actorRole
        self.actorPublicRef = actorPublicRef
        self.subjectPublicRef = subjectPublicRef
        self.summary = summary
        self.idempotencyKey = idempotencyKey
        self.declaredEffect = declaredEffect
        self.enqueuedAt = enqueuedAt
    }
}

// MARK: - 已入队的 mutation

/// 已入队的离线 mutation。只持有脱敏字段。
struct MobileOfflineMutation: Identifiable, Equatable {
    var clientMutationRef: String
    var kind: MobileOfflineMutationKind
    var actorRole: MobileOfflineActorRole
    var actorPublicRef: String
    var subjectPublicRef: String
    /// 脱敏摘要预览（已裁剪长度）。
    var summaryPreview: String
    var idempotencyKey: String
    var status: MobileOfflineMutationStatus
    var enqueuedAt: String
    var conflictReason: MobileOfflineConflictReason?

    var id: String { clientMutationRef }

    /// 该 mutation 最终仍需服务端/家长流程验证才能落定。
    var requiresServerVerification: Bool { kind.requiresServerVerification }
}

// MARK: - 冲突提示（脱敏展示）

/// 一条冲突/回滚提示，专供 UI 展示。只含脱敏文案与下一步建议。
struct MobileOfflineConflictHint: Identifiable, Equatable {
    var clientMutationRef: String
    var kindLabel: String
    var actorLabel: String
    var reason: MobileOfflineConflictReason
    var message: String
    var nextStep: String
    var rolledBack: Bool

    var id: String { clientMutationRef }
}

// MARK: - 公开状态（脱敏聚合）

/// outbox 的脱敏公开状态摘要：只暴露计数与一句话总览，绝不暴露条目细节。
struct MobileOfflinePublicStatus: Equatable {
    var pendingCount: Int
    var conflictCount: Int
    var rolledBackCount: Int

    /// 队列是否完全干净（无待同步、无冲突、无回滚）。
    var isClean: Bool { pendingCount == 0 && conflictCount == 0 && rolledBackCount == 0 }

    /// 是否存在需要关注的冲突或回滚。
    var hasAttention: Bool { conflictCount > 0 || rolledBackCount > 0 }

    /// 一句话总览（脱敏）。
    var headline: String {
        if isClean { return "全部已同步" }
        if hasAttention {
            return "有 \(conflictCount + rolledBackCount) 条需要处理，\(pendingCount) 条待同步"
        }
        return "有 \(pendingCount) 条待同步"
    }

    /// 双语一句话总览：中文孩子看中文，英文孩子看英文。
    func headline(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return headline }
        if isClean { return "Everything is synced" }
        if hasAttention {
            return "\(conflictCount + rolledBackCount) need attention, \(pendingCount) waiting to sync"
        }
        return "\(pendingCount) waiting to sync"
    }

    static let clean = MobileOfflinePublicStatus(pendingCount: 0, conflictCount: 0, rolledBackCount: 0)
}

// MARK: - 本地 outbox store

/// iOS 本地离线 outbox。只负责排队和展示同步风险，不把任何业务状态落定。
@Observable
final class MobileOfflineOutboxStore {
    private(set) var mutations: [MobileOfflineMutation]

    init(mutations: [MobileOfflineMutation] = []) {
        self.mutations = mutations
    }

    /// App 预览/本地演示用初始队列：覆盖六类入口与待同步/冲突/回滚提示。
    ///
    /// 故意预置一条冲突（学校作业，版本过期）与一条回滚（任务提交，已被家长覆盖），
    /// 这样首页跑一次 `.allClear` 本地重放即可同时呈现 confirmed / needsGuardianReview /
    /// conflict / rolledBack 四态，便于本地验收。所有引用均为脱敏 `kind-demo` 形式。
    static func mock() -> MobileOfflineOutboxStore {
        let store = MobileOfflineOutboxStore()
        let seeds: [MobileOfflineMutationRequest] = [
            MobileOfflineMutationRequest(
                kind: .childTaskSubmission,
                actorRole: .child,
                actorPublicRef: "actor-child-demo",
                subjectPublicRef: "subject-reading-demo",
                summary: "阅读任务证明待同步",
                idempotencyKey: "offline-demo-reading"
            ),
            MobileOfflineMutationRequest(
                kind: .schoolHomeworkSubmission,
                actorRole: .child,
                actorPublicRef: "actor-child-demo",
                subjectPublicRef: "subject-homework-demo",
                summary: "数学作业证明待同步",
                idempotencyKey: "offline-demo-homework"
            ),
            MobileOfflineMutationRequest(
                kind: .relativeComment,
                actorRole: .relative,
                actorPublicRef: "actor-relative-demo",
                subjectPublicRef: "subject-family-feed-demo",
                summary: "亲友鼓励待家长审核",
                idempotencyKey: "offline-demo-relative"
            ),
            MobileOfflineMutationRequest(
                kind: .rewardRequest,
                actorRole: .child,
                actorPublicRef: "actor-child-demo",
                subjectPublicRef: "subject-reward-demo",
                summary: "申请 30 成长积分兑换，待家长开启",
                idempotencyKey: "offline-demo-reward"
            ),
            MobileOfflineMutationRequest(
                kind: .childTaskSubmission,
                actorRole: .child,
                actorPublicRef: "actor-child-demo",
                subjectPublicRef: "subject-exercise-demo",
                summary: "运动任务证明待同步",
                idempotencyKey: "offline-demo-exercise"
            ),
            MobileOfflineMutationRequest(
                kind: .deviceReceipt,
                actorRole: .device,
                actorPublicRef: "actor-device-demo",
                subjectPublicRef: "subject-command-demo",
                summary: "本机回执：本次会话 15 分钟，仅确认不代表真实解锁",
                idempotencyKey: "offline-demo-receipt"
            )
        ]
        for seed in seeds {
            _ = store.enqueue(seed)
        }
        // 预置一条冲突：学校作业本地版本落后。
        if let homework = store.mutations.first(where: { $0.kind == .schoolHomeworkSubmission }) {
            _ = store.markConflict(clientMutationRef: homework.clientMutationRef, reason: .staleVersion)
        }
        // 预置一条回滚：运动任务已被家长在别处覆盖。
        if let exercise = store.mutations.first(where: { $0.idempotencyKey == "offline-demo-exercise" }) {
            _ = store.rollback(clientMutationRef: exercise.clientMutationRef, reason: .supersededByGuardian)
        }
        return store
    }

    var publicStatus: MobileOfflinePublicStatus {
        MobileOfflinePublicStatus(
            pendingCount: mutations.filter { $0.status == .pending }.count,
            conflictCount: mutations.filter { $0.status == .conflict }.count,
            rolledBackCount: mutations.filter { $0.status == .rolledBack }.count
        )
    }

    /// 冲突/回滚提示（默认中文，兼容既有调用方）。
    var conflictHints: [MobileOfflineConflictHint] {
        conflictHints(for: .chinese)
    }

    /// 双语冲突/回滚提示：中文孩子看中文，英文孩子看英文。
    func conflictHints(for language: AppInterfaceLanguage) -> [MobileOfflineConflictHint] {
        mutations.compactMap { mutation in
            guard mutation.status == .conflict || mutation.status == .rolledBack else { return nil }
            let reason = mutation.conflictReason ?? .alreadyResolved
            return MobileOfflineConflictHint(
                clientMutationRef: mutation.clientMutationRef,
                kindLabel: mutation.kind.label(for: language),
                actorLabel: mutation.actorRole.label(for: language),
                reason: reason,
                message: reason.hint(for: language),
                nextStep: reason.nextStep(for: language),
                rolledBack: mutation.status == .rolledBack
            )
        }
    }

    @discardableResult
    func enqueue(_ request: MobileOfflineMutationRequest) -> Result<MobileOfflineMutation, MobileOfflineError> {
        let cleaned = cleanedRequest(request)
        guard !cleaned.actorPublicRef.isEmpty, !cleaned.subjectPublicRef.isEmpty, !cleaned.idempotencyKey.isEmpty else {
            return .failure(.emptyIdentifier)
        }
        guard cleaned.declaredEffect == .localQueueOnly else {
            return .failure(.forbiddenEffect)
        }
        guard cleaned.kind.allowedRoles.contains(cleaned.actorRole) else {
            return .failure(.permissionDenied)
        }
        guard !Self.hasUnsafePayload(cleaned) else {
            return .failure(.unsafePayload)
        }

        if let existing = mutations.first(where: { $0.idempotencyKey == cleaned.idempotencyKey }) {
            if isReplayEquivalent(existing, cleaned) {
                return .success(existing)
            }
            return .failure(.duplicateReplay)
        }

        let mutation = MobileOfflineMutation(
            clientMutationRef: Self.stableLocalRef(prefix: "offline", source: "\(cleaned.idempotencyKey):\(mutations.count)"),
            kind: cleaned.kind,
            actorRole: cleaned.actorRole,
            actorPublicRef: cleaned.actorPublicRef,
            subjectPublicRef: cleaned.subjectPublicRef,
            summaryPreview: Self.summaryPreview(cleaned.summary),
            idempotencyKey: cleaned.idempotencyKey,
            status: .pending,
            enqueuedAt: cleaned.enqueuedAt,
            conflictReason: nil
        )
        mutations.append(mutation)
        return .success(mutation)
    }

    /// 只读查看同一入队请求当前会得到的结果，不新增 mutation。
    ///
    /// 页面可用它在重进时恢复“已排队/重复冲突/未排队”的展示状态，
    /// 避免为了判断状态而重复调用 `enqueue`。
    func existingEnqueueResult(
        for request: MobileOfflineMutationRequest
    ) -> Result<MobileOfflineMutation, MobileOfflineError>? {
        let cleaned = cleanedRequest(request)
        guard !cleaned.actorPublicRef.isEmpty, !cleaned.subjectPublicRef.isEmpty, !cleaned.idempotencyKey.isEmpty else {
            return .failure(.emptyIdentifier)
        }
        guard cleaned.declaredEffect == .localQueueOnly else {
            return .failure(.forbiddenEffect)
        }
        guard cleaned.kind.allowedRoles.contains(cleaned.actorRole) else {
            return .failure(.permissionDenied)
        }
        guard !Self.hasUnsafePayload(cleaned) else {
            return .failure(.unsafePayload)
        }

        guard let existing = mutations.first(where: { $0.idempotencyKey == cleaned.idempotencyKey }) else {
            return nil
        }
        if isReplayEquivalent(existing, cleaned) {
            return .success(existing)
        }
        return .failure(.duplicateReplay)
    }

    @discardableResult
    func markConflict(
        clientMutationRef: String,
        reason: MobileOfflineConflictReason
    ) -> Result<MobileOfflineMutation, MobileOfflineError> {
        guard let index = mutations.firstIndex(where: { $0.clientMutationRef == clientMutationRef }) else {
            return .failure(.mutationNotFound)
        }
        mutations[index].status = .conflict
        mutations[index].conflictReason = reason
        return .success(mutations[index])
    }

    @discardableResult
    func rollback(
        clientMutationRef: String,
        reason: MobileOfflineConflictReason
    ) -> Result<MobileOfflineMutation, MobileOfflineError> {
        guard let index = mutations.firstIndex(where: { $0.clientMutationRef == clientMutationRef }) else {
            return .failure(.mutationNotFound)
        }
        mutations[index].status = .rolledBack
        mutations[index].conflictReason = reason
        return .success(mutations[index])
    }

    private func cleanedRequest(_ request: MobileOfflineMutationRequest) -> MobileOfflineMutationRequest {
        MobileOfflineMutationRequest(
            kind: request.kind,
            actorRole: request.actorRole,
            actorPublicRef: request.actorPublicRef.trimmingCharacters(in: .whitespacesAndNewlines),
            subjectPublicRef: request.subjectPublicRef.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: request.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            idempotencyKey: request.idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines),
            declaredEffect: request.declaredEffect,
            enqueuedAt: request.enqueuedAt
        )
    }

    private func isReplayEquivalent(_ existing: MobileOfflineMutation, _ request: MobileOfflineMutationRequest) -> Bool {
        existing.kind == request.kind
            && existing.actorRole == request.actorRole
            && existing.actorPublicRef == request.actorPublicRef
            && existing.subjectPublicRef == request.subjectPublicRef
            && existing.summaryPreview == Self.summaryPreview(request.summary)
    }

    private static func hasUnsafePayload(_ request: MobileOfflineMutationRequest) -> Bool {
        let values = [
            request.actorPublicRef,
            request.subjectPublicRef,
            request.summary,
            request.idempotencyKey
        ]
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        return values.contains { value in
            value.range(of: "(?i)\\b(taskId|claimId)\\b", options: .regularExpression) != nil
        }
    }

    private static func summaryPreview(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    private static func stableLocalRef(prefix: String, source: String) -> String {
        var hash = 5381
        for scalar in source.unicodeScalars {
            hash = ((hash << 5) &+ hash) ^ Int(scalar.value)
        }
        let value = String(UInt(bitPattern: hash), radix: 36)
        return "\(prefix)-\(value)"
    }
}
