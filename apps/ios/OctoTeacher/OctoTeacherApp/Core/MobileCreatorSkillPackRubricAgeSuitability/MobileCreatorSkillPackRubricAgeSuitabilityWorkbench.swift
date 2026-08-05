import Foundation

/// iOS 创作者技能包量规与年龄适配安全壳的纯本地只读投影。
///
/// 该层把成长包 Manifest 草稿中的学习目标、测验证明、年龄分级、成长积分建议、
/// 徽章/能力卡草稿和市场展示边界裁剪成创作者、家长、孩子可看的安全状态：
/// 不提交审核、不发布市场、不收费、不写账本、不发成长积分、不授徽章、不改能力卡、不解锁设备。
enum MobileCreatorSkillPackRubricViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case creator

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .creator: return "创作者"
        }
    }

    var audienceNote: String {
        switch self {
        case .child:
            return "这里只看适龄目标、证明下一步和安全提示；不会显示最终解析、成人评分、奖励数值或市场话术。"
        case .guardian:
            return "只读查看年龄适配、量规完整性、证明引用、徽章/能力卡和成长积分建议边界。"
        case .creator:
            return "只读查看发布前待修项；真正提交审核和市场发布仍在正式流程完成。"
        }
    }
}

enum MobileCreatorSkillPackRubricState: String, Equatable {
    case readyForPractice
    case needsGuardianReview
    case needsCreatorFix
    case hiddenFromChild
    case blocked

    var label: String {
        switch self {
        case .readyForPractice: return "可练习"
        case .needsGuardianReview: return "待家长复核"
        case .needsCreatorFix: return "待创作者修正"
        case .hiddenFromChild: return "孩子不可见"
        case .blocked: return "已阻断"
        }
    }
}

enum MobileCreatorSkillPackRubricFindingCode: String, Equatable {
    case readOnlyReady = "READ_ONLY_READY"
    case ageBandBlocked = "AGE_BAND_BLOCKED"
    case rubricEvidenceMissing = "RUBRIC_EVIDENCE_MISSING"
    case answerAndScoringHidden = "ANSWER_AND_SCORING_HIDDEN"
    case creditDevicePromiseBlocked = "CREDIT_DEVICE_PROMISE_BLOCKED"
    case badgeAbilityEvidenceBlocked = "BADGE_ABILITY_EVIDENCE_BLOCKED"
    case marketplaceCopyBlocked = "MARKETPLACE_COPY_BLOCKED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

struct MobileCreatorSkillPackRubricRow: Identifiable, Equatable {
    var publicModuleRef: String
    var title: String
    var learningGoal: String
    var ageLabel: String
    var rubricLabel: String
    var proofLabel: String
    var badgeAbilityLabel: String
    var creditBoundaryLabel: String
    var marketplaceLabel: String
    var nextStep: String
    var safetyNote: String
    var state: MobileCreatorSkillPackRubricState
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToCreator: Bool
    var ageMatched: Bool
    var rubricHasEvidence: Bool
    var answerOrScoringBlocked: Bool
    var creditOrDevicePromiseBlocked: Bool
    var badgeAbilityBeforeEvidenceBlocked: Bool
    var marketplacePurchaseCopyBlocked: Bool

    let submitsReview = false
    let publishesMarketplace = false
    let chargesPayment = false
    let writesEntitlement = false
    let callsNetwork = false
    let callsAI = false
    let opensWebView = false
    let writesLedger = false
    let grantsCredit = false
    let grantsBadge = false
    let mutatesAbilityCard = false
    let unlocksDevice = false

    var id: String { publicModuleRef }

    var displayValues: [String] {
        [
            title,
            learningGoal,
            ageLabel,
            rubricLabel,
            proofLabel,
            badgeAbilityLabel,
            creditBoundaryLabel,
            marketplaceLabel,
            nextStep,
            safetyNote,
            state.rawValue,
            state.label
        ]
    }
}

struct MobileCreatorSkillPackRubricFinding: Identifiable, Equatable {
    var code: MobileCreatorSkillPackRubricFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToCreator: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileCreatorSkillPackRubricPublicSummary: Equatable {
    var role: MobileCreatorSkillPackRubricViewerRole
    var moduleCount: Int
    var visibleModuleCount: Int
    var blockedCount: Int
    var ageBlockedCount: Int
    var rubricEvidenceMissingCount: Int
    var answerOrScoringBlockedCount: Int
    var creditDevicePromiseBlockedCount: Int
    var badgeAbilityEvidenceBlockedCount: Int
    var marketplaceBlockedCount: Int
    var findingCodes: [MobileCreatorSkillPackRubricFindingCode]

    let submitsReview = false
    let publishesMarketplace = false
    let chargesPayment = false
    let writesEntitlement = false
    let callsNetwork = false
    let callsAI = false
    let opensWebView = false
    let writesLedger = false
    let grantsCredit = false
    let grantsBadge = false
    let mutatesAbilityCard = false
    let unlocksDevice = false

    var hasTriggeredSideEffect: Bool {
        submitsReview || publishesMarketplace || chargesPayment || writesEntitlement
            || callsNetwork || callsAI || opensWebView || writesLedger || grantsCredit
            || grantsBadge || mutatesAbilityCard || unlocksDevice
    }
}

struct MobileCreatorSkillPackRubricAgeSuitabilityWorkbench: Equatable {
    var role: MobileCreatorSkillPackRubricViewerRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var rows: [MobileCreatorSkillPackRubricRow]
    var findings: [MobileCreatorSkillPackRubricFinding]
    var publicSummary: MobileCreatorSkillPackRubricPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + rows.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileCreatorSkillPackRubricAgeSuitabilityBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileCreatorSkillPackRubricAgeSuitabilityBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "guardian:", "creator:", "pack:", "module:",
        "rubric:", "quiz:", "question:", "answer:", "answer key", "answerkey",
        "score key", "scoring key", "badge:", "card:", "order:", "ledger:",
        "credit:", "device:", "claim:", "task:", "审核原因：", "购买链接",
        "成长积分金额", "设备命令", "立即购买", "限时购买", "直接解锁",
        "http://", "https://", "file://", "/users/", "/volumes/", "192.168."
    ]
    private static let sensitivePatterns = [
        "(?i)\\b(?:access|device|session|api|bearer)[ _-]?token\\b",
        "(?i)\\b(?:api|server|client)[ _-]?secret\\b",
        "(?i)\\bapi[_-]?key\\b",
        "(?i)\\bcredit[ _-]?amount\\b",
        "(?i)\\banswer[ _-]?key\\b"
    ]

    func build(
        role: MobileCreatorSkillPackRubricViewerRole,
        draft: CreatorManifestPreviewDraft = .mock,
        childAge: Int = 10,
        answerKeyDraft: String? = nil,
        scoringRubricDraft: String? = nil,
        creatorAuditReason: String? = nil,
        directCreditPromise: Bool = false,
        deviceUnlockPromise: Bool = false,
        badgeBeforeEvidence: Bool = false,
        abilityCardBeforeEvidence: Bool = false,
        marketplacePurchaseCopy: String? = nil
    ) -> MobileCreatorSkillPackRubricAgeSuitabilityWorkbench {
        if Self.hasUnsafeDraftPayload(
            draft: draft,
            answerKeyDraft: answerKeyDraft,
            scoringRubricDraft: scoringRubricDraft,
            creatorAuditReason: creatorAuditReason,
            marketplacePurchaseCopy: marketplacePurchaseCopy
        ) {
            return safeFallback(role: role, hiddenCount: draft.contentBlocks.count)
        }

        let rows = draft.contentBlocks.map { block in
            row(
                role: role,
                draft: draft,
                block: block,
                childAge: childAge,
                answerKeyDraft: answerKeyDraft,
                scoringRubricDraft: scoringRubricDraft,
                directCreditPromise: directCreditPromise,
                deviceUnlockPromise: deviceUnlockPromise,
                badgeBeforeEvidence: badgeBeforeEvidence,
                abilityCardBeforeEvidence: abilityCardBeforeEvidence,
                marketplacePurchaseCopy: marketplacePurchaseCopy
            )
        }
        let visibleRows = rows.filter { isVisible($0, to: role) }
        let findings = findingRows(role: role, rows: rows)
        let summary = MobileCreatorSkillPackRubricPublicSummary(
            role: role,
            moduleCount: rows.count,
            visibleModuleCount: visibleRows.count,
            blockedCount: rows.filter { $0.state == .blocked }.count,
            ageBlockedCount: rows.filter { !$0.ageMatched }.count,
            rubricEvidenceMissingCount: rows.filter { !$0.rubricHasEvidence }.count,
            answerOrScoringBlockedCount: rows.filter(\.answerOrScoringBlocked).count,
            creditDevicePromiseBlockedCount: rows.filter(\.creditOrDevicePromiseBlocked).count,
            badgeAbilityEvidenceBlockedCount: rows.filter(\.badgeAbilityBeforeEvidenceBlocked).count,
            marketplaceBlockedCount: rows.filter(\.marketplacePurchaseCopyBlocked).count,
            findingCodes: findings.map(\.code)
        )
        let workbench = MobileCreatorSkillPackRubricAgeSuitabilityWorkbench(
            role: role,
            title: "创作者量规年龄适配",
            subtitle: "\(draft.title) · \(draft.ageBand.gradeBand)",
            audienceNote: role.audienceNote,
            rows: visibleRows,
            findings: findings.filter { finding in
                switch role {
                case .child: return finding.visibleToChild
                case .guardian: return finding.visibleToGuardian
                case .creator: return finding.visibleToCreator
                }
            },
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? safeFallback(role: role, hiddenCount: draft.contentBlocks.count) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        if sensitiveMarkers.contains(where: { joined.contains($0) }) { return true }
        return sensitivePatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func hasUnsafeDraftPayload(
        draft: CreatorManifestPreviewDraft,
        answerKeyDraft: String?,
        scoringRubricDraft: String?,
        creatorAuditReason: String?,
        marketplacePurchaseCopy: String?
    ) -> Bool {
        var values = [draft.title, draft.summary, draft.contentVersion, draft.ageBand.gradeBand]
        values.append(contentsOf: draft.contentBlocks.flatMap { [$0.title, $0.summary, $0.contentId] })
        values.append(contentsOf: draft.proofRequirements.flatMap { [$0.instructions, $0.proofId] })
        values.append(contentsOf: draft.creditDrafts.flatMap { [$0.scopeLabel, $0.reason, $0.creditId] })
        values.append(contentsOf: draft.badgeAbilityDrafts.flatMap { [$0.title, $0.category, $0.draftId] })
        values.append(contentsOf: [draft.manifestId, draft.creatorId, draft.packId, draft.licenseBoundary.licenseId])
        values.append(contentsOf: [answerKeyDraft, scoringRubricDraft, creatorAuditReason, marketplacePurchaseCopy].compactMap { $0 })
        return hasUnsafeDisplayPayload(values)
    }

    private func row(
        role: MobileCreatorSkillPackRubricViewerRole,
        draft: CreatorManifestPreviewDraft,
        block: CreatorManifestContentDraft,
        childAge: Int,
        answerKeyDraft: String?,
        scoringRubricDraft: String?,
        directCreditPromise: Bool,
        deviceUnlockPromise: Bool,
        badgeBeforeEvidence: Bool,
        abilityCardBeforeEvidence: Bool,
        marketplacePurchaseCopy: String?
    ) -> MobileCreatorSkillPackRubricRow {
        let ageMatched = childAge >= draft.ageBand.minAge && childAge <= draft.ageBand.maxAge
        let proofRows = proofRequirements(for: block, draft: draft)
        let rubricHasEvidence = block.kind != .quiz || (
            !proofRows.isEmpty
                && proofRows.allSatisfy { $0.evidenceRefsOnly && $0.status == .complete && !$0.verifierRoles.isEmpty }
        )
        let answerOrScoringBlocked = block.containsDirectAnswer || answerKeyDraft != nil || scoringRubricDraft != nil
        let matchingCredits = draft.creditDrafts.filter { $0.triggerContentId == block.contentId }
        let creditOrDevicePromiseBlocked = directCreditPromise || deviceUnlockPromise
            || matchingCredits.contains { !$0.requiresGuardianApproval || $0.writesLedger || $0.amount <= 0 || $0.amount > 120 }
        let rewardDraftLinkedToBlock = !matchingCredits.isEmpty
            || (!draft.badgeAbilityDrafts.isEmpty && (block.kind == .quiz || block.kind == .creatorUpload))
        let badgeAbilityBeforeEvidenceBlocked = rewardDraftLinkedToBlock
            && (badgeBeforeEvidence || abilityCardBeforeEvidence || proofRows.isEmpty || !rubricHasEvidence)
        let marketplacePurchaseCopyBlocked = marketplacePurchaseCopy != nil || draft.licenseBoundary.marketPublishReady
        let blocked = !ageMatched || !rubricHasEvidence || answerOrScoringBlocked || creditOrDevicePromiseBlocked
            || badgeAbilityBeforeEvidenceBlocked || marketplacePurchaseCopyBlocked || block.status != .complete
            || !block.assetModerationPassed

        let state: MobileCreatorSkillPackRubricState
        if blocked {
            state = .blocked
        } else if role == .creator && draft.proofRequirements.contains(where: { $0.status != .complete }) {
            state = .needsCreatorFix
        } else if role == .guardian && block.guardianReviewRequired {
            state = .needsGuardianReview
        } else if role == .child && !block.visibleToChild {
            state = .hiddenFromChild
        } else {
            state = .readyForPractice
        }

        return MobileCreatorSkillPackRubricRow(
            publicModuleRef: publicRef("mcsr", block.contentId),
            title: titleCopy(role: role, block: block),
            learningGoal: learningGoalCopy(role: role, block: block),
            ageLabel: ageMatched ? "\(draft.ageBand.minAge)-\(draft.ageBand.maxAge) 岁适配" : "当前年龄不在适配范围",
            rubricLabel: rubricLabel(role: role, block: block, rubricHasEvidence: rubricHasEvidence, answerOrScoringBlocked: answerOrScoringBlocked),
            proofLabel: proofLabel(role: role, proofRows: proofRows, rubricHasEvidence: rubricHasEvidence),
            badgeAbilityLabel: badgeAbilityLabel(
                role: role,
                hasRewardDraft: rewardDraftLinkedToBlock,
                blocked: badgeAbilityBeforeEvidenceBlocked
            ),
            creditBoundaryLabel: creditBoundaryLabel(role: role, blocked: creditOrDevicePromiseBlocked),
            marketplaceLabel: marketplacePurchaseCopyBlocked ? "市场展示待审核，购买诱导已阻断" : "市场展示仍为审核前草稿",
            nextStep: nextStep(role: role, state: state),
            safetyNote: safetyNote(role: role),
            state: state,
            visibleToChild: block.visibleToChild && state != .blocked && ageMatched,
            visibleToGuardian: role == .guardian,
            visibleToCreator: role == .creator,
            ageMatched: ageMatched,
            rubricHasEvidence: rubricHasEvidence,
            answerOrScoringBlocked: answerOrScoringBlocked,
            creditOrDevicePromiseBlocked: creditOrDevicePromiseBlocked,
            badgeAbilityBeforeEvidenceBlocked: badgeAbilityBeforeEvidenceBlocked,
            marketplacePurchaseCopyBlocked: marketplacePurchaseCopyBlocked
        )
    }

    private func proofRequirements(
        for block: CreatorManifestContentDraft,
        draft: CreatorManifestPreviewDraft
    ) -> [CreatorManifestProofRequirementDraft] {
        let ids = Set(block.proofRequirementIds)
        return draft.proofRequirements.filter { ids.contains($0.proofId) }
    }

    private func isVisible(
        _ row: MobileCreatorSkillPackRubricRow,
        to role: MobileCreatorSkillPackRubricViewerRole
    ) -> Bool {
        switch role {
        case .child: return row.visibleToChild && row.state != .blocked
        case .guardian: return row.visibleToGuardian
        case .creator: return row.visibleToCreator
        }
    }

    private func findingRows(
        role: MobileCreatorSkillPackRubricViewerRole,
        rows: [MobileCreatorSkillPackRubricRow]
    ) -> [MobileCreatorSkillPackRubricFinding] {
        var findings: [MobileCreatorSkillPackRubricFinding] = []
        if rows.contains(where: { !$0.ageMatched }) {
            findings.append(finding(.ageBandBlocked, "年龄分级不匹配，孩子视角不展示该学习模块。", true, child: true, guardian: true, creator: true))
        }
        if rows.contains(where: { !$0.rubricHasEvidence }) {
            findings.append(finding(.rubricEvidenceMissing, "测验/量规必须绑定完整的证据引用和验证角色。", true, child: false, guardian: true, creator: true))
        }
        if rows.contains(where: \.answerOrScoringBlocked) {
            findings.append(finding(.answerAndScoringHidden, "答案 key 和评分内部规则已从孩子视角裁剪。", true, child: false, guardian: true, creator: true))
        }
        if rows.contains(where: \.creditOrDevicePromiseBlocked) {
            findings.append(finding(.creditDevicePromiseBlocked, "成长包不能承诺直发成长积分、写账本或解锁设备。", true, child: false, guardian: true, creator: true))
        }
        if rows.contains(where: \.badgeAbilityBeforeEvidenceBlocked) {
            findings.append(finding(.badgeAbilityEvidenceBlocked, "徽章和能力卡草稿必须等证明闭环后再进入人工审核。", true, child: false, guardian: true, creator: true))
        }
        if rows.contains(where: \.marketplacePurchaseCopyBlocked) {
            findings.append(finding(.marketplaceCopyBlocked, "市场展示不能出现购买诱导或审核前发布承诺。", true, child: false, guardian: true, creator: true))
        }
        if findings.isEmpty {
            findings.append(finding(
                .readOnlyReady,
                role == .child ? "当前只显示适龄学习目标和证明下一步。" : "量规与年龄适配安全壳只读就绪。",
                false,
                child: true,
                guardian: true,
                creator: true
            ))
        }
        return findings
    }

    private func finding(
        _ code: MobileCreatorSkillPackRubricFindingCode,
        _ message: String,
        _ actionRequired: Bool,
        child: Bool,
        guardian: Bool,
        creator: Bool
    ) -> MobileCreatorSkillPackRubricFinding {
        MobileCreatorSkillPackRubricFinding(
            code: code,
            message: message,
            actionRequired: actionRequired,
            visibleToChild: child,
            visibleToGuardian: guardian,
            visibleToCreator: creator
        )
    }

    private func titleCopy(
        role: MobileCreatorSkillPackRubricViewerRole,
        block: CreatorManifestContentDraft
    ) -> String {
        switch role {
        case .child:
            return block.kind == .schoolHomeworkHook ? "学校任务待家长查看" : block.title
        case .guardian, .creator:
            return block.title
        }
    }

    private func learningGoalCopy(
        role: MobileCreatorSkillPackRubricViewerRole,
        block: CreatorManifestContentDraft
    ) -> String {
        switch role {
        case .child:
            return "完成这一段学习后，提交对应证明给家长确认。"
        case .guardian:
            return "\(block.kind.label) · \(block.summary)"
        case .creator:
            return "\(block.kind.label) · 发布前检查学习目标、证明和审核边界。"
        }
    }

    private func rubricLabel(
        role: MobileCreatorSkillPackRubricViewerRole,
        block: CreatorManifestContentDraft,
        rubricHasEvidence: Bool,
        answerOrScoringBlocked: Bool
    ) -> String {
        if answerOrScoringBlocked { return "答案和评分内部规则已裁剪" }
        if block.kind != .quiz { return role == .child ? "按步骤完成学习" : "非测验内容使用证明要求校验" }
        return rubricHasEvidence ? "测验量规已绑定证据引用" : "测验量规缺少证据闭环"
    }

    private func proofLabel(
        role: MobileCreatorSkillPackRubricViewerRole,
        proofRows: [CreatorManifestProofRequirementDraft],
        rubricHasEvidence: Bool
    ) -> String {
        if proofRows.isEmpty { return "暂无证明要求" }
        switch role {
        case .child:
            return "完成后提交证明给家长确认"
        case .guardian:
            return rubricHasEvidence ? "证明只保存引用，由 \(verifierLabel(proofRows)) 核验" : "证明引用或验证角色需要补齐"
        case .creator:
            return rubricHasEvidence ? "证明闭环完整" : "发布前补齐证据引用和验证角色"
        }
    }

    private func verifierLabel(_ proofRows: [CreatorManifestProofRequirementDraft]) -> String {
        let labels = proofRows.flatMap { $0.verifierRoles.map(\.label) }
        let uniqueLabels = Array(Set(labels)).sorted()
        return uniqueLabels.isEmpty ? "家长" : uniqueLabels.joined(separator: " / ")
    }

    private func badgeAbilityLabel(
        role: MobileCreatorSkillPackRubricViewerRole,
        hasRewardDraft: Bool,
        blocked: Bool
    ) -> String {
        if !hasRewardDraft { return "暂无徽章或能力卡草稿" }
        if blocked { return "徽章/能力卡需等待证明闭环和人工审核" }
        return role == .child ? "荣誉展示需家长确认后出现" : "徽章/能力卡仅为人工审核草稿"
    }

    private func creditBoundaryLabel(
        role: MobileCreatorSkillPackRubricViewerRole,
        blocked: Bool
    ) -> String {
        if blocked { return "成长积分和设备承诺已阻断" }
        return role == .child ? "完成后等待家长确认奖励边界" : "成长积分建议仅供家长审核，不写账本"
    }

    private func nextStep(
        role: MobileCreatorSkillPackRubricViewerRole,
        state: MobileCreatorSkillPackRubricState
    ) -> String {
        switch (role, state) {
        case (.child, .readyForPractice), (.child, .needsGuardianReview):
            return "先完成学习，再提交证明给家长。"
        case (.guardian, .readyForPractice), (.guardian, .needsGuardianReview):
            return "检查证明、年龄和奖励边界后，再进入正式流程。"
        case (.creator, .readyForPractice):
            return "可以继续准备正式审核材料。"
        case (.creator, .needsCreatorFix):
            return "先补齐量规、证明和适龄说明。"
        default:
            return "该模块暂不展示，请先修正安全边界。"
        }
    }

    private func safetyNote(role: MobileCreatorSkillPackRubricViewerRole) -> String {
        switch role {
        case .child:
            return "本页不显示最终解析、成人评分、奖励数值、市场话术或设备操作。"
        case .guardian:
            return "本页只读，不发布、不收费、不发成长积分、不改能力卡。"
        case .creator:
            return "本页只读，不提交审核、不写市场、不调用网络。"
        }
    }

    private func safeFallback(
        role: MobileCreatorSkillPackRubricViewerRole,
        hiddenCount: Int
    ) -> MobileCreatorSkillPackRubricAgeSuitabilityWorkbench {
        MobileCreatorSkillPackRubricAgeSuitabilityWorkbench(
            role: role,
            title: "量规与年龄适配已被安全保护",
            subtitle: "本地安全壳",
            audienceNote: role.audienceNote,
            rows: [],
            findings: [
                finding(
                    .unsafePayloadBlocked,
                    "检测到链接、路径、密钥、局域网地址、内部标识或答案/成长积分/设备敏感语义，本地壳不回显原文。",
                    role == .guardian || role == .creator,
                    child: false,
                    guardian: true,
                    creator: true
                )
            ],
            publicSummary: MobileCreatorSkillPackRubricPublicSummary(
                role: role,
                moduleCount: hiddenCount,
                visibleModuleCount: 0,
                blockedCount: hiddenCount,
                ageBlockedCount: 0,
                rubricEvidenceMissingCount: 0,
                answerOrScoringBlockedCount: 0,
                creditDevicePromiseBlockedCount: 0,
                badgeAbilityEvidenceBlockedCount: 0,
                marketplaceBlockedCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        var hash: UInt32 = 5381
        for scalar in "mobile-creator-rubric-age:\(source)".unicodeScalars {
            hash = (hash &* 33) ^ (scalar.value & 0xFFFF)
        }
        return "\(prefix)-\(String(hash, radix: 36))"
    }
}
