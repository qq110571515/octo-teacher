import Foundation

/// iOS 端「创作者 Manifest V1 预览 / 校验」只读快照。
///
/// 这是成长包创作者/家长在手机端查看草稿的本地消费壳：只投影内容块、证明要求、
/// 成长积分建议草稿、徽章/能力草稿、许可边界、年龄分级和阻断发现项。不上传、不发布、
/// 不收费、不写审核队列、不发成长积分、不调用 AI。
enum CreatorManifestPreviewViewerRole: String, Equatable, CaseIterable {
    case creator
    case guardian
    case child
    case relative
    case teacher

    var label: String {
        switch self {
        case .creator: return "创作者"
        case .guardian: return "家长"
        case .child: return "孩子"
        case .relative: return "亲友"
        case .teacher: return "老师"
        }
    }
}

enum CreatorManifestPreviewStatus: String, Equatable {
    case readyForReview = "ready_for_review"
    case needsWork = "needs_work"
    case blocked
    case hidden

    var label: String {
        switch self {
        case .readyForReview: return "可提交审核"
        case .needsWork: return "需要补齐"
        case .blocked: return "已阻断"
        case .hidden: return "不可见"
        }
    }
}

enum CreatorManifestContentKind: String, Equatable, CaseIterable {
    case text
    case image
    case quiz
    case externalVideo = "external_video"
    case gameScreenshotProof = "game_screenshot_proof"
    case exerciseProof = "exercise_proof"
    case creatorUpload = "creator_upload"
    case schoolHomeworkHook = "school_homework_hook"

    var label: String {
        switch self {
        case .text: return "文字"
        case .image: return "图片"
        case .quiz: return "测验"
        case .externalVideo: return "视频链接"
        case .gameScreenshotProof: return "游戏截图证明"
        case .exerciseProof: return "运动证明"
        case .creatorUpload: return "创作上传"
        case .schoolHomeworkHook: return "学校作业挂钩"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .quiz: return "checklist"
        case .externalVideo: return "play.rectangle"
        case .gameScreenshotProof: return "gamecontroller"
        case .exerciseProof: return "figure.run"
        case .creatorUpload: return "paintpalette"
        case .schoolHomeworkHook: return "graduationcap"
        }
    }
}

enum CreatorManifestProofKind: String, Equatable {
    case quizResult = "quiz_result"
    case externalVideoRef = "external_video_ref"
    case gameScreenshot = "game_screenshot"
    case exerciseSignal = "exercise_signal"
    case creatorUploadRef = "creator_upload_ref"
    case teacherGuardianCheck = "teacher_guardian_check"

    var label: String {
        switch self {
        case .quizResult: return "测验结果"
        case .externalVideoRef: return "视频观看引用"
        case .gameScreenshot: return "游戏截图"
        case .exerciseSignal: return "运动信号"
        case .creatorUploadRef: return "创作上传引用"
        case .teacherGuardianCheck: return "老师/家长核验"
        }
    }
}

enum CreatorManifestVerifierRole: String, Equatable {
    case system
    case guardian
    case teacher
    case creator

    var label: String {
        switch self {
        case .system: return "系统"
        case .guardian: return "家长"
        case .teacher: return "老师"
        case .creator: return "创作者"
        }
    }
}

enum CreatorManifestPreviewFindingCode: String, Equatable {
    case manifestPreviewOK = "MANIFEST_PREVIEW_OK"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case nonAuthorPreviewHidden = "NON_AUTHOR_PREVIEW_HIDDEN"
    case draftContentIncomplete = "DRAFT_CONTENT_INCOMPLETE"
    case proofRequirementIncomplete = "PROOF_REQUIREMENT_INCOMPLETE"
    case directAnswerBlocked = "DIRECT_ANSWER_BLOCKED"
    case licenseBoundaryBlocked = "LICENSE_BOUNDARY_BLOCKED"
    case ageRatingBlocked = "AGE_RATING_BLOCKED"
    case creditSuggestionBlocked = "CREDIT_SUGGESTION_BLOCKED"
    case assetModerationRequired = "ASSET_MODERATION_REQUIRED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

enum CreatorManifestPreviewSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

enum CreatorManifestDraftBlockStatus: String, Equatable {
    case draft
    case complete
    case missing

    var label: String {
        switch self {
        case .draft: return "草稿"
        case .complete: return "完整"
        case .missing: return "缺失"
        }
    }
}

struct CreatorManifestContentDraft: Equatable {
    var contentId: String
    var kind: CreatorManifestContentKind
    var title: String
    var summary: String
    var status: CreatorManifestDraftBlockStatus
    var proofRequirementIds: [String]
    var guardianReviewRequired: Bool
    var visibleToChild: Bool
    var assetModerationPassed: Bool
    var containsDirectAnswer: Bool
}

struct CreatorManifestProofRequirementDraft: Equatable {
    var proofId: String
    var kind: CreatorManifestProofKind
    var verifierRoles: [CreatorManifestVerifierRole]
    var instructions: String
    var evidenceRefsOnly: Bool
    var status: CreatorManifestDraftBlockStatus
}

struct CreatorManifestCreditDraft: Equatable {
    var creditId: String
    var triggerContentId: String
    var amount: Int
    var scopeLabel: String
    var reason: String
    var requiresGuardianApproval: Bool
    var writesLedger: Bool

    var amountLabel: String { "\(amount) 成长积分" }
}

struct CreatorManifestBadgeAbilityDraft: Equatable {
    enum Kind: String, Equatable {
        case badge
        case abilityCard = "ability_card"

        var label: String {
            switch self {
            case .badge: return "徽章"
            case .abilityCard: return "能力卡"
            }
        }
    }

    var draftId: String
    var kind: Kind
    var title: String
    var category: String
    var requiresHumanReview: Bool
    var mutatesProfile: Bool
}

struct CreatorManifestLicenseBoundaryDraft: Equatable {
    var licenseId: String
    var allowsExternalVideo: Bool
    var allowsCreatorUpload: Bool
    var allowsSchoolHook: Bool
    var marketPublishReady: Bool
}

struct CreatorManifestAgeBandDraft: Equatable {
    var minAge: Int
    var maxAge: Int
    var gradeBand: String
    var requiresGuardianConsent: Bool
}

struct CreatorManifestPreviewDraft: Equatable {
    var manifestId: String
    var creatorId: String
    var packId: String
    var title: String
    var summary: String
    var contentVersion: String
    var contentBlocks: [CreatorManifestContentDraft]
    var proofRequirements: [CreatorManifestProofRequirementDraft]
    var creditDrafts: [CreatorManifestCreditDraft]
    var badgeAbilityDrafts: [CreatorManifestBadgeAbilityDraft]
    var licenseBoundary: CreatorManifestLicenseBoundaryDraft
    var ageBand: CreatorManifestAgeBandDraft
    var generatedAt: String
}

struct CreatorManifestContentPreview: Identifiable, Equatable {
    var publicContentRef: String
    var kind: CreatorManifestContentKind
    var title: String
    var summary: String
    var status: CreatorManifestDraftBlockStatus
    var requiredProofCount: Int
    var guardianReviewRequired: Bool
    var assetModerationPassed: Bool
    var visibleToChild: Bool

    var id: String { publicContentRef }
}

struct CreatorManifestProofPreview: Identifiable, Equatable {
    var publicProofRef: String
    var kind: CreatorManifestProofKind
    var verifierRoles: [CreatorManifestVerifierRole]
    var instructions: String
    var evidenceRefsOnly: Bool
    var status: CreatorManifestDraftBlockStatus

    var id: String { publicProofRef }
}

struct CreatorManifestCreditPreview: Identifiable, Equatable {
    var publicCreditRef: String
    var amount: Int
    var scopeLabel: String
    var reason: String
    var requiresGuardianApproval: Bool

    let writesLedger = false
    let issuesCredit = false
    let unlocksDevice = false

    var id: String { publicCreditRef }
    var amountLabel: String { "\(amount) 成长积分" }
}

struct CreatorManifestBadgeAbilityPreview: Identifiable, Equatable {
    var publicDraftRef: String
    var kind: CreatorManifestBadgeAbilityDraft.Kind
    var title: String
    var category: String
    var requiresHumanReview: Bool

    let grantsBadge = false
    let mutatesAbilityCard = false

    var id: String { publicDraftRef }
}

struct CreatorManifestLicenseBoundaryPreview: Equatable {
    var publicLicenseRef: String
    var allowsExternalVideo: Bool
    var allowsCreatorUpload: Bool
    var allowsSchoolHook: Bool
    var marketPublishReady: Bool

    let chargesPayment = false
    let publishesPack = false
    let writesMarketplace = false
}

struct CreatorManifestAgeRatingPreview: Equatable {
    var minAge: Int
    var maxAge: Int
    var gradeBand: String
    var requiresGuardianConsent: Bool
    var safeForChildPreview: Bool
}

struct CreatorManifestPreviewFinding: Identifiable, Equatable {
    var code: CreatorManifestPreviewFindingCode
    var severity: CreatorManifestPreviewSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct CreatorManifestPreviewVisibility: Equatable {
    var viewerRole: CreatorManifestPreviewViewerRole
    var canSeeManifest: Bool
    var canSeeProofRequirements: Bool
    var canSeeCreditDrafts: Bool
    var canSeeBadgeAbilityDrafts: Bool
    var canSeeLicenseBoundary: Bool
    var canSeeBlockingFindings: Bool
}

struct CreatorManifestPreviewPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: CreatorManifestPreviewViewerRole
    var status: CreatorManifestPreviewStatus
    var packPublicRef: String
    var creatorPublicRef: String
    var title: String
    var contentVersion: String
    var visibleContentCount: Int
    var visibleProofCount: Int
    var visibleCreditDraftCount: Int
    var visibleBadgeAbilityCount: Int
    var findingCodes: [CreatorManifestPreviewFindingCode]

    let uploadsMedia = false
    let publishesPack = false
    let chargesPayment = false
    let writesReviewQueue = false
    let writesMarketplace = false
    let writesLedger = false
    let issuesCredit = false
    let grantsBadge = false
    let mutatesAbilityCard = false
    let callsAi = false
    let fetchesExternalMedia = false
    let unlocksDevice = false
}

struct CreatorManifestPreviewSnapshot: Equatable {
    var generatedAt: String
    var viewerRole: CreatorManifestPreviewViewerRole
    var status: CreatorManifestPreviewStatus
    var manifestVersion: String
    var title: String
    var summary: String
    var contentBlocks: [CreatorManifestContentPreview]
    var proofRequirements: [CreatorManifestProofPreview]
    var creditDrafts: [CreatorManifestCreditPreview]
    var badgeAbilityDrafts: [CreatorManifestBadgeAbilityPreview]
    var licenseBoundary: CreatorManifestLicenseBoundaryPreview?
    var ageRating: CreatorManifestAgeRatingPreview
    var visibility: CreatorManifestPreviewVisibility
    var findings: [CreatorManifestPreviewFinding]
    var publicSummary: CreatorManifestPreviewPublicSummary
}

struct CreatorManifestPreviewSnapshotBuilder {
    var generatedAt: String = "2026-06-24T11:00:00Z"
    var manifestVersion: String = "manifest-v1-local-ios"
    var redactionSalt: String = "creator-manifest-preview-ios-v1"

    func build(
        viewerRole: CreatorManifestPreviewViewerRole,
        draft: CreatorManifestPreviewDraft = .mock
    ) -> CreatorManifestPreviewSnapshot {
        let visibility = visibility(for: viewerRole)
        let baseFindings = validate(draft)
        let status = statusFor(role: viewerRole, findings: baseFindings, visibility: visibility)
        let content = visibility.canSeeManifest ? contentPreviews(draft, role: viewerRole) : []
        let proofs = visibility.canSeeProofRequirements ? proofPreviews(draft) : []
        let credits = visibility.canSeeCreditDrafts ? creditPreviews(draft) : []
        let badgeAbilities = visibility.canSeeBadgeAbilityDrafts ? badgeAbilityPreviews(draft) : []
        let license = visibility.canSeeLicenseBoundary ? licensePreview(draft) : nil
        let findings = visibleFindings(baseFindings, visibility: visibility)
        let snapshot = CreatorManifestPreviewSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            manifestVersion: manifestVersion,
            title: visibility.canSeeManifest ? draft.title : "预览不可见",
            summary: visibility.canSeeManifest ? draft.summary : "该视角只能查看已公开的成长摘要。",
            contentBlocks: content,
            proofRequirements: proofs,
            creditDrafts: credits,
            badgeAbilityDrafts: badgeAbilities,
            licenseBoundary: license,
            ageRating: ageRating(draft, visibility: visibility),
            visibility: visibility,
            findings: findings,
            publicSummary: publicSummary(
                role: viewerRole,
                status: status,
                draft: draft,
                visibility: visibility,
                content: content,
                proofs: proofs,
                credits: credits,
                badgeAbilities: badgeAbilities,
                findings: findings
            )
        )
        return redacts(snapshot) ? snapshot : safeFallback(role: viewerRole, visibility: visibility)
    }

    func redacts(_ snapshot: CreatorManifestPreviewSnapshot) -> Bool {
        let values = displayValues(snapshot)
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ").lowercased()
        let blocked = [
            "creator:", "child:", "family:", "pack:", "content:", "license:",
            "homework:", "proof:", "media:", "ledger:", "device:", "task:", "claim:"
        ]
        return !blocked.contains { joined.contains($0) }
    }

    // MARK: - Validation

    private func validate(_ draft: CreatorManifestPreviewDraft) -> [CreatorManifestPreviewFinding] {
        var result: [CreatorManifestPreviewFinding] = []
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            draft.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            draft.contentBlocks.contains(where: { $0.title.isEmpty || $0.summary.isEmpty || $0.status != .complete }) {
            result.append(finding(.draftContentIncomplete, .blocker, "成长包内容块还没有补齐。", "content"))
        }
        if draft.proofRequirements.contains(where: { $0.status != .complete || $0.instructions.isEmpty || !$0.evidenceRefsOnly || $0.verifierRoles.isEmpty }) {
            result.append(finding(.proofRequirementIncomplete, .blocker, "证明要求必须完整且只保存证据引用。", "proof"))
        }
        if draft.contentBlocks.contains(where: { $0.containsDirectAnswer }) {
            result.append(finding(.directAnswerBlocked, .blocker, "Manifest 不允许直接答案型作业包进入预览。", "direct-answer"))
        }
        if draft.contentBlocks.contains(where: { !$0.assetModerationPassed }) {
            result.append(finding(.assetModerationRequired, .warning, "部分素材还需要完成安全审核。", "asset"))
        }
        if !draft.licenseBoundary.allowsExternalVideo && draft.contentBlocks.contains(where: { $0.kind == .externalVideo }) {
            result.append(finding(.licenseBoundaryBlocked, .blocker, "许可边界不允许外部视频内容。", "license-video"))
        }
        if !draft.licenseBoundary.allowsCreatorUpload && draft.contentBlocks.contains(where: { $0.kind == .creatorUpload }) {
            result.append(finding(.licenseBoundaryBlocked, .blocker, "许可边界不允许创作者上传内容。", "license-upload"))
        }
        if !draft.licenseBoundary.allowsSchoolHook && draft.contentBlocks.contains(where: { $0.kind == .schoolHomeworkHook }) {
            result.append(finding(.licenseBoundaryBlocked, .blocker, "许可边界不允许学校作业挂钩。", "license-school"))
        }
        if draft.ageBand.minAge < 4 || draft.ageBand.maxAge > 18 || draft.ageBand.minAge > draft.ageBand.maxAge || !draft.ageBand.requiresGuardianConsent {
            result.append(finding(.ageRatingBlocked, .blocker, "年龄分级必须落在孩子产品安全范围内，并需要家长许可。", "age"))
        }
        if draft.creditDrafts.contains(where: { $0.amount <= 0 || $0.amount > 120 || !$0.requiresGuardianApproval || $0.writesLedger }) {
            result.append(finding(.creditSuggestionBlocked, .blocker, "成长积分建议必须经过家长审批，且不能写账本。", "credit"))
        }
        if draft.badgeAbilityDrafts.contains(where: { !$0.requiresHumanReview || $0.mutatesProfile }) {
            result.append(finding(.creditSuggestionBlocked, .blocker, "徽章和能力卡只能作为人工审核草稿。", "badge"))
        }
        if hasUnsafeText(draft) {
            result.append(finding(.unsafePayloadBlocked, .blocker, "Manifest 文案含有不安全 payload、局域网地址或内部标识。", "unsafe"))
        }
        if result.isEmpty {
            result.append(finding(.manifestPreviewOK, .ok, "Manifest 预览已脱敏，可进入人工审核。", "ok"))
        }
        return unique(result)
    }

    private func hasUnsafeText(_ draft: CreatorManifestPreviewDraft) -> Bool {
        let values =
            [draft.title, draft.summary, draft.contentVersion]
            + draft.contentBlocks.flatMap { [$0.title, $0.summary] }
            + draft.proofRequirements.map(\.instructions)
            + draft.creditDrafts.flatMap { [$0.reason, $0.scopeLabel] }
            + draft.badgeAbilityDrafts.flatMap { [$0.title, $0.category] }
            + [draft.ageBand.gradeBand]
        return MobileSyncPayloadGuard.isUnsafe(values)
    }

    // MARK: - Mapping

    private func visibility(for role: CreatorManifestPreviewViewerRole) -> CreatorManifestPreviewVisibility {
        switch role {
        case .creator, .guardian:
            return CreatorManifestPreviewVisibility(
                viewerRole: role,
                canSeeManifest: true,
                canSeeProofRequirements: true,
                canSeeCreditDrafts: true,
                canSeeBadgeAbilityDrafts: true,
                canSeeLicenseBoundary: true,
                canSeeBlockingFindings: true
            )
        case .teacher:
            return CreatorManifestPreviewVisibility(
                viewerRole: role,
                canSeeManifest: true,
                canSeeProofRequirements: true,
                canSeeCreditDrafts: false,
                canSeeBadgeAbilityDrafts: false,
                canSeeLicenseBoundary: false,
                canSeeBlockingFindings: false
            )
        case .child:
            return CreatorManifestPreviewVisibility(
                viewerRole: role,
                canSeeManifest: true,
                canSeeProofRequirements: true,
                canSeeCreditDrafts: false,
                canSeeBadgeAbilityDrafts: false,
                canSeeLicenseBoundary: false,
                canSeeBlockingFindings: false
            )
        case .relative:
            return CreatorManifestPreviewVisibility(
                viewerRole: role,
                canSeeManifest: false,
                canSeeProofRequirements: false,
                canSeeCreditDrafts: false,
                canSeeBadgeAbilityDrafts: false,
                canSeeLicenseBoundary: false,
                canSeeBlockingFindings: false
            )
        }
    }

    private func statusFor(
        role: CreatorManifestPreviewViewerRole,
        findings: [CreatorManifestPreviewFinding],
        visibility: CreatorManifestPreviewVisibility
    ) -> CreatorManifestPreviewStatus {
        if !visibility.canSeeManifest { return .hidden }
        if findings.contains(where: { $0.severity == .blocker }) {
            return visibility.canSeeBlockingFindings ? .blocked : (role == .child ? .needsWork : .hidden)
        }
        if findings.contains(where: { $0.severity == .warning }) { return .needsWork }
        return .readyForReview
    }

    private func contentPreviews(
        _ draft: CreatorManifestPreviewDraft,
        role: CreatorManifestPreviewViewerRole
    ) -> [CreatorManifestContentPreview] {
        draft.contentBlocks
            .filter { role == .creator || role == .guardian || role == .teacher || $0.visibleToChild }
            .filter { role != .teacher || $0.kind == .schoolHomeworkHook || $0.kind == .quiz || $0.kind == .text }
            .map { block in
                CreatorManifestContentPreview(
                    publicContentRef: publicRef("cmc", block.contentId),
                    kind: block.kind,
                    title: block.title,
                    summary: role == .child ? "完成这一段学习后提交对应证明。" : block.summary,
                    status: block.status,
                    requiredProofCount: block.proofRequirementIds.count,
                    guardianReviewRequired: role == .child ? false : block.guardianReviewRequired,
                    assetModerationPassed: role == .child ? true : block.assetModerationPassed,
                    visibleToChild: block.visibleToChild
                )
            }
    }

    private func proofPreviews(_ draft: CreatorManifestPreviewDraft) -> [CreatorManifestProofPreview] {
        draft.proofRequirements.map { proof in
            CreatorManifestProofPreview(
                publicProofRef: publicRef("cmp", proof.proofId),
                kind: proof.kind,
                verifierRoles: proof.verifierRoles,
                instructions: proof.instructions,
                evidenceRefsOnly: proof.evidenceRefsOnly,
                status: proof.status
            )
        }
    }

    private func creditPreviews(_ draft: CreatorManifestPreviewDraft) -> [CreatorManifestCreditPreview] {
        draft.creditDrafts.map { credit in
            CreatorManifestCreditPreview(
                publicCreditRef: publicRef("cmd", credit.creditId),
                amount: credit.amount,
                scopeLabel: credit.scopeLabel,
                reason: credit.reason,
                requiresGuardianApproval: true
            )
        }
    }

    private func badgeAbilityPreviews(_ draft: CreatorManifestPreviewDraft) -> [CreatorManifestBadgeAbilityPreview] {
        draft.badgeAbilityDrafts.map { draft in
            CreatorManifestBadgeAbilityPreview(
                publicDraftRef: publicRef("cma", draft.draftId),
                kind: draft.kind,
                title: draft.title,
                category: draft.category,
                requiresHumanReview: draft.requiresHumanReview
            )
        }
    }

    private func licensePreview(_ draft: CreatorManifestPreviewDraft) -> CreatorManifestLicenseBoundaryPreview {
        CreatorManifestLicenseBoundaryPreview(
            publicLicenseRef: publicRef("cmu", draft.licenseBoundary.licenseId),
            allowsExternalVideo: draft.licenseBoundary.allowsExternalVideo,
            allowsCreatorUpload: draft.licenseBoundary.allowsCreatorUpload,
            allowsSchoolHook: draft.licenseBoundary.allowsSchoolHook,
            marketPublishReady: draft.licenseBoundary.marketPublishReady
        )
    }

    private func ageRating(
        _ draft: CreatorManifestPreviewDraft,
        visibility: CreatorManifestPreviewVisibility
    ) -> CreatorManifestAgeRatingPreview {
        CreatorManifestAgeRatingPreview(
            minAge: draft.ageBand.minAge,
            maxAge: draft.ageBand.maxAge,
            gradeBand: visibility.canSeeLicenseBoundary ? draft.ageBand.gradeBand : "适龄学习",
            requiresGuardianConsent: draft.ageBand.requiresGuardianConsent,
            safeForChildPreview: draft.ageBand.requiresGuardianConsent && draft.ageBand.minAge >= 4 && draft.ageBand.maxAge <= 18
        )
    }

    private func visibleFindings(
        _ findings: [CreatorManifestPreviewFinding],
        visibility: CreatorManifestPreviewVisibility
    ) -> [CreatorManifestPreviewFinding] {
        var result = findings
        result.append(finding(.roleVisibilityApplied, .info, "已按 \(visibility.viewerRole.label) 视角裁剪 Manifest 预览。", visibility.viewerRole.rawValue))
        if !visibility.canSeeManifest {
            result.append(finding(.nonAuthorPreviewHidden, .info, "该视角不可查看创作者 Manifest 草稿。", visibility.viewerRole.rawValue))
        }
        if !visibility.canSeeBlockingFindings {
            result = result.filter { $0.severity != .blocker }
        }
        return unique(result)
    }

    private func publicSummary(
        role: CreatorManifestPreviewViewerRole,
        status: CreatorManifestPreviewStatus,
        draft: CreatorManifestPreviewDraft,
        visibility: CreatorManifestPreviewVisibility,
        content: [CreatorManifestContentPreview],
        proofs: [CreatorManifestProofPreview],
        credits: [CreatorManifestCreditPreview],
        badgeAbilities: [CreatorManifestBadgeAbilityPreview],
        findings: [CreatorManifestPreviewFinding]
    ) -> CreatorManifestPreviewPublicSummary {
        CreatorManifestPreviewPublicSummary(
            generatedAt: generatedAt,
            viewerRole: role,
            status: status,
            packPublicRef: publicRef("cmr", draft.packId),
            creatorPublicRef: publicRef("cmr", draft.creatorId),
            title: visibility.canSeeManifest ? draft.title : "预览不可见",
            contentVersion: draft.contentVersion,
            visibleContentCount: content.count,
            visibleProofCount: proofs.count,
            visibleCreditDraftCount: credits.count,
            visibleBadgeAbilityCount: badgeAbilities.count,
            findingCodes: findings.map(\.code)
        )
    }

    // MARK: - Helpers

    private func publicRef(_ prefix: String, _ source: String) -> String {
        Self.stablePublicRef(prefix: prefix, source: source, salt: redactionSalt)
    }

    static func stablePublicRef(prefix: String, source: String, salt: String = "creator-manifest-preview-ios-v1") -> String {
        var hash: UInt32 = 2166136261
        for scalar in "\(salt):\(source)".unicodeScalars {
            hash ^= UInt32(scalar.value)
            hash = hash &* 16777619
        }
        let body = String(hash, radix: 36)
        let padded = body.count >= 8 ? body : String(repeating: "0", count: 8 - body.count) + body
        return "\(prefix):\(padded)"
    }

    private func finding(
        _ code: CreatorManifestPreviewFindingCode,
        _ severity: CreatorManifestPreviewSeverity,
        _ message: String,
        _ seed: String
    ) -> CreatorManifestPreviewFinding {
        CreatorManifestPreviewFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("cmf", "\(code.rawValue):\(seed)")
        )
    }

    private func unique(_ findings: [CreatorManifestPreviewFinding]) -> [CreatorManifestPreviewFinding] {
        var seen = Set<String>()
        return findings.filter { item in
            let key = "\(item.code.rawValue):\(item.publicRef)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func safeFallback(
        role: CreatorManifestPreviewViewerRole,
        visibility: CreatorManifestPreviewVisibility
    ) -> CreatorManifestPreviewSnapshot {
        let fallback = finding(.publicSummaryLeak, .blocker, "Manifest 预览未通过脱敏检查，已安全降级。", "fallback")
        let summary = CreatorManifestPreviewPublicSummary(
            generatedAt: generatedAt,
            viewerRole: role,
            status: .blocked,
            packPublicRef: publicRef("cmr", "redacted-pack"),
            creatorPublicRef: publicRef("cmr", "redacted-creator"),
            title: "预览已降级",
            contentVersion: "redacted",
            visibleContentCount: 0,
            visibleProofCount: 0,
            visibleCreditDraftCount: 0,
            visibleBadgeAbilityCount: 0,
            findingCodes: [.publicSummaryLeak]
        )
        return CreatorManifestPreviewSnapshot(
            generatedAt: generatedAt,
            viewerRole: role,
            status: .blocked,
            manifestVersion: "redacted",
            title: "预览已降级",
            summary: "Manifest 预览未通过脱敏检查。",
            contentBlocks: [],
            proofRequirements: [],
            creditDrafts: [],
            badgeAbilityDrafts: [],
            licenseBoundary: nil,
            ageRating: CreatorManifestAgeRatingPreview(
                minAge: 0,
                maxAge: 0,
                gradeBand: "redacted",
                requiresGuardianConsent: true,
                safeForChildPreview: false
            ),
            visibility: visibility,
            findings: [fallback],
            publicSummary: summary
        )
    }

    private func displayValues(_ snapshot: CreatorManifestPreviewSnapshot) -> [String] {
        var values: [String] = [
            snapshot.generatedAt,
            snapshot.manifestVersion,
            snapshot.title,
            snapshot.summary,
            snapshot.status.label,
            snapshot.publicSummary.packPublicRef,
            snapshot.publicSummary.creatorPublicRef,
            snapshot.publicSummary.title,
            snapshot.publicSummary.contentVersion,
            snapshot.ageRating.gradeBand
        ]
        values += snapshot.contentBlocks.flatMap {
            [$0.publicContentRef, $0.kind.label, $0.title, $0.summary, $0.status.label]
        }
        values += snapshot.proofRequirements.flatMap {
            [$0.publicProofRef, $0.kind.label, $0.instructions] + $0.verifierRoles.map(\.label)
        }
        values += snapshot.creditDrafts.flatMap {
            [$0.publicCreditRef, $0.scopeLabel, $0.reason]
        }
        values += snapshot.badgeAbilityDrafts.flatMap {
            [$0.publicDraftRef, $0.kind.label, $0.title, $0.category]
        }
        if let license = snapshot.licenseBoundary {
            values.append(license.publicLicenseRef)
        }
        values += snapshot.findings.flatMap { [$0.publicRef, $0.code.rawValue, $0.message] }
        values += snapshot.publicSummary.findingCodes.map(\.rawValue)
        return values
    }
}

extension CreatorManifestPreviewDraft {
    static var mock: CreatorManifestPreviewDraft {
        CreatorManifestPreviewDraft(
            manifestId: "manifest-sunrise-a",
            creatorId: "creator-sunrise-a",
            packId: "pack-sunrise-builder-a",
            title: "Sunrise Builder",
            summary: "晨间科学、运动和创作组合成长包。",
            contentVersion: "1.0.0",
            contentBlocks: [
                CreatorManifestContentDraft(
                    contentId: "c-text-a",
                    kind: .text,
                    title: "阅读任务说明",
                    summary: "孩子先阅读一段任务说明，再用自己的话复述。",
                    status: .complete,
                    proofRequirementIds: [],
                    guardianReviewRequired: false,
                    visibleToChild: true,
                    assetModerationPassed: true,
                    containsDirectAnswer: false
                ),
                CreatorManifestContentDraft(
                    contentId: "c-quiz-a",
                    kind: .quiz,
                    title: "知识小测",
                    summary: "通过小测确认孩子理解基本概念。",
                    status: .complete,
                    proofRequirementIds: ["p-quiz-a"],
                    guardianReviewRequired: false,
                    visibleToChild: true,
                    assetModerationPassed: true,
                    containsDirectAnswer: false
                ),
                CreatorManifestContentDraft(
                    contentId: "c-video-a",
                    kind: .externalVideo,
                    title: "学习视频引用",
                    summary: "引用受信任的学习视频，不在本地抓取流媒体。",
                    status: .complete,
                    proofRequirementIds: ["p-video-a"],
                    guardianReviewRequired: true,
                    visibleToChild: true,
                    assetModerationPassed: true,
                    containsDirectAnswer: false
                ),
                CreatorManifestContentDraft(
                    contentId: "c-upload-a",
                    kind: .creatorUpload,
                    title: "创作上传草稿",
                    summary: "孩子完成一幅画后提交脱敏作品引用。",
                    status: .complete,
                    proofRequirementIds: ["p-upload-a"],
                    guardianReviewRequired: true,
                    visibleToChild: true,
                    assetModerationPassed: true,
                    containsDirectAnswer: false
                ),
                CreatorManifestContentDraft(
                    contentId: "c-school-a",
                    kind: .schoolHomeworkHook,
                    title: "学校作业挂钩",
                    summary: "老师和家长共同确认学校作业完成情况。",
                    status: .complete,
                    proofRequirementIds: ["p-school-a"],
                    guardianReviewRequired: true,
                    visibleToChild: false,
                    assetModerationPassed: true,
                    containsDirectAnswer: false
                )
            ],
            proofRequirements: [
                CreatorManifestProofRequirementDraft(
                    proofId: "p-quiz-a",
                    kind: .quizResult,
                    verifierRoles: [.system, .guardian],
                    instructions: "只保存测验结果引用和通过状态。",
                    evidenceRefsOnly: true,
                    status: .complete
                ),
                CreatorManifestProofRequirementDraft(
                    proofId: "p-video-a",
                    kind: .externalVideoRef,
                    verifierRoles: [.guardian],
                    instructions: "家长确认孩子观看学习视频。",
                    evidenceRefsOnly: true,
                    status: .complete
                ),
                CreatorManifestProofRequirementDraft(
                    proofId: "p-upload-a",
                    kind: .creatorUploadRef,
                    verifierRoles: [.guardian],
                    instructions: "只保存审核后的创作作品引用。",
                    evidenceRefsOnly: true,
                    status: .complete
                ),
                CreatorManifestProofRequirementDraft(
                    proofId: "p-school-a",
                    kind: .teacherGuardianCheck,
                    verifierRoles: [.teacher, .guardian],
                    instructions: "老师和家长共同核验学校作业引用。",
                    evidenceRefsOnly: true,
                    status: .complete
                )
            ],
            creditDrafts: [
                CreatorManifestCreditDraft(
                    creditId: "credit-quiz-a",
                    triggerContentId: "c-quiz-a",
                    amount: 15,
                    scopeLabel: "screen_time",
                    reason: "通过知识小测后建议奖励。",
                    requiresGuardianApproval: true,
                    writesLedger: false
                ),
                CreatorManifestCreditDraft(
                    creditId: "credit-upload-a",
                    triggerContentId: "c-upload-a",
                    amount: 20,
                    scopeLabel: "creative_bonus",
                    reason: "完成创作并通过家长审核后建议奖励。",
                    requiresGuardianApproval: true,
                    writesLedger: false
                )
            ],
            badgeAbilityDrafts: [
                CreatorManifestBadgeAbilityDraft(
                    draftId: "badge-science-a",
                    kind: .badge,
                    title: "晨间科学观察者",
                    category: "知识",
                    requiresHumanReview: true,
                    mutatesProfile: false
                ),
                CreatorManifestBadgeAbilityDraft(
                    draftId: "ability-creative-a",
                    kind: .abilityCard,
                    title: "创作表达",
                    category: "天赋",
                    requiresHumanReview: true,
                    mutatesProfile: false
                )
            ],
            licenseBoundary: CreatorManifestLicenseBoundaryDraft(
                licenseId: "license-sunrise-a",
                allowsExternalVideo: true,
                allowsCreatorUpload: true,
                allowsSchoolHook: true,
                marketPublishReady: false
            ),
            ageBand: CreatorManifestAgeBandDraft(
                minAge: 8,
                maxAge: 12,
                gradeBand: "小学中高年级",
                requiresGuardianConsent: true
            ),
            generatedAt: "2026-06-24T11:00:00Z"
        )
    }
}
