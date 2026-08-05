import Foundation

/// 成长日记 / VLOG / 故事线手机端工作台的纯本地安全投影。
///
/// 这一层只读取 `FamilyGrowthAchievementStore` 中已经脱敏的本地 mock 卡片，
/// 按孩子、家长、亲友三种视角裁剪可见内容。它不打开相机/相册，不上传媒体，
/// 不发布动态，不发送评论/通知，不发成长积分，不写账本，不解锁设备，不调用网络或 AI。
enum MobileGrowthDiaryVlogViewerRole: String, CaseIterable, Equatable {
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

    var familyGrowthRole: FamilyGrowthViewerRole {
        switch self {
        case .child: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        }
    }

    var audienceNote: String {
        switch self {
        case .child:
            return "这里是你的成长记录草稿箱。私密日记和 VLOG 草稿只给你和家长看，暂不公开。"
        case .guardian:
            return "家长只读查看草稿、待复核、撤回和阻断状态，用来决定后续是否允许分享。"
        case .relative:
            return "亲友只看家长通过并允许亲友可见的脱敏片段，不能看私密草稿。"
        }
    }
}

enum MobileGrowthDiaryVlogItemKind: String, Equatable {
    case diary
    case vlogDraft
    case storyline
    case honorMoment
    case encouragement
    case abilityCard

    var label: String {
        switch self {
        case .diary: return "成长日记"
        case .vlogDraft: return "VLOG 草稿"
        case .storyline: return "故事线"
        case .honorMoment: return "荣誉片段"
        case .encouragement: return "亲友鼓励"
        case .abilityCard: return "能力球星卡"
        }
    }

    var systemImage: String {
        switch self {
        case .diary: return "book"
        case .vlogDraft: return "film"
        case .storyline: return "sparkles"
        case .honorMoment: return "trophy"
        case .encouragement: return "text.bubble"
        case .abilityCard: return "person.text.rectangle"
        }
    }
}

enum MobileGrowthDiaryVlogReviewState: String, Equatable {
    case savedPrivate
    case pendingGuardianReview
    case relativeVisible
    case familyVisible
    case publicRedacted
    case withdrawn
    case blocked

    var label: String {
        switch self {
        case .savedPrivate: return "私密保存"
        case .pendingGuardianReview: return "待家长复核"
        case .relativeVisible: return "亲友可见"
        case .familyVisible: return "家庭可见"
        case .publicRedacted: return "公开脱敏"
        case .withdrawn: return "已撤回"
        case .blocked: return "已保护"
        }
    }

    var isVisibleOutsideHousehold: Bool {
        self == .relativeVisible || self == .familyVisible || self == .publicRedacted
    }

    var needsGuardianReview: Bool {
        self == .pendingGuardianReview || self == .withdrawn || self == .blocked
    }
}

struct MobileGrowthDiaryVlogStorylineItem: Identifiable, Equatable {
    var publicItemRef: String
    var sourceCardPublicRef: String
    var kind: MobileGrowthDiaryVlogItemKind
    var title: String
    var summary: String
    var occurredLabel: String
    var visibilityLabel: String
    var reviewState: MobileGrowthDiaryVlogReviewState
    var mediaStateLabel: String
    var supportiveCopy: String
    var nextStep: String
    var tags: [String]
    var showsGuardianReviewHint: Bool
    var canContinueDraft: Bool
    var canRelativeEncourage: Bool

    var id: String { publicItemRef }

    var displayValues: [String] {
        [
            kind.rawValue,
            kind.label,
            title,
            summary,
            occurredLabel,
            visibilityLabel,
            reviewState.rawValue,
            reviewState.label,
            mediaStateLabel,
            supportiveCopy,
            nextStep
        ] + tags
    }
}

struct MobileGrowthDiaryVlogBoundary: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var isBlocked: Bool
}

struct MobileGrowthDiaryVlogNextAction: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var actionRequired: Bool
}

struct MobileGrowthDiaryVlogPublicSummary: Equatable {
    var role: MobileGrowthDiaryVlogViewerRole
    var visibleItemCount: Int
    var diaryCount: Int
    var vlogDraftCount: Int
    var pendingReviewCount: Int
    var hiddenItemCount: Int
    var relativeVisibleCount: Int
    var blockedCount: Int

    let opensCamera = false
    let opensPhotoLibrary = false
    let uploadsMedia = false
    let publishesStoryline = false
    let sendsComment = false
    let sendsNotification = false
    let callsNetwork = false
    let callsAIProvider = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let writesSchoolSystem = false

    var hasTriggeredSideEffect: Bool {
        opensCamera || opensPhotoLibrary || uploadsMedia || publishesStoryline
            || sendsComment || sendsNotification || callsNetwork || callsAIProvider
            || writesLedger || grantsCredit || unlocksDevice || writesSchoolSystem
    }
}

struct MobileGrowthDiaryVlogStorylineWorkbench: Equatable {
    var role: MobileGrowthDiaryVlogViewerRole
    var headline: String
    var audienceNote: String
    var items: [MobileGrowthDiaryVlogStorylineItem]
    var boundaries: [MobileGrowthDiaryVlogBoundary]
    var nextActions: [MobileGrowthDiaryVlogNextAction]
    var publicSummary: MobileGrowthDiaryVlogPublicSummary

    var displayValues: [String] {
        [role.rawValue, headline, audienceNote]
            + items.flatMap(\.displayValues)
            + boundaries.flatMap { [$0.title, $0.detail] }
            + nextActions.flatMap { [$0.title, $0.detail] }
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileGrowthDiaryVlogStorylineBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileGrowthDiaryVlogStorylineBuilder {
    var store: FamilyGrowthAchievementStore

    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "relative:", "guardian:",
        "task:", "claim:", "proof:", "ledger:", "device:", "media:", "session:",
        "token", "secret", "api_key", "apikey", "provider:", "model:",
        "http://", "https://", "file://", "/users/", "/volumes/", "192.168."
    ]

    init(store: FamilyGrowthAchievementStore = FamilyGrowthAchievementStore()) {
        self.store = store
    }

    func build(role: MobileGrowthDiaryVlogViewerRole) -> MobileGrowthDiaryVlogStorylineWorkbench {
        let visibleCards = store.cards
            .filter { $0.isVisible(to: role.familyGrowthRole) }
            .sorted(by: cardOrder)
        let hiddenCount = store.cards.count - visibleCards.count
        let items = visibleCards.map { item(from: $0, role: role) }

        let candidate = workbench(role: role, items: items, hiddenCount: hiddenCount)
        return candidate.hasUnsafeDisplayPayload ? blockedShell(role: role, hiddenCount: store.cards.count) : candidate
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private func workbench(
        role: MobileGrowthDiaryVlogViewerRole,
        items: [MobileGrowthDiaryVlogStorylineItem],
        hiddenCount: Int
    ) -> MobileGrowthDiaryVlogStorylineWorkbench {
        let pending = items.filter { $0.reviewState.needsGuardianReview }.count
        let relativeVisible = items.filter { $0.reviewState == .relativeVisible || $0.reviewState == .familyVisible }.count
        let blocked = items.filter { $0.reviewState == .blocked }.count
        let summary = MobileGrowthDiaryVlogPublicSummary(
            role: role,
            visibleItemCount: items.count,
            diaryCount: items.filter { $0.kind == .diary }.count,
            vlogDraftCount: items.filter { $0.kind == .vlogDraft }.count,
            pendingReviewCount: pending,
            hiddenItemCount: hiddenCount,
            relativeVisibleCount: relativeVisible,
            blockedCount: blocked
        )

        return MobileGrowthDiaryVlogStorylineWorkbench(
            role: role,
            headline: headline(role: role, items: items, pendingCount: pending),
            audienceNote: role.audienceNote,
            items: items,
            boundaries: boundaryRows(role: role),
            nextActions: nextActions(role: role, items: items, pendingCount: pending),
            publicSummary: summary
        )
    }

    private func item(
        from card: FamilyGrowthCard,
        role: MobileGrowthDiaryVlogViewerRole
    ) -> MobileGrowthDiaryVlogStorylineItem {
        let state = reviewState(for: card)
        return MobileGrowthDiaryVlogStorylineItem(
            publicItemRef: FamilyGrowthRedaction.publicRef(
                prefix: "story",
                source: "\(role.rawValue):\(card.publicRef):\(card.kind.rawValue)"
            ),
            sourceCardPublicRef: card.publicRef,
            kind: itemKind(for: card.kind),
            title: card.title,
            summary: summary(for: card, role: role),
            occurredLabel: card.occurredLabel,
            visibilityLabel: card.visibility.label,
            reviewState: state,
            mediaStateLabel: mediaState(for: card.kind),
            supportiveCopy: card.supportiveCopy,
            nextStep: nextStep(for: card, role: role, state: state),
            tags: card.tags,
            showsGuardianReviewHint: role == .guardian && state.needsGuardianReview,
            canContinueDraft: role == .child && (card.kind == .journal || card.kind == .vlogPlaceholder),
            canRelativeEncourage: role == .relative && state.isVisibleOutsideHousehold
        )
    }

    private func itemKind(for kind: FamilyGrowthCardKind) -> MobileGrowthDiaryVlogItemKind {
        switch kind {
        case .journal: return .diary
        case .vlogPlaceholder: return .vlogDraft
        case .storyline: return .storyline
        case .honorWall, .badge: return .honorMoment
        case .relativeComment: return .encouragement
        case .growthCard: return .abilityCard
        }
    }

    private func reviewState(for card: FamilyGrowthCard) -> MobileGrowthDiaryVlogReviewState {
        switch card.lifecycle {
        case .pending:
            return .pendingGuardianReview
        case .withdrawn:
            return .withdrawn
        case .blocked:
            return .blocked
        case .published:
            switch card.visibility {
            case .privateOnly: return .savedPrivate
            case .family: return .familyVisible
            case .relatives: return .relativeVisible
            case .publicShare: return .publicRedacted
            }
        }
    }

    private func mediaState(for kind: FamilyGrowthCardKind) -> String {
        switch kind {
        case .vlogPlaceholder:
            return "待家长开启拍摄/导入 · 未打开相机/相册"
        case .journal:
            return "文字记录 · 不上传"
        case .storyline:
            return "故事线摘要 · 只读"
        case .honorWall, .badge, .growthCard, .relativeComment:
            return "脱敏片段 · 无原始证明"
        }
    }

    private func summary(
        for card: FamilyGrowthCard,
        role: MobileGrowthDiaryVlogViewerRole
    ) -> String {
        if card.lifecycle == .blocked {
            return role == .child
                ? "这条内容被安全保护起来了，可以和家长一起处理。"
                : card.displaySummary(for: role.familyGrowthRole)
        }
        if role == .relative && card.kind == .relativeComment {
            return "这是一条家长已通过的鼓励摘要。"
        }
        return card.displaySummary(for: role.familyGrowthRole)
    }

    private func nextStep(
        for card: FamilyGrowthCard,
        role: MobileGrowthDiaryVlogViewerRole,
        state: MobileGrowthDiaryVlogReviewState
    ) -> String {
        switch role {
        case .child:
            if card.kind == .vlogPlaceholder {
                return "先写下想记录的片段；是否拍摄和分享，之后由家长陪同决定。"
            }
            if state.needsGuardianReview {
                return "这条记录会先等家长看一眼，不会直接公开或换成长积分。"
            }
            return card.nextStep
        case .guardian:
            if state.needsGuardianReview {
                return "后续审批需要进入正式策略服务；当前页面只展示待处理线索。"
            }
            return "可以继续观察这条记录的可见范围，当前页面不执行发布。"
        case .relative:
            return "可以表达支持，但鼓励不会直接发成长积分，也不会通知孩子。"
        }
    }

    private func headline(
        role: MobileGrowthDiaryVlogViewerRole,
        items: [MobileGrowthDiaryVlogStorylineItem],
        pendingCount: Int
    ) -> String {
        switch role {
        case .child:
            return items.isEmpty ? "还没有成长记录草稿" : "继续整理你的成长日记"
        case .guardian:
            return pendingCount > 0 ? "有成长素材等待家长把关" : "成长日记与故事线安全可查看"
        case .relative:
            return items.isEmpty ? "暂无家长开放的成长片段" : "亲友可见的成长故事"
        }
    }

    private func boundaryRows(role: MobileGrowthDiaryVlogViewerRole) -> [MobileGrowthDiaryVlogBoundary] {
        [
            MobileGrowthDiaryVlogBoundary(
                id: "media",
                title: "不打开媒体权限",
                detail: "拍摄和导入需要家长确认开启；不会自动调用相机、相册、麦克风或文件选择器，也不会读取或上传媒体。",
                isBlocked: true
            ),
            MobileGrowthDiaryVlogBoundary(
                id: "publish",
                title: "不直接发布",
                detail: "草稿、日记、VLOG 和故事线不会在这里公开，也不会通知亲友。",
                isBlocked: true
            ),
            MobileGrowthDiaryVlogBoundary(
                id: "credit",
                title: "不触发成长积分",
                detail: "任何展示、鼓励或待审核状态都不会发成长积分、写账本或解锁设备。",
                isBlocked: true
            ),
            MobileGrowthDiaryVlogBoundary(
                id: "role",
                title: role == .relative ? "亲友只读" : "家庭内把关",
                detail: role == .relative
                    ? "亲友看不到私密日记、VLOG 草稿、撤回和阻断内容。"
                    : "家庭内视角能看状态，但孩子视角不展示成人审核内部原因。",
                isBlocked: role == .relative
            )
        ]
    }

    private func nextActions(
        role: MobileGrowthDiaryVlogViewerRole,
        items: [MobileGrowthDiaryVlogStorylineItem],
        pendingCount: Int
    ) -> [MobileGrowthDiaryVlogNextAction] {
        switch role {
        case .child:
            return [
                MobileGrowthDiaryVlogNextAction(
                    id: "continue-diary",
                    title: "继续写一小段",
                    detail: "只保存为本地草稿提示，不上传、不公开。",
                    actionRequired: false
                )
            ]
        case .guardian:
            return [
                MobileGrowthDiaryVlogNextAction(
                    id: "review",
                    title: pendingCount > 0 ? "查看待复核素材" : "检查可见性设置",
                    detail: "当前页面只提示需要把关的素材，不执行批准或驳回。",
                    actionRequired: pendingCount > 0
                )
            ]
        case .relative:
            return [
                MobileGrowthDiaryVlogNextAction(
                    id: "encourage",
                    title: items.isEmpty ? "等待家长开放内容" : "留下温和鼓励",
                    detail: "鼓励入口仅为说明，真实留言仍需走家长审核队列。",
                    actionRequired: false
                )
            ]
        }
    }

    private func blockedShell(
        role: MobileGrowthDiaryVlogViewerRole,
        hiddenCount: Int
    ) -> MobileGrowthDiaryVlogStorylineWorkbench {
        MobileGrowthDiaryVlogStorylineWorkbench(
            role: role,
            headline: "成长记录已被安全边界保护",
            audienceNote: role.audienceNote,
            items: [],
            boundaries: [
                MobileGrowthDiaryVlogBoundary(
                    id: "unsafe",
                    title: "展示内容已隐藏",
                    detail: "检测到链接、路径、密钥、局域网地址或内部标识，本地壳不回显原文。",
                    isBlocked: true
                )
            ],
            nextActions: [
                MobileGrowthDiaryVlogNextAction(
                    id: "clean-input",
                    title: "等待家长清理素材",
                    detail: "移除敏感信息后再进入成长故事线。",
                    actionRequired: role == .guardian
                )
            ],
            publicSummary: MobileGrowthDiaryVlogPublicSummary(
                role: role,
                visibleItemCount: 0,
                diaryCount: 0,
                vlogDraftCount: 0,
                pendingReviewCount: 0,
                hiddenItemCount: hiddenCount,
                relativeVisibleCount: 0,
                blockedCount: hiddenCount
            )
        )
    }

    private func cardOrder(_ lhs: FamilyGrowthCard, _ rhs: FamilyGrowthCard) -> Bool {
        let li = itemOrder(lhs.kind)
        let ri = itemOrder(rhs.kind)
        if li != ri { return li < ri }
        if lhs.lifecycle != rhs.lifecycle {
            return lifecycleOrder(lhs.lifecycle) < lifecycleOrder(rhs.lifecycle)
        }
        return lhs.title < rhs.title
    }

    private func itemOrder(_ kind: FamilyGrowthCardKind) -> Int {
        switch kind {
        case .journal: return 0
        case .vlogPlaceholder: return 1
        case .storyline: return 2
        case .honorWall: return 3
        case .relativeComment: return 4
        case .badge: return 5
        case .growthCard: return 6
        }
    }

    private func lifecycleOrder(_ lifecycle: FamilyGrowthLifecycle) -> Int {
        switch lifecycle {
        case .pending: return 0
        case .published: return 1
        case .withdrawn: return 2
        case .blocked: return 3
        }
    }
}
