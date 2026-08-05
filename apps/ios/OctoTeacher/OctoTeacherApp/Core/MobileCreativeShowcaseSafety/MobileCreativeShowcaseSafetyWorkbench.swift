import Foundation

/// iOS 孩子创作作品展示安全壳的纯本地只读投影。
///
/// 该层只把成长包 Manifest 中的创作上传草稿组织成孩子、家长、亲友可看的展示前安全状态：
/// 不打开相机/相册/文件选择器，不上传媒体，不发布作品，不审核评论，不通知亲友，
/// 不写账本，不发成长积分，不解锁设备，不接真实社交平台。
enum MobileCreativeShowcaseViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case relative

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        }
    }

    var audienceNote: String {
        switch self {
        case .child:
            return "这里只看创作目标、自检和等待家长审核；不会打开相册、上传作品或显示奖励压力。"
        case .guardian:
            return "只读查看同意、审核、亲友可见、奖励压力、证明和成长积分边界；真正发布仍需正式流程。"
        case .relative:
            return "亲友只看已批准、非私密、脱敏作品摘要；互动和奖励都由家长流程处理。"
        }
    }
}

enum MobileCreativeShowcaseState: String, Equatable {
    case approvedPreview
    case waitingGuardianReview
    case hiddenFromRelative
    case blocked

    var label: String {
        switch self {
        case .approvedPreview: return "可展示"
        case .waitingGuardianReview: return "待家长审核"
        case .hiddenFromRelative: return "亲友不可见"
        case .blocked: return "已阻断"
        }
    }
}

enum MobileCreativeShowcaseFindingCode: String, Equatable {
    case readOnlyReady = "READ_ONLY_READY"
    case approvalRequired = "APPROVAL_REQUIRED"
    case privacyVisibilityBlocked = "PRIVACY_VISIBILITY_BLOCKED"
    case rewardPressureBlocked = "REWARD_PRESSURE_BLOCKED"
    case creditBoundaryBlocked = "CREDIT_BOUNDARY_BLOCKED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

struct MobileCreativeShowcaseItem: Identifiable, Equatable {
    var publicShowcaseRef: String
    var title: String
    var creativePrompt: String
    var audienceLabel: String
    var consentLabel: String
    var moderationLabel: String
    var proofLabel: String
    var creditBoundaryLabel: String
    var nextStep: String
    var safetyNote: String
    var state: MobileCreativeShowcaseState
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToRelative: Bool
    var childAssentGranted: Bool
    var guardianApproved: Bool
    var moderationPassed: Bool
    var privateByChild: Bool
    var withdrawn: Bool
    var rewardPressureBlocked: Bool
    var directCreditBlocked: Bool

    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let uploadsMedia = false
    let publishesShowcase = false
    let approvesComment = false
    let sendsComment = false
    let sendsNotification = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let callsNetwork = false
    let writesSocialPlatform = false

    var id: String { publicShowcaseRef }

    var displayValues: [String] {
        [
            title,
            creativePrompt,
            audienceLabel,
            consentLabel,
            moderationLabel,
            proofLabel,
            creditBoundaryLabel,
            nextStep,
            safetyNote,
            state.rawValue,
            state.label
        ]
    }
}

struct MobileCreativeShowcaseProofRow: Identifiable, Equatable {
    var publicProofRef: String
    var title: String
    var verifierLabels: [String]
    var instructions: String

    let opensFilePicker = false
    let uploadsMedia = false
    let writesLedger = false
    let grantsCredit = false

    var id: String { publicProofRef }

    var displayValues: [String] { [title, instructions] + verifierLabels }
}

struct MobileCreativeShowcaseFinding: Identifiable, Equatable {
    var code: MobileCreativeShowcaseFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool
    var visibleToRelative: Bool

    var id: String { code.rawValue }

    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileCreativeShowcasePublicSummary: Equatable {
    var role: MobileCreativeShowcaseViewerRole
    var showcaseCount: Int
    var visibleShowcaseCount: Int
    var pendingReviewCount: Int
    var hiddenFromRelativeCount: Int
    var blockedCount: Int
    var proofRequirementCount: Int
    var directCreditBlockedCount: Int
    var findingCodes: [MobileCreativeShowcaseFindingCode]

    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let uploadsMedia = false
    let publishesShowcase = false
    let approvesComment = false
    let sendsComment = false
    let sendsNotification = false
    let callsNetwork = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let writesSocialPlatform = false

    var hasTriggeredSideEffect: Bool {
        opensCamera || opensPhotoLibrary || opensFilePicker || uploadsMedia || publishesShowcase
            || approvesComment || sendsComment || sendsNotification || callsNetwork || writesLedger
            || grantsCredit || unlocksDevice || writesSocialPlatform
    }
}

struct MobileCreativeShowcaseSafetyWorkbench: Equatable {
    var role: MobileCreativeShowcaseViewerRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var showcases: [MobileCreativeShowcaseItem]
    var proofs: [MobileCreativeShowcaseProofRow]
    var findings: [MobileCreativeShowcaseFinding]
    var publicSummary: MobileCreativeShowcasePublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + showcases.flatMap(\.displayValues)
            + proofs.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileCreativeShowcaseSafetyBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileCreativeShowcaseSafetyBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "guardian:", "relative:", "comment:", "media:",
        "showcase:", "proof:", "creator:", "pack:", "session:", "device:",
        "ledger:", "credit:", "reward amount", "设备命令",
        "http://", "https://", "file://", "/users/", "/volumes/"
    ]
    private static let sensitivePatterns = [
        "(?i)\\b(?:access|device|session|api|bearer)[ _-]?token\\b",
        "(?i)\\b(?:api|server|client)[ _-]?secret\\b",
        "(?i)\\bapi[_-]?key\\b",
        "(?i)\\bcredit[ _-]?amount\\b",
        "成长积分金额[:：]"
    ]

    func build(
        role: MobileCreativeShowcaseViewerRole,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock,
        childAssentGranted: Bool = true,
        guardianApproved: Bool = true,
        moderationPassed: Bool = true,
        privateByChild: Bool = false,
        withdrawn: Bool = false,
        relativeRewardPromise: Bool = false
    ) -> MobileCreativeShowcaseSafetyWorkbench {
        if Self.hasUnsafeDraftPayload(draft) {
            return safeFallback(role: role, hiddenCount: creativeBlocks(in: draft).count)
        }

        let creativeBlocks = creativeBlocks(in: draft)
        let items = creativeBlocks.map {
            item(
                from: $0,
                role: role,
                draft: draft,
                childAssentGranted: childAssentGranted,
                guardianApproved: guardianApproved,
                moderationPassed: moderationPassed,
                privateByChild: privateByChild,
                withdrawn: withdrawn,
                relativeRewardPromise: relativeRewardPromise
            )
        }
        let visibleItems = items.filter { isVisible($0, to: role) }
        let visibleItemRefs = Set(visibleItems.map(\.publicShowcaseRef))
        let proofSourceBlocks: [CreatorManifestContentDraft]
        if role == .guardian {
            proofSourceBlocks = creativeBlocks
        } else {
            proofSourceBlocks = creativeBlocks.filter { visibleItemRefs.contains(publicRef("mcs", $0.contentId)) }
        }
        let proofIds = Set(proofSourceBlocks.flatMap(\.proofRequirementIds))
        let proofRows = draft.proofRequirements
            .filter { proofIds.contains($0.proofId) }
            .map { proof(from: $0, role: role) }
        let findings = findingRows(role: role, items: items)
        let summary = MobileCreativeShowcasePublicSummary(
            role: role,
            showcaseCount: items.count,
            visibleShowcaseCount: visibleItems.count,
            pendingReviewCount: items.filter { $0.state == .waitingGuardianReview }.count,
            hiddenFromRelativeCount: items.filter { !$0.visibleToRelative }.count,
            blockedCount: items.filter { $0.state == .blocked }.count,
            proofRequirementCount: proofRows.count,
            directCreditBlockedCount: items.filter(\.directCreditBlocked).count,
            findingCodes: findings.map(\.code)
        )
        let workbench = MobileCreativeShowcaseSafetyWorkbench(
            role: role,
            title: "创作作品展示安全壳",
            subtitle: "\(draft.title) · \(draft.ageBand.gradeBand)",
            audienceNote: role.audienceNote,
            showcases: visibleItems,
            proofs: role == .child || role == .relative ? proofRows.map(publicProof) : proofRows,
            findings: findings.filter { finding in
                switch role {
                case .child: return finding.visibleToChild
                case .relative: return finding.visibleToRelative
                case .guardian: return true
                }
            },
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? safeFallback(role: role, hiddenCount: creativeBlocks.count) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        if sensitiveMarkers.contains(where: { joined.contains($0) }) { return true }
        return sensitivePatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func hasUnsafeDraftPayload(_ draft: CreatorManifestPreviewDraft) -> Bool {
        let values = [draft.title, draft.summary, draft.contentVersion, draft.ageBand.gradeBand]
            + draft.contentBlocks.flatMap { [$0.title, $0.summary] }
            + draft.proofRequirements.map(\.instructions)
            + draft.creditDrafts.flatMap { [$0.scopeLabel, $0.reason] }
        return hasUnsafeDisplayPayload(values)
    }

    private func creativeBlocks(in draft: CreatorManifestPreviewDraft) -> [CreatorManifestContentDraft] {
        draft.contentBlocks.filter { $0.kind == .creatorUpload }
    }

    private func item(
        from block: CreatorManifestContentDraft,
        role: MobileCreativeShowcaseViewerRole,
        draft: CreatorManifestPreviewDraft,
        childAssentGranted: Bool,
        guardianApproved: Bool,
        moderationPassed: Bool,
        privateByChild: Bool,
        withdrawn: Bool,
        relativeRewardPromise: Bool
    ) -> MobileCreativeShowcaseItem {
        let creditDrafts = draft.creditDrafts.filter { $0.triggerContentId == block.contentId }
        let directCreditBlocked = creditDrafts.contains { !$0.requiresGuardianApproval || $0.writesLedger }
        let rewardPressureBlocked = relativeRewardPromise
        let licenseAllowsUpload = draft.licenseBoundary.allowsCreatorUpload
        let blocked = !licenseAllowsUpload || !block.assetModerationPassed || block.containsDirectAnswer
            || !childAssentGranted || withdrawn || directCreditBlocked || rewardPressureBlocked
        let visibleToRelative = guardianApproved && moderationPassed && !privateByChild && !withdrawn && !blocked
        let state: MobileCreativeShowcaseState
        if blocked {
            state = .blocked
        } else if !guardianApproved || !moderationPassed {
            state = .waitingGuardianReview
        } else if role == .relative && !visibleToRelative {
            state = .hiddenFromRelative
        } else {
            state = .approvedPreview
        }

        return MobileCreativeShowcaseItem(
            publicShowcaseRef: publicRef("mcs", block.contentId),
            title: role == .relative ? "孩子创作作品" : block.title,
            creativePrompt: promptCopy(role: role),
            audienceLabel: visibleToRelative ? "亲友可见：已批准摘要" : "仅孩子与家长可见",
            consentLabel: childAssentGranted && !withdrawn ? "孩子同意有效" : "孩子同意已缺失或撤回",
            moderationLabel: guardianApproved && moderationPassed ? "家长审核已通过" : "仍需家长审核",
            proofLabel: block.proofRequirementIds.isEmpty ? "无需作品证明" : "家长保管脱敏作品证明引用",
            creditBoundaryLabel: directCreditBlocked ? "作品展示不能直接发成长积分" : "成长积分建议需家长/正式流程确认",
            nextStep: nextStep(role: role, state: state),
            safetyNote: safetyNote(role: role),
            state: state,
            visibleToChild: role == .child && state != .blocked,
            visibleToGuardian: role == .guardian,
            visibleToRelative: visibleToRelative,
            childAssentGranted: childAssentGranted,
            guardianApproved: guardianApproved,
            moderationPassed: moderationPassed,
            privateByChild: privateByChild,
            withdrawn: withdrawn,
            rewardPressureBlocked: rewardPressureBlocked,
            directCreditBlocked: directCreditBlocked
        )
    }

    private func proof(
        from proof: CreatorManifestProofRequirementDraft,
        role: MobileCreativeShowcaseViewerRole
    ) -> MobileCreativeShowcaseProofRow {
        MobileCreativeShowcaseProofRow(
            publicProofRef: publicRef("mcsp", proof.proofId),
            title: role == .relative ? "作品证明引用" : proof.kind.label,
            verifierLabels: role == .guardian ? proof.verifierRoles.map(\.label) : ["家长"],
            instructions: role == .guardian ? proof.instructions : "作品是否展示由家长确认；本页只读。"
        )
    }

    private func publicProof(_ proof: MobileCreativeShowcaseProofRow) -> MobileCreativeShowcaseProofRow {
        MobileCreativeShowcaseProofRow(
            publicProofRef: proof.publicProofRef,
            title: "作品证明引用",
            verifierLabels: ["家长"],
            instructions: "作品是否展示由家长确认；本页只读。"
        )
    }

    private func promptCopy(role: MobileCreativeShowcaseViewerRole) -> String {
        switch role {
        case .child:
            return "完成作品后先自检，再请家长决定是否展示。"
        case .guardian:
            return "作品展示只保存脱敏引用，真实发布必须走正式审核。"
        case .relative:
            return "这里仅展示家长批准后的作品摘要。"
        }
    }

    private func safetyNote(role: MobileCreativeShowcaseViewerRole) -> String {
        switch role {
        case .child, .guardian:
            return "本页不打开相机/相册/文件，不上传作品，不发布到社交平台。"
        case .relative:
            return "亲友只能看已批准摘要，互动和奖励都由家长流程处理。"
        }
    }

    private func findingRows(
        role: MobileCreativeShowcaseViewerRole,
        items: [MobileCreativeShowcaseItem]
    ) -> [MobileCreativeShowcaseFinding] {
        var findings: [MobileCreativeShowcaseFinding] = []
        if items.contains(where: { $0.state == .waitingGuardianReview }) {
            findings.append(finding(.approvalRequired, "作品仍需家长审核或内容审核，不能对亲友展示。", true, child: true, relative: false))
        }
        if items.contains(where: { $0.privateByChild || $0.withdrawn || !$0.childAssentGranted || !$0.visibleToRelative }) {
            findings.append(finding(.privacyVisibilityBlocked, "私密、撤回、未同意或未批准作品不会进入亲友展示面。", true, child: false, relative: false))
        }
        if items.contains(where: \.rewardPressureBlocked) {
            findings.append(finding(.rewardPressureBlocked, "亲友奖励承诺或压力语言会阻断展示。", true, child: false, relative: false))
        }
        if items.contains(where: \.directCreditBlocked) {
            findings.append(finding(.creditBoundaryBlocked, "作品完成不能直接写账本、发成长积分或解锁设备。", true, child: false, relative: false))
        }
        if findings.isEmpty {
            findings.append(finding(
                .readOnlyReady,
                role == .relative ? "当前仅展示已批准的脱敏作品摘要。" : "创作展示安全壳只读就绪，后续仍需正式审核流程处理。",
                false,
                child: true,
                relative: true
            ))
        }
        return findings
    }

    private func finding(
        _ code: MobileCreativeShowcaseFindingCode,
        _ message: String,
        _ actionRequired: Bool,
        child: Bool,
        relative: Bool
    ) -> MobileCreativeShowcaseFinding {
        MobileCreativeShowcaseFinding(
            code: code,
            message: message,
            actionRequired: actionRequired,
            visibleToChild: child,
            visibleToRelative: relative
        )
    }

    private func isVisible(
        _ item: MobileCreativeShowcaseItem,
        to role: MobileCreativeShowcaseViewerRole
    ) -> Bool {
        switch role {
        case .child: return item.state != .blocked
        case .guardian: return item.visibleToGuardian
        case .relative: return item.visibleToRelative && item.state == .approvedPreview
        }
    }

    private func nextStep(
        role: MobileCreativeShowcaseViewerRole,
        state: MobileCreativeShowcaseState
    ) -> String {
        switch (role, state) {
        case (.child, .approvedPreview):
            return "可以请家长确认是否加入家庭展示。"
        case (.child, .waitingGuardianReview):
            return "先完成自检，等待家长审核。"
        case (.guardian, .approvedPreview):
            return "确认可见范围后，再交给正式发布流程。"
        case (.guardian, .waitingGuardianReview):
            return "先检查同意、内容、亲友可见和奖励压力。"
        case (.relative, .approvedPreview):
            return "可以表达支持，但不能承诺奖励或要求孩子兑换。"
        default:
            return "该作品暂不展示，请先修正安全边界。"
        }
    }

    private func safeFallback(
        role: MobileCreativeShowcaseViewerRole,
        hiddenCount: Int
    ) -> MobileCreativeShowcaseSafetyWorkbench {
        MobileCreativeShowcaseSafetyWorkbench(
            role: role,
            title: "创作作品已被安全保护",
            subtitle: "本地安全壳",
            audienceNote: role.audienceNote,
            showcases: [],
            proofs: [],
            findings: [
                finding(
                    .unsafePayloadBlocked,
                    "检测到链接、路径、密钥、局域网地址、内部标识或成长积分/设备敏感语义，本地壳不回显原文。",
                    role == .guardian,
                    child: false,
                    relative: false
                )
            ],
            publicSummary: MobileCreativeShowcasePublicSummary(
                role: role,
                showcaseCount: hiddenCount,
                visibleShowcaseCount: 0,
                pendingReviewCount: 0,
                hiddenFromRelativeCount: hiddenCount,
                blockedCount: hiddenCount,
                proofRequirementCount: 0,
                directCreditBlockedCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        var hash: UInt32 = 5381
        for scalar in "mobile-creative-showcase:\(source)".unicodeScalars {
            hash = (hash &* 33) ^ (scalar.value & 0xFFFF)
        }
        return "\(prefix)-\(String(hash, radix: 36))"
    }
}
