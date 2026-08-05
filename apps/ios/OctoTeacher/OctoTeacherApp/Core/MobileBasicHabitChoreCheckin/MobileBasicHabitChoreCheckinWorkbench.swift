import Foundation

/// iOS 端「个人独立性 / 家务打卡工作台」只读读取模型。
///
/// 它从本地 `LocalFamilyStore` 和既有今日任务包快照中，把早睡早起、阅读、整理、
/// 运动和基础家务类任务整理成孩子 / 家长可看的打卡工作台。这里不提交证明、不批准、
/// 不驳回、不发成长积分、不写账本、不解锁设备、不发通知，也不接任何真实网络、AI、
/// 学校系统或云端服务。

enum MobileBasicHabitChoreViewerRole: String, Equatable, CaseIterable {
    case child
    case guardian

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        }
    }
}

enum MobileBasicHabitChoreKind: String, Equatable, CaseIterable {
    case dailyHabit = "daily_habit"
    case chore
    case reading
    case movement
    case familyCare = "family_care"

    var label: String {
        switch self {
        case .dailyHabit: return "日常习惯"
        case .chore: return "基础家务"
        case .reading: return "阅读习惯"
        case .movement: return "运动健康"
        case .familyCare: return "家庭责任"
        }
    }

    var systemImage: String {
        switch self {
        case .dailyHabit: return "sun.max"
        case .chore: return "sparkles"
        case .reading: return "book"
        case .movement: return "figure.walk"
        case .familyCare: return "house"
        }
    }
}

enum MobileBasicHabitChoreState: String, Equatable, CaseIterable {
    case locked
    case ready
    case waitingCheck = "waiting_check"
    case done
    case redo

    var label: String {
        switch self {
        case .locked: return "待解锁"
        case .ready: return "可打卡"
        case .waitingCheck: return "等待确认"
        case .done: return "已完成"
        case .redo: return "再试一次"
        }
    }
}

enum MobileBasicHabitChoreFindingCode: String, Equatable {
    case workbenchOK = "BASIC_HABIT_CHORE_OK"
    case empty = "BASIC_HABIT_CHORE_EMPTY"
    case waitingCheck = "BASIC_HABIT_CHORE_WAITING_CHECK"
    case redoNeeded = "BASIC_HABIT_CHORE_REDO_NEEDED"
    case offlinePending = "BASIC_HABIT_CHORE_OFFLINE_PENDING"
    case publicSummaryLeak = "BASIC_HABIT_CHORE_PUBLIC_SUMMARY_LEAK"
}

enum MobileBasicHabitChoreSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

struct MobileBasicHabitChoreItem: Identifiable, Equatable {
    var publicItemRef: String
    var assignmentId: UUID
    var title: String
    var kind: MobileBasicHabitChoreKind
    var state: MobileBasicHabitChoreState
    var proof: MobileTodayTaskProofRequirement
    var rewardMinutes: Int
    var streakDays: Int
    var proofSummary: String
    var childNextStep: String
    var guardianNextStep: String

    let approvesTask = false
    let grantsCredit = false
    let writesLedger = false
    let unlocksDevice = false
    let sendsNotification = false

    var id: String { publicItemRef }
    var suggestedGrowthCredits: Int { rewardMinutes }
    var rewardLabel: String { "\(suggestedGrowthCredits) 成长积分" }
}

struct MobileBasicHabitChoreCounts: Equatable {
    var total: Int
    var ready: Int
    var waitingCheck: Int
    var done: Int
    var redo: Int
    var locked: Int

    static let empty = MobileBasicHabitChoreCounts(total: 0, ready: 0, waitingCheck: 0, done: 0, redo: 0, locked: 0)
}

struct MobileBasicHabitChoreRoleProjection: Equatable {
    var viewerRole: MobileBasicHabitChoreViewerRole
    var headline: String
    var visibleItems: [MobileBasicHabitChoreItem]
    var nextActions: [String]

    let approvesTask = false
    let rejectsTask = false
    let grantsCredit = false
    let writesLedger = false
    let unlocksDevice = false
    let sendsNotification = false
}

struct MobileBasicHabitChoreFinding: Identifiable, Equatable {
    var code: MobileBasicHabitChoreFindingCode
    var severity: MobileBasicHabitChoreSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct MobileBasicHabitChorePublicSummary: Equatable {
    var generatedAt: String
    var publicWorkbenchRef: String
    var viewerRole: MobileBasicHabitChoreViewerRole
    var counts: MobileBasicHabitChoreCounts
    var pendingRewardMinutes: Int
    var suggestedRewardMinutes: Int
    var longestStreakDays: Int
    var offlinePendingCount: Int
    var findingCodes: [MobileBasicHabitChoreFindingCode]

    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let approvesTask = false
    let rejectsTask = false
    let grantsCredit = false
    let spendsCredit = false
    let writesLedger = false
    let unlocksDevice = false
    let sendsNotification = false
    let uploadsMedia = false
}

struct MobileBasicHabitChoreCheckinWorkbench: Equatable {
    var generatedAt: String
    var publicWorkbenchRef: String
    var title: String
    var viewerRole: MobileBasicHabitChoreViewerRole
    var counts: MobileBasicHabitChoreCounts
    var pendingRewardMinutes: Int
    var suggestedRewardMinutes: Int
    var longestStreakDays: Int
    var offlineHint: MobileTodayTaskOfflineHint
    var projection: MobileBasicHabitChoreRoleProjection
    var findings: [MobileBasicHabitChoreFinding]
    var publicSummary: MobileBasicHabitChorePublicSummary

    var isEmpty: Bool { projection.visibleItems.isEmpty }
}

struct MobileBasicHabitChoreCheckinWorkbenchBuilder {
    var generatedAt: String = "2026-06-24T09:30:00Z"
    var redactionSalt: String = "mobile-basic-habit-chore-ios-v1"

    private let todayBuilder = MobileTodayTaskPackageWorkbenchBuilder()

    func build(
        store: LocalFamilyStore,
        viewerRole: MobileBasicHabitChoreViewerRole,
        offlineStatus: MobileOfflinePublicStatus = .clean
    ) -> MobileBasicHabitChoreCheckinWorkbench {
        let today = todayBuilder.build(store: store, offlineStatus: offlineStatus)
        if today.publicSummary.findingCodes.contains(.publicSummaryLeak) {
            return safeFallback(viewerRole: viewerRole)
        }

        let items = buildItems(store: store, todayCards: today.cards)
        let counts = count(items)
        let pendingReward = items
            .filter { $0.state == .waitingCheck }
            .reduce(0) { $0 + $1.rewardMinutes }
        let suggestedReward = items
            .filter { $0.state == .ready || $0.state == .redo }
            .reduce(0) { $0 + $1.rewardMinutes }
        let longestStreak = items.map(\.streakDays).max() ?? 0
        let offlineHint = safeOfflineHint(from: today.offlineHint)
        let projection = roleProjection(
            viewerRole: viewerRole,
            items: items,
            counts: counts,
            pendingReward: pendingReward,
            suggestedReward: suggestedReward,
            offline: offlineHint
        )
        let findings = collectFindings(items: items, counts: counts, offline: offlineHint)
        let publicWorkbenchRef = publicRef("habit", "\(viewerRole.rawValue):basic-habit-chore")
        let publicSummary = MobileBasicHabitChorePublicSummary(
            generatedAt: generatedAt,
            publicWorkbenchRef: publicWorkbenchRef,
            viewerRole: viewerRole,
            counts: counts,
            pendingRewardMinutes: pendingReward,
            suggestedRewardMinutes: suggestedReward,
            longestStreakDays: longestStreak,
            offlinePendingCount: offlineHint.pendingCount,
            findingCodes: findings.map(\.code)
        )
        let workbench = MobileBasicHabitChoreCheckinWorkbench(
            generatedAt: generatedAt,
            publicWorkbenchRef: publicWorkbenchRef,
            title: "个人独立性与家务打卡",
            viewerRole: viewerRole,
            counts: counts,
            pendingRewardMinutes: pendingReward,
            suggestedRewardMinutes: suggestedReward,
            longestStreakDays: longestStreak,
            offlineHint: offlineHint,
            projection: projection,
            findings: findings,
            publicSummary: publicSummary
        )
        return redacts(workbench) ? workbench : safeFallback(viewerRole: viewerRole)
    }

    func redacts(_ workbench: MobileBasicHabitChoreCheckinWorkbench) -> Bool {
        let values = publicStrings(workbench)
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ").lowercased()
        for marker in [
            "child:", "family:", "school:", "teacher:", "guardian:", "relative:",
            "task:", "claim:", "proof:", "ledger:", "device:", "order:", "session:",
            "entitlement:", "homework:", "provider:", "model:", "transcript",
            "http://", "https://", "/users/", "/volumes/", "192.168.", "token",
            "api_key", "apikey", "secret", "批准", "驳回", "发成长积分", "写账本", "解锁设备"
        ] {
            if joined.contains(marker.lowercased()) { return false }
        }
        return true
    }

    private func buildItems(
        store: LocalFamilyStore,
        todayCards: [MobileTodayTaskCard]
    ) -> [MobileBasicHabitChoreItem] {
        store.growthPack.steps
            .sorted { $0.order < $1.order }
            .compactMap { step in
                guard
                    let assignment = store.assignment(for: step),
                    let card = todayCards.first(where: { $0.order == step.order })
                else { return nil }
                let state = state(from: card.state)
                return MobileBasicHabitChoreItem(
                    publicItemRef: publicRef("habit-item", step.assignmentId.uuidString),
                    assignmentId: step.assignmentId,
                    title: localizedTitle(step.title, category: assignment.task.category),
                    kind: kind(for: assignment.task),
                    state: state,
                    proof: card.proof,
                    rewardMinutes: step.rewardMinutes,
                    streakDays: streakDays(for: state, order: step.order),
                    proofSummary: proofSummary(for: assignment, proof: card.proof),
                    childNextStep: childNextStep(state: state, proof: card.proof),
                    guardianNextStep: guardianNextStep(state: state)
                )
            }
    }

    private func state(from state: MobileTodayTaskCardState) -> MobileBasicHabitChoreState {
        switch state {
        case .locked: return .locked
        case .active: return .ready
        case .waitingCheck: return .waitingCheck
        case .done: return .done
        case .redo: return .redo
        }
    }

    private func kind(for task: TaskTemplate) -> MobileBasicHabitChoreKind {
        let title = task.title.lowercased()
        if title.contains("read") || title.contains("阅读") { return .reading }
        if title.contains("clean") || title.contains("desk") || title.contains("整理") || task.category == .home { return .chore }
        if title.contains("exercise") || title.contains("运动") || task.category == .health { return .movement }
        if task.category == .family { return .familyCare }
        return .dailyHabit
    }

    private func localizedTitle(_ title: String, category: TaskCategory) -> String {
        let normalized = title.lowercased()
        if normalized.contains("read") || normalized.contains("阅读") { return "晨读 / 睡前阅读" }
        if normalized.contains("clean") || normalized.contains("desk") || normalized.contains("整理") { return "整理书桌" }
        if normalized.contains("exercise") || normalized.contains("运动") { return "运动 20 分钟" }
        switch category {
        case .home: return "基础家务"
        case .learning: return "学习习惯"
        case .health: return "健康习惯"
        case .creative: return "创作习惯"
        case .family: return "家庭责任"
        case .school: return "学校任务"
        }
    }

    private func streakDays(for state: MobileBasicHabitChoreState, order: Int) -> Int {
        switch state {
        case .done: return max(1, order + 2)
        case .waitingCheck: return max(1, order + 1)
        case .ready: return max(1, order)
        case .redo, .locked: return 0
        }
    }

    private func proofSummary(
        for assignment: TaskAssignment,
        proof: MobileTodayTaskProofRequirement
    ) -> String {
        switch assignment.proof.status {
        case .submitted:
            if proof == .text {
                return "已提交文字证明，内容已脱敏。"
            }
            if assignment.proof.photoFileName != nil {
                return "已提交本机照片证明，等待大人确认。"
            }
            return "已提交旧本地图片证明，未上传媒体。"
        case .drafting:
            return "证明还在草稿中，未进入确认。"
        case .empty:
            return "需要\(proof.label)作为本地证明。"
        }
    }

    private func childNextStep(
        state: MobileBasicHabitChoreState,
        proof: MobileTodayTaskProofRequirement
    ) -> String {
        switch state {
        case .locked: return "先完成前面的习惯，这一项就会解锁。"
        case .ready: return proof.hint
        case .waitingCheck: return "已经交啦，等大人看看就好。"
        case .done: return "今天这项已经完成，继续保持。"
        case .redo: return "再做一次，补上更清楚的证明。"
        }
    }

    private func guardianNextStep(state: MobileBasicHabitChoreState) -> String {
        switch state {
        case .locked: return "前置习惯未完成，仅展示锁定状态。"
        case .ready: return "孩子还没提交证明，可在配置草稿里调整提醒。"
        case .waitingCheck: return "查看脱敏证明摘要，真正处理仍回到原有复核闭环。"
        case .done: return "已完成，可作为习惯连续性参考。"
        case .redo: return "需要孩子重做，工作台不直接处理。"
        }
    }

    private func count(_ items: [MobileBasicHabitChoreItem]) -> MobileBasicHabitChoreCounts {
        MobileBasicHabitChoreCounts(
            total: items.count,
            ready: items.filter { $0.state == .ready }.count,
            waitingCheck: items.filter { $0.state == .waitingCheck }.count,
            done: items.filter { $0.state == .done }.count,
            redo: items.filter { $0.state == .redo }.count,
            locked: items.filter { $0.state == .locked }.count
        )
    }

    private func roleProjection(
        viewerRole: MobileBasicHabitChoreViewerRole,
        items: [MobileBasicHabitChoreItem],
        counts: MobileBasicHabitChoreCounts,
        pendingReward: Int,
        suggestedReward: Int,
        offline: MobileTodayTaskOfflineHint
    ) -> MobileBasicHabitChoreRoleProjection {
        switch viewerRole {
        case .child:
            var actions = ["先完成可打卡的个人独立性或家务分项，再提交本地证明。"]
            if pendingReward > 0 { actions.append("有 \(pendingReward) 成长积分正在等待确认。") }
            if offline.hasPending { actions.append("有记录等待同步，联网后仍要等大人看看。") }
            return MobileBasicHabitChoreRoleProjection(
                viewerRole: viewerRole,
                headline: "今天有 \(counts.ready) 项可打卡，\(counts.waitingCheck) 项等待确认。",
                visibleItems: items,
                nextActions: actions
            )
        case .guardian:
            var actions = ["查看待确认习惯的脱敏证明摘要。"]
            if suggestedReward > 0 { actions.append("可建议成长积分 \(suggestedReward) 积分，真正发放仍走原有复核。") }
            if counts.redo > 0 { actions.append("有 \(counts.redo) 项需要孩子重做。") }
            return MobileBasicHabitChoreRoleProjection(
                viewerRole: viewerRole,
                headline: "待确认 \(counts.waitingCheck) 项，最长连续 \(items.map(\.streakDays).max() ?? 0) 天。",
                visibleItems: items,
                nextActions: actions
            )
        }
    }

    private func collectFindings(
        items: [MobileBasicHabitChoreItem],
        counts: MobileBasicHabitChoreCounts,
        offline: MobileTodayTaskOfflineHint
    ) -> [MobileBasicHabitChoreFinding] {
        var findings: [MobileBasicHabitChoreFinding] = []
        if items.isEmpty {
            return [finding(.empty, .info, "当前没有可见的个人独立性或家务任务。", "empty")]
        }
        if counts.waitingCheck > 0 {
            findings.append(finding(.waitingCheck, .info, "有 \(counts.waitingCheck) 项习惯等待确认。", "waiting"))
        }
        if counts.redo > 0 {
            findings.append(finding(.redoNeeded, .warning, "有 \(counts.redo) 项习惯需要再试一次。", "redo"))
        }
        if offline.hasPending {
            findings.append(finding(.offlinePending, .info, "有本地记录等待同步。", "offline"))
        }
        if !findings.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            findings.append(finding(.workbenchOK, .ok, "个人独立性家务工作台已脱敏且无副作用。", "ok"))
        }
        return findings
    }

    private func safeOfflineHint(
        from hint: MobileTodayTaskOfflineHint
    ) -> MobileTodayTaskOfflineHint {
        guard hint.hasPending else {
            return MobileTodayTaskOfflineHint(
                pendingCount: 0,
                title: "记录都已同步",
                message: "你的习惯记录已经安全保存。"
            )
        }
        return MobileTodayTaskOfflineHint(
            pendingCount: hint.pendingCount,
            title: "有 \(hint.pendingCount) 条记录在等待同步",
            message: "联网后仍需确认，记录不会自动生效。"
        )
    }

    private func safeFallback(
        viewerRole: MobileBasicHabitChoreViewerRole
    ) -> MobileBasicHabitChoreCheckinWorkbench {
        let counts = MobileBasicHabitChoreCounts.empty
        let offline = MobileTodayTaskOfflineHint(pendingCount: 0, title: "记录都已同步", message: "你的任务记录已经安全保存。")
        let leak = finding(.publicSummaryLeak, .blocker, "个人独立性家务工作台未通过脱敏检查，已进入安全保护模式。", "leak")
        let publicWorkbenchRef = publicRef("habit", "fallback:\(viewerRole.rawValue)")
        let nextActions: [String]
        switch viewerRole {
        case .child:
            nextActions = [
                "请找爸爸妈妈一起看看，确认后就能继续打卡。",
                "已有的打卡记录都安全保存着，不会丢。"
            ]
        case .guardian:
            nextActions = [
                "部分任务内容未通过脱敏检查，请在家长模式复核任务标题后重试。",
                "已有记录与成长积分不受影响，不会自动发放或解锁。"
            ]
        }
        let projection = MobileBasicHabitChoreRoleProjection(
            viewerRole: viewerRole,
            headline: "个人独立性工作台已进入安全保护模式。",
            visibleItems: [],
            nextActions: nextActions
        )
        let publicSummary = MobileBasicHabitChorePublicSummary(
            generatedAt: generatedAt,
            publicWorkbenchRef: publicWorkbenchRef,
            viewerRole: viewerRole,
            counts: counts,
            pendingRewardMinutes: 0,
            suggestedRewardMinutes: 0,
            longestStreakDays: 0,
            offlinePendingCount: 0,
            findingCodes: [.publicSummaryLeak]
        )
        return MobileBasicHabitChoreCheckinWorkbench(
            generatedAt: generatedAt,
            publicWorkbenchRef: publicWorkbenchRef,
            title: "个人独立性与家务打卡",
            viewerRole: viewerRole,
            counts: counts,
            pendingRewardMinutes: 0,
            suggestedRewardMinutes: 0,
            longestStreakDays: 0,
            offlineHint: offline,
            projection: projection,
            findings: [leak],
            publicSummary: publicSummary
        )
    }

    private func finding(
        _ code: MobileBasicHabitChoreFindingCode,
        _ severity: MobileBasicHabitChoreSeverity,
        _ message: String,
        _ seed: String
    ) -> MobileBasicHabitChoreFinding {
        MobileBasicHabitChoreFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("habit-finding", "\(code.rawValue):\(seed)")
        )
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        MobileTodayTaskPackageWorkbenchBuilder.stablePublicRef(
            prefix: prefix,
            source: source,
            salt: redactionSalt
        )
    }

    private func publicStrings(_ workbench: MobileBasicHabitChoreCheckinWorkbench) -> [String] {
        var values = [
            workbench.generatedAt,
            workbench.publicWorkbenchRef,
            workbench.title,
            workbench.viewerRole.rawValue,
            workbench.viewerRole.label,
            workbench.offlineHint.title,
            workbench.offlineHint.message,
            workbench.projection.headline
        ]
        values += workbench.projection.nextActions
        values += workbench.projection.visibleItems.flatMap {
            [
                $0.publicItemRef,
                $0.title,
                $0.kind.rawValue,
                $0.kind.label,
                $0.state.rawValue,
                $0.state.label,
                $0.proof.label,
                $0.proofSummary,
                $0.childNextStep,
                $0.guardianNextStep
            ]
        }
        values += workbench.findings.flatMap { [$0.publicRef, $0.code.rawValue, $0.message] }
        values += workbench.publicSummary.findingCodes.map(\.rawValue)
        return values
    }
}
