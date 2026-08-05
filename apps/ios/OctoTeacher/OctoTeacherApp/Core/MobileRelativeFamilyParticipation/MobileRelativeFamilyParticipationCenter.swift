import Foundation

/// 亲友/祖辈手机端参与中心的纯本地只读投影。
///
/// 该模型只聚合已经脱敏、按角色裁剪过的家庭成长数据和离线 outbox 摘要：
/// 不审批任务、不发成长积分、不写账本、不解锁设备、不通知亲友、不上传媒体、不接网络。
struct MobileRelativeFamilyParticipationCenter: Equatable {
    var status: MobileRelativeFamilyParticipationStatus
    var headline: String
    var subtitle: String
    var relativeCount: Int
    var visibleFeedCount: Int
    var visibleHonorCount: Int
    var approvedCommentCount: Int
    var pendingLocalCommentCount: Int
    var abilityAverageScore: Int?
    var visibleCards: [MobileRelativeFamilyParticipationCard]
    var comments: [MobileRelativeFamilyParticipationComment]
    var boundaries: [MobileRelativeFamilyParticipationBoundary]
    var nextActions: [MobileRelativeFamilyParticipationNextAction]
    var publicSummary: MobileRelativeFamilyParticipationPublicSummary
}

enum MobileRelativeFamilyParticipationStatus: String, Equatable {
    case ready
    case waitingForGuardianReview
    case blocked

    var label: String {
        switch self {
        case .ready: return "可参与"
        case .waitingForGuardianReview: return "待家长审核"
        case .blocked: return "已保护"
        }
    }
}

struct MobileRelativeFamilyParticipationCard: Identifiable, Equatable {
    var id: String
    var kindLabel: String
    var title: String
    var summary: String
    var occurredLabel: String
    var supportiveCopy: String
    var nextStep: String
}

struct MobileRelativeFamilyParticipationComment: Identifiable, Equatable {
    var id: String
    var authorLabel: String
    var message: String
    var statusLabel: String
    var createdLabel: String
}

struct MobileRelativeFamilyParticipationBoundary: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var isBlocked: Bool
}

struct MobileRelativeFamilyParticipationNextAction: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var action: MobileRelativeFamilyParticipationNextActionKind
}

enum MobileRelativeFamilyParticipationNextActionKind: String, Equatable {
    case readOnly
    case leaveEncouragement
    case waitForGuardianReview
    case fixUnsafeInput
}

struct MobileRelativeFamilyParticipationPublicSummary: Equatable {
    var status: MobileRelativeFamilyParticipationStatus
    var visibleFeedCount: Int
    var visibleHonorCount: Int
    var approvedCommentCount: Int
    var pendingLocalCommentCount: Int
    var grantsCredit: Bool = false
    var spendsCredit: Bool = false
    var approvesTask: Bool = false
    var rejectsTask: Bool = false
    var writesLedger: Bool = false
    var unlocksDevice: Bool = false
    var sendsNotification: Bool = false
    var uploadsMedia: Bool = false
    var callsNetwork: Bool = false
    var writesSchoolSystem: Bool = false
    var publishesHonorWall: Bool = false
}

struct MobileRelativeFamilyParticipationCenterBuilder {
    var family: LocalFamilyStore
    var schoolFamily: SchoolFamilyStore
    var achievementStore: FamilyGrowthAchievementStore
    var offlineOutbox: MobileOfflineOutboxStore

    init(
        family: LocalFamilyStore,
        schoolFamily: SchoolFamilyStore,
        achievementStore: FamilyGrowthAchievementStore,
        offlineOutbox: MobileOfflineOutboxStore
    ) {
        self.family = family
        self.schoolFamily = schoolFamily
        self.achievementStore = achievementStore
        self.offlineOutbox = offlineOutbox
    }

    func build() -> MobileRelativeFamilyParticipationCenter {
        let visibleFeed = schoolFamily.visibleFeed(for: .relative)
        let visibleHonor = schoolFamily.visibleHonorWall(for: .relative)
        let visibleComments = schoolFamily.visibleComments(for: .relative)
        let achievementDashboard = FamilyAchievementSnapshotDashboardBuilder(store: achievementStore)
            .dashboard(for: .relative)
        let achievementCards = achievementStore.summary(for: .relative).cards
        let localPendingComments = offlineOutbox.mutations.filter {
            $0.kind == .relativeComment && $0.status == .pending
        }
        let unsafe = hasUnsafeDisplayPayload(
            feed: visibleFeed,
            honor: visibleHonor,
            comments: visibleComments,
            achievementCards: achievementCards,
            pendingComments: localPendingComments
        )

        if unsafe {
            return blockedShell()
        }

        let cards = visibleFeed.map(feedCard)
            + visibleHonor.map(honorCard)
            + achievementCards.prefix(4).map(achievementCard)
        let comments = visibleComments.map(commentCard)
            + localPendingComments.prefix(3).map(localPendingComment)
        let status: MobileRelativeFamilyParticipationStatus = localPendingComments.isEmpty ? .ready : .waitingForGuardianReview
        let publicSummary = MobileRelativeFamilyParticipationPublicSummary(
            status: status,
            visibleFeedCount: visibleFeed.count,
            visibleHonorCount: visibleHonor.count,
            approvedCommentCount: visibleComments.count,
            pendingLocalCommentCount: localPendingComments.count
        )

        return MobileRelativeFamilyParticipationCenter(
            status: status,
            headline: status == .ready ? "亲友可以安全参与孩子成长" : "鼓励留言已进入待审核队列",
            subtitle: "这里只展示家长允许亲友看到的内容，留言会先交给家长审核。",
            relativeCount: family.relativeParticipationSummary.relativeCount,
            visibleFeedCount: visibleFeed.count,
            visibleHonorCount: visibleHonor.count,
            approvedCommentCount: visibleComments.count,
            pendingLocalCommentCount: localPendingComments.count,
            abilityAverageScore: achievementDashboard.abilityCardSummary.averageScore,
            visibleCards: cards,
            comments: comments,
            boundaries: boundaryRows(),
            nextActions: nextActions(status: status, canSuggest: family.relatives.contains { $0.capability.canSuggest }),
            publicSummary: publicSummary
        )
    }

    private func feedCard(_ entry: GrowthFeedEntry) -> MobileRelativeFamilyParticipationCard {
        MobileRelativeFamilyParticipationCard(
            id: stableRef(prefix: "feed", source: "\(entry.title):\(entry.occurredLabel)"),
            kindLabel: "成长动态",
            title: entry.title,
            summary: entry.summary,
            occurredLabel: entry.occurredLabel,
            supportiveCopy: "亲友可以看见这条家长允许展示的成长记录。",
            nextStep: "可以留一句鼓励，等待家长审核。"
        )
    }

    private func honorCard(_ item: HonorWallItem) -> MobileRelativeFamilyParticipationCard {
        MobileRelativeFamilyParticipationCard(
            id: stableRef(prefix: "honor", source: "\(item.title):\(item.category)"),
            kindLabel: "荣誉墙",
            title: item.title,
            summary: "\(item.category) · 已由家长确认",
            occurredLabel: "家庭荣誉",
            supportiveCopy: "这份荣誉只展示脱敏摘要，不展示原始证明。",
            nextStep: "亲友可以表达支持，但不能发放奖励。"
        )
    }

    private func achievementCard(_ card: FamilyGrowthCard) -> MobileRelativeFamilyParticipationCard {
        MobileRelativeFamilyParticipationCard(
            id: card.publicRef,
            kindLabel: card.kind.label,
            title: card.title,
            summary: card.displaySummary(for: .relative),
            occurredLabel: card.occurredLabel,
            supportiveCopy: card.supportiveCopy,
            nextStep: card.nextStep
        )
    }

    private func commentCard(_ comment: RelativeFeedComment) -> MobileRelativeFamilyParticipationComment {
        MobileRelativeFamilyParticipationComment(
            id: stableRef(prefix: "comment", source: "\(comment.relativeNickname):\(comment.createdLabel):\(comment.message)"),
            authorLabel: comment.relativeNickname,
            message: comment.message,
            statusLabel: "已通过",
            createdLabel: comment.createdLabel
        )
    }

    private func localPendingComment(_ mutation: MobileOfflineMutation) -> MobileRelativeFamilyParticipationComment {
        MobileRelativeFamilyParticipationComment(
            id: mutation.clientMutationRef,
            authorLabel: "亲友留言",
            message: mutation.summaryPreview,
            statusLabel: "待家长审核",
            createdLabel: "本地队列"
        )
    }

    private func boundaryRows() -> [MobileRelativeFamilyParticipationBoundary] {
        [
            MobileRelativeFamilyParticipationBoundary(
                id: "view",
                title: "只看家长开放内容",
                detail: "私密日记、待审核证明、作业细节和跨孩子内容不会出现在亲友视角。",
                isBlocked: false
            ),
            MobileRelativeFamilyParticipationBoundary(
                id: "credit",
                title: "亲友不能发成长积分",
                detail: "鼓励留言不会修改任务、账本或奖励余额。",
                isBlocked: true
            ),
            MobileRelativeFamilyParticipationBoundary(
                id: "device",
                title: "亲友不能解锁设备",
                detail: "所有手机时间、设备命令和会话仍由家长/孩子原流程处理。",
                isBlocked: true
            )
        ]
    }

    private func nextActions(
        status: MobileRelativeFamilyParticipationStatus,
        canSuggest: Bool
    ) -> [MobileRelativeFamilyParticipationNextAction] {
        if status == .blocked {
            return [
                MobileRelativeFamilyParticipationNextAction(
                    id: "fix-unsafe",
                    title: "内容被安全边界保护",
                    detail: "请删掉链接、路径、账号、局域网地址或内部标识后再试。",
                    action: .fixUnsafeInput
                )
            ]
        }
        var actions = [
            MobileRelativeFamilyParticipationNextAction(
                id: "read-only",
                title: "放心查看成长摘要",
                detail: "当前页面不会审批、发成长积分、写账本或解锁设备。",
                action: .readOnly
            )
        ]
        if canSuggest {
            actions.append(
                MobileRelativeFamilyParticipationNextAction(
                    id: "leave-encouragement",
                    title: "留一句鼓励",
                    detail: "留言只进入本地队列，等家长审核后才会展示。",
                    action: .leaveEncouragement
                )
            )
        }
        if status == .waitingForGuardianReview {
            actions.append(
                MobileRelativeFamilyParticipationNextAction(
                    id: "wait-review",
                    title: "等待家长审核",
                    detail: "已有留言待同步或待审核，不会直接通知其他亲友。",
                    action: .waitForGuardianReview
                )
            )
        }
        return actions
    }

    private func blockedShell() -> MobileRelativeFamilyParticipationCenter {
        MobileRelativeFamilyParticipationCenter(
            status: .blocked,
            headline: "亲友参与中心已保护",
            subtitle: "检测到不适合展示给亲友的内容，本地壳已隐藏详情。",
            relativeCount: family.relativeParticipationSummary.relativeCount,
            visibleFeedCount: 0,
            visibleHonorCount: 0,
            approvedCommentCount: 0,
            pendingLocalCommentCount: 0,
            abilityAverageScore: nil,
            visibleCards: [],
            comments: [],
            boundaries: boundaryRows(),
            nextActions: nextActions(status: .blocked, canSuggest: false),
            publicSummary: MobileRelativeFamilyParticipationPublicSummary(
                status: .blocked,
                visibleFeedCount: 0,
                visibleHonorCount: 0,
                approvedCommentCount: 0,
                pendingLocalCommentCount: 0
            )
        )
    }

    private func hasUnsafeDisplayPayload(
        feed: [GrowthFeedEntry],
        honor: [HonorWallItem],
        comments: [RelativeFeedComment],
        achievementCards: [FamilyGrowthCard],
        pendingComments: [MobileOfflineMutation]
    ) -> Bool {
        var values: [String] = []
        values += feed.flatMap { [$0.title, $0.summary, $0.occurredLabel] }
        values += honor.flatMap { [$0.title, $0.category] }
        values += comments.flatMap { [$0.relativeNickname, $0.message, $0.createdLabel] }
        values += achievementCards.flatMap { [$0.title, $0.summary, $0.supportiveCopy, $0.nextStep] }
        values += pendingComments.flatMap { [$0.actorPublicRef, $0.subjectPublicRef, $0.summaryPreview] }
        values += [
            family.relativeParticipationSummary.anyRelativeCanGrantCredit ? "grant-credit" : "safe-credit",
            family.relativeParticipationSummary.anyRelativeCanUnlockDevice ? "unlock-device" : "safe-device"
        ]
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        return [
            "child:",
            "family:",
            "school:",
            "teacher:",
            "guardian:",
            "relative:",
            "homework:",
            "session:",
            "device:",
            "ledger:",
            "taskid",
            "claimid",
            "baseurl",
            "/users/",
            "/volumes/",
            "192.168.",
            "http://",
            "https://",
            "发成长积分",
            "解锁设备",
            "批准任务"
        ].contains { joined.contains($0) }
    }

    private func stableRef(prefix: String, source: String) -> String {
        var hash = 5381
        for scalar in source.unicodeScalars {
            hash = ((hash << 5) &+ hash) ^ Int(scalar.value)
        }
        return "\(prefix)-\(String(UInt(bitPattern: hash), radix: 36))"
    }
}
