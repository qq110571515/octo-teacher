import Foundation

/// iOS 端孩子视角「成长积分钱包与娱乐申请中心」只读读取模型。
///
/// 它聚合本地成长积分、今日任务包收益、娱乐会话状态和离线请求提示，只做展示和导航建议。
/// 这里不批准任务、不发积分、不扣积分、不写账本、不解锁设备、不发通知、不上传媒体，也不接
/// 任何真实网络、云、AI、LMS 或学校系统。真正兑换仍在既有 RewardRedemptionView /
/// StartRewardSessionUseCase 与离线 outbox 闭环里完成。

enum MobileChildCreditWalletSessionState: String, Equatable, CaseIterable {
    case locked
    case active
    case expired

    var label: String {
        switch self {
        case .locked: return "未开启"
        case .active: return "正在使用"
        case .expired: return "已结束"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .locked: return "Not started"
        case .active: return "In use"
        case .expired: return "Ended"
        }
    }

    var systemImage: String {
        switch self {
        case .locked: return "lock.fill"
        case .active: return "lock.open.fill"
        case .expired: return "clock.badge.checkmark"
        }
    }
}

enum MobileChildCreditWalletFindingCode: String, Equatable {
    case walletOK = "CHILD_CREDIT_WALLET_OK"
    case noAvailableCredit = "CHILD_CREDIT_WALLET_NO_AVAILABLE_CREDIT"
    case pendingCredit = "CHILD_CREDIT_WALLET_PENDING_CREDIT"
    case activeSession = "CHILD_CREDIT_WALLET_ACTIVE_SESSION"
    case offlinePending = "CHILD_CREDIT_WALLET_OFFLINE_PENDING"
    case publicSummaryLeak = "CHILD_CREDIT_WALLET_PUBLIC_SUMMARY_LEAK"
}

enum MobileChildCreditWalletSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

struct MobileChildCreditWalletFinding: Identifiable, Equatable {
    var code: MobileChildCreditWalletFindingCode
    var severity: MobileChildCreditWalletSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct MobileChildCreditWalletBalance: Equatable {
    var availableMinutes: Int
    var pendingMinutes: Int
    var lifetimeEarnedMinutes: Int
    var todayPackageRewardMinutes: Int
    var todayDoneRewardMinutes: Int

    var headline: String {
        if pendingMinutes > 0 {
            return "可用 \(availableMinutes) 成长积分，还有 \(pendingMinutes) 积分等确认"
        }
        return "可用 \(availableMinutes) 成长积分"
    }

    func headline(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return headline }
        if pendingMinutes > 0 {
            return "\(availableMinutes) Growth Points available, \(pendingMinutes) waiting for check"
        }
        return "\(availableMinutes) Growth Points available"
    }
}

struct MobileChildCreditWalletSession: Equatable {
    var state: MobileChildCreditWalletSessionState
    var grantedMinutes: Int
    var remainingSeconds: Int
    var latestReceiptSummary: String

    let unlocksDevice = false
    let writesLedger = false
}

enum MobileChildCreditWalletActionKind: String, Equatable {
    case earnToday = "earn_today"
    case openRedemption = "open_redemption"
    case waitForCheck = "wait_for_check"
    case viewSync = "view_sync"
    case viewStatus = "view_status"
}

struct MobileChildCreditWalletAction: Identifiable, Equatable {
    var publicActionRef: String
    var kind: MobileChildCreditWalletActionKind
    var title: String
    var detail: String
    var systemImage: String
    var isPrimary: Bool

    let approvesTask = false
    let grantsCredit = false
    let spendsCredit = false
    let writesLedger = false
    let unlocksDevice = false
    let sendsNotification = false

    var id: String { publicActionRef }
}

struct MobileChildCreditWalletPublicSummary: Equatable {
    var generatedAt: String
    var publicWalletRef: String
    var availableMinutes: Int
    var pendingMinutes: Int
    var todayPackageRewardMinutes: Int
    var sessionState: MobileChildCreditWalletSessionState
    var offlinePendingCount: Int
    var findingCodes: [MobileChildCreditWalletFindingCode]

    let approvesTask = false
    let rejectsTask = false
    let grantsCredit = false
    let spendsCredit = false
    let writesLedger = false
    let unlocksDevice = false
    let sendsNotification = false
    let uploadsMedia = false
    let callsNetwork = false
    let callsSchoolSystem = false
}

struct MobileChildCreditWallet: Equatable {
    var generatedAt: String
    var publicWalletRef: String
    var title: String
    var balance: MobileChildCreditWalletBalance
    var session: MobileChildCreditWalletSession
    var offlineHint: MobileTodayTaskOfflineHint
    var actions: [MobileChildCreditWalletAction]
    var findings: [MobileChildCreditWalletFinding]
    var publicSummary: MobileChildCreditWalletPublicSummary
}

struct MobileChildCreditWalletBuilder {
    var generatedAt: String = "2026-06-24T07:30:00Z"
    var redactionSalt: String = "mobile-child-credit-wallet-ios-v1"

    private let taskWorkbenchBuilder = MobileTodayTaskPackageWorkbenchBuilder()

    func build(
        store: LocalFamilyStore,
        screenTime: MockScreenTimeController,
        offlineStatus: MobileOfflinePublicStatus = .clean,
        now: Date = Date()
    ) -> MobileChildCreditWallet {
        let taskWorkbench = taskWorkbenchBuilder.build(store: store, offlineStatus: offlineStatus)
        if taskWorkbench.publicSummary.findingCodes.contains(.publicSummaryLeak) {
            return safeFallback()
        }

        // 孩子视角文案统一跟随当前活跃孩子的界面语言。
        let language = store.activeChildInterfaceLanguage
        let balance = balanceSummary(store: store, workbench: taskWorkbench)
        let session = sessionSummary(screenTime: screenTime, now: now, language: language)
        let offlineHint = taskWorkbench.offlineHint
        let actions = buildActions(balance: balance, session: session, offline: offlineHint, language: language)
        let findings = collectFindings(balance: balance, session: session, offline: offlineHint, language: language)
        let publicWalletRef = publicRef("wallet", "child-credit-wallet")
        let publicSummary = MobileChildCreditWalletPublicSummary(
            generatedAt: generatedAt,
            publicWalletRef: publicWalletRef,
            availableMinutes: balance.availableMinutes,
            pendingMinutes: balance.pendingMinutes,
            todayPackageRewardMinutes: balance.todayPackageRewardMinutes,
            sessionState: session.state,
            offlinePendingCount: offlineHint.pendingCount,
            findingCodes: findings.map(\.code)
        )
        let wallet = MobileChildCreditWallet(
            generatedAt: generatedAt,
            publicWalletRef: publicWalletRef,
            title: language.pick("成长积分钱包", "Growth Point Wallet"),
            balance: balance,
            session: session,
            offlineHint: offlineHint,
            actions: actions,
            findings: findings,
            publicSummary: publicSummary
        )
        return redacts(wallet) ? wallet : safeFallback()
    }

    func redacts(_ wallet: MobileChildCreditWallet) -> Bool {
        let values = publicStrings(wallet)
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ")
        for marker in [
            "child:", "family:", "task:", "claim:", "pack:", "ledger:", "device:",
            "proof:", "order:", "session:", "entitlement:", "homework:", "http://",
            "https://", "/users/", "/volumes/", "192.168.", "token", "api_key",
            "批准", "发成长积分", "写账本", "审批"
        ] {
            if joined.localizedCaseInsensitiveContains(marker) { return false }
        }
        return true
    }

    private func balanceSummary(
        store: LocalFamilyStore,
        workbench: MobileTodayTaskPackageWorkbench
    ) -> MobileChildCreditWalletBalance {
        MobileChildCreditWalletBalance(
            availableMinutes: store.creditBalance.availableMinutes,
            pendingMinutes: store.creditBalance.pendingMinutes,
            lifetimeEarnedMinutes: store.creditBalance.lifetimeEarnedMinutes,
            todayPackageRewardMinutes: workbench.cards.reduce(0) { $0 + $1.rewardMinutes },
            todayDoneRewardMinutes: workbench.cards.filter { $0.state == .done }.reduce(0) { $0 + $1.rewardMinutes }
        )
    }

    private func sessionSummary(
        screenTime: MockScreenTimeController,
        now: Date,
        language: AppInterfaceLanguage = .chinese
    ) -> MobileChildCreditWalletSession {
        let state = MobileChildCreditWalletSessionState(rawValue: screenTime.sessionStatus.rawValue) ?? .locked
        let remaining: Int
        if state == .active, let endsAt = screenTime.unlockEndsAt {
            remaining = max(0, Int(endsAt.timeIntervalSince(now)))
        } else {
            remaining = 0
        }
        return MobileChildCreditWalletSession(
            state: state,
            grantedMinutes: screenTime.activeMinutes,
            remainingSeconds: remaining,
            latestReceiptSummary: receiptSummary(screenTime.latestReceipt, language: language)
        )
    }

    private func receiptSummary(_ receipt: RewardSessionReceipt?, language: AppInterfaceLanguage) -> String {
        guard let receipt else { return language.pick("还没有本机回执", "No local receipt yet") }
        switch receipt.endReason {
        case .expired:
            return language.pick(
                "上次用满 \(receipt.consumedMinutes) 分钟",
                "Last time you used the full \(receipt.consumedMinutes) minutes"
            )
        case .parentEnded:
            return language.pick(
                "上次提前结束，剩余 \(receipt.unusedMinutes) 分钟",
                "Last session ended early with \(receipt.unusedMinutes) minutes left"
            )
        }
    }

    private func buildActions(
        balance: MobileChildCreditWalletBalance,
        session: MobileChildCreditWalletSession,
        offline: MobileTodayTaskOfflineHint,
        language: AppInterfaceLanguage = .chinese
    ) -> [MobileChildCreditWalletAction] {
        var actions: [MobileChildCreditWalletAction] = []
        if session.state == .active {
            actions.append(action(
                .viewStatus,
                language.pick("查看正在使用的时间", "See the time in use"),
                language.pick("看看还剩多少时间，本页不改变会话。", "Check how much time is left; this page never changes the session."),
                "timer", true
            ))
        } else if balance.availableMinutes >= 15 {
            actions.append(action(
                .openRedemption,
                language.pick("用成长积分换屏幕时间", "Trade Growth Points for screen time"),
                language.pick("到兑换页申请一次屏幕时间，具体多久按家长规则执行。", "Go to the exchange page to request a session; its length follows your parents' rules."),
                "gift", true
            ))
        } else {
            actions.append(action(
                .earnToday,
                language.pick("先完成今日任务", "Finish today's tasks first"),
                language.pick("做完任务并交上证明，就能等待成长积分确认。", "Finish tasks and hand in proof, then wait for your Growth Points to be checked."),
                "checklist", true
            ))
        }
        if balance.pendingMinutes > 0 {
            actions.append(action(
                .waitForCheck,
                language.pick("等待确认", "Waiting for check"),
                language.pick("有成长积分正在等大人看看。", "Some Growth Points are waiting for a grown-up's look."),
                "hourglass", false
            ))
        }
        if offline.hasPending {
            actions.append(action(
                .viewSync,
                language.pick("查看同步进度", "See sync progress"),
                language.pick("离线请求已经排队，已收到不代表已完成。", "Offline requests are queued; received doesn't mean done."),
                "arrow.triangle.2.circlepath", false
            ))
        }
        return actions
    }

    private func collectFindings(
        balance: MobileChildCreditWalletBalance,
        session: MobileChildCreditWalletSession,
        offline: MobileTodayTaskOfflineHint,
        language: AppInterfaceLanguage = .chinese
    ) -> [MobileChildCreditWalletFinding] {
        var findings: [MobileChildCreditWalletFinding] = []
        if balance.availableMinutes == 0 {
            findings.append(finding(.noAvailableCredit, .info, language.pick("现在还没有可用成长积分。", "No Growth Points available yet."), "empty"))
        }
        if balance.pendingMinutes > 0 {
            findings.append(finding(.pendingCredit, .info, language.pick(
                "有 \(balance.pendingMinutes) 成长积分正在等待确认。",
                "\(balance.pendingMinutes) Growth Points are waiting for check."
            ), "pending"))
        }
        if session.state == .active {
            findings.append(finding(.activeSession, .warning, language.pick("有正在使用的娱乐时间。", "A fun-time session is in use."), "active"))
        }
        if offline.hasPending {
            findings.append(finding(.offlinePending, .info, language.pick("有离线请求等待同步。", "Offline requests are waiting to sync."), "offline"))
        }
        if !findings.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            findings.append(finding(.walletOK, .ok, language.pick(
                "成长积分钱包只读、脱敏且无副作用。",
                "The Growth Point wallet is read-only, redacted, and side-effect free."
            ), "ok"))
        }
        return unique(findings)
    }

    private func safeFallback() -> MobileChildCreditWallet {
        let balance = MobileChildCreditWalletBalance(
            availableMinutes: 0,
            pendingMinutes: 0,
            lifetimeEarnedMinutes: 0,
            todayPackageRewardMinutes: 0,
            todayDoneRewardMinutes: 0
        )
        let session = MobileChildCreditWalletSession(
            state: .locked,
            grantedMinutes: 0,
            remainingSeconds: 0,
            latestReceiptSummary: "还没有本机回执"
        )
        let offline = MobileTodayTaskOfflineHint(
            pendingCount: 0,
            title: "记录都已同步",
            message: "成长积分钱包已进入安全空壳。"
        )
        let finding = finding(.publicSummaryLeak, .blocker, "成长积分钱包未通过脱敏检查，已进入安全空壳。", "leak")
        let publicWalletRef = publicRef("wallet", "redacted-child-credit-wallet")
        let publicSummary = MobileChildCreditWalletPublicSummary(
            generatedAt: generatedAt,
            publicWalletRef: publicWalletRef,
            availableMinutes: 0,
            pendingMinutes: 0,
            todayPackageRewardMinutes: 0,
            sessionState: .locked,
            offlinePendingCount: 0,
            findingCodes: [.publicSummaryLeak]
        )
        return MobileChildCreditWallet(
            generatedAt: generatedAt,
            publicWalletRef: publicWalletRef,
            title: "成长积分钱包",
            balance: balance,
            session: session,
            offlineHint: offline,
            actions: [],
            findings: [finding],
            publicSummary: publicSummary
        )
    }

    private func action(
        _ kind: MobileChildCreditWalletActionKind,
        _ title: String,
        _ detail: String,
        _ systemImage: String,
        _ isPrimary: Bool
    ) -> MobileChildCreditWalletAction {
        MobileChildCreditWalletAction(
            publicActionRef: publicRef("wallet-action", "\(kind.rawValue):\(title)"),
            kind: kind,
            title: title,
            detail: detail,
            systemImage: systemImage,
            isPrimary: isPrimary
        )
    }

    private func finding(
        _ code: MobileChildCreditWalletFindingCode,
        _ severity: MobileChildCreditWalletSeverity,
        _ message: String,
        _ seed: String
    ) -> MobileChildCreditWalletFinding {
        MobileChildCreditWalletFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("wallet-finding", "\(code.rawValue):\(seed)")
        )
    }

    private func unique(
        _ findings: [MobileChildCreditWalletFinding]
    ) -> [MobileChildCreditWalletFinding] {
        var seen = Set<String>()
        return findings.filter { item in
            if seen.contains(item.id) { return false }
            seen.insert(item.id)
            return true
        }
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        MobileTodayTaskPackageWorkbenchBuilder.stablePublicRef(
            prefix: prefix,
            source: source,
            salt: redactionSalt
        )
    }

    private func publicStrings(_ wallet: MobileChildCreditWallet) -> [String] {
        var values = [
            wallet.generatedAt,
            wallet.publicWalletRef,
            wallet.title,
            wallet.balance.headline,
            wallet.session.state.label,
            wallet.session.latestReceiptSummary,
            wallet.offlineHint.title,
            wallet.offlineHint.message
        ]
        values += wallet.actions.flatMap { [$0.publicActionRef, $0.title, $0.detail, $0.kind.rawValue] }
        values += wallet.findings.flatMap { [$0.publicRef, $0.code.rawValue, $0.message] }
        values += wallet.publicSummary.findingCodes.map(\.rawValue)
        return values
    }
}
