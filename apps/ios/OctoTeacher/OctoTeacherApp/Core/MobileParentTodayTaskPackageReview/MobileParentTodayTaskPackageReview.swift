import Foundation

/// iOS 端「家长今日任务包复核台」只读读取模型。
///
/// 它把孩子端今日任务包工作台、本地任务证明摘要、成长积分和离线队列提示，
/// 编排成家长视角的复核总览。这里不批准、不驳回、不发成长积分、不写账本、
/// 不通知、不上传媒体、不解锁设备；真正处理仍留在 `ParentModeView` 既有闭环。

enum MobileParentTodayTaskPackageReviewViewerRole: String, Equatable, CaseIterable {
    case guardian
    case child
    case relative

    var label: String {
        switch self {
        case .guardian: return "家长"
        case .child: return "孩子"
        case .relative: return "亲友"
        }
    }
}

enum MobileParentTodayTaskReviewFindingCode: String, Equatable {
    case reviewOK = "PARENT_TODAY_PACKAGE_OK"
    case emptyToday = "PARENT_TODAY_PACKAGE_EMPTY"
    case proofWaiting = "PARENT_TODAY_PACKAGE_PROOF_WAITING"
    case redoNeeded = "PARENT_TODAY_PACKAGE_REDO_NEEDED"
    case offlinePending = "PARENT_TODAY_PACKAGE_OFFLINE_PENDING"
    case nonGuardianHidden = "PARENT_TODAY_PACKAGE_NON_GUARDIAN_HIDDEN"
    case publicSummaryLeak = "PARENT_TODAY_PACKAGE_PUBLIC_SUMMARY_LEAK"
}

enum MobileParentTodayTaskReviewSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

struct MobileParentTodayTaskReviewFinding: Identifiable, Equatable {
    var code: MobileParentTodayTaskReviewFindingCode
    var severity: MobileParentTodayTaskReviewSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct MobileParentTodayTaskReviewVisibility: Equatable {
    var viewerRole: MobileParentTodayTaskPackageReviewViewerRole
    var canSeeReviewQueue: Bool
    var canSeeProofSummary: Bool
    var canSeeRewardMinutes: Bool
    var canSeeInternalNextAction: Bool
}

struct MobileParentTodayTaskReviewCounts: Equatable {
    var total: Int
    var readyToStart: Int
    var locked: Int
    var waitingCheck: Int
    var done: Int
    var redo: Int

    static let empty = MobileParentTodayTaskReviewCounts(
        total: 0, readyToStart: 0, locked: 0, waitingCheck: 0, done: 0, redo: 0
    )

    var needsAttention: Int { waitingCheck + redo }
}

struct MobileParentTodayTaskReviewItem: Identifiable, Equatable {
    var publicReviewRef: String
    var order: Int
    var title: String
    var categoryLabel: String
    var state: MobileTodayTaskCardState
    var proofRequirement: MobileTodayTaskProofRequirement
    var proofSummary: String
    var rewardMinutes: Int
    var nextAction: String
    var actionRequired: Bool

    let approvesTask = false
    let rejectsTask = false
    let grantsCredit = false
    let writesLedger = false
    let unlocksDevice = false
    let sendsNotification = false
    let uploadsMedia = false

    var id: String { publicReviewRef }
    var rewardLabel: String { "\(rewardMinutes) 成长积分" }
}

struct MobileParentTodayTaskReviewPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: MobileParentTodayTaskPackageReviewViewerRole
    var publicPackRef: String
    var counts: MobileParentTodayTaskReviewCounts
    var availableMinutes: Int
    var pendingMinutes: Int
    var offlinePendingCount: Int
    var findingCodes: [MobileParentTodayTaskReviewFindingCode]

    let approvesTask = false
    let rejectsTask = false
    let grantsCredit = false
    let writesLedger = false
    let unlocksDevice = false
    let sendsNotification = false
    let uploadsMedia = false
    let callsNetwork = false
    let callsSchoolSystem = false
}

struct MobileParentTodayTaskPackageReview: Equatable {
    var generatedAt: String
    var viewerRole: MobileParentTodayTaskPackageReviewViewerRole
    var publicPackRef: String
    var title: String
    var summary: String
    var visibility: MobileParentTodayTaskReviewVisibility
    var counts: MobileParentTodayTaskReviewCounts
    var items: [MobileParentTodayTaskReviewItem]
    var credit: MobileTodayTaskCreditSummary
    var offlineHint: MobileTodayTaskOfflineHint
    var findings: [MobileParentTodayTaskReviewFinding]
    var publicSummary: MobileParentTodayTaskReviewPublicSummary

    var isEmpty: Bool { items.isEmpty }
}

struct MobileParentTodayTaskPackageReviewBuilder {
    var generatedAt: String = "2026-06-24T04:00:00Z"
    var redactionSalt: String = "mobile-parent-today-task-package-review-ios-v1"

    private let childWorkbenchBuilder = MobileTodayTaskPackageWorkbenchBuilder()

    func build(
        viewerRole: MobileParentTodayTaskPackageReviewViewerRole = .guardian,
        store: LocalFamilyStore,
        offlineStatus: MobileOfflinePublicStatus = .clean
    ) -> MobileParentTodayTaskPackageReview {
        let visibility = visibility(for: viewerRole)
        if !visibility.canSeeReviewQueue {
            return nonGuardianFallback(viewerRole: viewerRole)
        }

        let childWorkbench = childWorkbenchBuilder.build(store: store, offlineStatus: offlineStatus)
        if childWorkbench.publicSummary.findingCodes.contains(.publicSummaryLeak) {
            return safeFallback(viewerRole: viewerRole)
        }
        let items = buildItems(from: childWorkbench, store: store)
        let counts = countItems(items)
        let findings = collectFindings(items: items, counts: counts, offline: childWorkbench.offlineHint)
        let publicSummary = MobileParentTodayTaskReviewPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            publicPackRef: childWorkbench.publicPackRef,
            counts: counts,
            availableMinutes: childWorkbench.credit.availableMinutes,
            pendingMinutes: childWorkbench.credit.pendingMinutes,
            offlinePendingCount: childWorkbench.offlineHint.pendingCount,
            findingCodes: findings.map(\.code)
        )
        let review = MobileParentTodayTaskPackageReview(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            publicPackRef: childWorkbench.publicPackRef,
            title: childWorkbench.packTitle.isEmpty ? "今日任务包复核" : childWorkbench.packTitle,
            summary: childWorkbench.packSummary,
            visibility: visibility,
            counts: counts,
            items: items,
            credit: childWorkbench.credit,
            offlineHint: childWorkbench.offlineHint,
            findings: findings,
            publicSummary: publicSummary
        )
        return redacts(review) ? review : safeFallback(viewerRole: viewerRole)
    }

    func redacts(_ review: MobileParentTodayTaskPackageReview) -> Bool {
        let values = publicStrings(review)
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ")
        for marker in [
            "child:", "family:", "task:", "claim:", "pack:", "ledger:", "device:",
            "proof:", "order:", "session:", "entitlement:", "homework:", "http://",
            "https://", "/users/", "/volumes/", "192.168.", "token", "api_key"
        ] {
            if joined.localizedCaseInsensitiveContains(marker) { return false }
        }
        return true
    }

    private func visibility(
        for role: MobileParentTodayTaskPackageReviewViewerRole
    ) -> MobileParentTodayTaskReviewVisibility {
        switch role {
        case .guardian:
            return MobileParentTodayTaskReviewVisibility(
                viewerRole: role,
                canSeeReviewQueue: true,
                canSeeProofSummary: true,
                canSeeRewardMinutes: true,
                canSeeInternalNextAction: true
            )
        case .child, .relative:
            return MobileParentTodayTaskReviewVisibility(
                viewerRole: role,
                canSeeReviewQueue: false,
                canSeeProofSummary: false,
                canSeeRewardMinutes: false,
                canSeeInternalNextAction: false
            )
        }
    }

    private func buildItems(
        from childWorkbench: MobileTodayTaskPackageWorkbench,
        store: LocalFamilyStore
    ) -> [MobileParentTodayTaskReviewItem] {
        childWorkbench.cards.compactMap { card in
            guard let assignment = assignment(for: card.order, store: store) else { return nil }
            return MobileParentTodayTaskReviewItem(
                publicReviewRef: publicRef("ptr", "\(card.publicTaskRef):\(card.order)"),
                order: card.order,
                title: card.title,
                categoryLabel: card.categoryLabel,
                state: card.state,
                proofRequirement: card.proof,
                proofSummary: proofSummary(assignment.proof),
                rewardMinutes: card.rewardMinutes,
                nextAction: nextAction(for: card.state),
                actionRequired: card.state == .waitingCheck || card.state == .redo
            )
        }
    }

    private func assignment(for order: Int, store: LocalFamilyStore) -> TaskAssignment? {
        guard let step = store.growthPack.steps.first(where: { $0.order == order }) else { return nil }
        return store.assignment(for: step)
    }

    private func proofSummary(_ proof: ProofDraft) -> String {
        let kindLabel: String
        switch proof.kind {
        case .text: kindLabel = "文字证明"
        // 旧数据按照片证明展示，家长复核台不再出现旧标签。
        case .photoPlaceholder, .photo: kindLabel = "照片证明"
        }
        switch proof.status {
        case .empty:
            return "还没有证明"
        case .drafting:
            return "\(kindLabel)正在准备"
        case .submitted:
            return "\(kindLabel)已提交"
        }
    }

    private func nextAction(for state: MobileTodayTaskCardState) -> String {
        switch state {
        case .locked:
            return "等待前一步完成后再复核。"
        case .active:
            return "孩子还可以继续完成这一步。"
        case .waitingCheck:
            return "到原有待批准任务区处理，本复核台不直接批准或驳回。"
        case .done:
            return "已完成，可继续查看后续步骤。"
        case .redo:
            return "确认孩子已看到重做提示，再到原有待批准任务区处理。"
        }
    }

    private func countItems(_ items: [MobileParentTodayTaskReviewItem]) -> MobileParentTodayTaskReviewCounts {
        MobileParentTodayTaskReviewCounts(
            total: items.count,
            readyToStart: items.filter { $0.state == .active }.count,
            locked: items.filter { $0.state == .locked }.count,
            waitingCheck: items.filter { $0.state == .waitingCheck }.count,
            done: items.filter { $0.state == .done }.count,
            redo: items.filter { $0.state == .redo }.count
        )
    }

    private func collectFindings(
        items: [MobileParentTodayTaskReviewItem],
        counts: MobileParentTodayTaskReviewCounts,
        offline: MobileTodayTaskOfflineHint
    ) -> [MobileParentTodayTaskReviewFinding] {
        var findings: [MobileParentTodayTaskReviewFinding] = []
        if items.isEmpty {
            findings.append(finding(.emptyToday, .info, "今天还没有可复核任务。", "empty"))
            return findings
        }
        if counts.waitingCheck > 0 {
            findings.append(finding(.proofWaiting, .warning, "有 \(counts.waitingCheck) 个任务等待家长复核。", "waiting"))
        }
        if counts.redo > 0 {
            findings.append(finding(.redoNeeded, .warning, "有 \(counts.redo) 个任务需要孩子再试一次。", "redo"))
        }
        if offline.hasPending {
            findings.append(finding(.offlinePending, .info, "有离线记录等待同步，不能在本页直接落定。", "offline"))
        }
        if !findings.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            findings.append(finding(.reviewOK, .ok, "今日任务包复核台已脱敏且无副作用。", "ok"))
        }
        return unique(findings)
    }

    private func nonGuardianFallback(
        viewerRole: MobileParentTodayTaskPackageReviewViewerRole
    ) -> MobileParentTodayTaskPackageReview {
        let visibility = visibility(for: viewerRole)
        let counts = MobileParentTodayTaskReviewCounts.empty
        let credit = MobileTodayTaskCreditSummary(availableMinutes: 0, pendingMinutes: 0, lifetimeEarnedMinutes: 0)
        let offline = MobileTodayTaskOfflineHint(pendingCount: 0, title: "记录都已同步", message: "该视角只能查看安全摘要。")
        let finding = finding(.nonGuardianHidden, .info, "该视角不可查看家长复核队列。", viewerRole.rawValue)
        let publicSummary = MobileParentTodayTaskReviewPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            publicPackRef: publicRef("bundle", "hidden-\(viewerRole.rawValue)"),
            counts: counts,
            availableMinutes: 0,
            pendingMinutes: 0,
            offlinePendingCount: 0,
            findingCodes: [.nonGuardianHidden]
        )
        return MobileParentTodayTaskPackageReview(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            publicPackRef: publicSummary.publicPackRef,
            title: "今日任务包",
            summary: "",
            visibility: visibility,
            counts: counts,
            items: [],
            credit: credit,
            offlineHint: offline,
            findings: [finding],
            publicSummary: publicSummary
        )
    }

    private func safeFallback(
        viewerRole: MobileParentTodayTaskPackageReviewViewerRole
    ) -> MobileParentTodayTaskPackageReview {
        let visibility = visibility(for: viewerRole)
        let counts = MobileParentTodayTaskReviewCounts.empty
        let credit = MobileTodayTaskCreditSummary(availableMinutes: 0, pendingMinutes: 0, lifetimeEarnedMinutes: 0)
        let offline = MobileTodayTaskOfflineHint(pendingCount: 0, title: "记录都已同步", message: "复核台已进入安全空壳。")
        let finding = finding(.publicSummaryLeak, .blocker, "今日任务包复核台未通过脱敏检查，已进入安全空壳。", "leak")
        let publicSummary = MobileParentTodayTaskReviewPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            publicPackRef: publicRef("bundle", "redacted-parent-today-package"),
            counts: counts,
            availableMinutes: 0,
            pendingMinutes: 0,
            offlinePendingCount: 0,
            findingCodes: [.publicSummaryLeak]
        )
        return MobileParentTodayTaskPackageReview(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            publicPackRef: publicSummary.publicPackRef,
            title: "今日任务包复核",
            summary: "",
            visibility: visibility,
            counts: counts,
            items: [],
            credit: credit,
            offlineHint: offline,
            findings: [finding],
            publicSummary: publicSummary
        )
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        MobileTodayTaskPackageWorkbenchBuilder.stablePublicRef(
            prefix: prefix,
            source: source,
            salt: redactionSalt
        )
    }

    private func finding(
        _ code: MobileParentTodayTaskReviewFindingCode,
        _ severity: MobileParentTodayTaskReviewSeverity,
        _ message: String,
        _ seed: String
    ) -> MobileParentTodayTaskReviewFinding {
        MobileParentTodayTaskReviewFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("ptr-finding", "\(code.rawValue):\(seed)")
        )
    }

    private func unique(
        _ findings: [MobileParentTodayTaskReviewFinding]
    ) -> [MobileParentTodayTaskReviewFinding] {
        var seen = Set<String>()
        return findings.filter { item in
            let key = item.id
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func publicStrings(_ review: MobileParentTodayTaskPackageReview) -> [String] {
        var values = [
            review.generatedAt,
            review.viewerRole.rawValue,
            review.publicPackRef,
            review.title,
            review.summary,
            review.credit.headline,
            review.offlineHint.title,
            review.offlineHint.message
        ]
        values += review.items.flatMap {
            [
                $0.publicReviewRef,
                $0.title,
                $0.categoryLabel,
                $0.state.label,
                $0.proofRequirement.label,
                $0.proofSummary,
                $0.nextAction
            ]
        }
        values += review.findings.flatMap { [$0.publicRef, $0.code.rawValue, $0.message] }
        values += review.publicSummary.findingCodes.map(\.rawValue)
        return values
    }
}
