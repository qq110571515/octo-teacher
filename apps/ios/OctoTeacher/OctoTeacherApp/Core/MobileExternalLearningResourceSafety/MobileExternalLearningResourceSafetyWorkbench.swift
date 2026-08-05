import Foundation

/// iOS 外部学习资源安全壳的纯本地只读投影。
///
/// 它只把成长包 Manifest 中的外部视频/网页资源组织成孩子和家长可看的安全状态：
/// 不展示原始 URL、域名、短链或内部审核字段，不打开外链/WebView，不下载媒体，
/// 不上传证明，不写账本，不发成长积分，不解锁设备。
enum MobileExternalLearningResourceViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        }
    }

    var audienceNote: String {
        switch self {
        case .child:
            return "这里只显示学习目标、可信来源标签和下一步；不会打开链接，也不会显示网址或域名。"
        case .guardian:
            return "只读查看来源、白名单、年龄、版权、证明和成长积分边界；真正放行仍需要正式审核。"
        }
    }
}

enum MobileExternalLearningResourceState: String, Equatable {
    case ready
    case guardianReview
    case blocked
    case hiddenFromChild

    var label: String {
        switch self {
        case .ready: return "可学习"
        case .guardianReview: return "需家长复核"
        case .blocked: return "已阻断"
        case .hiddenFromChild: return "孩子不可见"
        }
    }
}

enum MobileExternalLearningResourceFindingCode: String, Equatable {
    case readOnlyReady = "READ_ONLY_READY"
    case allowlistBlocked = "ALLOWLIST_BLOCKED"
    case ageMismatchBlocked = "AGE_MISMATCH_BLOCKED"
    case creditBoundaryBlocked = "CREDIT_BOUNDARY_BLOCKED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

struct MobileExternalLearningResourceRow: Identifiable, Equatable {
    var publicResourceRef: String
    var title: String
    var sourceLabel: String
    var resourceKindLabel: String
    var ageLabel: String
    var licenseLabel: String
    var proofLabel: String
    var creditBoundaryLabel: String
    var nextStep: String
    var safetyNote: String
    var state: MobileExternalLearningResourceState
    var visibleToChild: Bool
    var allowlisted: Bool
    var ageAppropriate: Bool
    var licenseActive: Bool
    var guardianReviewRequired: Bool
    var creditRequiresGuardianApproval: Bool
    var directCreditBlocked: Bool

    let showsRawURL = false
    let showsDomain = false
    let opensExternalURL = false
    let opensWebView = false
    let opensBrowser = false
    let downloadsMedia = false
    let callsNetwork = false
    let uploadsProof = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let writesMarketplace = false

    var id: String { publicResourceRef }

    var displayValues: [String] {
        [
            title,
            sourceLabel,
            resourceKindLabel,
            ageLabel,
            licenseLabel,
            proofLabel,
            creditBoundaryLabel,
            nextStep,
            safetyNote,
            state.rawValue,
            state.label
        ]
    }
}

struct MobileExternalLearningResourceProofRow: Identifiable, Equatable {
    var publicProofRef: String
    var title: String
    var verifierLabels: [String]
    var instructions: String

    let uploadsProof = false
    let writesLedger = false
    let grantsCredit = false

    var id: String { publicProofRef }

    var displayValues: [String] { [title, instructions] + verifierLabels }
}

struct MobileExternalLearningResourceFinding: Identifiable, Equatable {
    var code: MobileExternalLearningResourceFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool

    var id: String { code.rawValue }

    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileExternalLearningResourcePublicSummary: Equatable {
    var role: MobileExternalLearningResourceViewerRole
    var resourceCount: Int
    var visibleResourceCount: Int
    var blockedResourceCount: Int
    var guardianReviewCount: Int
    var proofRequirementCount: Int
    var directCreditBlockedCount: Int
    var findingCodes: [MobileExternalLearningResourceFindingCode]

    let showsRawURL = false
    let showsDomain = false
    let opensExternalURL = false
    let opensWebView = false
    let opensBrowser = false
    let downloadsMedia = false
    let callsNetwork = false
    let callsAIProvider = false
    let uploadsProof = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let writesMarketplace = false

    var hasTriggeredSideEffect: Bool {
        showsRawURL || showsDomain || opensExternalURL || opensWebView || opensBrowser
            || downloadsMedia || callsNetwork || callsAIProvider || uploadsProof
            || writesLedger || grantsCredit || unlocksDevice || writesMarketplace
    }
}

struct MobileExternalLearningResourceSafetyWorkbench: Equatable {
    var role: MobileExternalLearningResourceViewerRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var resources: [MobileExternalLearningResourceRow]
    var proofs: [MobileExternalLearningResourceProofRow]
    var findings: [MobileExternalLearningResourceFinding]
    var publicSummary: MobileExternalLearningResourcePublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + resources.flatMap(\.displayValues)
            + proofs.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileExternalLearningResourceSafetyBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileExternalLearningResourceSafetyBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "creator:", "resource:", "link:", "url:",
        "content:", "proof:", "session:", "device:", "ledger:", "credit:",
        "token", "secret", "api_key", "apikey", "bearer ", "domain:",
        "shortlink", "bit.ly", "t.co", "youtu.be", "youtube.com",
        "vimeo.com", "http://", "https://", "file://", "/users/",
        "/volumes/", "192.168.", "www."
    ]

    private static let likelyDomainPattern = #"[a-z0-9-]+\.(com|cn|net|org|edu)(/|\s|$)"#

    func build(
        role: MobileExternalLearningResourceViewerRole,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock,
        childAge: Int = 10
    ) -> MobileExternalLearningResourceSafetyWorkbench {
        if Self.hasUnsafeDraftPayload(draft) {
            return safeFallback(role: role, hiddenCount: externalBlocks(in: draft).count)
        }

        let externalBlocks = externalBlocks(in: draft)
        let resourceRows = externalBlocks.map { resource(from: $0, role: role, draft: draft, childAge: childAge) }
        let visibleRows = resourceRows.filter { role == .guardian || ($0.visibleToChild && $0.state != .blocked) }
        let visibleResourceRefs = Set(visibleRows.map(\.publicResourceRef))
        let proofSourceBlocks: [CreatorManifestContentDraft]
        if role == .guardian {
            proofSourceBlocks = externalBlocks
        } else {
            proofSourceBlocks = externalBlocks.filter { visibleResourceRefs.contains(publicRef("mer", $0.contentId)) }
        }
        let proofIds = Set(proofSourceBlocks.flatMap(\.proofRequirementIds))
        let proofRows = draft.proofRequirements
            .filter { proofIds.contains($0.proofId) }
            .map { proof(from: $0, role: role) }
        let findings = findingRows(role: role, rows: resourceRows)
        let summary = MobileExternalLearningResourcePublicSummary(
            role: role,
            resourceCount: resourceRows.count,
            visibleResourceCount: visibleRows.count,
            blockedResourceCount: resourceRows.filter { $0.state == .blocked }.count,
            guardianReviewCount: resourceRows.filter(\.guardianReviewRequired).count,
            proofRequirementCount: proofRows.count,
            directCreditBlockedCount: resourceRows.filter(\.directCreditBlocked).count,
            findingCodes: findings.map(\.code)
        )
        let workbench = MobileExternalLearningResourceSafetyWorkbench(
            role: role,
            title: "外部学习资源安全壳",
            subtitle: "\(draft.title) · \(draft.ageBand.gradeBand)",
            audienceNote: role.audienceNote,
            resources: visibleRows,
            proofs: role == .child ? proofRows.map(childProof) : proofRows,
            findings: findings.filter { role == .guardian || $0.visibleToChild },
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? safeFallback(role: role, hiddenCount: externalBlocks.count) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
            || joined.range(of: likelyDomainPattern, options: .regularExpression) != nil
    }

    private static func hasUnsafeDraftPayload(_ draft: CreatorManifestPreviewDraft) -> Bool {
        let values = [draft.title, draft.summary, draft.contentVersion, draft.ageBand.gradeBand]
            + draft.contentBlocks.flatMap { [$0.title, $0.summary] }
            + draft.proofRequirements.map(\.instructions)
            + draft.creditDrafts.flatMap { [$0.scopeLabel, $0.reason] }
        return hasUnsafeDisplayPayload(values)
    }

    private func externalBlocks(in draft: CreatorManifestPreviewDraft) -> [CreatorManifestContentDraft] {
        draft.contentBlocks.filter { $0.kind == .externalVideo }
    }

    private func resource(
        from block: CreatorManifestContentDraft,
        role: MobileExternalLearningResourceViewerRole,
        draft: CreatorManifestPreviewDraft,
        childAge: Int
    ) -> MobileExternalLearningResourceRow {
        let allowlisted = draft.licenseBoundary.allowsExternalVideo && block.assetModerationPassed && !block.containsDirectAnswer
        let ageAppropriate = draft.ageBand.minAge <= childAge && childAge <= draft.ageBand.maxAge
        let licenseActive = draft.licenseBoundary.allowsExternalVideo
        let creditDrafts = draft.creditDrafts.filter { $0.triggerContentId == block.contentId }
        let directCreditBlocked = creditDrafts.contains { !$0.requiresGuardianApproval || $0.writesLedger }
        let blocked = !allowlisted || !ageAppropriate || !licenseActive || directCreditBlocked || block.status == .missing
        let state: MobileExternalLearningResourceState
        if blocked {
            state = .blocked
        } else if role == .child && !block.visibleToChild {
            state = .hiddenFromChild
        } else if block.guardianReviewRequired || draft.ageBand.requiresGuardianConsent {
            state = .guardianReview
        } else {
            state = .ready
        }

        return MobileExternalLearningResourceRow(
            publicResourceRef: publicRef("mer", block.contentId),
            title: block.title,
            sourceLabel: allowlisted ? "可信学习来源" : "来源待复核",
            resourceKindLabel: "外部视频/网页引用",
            ageLabel: ageAppropriate ? "\(draft.ageBand.gradeBand) · 需家长同意" : "年龄标签不匹配",
            licenseLabel: licenseActive ? "版权边界允许引用" : "版权或许可已阻断",
            proofLabel: block.proofRequirementIds.isEmpty ? "无需外部完成证明" : "只保存脱敏证明引用",
            creditBoundaryLabel: directCreditBlocked ? "外部完成不能直接发成长积分" : "成长积分需家长/正式流程确认",
            nextStep: nextStep(for: role, blocked: blocked),
            safetyNote: role == .child
                ? "不展示网址、域名或短链；请在家长陪同下学习。"
                : "本页只读检查来源、白名单、版权、年龄和证明边界。",
            state: state,
            visibleToChild: block.visibleToChild && !blocked,
            allowlisted: allowlisted,
            ageAppropriate: ageAppropriate,
            licenseActive: licenseActive,
            guardianReviewRequired: block.guardianReviewRequired || draft.ageBand.requiresGuardianConsent,
            creditRequiresGuardianApproval: creditDrafts.allSatisfy(\.requiresGuardianApproval),
            directCreditBlocked: directCreditBlocked
        )
    }

    private func proof(
        from proof: CreatorManifestProofRequirementDraft,
        role: MobileExternalLearningResourceViewerRole
    ) -> MobileExternalLearningResourceProofRow {
        MobileExternalLearningResourceProofRow(
            publicProofRef: publicRef("merp", proof.proofId),
            title: proof.kind.label,
            verifierLabels: role == .child ? ["家长"] : proof.verifierRoles.map(\.label),
            instructions: role == .child ? "学习完成后等待家长确认，本页不打开链接、不上传证明。" : proof.instructions
        )
    }

    private func childProof(_ proof: MobileExternalLearningResourceProofRow) -> MobileExternalLearningResourceProofRow {
        MobileExternalLearningResourceProofRow(
            publicProofRef: proof.publicProofRef,
            title: proof.title,
            verifierLabels: ["家长"],
            instructions: "学习完成后等待家长确认，本页不打开链接、不上传证明。"
        )
    }

    private func findingRows(
        role: MobileExternalLearningResourceViewerRole,
        rows: [MobileExternalLearningResourceRow]
    ) -> [MobileExternalLearningResourceFinding] {
        if rows.isEmpty {
            return [
                MobileExternalLearningResourceFinding(
                    code: .readOnlyReady,
                    message: "当前成长包没有外部学习资源；本地壳不会访问网络。",
                    actionRequired: false,
                    visibleToChild: true
                )
            ]
        }

        var findings: [MobileExternalLearningResourceFinding] = []
        if rows.contains(where: { !$0.allowlisted || !$0.licenseActive }) {
            findings.append(MobileExternalLearningResourceFinding(
                code: .allowlistBlocked,
                message: "存在非白名单、未过审或许可阻断的外部学习资源。",
                actionRequired: true,
                visibleToChild: false
            ))
        }
        if rows.contains(where: { !$0.ageAppropriate }) {
            findings.append(MobileExternalLearningResourceFinding(
                code: .ageMismatchBlocked,
                message: "存在年龄标签与孩子成长包不匹配的外部学习资源。",
                actionRequired: true,
                visibleToChild: false
            ))
        }
        if rows.contains(where: \.directCreditBlocked) {
            findings.append(MobileExternalLearningResourceFinding(
                code: .creditBoundaryBlocked,
                message: "外部资源完成状态不能直接写账本、发成长积分或解锁设备。",
                actionRequired: true,
                visibleToChild: false
            ))
        }
        if findings.isEmpty {
            findings.append(MobileExternalLearningResourceFinding(
                code: .readOnlyReady,
                message: role == .child
                    ? "外部学习资源只显示安全学习提示，完成后等待家长确认。"
                    : "外部学习资源安全壳只读就绪；来源、年龄、许可和证明边界均可进入人工复核。",
                actionRequired: false,
                visibleToChild: true
            ))
        }
        return findings
    }

    private func nextStep(
        for role: MobileExternalLearningResourceViewerRole,
        blocked: Bool
    ) -> String {
        if blocked {
            return role == .child ? "这个资源暂时不可学习，请等待家长换一个资源。" : "先修正来源、年龄、版权或成长积分边界，再进入孩子端。"
        }
        return role == .child ? "请在家长陪同下完成学习，然后等待确认。" : "确认来源和证明规则后，再交给正式审核流程。"
    }

    private func safeFallback(
        role: MobileExternalLearningResourceViewerRole,
        hiddenCount: Int
    ) -> MobileExternalLearningResourceSafetyWorkbench {
        MobileExternalLearningResourceSafetyWorkbench(
            role: role,
            title: "外部学习资源已被安全保护",
            subtitle: "本地安全壳",
            audienceNote: role.audienceNote,
            resources: [],
            proofs: [],
            findings: [
                MobileExternalLearningResourceFinding(
                    code: .unsafePayloadBlocked,
                    message: "检测到网址、域名、短链、路径、密钥、局域网地址或内部标识，本地壳不回显原文。",
                    actionRequired: role == .guardian,
                    visibleToChild: false
                )
            ],
            publicSummary: MobileExternalLearningResourcePublicSummary(
                role: role,
                resourceCount: hiddenCount,
                visibleResourceCount: 0,
                blockedResourceCount: hiddenCount,
                guardianReviewCount: 0,
                proofRequirementCount: 0,
                directCreditBlockedCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        var hash: UInt32 = 5381
        for scalar in "mobile-external-learning-resource:\(source)".unicodeScalars {
            hash = (hash &* 33) ^ (scalar.value & 0xFFFF)
        }
        return "\(prefix)-\(String(hash, radix: 36))"
    }
}
