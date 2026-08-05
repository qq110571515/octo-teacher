import Foundation

/// 家庭荣誉墙与成长故事线的同意入口快照。
///
/// 这一层只读 `FamilyGrowthAchievementStore` 的本地荣誉卡片，将 B48「家庭荣誉墙同意与
/// 故事线契约」投影到 iOS：家庭私密、亲友可见、公开脱敏三层展示；待审核、撤回、阻断
/// 不对亲友或公开访客可见；公开层只保留脱敏摘要。
///
/// 安全边界：不发布、不通知、不上传媒体、不写成长积分账本、不授徽章、不解锁设备、不调用 AI。
enum FamilyHonorStorylineConsentViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case relative
    case publicViewer

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        case .publicViewer: return "公开访客"
        }
    }

    var isHousehold: Bool {
        self == .child || self == .guardian
    }

    var canSeeConsentControls: Bool {
        self == .guardian
    }

    var audienceNote: String {
        switch self {
        case .child:
            return "孩子看到鼓励式成长记录，不展示成人审核内部原因。"
        case .guardian:
            return "家长可见全部层级、同意状态、撤回传播和阻断项。"
        case .relative:
            return "亲友只读，只看已通过且被授权的家庭/亲友层内容。"
        case .publicViewer:
            return "公开访客只看已通过的公开脱敏摘要。"
        }
    }
}

enum FamilyHonorStorylineLayer: String, CaseIterable, Equatable {
    case privateFamily
    case relativeVisible
    case publicRedacted

    var label: String {
        switch self {
        case .privateFamily: return "家庭私密"
        case .relativeVisible: return "亲友可见"
        case .publicRedacted: return "公开脱敏"
        }
    }

    var systemImage: String {
        switch self {
        case .privateFamily: return "lock.shield"
        case .relativeVisible: return "person.2"
        case .publicRedacted: return "globe.badge.chevron.backward"
        }
    }

    var sortOrder: Int {
        switch self {
        case .privateFamily: return 0
        case .relativeVisible: return 1
        case .publicRedacted: return 2
        }
    }
}

enum FamilyHonorStorylineConsentState: String, Equatable {
    case ready
    case needsGuardianConsent
    case withdrawn
    case frozen
    case blocked

    var label: String {
        switch self {
        case .ready: return "同意已就绪"
        case .needsGuardianConsent: return "待家长同意"
        case .withdrawn: return "已撤回传播"
        case .frozen: return "申诉冻结"
        case .blocked: return "内容阻断"
        }
    }

    var systemImage: String {
        switch self {
        case .ready: return "checkmark.seal"
        case .needsGuardianConsent: return "person.crop.circle.badge.questionmark"
        case .withdrawn: return "arrow.uturn.backward"
        case .frozen: return "pause.circle"
        case .blocked: return "exclamationmark.shield"
        }
    }

    var isVisibleOutsideHousehold: Bool {
        self == .ready
    }
}

enum FamilyStorylineReleaseGateStatus: String, Equatable {
    case ready
    case manualGate
    case blocked

    var label: String {
        switch self {
        case .ready: return "可生成预览"
        case .manualGate: return "需要人工确认"
        case .blocked: return "暂不可发布"
        }
    }
}

enum FamilyStorylineReleaseGateReason: String, Equatable {
    case guardianConsent
    case childAssent
    case revocationPropagation
    case sourceEntry

    var label: String {
        switch self {
        case .guardianConsent: return "监护人同意"
        case .childAssent: return "孩子意愿"
        case .revocationPropagation: return "撤回传播"
        case .sourceEntry: return "故事来源"
        }
    }
}

struct FamilyStorylineReleaseGate: Equatable {
    var status: FamilyStorylineReleaseGateStatus
    var primaryReason: FamilyStorylineReleaseGateReason
    var title: String
    var guardianSummary: String
    var childCopy: String
    var nextAction: String
    var readySourceCount: Int
    var manualGateCount: Int
    var blockedCount: Int
    var publishCandidateCount: Int
    var evidenceChecklist: [FamilyStorylineReleaseEvidence]
    var writesStoryline: Bool = false
    var publishesHonorWall: Bool = false
    var notifiesRelatives: Bool = false
    var grantsCredit: Bool = false
    var awardsBadges: Bool = false
    var unlocksDevice: Bool = false
    var callsNetwork: Bool = false
    var callsAIProvider: Bool = false
}

struct FamilyStorylineReleaseEvidence: Identifiable, Equatable {
    var id: String { publicEvidenceRef }
    var publicEvidenceRef: String
    var title: String
    var status: FamilyStorylineReleaseGateStatus
    var summary: String
}

struct FamilyHonorStorylineConsentNode: Identifiable, Equatable {
    var id: String { publicNodeRef }
    var publicNodeRef: String
    var sourceCardPublicRef: String
    var kind: FamilyGrowthCardKind
    var title: String
    var summary: String
    var supportiveCopy: String
    var nextStep: String
    var occurredLabel: String
    var layer: FamilyHonorStorylineLayer
    var lifecycle: FamilyGrowthLifecycle
    var consentState: FamilyHonorStorylineConsentState
    var visibilityLabel: String
    var showsConsentControls: Bool
    var showsWithdrawalReason: Bool
    var isFormalHonor: Bool
    var tags: [String]
    var reactionCount: Int
    var approvedCommentCount: Int
}

enum FamilyHonorStorylineConsentFindingCode: String, Equatable {
    case guardianConsentRequired
    case withdrawalPropagated
    case frozenOrBlockedHidden
    case relativeBoundaryApplied
    case publicRedactionApplied
    case childFriendlyCopyApplied
    case sideEffectFree

    var label: String {
        switch self {
        case .guardianConsentRequired: return "家长同意门禁"
        case .withdrawalPropagated: return "撤回传播"
        case .frozenOrBlockedHidden: return "冻结/阻断隐藏"
        case .relativeBoundaryApplied: return "亲友边界"
        case .publicRedactionApplied: return "公开脱敏"
        case .childFriendlyCopyApplied: return "孩子友好文案"
        case .sideEffectFree: return "无副作用"
        }
    }
}

struct FamilyHonorStorylineConsentFinding: Identifiable, Equatable {
    var id: String { publicFindingRef }
    var publicFindingRef: String
    var code: FamilyHonorStorylineConsentFindingCode
    var title: String
    var count: Int
    var actionRequired: Bool
}

struct FamilyHonorStorylineConsentPublicSummary: Equatable {
    var role: FamilyHonorStorylineConsentViewerRole
    var visibleNodeCount: Int
    var privateFamilyCount: Int
    var relativeVisibleCount: Int
    var publicRedactedCount: Int
    var hiddenNodeCount: Int
    var findingCount: Int
    var publishesHonorWall: Bool = false
    var mutatesStoryline: Bool = false
    var grantsBadge: Bool = false
    var writesLedger: Bool = false
    var unlocksDevice: Bool = false
    var uploadsMedia: Bool = false
    var sendsNotification: Bool = false
    var callsNetwork: Bool = false
    var callsAIProvider: Bool = false
}

struct FamilyHonorStorylineConsentSnapshot: Equatable {
    var role: FamilyHonorStorylineConsentViewerRole
    var familyPublicRef: String
    var childPublicRef: String
    var headline: String
    var audienceNote: String
    var nodes: [FamilyHonorStorylineConsentNode]
    var hiddenNodeCount: Int
    var releaseGate: FamilyStorylineReleaseGate
    var findings: [FamilyHonorStorylineConsentFinding]
    var publicSummary: FamilyHonorStorylineConsentPublicSummary

    func nodes(in layer: FamilyHonorStorylineLayer) -> [FamilyHonorStorylineConsentNode] {
        nodes.filter { $0.layer == layer }
    }

    var hasUnsafeDisplayPayload: Bool {
        let nodeValues = nodes.flatMap { node in
            [
                node.publicNodeRef,
                node.sourceCardPublicRef,
                node.title,
                node.summary,
                node.supportiveCopy,
                node.nextStep,
                node.occurredLabel,
                node.visibilityLabel,
                node.tags.joined(separator: " ")
            ]
        }
        let findingValues = findings.flatMap { finding in
            [finding.publicFindingRef, finding.title, finding.code.label]
        }
        return MobileSyncPayloadGuard.isUnsafe(
            [familyPublicRef, childPublicRef, headline, audienceNote] + nodeValues + findingValues
        )
    }
}

struct FamilyHonorStorylineConsentBuilder {
    var store: FamilyGrowthAchievementStore

    init(store: FamilyGrowthAchievementStore = FamilyGrowthAchievementStore()) {
        self.store = store
    }

    func snapshot(for role: FamilyHonorStorylineConsentViewerRole) -> FamilyHonorStorylineConsentSnapshot {
        let familyPublicRef = FamilyGrowthRedaction.publicRef(prefix: "family", source: "family-self")
        let childPublicRef = FamilyGrowthRedaction.publicRef(prefix: "child", source: "child-self")
        let sortedCards = store.cards.sorted(by: cardOrder)
        let visibleNodes = sortedCards.compactMap { node(for: $0, role: role) }
        let findings = findings(for: role, allCards: sortedCards, visibleNodes: visibleNodes)
        let counts = layerCounts(nodes: visibleNodes)
        let hiddenCount = sortedCards.count - visibleNodes.count
        let releaseGate = releaseGate(for: role, allCards: sortedCards, visibleNodes: visibleNodes)
        let publicSummary = FamilyHonorStorylineConsentPublicSummary(
            role: role,
            visibleNodeCount: visibleNodes.count,
            privateFamilyCount: counts[.privateFamily, default: 0],
            relativeVisibleCount: counts[.relativeVisible, default: 0],
            publicRedactedCount: counts[.publicRedacted, default: 0],
            hiddenNodeCount: hiddenCount,
            findingCount: findings.count
        )

        return FamilyHonorStorylineConsentSnapshot(
            role: role,
            familyPublicRef: familyPublicRef,
            childPublicRef: childPublicRef,
            headline: "荣誉墙与成长故事线同意入口",
            audienceNote: role.audienceNote,
            nodes: visibleNodes,
            hiddenNodeCount: hiddenCount,
            releaseGate: releaseGate,
            findings: findings,
            publicSummary: publicSummary
        )
    }

    private func node(
        for card: FamilyGrowthCard,
        role: FamilyHonorStorylineConsentViewerRole
    ) -> FamilyHonorStorylineConsentNode? {
        guard isVisible(card: card, to: role) else { return nil }
        let layer = layer(for: card)
        let consentState = consentState(for: card)
        let summary = displaySummary(card: card, role: role)
        let supportiveCopy = safeText(card.supportiveCopy, fallback: "这条成长记录只保留支持性鼓励。")
        let nextStep = safeText(card.nextStep, fallback: "下一步由家庭内部确认后再继续。")

        return FamilyHonorStorylineConsentNode(
            publicNodeRef: FamilyGrowthRedaction.publicRef(
                prefix: "honor-node",
                source: "\(card.publicRef):\(role.rawValue):\(layer.rawValue)"
            ),
            sourceCardPublicRef: card.publicRef,
            kind: card.kind,
            title: displayTitle(card: card, role: role),
            summary: summary,
            supportiveCopy: role == .publicViewer ? "公开层只保留脱敏鼓励摘要。" : supportiveCopy,
            nextStep: role == .publicViewer ? "公开访客不能审批、留言、发成长积分或解锁设备。" : nextStep,
            occurredLabel: safeText(card.occurredLabel, fallback: "近期"),
            layer: layer,
            lifecycle: card.lifecycle,
            consentState: consentState,
            visibilityLabel: layer.label,
            showsConsentControls: role.canSeeConsentControls,
            showsWithdrawalReason: role == .guardian && (card.lifecycle == .withdrawn || card.lifecycle == .blocked),
            isFormalHonor: card.isFormalHonor && consentState.isVisibleOutsideHousehold,
            tags: safeTags(card.tags, role: role),
            reactionCount: role == .publicViewer ? 0 : card.reactionCount,
            approvedCommentCount: role == .publicViewer ? 0 : card.approvedCommentCount
        )
    }

    private func isVisible(card: FamilyGrowthCard, to role: FamilyHonorStorylineConsentViewerRole) -> Bool {
        switch role {
        case .child, .guardian:
            return true
        case .relative:
            guard card.lifecycle == .published else { return false }
            switch card.visibility {
            case .family:
                return true
            case .relatives:
                return card.allowsRelative
            case .privateOnly, .publicShare:
                return false
            }
        case .publicViewer:
            return card.lifecycle == .published && card.visibility == .publicShare
        }
    }

    private func layer(for card: FamilyGrowthCard) -> FamilyHonorStorylineLayer {
        switch card.visibility {
        case .privateOnly:
            return .privateFamily
        case .family, .relatives:
            return .relativeVisible
        case .publicShare:
            return .publicRedacted
        }
    }

    private func consentState(for card: FamilyGrowthCard) -> FamilyHonorStorylineConsentState {
        switch card.lifecycle {
        case .published:
            return .ready
        case .pending:
            return .needsGuardianConsent
        case .withdrawn:
            return .withdrawn
        case .blocked:
            return .blocked
        }
    }

    private func findings(
        for role: FamilyHonorStorylineConsentViewerRole,
        allCards: [FamilyGrowthCard],
        visibleNodes: [FamilyHonorStorylineConsentNode]
    ) -> [FamilyHonorStorylineConsentFinding] {
        var result: [FamilyHonorStorylineConsentFinding] = []
        let pendingCount = allCards.filter { $0.lifecycle == .pending }.count
        let withdrawnCount = allCards.filter { $0.lifecycle == .withdrawn }.count
        let blockedCount = allCards.filter { $0.lifecycle == .blocked }.count
        let outsideHiddenCount = allCards.count - visibleNodes.count
        let publicCount = allCards.filter { $0.visibility == .publicShare && $0.lifecycle == .published }.count

        if role == .guardian && pendingCount > 0 {
            result.append(finding(.guardianConsentRequired, count: pendingCount, actionRequired: true))
        }
        if role == .guardian && withdrawnCount > 0 {
            result.append(finding(.withdrawalPropagated, count: withdrawnCount, actionRequired: false))
        }
        if role == .guardian && blockedCount > 0 {
            result.append(finding(.frozenOrBlockedHidden, count: blockedCount, actionRequired: true))
        }
        if role == .child && (pendingCount + withdrawnCount + blockedCount) > 0 {
            result.append(finding(.childFriendlyCopyApplied, count: pendingCount + withdrawnCount + blockedCount, actionRequired: false))
        }
        if role == .relative && outsideHiddenCount > 0 {
            result.append(finding(.relativeBoundaryApplied, count: outsideHiddenCount, actionRequired: false))
        }
        if role == .publicViewer && (outsideHiddenCount > 0 || publicCount > 0) {
            result.append(finding(.publicRedactionApplied, count: max(publicCount, outsideHiddenCount), actionRequired: false))
        }
        result.append(finding(.sideEffectFree, count: visibleNodes.count, actionRequired: false))
        return result
    }

    private func releaseGate(
        for role: FamilyHonorStorylineConsentViewerRole,
        allCards: [FamilyGrowthCard],
        visibleNodes: [FamilyHonorStorylineConsentNode]
    ) -> FamilyStorylineReleaseGate {
        let pendingCount = allCards.filter { $0.lifecycle == .pending }.count
        let withdrawnCount = allCards.filter { $0.lifecycle == .withdrawn }.count
        let blockedCount = allCards.filter { $0.lifecycle == .blocked }.count
        let readySourceCount = visibleNodes.filter { $0.consentState == .ready }.count
        let publishCandidateCount = role == .guardian || role == .child ? readySourceCount : visibleNodes.count

        if blockedCount > 0 {
            return FamilyStorylineReleaseGate(
                status: .blocked,
                primaryReason: .sourceEntry,
                title: "故事线发布前检查未通过",
                guardianSummary: "有 \(blockedCount) 条内容处于阻断状态，需先处理来源安全或申诉结果。",
                childCopy: "有些内容会先被保护起来，等家长确认安全后再继续。",
                nextAction: "先处理阻断来源；当前页面只做本地预览，不发布、不通知、不发成长积分。",
                readySourceCount: readySourceCount,
                manualGateCount: pendingCount + withdrawnCount,
                blockedCount: blockedCount,
                publishCandidateCount: 0,
                evidenceChecklist: releaseEvidenceChecklist(
                    readySourceCount: readySourceCount,
                    pendingCount: pendingCount,
                    withdrawnCount: withdrawnCount,
                    blockedCount: blockedCount
                )
            )
        }

        if withdrawnCount > 0 {
            return FamilyStorylineReleaseGate(
                status: .manualGate,
                primaryReason: .revocationPropagation,
                title: "等待撤回传播确认",
                guardianSummary: "\(withdrawnCount) 条内容已撤回，需要确认亲友和公开层都已隐藏。",
                childCopy: "你可以决定暂时不展示某些成长故事，我们会先保护你的选择。",
                nextAction: "确认撤回传播完成后，再生成新的故事线发布预览。",
                readySourceCount: readySourceCount,
                manualGateCount: pendingCount + withdrawnCount,
                blockedCount: blockedCount,
                publishCandidateCount: readySourceCount,
                evidenceChecklist: releaseEvidenceChecklist(
                    readySourceCount: readySourceCount,
                    pendingCount: pendingCount,
                    withdrawnCount: withdrawnCount,
                    blockedCount: blockedCount
                )
            )
        }

        if pendingCount > 0 {
            return FamilyStorylineReleaseGate(
                status: .manualGate,
                primaryReason: .guardianConsent,
                title: "需要家长完成同意确认",
                guardianSummary: "\(pendingCount) 条内容等待家长同意或范围确认。",
                childCopy: "等你和家长都觉得合适，再把成长故事展示给家人。",
                nextAction: "先确认同意范围和孩子意愿；仍不写入故事线或通知亲友。",
                readySourceCount: readySourceCount,
                manualGateCount: pendingCount,
                blockedCount: blockedCount,
                publishCandidateCount: readySourceCount,
                evidenceChecklist: releaseEvidenceChecklist(
                    readySourceCount: readySourceCount,
                    pendingCount: pendingCount,
                    withdrawnCount: withdrawnCount,
                    blockedCount: blockedCount
                )
            )
        }

        return FamilyStorylineReleaseGate(
            status: .ready,
            primaryReason: .sourceEntry,
            title: "可以生成故事线只读预览",
            guardianSummary: "\(readySourceCount) 条家庭成长来源已通过同意和可见性检查。",
            childCopy: "这些记录会先成为预览，家人看到的是你的努力，不是排名压力。",
            nextAction: "生成只读预览；不发布、不通知、不发成长积分、不解锁设备。",
            readySourceCount: readySourceCount,
            manualGateCount: 0,
            blockedCount: 0,
            publishCandidateCount: publishCandidateCount,
            evidenceChecklist: releaseEvidenceChecklist(
                readySourceCount: readySourceCount,
                pendingCount: pendingCount,
                withdrawnCount: withdrawnCount,
                blockedCount: blockedCount
            )
        )
    }

    private func releaseEvidenceChecklist(
        readySourceCount: Int,
        pendingCount: Int,
        withdrawnCount: Int,
        blockedCount: Int
    ) -> [FamilyStorylineReleaseEvidence] {
        [
            releaseEvidence(
                seed: "ready-sources:\(readySourceCount)",
                title: "已同意来源",
                status: readySourceCount > 0 ? .ready : .manualGate,
                summary: readySourceCount > 0 ? "\(readySourceCount) 条来源可进入只读预览。" : "还没有可进入只读预览的来源。"
            ),
            releaseEvidence(
                seed: "guardian-pending:\(pendingCount)",
                title: "家长同意",
                status: pendingCount > 0 ? .manualGate : .ready,
                summary: pendingCount > 0 ? "\(pendingCount) 条内容仍需家长确认范围。" : "没有等待家长确认的内容。"
            ),
            releaseEvidence(
                seed: "withdrawn:\(withdrawnCount)",
                title: "撤回传播",
                status: withdrawnCount > 0 ? .manualGate : .ready,
                summary: withdrawnCount > 0 ? "\(withdrawnCount) 条撤回内容需确认亲友/公开层已隐藏。" : "撤回传播队列为空。"
            ),
            releaseEvidence(
                seed: "blocked:\(blockedCount)",
                title: "阻断来源",
                status: blockedCount > 0 ? .blocked : .ready,
                summary: blockedCount > 0 ? "\(blockedCount) 条内容需先处理安全或申诉结果。" : "没有阻断来源。"
            ),
        ]
    }

    private func releaseEvidence(
        seed: String,
        title: String,
        status: FamilyStorylineReleaseGateStatus,
        summary: String
    ) -> FamilyStorylineReleaseEvidence {
        FamilyStorylineReleaseEvidence(
            publicEvidenceRef: FamilyGrowthRedaction.publicRef(prefix: "story-proof", source: seed),
            title: title,
            status: status,
            summary: summary
        )
    }

    private func finding(
        _ code: FamilyHonorStorylineConsentFindingCode,
        count: Int,
        actionRequired: Bool
    ) -> FamilyHonorStorylineConsentFinding {
        FamilyHonorStorylineConsentFinding(
            publicFindingRef: FamilyGrowthRedaction.publicRef(prefix: "honor-find", source: "\(code.rawValue):\(count)"),
            code: code,
            title: code.label,
            count: count,
            actionRequired: actionRequired
        )
    }

    private func layerCounts(nodes: [FamilyHonorStorylineConsentNode]) -> [FamilyHonorStorylineLayer: Int] {
        var counts: [FamilyHonorStorylineLayer: Int] = [:]
        for node in nodes {
            counts[node.layer, default: 0] += 1
        }
        return counts
    }

    private func displayTitle(card: FamilyGrowthCard, role: FamilyHonorStorylineConsentViewerRole) -> String {
        if role == .publicViewer {
            return safeText("\(card.kind.label)公开摘要", fallback: "公开摘要")
        }
        return safeText(card.title, fallback: card.kind.label)
    }

    private func displaySummary(
        card: FamilyGrowthCard,
        role: FamilyHonorStorylineConsentViewerRole
    ) -> String {
        let base: String
        switch role {
        case .child:
            base = card.lifecycle == .blocked ? "这条内容暂时被保护起来，可以和家长一起看。" : card.displaySummary(for: .child)
        case .guardian:
            base = card.displaySummary(for: .guardian)
        case .relative:
            base = card.displaySummary(for: .relative)
        case .publicViewer:
            base = "公开脱敏摘要：\(card.displaySummary(for: .guardian))"
        }
        return safeText(base, fallback: "内容已脱敏，仅保留安全摘要。")
    }

    private func safeTags(_ tags: [String], role: FamilyHonorStorylineConsentViewerRole) -> [String] {
        if role == .publicViewer {
            return tags.prefix(2).map { safeText($0, fallback: "成长") }
        }
        return tags.map { safeText($0, fallback: "成长") }
    }

    private func safeText(_ value: String, fallback: String) -> String {
        MobileSyncPayloadGuard.isUnsafe(value) ? fallback : value
    }

    private func cardOrder(_ lhs: FamilyGrowthCard, _ rhs: FamilyGrowthCard) -> Bool {
        let leftLayer = layer(for: lhs).sortOrder
        let rightLayer = layer(for: rhs).sortOrder
        if leftLayer != rightLayer { return leftLayer < rightLayer }
        let leftKind = kindOrder(lhs.kind)
        let rightKind = kindOrder(rhs.kind)
        if leftKind != rightKind { return leftKind < rightKind }
        if lhs.isFormalHonor != rhs.isFormalHonor { return lhs.isFormalHonor && !rhs.isFormalHonor }
        return lhs.title < rhs.title
    }

    private func kindOrder(_ kind: FamilyGrowthCardKind) -> Int {
        switch kind {
        case .storyline: return 0
        case .honorWall: return 1
        case .badge: return 2
        case .growthCard: return 3
        case .journal: return 4
        case .relativeComment: return 5
        case .vlogPlaceholder: return 6
        }
    }
}
