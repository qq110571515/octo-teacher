import SwiftUI
#if canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
import ManagedSettings
#endif

struct RewardStatusView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(MockScreenTimeController.self) private var screenTimeController
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay
    @Environment(MobileCreditSettlementStore.self) private var creditSettlement
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @Environment(ScreenTimePOCManager.self) private var screenTimePOCManager
    #endif
    @State private var now = Date()
    @State private var latestRedemptionResult: (result: StartRewardSessionResult, minutes: Int, cost: Int)?
    @State private var setupHint: String?
    @State private var exchangeTransactionState: RewardExchangeTransactionState = .idle
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @State private var selectedApplicationToken: ApplicationToken?
    #endif

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var status: RewardSessionStatus { screenTimeController.sessionStatus }

    private var isUITestMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-OctoTeacherUITest") }
        #else
        false
        #endif
    }

    /// 当前孩子的界面语言：本页所有可见文案与小喇叭 speech 都从这里取。
    private var loc: ChildLocalizationContext { ChildLocalizationContext(language: childSurfaceLanguage) }

    private var mayExecuteDeviceControl: Bool {
        ScreenTimeSharedContract.mayExecuteDeviceControl(
            isChildDevice: familyCloud.isChildDevice,
            isUITestMode: isUITestMode
        )
    }

    private var dailyRemainingMinutes: Int {
        max(0, store.child.dailyLimitMinutes - screenTimeController.grantedMinutes(on: now))
    }

    private var options: [Int] {
        RewardScreenTimeUI.exchangeMinutes(
            customMinutes: store.policy(for: store.activeChildId).resolvedScreenExchangeMinutes
        )
    }

    var remainingSeconds: Int {
        guard let end = screenTimeController.unlockEndsAt else { return 0 }
        return max(0, Int(end.timeIntervalSince(now)))
    }

    private var selectedAppWindowEndsAt: Date? {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        if isUITestMode { return screenTimeController.unlockEndsAt }
        guard let selectedApplicationToken else { return nil }
        return screenTimePOCManager.rewardWindowEnd(for: selectedApplicationToken, at: now)
        #else
        return screenTimeController.unlockEndsAt
        #endif
    }

    private var selectedAppHasActiveWindow: Bool {
        selectedAppWindowEndsAt != nil
    }

    private var selectedAppRemainingSeconds: Int {
        max(0, Int(selectedAppWindowEndsAt?.timeIntervalSince(now) ?? 0))
    }

    private func exchangeAvailability(
        minutes: Int,
        cost: Int,
        transactionState: RewardExchangeTransactionState? = nil
    ) -> RewardExchangeAvailability {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let schoolMode = screenTimePOCManager.schoolModeIsActive
        #else
        let schoolMode = false
        #endif
        let dailyRequiredMinutes = screenTimeController.additionalGrantedMinutes(
            for: minutes,
            startingAt: now
        )
        return RewardScreenTimeUI.availability(
            dailyRequiredMinutes: dailyRequiredMinutes,
            cost: cost,
            availablePoints: store.child.rewardBalanceMinutes,
            dailyRemainingMinutes: dailyRemainingMinutes,
            isSchoolMode: schoolMode,
            isAuthorized: realDeviceReady,
            selectedAppIsActive: selectedAppHasActiveWindow,
            transactionState: transactionState ?? exchangeTransactionState
        )
    }

    private var exchangeSummaryAvailability: RewardExchangeAvailability {
        let availabilities = options.map { minutes in
            exchangeAvailability(
                minutes: minutes,
                cost: store.policy(for: store.activeChildId).screenPointsRequired(forMinutes: minutes)
            )
        }
        return availabilities.first(where: { $0 == .available }) ?? availabilities.first ?? .unauthorized
    }

    var body: some View {
        NavigationStack {
            List {
                Section(loc.pick("成长积分余额", "Growth Points Balance")) {
                    HStack {
                        Text(GrowthCreditCopy.label(points: store.child.rewardBalanceMinutes, language: loc.language))
                            .font(.title.bold())
                            .monospacedDigit()
                            .accessibilityIdentifier("reward-status-balance")
                        Spacer()
                        SpeakButton(text: balanceSpeakText, language: loc.language)
                    }
                }

                Section(loc.pick("使用状态", "Play Status")) {
                    HStack {
                        Label(statusTitle, systemImage: statusIcon)
                            .accessibilityIdentifier("reward-status-state-\(status.rawValue)")
                        Spacer()
                        SpeakButton(text: sessionStatusSpeakText, language: loc.language)
                    }

                    if status == .active {
                        Text(remainingTimeText)
                            .monospacedDigit()
                            .accessibilityIdentifier("reward-status-remaining")
                    } else if status == .expired {
                        Text(sessionExpiredText)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("reward-status-expired-message")
                    }
                }

                if !mayExecuteDeviceControl {
                    Section {
                        Label(
                            loc.pick("家长端只查看状态；兑换和设备控制请在孩子手机完成。", "The guardian view is status-only. Exchange and device control happen on the child's phone."),
                            systemImage: "iphone.and.arrow.forward"
                        )
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("reward-status-guardian-preview")
                    }
                }

                #if canImport(FamilyControls) && canImport(ManagedSettings)
                Section(loc.pick("选择 App", "Choose an App")) {
                    Label(
                        screenTimePOCManager.canStartSingleAppRewardWindow
                            ? loc.pick("可以兑换屏幕时间", "Screen time is ready")
                            : loc.pick("请家长先完成屏幕时间设置", "Ask a parent to finish Screen Time setup"),
                        systemImage: screenTimePOCManager.canStartSingleAppRewardWindow ? "iphone.gen3.badge.checkmark" : "iphone.slash"
                    )
                    .accessibilityIdentifier("reward-status-real-device-readiness")

                    ForEach(Array(screenTimePOCManager.selection.applicationTokens), id: \.self) { token in
                        Button {
                            selectedApplicationToken = token
                        } label: {
                            HStack {
                                Label(token)
                                Spacer()
                                if let endsAt = screenTimePOCManager.rewardWindowEnd(for: token, at: now) {
                                    Label(countdown(until: endsAt), systemImage: "timer")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.orange)
                                } else if selectedApplicationToken == token {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(exchangeTransactionState == .inFlight)
                    }
                    if let setupHint {
                        HStack(alignment: .top) {
                            Text(setupHint)
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                            SpeakButton(text: setupHint, language: loc.language)
                        }
                    }
                }
                #endif

                Section {
                    Label(
                        loc.pick(
                            "今天还可兑换 \(dailyRemainingMinutes) / \(store.child.dailyLimitMinutes) 分钟",
                            "\(dailyRemainingMinutes) / \(store.child.dailyLimitMinutes) minutes left today"
                        ),
                        systemImage: "clock"
                    )
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(options, id: \.self) { minutes in
                            let cost = store.policy(for: store.activeChildId).screenPointsRequired(forMinutes: minutes)
                            let availability = exchangeAvailability(minutes: minutes, cost: cost)
                            Button {
                                startRewardSession(minutes: minutes, cost: cost)
                            } label: {
                                VStack(spacing: 5) {
                                    Text(loc.pick("\(minutes) 分钟", "\(minutes) min"))
                                        .font(.headline)
                                    Text(GrowthCreditCopy.label(points: cost, language: loc.language))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Text(RewardScreenTimeUI.title(for: availability, language: loc.language))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(availability == .available ? Color.green : Color.orange)
                                }
                                .frame(maxWidth: .infinity, minHeight: 82)
                                .background(
                                    availability == .available ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(availability != .available)
                            .accessibilityHint(RewardScreenTimeUI.detail(
                                for: availability,
                                language: loc.language,
                                isPreReader: store.isPreReaderActive
                            ))
                            .accessibilityIdentifier("reward-status-use-\(minutes)")
                        }
                    }

                    if selectedAppHasActiveWindow {
                        Label(
                            loc.pick(
                                "这个 App 还剩 \(selectedAppRemainingSeconds / 60):\(String(format: "%02d", selectedAppRemainingSeconds % 60))",
                                "This app has \(selectedAppRemainingSeconds / 60):\(String(format: "%02d", selectedAppRemainingSeconds % 60)) left"
                            ),
                            systemImage: "timer"
                        )
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    }

                    Button {
                        #if canImport(FamilyControls) && canImport(ManagedSettings)
                        if isUITestMode {
                            screenTimeController.reshieldNow()
                        } else if let selectedApplicationToken,
                           let removed = screenTimePOCManager.relockRewardWindow(
                               for: selectedApplicationToken,
                               referenceDate: now
                           ) {
                            queueCompletedScreenTimeReceipt(screenTimeController.endConcurrentExternalUnlock(
                                sessionID: removed.resolvedID,
                                now: now
                            ))
                        }
                        #else
                        screenTimeController.reshieldNow()
                        #endif
                    } label: {
                        Label(loc.pick("结束所选 App", "End Selected App"), systemImage: "stop.circle")
                    }
                    .disabled(!selectedAppHasActiveWindow || !mayExecuteDeviceControl)
                    .accessibilityIdentifier("reward-status-end-session")
                } header: {
                    HStack {
                        Text(loc.pick("玩多久？", "How Long?"))
                        Spacer()
                        SpeakButton(
                            text: store.isPreReaderActive
                                ? loc.pick("选时间。", "Pick a time.")
                                : loc.pick("每次可以兑换十五、三十、四十五或六十分钟。", "Choose 15, 30, 45, or 60 minutes each time."),
                            language: loc.language
                        )
                    }
                } footer: {
                    Text(RewardScreenTimeUI.detail(
                        for: exchangeSummaryAvailability,
                        language: loc.language,
                        isPreReader: store.isPreReaderActive
                    ))
                }

                if let latestRedemptionResult {
                    Section(loc.pick("最近兑换结果", "Latest Exchange Result")) {
                        Label(
                            ScreenTimeRedemptionResultCopy.title(for: latestRedemptionResult.result, language: loc.language),
                            systemImage: ScreenTimeRedemptionResultCopy.icon(for: latestRedemptionResult.result)
                        )
                        .accessibilityIdentifier("reward-status-result-\(ScreenTimeRedemptionResultCopy.accessibilitySuffix(for: latestRedemptionResult.result))")
                        let message = ScreenTimeRedemptionResultCopy.message(
                            for: latestRedemptionResult.result,
                            minutes: latestRedemptionResult.minutes,
                            cost: latestRedemptionResult.cost,
                            language: loc.language
                        )
                        HStack(alignment: .top) {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            SpeakButton(text: message, language: loc.language)
                        }
                    }
                }

                if let commandReceipt = screenTimeController.latestDeviceCommandReceipt {
                    Section(loc.pick("屏幕时间更新", "Screen Time Update")) {
                        DeviceCommandReceiptRow(receipt: commandReceipt)
                            .accessibilityIdentifier("reward-status-device-command-receipt")
                    }
                }

                if let receipt = screenTimeController.latestReceipt {
                    Section(loc.pick("上次使用", "Last Play Time")) {
                        SessionReceiptRow(receipt: receipt)
                            .accessibilityIdentifier("reward-status-latest-receipt")
                    }
                }

                if !familyCloud.isChildDevice {
                    MobileCreditSettlementSummarySection(
                        report: creditSettlement.report,
                        focus: [.frozen, .refundSuggestion]
                    ) {
                        refreshSettlement()
                    }

                    Section {
                        NavigationLink {
                            MobileRewardStoreInventoryFulfillmentWorkbenchView(
                                initialRole: .guardian,
                                allowedRoles: [.guardian]
                            )
                        } label: {
                            Label(loc.pick("查看奖励记录", "Review Reward Records"), systemImage: "shippingbox")
                        }
                        .accessibilityIdentifier("reward-status-inventory-link")
                    } footer: {
                        Text(loc.pick("供家长查看兑换、退款和奖励记录。", "For parents to review exchanges, refunds, and reward records."))
                    }
                }
            }
            .navigationTitle(loc.pick("奖励", "Rewards"))
        }
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        .onAppear {
            reconcileSelectedApplicationToken()
        }
        #endif
        .task { refreshSettlement() }
        .onReceive(timer) { value in
            now = value
            #if canImport(FamilyControls) && canImport(ManagedSettings)
            reconcileSelectedApplicationToken()
            #endif
            if screenTimeController.tick(now: value) != nil {
                queueCompletedScreenTimeReceipts()
                // 会话刚到期：结算建议（冻结/释放）随之变化，刷新一次。
                refreshSettlement()
            }
        }
    }

    /// 基于最新离线重放报告与本地 store 重新生成结算建议。只读不写。
    private func refreshSettlement() {
        creditSettlement.refresh(
            offlineReport: offlineReplay.report,
            family: store,
            schoolFamily: schoolFamily,
            screenTime: screenTimeController
        )
    }

    private func startRewardSession(minutes: Int, cost: Int) {
        guard let nextState = exchangeTransactionState.beginning else { return }
        exchangeTransactionState = nextState
        Task { @MainActor in
            await Task.yield()
            await performStartRewardSession(minutes: minutes, cost: cost)
            try? await Task.sleep(for: RewardExchangeTransactionState.rapidTapProtectionDuration)
            exchangeTransactionState = exchangeTransactionState.completing
        }
    }

    @MainActor
    private func performStartRewardSession(minutes: Int, cost: Int) async {
        guard mayExecuteDeviceControl else {
            setupHint = loc.pick(
                "请在孩子手机完成兑换，家长手机不会执行锁定或解锁。",
                "Complete the exchange on the child's phone. The guardian phone will not lock or unlock."
            )
            return
        }
        let availability = exchangeAvailability(
            minutes: minutes,
            cost: cost,
            transactionState: .idle
        )
        guard availability == .available else {
            setupHint = RewardScreenTimeUI.detail(
                for: availability,
                language: loc.language,
                isPreReader: store.isPreReaderActive
            )
            return
        }
        let useCase = StartRewardSessionUseCase(
            store: store,
            screenTimeController: screenTimeController
        )
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let redeemedApplicationToken = selectedApplicationToken
        let redeemedAppUsageRef: String? = redeemedApplicationToken.flatMap { token -> String? in
            guard let tokenData = try? screenTimePOCManager.encodedApplicationToken(token) else {
                return nil
            }
            return ScreenTimeApplicationUsageAliasStore.appUsageRef(for: tokenData)
        }
        var result: StartRewardSessionResult
        if isUITestMode {
            result = useCase(minutes: minutes, now: now)
        } else {
            guard let selectedApplicationToken,
                  screenTimePOCManager.canStartSingleAppRewardWindow(
                      applicationToken: selectedApplicationToken,
                      shieldRequestID: nil,
                      at: now
                  ) else {
                setupHint = loc.pick("请先选择一个 App；未执行解锁时不会扣成长积分。", "Choose one app first; no Growth Points are charged without a real unlock.")
                return
            }
            guard let policy = familyCloud.screenTimePolicy(for: store.activeChildId) else {
                setupHint = loc.pick(
                    "孩子手机还没有确认家长端最新规则，积分不会扣除。请先刷新屏幕时间状态。",
                    "The child phone has not acknowledged the latest guardian policy. No points were charged. Refresh Screen Time status first."
                )
                return
            }
            let redemptionID = UUID()
            let transactionNow = now
            let receipt: FamilyScreenTimeRedemptionReceipt
            let reservation: FamilyScreenTimeRedemptionReservation
            do {
                receipt = try screenTimePOCManager.makeRedemptionReceipt(
                    redemptionID: redemptionID,
                    applicationToken: selectedApplicationToken,
                    points: cost,
                    minutes: minutes,
                    policy: policy,
                    now: transactionNow
                )
                reservation = try await familyCloud.reserveScreenTimeRedemption(receipt)
                guard reservation.state == .reserved else {
                    throw FamilyCloudClientError.server("screen_time_redemption_not_reserved")
                }
            } catch {
                setupHint = loc.pick(
                    "没有取得最新设备回执，兑换已停止，积分没有扣除。请刷新后再试。",
                    "A current device receipt was not available. The exchange stopped and no points were charged. Refresh and try again."
                )
                return
            }
            setupHint = nil
            result = useCase(
                minutes: minutes,
                now: transactionNow,
                concurrentExternalDeviceStart: { minutes, now in
                    try screenTimePOCManager.startSingleAppRewardSession(
                        applicationToken: selectedApplicationToken,
                        minutes: minutes,
                        now: now,
                        sessionID: redemptionID
                    )
                },
                concurrentExternalDeviceRelock: { sessionID in
                    screenTimePOCManager.relockRewardWindow(id: sessionID, referenceDate: transactionNow)
                },
                appUsageRef: redeemedAppUsageRef
            )
            if case .started = result {
                do {
                    let committed = try await familyCloud.commitScreenTimeRedemption(
                        reservationID: reservation.id,
                        receipt: receipt,
                        local: store
                    )
                    guard committed.state == .committed else {
                        throw FamilyCloudClientError.server("screen_time_redemption_commit_failed")
                    }
                } catch {
                    let settlement = try? await familyCloud.cancelScreenTimeRedemption(
                        reservationID: reservation.id,
                        local: store
                    )
                    if settlement?.state != .committed {
                        _ = screenTimePOCManager.relockRewardWindow(
                            id: redemptionID,
                            referenceDate: transactionNow
                        )
                        _ = screenTimeController.endConcurrentExternalUnlock(
                            sessionID: redemptionID,
                            now: transactionNow
                        )
                        if settlement == nil {
                            store.refundRewardMinutes(cost, for: store.activeChildId)
                        }
                        result = .deviceFailureRolledBack
                        setupHint = loc.pick(
                            "云端没有确认这次解锁，App 已重新上锁，积分已退回。",
                            "The cloud did not confirm this unlock. The app was relocked and the points were returned."
                        )
                    }
                }
            } else {
                _ = try? await familyCloud.cancelScreenTimeRedemption(
                    reservationID: reservation.id,
                    local: store
                )
            }
        }
        #else
        let result = useCase(minutes: minutes, now: now)
        #endif
        latestRedemptionResult = (result, minutes, cost)
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        if case .started = result {
            selectedApplicationToken = RewardScreenTimeUI.nextInactiveSelection(
                from: Array(screenTimePOCManager.selection.applicationTokens),
                excluding: redeemedApplicationToken,
                isActive: { screenTimePOCManager.rewardWindowEnd(for: $0, at: now) != nil }
            )
        }
        #endif
        refreshSettlement()
    }

    private func queueCompletedScreenTimeReceipt(_ receipt: RewardSessionReceipt?) {
        guard let receipt else { return }
        if familyCloud.queueScreenTimeAuthorizationReceipt(receipt) {
            screenTimeController.markActivityReceiptQueued(receipt.id)
        }
    }

    private func queueCompletedScreenTimeReceipts() {
        for receipt in screenTimeController.pendingActivityReceipts {
            queueCompletedScreenTimeReceipt(receipt)
        }
    }

    #if canImport(FamilyControls) && canImport(ManagedSettings)
    private func reconcileSelectedApplicationToken() {
        let currentTokens = screenTimePOCManager.selection.applicationTokens
        if let selectedApplicationToken,
           currentTokens.contains(selectedApplicationToken) {
            return
        }
        selectedApplicationToken = RewardScreenTimeUI.nextInactiveSelection(
            from: Array(currentTokens),
            excluding: nil,
            isActive: {
                screenTimePOCManager.rewardWindowEnd(for: $0, at: now) != nil
            }
        ) ?? currentTokens.first
    }
    #endif

    private var realDeviceReady: Bool {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        guard mayExecuteDeviceControl else { return false }
        if isUITestMode { return true }
        guard let selectedApplicationToken else { return false }
        return screenTimePOCManager.canStartSingleAppRewardWindow(
            applicationToken: selectedApplicationToken,
            shieldRequestID: nil,
            at: now
        )
        #else
        return mayExecuteDeviceControl
        #endif
    }

    private var statusTitle: String {
        switch status {
        case .active: return loc.pick("解锁中", "Unlocked")
        case .locked: return loc.pick("已锁定", "Locked")
        case .expired: return loc.pick("已到期", "Time's up")
        }
    }

    private func countdown(until end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private var sessionExpiredText: String {
        loc.pick(
            "会话已到期，娱乐时间重新锁定。",
            "The session ended, and fun time is locked again."
        )
    }

    private var statusIcon: String {
        switch status {
        case .active: return "lock.open.fill"
        case .locked: return "lock.fill"
        case .expired: return "clock.badge.xmark"
        }
    }

    private var remainingTimeText: String {
        loc.pick(
            "剩余 \(remainingSeconds / 60) 分 \(remainingSeconds % 60) 秒",
            "\(remainingSeconds / 60) min \(remainingSeconds % 60) sec left"
        )
    }

    private var balanceSpeakText: String {
        if store.isPreReaderActive {
            return loc.pick(
                "你有 \(GrowthCreditCopy.label(points: store.child.rewardBalanceMinutes))。",
                "You have \(GrowthCreditCopy.label(points: store.child.rewardBalanceMinutes, language: .english))."
            )
        }
        return loc.pick(
            "你现在有 \(GrowthCreditCopy.label(points: store.child.rewardBalanceMinutes))。",
            "You have \(GrowthCreditCopy.label(points: store.child.rewardBalanceMinutes, language: .english)) right now."
        )
    }

    private var sessionStatusSpeakText: String {
        switch status {
        case .active:
            if store.isPreReaderActive {
                return loc.pick("正在玩，\(remainingTimeText)。", "Playing now. \(remainingTimeText).")
            }
            return loc.pick(
                "现在是解锁中，\(remainingTimeText)。到期会自动重新锁定。",
                "It's unlocked now. \(remainingTimeText). It will lock again when time is up."
            )
        case .locked:
            if store.isPreReaderActive {
                return loc.pick("现在不能玩。可以用积分换时间。", "Play time is locked. You can use points for time.")
            }
            return loc.pick(
                "现在已锁定。你可以用成长积分兑换屏幕时间。",
                "It's locked now. You can trade Growth Points for screen time."
            )
        case .expired:
            return sessionExpiredText
        }
    }

}

/// 会话收据展示行：分钟数、结束原因与消耗/未用对账。仅本地数据，无隐私字段。
/// 既有调用方（RewardStatusView / RewardRedemptionView）不传语言，
/// 这里从环境 store 取当前孩子的界面语言，保持调用方不变。
struct SessionReceiptRow: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    let receipt: RewardSessionReceipt

    private var loc: ChildLocalizationContext { ChildLocalizationContext(language: childSurfaceLanguage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reasonLabel)
                .font(.subheadline.bold())
            Text(loc.pick(
                "屏幕时间 \(receipt.grantedMinutes) 分钟 · 已用 \(receipt.consumedMinutes) 分钟 · 未用 \(receipt.unusedMinutes) 分钟",
                "Screen time \(receipt.grantedMinutes) min · used \(receipt.consumedMinutes) min · unused \(receipt.unusedMinutes) min"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var reasonLabel: String {
        switch receipt.endReason {
        case .expired: return loc.pick("到期自动结束", "Ended when time was up")
        case .parentEnded: return loc.pick("家长提前结束", "A parent ended it early")
        }
    }
}

/// 设备命令回执展示行：命令发出即产生，结束会话收据稍后产生。
/// 语言同样从环境 store 取当前孩子的界面语言。
struct DeviceCommandReceiptRow: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    let receipt: ScreenTimeDeviceCommandReceipt

    private var loc: ChildLocalizationContext { ChildLocalizationContext(language: childSurfaceLanguage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: receipt.status == .succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(receipt.status == .succeeded ? Color.green : Color.orange)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var title: String {
        switch (receipt.kind, receipt.status) {
        case (.startUnlock, .succeeded): return loc.pick("屏幕时间已打开", "Screen time is on")
        case (.startUnlock, .failed): return loc.pick("屏幕时间未打开", "Screen time did not open")
        case (.automaticRelock, .succeeded): return loc.pick("到期后已重新锁定", "Locked again when time was up")
        case (.automaticRelock, .failed): return loc.pick("到期重锁失败", "Relock failed when time was up")
        case (.parentRelock, .succeeded): return loc.pick("家长已提前锁定", "A parent locked it early")
        case (.parentRelock, .failed): return loc.pick("提前锁定失败", "Early lock failed")
        }
    }

    private var detail: String {
        if receipt.status == .failed {
            return failureDetail
        }
        var parts: [String] = []
        if let requestedMinutes = receipt.requestedMinutes {
            parts.append(loc.pick("本次 \(requestedMinutes) 分钟", "\(requestedMinutes) minutes this time"))
        }
        if let plannedEndsAt = receipt.plannedEndsAt {
            parts.append(loc.pick(
                "计划 \(plannedEndsAt.formatted(date: .omitted, time: .shortened)) 结束",
                "ends at \(plannedEndsAt.formatted(date: .omitted, time: .shortened))"
            ))
        }
        return parts.isEmpty ? loc.pick("设备命令已完成", "Device command finished") : parts.joined(separator: " · ")
    }

    private var failureDetail: String {
        switch receipt.failureReason {
        case .alreadyActive:
            return loc.pick(
                "已有屏幕时间在进行；本次没有叠加，成长积分已保护。",
                "A screen time session is already running; no extra time was added and your points are protected."
            )
        case .nonPositiveMinutes:
            return loc.pick(
                "兑换分钟数无效；没有扣成长积分。",
                "The exchange minutes were invalid; no Growth Points were taken."
            )
        case .deviceCommandFailed:
            return loc.pick(
                "设备命令失败；成长积分已退回。",
                "The device command failed; your Growth Points were refunded."
            )
        case nil:
            return loc.pick(
                "设备命令失败；请家长检查授权。",
                "The device command failed; ask a parent to check the permission."
            )
        }
    }
}
