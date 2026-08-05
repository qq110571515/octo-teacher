import Foundation

/// 家长模块配置草稿中心。
///
/// 第一版只生成本地草稿预览，不写任务、账本、学校系统、通知、设备或云端。
enum MobileModuleConfigurationDraftViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case operations

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .operations: return "运营"
        }
    }
}

enum MobileModuleConfigurationDraftStatus: String, Equatable {
    case ready
    case reviewRequired = "review_required"
    case blocked

    var label: String {
        switch self {
        case .ready: return "可预览"
        case .reviewRequired: return "需家长复核"
        case .blocked: return "已阻断"
        }
    }
}

enum MobileModuleConfigurationDayPart: String, CaseIterable, Equatable {
    case morning
    case afterSchool = "after_school"
    case evening
    case weekend

    var label: String {
        switch self {
        case .morning: return "早晨"
        case .afterSchool: return "放学后"
        case .evening: return "晚上"
        case .weekend: return "周末"
        }
    }
}

enum MobileModuleConfigurationFindingCode: String, Equatable {
    case draftReady = "DRAFT_READY"
    case creditBudgetReview = "CREDIT_BUDGET_REVIEW"
    case schoolPriority = "SCHOOL_PRIORITY"
    case childControlsHidden = "CHILD_CONTROLS_HIDDEN"
    case operationsRedacted = "OPERATIONS_REDACTED"
    case unsafeInputBlocked = "UNSAFE_INPUT_BLOCKED"
}

enum MobileModuleConfigurationFindingSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker

    var label: String {
        switch self {
        case .ok: return "正常"
        case .info: return "提示"
        case .warning: return "需复核"
        case .blocker: return "阻断"
        }
    }
}

enum MobileModuleConfigurationReviewPriority: String, Equatable {
    case normal
    case high
    case urgent

    var label: String {
        switch self {
        case .normal: return "普通"
        case .high: return "较高"
        case .urgent: return "优先"
        }
    }
}

struct MobileModuleConfigurationDraftItem: Identifiable, Equatable {
    var publicItemRef: String
    var moduleKey: MobileModuleLaunchModuleKey
    var dayPart: MobileModuleConfigurationDayPart
    var title: String
    var detail: String
    var estimatedMinutes: Int
    var creditPreviewMinutes: Int?
    var requiresGuardianApproval: Bool
    var warning: String?

    let writesAssignments = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false
    let callsNetwork = false
    let callsAiProvider = false
    let callsLms = false
    let writesSchoolSystem = false
    let writesEntitlement = false
    let createsOrder = false

    var id: String { publicItemRef }
}

struct MobileModuleConfigurationReviewAction: Identifiable, Equatable {
    var publicActionRef: String
    var itemRef: String
    var moduleKey: MobileModuleLaunchModuleKey
    var title: String
    var detail: String
    var priority: MobileModuleConfigurationReviewPriority
    var reason: String
    var requiresGuardianDecision: Bool
    var blockedUntilReviewed: Bool

    let writesAssignments = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false
    let callsNetwork = false
    let callsAiProvider = false
    let callsLms = false
    let writesSchoolSystem = false
    let writesEntitlement = false
    let createsOrder = false

    var id: String { publicActionRef }
}

struct MobileModuleConfigurationFinding: Identifiable, Equatable {
    var code: MobileModuleConfigurationFindingCode
    var severity: MobileModuleConfigurationFindingSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct MobileModuleConfigurationPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: MobileModuleConfigurationDraftViewerRole
    var status: MobileModuleConfigurationDraftStatus
    var visibleItemCount: Int
    var hiddenItemCount: Int
    var estimatedMinutesTotal: Int
    var creditPreviewTotal: Int?
    var reviewActionCount: Int
    var blockingActionCount: Int
    var findingCodes: [MobileModuleConfigurationFindingCode]

    let writesAssignments = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false
    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let writesEntitlement = false
    let createsOrder = false
}

struct MobileModuleConfigurationSideEffects: Equatable {
    let writesAssignments = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false
    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let writesEntitlement = false
    let createsOrder = false

    var hasTriggeredSideEffect: Bool {
        writesAssignments || writesLedger || grantsCredit || unlocksDevice || sendsNotification
            || callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || writesEntitlement || createsOrder
    }
}

struct MobileModuleConfigurationDraftSnapshot: Equatable {
    var generatedAt: String
    var viewerRole: MobileModuleConfigurationDraftViewerRole
    var status: MobileModuleConfigurationDraftStatus
    var headline: String
    var items: [MobileModuleConfigurationDraftItem]
    var reviewActions: [MobileModuleConfigurationReviewAction]
    var findings: [MobileModuleConfigurationFinding]
    var publicSummary: MobileModuleConfigurationPublicSummary
    var sideEffects: MobileModuleConfigurationSideEffects

    var displayValues: [String] {
        [generatedAt, viewerRole.rawValue, status.rawValue, headline]
            + items.flatMap {
                [
                    $0.publicItemRef,
                    $0.moduleKey.rawValue,
                    $0.dayPart.rawValue,
                    $0.title,
                    $0.detail,
                    $0.warning ?? ""
                ]
            }
            + reviewActions.flatMap {
                [
                    $0.publicActionRef,
                    $0.itemRef,
                    $0.moduleKey.rawValue,
                    $0.title,
                    $0.detail,
                    $0.priority.rawValue,
                    $0.reason
                ]
            }
            + findings.flatMap { [$0.code.rawValue, $0.severity.rawValue, $0.message, $0.publicRef] }
            + publicSummary.findingCodes.map(\.rawValue)
    }
}

struct MobileModuleConfigurationDraftBuilder {
    var generatedAt = "2026-06-24T17:30:00Z"
    private static let redactionSalt = "mobile-module-configuration-draft-ios-v1"
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "relative:", "guardian:",
        "task:", "claim:", "proof:", "ledger:", "device:", "order:", "entitlement:",
        "publicref", "provider:", "model:", "transcript", "baseurl", "api_key",
        "apikey", "token", "secret", "qwen", "claude", "openai", "credit amount",
        "成长积分金额", "答案键", "老师私密", "家长私密", "http://", "https://",
        "file://", "/users/", "/volumes/", "192.168."
    ]

    func build(
        viewerRole: MobileModuleConfigurationDraftViewerRole,
        family: LocalFamilyStore = LocalFamilyStore(),
        schoolFamily: SchoolFamilyStore = SchoolFamilyStore(),
        unsafePayload: [String] = []
    ) -> MobileModuleConfigurationDraftSnapshot {
        if !redacts(unsafePayload) || MobileSyncPayloadGuard.isUnsafe(unsafePayload) {
            return safeFallback(viewerRole: viewerRole)
        }

        let allItems = draftItems(family: family, schoolFamily: schoolFamily)
        let visibleItems = project(allItems, for: viewerRole)
        let findings = findings(
            viewerRole: viewerRole,
            allItems: allItems,
            visibleItems: visibleItems,
            family: family,
            schoolFamily: schoolFamily
        )
        let reviewActions = reviewActions(viewerRole: viewerRole, visibleItems: visibleItems)
        let status = status(for: findings)
        let summary = MobileModuleConfigurationPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            visibleItemCount: visibleItems.count,
            hiddenItemCount: allItems.count - visibleItems.count,
            estimatedMinutesTotal: visibleItems.reduce(0) { $0 + $1.estimatedMinutes },
            creditPreviewTotal: viewerRole == .guardian ? visibleItems.compactMap(\.creditPreviewMinutes).reduce(0, +) : nil,
            reviewActionCount: reviewActions.count,
            blockingActionCount: reviewActions.filter(\.blockedUntilReviewed).count,
            findingCodes: findings.map(\.code)
        )
        let snapshot = MobileModuleConfigurationDraftSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            headline: headline(for: viewerRole, status: status, visibleCount: visibleItems.count),
            items: visibleItems,
            reviewActions: reviewActions,
            findings: findings,
            publicSummary: summary,
            sideEffects: MobileModuleConfigurationSideEffects()
        )
        return redacts(snapshot.displayValues) ? snapshot : safeFallback(viewerRole: viewerRole)
    }

    func redacts(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ").lowercased()
        return !Self.sensitiveMarkers.contains { joined.contains($0) }
    }

    private func draftItems(
        family: LocalFamilyStore,
        schoolFamily: SchoolFamilyStore
    ) -> [MobileModuleConfigurationDraftItem] {
        var items = family.assignments.prefix(3).map { assignment in
            MobileModuleConfigurationDraftItem(
                publicItemRef: publicRef("task:\(assignment.task.title)"),
                moduleKey: .todayTasks,
                dayPart: assignment.task.category == .health ? .evening : .morning,
                title: assignment.task.title,
                detail: assignment.task.instructions,
                estimatedMinutes: assignment.task.category == .health ? 20 : 15,
                creditPreviewMinutes: assignment.task.rewardMinutes,
                requiresGuardianApproval: true,
                warning: nil
            )
        }

        items.append(
            MobileModuleConfigurationDraftItem(
                publicItemRef: publicRef("growth:\(family.growthPack.title)"),
                moduleKey: .growthPackRuntime,
                dayPart: .afterSchool,
                title: family.growthPack.title,
                detail: "按步骤运行成长包，证明通过后只进入成长积分建议。",
                estimatedMinutes: 25,
                creditPreviewMinutes: 10,
                requiresGuardianApproval: true,
                warning: nil
            )
        )

        if let homework = schoolFamily.openHomeworks.first {
            items.append(
                MobileModuleConfigurationDraftItem(
                    publicItemRef: publicRef("school:\(homework.title)"),
                    moduleKey: .schoolHomework,
                    dayPart: .afterSchool,
                    title: homework.title,
                    detail: "学校作业优先完成；AI 只能引导思路，不直接给答案。",
                    estimatedMinutes: 30,
                    creditPreviewMinutes: 10,
                    requiresGuardianApproval: true,
                    warning: "学校作业应排在娱乐奖励前。"
                )
            )
        }

        items.append(
            MobileModuleConfigurationDraftItem(
                publicItemRef: publicRef("honor:family-review"),
                moduleKey: .honorWall,
                dayPart: .evening,
                title: "家庭荣誉复盘",
                detail: "家长和孩子一起挑选可进入荣誉墙或球星卡的成长证据。",
                estimatedMinutes: 10,
                creditPreviewMinutes: nil,
                requiresGuardianApproval: true,
                warning: nil
            )
        )

        items.append(
            MobileModuleConfigurationDraftItem(
                publicItemRef: publicRef("reward:window"),
                moduleKey: .rewardWindow,
                dayPart: .evening,
                title: "成长积分兑换窗口",
                detail: "只展示可兑换窗口，真正兑换仍需成长积分余额和设备会话护栏。",
                estimatedMinutes: 30,
                creditPreviewMinutes: nil,
                requiresGuardianApproval: true,
                warning: "奖励窗口不应早于学校作业和基础任务。"
            )
        )

        return items
    }

    private func project(
        _ items: [MobileModuleConfigurationDraftItem],
        for role: MobileModuleConfigurationDraftViewerRole
    ) -> [MobileModuleConfigurationDraftItem] {
        switch role {
        case .guardian:
            return items
        case .child:
            return items.map { item in
                MobileModuleConfigurationDraftItem(
                    publicItemRef: item.publicItemRef,
                    moduleKey: item.moduleKey,
                    dayPart: item.dayPart,
                    title: item.title,
                    detail: "这是今天可以努力完成的成长安排，完成后等待家长确认。",
                    estimatedMinutes: item.estimatedMinutes,
                    creditPreviewMinutes: nil,
                    requiresGuardianApproval: false,
                    warning: item.moduleKey == .rewardWindow ? "成长积分要等任务确认后再看。" : nil
                )
            }
        case .operations:
            return items.map { item in
                MobileModuleConfigurationDraftItem(
                    publicItemRef: item.publicItemRef,
                    moduleKey: item.moduleKey,
                    dayPart: item.dayPart,
                    title: item.moduleKey.title,
                    detail: "脱敏模块草稿计数，仅用于发布候选检查。",
                    estimatedMinutes: item.estimatedMinutes,
                    creditPreviewMinutes: nil,
                    requiresGuardianApproval: false,
                    warning: item.warning == nil ? nil : "存在排序或预算提醒。"
                )
            }
        }
    }

    private func findings(
        viewerRole: MobileModuleConfigurationDraftViewerRole,
        allItems: [MobileModuleConfigurationDraftItem],
        visibleItems: [MobileModuleConfigurationDraftItem],
        family: LocalFamilyStore,
        schoolFamily: SchoolFamilyStore
    ) -> [MobileModuleConfigurationFinding] {
        var output = [
            finding(.draftReady, .ok, "模块配置草稿已生成，但不会写入任何系统。")
        ]
        let creditPreview = allItems.compactMap(\.creditPreviewMinutes).reduce(0, +)
        if creditPreview > family.child.dailyLimitMinutes {
            output.append(finding(.creditBudgetReview, .warning, "草稿成长积分预览超过孩子每日娱乐上限，需要家长调整。"))
        }
        if !schoolFamily.openHomeworks.isEmpty {
            output.append(finding(.schoolPriority, .info, "存在未完成学校作业，草稿已提示优先处理。"))
        }
        if viewerRole == .child && visibleItems.allSatisfy({ !$0.requiresGuardianApproval && $0.creditPreviewMinutes == nil }) {
            output.append(finding(.childControlsHidden, .info, "孩子视角已隐藏配置控制和成长积分预览。"))
        }
        if viewerRole == .operations {
            output.append(finding(.operationsRedacted, .info, "运营视角只看脱敏模块草稿计数。"))
        }
        return output
    }

    private func reviewActions(
        viewerRole: MobileModuleConfigurationDraftViewerRole,
        visibleItems: [MobileModuleConfigurationDraftItem]
    ) -> [MobileModuleConfigurationReviewAction] {
        guard viewerRole == .guardian else { return [] }
        return visibleItems
            .filter { $0.requiresGuardianApproval || $0.warning != nil }
            .enumerated()
            .map { index, item in
                let blocked = item.warning != nil || item.moduleKey == .schoolHomework || item.moduleKey == .rewardWindow
                let priority = priority(for: item, blocked: blocked)
                let reason = reviewReason(for: item)
                return MobileModuleConfigurationReviewAction(
                    publicActionRef: publicRef("review:\(item.publicItemRef):\(index)"),
                    itemRef: item.publicItemRef,
                    moduleKey: item.moduleKey,
                    title: "\(item.title) 复核",
                    detail: reviewDetail(for: item, blocked: blocked),
                    priority: priority,
                    reason: reason,
                    requiresGuardianDecision: true,
                    blockedUntilReviewed: blocked
                )
            }
    }

    private func priority(
        for item: MobileModuleConfigurationDraftItem,
        blocked: Bool
    ) -> MobileModuleConfigurationReviewPriority {
        if item.moduleKey == .schoolHomework { return .urgent }
        if blocked || item.moduleKey == .rewardWindow { return .high }
        return .normal
    }

    private func reviewReason(for item: MobileModuleConfigurationDraftItem) -> String {
        if let warning = item.warning { return warning }
        switch item.moduleKey {
        case .schoolHomework:
            return "学校作业需要先完成并等待老师或家长验证。"
        case .rewardWindow:
            return "成长积分窗口需要确认任务顺序和可用积分。"
        default:
            return "该安排需要家长确认后再进入正式执行。"
        }
    }

    private func reviewDetail(
        for item: MobileModuleConfigurationDraftItem,
        blocked: Bool
    ) -> String {
        if blocked {
            return "先由家长复核顺序、时长和证明要求；复核前不发布配置。"
        }
        return "确认后仍只进入对应模块，不能由草稿直接发放积分或解锁设备。"
    }

    private func status(for findings: [MobileModuleConfigurationFinding]) -> MobileModuleConfigurationDraftStatus {
        if findings.contains(where: { $0.severity == .blocker }) { return .blocked }
        if findings.contains(where: { $0.severity == .warning }) { return .reviewRequired }
        return .ready
    }

    private func headline(
        for role: MobileModuleConfigurationDraftViewerRole,
        status: MobileModuleConfigurationDraftStatus,
        visibleCount: Int
    ) -> String {
        switch role {
        case .child: return "今天有 \(visibleCount) 个成长安排可以预览。"
        case .guardian: return "这里是家长模块配置草稿，当前状态：\(status.label)。"
        case .operations: return "这里是脱敏模块配置草稿状态。"
        }
    }

    private func safeFallback(
        viewerRole: MobileModuleConfigurationDraftViewerRole
    ) -> MobileModuleConfigurationDraftSnapshot {
        let finding = finding(.unsafeInputBlocked, .blocker, "配置草稿输入包含不安全展示内容，已切换为安全阻断视图。")
        return MobileModuleConfigurationDraftSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: .blocked,
            headline: "模块配置草稿暂时不可展示",
            items: [],
            reviewActions: [],
            findings: [finding],
            publicSummary: MobileModuleConfigurationPublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: .blocked,
                visibleItemCount: 0,
                hiddenItemCount: 0,
                estimatedMinutesTotal: 0,
                creditPreviewTotal: nil,
                reviewActionCount: 0,
                blockingActionCount: 0,
                findingCodes: [.unsafeInputBlocked]
            ),
            sideEffects: MobileModuleConfigurationSideEffects()
        )
    }

    private func finding(
        _ code: MobileModuleConfigurationFindingCode,
        _ severity: MobileModuleConfigurationFindingSeverity,
        _ message: String
    ) -> MobileModuleConfigurationFinding {
        MobileModuleConfigurationFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("finding:\(code.rawValue):\(message)")
        )
    }

    private func publicRef(_ seed: String) -> String {
        "mcd-\(Self.stableHash("\(Self.redactionSalt):\(seed)"))"
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
