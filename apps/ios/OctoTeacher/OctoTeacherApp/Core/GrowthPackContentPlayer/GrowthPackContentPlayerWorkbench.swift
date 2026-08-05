import Foundation

/// 成长包内容播放器 / 证明工作台的纯本地安全投影。
///
/// 读取创作者 Manifest 草稿中的内容块和证明要求，组织成孩子/家长可看的播放清单。
/// 它不打开 WebView/浏览器/外部视频，不下载图片，不打开相机/相册/文件选择器，
/// 不上传证明，不自动判分，不写账本，不发成长积分，不解锁设备，不调用网络或 AI。
enum GrowthPackContentPlayerViewerRole: String, CaseIterable, Equatable {
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
            return "只看学习内容和下一步。视频、图片和截图都是安全预览，不会打开外部链接或上传文件。"
        case .guardian:
            return "只读查看内容来源、外链、版权、证明和风险边界；真正审批仍在正式审核服务里完成。"
        }
    }
}

enum GrowthPackContentPlaybackMode: String, Equatable {
    case textLesson
    case imagePlaceholder
    case externalVideoReference
    case quizPractice
    case screenshotProof
    case uploadPlaceholder
    case schoolHook
    case exerciseProof

    var label: String {
        switch self {
        case .textLesson: return "文字课程"
        case .imagePlaceholder: return "图片观察"
        case .externalVideoReference: return "视频引用"
        case .quizPractice: return "测验练习"
        case .screenshotProof: return "截图证明"
        case .uploadPlaceholder: return "创作证明"
        case .schoolHook: return "学校挂钩"
        case .exerciseProof: return "运动证明"
        }
    }

    var systemImage: String {
        switch self {
        case .textLesson: return "text.alignleft"
        case .imagePlaceholder: return "photo"
        case .externalVideoReference: return "play.rectangle"
        case .quizPractice: return "checklist"
        case .screenshotProof: return "gamecontroller"
        case .uploadPlaceholder: return "paintpalette"
        case .schoolHook: return "graduationcap"
        case .exerciseProof: return "figure.run"
        }
    }
}

enum GrowthPackContentPlayerState: String, Equatable {
    case ready
    case practiceOnly
    case proofRequired
    case guardianReview
    case hiddenFromChild
    case blocked

    var label: String {
        switch self {
        case .ready: return "可学习"
        case .practiceOnly: return "练习模式"
        case .proofRequired: return "需证明"
        case .guardianReview: return "需家长复核"
        case .hiddenFromChild: return "孩子不可见"
        case .blocked: return "已阻断"
        }
    }
}

struct GrowthPackContentPlayerItem: Identifiable, Equatable {
    var publicContentRef: String
    var mode: GrowthPackContentPlaybackMode
    var title: String
    var summary: String
    var state: GrowthPackContentPlayerState
    var proofCount: Int
    var nextStep: String
    var safetyNote: String
    var visibleToChild: Bool
    var guardianReviewRequired: Bool

    let opensExternalURL = false
    let opensWebView = false
    let downloadsMedia = false
    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let uploadsProof = false
    let autoGradesQuiz = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false

    var id: String { publicContentRef }

    var displayValues: [String] {
        [
            mode.rawValue,
            mode.label,
            title,
            summary,
            state.rawValue,
            state.label,
            nextStep,
            safetyNote
        ]
    }
}

struct GrowthPackContentProofRow: Identifiable, Equatable {
    var publicProofRef: String
    var kind: CreatorManifestProofKind
    var verifierLabels: [String]
    var instructions: String
    var evidenceRefsOnly: Bool
    var visibleToChild: Bool

    let uploadsProof = false
    let writesSchoolSystem = false
    let writesLedger = false

    var id: String { publicProofRef }

    var displayValues: [String] {
        [kind.rawValue, kind.label, instructions] + verifierLabels
    }
}

struct GrowthPackContentRiskRow: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var actionRequired: Bool

    var displayValues: [String] { [id, title, detail] }
}

struct GrowthPackContentPlayerPublicSummary: Equatable {
    var role: GrowthPackContentPlayerViewerRole
    var visibleItemCount: Int
    var proofRequirementCount: Int
    var externalVideoCount: Int
    var screenshotProofCount: Int
    var guardianReviewCount: Int
    var hiddenItemCount: Int
    var riskCount: Int

    let opensExternalURL = false
    let opensWebView = false
    let downloadsMedia = false
    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let uploadsMedia = false
    let uploadsProof = false
    let autoGradesQuiz = false
    let callsNetwork = false
    let callsAIProvider = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let writesSchoolSystem = false

    var hasTriggeredSideEffect: Bool {
        opensExternalURL || opensWebView || downloadsMedia || opensCamera || opensPhotoLibrary
            || opensFilePicker || uploadsMedia || uploadsProof || autoGradesQuiz || callsNetwork
            || callsAIProvider || writesLedger || grantsCredit || unlocksDevice || writesSchoolSystem
    }
}

struct GrowthPackContentPlayerWorkbench: Equatable {
    var role: GrowthPackContentPlayerViewerRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var items: [GrowthPackContentPlayerItem]
    var proofs: [GrowthPackContentProofRow]
    var risks: [GrowthPackContentRiskRow]
    var publicSummary: GrowthPackContentPlayerPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + items.flatMap(\.displayValues)
            + proofs.flatMap(\.displayValues)
            + risks.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        GrowthPackContentPlayerWorkbenchBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct GrowthPackContentPlayerWorkbenchBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "creator:",
        "pack:", "content:", "media:", "video:", "proof:", "ledger:", "device:",
        "task:", "claim:", "session:", "token", "secret", "api_key", "apikey",
        "provider:", "model:", "http://", "https://", "file://", "/users/",
        "/volumes/", "192.168."
    ]

    func build(
        role: GrowthPackContentPlayerViewerRole,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock
    ) -> GrowthPackContentPlayerWorkbench {
        if Self.hasUnsafeDraftPayload(draft) || Self.hasUnsafeContentBlock(draft) {
            return blockedShell(role: role, hiddenCount: draft.contentBlocks.count)
        }

        let visibleBlocks = draft.contentBlocks.filter { role == .guardian || $0.visibleToChild }
        let items = visibleBlocks.map { item(from: $0, role: role) }
        let visibleProofIds = Set(visibleBlocks.flatMap(\.proofRequirementIds))
        let proofs = draft.proofRequirements
            .filter { role == .guardian || visibleProofIds.contains($0.proofId) }
            .map { proof(from: $0, role: role) }
        let risks = riskRows(for: draft, role: role, items: items, proofs: proofs)
        let hiddenItemCount = role == .guardian
            ? draft.contentBlocks.filter { !$0.visibleToChild }.count
            : draft.contentBlocks.count - items.count
        let summary = GrowthPackContentPlayerPublicSummary(
            role: role,
            visibleItemCount: items.count,
            proofRequirementCount: proofs.count,
            externalVideoCount: items.filter { $0.mode == .externalVideoReference }.count,
            screenshotProofCount: items.filter { $0.mode == .screenshotProof }.count,
            guardianReviewCount: items.filter(\.guardianReviewRequired).count,
            hiddenItemCount: hiddenItemCount,
            riskCount: risks.count
        )
        let workbench = GrowthPackContentPlayerWorkbench(
            role: role,
            title: draft.title,
            subtitle: "\(draft.contentVersion) · \(draft.ageBand.gradeBand)",
            audienceNote: role.audienceNote,
            items: items,
            proofs: proofs,
            risks: risks,
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? blockedShell(role: role, hiddenCount: draft.contentBlocks.count) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private static func hasUnsafeDraftPayload(_ draft: CreatorManifestPreviewDraft) -> Bool {
        let values = [draft.title, draft.summary, draft.contentVersion, draft.ageBand.gradeBand]
            + draft.contentBlocks.flatMap { [$0.title, $0.summary] }
            + draft.proofRequirements.map(\.instructions)
            + draft.creditDrafts.flatMap { [$0.scopeLabel, $0.reason] }
            + draft.badgeAbilityDrafts.flatMap { [$0.title, $0.category] }
        return hasUnsafeDisplayPayload(values)
    }

    private static func hasUnsafeContentBlock(_ draft: CreatorManifestPreviewDraft) -> Bool {
        draft.contentBlocks.contains { $0.containsDirectAnswer || !$0.assetModerationPassed }
    }

    private func item(
        from block: CreatorManifestContentDraft,
        role: GrowthPackContentPlayerViewerRole
    ) -> GrowthPackContentPlayerItem {
        let mode = playbackMode(for: block.kind)
        return GrowthPackContentPlayerItem(
            publicContentRef: publicRef("gpc", block.contentId),
            mode: mode,
            title: block.title,
            summary: summary(for: block, role: role),
            state: state(for: block, role: role, mode: mode),
            proofCount: block.proofRequirementIds.count,
            nextStep: nextStep(for: block, role: role, mode: mode),
            safetyNote: safetyNote(for: mode),
            visibleToChild: block.visibleToChild,
            guardianReviewRequired: role == .guardian && block.guardianReviewRequired
        )
    }

    private func proof(
        from proof: CreatorManifestProofRequirementDraft,
        role: GrowthPackContentPlayerViewerRole
    ) -> GrowthPackContentProofRow {
        GrowthPackContentProofRow(
            publicProofRef: publicRef("gpp", proof.proofId),
            kind: proof.kind,
            verifierLabels: role == .child ? ["家长"] : proof.verifierRoles.map(\.label),
            instructions: role == .child ? childProofCopy(for: proof.kind) : proof.instructions,
            evidenceRefsOnly: proof.evidenceRefsOnly,
            visibleToChild: role == .child
        )
    }

    private func playbackMode(for kind: CreatorManifestContentKind) -> GrowthPackContentPlaybackMode {
        switch kind {
        case .text: return .textLesson
        case .image: return .imagePlaceholder
        case .externalVideo: return .externalVideoReference
        case .quiz: return .quizPractice
        case .gameScreenshotProof: return .screenshotProof
        case .creatorUpload: return .uploadPlaceholder
        case .schoolHomeworkHook: return .schoolHook
        case .exerciseProof: return .exerciseProof
        }
    }

    private func state(
        for block: CreatorManifestContentDraft,
        role: GrowthPackContentPlayerViewerRole,
        mode: GrowthPackContentPlaybackMode
    ) -> GrowthPackContentPlayerState {
        if block.containsDirectAnswer || !block.assetModerationPassed { return .blocked }
        if role == .child && !block.visibleToChild { return .hiddenFromChild }
        if role == .guardian && block.guardianReviewRequired { return .guardianReview }
        if mode == .quizPractice { return .practiceOnly }
        if block.proofRequirementIds.isEmpty { return .ready }
        return .proofRequired
    }

    private func summary(
        for block: CreatorManifestContentDraft,
        role: GrowthPackContentPlayerViewerRole
    ) -> String {
        if role == .child {
            switch block.kind {
            case .externalVideo:
                return "这里会显示视频学习要求，但不会直接打开外部链接。"
            case .image:
                return "这里是图片观察说明，不下载原图。"
            case .gameScreenshotProof:
                return "这里只说明通关截图证明要求，不打开相册或上传文件。"
            case .quiz:
                return "这是练习小测说明，不自动判分，也不直接给奖励。"
            default:
                return block.summary
            }
        }
        return block.summary
    }

    private func nextStep(
        for block: CreatorManifestContentDraft,
        role: GrowthPackContentPlayerViewerRole,
        mode: GrowthPackContentPlaybackMode
    ) -> String {
        if role == .guardian {
            return block.guardianReviewRequired
                ? "检查内容来源、证明要求和家长复核边界；本页不执行批准。"
                : "确认内容适龄、脱敏且不含直接答案；本页只读。"
        }
        switch mode {
        case .textLesson:
            return "读完后用自己的话复述给家长。"
        case .imagePlaceholder:
            return "看图片说明即可，原图不在本地加载。"
        case .externalVideoReference:
            return "请在家长陪同下完成视频学习，本页不打开链接。"
        case .quizPractice:
            return "先练习思路，结果等待家长确认。"
        case .screenshotProof:
            return "完成通关后请家长确认截图证明。"
        case .uploadPlaceholder:
            return "完成创作后请家长选择是否提交作品引用。"
        case .schoolHook:
            return "学校作业由老师和家长共同确认。"
        case .exerciseProof:
            return "完成运动后等待家长或设备证明确认。"
        }
    }

    private func safetyNote(for mode: GrowthPackContentPlaybackMode) -> String {
        switch mode {
        case .textLesson:
            return "文本本地展示，不含直接答案。"
        case .imagePlaceholder:
            return "图片只显示安全预览，不下载、不缓存原图。"
        case .externalVideoReference:
            return "只显示视频引用说明，不打开外链或 WebView。"
        case .quizPractice:
            return "测验仅作练习，不自动判分、不发成长积分。"
        case .screenshotProof:
            return "截图证明只显示要求，不打开相册、不上传。"
        case .uploadPlaceholder:
            return "创作作品只显示证明要求，不打开文件选择器。"
        case .schoolHook:
            return "学校挂钩只读，不写学校系统。"
        case .exerciseProof:
            return "运动证明只读，不读取真实健康数据。"
        }
    }

    private func childProofCopy(for kind: CreatorManifestProofKind) -> String {
        switch kind {
        case .quizResult:
            return "练习完成后等待家长确认。"
        case .externalVideoRef:
            return "视频学习需要家长确认。"
        case .gameScreenshot:
            return "通关截图由家长确认，本页不上传。"
        case .exerciseSignal:
            return "运动完成后等待证明确认。"
        case .creatorUploadRef:
            return "作品是否提交由家长决定。"
        case .teacherGuardianCheck:
            return "老师和家长共同确认。"
        }
    }

    private func riskRows(
        for draft: CreatorManifestPreviewDraft,
        role: GrowthPackContentPlayerViewerRole,
        items: [GrowthPackContentPlayerItem],
        proofs: [GrowthPackContentProofRow]
    ) -> [GrowthPackContentRiskRow] {
        guard role == .guardian else { return [] }
        var rows: [GrowthPackContentRiskRow] = []
        if draft.contentBlocks.contains(where: { $0.kind == .externalVideo }) {
            rows.append(GrowthPackContentRiskRow(
                id: "external-video",
                title: "外部视频只读引用",
                detail: "本地壳不打开外链、不嵌入 WebView，后续需接 allowlist 和家长同意。",
                actionRequired: true
            ))
        }
        if draft.contentBlocks.contains(where: { $0.kind == .image || $0.kind == .creatorUpload }) {
            rows.append(GrowthPackContentRiskRow(
                id: "asset",
                title: "图片与创作素材需审核",
                detail: "图片/作品只显示安全预览或来源引用，真实素材必须先过版权和内容审核。",
                actionRequired: true
            ))
        }
        if draft.contentBlocks.contains(where: { $0.kind == .gameScreenshotProof }) {
            rows.append(GrowthPackContentRiskRow(
                id: "screenshot",
                title: "截图证明不能直传",
                detail: "通关截图证明需要家长确认，本页不会打开相册或上传文件。",
                actionRequired: true
            ))
        }
        if proofs.contains(where: { !$0.evidenceRefsOnly }) || items.contains(where: { $0.state == .blocked }) {
            rows.append(GrowthPackContentRiskRow(
                id: "blocked",
                title: "内容或证明需要修正",
                detail: "发现未通过安全边界的内容块或证明要求，不能进入孩子学习面。",
                actionRequired: true
            ))
        }
        if rows.isEmpty {
            rows.append(GrowthPackContentRiskRow(
                id: "readonly",
                title: "本地安全壳已就绪",
                detail: "当前内容播放器没有外部副作用，可继续进入人工审核。",
                actionRequired: false
            ))
        }
        return rows
    }

    private func blockedShell(
        role: GrowthPackContentPlayerViewerRole,
        hiddenCount: Int
    ) -> GrowthPackContentPlayerWorkbench {
        GrowthPackContentPlayerWorkbench(
            role: role,
            title: "成长包内容已被安全保护",
            subtitle: "本地安全壳",
            audienceNote: role.audienceNote,
            items: [],
            proofs: [],
            risks: [
                GrowthPackContentRiskRow(
                    id: "unsafe",
                    title: "展示内容已隐藏",
                    detail: "检测到链接、路径、密钥、局域网地址或内部标识，本地壳不回显原文。",
                    actionRequired: role == .guardian
                )
            ],
            publicSummary: GrowthPackContentPlayerPublicSummary(
                role: role,
                visibleItemCount: 0,
                proofRequirementCount: 0,
                externalVideoCount: 0,
                screenshotProofCount: 0,
                guardianReviewCount: 0,
                hiddenItemCount: hiddenCount,
                riskCount: 1
            )
        )
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        var hash: UInt32 = 5381
        for scalar in "growth-pack-content-player:\(source)".unicodeScalars {
            hash = (hash &* 33) ^ (scalar.value & 0xFFFF)
        }
        return "\(prefix)-\(String(hash, radix: 36))"
    }
}

extension CreatorManifestPreviewDraft {
    static var growthPackContentPlayerMock: CreatorManifestPreviewDraft {
        var draft = CreatorManifestPreviewDraft.mock
        draft.contentBlocks.insert(
            CreatorManifestContentDraft(
                contentId: "c-image-a",
                kind: .image,
                title: "观察图片线索",
                summary: "展示一张科学观察图片的说明，不下载原始图片。",
                status: .complete,
                proofRequirementIds: [],
                guardianReviewRequired: false,
                visibleToChild: true,
                assetModerationPassed: true,
                containsDirectAnswer: false
            ),
            at: 1
        )
        draft.contentBlocks.append(
            CreatorManifestContentDraft(
                contentId: "c-game-proof-a",
                kind: .gameScreenshotProof,
                title: "通关截图证明",
                summary: "孩子完成小游戏后，由家长确认通关截图证明。",
                status: .complete,
                proofRequirementIds: ["p-game-proof-a"],
                guardianReviewRequired: true,
                visibleToChild: true,
                assetModerationPassed: true,
                containsDirectAnswer: false
            )
        )
        draft.proofRequirements.append(
            CreatorManifestProofRequirementDraft(
                proofId: "p-game-proof-a",
                kind: .gameScreenshot,
                verifierRoles: [.guardian],
                instructions: "只保存家长确认后的截图证明引用。",
                evidenceRefsOnly: true,
                status: .complete
            )
        )
        return draft
    }
}
