import Foundation

/// 家庭端展示用文案。
///
/// 聚合快照里的 finding / risk code 是给测试、控制台和发布质量门使用的机器码；
/// 手机端家庭用户默认只看人话，原始 code 只放进开发者信息。
enum MobilePlatformAggregateUserFacingCopy {
    static func statusLabel(
        for status: MobilePlatformAggregateStatus,
        role: MobilePlatformAggregateViewerRole
    ) -> String {
        switch (status, role) {
        case (.blocked, .child):
            return "需要大人帮忙"
        case (.blocked, .guardian):
            return "有事项需要处理"
        case (.blocked, .teacher):
            return "有事项待协同"
        case (.blocked, .relative):
            return "仅显示可见事项"
        case (.reviewRequired, .guardian):
            return "等待家长复核"
        case (.reviewRequired, .teacher):
            return "等待协同复核"
        case (.offlineConflict, .child):
            return "同步中"
        case (.offlineConflict, .guardian):
            return "有离线记录待复核"
        case (.privateOnly, _):
            return "仅家庭可见"
        default:
            return status.label
        }
    }

    static func riskTitle(for risk: MobilePlatformAggregateRiskFlag) -> String {
        if let mapped = title(forCode: risk.code) {
            return mapped
        }

        switch risk.source {
        case .growthPack:
            return "成长包需要复核"
        case .schoolHomework:
            return "学校作业联动需要复核"
        case .familyAchievement:
            return "家庭成长记录需要复核"
        case .creditReward:
            return "成长积分奖励需要复核"
        case .offlineSync:
            return "离线同步需要复核"
        case .roleBoundary:
            return "角色可见性已保护"
        }
    }

    static func riskDetail(for risk: MobilePlatformAggregateRiskFlag) -> String {
        if let mapped = detail(forCode: risk.code) {
            return "\(risk.source.label) · \(mapped)"
        }
        return "\(risk.source.label) · \(risk.severity.label)"
    }

    static func findingTitle(for finding: MobilePlatformAggregateFinding) -> String {
        title(forCode: finding.code.rawValue) ?? "平台总览提示"
    }

    static func findingDetail(for finding: MobilePlatformAggregateFinding) -> String {
        if let mapped = detail(forCode: finding.code.rawValue) {
            return mapped
        }
        return finding.message
    }

    static func developerCodeLabel(_ code: String) -> String {
        "开发者代码：\(code)"
    }

    private static func title(forCode code: String) -> String? {
        switch normalized(code) {
        case "PLATFORM_SNAPSHOT_OK", "DETAIL_SNAPSHOT_OK", "SCHOOL_CREDIT_SNAPSHOT_OK", "CREDIT_LEDGER_REVIEW_OK":
            return "快照检查通过"
        case "ROLE_VISIBILITY_APPLIED":
            return "已按当前角色裁剪可见内容"
        case "UPSTREAM_BLOCKED":
            return "上游模块还有待处理事项"
        case "PENDING_REVIEW_ACTIVE":
            return "存在待复核事项"
        case "OFFLINE_SYNC_ACTIVE", "OFFLINE_SYNC_ACTION_REQUIRED", "OFFLINE_CONFLICT_ACTIVE", "OFFLINE_CONFLICT_REVIEW", "OFFLINE_REPLAY_BLOCKED":
            return "离线同步需要复核"
        case "CREDIT_REWARD_NOT_USABLE", "CREDIT_NOT_USABLE":
            return "成长积分暂不可用于奖励"
        case "PUBLIC_OR_RELATIVE_PRIVATE_LEAK_BLOCKED", "PUBLIC_SUMMARY_LEAK", "UPSTREAM_LEAK", "UNSAFE_PAYLOAD":
            return "隐私保护已拦截敏感内容"
        case "RUNTIME_PLAN_BLOCKED":
            return "成长包执行计划需要复核"
        case "SETTLEMENT_BLOCKED":
            return "成长积分结算暂时冻结"
        case "APPEAL_REVIEW_REQUIRED", "APPEAL_OR_FREEZE_ACTIVE", "REVIEW_REQUIRED_PRESENT", "CONFLICT_REVIEW_REQUIRED":
            return "有申诉或冲突需要复核"
        case "RELATIVE_REVIEW_HIDDEN_FROM_CHILD", "NON_GUARDIAN_DETAIL_HIDDEN", "RELATIVE_PRIVATE_REVIEW_HIDDEN":
            return "亲友或非家长信息已隐藏"
        case "TEACHER_GUARDIAN_CONFLICT":
            return "老师和家长确认结果不一致"
        case "SCHOOL_HOMEWORK_BLOCKED":
            return "学校作业联动暂时阻断"
        case "AI_DIRECT_ANSWER_BLOCKED":
            return "AI 已阻止直接给作业答案"
        case "GROWTH_PACK_INSTALL_ATTENTION":
            return "成长包安装权益需要家长关注"
        case "DUPLICATE_IDEMPOTENCY":
            return "重复记录已被拦截"
        case "EXPIRED_HOLD":
            return "有过期冻结记录需要处理"
        case "DEVICE_FAILURE_REFUND_REVIEW":
            return "设备执行失败，需要复核退款或补偿"
        case "REVOKED_ACTION_BLOCKED":
            return "已撤销动作被拦截"
        case "CROSS_CHILD_FAMILY_MISMATCH":
            return "孩子与家庭记录不匹配"
        case "RELATIVE_ENCOURAGEMENT_REVIEW_REQUIRED":
            return "亲友鼓励需要家长复核"
        case "ROLLBACK_REQUIRED":
            return "需要回滚复核"
        case "INVALID_AMOUNT":
            return "成长积分金额异常"
        case "MISSING_RELATED_HOLD":
            return "缺少对应冻结记录"
        case "BLOCKED_PRESENT":
            return "存在阻断项"
        case "FEED":
            return "成长动态需要复核"
        case "EVIDENCE":
            return "成长证明需要复核"
        case "BADGECARDSTORYLINE", "BADGE_CARD_STORYLINE":
            return "徽章故事线需要复核"
        case "ABILITYCARD", "ABILITY_CARD":
            return "成长卡片需要复核"
        case "HONORWALL", "HONOR_WALL":
            return "荣誉墙内容需要复核"
        default:
            return nil
        }
    }

    private static func detail(forCode code: String) -> String? {
        switch normalized(code) {
        case "ROLE_VISIBILITY_APPLIED":
            return "当前页面只显示这个角色可以看的内容。"
        case "UPSTREAM_BLOCKED":
            return "相关上游模块还有阻断项，先处理后才能继续流转。"
        case "PENDING_REVIEW_ACTIVE":
            return "有内容需要家长、老师或授权角色确认。"
        case "RUNTIME_PLAN_BLOCKED":
            return "成长包的执行计划还没有满足继续条件。"
        case "SETTLEMENT_BLOCKED":
            return "成长积分结算暂时冻结，避免错误发放奖励。"
        case "CREDIT_NOT_USABLE", "CREDIT_REWARD_NOT_USABLE":
            return "这些成长积分目前只作预览，暂不能直接兑换奖励。"
        case "TEACHER_GUARDIAN_CONFLICT":
            return "老师验证和家长确认不一致，需要人工复核。"
        case "SCHOOL_HOMEWORK_BLOCKED":
            return "学校作业与成长任务联动暂时停止，避免错误计分。"
        case "AI_DIRECT_ANSWER_BLOCKED":
            return "AI 不会直接给孩子作业答案，只能一步步引导。"
        case "PUBLIC_SUMMARY_LEAK", "PUBLIC_OR_RELATIVE_PRIVATE_LEAK_BLOCKED", "UPSTREAM_LEAK", "UNSAFE_PAYLOAD":
            return "系统检测到可能暴露隐私的信息，已进入保护状态。"
        case "GROWTH_PACK_INSTALL_ATTENTION":
            return "有成长包安装、冻结或权益项需要家长确认。"
        default:
            return nil
        }
    }

    private static func normalized(_ code: String) -> String {
        code
            .replacingOccurrences(of: "-", with: "_")
            .uppercased()
    }
}
