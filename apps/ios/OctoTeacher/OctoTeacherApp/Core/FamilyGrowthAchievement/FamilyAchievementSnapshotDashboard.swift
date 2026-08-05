import Foundation

/// B32 family-growth-achievement-snapshot-contract 在 iOS 本地壳里的快照仪表盘投影。
///
/// 该层只读聚合 `FamilyGrowthAchievementStore` 的本地 mock 数据，不发布动态、不授徽章、
/// 不改能力卡、不写成长积分账本、不上传媒体、不通知亲友、不解锁设备。
struct FamilyAchievementSnapshotDashboard: Equatable {
    var role: FamilyGrowthViewerRole
    var status: FamilyAchievementSnapshotStatus
    var generatedLabel: String
    var familyPublicRef: String
    var childPublicRef: String
    var evidence: FamilyAchievementEvidenceSnapshot
    var badgeSummary: FamilyAchievementCountSummary
    var abilityCardSummary: FamilyAchievementAbilityCardSummary
    var honorSummary: FamilyAchievementCountSummary
    var storylineSummary: FamilyAchievementCountSummary
    var relativeParticipation: FamilyAchievementRelativeParticipation
    var riskFlags: [FamilyAchievementRiskFlag]
    var nextActions: [FamilyAchievementNextAction]
    var publicSummary: FamilyAchievementPublicSummary

    var hasActionableGuardianWork: Bool {
        nextActions.contains { $0.actionRequired }
    }
}

enum FamilyAchievementSnapshotStatus: String, Equatable {
    case ready
    case reviewRequired
    case blocked
    case privateOnly

    var label: String {
        switch self {
        case .ready: return "可展示"
        case .reviewRequired: return "待家长复核"
        case .blocked: return "已阻断"
        case .privateOnly: return "仅家庭可见"
        }
    }
}

struct FamilyAchievementEvidenceSnapshot: Equatable {
    var visibleAchievementCount: Int
    var formalHonorCount: Int
    var reviewRequiredCount: Int
    var blockedCount: Int
    var withdrawnCount: Int
    var publicReadyCount: Int
    var writesLedger: Bool = false
    var modifiesHomework: Bool = false
}

struct FamilyAchievementCountSummary: Equatable {
    var title: String
    var itemCount: Int
    var verifiedCount: Int
    var reviewRequiredCount: Int
    var blockedCount: Int
    var sideEffectFree: Bool = true
}

struct FamilyAchievementAbilityCardSummary: Equatable {
    var cardCount: Int
    var dimensionScoreCount: Int
    var averageScore: Int?
    var warningCount: Int
    var updatesAbilityCard: Bool = false
}

struct FamilyAchievementRelativeParticipation: Equatable {
    var canSeeParticipation: Bool
    var approvedCommentCount: Int
    var pendingCommentCount: Int
    var blockedActionCount: Int
    var viewerRelativePublicRef: String?
    var notifiesRelatives: Bool = false
}

struct FamilyAchievementRiskFlag: Identifiable, Equatable {
    var id: String
    var source: FamilyAchievementRiskSource
    var severity: FamilyAchievementRiskSeverity
    var title: String
}

enum FamilyAchievementRiskSource: String, Equatable {
    case feed
    case evidence
    case badgeCardStoryline
    case abilityCard
    case honorWall

    var label: String {
        switch self {
        case .feed: return "动态"
        case .evidence: return "证据"
        case .badgeCardStoryline: return "徽章/故事线"
        case .abilityCard: return "成长球星卡"
        case .honorWall: return "荣誉墙"
        }
    }
}

enum FamilyAchievementRiskSeverity: String, Equatable {
    case info
    case warning
    case blocker

    var label: String {
        switch self {
        case .info: return "提示"
        case .warning: return "需复核"
        case .blocker: return "阻断"
        }
    }
}

struct FamilyAchievementNextAction: Identifiable, Equatable {
    var id: String
    var kind: FamilyAchievementNextActionKind
    var title: String
    var severity: FamilyAchievementRiskSeverity
    var actionRequired: Bool
}

enum FamilyAchievementNextActionKind: String, Equatable {
    case approveRelativeComment
    case reviewPendingAchievement
    case reviewBlockedContent
    case readOnly
}

struct FamilyAchievementPublicSummary: Equatable {
    var status: FamilyAchievementSnapshotStatus
    var achievementCount: Int
    var publicReadyCount: Int
    var reviewRequiredCount: Int
    var riskCount: Int
    var grantsBadge: Bool = false
    var updatesAbilityCard: Bool = false
    var publishesHonorWall: Bool = false
    var emitsEvent: Bool = false
    var writesLedger: Bool = false
    var modifiesTaskState: Bool = false
    var modifiesHomework: Bool = false
    var uploadsMedia: Bool = false
    var sendsNotification: Bool = false
    var notifiesRelatives: Bool = false
    var unlocksDevice: Bool = false
}

struct FamilyAchievementSnapshotDashboardBuilder {
    var store: FamilyGrowthAchievementStore
    var generatedLabel: String = "本地快照"

    init(store: FamilyGrowthAchievementStore = FamilyGrowthAchievementStore()) {
        self.store = store
    }

    func dashboard(for role: FamilyGrowthViewerRole) -> FamilyAchievementSnapshotDashboard {
        let summary = store.summary(for: role)
        let visible = summary.cards
        let allCards = store.cards
        let guardianCanReview = role == .guardian
        let evidence = evidenceSnapshot(visible: visible, allCards: allCards, guardianCanReview: guardianCanReview)
        let risks = riskFlags(for: role, allCards: allCards)
        let status = statusFor(role: role, visible: visible, evidence: evidence, risks: risks)
        let actions = nextActions(for: role, allCards: allCards, risks: risks)
        let publicSummary = FamilyAchievementPublicSummary(
            status: status,
            achievementCount: visible.count,
            publicReadyCount: visible.filter { $0.visibility == .publicShare && $0.lifecycle == .published }.count,
            reviewRequiredCount: evidence.reviewRequiredCount,
            riskCount: risks.count
        )

        return FamilyAchievementSnapshotDashboard(
            role: role,
            status: status,
            generatedLabel: generatedLabel,
            familyPublicRef: summary.familyPublicRef,
            childPublicRef: summary.childPublicRef,
            evidence: evidence,
            badgeSummary: countSummary(title: "徽章", kind: .badge, visible: visible),
            abilityCardSummary: abilityCardSummary(visible: visible),
            honorSummary: countSummary(title: "荣誉墙", kind: .honorWall, visible: visible),
            storylineSummary: countSummary(title: "故事线", kind: .storyline, visible: visible),
            relativeParticipation: relativeParticipation(for: role, allCards: allCards),
            riskFlags: risks,
            nextActions: actions,
            publicSummary: publicSummary
        )
    }

    private func evidenceSnapshot(
        visible: [FamilyGrowthCard],
        allCards: [FamilyGrowthCard],
        guardianCanReview: Bool
    ) -> FamilyAchievementEvidenceSnapshot {
        FamilyAchievementEvidenceSnapshot(
            visibleAchievementCount: visible.count,
            formalHonorCount: visible.filter(\.isFormalHonor).count,
            reviewRequiredCount: guardianCanReview ? allCards.filter { $0.lifecycle == .pending }.count : 0,
            blockedCount: guardianCanReview ? allCards.filter { $0.lifecycle == .blocked }.count : 0,
            withdrawnCount: guardianCanReview ? allCards.filter { $0.lifecycle == .withdrawn }.count : 0,
            publicReadyCount: visible.filter { $0.visibility == .publicShare && $0.lifecycle == .published }.count
        )
    }

    private func countSummary(
        title: String,
        kind: FamilyGrowthCardKind,
        visible: [FamilyGrowthCard]
    ) -> FamilyAchievementCountSummary {
        let cards = visible.filter { $0.kind == kind }
        return FamilyAchievementCountSummary(
            title: title,
            itemCount: cards.count,
            verifiedCount: cards.filter(\.isFormalHonor).count,
            reviewRequiredCount: cards.filter { $0.lifecycle == .pending || $0.lifecycle == .withdrawn }.count,
            blockedCount: cards.filter { $0.lifecycle == .blocked }.count
        )
    }

    private func abilityCardSummary(visible: [FamilyGrowthCard]) -> FamilyAchievementAbilityCardSummary {
        let cards = visible.filter { $0.kind == .growthCard }
        let scoreValues = cards.flatMap { card in
            card.ratings.map { Array($0.values) } ?? []
        }
        let average = scoreValues.isEmpty ? nil : scoreValues.reduce(0, +) / scoreValues.count
        return FamilyAchievementAbilityCardSummary(
            cardCount: cards.count,
            dimensionScoreCount: scoreValues.count,
            averageScore: average,
            warningCount: cards.filter { $0.lifecycle != .published }.count
        )
    }

    private func relativeParticipation(
        for role: FamilyGrowthViewerRole,
        allCards: [FamilyGrowthCard]
    ) -> FamilyAchievementRelativeParticipation {
        let relativeCards = allCards.filter { $0.kind == .relativeComment }
        let canSeeApproved = role == .guardian || role == .relative
        let guardianCanReview = role == .guardian
        return FamilyAchievementRelativeParticipation(
            canSeeParticipation: canSeeApproved,
            approvedCommentCount: canSeeApproved ? relativeCards.filter { $0.lifecycle == .published }.reduce(0) { $0 + $1.approvedCommentCount } : 0,
            pendingCommentCount: guardianCanReview ? relativeCards.filter { $0.lifecycle == .pending }.count : 0,
            blockedActionCount: guardianCanReview ? relativeCards.filter { $0.lifecycle == .blocked || $0.lifecycle == .withdrawn }.count : 0,
            viewerRelativePublicRef: role == .relative ? FamilyGrowthRedaction.publicRef(prefix: "relative", source: "relative-self") : nil
        )
    }

    private func riskFlags(
        for role: FamilyGrowthViewerRole,
        allCards: [FamilyGrowthCard]
    ) -> [FamilyAchievementRiskFlag] {
        guard role == .guardian else { return [] }
        var flags: [FamilyAchievementRiskFlag] = []
        let pendingCount = allCards.filter { $0.lifecycle == .pending }.count
        if pendingCount > 0 {
            flags.append(risk("pending", source: .feed, severity: .warning, title: "有 \(pendingCount) 条成长内容待家长复核。"))
        }
        let blockedCount = allCards.filter { $0.lifecycle == .blocked }.count
        if blockedCount > 0 {
            flags.append(risk("blocked", source: .evidence, severity: .blocker, title: "有 \(blockedCount) 条内容被安全边界阻断。"))
        }
        let withdrawnCount = allCards.filter { $0.lifecycle == .withdrawn }.count
        if withdrawnCount > 0 {
            flags.append(risk("withdrawn", source: .honorWall, severity: .warning, title: "有 \(withdrawnCount) 条内容已撤回，不进入公开荣誉。"))
        }
        return flags
    }

    private func nextActions(
        for role: FamilyGrowthViewerRole,
        allCards: [FamilyGrowthCard],
        risks: [FamilyAchievementRiskFlag]
    ) -> [FamilyAchievementNextAction] {
        if role != .guardian {
            return [
                action("read-only-\(role.rawValue)", kind: .readOnly, title: "当前视图只读，不会审批、发成长积分或发布荣誉。", severity: .info, required: false)
            ]
        }

        var actions: [FamilyAchievementNextAction] = []
        if allCards.contains(where: { $0.kind == .relativeComment && $0.lifecycle == .pending }) {
            actions.append(action("approve-relative", kind: .approveRelativeComment, title: "复核亲友鼓励后再决定是否展示。", severity: .warning, required: true))
        }
        if allCards.contains(where: { $0.lifecycle == .pending }) {
            actions.append(action("review-pending", kind: .reviewPendingAchievement, title: "复核待审核成长内容，避免提前成为正式荣誉。", severity: .warning, required: true))
        }
        if risks.contains(where: { $0.severity == .blocker }) {
            actions.append(action("review-blocked", kind: .reviewBlockedContent, title: "查看已阻断内容的脱敏说明，必要时和孩子沟通。", severity: .blocker, required: true))
        }
        if actions.isEmpty {
            actions.append(action("read-only-guardian", kind: .readOnly, title: "快照已可展示，当前页面仍只读。", severity: .info, required: false))
        }
        return actions
    }

    private func statusFor(
        role: FamilyGrowthViewerRole,
        visible: [FamilyGrowthCard],
        evidence: FamilyAchievementEvidenceSnapshot,
        risks: [FamilyAchievementRiskFlag]
    ) -> FamilyAchievementSnapshotStatus {
        if risks.contains(where: { $0.severity == .blocker }) { return .blocked }
        if role == .guardian && (evidence.reviewRequiredCount > 0 || evidence.withdrawnCount > 0) { return .reviewRequired }
        if visible.isEmpty { return .privateOnly }
        return .ready
    }

    private func risk(
        _ idSeed: String,
        source: FamilyAchievementRiskSource,
        severity: FamilyAchievementRiskSeverity,
        title: String
    ) -> FamilyAchievementRiskFlag {
        FamilyAchievementRiskFlag(
            id: FamilyGrowthRedaction.publicRef(prefix: "risk", source: idSeed),
            source: source,
            severity: severity,
            title: title
        )
    }

    private func action(
        _ idSeed: String,
        kind: FamilyAchievementNextActionKind,
        title: String,
        severity: FamilyAchievementRiskSeverity,
        required: Bool
    ) -> FamilyAchievementNextAction {
        FamilyAchievementNextAction(
            id: FamilyGrowthRedaction.publicRef(prefix: "action", source: idSeed),
            kind: kind,
            title: title,
            severity: severity,
            actionRequired: required
        )
    }
}
