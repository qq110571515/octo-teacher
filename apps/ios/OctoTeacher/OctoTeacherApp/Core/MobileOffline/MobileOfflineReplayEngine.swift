import Foundation
import Observation

/// iOS 离线队列「本地 mock 同步重放与冲突回填」层。
///
/// 承接 `MobileOfflineOutboxStore`（本地待同步队列）与 `MobileOfflineActionComposer`
/// （脱敏请求组装），在**完全本地、确定性**的前提下复现「联网同步重放」的结果：
/// 每条 pending 动作经过一次 mock replay 后会落到四种 view 态之一 ——
/// `confirmed` / `needsGuardianReview` / `conflict` / `rolledBack`。
///
/// 关键安全边界（与 CLAUDE.md 一致，且比 outbox 更进一步）：
///
/// - **不接任何真实网络/云 API/数据库/队列/登录/推送**：重放结果完全由调用方注入的
///   确定性 `MobileOfflineReplayDirective`（本地 mock 服务端账本）决定，没有随机、没有时钟。
/// - **`confirmed` 不是业务落定**：它只表示「mock 服务端已确认收到这条排队动作」。
///   对仍需验证的提交（任务/作业）来说，confirmed 之后**依旧待家长/老师验证**，
///   绝不代表已发成长积分、已验证、已解锁设备。
/// - **审批 / 亲友评论 / 成长积分兑换请求一律走 `needsGuardianReview`**：这三类带「家长闸门」的动作
///   永远不会被 replay 直接 `confirmed`/落定。即便 directive 显式要求 confirm，引擎也会
///   强制降级为 needsGuardianReview。这从结构上保证：孩子不能借重放自批/发成长积分/解锁设备，
///   亲友动作不会直接变成公开动态，家长审批草稿仍需联网二次确认。
/// - **只读脱敏字段**：结果只携带 `clientMutationRef`（哈希引用）、角色/类型标签和脱敏文案，
///   绝不暴露真实 child/family/school/teacher/relative/device/ref、token、路径、局域网地址、
///   taskId、claimId 或完整内部 ID。

// MARK: - 重放结果态

/// 一条离线动作经本地 mock replay 后的 view 态。
///
/// 注意：这是**重放结果视图**，与 outbox 内部的 `MobileOfflineMutationStatus`
/// （只有 pending/conflict/rolledBack，永不落定）是两层。confirmed / needsGuardianReview
/// 表达「mock 同步层对这条动作的处置」，而非任何业务终态。
enum MobileOfflineReplayStatus: String, Codable, Equatable, CaseIterable {
    /// mock 服务端已确认收到（仍待下游验证；绝不代表已发成长积分/已解锁）。
    case confirmed
    /// 仍需家长闸门：审批草稿需联网二次确认、亲友留言需家长审核、成长积分兑换请求需家长开启。
    case needsGuardianReview = "needs_guardian_review"
    /// 与服务端裁决冲突，需关注（本地乐观变更可能保留也可能回滚）。
    case conflict
    /// 冲突且本地乐观变更已回滚。
    case rolledBack = "rolled_back"

    var label: String {
        switch self {
        case .confirmed: return "已确认收到"
        case .needsGuardianReview: return "待家长处理"
        case .conflict: return "有冲突"
        case .rolledBack: return "已回滚"
        }
    }

    var systemImage: String {
        switch self {
        case .confirmed: return "checkmark.circle"
        case .needsGuardianReview: return "person.crop.circle.badge.clock"
        case .conflict: return "exclamationmark.triangle"
        case .rolledBack: return "arrow.uturn.backward.circle"
        }
    }

    /// 是否需要用户/家长关注（confirmed 之外都算）。
    var needsAttention: Bool { self != .confirmed }
}

// MARK: - 重放裁决（mock 服务端账本注入点）

/// 单条动作的强制裁决。`MobileOfflineReplayDirective` 用它表达「mock 服务端账本」对
/// 某个幂等键的处置；未被覆盖的动作走按类型的默认策略。
enum MobileOfflineReplayVerdict: Equatable {
    /// mock 服务端确认收到（对带家长闸门的类型会被引擎强制降级为 needsGuardianReview）。
    case confirm
    /// 强制进入家长闸门。
    case needsGuardianReview
    /// 冲突，保留本地条目，附原因。
    case conflict(MobileOfflineConflictReason)
    /// 冲突且回滚本地乐观变更，附原因。
    case rollback(MobileOfflineConflictReason)
}

/// 本地 mock 重放指令：完全确定性，按 `idempotencyKey` 指定强制裁决。
///
/// 这是唯一的「服务端账本」输入口——没有它，引擎只按类型默认策略处置；有它，
/// 调用方（或测试）就能确定性地构造重复重放、版本过期、已被家长覆盖、已在其它设备处理等场景。
struct MobileOfflineReplayDirective: Equatable {
    /// idempotencyKey -> 强制裁决。
    var verdicts: [String: MobileOfflineReplayVerdict]
    /// 重放时间戳（可注入，便于确定性测试）。
    var replayedAt: String

    init(
        verdicts: [String: MobileOfflineReplayVerdict] = [:],
        replayedAt: String = "2026-06-23T21:30:00Z"
    ) {
        self.verdicts = verdicts
        self.replayedAt = replayedAt
    }

    /// 不注入任何冲突：全部走类型默认策略。
    static let allClear = MobileOfflineReplayDirective()
}

// MARK: - 重放结果（脱敏单条）

/// 一条动作的重放结果，专供 UI 展示。只含脱敏引用、标签与文案。
struct MobileOfflineReplayResult: Identifiable, Equatable {
    var clientMutationRef: String
    var kind: MobileOfflineMutationKind
    var actorRole: MobileOfflineActorRole
    var status: MobileOfflineReplayStatus
    var conflictReason: MobileOfflineConflictReason?
    var message: String
    var nextStep: String

    var id: String { clientMutationRef }
    var kindLabel: String { kind.label }
    var actorLabel: String { actorRole.label }
    var systemImage: String { status.systemImage }
}

// MARK: - 重放报告（脱敏聚合）

/// 一次重放的聚合报告：只暴露分态计数、一句话总览与脱敏结果列表。
struct MobileOfflineReplayReport: Equatable {
    var results: [MobileOfflineReplayResult]
    var replayedAt: String

    var confirmedCount: Int { results.filter { $0.status == .confirmed }.count }
    var needsReviewCount: Int { results.filter { $0.status == .needsGuardianReview }.count }
    var conflictCount: Int { results.filter { $0.status == .conflict }.count }
    var rolledBackCount: Int { results.filter { $0.status == .rolledBack }.count }

    /// 是否有需要关注的结果（待家长处理 / 冲突 / 回滚）。
    var hasAttention: Bool { needsReviewCount + conflictCount + rolledBackCount > 0 }

    /// 是否尚未跑过任何重放。
    var isEmpty: Bool { results.isEmpty }

    /// 一句话总览（脱敏）。
    var headline: String {
        if results.isEmpty { return "还没有可重放的离线动作" }
        if !hasAttention { return "\(confirmedCount) 条已确认收到，全部正常" }
        var parts: [String] = []
        if confirmedCount > 0 { parts.append("\(confirmedCount) 条已确认") }
        if needsReviewCount > 0 { parts.append("\(needsReviewCount) 条待家长处理") }
        if conflictCount > 0 { parts.append("\(conflictCount) 条冲突") }
        if rolledBackCount > 0 { parts.append("\(rolledBackCount) 条已回滚") }
        return parts.joined(separator: " · ")
    }

    /// 按类型过滤（供各页面只展示与本页相关的结果）。
    func results(for kinds: Set<MobileOfflineMutationKind>) -> [MobileOfflineReplayResult] {
        results.filter { kinds.contains($0.kind) }
    }

    static let empty = MobileOfflineReplayReport(results: [], replayedAt: "")
}

// MARK: - 重放引擎（纯逻辑）

/// 本地 mock 同步重放引擎。纯逻辑、无副作用、无网络、无随机、无时钟，给定相同输入恒定输出。
struct MobileOfflineReplayEngine {
    func replay(
        mutations: [MobileOfflineMutation],
        directive: MobileOfflineReplayDirective = .allClear
    ) -> MobileOfflineReplayReport {
        let results = mutations.map { resolve($0, directive: directive) }
        return MobileOfflineReplayReport(results: results, replayedAt: directive.replayedAt)
    }

    /// 处置单条动作：已是冲突/回滚的保持其态；pending 的按 directive/类型默认策略。
    private func resolve(
        _ mutation: MobileOfflineMutation,
        directive: MobileOfflineReplayDirective
    ) -> MobileOfflineReplayResult {
        switch mutation.status {
        case .conflict:
            return conflictResult(mutation, reason: mutation.conflictReason ?? .alreadyResolved, rolledBack: false)
        case .rolledBack:
            return conflictResult(mutation, reason: mutation.conflictReason ?? .supersededByGuardian, rolledBack: true)
        case .pending:
            return resolvePending(mutation, directive: directive)
        }
    }

    private func resolvePending(
        _ mutation: MobileOfflineMutation,
        directive: MobileOfflineReplayDirective
    ) -> MobileOfflineReplayResult {
        let verdict = directive.verdicts[mutation.idempotencyKey] ?? .confirm
        switch verdict {
        case .confirm:
            // 带家长闸门的类型永不被 replay 直接落定：强制降级。
            if mutation.kind.requiresGuardianGate {
                return needsReviewResult(mutation)
            }
            return confirmedResult(mutation)
        case .needsGuardianReview:
            return needsReviewResult(mutation)
        case .conflict(let reason):
            return conflictResult(mutation, reason: reason, rolledBack: false)
        case .rollback(let reason):
            return conflictResult(mutation, reason: reason, rolledBack: true)
        }
    }

    // MARK: - 各态文案（全部脱敏）

    private func confirmedResult(_ mutation: MobileOfflineMutation) -> MobileOfflineReplayResult {
        let message: String
        let nextStep: String
        if mutation.requiresServerVerification {
            message = "云端已确认收到，仍待家长或老师验证"
            nextStep = "无需重复提交，等验证结果即可"
        } else {
            // 设备回执：纯本地确认，不代表真实解锁。
            message = "本机回执已确认记录，不代表真实解锁设备"
            nextStep = "无需操作"
        }
        return MobileOfflineReplayResult(
            clientMutationRef: mutation.clientMutationRef,
            kind: mutation.kind,
            actorRole: mutation.actorRole,
            status: .confirmed,
            conflictReason: nil,
            message: message,
            nextStep: nextStep
        )
    }

    private func needsReviewResult(_ mutation: MobileOfflineMutation) -> MobileOfflineReplayResult {
        let message: String
        let nextStep: String
        switch mutation.kind {
        case .guardianApproval:
            message = "审批草稿已上传，需家长联网二次确认才生效"
            nextStep = "等家长联网确认后裁决才落定"
        case .relativeComment:
            message = "留言已上传，需家长审核后才对亲友可见"
            nextStep = "等家长审核通过即可显示"
        case .rewardRequest:
            message = "成长积分兑换请求已上传，需家长开启才生效，不解锁、不扣成长积分"
            nextStep = "等家长联网开启奖励窗口"
        default:
            message = "已上传，仍需家长处理后才生效"
            nextStep = "等家长处理"
        }
        return MobileOfflineReplayResult(
            clientMutationRef: mutation.clientMutationRef,
            kind: mutation.kind,
            actorRole: mutation.actorRole,
            status: .needsGuardianReview,
            conflictReason: nil,
            message: message,
            nextStep: nextStep
        )
    }

    private func conflictResult(
        _ mutation: MobileOfflineMutation,
        reason: MobileOfflineConflictReason,
        rolledBack: Bool
    ) -> MobileOfflineReplayResult {
        MobileOfflineReplayResult(
            clientMutationRef: mutation.clientMutationRef,
            kind: mutation.kind,
            actorRole: mutation.actorRole,
            status: rolledBack ? .rolledBack : .conflict,
            conflictReason: reason,
            message: reason.hint,
            nextStep: reason.nextStep
        )
    }
}

// MARK: - 类型的家长闸门标记

extension MobileOfflineMutationKind {
    /// 该类型是否必须经过「家长闸门」，因此**永远不能被本地重放直接 confirmed/落定**。
    ///
    /// - 审批草稿：联网后仍需家长/服务端二次确认。
    /// - 亲友评论：需家长审核后才可见，绝不直接公开。
    /// - 成长积分兑换请求：需家长开启，孩子不能借此自助发成长积分/解锁设备。
    ///
    /// 任务/作业提交与设备回执不带闸门：confirmed 仅表示「已收到」，下游仍各自走验证。
    var requiresGuardianGate: Bool {
        switch self {
        case .guardianApproval, .relativeComment, .rewardRequest:
            return true
        case .childTaskSubmission, .schoolHomeworkSubmission, .deviceReceipt:
            return false
        }
    }
}

// MARK: - 重放协调 store（@Observable，供 UI 持有）

/// 把重放引擎包成可观察 store：持有最近一次重放报告，并在重放时把冲突/回滚**回填**进
/// `MobileOfflineOutboxStore`，保证 outbox 的 `publicStatus` / `conflictHints` 与重放结果一致。
///
/// 回填只写 outbox 已有的两种「非落定」态（conflict / rolledBack）。confirmed 与
/// needsGuardianReview **不回填**为任何业务终态——outbox 在设计上永不落定，这两态只活在
/// 重放报告里供 UI 展示。
@Observable
final class MobileOfflineReplayStore {
    private(set) var report: MobileOfflineReplayReport
    @ObservationIgnored private let engine = MobileOfflineReplayEngine()

    init(report: MobileOfflineReplayReport = .empty) {
        self.report = report
    }

    /// 是否已经跑过重放。
    var hasReplayed: Bool { !report.isEmpty }

    /// 对一个 outbox 跑一次本地 mock 重放，回填冲突/回滚，并保存报告。
    @discardableResult
    func replay(
        outbox: MobileOfflineOutboxStore,
        directive: MobileOfflineReplayDirective = .allClear
    ) -> MobileOfflineReplayReport {
        let report = engine.replay(mutations: outbox.mutations, directive: directive)
        for result in report.results {
            switch result.status {
            case .conflict:
                outbox.markConflict(
                    clientMutationRef: result.clientMutationRef,
                    reason: result.conflictReason ?? .alreadyResolved
                )
            case .rolledBack:
                outbox.rollback(
                    clientMutationRef: result.clientMutationRef,
                    reason: result.conflictReason ?? .supersededByGuardian
                )
            case .confirmed, .needsGuardianReview:
                // 不落定：这两态只活在重放报告里。
                break
            }
        }
        self.report = report
        return report
    }

    /// 清空重放报告（回到「未重放」）。
    func reset() {
        report = .empty
    }
}
