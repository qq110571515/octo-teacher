import Foundation

/// 离线动作组装器：把各页面的领域操作统一翻译成脱敏的 `MobileOfflineMutationRequest`。
///
/// 这是一个**纯逻辑层**（无 SwiftUI、无副作用、可在无界面环境测试），唯一职责是：
///
/// - 把内部标识（taskId / homeworkId / assignmentId / childId / commandId 等）通过稳定哈希
///   折叠成脱敏公开引用，**绝不**把原始 ID、token、路径、局域网地址写进请求；
/// - 为每类入口生成正确的 `kind` + `actorRole`（授权矩阵仍在 outbox 侧二次收口）；
/// - 用安全的中文摘要 + 稳定幂等键，保证同一逻辑动作重复触发是**幂等重放**而非重复入队。
///
/// 组装器只生产请求，**绝不入队、绝不落定**：入队、冲突/回滚裁决和脱敏守卫仍由
/// `MobileOfflineOutboxStore` 负责。页面拿到请求后只把它交给 outbox，不真实写成长积分账本、
/// 审批终态、学校验证、家庭动态或设备控制。
struct MobileOfflineActionComposer {
    /// 入队时间戳（可注入，便于确定性测试）。
    var enqueuedAt: String

    init(enqueuedAt: String = "2026-06-23T21:00:00Z") {
        self.enqueuedAt = enqueuedAt
    }

    /// 家长审批草稿的本地裁决意向。
    ///
    /// 注意：这只是「草稿」。离线壳永远不会因为有了草稿就把审批落定为终态——草稿入队后
    /// 仍停在 `pending`，最终仍需联网由服务端/家长流程确认。
    enum ApprovalDraftDecision: String, Equatable, CaseIterable {
        case approve
        case reject

        var summaryLabel: String {
            switch self {
            case .approve: return "建议通过"
            case .reject: return "建议驳回"
            }
        }
    }

    // MARK: - 六类入口

    /// 孩子任务提交：把一条本地任务证明排进离线队列，等家长/老师联网验证。
    func childTaskSubmission(taskSeed: String, proofKindLabel: String) -> MobileOfflineMutationRequest {
        request(
            kind: .childTaskSubmission,
            actorRole: .child,
            actorSeed: "child",
            subjectPrefix: "task",
            subjectSeed: taskSeed,
            summary: "任务证明待同步（\(proofKindLabel)）",
            idempotencySeed: taskSeed
        )
    }

    /// 学校作业提交：把一条作业证明排进离线队列，等老师/家长联网验证。
    func schoolHomeworkSubmission(homeworkSeed: String, subjectLabel: String) -> MobileOfflineMutationRequest {
        request(
            kind: .schoolHomeworkSubmission,
            actorRole: .child,
            actorSeed: "child",
            subjectPrefix: "homework",
            subjectSeed: homeworkSeed,
            summary: "\(subjectLabel)作业证明待同步",
            idempotencySeed: homeworkSeed
        )
    }

    /// 家长审批草稿：家长在离线态记录一条裁决意向，**只入队不落定**，联网后仍需确认。
    func guardianApprovalDraft(submissionSeed: String, decision: ApprovalDraftDecision) -> MobileOfflineMutationRequest {
        request(
            kind: .guardianApproval,
            actorRole: .guardian,
            actorSeed: "guardian",
            subjectPrefix: "submission",
            subjectSeed: submissionSeed,
            summary: "审批草稿待同步：\(decision.summaryLabel)（联网后才生效）",
            // approve / reject 草稿视为两个独立逻辑动作，互不覆盖、各自幂等。
            idempotencySeed: "\(submissionSeed):\(decision.rawValue)"
        )
    }

    /// 亲友评论：亲友留一句鼓励，**只入队待家长审核**，不发成长积分、不解锁设备、不直接可见。
    func relativeComment(targetSeed: String, relativeSeed: String, message: String) -> MobileOfflineMutationRequest {
        request(
            kind: .relativeComment,
            actorRole: .relative,
            actorSeed: relativeSeed,
            subjectPrefix: "feed",
            subjectSeed: targetSeed,
            summary: message,
            idempotencySeed: "\(targetSeed):\(relativeSeed):\(message)"
        )
    }

    /// 成长积分兑换请求：孩子发起「想用 N 成长积分换屏幕时间」的请求，**只入队待家长开启**，本地不发放、不解锁。
    func rewardRequest(childSeed: String, minutes: Int) -> MobileOfflineMutationRequest {
        request(
            kind: .rewardRequest,
            actorRole: .child,
            actorSeed: childSeed,
            subjectPrefix: "reward",
            subjectSeed: "\(childSeed):\(minutes)",
            summary: "申请 \(minutes) 成长积分兑换，待家长开启",
            idempotencySeed: "\(childSeed):\(minutes)"
        )
    }

    /// 设备回执：设备侧对一条会话命令的本地确认，**只记录不代表真实解锁**。
    func deviceReceipt(commandSeed: String, grantedMinutes: Int) -> MobileOfflineMutationRequest {
        request(
            kind: .deviceReceipt,
            actorRole: .device,
            actorSeed: "device",
            subjectPrefix: "command",
            subjectSeed: commandSeed,
            summary: "本机回执：本次会话 \(grantedMinutes) 分钟（仅确认，不代表真实解锁设备）",
            idempotencySeed: commandSeed
        )
    }

    // MARK: - 组装与脱敏

    private func request(
        kind: MobileOfflineMutationKind,
        actorRole: MobileOfflineActorRole,
        actorSeed: String,
        subjectPrefix: String,
        subjectSeed: String,
        summary: String,
        idempotencySeed: String
    ) -> MobileOfflineMutationRequest {
        MobileOfflineMutationRequest(
            kind: kind,
            actorRole: actorRole,
            actorPublicRef: redactedRef(prefix: "actor", seed: "\(actorRole.rawValue):\(actorSeed)"),
            subjectPublicRef: redactedRef(prefix: subjectPrefix, seed: subjectSeed),
            summary: summary,
            // 幂等键也经过哈希，绝不携带原始 ID；同一逻辑动作 → 同一键 → 幂等重放。
            idempotencyKey: redactedRef(prefix: "idem", seed: "\(kind.rawValue):\(idempotencySeed)"),
            declaredEffect: .localQueueOnly,
            enqueuedAt: enqueuedAt
        )
    }

    /// 把任意内部 seed 折叠成 `prefix-<hash>` 形式的脱敏公开引用。
    private func redactedRef(prefix: String, seed: String) -> String {
        "\(prefix)-\(Self.stableHash(seed))"
    }

    /// 与 `MobileOfflineOutboxStore.stableLocalRef` 同款 djb2 稳定哈希：跨进程确定，
    /// 不可逆推回原始 ID，便于测试断言。
    private static func stableHash(_ source: String) -> String {
        var hash = 5381
        for scalar in source.unicodeScalars {
            hash = ((hash << 5) &+ hash) ^ Int(scalar.value)
        }
        return String(UInt(bitPattern: hash), radix: 36)
    }
}

// MARK: - 入队反馈

extension MobileOfflineError {
    /// 面向用户的脱敏中文提示。绝不回显原始负载或内部标识。
    var localizedHint: String {
        switch self {
        case .permissionDenied: return "当前角色无权发起该离线动作"
        case .unsafePayload: return "内容包含敏感信息，未加入离线队列"
        case .forbiddenEffect: return "离线动作不能直接发成长积分或解锁设备"
        case .duplicateReplay: return "已有同名但内容不同的请求，请勿重复提交"
        case .emptyIdentifier: return "信息不完整，未加入离线队列"
        case .mutationNotFound: return "找不到对应的离线动作"
        }
    }
}

/// 把 outbox 的入队结果翻译成一句本地状态提示，供各页面统一展示。
enum MobileOfflineEnqueueFeedback {
    static func message(
        for result: Result<MobileOfflineMutation, MobileOfflineError>,
        successText: String
    ) -> String {
        switch result {
        case .success: return successText
        case .failure(let error): return error.localizedHint
        }
    }
}
