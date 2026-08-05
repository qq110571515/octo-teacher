import SwiftUI
#if canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
import ManagedSettings
#endif

enum RewardExchangeAvailability: Equatable {
    case available
    case transactionInFlight
    case insufficientPoints(required: Int, available: Int)
    case dailyLimit(remainingMinutes: Int)
    case schoolMode
    case unauthorized
    case appAlreadyActive
}

enum RewardExchangeTransactionState: Equatable {
    case idle
    case inFlight

    static let rapidTapProtectionDuration = Duration.milliseconds(350)

    var beginning: Self? {
        self == .idle ? .inFlight : nil
    }

    var completing: Self { .idle }
}

enum RewardScreenTimeFlow: Equatable {
    case schoolEmergency
    case exactApplication
    case exactCategory
    case impreciseTarget
    case setup

    static func resolve(
        isSchoolMode: Bool,
        hasPendingShieldAction: Bool,
        hasDirectShieldApplication: Bool,
        hasDirectShieldCategory: Bool,
        selectedAppIsAuthorizedForUnlock: Bool,
        isUITestMode: Bool
    ) -> Self {
        if isSchoolMode {
            return .schoolEmergency
        }
        if hasDirectShieldCategory {
            return .exactCategory
        }
        if hasPendingShieldAction && !hasDirectShieldApplication {
            return .impreciseTarget
        }
        if isUITestMode || hasDirectShieldApplication || selectedAppIsAuthorizedForUnlock {
            return .exactApplication
        }
        return .setup
    }
}

enum RewardScreenTimeUI {
    static let fixedExchangeMinutes = [15, 30, 45, 60]

    static func exchangeMinutes(customMinutes: Int) -> [Int] {
        let customOption = ScreenTimeUsageWindowSchedule.supports(minutes: customMinutes) && customMinutes <= 60
            ? [customMinutes]
            : []
        return Array(Set(fixedExchangeMinutes + customOption)).sorted()
    }

    static func activeShieldAction(
        _ action: PersistedShieldActionRequest?,
        consumedActionID: UUID?
    ) -> PersistedShieldActionRequest? {
        guard action?.id != consumedActionID else { return nil }
        return action
    }

    static func nextInactiveSelection<Option: Equatable>(
        from options: [Option],
        excluding redeemedOption: Option?,
        isActive: (Option) -> Bool
    ) -> Option? {
        options.first { option in
            (redeemedOption.map { option != $0 } ?? true) && !isActive(option)
        }
    }

    static func availability(
        dailyRequiredMinutes: Int,
        cost: Int,
        availablePoints: Int,
        dailyRemainingMinutes: Int,
        isSchoolMode: Bool,
        isAuthorized: Bool,
        selectedAppIsActive: Bool,
        transactionState: RewardExchangeTransactionState = .idle
    ) -> RewardExchangeAvailability {
        if transactionState == .inFlight { return .transactionInFlight }
        if isSchoolMode { return .schoolMode }
        if !isAuthorized { return .unauthorized }
        if selectedAppIsActive { return .appAlreadyActive }
        if dailyRequiredMinutes > dailyRemainingMinutes {
            return .dailyLimit(remainingMinutes: max(0, dailyRemainingMinutes))
        }
        if cost > availablePoints {
            return .insufficientPoints(required: cost, available: max(0, availablePoints))
        }
        return .available
    }

    static func title(
        for availability: RewardExchangeAvailability,
        language: AppInterfaceLanguage
    ) -> String {
        switch availability {
        case .available:
            return language.pick("可以兑换", "Ready")
        case .transactionInFlight:
            return language.pick("正在兑换", "Exchanging")
        case .insufficientPoints:
            return language.pick("积分不足", "Need more points")
        case .dailyLimit:
            return language.pick("每日上限", "Daily limit")
        case .schoolMode:
            return language.pick("学校模式", "School Mode")
        case .unauthorized:
            return language.pick("尚未授权", "Not authorized")
        case .appAlreadyActive:
            return language.pick("这个 App 在计时", "This app is timed")
        }
    }

    static func detail(
        for availability: RewardExchangeAvailability,
        language: AppInterfaceLanguage,
        isPreReader: Bool
    ) -> String {
        switch availability {
        case .available:
            return isPreReader
                ? language.pick("可以换。", "Ready to play.")
                : language.pick("积分够，今天也还有可用时间。", "You have enough points and time today.")
        case .transactionInFlight:
            return isPreReader
                ? language.pick("等一下。", "One moment.")
                : language.pick("正在完成这次兑换，请稍候。", "Finishing this exchange. Please wait.")
        case let .insufficientPoints(required, available):
            let missing = max(0, required - available)
            return isPreReader
                ? language.pick("积分不够。先做任务。", "Not enough points. Do a task first.")
                : language.pick("还差 \(missing) 成长积分，先完成任务。", "You need \(missing) more Growth Points. Finish a task first.")
        case let .dailyLimit(remainingMinutes):
            return isPreReader
                ? language.pick("今天不能再换了。", "No more play time today.")
                : language.pick("今天还可兑换 \(remainingMinutes) 分钟。", "You can trade for \(remainingMinutes) more minutes today.")
        case .schoolMode:
            return isPreReader
                ? language.pick("现在是上学时间。", "It is school time.")
                : language.pick("学校模式开启，放学后再兑换。", "School Mode is on. Try again after school.")
        case .unauthorized:
            return isPreReader
                ? language.pick("请大人先帮忙。", "Ask a grown-up for help.")
                : language.pick("请家长先授权并选择可以兑换的 App。", "Ask a parent to authorize Screen Time and choose allowed apps.")
        case .appAlreadyActive:
            return isPreReader
                ? language.pick("换一个 App。", "Pick another app.")
                : language.pick("这个 App 正在计时，请选择另一个 App。", "This app is already timed. Choose another app.")
        }
    }
}

private enum ParentScreenTimeUnlockDuration: String, CaseIterable {
    case oneHour
    case twoHours
    case allDay

    func title(language: AppInterfaceLanguage) -> String {
        switch self {
        case .oneHour: return language.pick("1 小时", "1 Hour")
        case .twoHours: return language.pick("2 小时", "2 Hours")
        case .allDay: return language.pick("今天", "All Day")
        }
    }

    func minutes(from now: Date, calendar: Calendar = .current) -> Int {
        switch self {
        case .oneHour: return 60
        case .twoHours: return 120
        case .allDay:
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(24 * 60 * 60)
            return min(24 * 60, max(1, Int(ceil(endOfDay.timeIntervalSince(now) / 60))))
        }
    }
}

/// 孩子端成长积分兑换入口，从 ChildHome 推入，统一扣成长积分、下发设备命令并展示回执。
/// 设备命令失败会由用例回滚成长积分。
struct RewardRedemptionView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(MockScreenTimeController.self) private var screenTimeController
    @Environment(ParentGate.self) private var parentGate
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @Environment(ScreenTimePOCManager.self) private var screenTimePOCManager
    #endif
    @State private var now = Date()
    @State private var latestRedemptionResult: (result: StartRewardSessionResult, minutes: Int, cost: Int)?
    @State private var emergencyHint: String?
    @State private var setupHint: String?
    @State private var parentPIN = ""
    @State private var parentUnlockDuration: ParentScreenTimeUnlockDuration = .oneHour
    @State private var pinFeedback: String?
    @State private var isEmergencyWorking = false
    @State private var exchangeTransactionState: RewardExchangeTransactionState = .idle
    @State private var consumedShieldActionID: UUID?
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @State private var selectedApplicationToken: ApplicationToken?
    @State private var selectedCategoryToken: ActivityCategoryToken?
    @State private var showsScreenTimeSetup = false
    #endif

    let pendingShieldAction: PersistedShieldActionRequest?
    let interfaceLanguageOverride: AppInterfaceLanguage?
    let onShieldActionCompleted: (() -> Void)?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var status: RewardSessionStatus { screenTimeController.sessionStatus }

    init(
        pendingShieldAction: PersistedShieldActionRequest? = nil,
        interfaceLanguageOverride: AppInterfaceLanguage? = nil,
        onShieldActionCompleted: (() -> Void)? = nil
    ) {
        self.pendingShieldAction = pendingShieldAction
        self.interfaceLanguageOverride = interfaceLanguageOverride
        self.onShieldActionCompleted = onShieldActionCompleted
    }

    private var isUITestMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-OctoTeacherUITest") }
        #else
        false
        #endif
    }

    private var loc: ChildLocalizationContext {
        let currentLanguage = interfaceLanguageOverride ?? childSurfaceLanguage
        let rawValue = ScreenTimeSharedContract.hostInterfaceLanguageRawValue(
            currentChildLanguage: currentLanguage.rawValue,
            request: pendingShieldAction,
            fallback: currentLanguage.rawValue
        )
        return ChildLocalizationContext(
            language: AppInterfaceLanguage(rawValue: rawValue) ?? currentLanguage
        )
    }

    private var mayExecuteDeviceControl: Bool {
        ScreenTimeSharedContract.mayExecuteDeviceControl(
            isChildDevice: familyCloud.isChildDevice,
            isUITestMode: isUITestMode
        )
    }

    private var options: [Int] {
        RewardScreenTimeUI.exchangeMinutes(
            customMinutes: store.policy(for: store.activeChildId).resolvedScreenExchangeMinutes
        )
    }

    private var dailyRemainingMinutes: Int {
        max(0, store.child.dailyLimitMinutes - screenTimeController.grantedMinutes(on: now))
    }

    private var selectedAppWindowEndsAt: Date? {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        if let selectedApplicationToken {
            return screenTimePOCManager.rewardWindowEnd(for: selectedApplicationToken, at: now)
        }
        if let selectedCategoryToken {
            return screenTimePOCManager.rewardWindowEnd(for: selectedCategoryToken, at: now)
        }
        return nil
        #else
        return screenTimeController.unlockEndsAt
        #endif
    }

    private var selectedAppHasActiveWindow: Bool {
        selectedAppWindowEndsAt != nil
    }

    private func countdown(until end: Date?) -> String {
        let seconds = max(0, Int(end?.timeIntervalSince(now) ?? 0))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func timerAccessibilityText(until end: Date?) -> String {
        let seconds = max(0, Int(end?.timeIntervalSince(now) ?? 0))
        return loc.pick(
            "还剩 \(seconds / 60) 分 \(seconds % 60) 秒",
            "\(seconds / 60) minutes and \(seconds % 60) seconds left"
        )
    }

    private func exchangeAvailability(
        minutes: Int,
        cost: Int,
        transactionState: RewardExchangeTransactionState? = nil
    ) -> RewardExchangeAvailability {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let schoolMode = isSchoolShieldRequest
        let isAuthorized = realDeviceExchangeReady
        #else
        let schoolMode = false
        let isAuthorized = mayExecuteDeviceControl
        #endif
        let dailyRequiredMinutes = screenTimeController.additionalGrantedMinutes(
            for: minutes,
            startingAt: now
        )
        return RewardScreenTimeUI.availability(
            dailyRequiredMinutes: dailyRequiredMinutes,
            cost: cost,
            availablePoints: store.creditBalance.availableMinutes,
            dailyRemainingMinutes: dailyRemainingMinutes,
            isSchoolMode: schoolMode,
            isAuthorized: isAuthorized,
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

    private var exchangeSummaryColor: Color {
        switch exchangeSummaryAvailability {
        case .available:
            return .green
        case .transactionInFlight, .appAlreadyActive:
            return .blue
        case .insufficientPoints, .dailyLimit, .schoolMode:
            return .orange
        case .unauthorized:
            return .red
        }
    }

    private var exchangeSummarySystemImage: String {
        switch exchangeSummaryAvailability {
        case .available:
            return "checkmark.circle.fill"
        case .transactionInFlight:
            return "arrow.triangle.2.circlepath"
        case .insufficientPoints:
            return "leaf.fill"
        case .dailyLimit:
            return "clock.badge.exclamationmark"
        case .schoolMode:
            return "graduationcap.fill"
        case .unauthorized:
            return "lock.trianglebadge.exclamationmark.fill"
        case .appAlreadyActive:
            return "timer"
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("🌱 \(GrowthCreditCopy.label(points: store.creditBalance.availableMinutes, language: loc.language))")
                        .font(.system(.title, design: .rounded).bold())
                        .monospacedDigit()
                        .accessibilityIdentifier("reward-redemption-balance")
                    Spacer()
                    SpeakButton(text: loc.pick(
                        store.isPreReaderActive
                            ? "你有 \(GrowthCreditCopy.label(points: store.creditBalance.availableMinutes))。"
                            : "你现在有 \(GrowthCreditCopy.label(points: store.creditBalance.availableMinutes))。",
                        store.isPreReaderActive
                            ? "You have \(GrowthCreditCopy.label(points: store.creditBalance.availableMinutes, language: .english))."
                            : "You have \(GrowthCreditCopy.label(points: store.creditBalance.availableMinutes, language: .english)) right now."
                    ), language: loc.language)
                }
                Text(loc.pick(
                    "\(store.policy(for: store.activeChildId).screenRateLabel(for: loc.language))",
                    "\(store.policy(for: store.activeChildId).screenRateLabel(for: loc.language))"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(loc.pick("我的成长积分", "My Growth Points"))
            }

            if !mayExecuteDeviceControl {
                Section {
                    Label(
                        loc.pick("这是家长预览；屏幕时间只能在孩子手机上兑换。", "This is a parent preview. Screen Time can only be exchanged on the child's phone."),
                        systemImage: "iphone.and.arrow.forward"
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("reward-redemption-guardian-preview")
                }
            }

            if mayExecuteDeviceControl {
                if status == .active {
                    activeAppTimersSection
                }

                #if canImport(FamilyControls) && canImport(ManagedSettings)
                switch screenTimeFlow {
                case .schoolEmergency:
                    schoolShieldActionSection
                    parentPINUnlockSection
                case .impreciseTarget:
                    impreciseShieldTargetSection
                case .exactApplication:
                    applicationSelectionSection
                    if allAvailableApplicationsAreActive {
                        allAvailableApplicationsActiveSection
                    } else {
                        screenTimeExchangeSection
                        if activePendingShieldAction != nil {
                            parentPINUnlockSection
                        }
                    }
                case .exactCategory:
                    categorySelectionSection
                    screenTimeExchangeSection
                    parentPINUnlockSection
                case .setup:
                    Section {
                        Label(
                            screenTimeSetupStatusTitle,
                            systemImage: "person.badge.key.fill"
                        )
                        Button {
                            showsScreenTimeSetup = true
                        } label: {
                            Label(
                                screenTimeSetupActionTitle,
                                systemImage: "lock.shield.fill"
                            )
                        }
                        .accessibilityIdentifier("reward-redemption-open-screen-time-setup")
                    } header: {
                        Text(loc.pick("屏幕时间", "Screen Time"))
                    } footer: {
                        Text(RewardScreenTimeUI.detail(
                            for: .unauthorized,
                            language: loc.language,
                            isPreReader: store.isPreReaderActive
                        ))
                    }
                }
                #endif
            }

            if let latestRedemptionResult {
                Section {
                    Label(
                        ScreenTimeRedemptionResultCopy.title(for: latestRedemptionResult.result, language: loc.language),
                        systemImage: ScreenTimeRedemptionResultCopy.icon(for: latestRedemptionResult.result)
                    )
                    .accessibilityIdentifier("reward-redemption-result-\(ScreenTimeRedemptionResultCopy.accessibilitySuffix(for: latestRedemptionResult.result))")

                    let message = ScreenTimeRedemptionResultCopy.message(
                        for: latestRedemptionResult.result,
                        minutes: latestRedemptionResult.minutes,
                        cost: latestRedemptionResult.cost,
                        language: loc.language
                    )
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SpeakButton(text: message, language: loc.language)
                }
            }
        }
        .navigationTitle(loc.pick("玩一会儿", "Play Time"))
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        .sheet(isPresented: $showsScreenTimeSetup) {
            ChildScreenTimeLocalSetupView(
                language: loc.language,
                autoPresentPickerAfterParentUnlock: screenTimeFlow == .impreciseTarget
            )
        }
        .onAppear {
            selectShieldApplicationOrFirst()
        }
        .onChange(of: screenTimePOCManager.selectionCounts) { _, _ in
            selectShieldApplicationOrFirst()
        }
        .onChange(of: pendingShieldAction?.id) { oldID, newID in
            guard oldID != newID, let newID else { return }
            if consumedShieldActionID != newID {
                consumedShieldActionID = nil
            }
            latestRedemptionResult = nil
            pinFeedback = nil
            setupHint = nil
            selectShieldApplicationOrFirst()
        }
        #endif
        .onReceive(timer) { value in
            now = value
            if screenTimeController.tick(now: value) != nil {
                queueCompletedScreenTimeReceipts()
            }
        }
    }

    @ViewBuilder
    private var activeAppTimersSection: some View {
        Section {
            Label(statusTitle, systemImage: statusIcon)
                .accessibilityIdentifier("reward-redemption-status-\(status.rawValue)")

            #if canImport(FamilyControls) && canImport(ManagedSettings)
            if activeApplicationTokens.isEmpty {
                genericActiveTimerRow
            } else {
                ForEach(activeApplicationTokens, id: \.self) { token in
                    HStack(spacing: 12) {
                        Label(token)
                        Spacer()
                        Text(countdown(until: screenTimePOCManager.rewardWindowEnd(for: token, at: now)))
                            .font(.headline.monospacedDigit())
                            .accessibilityLabel(timerAccessibilityText(
                                until: screenTimePOCManager.rewardWindowEnd(for: token, at: now)
                            ))
                        Button(role: .destructive) {
                            endRewardSession(for: token)
                        } label: {
                            Image(systemName: "stop.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(loc.pick("结束这个 App", "End this app"))
                        .accessibilityIdentifier("reward-redemption-end-session")
                    }
                }
            }
            #else
            genericActiveTimerRow
            #endif
        } header: {
            HStack {
                Text(loc.pick("App 倒计时", "App Timers"))
                Spacer()
                SpeakButton(
                    text: loc.pick("每个 App 都有自己的倒计时。", "Each app has its own timer."),
                    language: loc.language
                )
            }
        } footer: {
            Text(store.isPreReaderActive
                ? loc.pick("还想玩？选另一个 App。", "Want more? Pick another app.")
                : loc.pick("可以选择另一个 App 再兑换一次。", "You can choose another app and trade again."))
        }
    }

    private var genericActiveTimerRow: some View {
        HStack {
            Text(loc.pick(
                "还剩 \(countdown(until: screenTimeController.unlockEndsAt))",
                "\(countdown(until: screenTimeController.unlockEndsAt)) left"
            ))
                .font(.headline.monospacedDigit())
                .accessibilityIdentifier("reward-redemption-remaining-time")
            Spacer()
            Button(role: .destructive) {
                endSelectedRewardSession()
            } label: {
                Image(systemName: "stop.circle.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(loc.pick("现在结束", "End now"))
            .accessibilityIdentifier("reward-redemption-end-session")
        }
    }

    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @ViewBuilder
    private var applicationSelectionSection: some View {
        Section {
            ForEach(availableApplicationTokens, id: \.self) { token in
                let endsAt = screenTimePOCManager.rewardWindowEnd(for: token, at: now)
                Button {
                    selectedApplicationToken = token
                } label: {
                    HStack(spacing: 12) {
                        Label(token)
                        Spacer()
                        if let endsAt {
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
                .accessibilityHint(endsAt == nil
                    ? loc.pick("选择这个 App", "Select this app")
                    : timerAccessibilityText(until: endsAt))
                .accessibilityIdentifier("reward-redemption-app-choice")
            }
        } header: {
            HStack {
                Text(loc.pick("选择 App", "Choose an App"))
                Spacer()
                SpeakButton(
                    text: loc.pick("选一个 App。正在计时的 App 旁边会显示剩余时间。", "Choose an app. Timed apps show their time left."),
                    language: loc.language
                )
            }
        }
    }

    @ViewBuilder
    private var categorySelectionSection: some View {
        Section {
            Label(
                loc.pick("刚才点到的受控分类", "The Managed Category You Tapped"),
                systemImage: "square.grid.3x3.fill"
            )
            Text(loc.pick(
                "Apple 为分类锁定隐藏具体 App 身份；本次时长只临时开放这个分类，其他受控分类继续上锁。",
                "Apple hides the app identity for category shields. This window opens only this category; other managed categories stay locked."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text(loc.pick("兑换范围", "Exchange Scope"))
        }
    }

    @ViewBuilder
    private var allAvailableApplicationsActiveSection: some View {
        Section {
            Label(
                loc.pick("清单里的 App 都在计时", "Every listed app is already timed"),
                systemImage: "timer.circle.fill"
            )
            Text(store.isPreReaderActive
                ? loc.pick(
                    "想玩别的？返回点那个被锁的 App。若它是新安装的，请让家长在自己的手机刷新分类规则。",
                    "Want another app? Go back and tap it. If it was newly installed, ask a parent to refresh the category policy on their own phone."
                )
                : loc.pick(
                    "当前精确清单里的 App 都已解锁计时。要打开另一个 App，请返回点它；若 Apple 只返回分类，请家长在自己的手机重新发布该分类。",
                    "Every app in the exact list is already timed. To open another app, tap it. If Apple returns only its category, the guardian should republish that category from their own phone."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                showsScreenTimeSetup = true
            } label: {
                Label(
                    loc.pick("家长补充 App 清单", "Parent Update App List"),
                    systemImage: "arrow.clockwise"
                )
            }
        } header: {
            Text(loc.pick("继续使用", "Use Another App"))
        }
    }
    #endif

    @ViewBuilder
    private var screenTimeExchangeSection: some View {
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
            .accessibilityIdentifier("reward-redemption-daily-remaining")

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: exchangeSummarySystemImage)
                    .font(.title3)
                    .foregroundStyle(exchangeSummaryColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(RewardScreenTimeUI.title(for: exchangeSummaryAvailability, language: loc.language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(RewardScreenTimeUI.detail(
                        for: exchangeSummaryAvailability,
                        language: loc.language,
                        isPreReader: store.isPreReaderActive
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                SpeakButton(
                    text: RewardScreenTimeUI.detail(
                        for: exchangeSummaryAvailability,
                        language: loc.language,
                        isPreReader: store.isPreReaderActive
                    ),
                    language: loc.language
                )
            }
            .padding(10)
            .background(
                exchangeSummaryColor.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("reward-redemption-availability-summary")

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
                    .accessibilityIdentifier("reward-redemption-use-\(minutes)")
                }
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
        } header: {
            HStack {
                Text(loc.pick("玩多久？", "How Long?"))
                Spacer()
                SpeakButton(
                    text: store.isPreReaderActive
                        ? loc.pick("选时间。", "Pick a time.")
                        : loc.pick("选择你想玩的时间。每次最多 60 分钟。", "Choose how long you want to play, up to 60 minutes each time."),
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
    }

    @ViewBuilder
    private var parentPINUnlockSection: some View {
        Section {
            if parentGate.hasPin {
                if !isSchoolShieldRequest {
                    Picker(loc.pick("解锁时长", "Unlock Duration"), selection: $parentUnlockDuration) {
                        ForEach(ParentScreenTimeUnlockDuration.allCases, id: \.self) { duration in
                            Text(duration.title(language: loc.language)).tag(duration)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                SecureField(loc.pick("输入家长 PIN", "Enter Parent PIN"), text: $parentPIN)
                    .keyboardType(.numberPad)
                Button {
                    unlockWithParentPIN()
                } label: {
                    Label(
                        isSchoolShieldRequest
                            ? loc.pick("家长紧急解锁 30 分钟", "Parent Emergency Unlock for 30 Minutes")
                            : loc.pick("家长直接解锁", "Parent Unlock"),
                        systemImage: "person.badge.key.fill"
                    )
                }
                .disabled(parentPIN.isEmpty || (isSchoolShieldRequest ? status == .active : selectedAppHasActiveWindow))
            } else {
                Text(store.isPreReaderActive
                    ? loc.pick("请大人先设置 PIN。", "Ask a grown-up to set a PIN.")
                    : loc.pick("请家长先在家长入口设置 PIN。", "Ask a parent to set a PIN in the Parent area."))
                .foregroundStyle(.secondary)
            }
            if let pinFeedback {
                HStack(alignment: .top) {
                    Text(pinFeedback)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    SpeakButton(text: pinFeedback, language: loc.language)
                }
            }
        } header: {
            Text(loc.pick("请家长帮忙", "Parent Help"))
        } footer: {
            Text(isSchoolShieldRequest
                ? loc.pick("不扣分；30 分钟后恢复学校规则。", "No points used. School controls return after 30 minutes.")
                : loc.pick("不扣分；到期自动恢复。", "No points used. Controls return automatically."))
        }
    }

    @ViewBuilder
    private var impreciseShieldTargetSection: some View {
        Section {
            Label(
                loc.pick("这个项目暂不支持积分兑换", "This Item Cannot Use Growth Points"),
                systemImage: "exclamationmark.shield.fill"
            )
            Text(store.isPreReaderActive
                ? loc.pick("请让家长帮忙。", "Ask a grown-up for help.")
                : loc.pick(
                    "Apple 没有返回可兑换的 App 或分类令牌，通常是受控网站。本次不会扣成长积分。",
                    "Apple did not return an exchangeable app or category token, usually because this is a managed website. No Growth Points will be used."
                ))
            .font(.caption)
            .foregroundStyle(.secondary)
            Button {
                showsScreenTimeSetup = true
            } label: {
                Label(
                    loc.pick("检查设备控制", "Check Device Controls"),
                    systemImage: "lock.shield"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } header: {
            Text(loc.pick("无法兑换", "Unavailable"))
        }
    }

    @ViewBuilder
    private var schoolShieldActionSection: some View {
        Section {
            Label(
                loc.pick("现在是学校模式，不能用成长积分解锁。", "School Mode is active. Growth Points cannot unlock apps now."),
                systemImage: "graduationcap.fill"
            )
            schoolEmergencyAction
            if let emergencyHint {
                HStack(alignment: .top) {
                    Text(emergencyHint).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    SpeakButton(text: emergencyHint, language: loc.language)
                }
            }
        } header: {
            Text(loc.pick("学校模式", "School Mode"))
        } footer: {
            Text(store.isPreReaderActive
                ? loc.pick("紧急时请大人帮忙。", "Ask a grown-up for emergency help.")
                : loc.pick("家长批准的紧急使用会在 30 分钟后结束。", "Parent-approved emergency access ends after 30 minutes."))
        }
    }

    @ViewBuilder
    private var schoolEmergencyAction: some View {
        let emergency = familyCloud.screenTimeEmergency(for: store.activeChildId)
        if isEmergencyWorking {
            HStack {
                ProgressView()
                Text(loc.pick("正在同步家长与孩子手机…", "Syncing parent and child phones…"))
            }
        } else {
            switch emergency?.status ?? .idle {
            case .idle, .completed, .expired:
                Button {
                    submitEmergencyUnlockRequest()
                } label: {
                    Label(
                        loc.pick("向家长申请紧急解锁", "Ask a Parent for Emergency Access"),
                        systemImage: "bell.badge.fill"
                    )
                }
                .accessibilityIdentifier("emergency-unlock-request")
            case .requested:
                Label(loc.pick("已发给家长，等待批准", "Sent to a parent for approval"), systemImage: "hourglass")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("emergency-unlock-requested")
            case .approved:
                Button {
                    startApprovedSchoolEmergency(emergency)
                } label: {
                    Label(
                        loc.pick(
                            "使用批准：打开全部 App \(emergency?.minutes ?? 30) 分钟",
                            "Use Approval: Open All Apps for \(emergency?.minutes ?? 30) Minutes"
                        ),
                        systemImage: "lock.open.fill"
                    )
                }
                .accessibilityIdentifier("emergency-unlock-start-approved")
            case .active:
                Label(loc.pick("紧急解锁使用中，到期自动恢复学校锁定", "Emergency access is active. School Mode will relock automatically."), systemImage: "timer")
                    .foregroundStyle(.green)
            case .denied:
                Label(loc.pick("家长没有批准这次申请", "A parent declined this request"), systemImage: "xmark.circle")
                    .foregroundStyle(.red)
                Button(loc.pick("重新申请", "Request Again")) {
                    submitEmergencyUnlockRequest()
                }
            }
        }
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
        let redeemedCategoryToken = selectedCategoryToken
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
            let shieldRequestID = activePendingShieldAction?.id
            let applicationIsReady = selectedApplicationToken.map {
                screenTimePOCManager.canStartSingleAppRewardWindow(
                    applicationToken: $0,
                    shieldRequestID: shieldRequestID,
                    at: now
                )
            } ?? false
            let categoryIsReady = selectedCategoryToken.map {
                screenTimePOCManager.canStartCategoryRewardWindow(
                    categoryToken: $0,
                    shieldRequestID: shieldRequestID,
                    at: now
                )
            } ?? false
            guard applicationIsReady || categoryIsReady else {
                setupHint = loc.pick("无法确认刚才点到的受控范围；没有真正解锁时不会扣成长积分。", "The tapped managed scope could not be verified. No Growth Points are charged without a real unlock.")
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
                if let selectedApplicationToken, applicationIsReady {
                    receipt = try screenTimePOCManager.makeRedemptionReceipt(
                        redemptionID: redemptionID,
                        applicationToken: selectedApplicationToken,
                        points: cost,
                        minutes: minutes,
                        policy: policy,
                        now: transactionNow
                    )
                } else if let selectedCategoryToken, categoryIsReady {
                    receipt = try screenTimePOCManager.makeRedemptionReceipt(
                        redemptionID: redemptionID,
                        categoryToken: selectedCategoryToken,
                        points: cost,
                        minutes: minutes,
                        policy: policy,
                        now: transactionNow
                    )
                } else {
                    throw UnlockError.deviceCommandFailed
                }
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
                    if let selectedApplicationToken, applicationIsReady {
                        return try screenTimePOCManager.startSingleAppRewardSession(
                            applicationToken: selectedApplicationToken,
                            minutes: minutes,
                            now: now,
                            shieldRequestID: shieldRequestID,
                            sessionID: redemptionID
                        )
                    }
                    guard let selectedCategoryToken,
                          categoryIsReady,
                          let shieldRequestID else {
                        throw UnlockError.deviceCommandFailed
                    }
                    return try screenTimePOCManager.startCategoryRewardSession(
                        categoryToken: selectedCategoryToken,
                        minutes: minutes,
                        now: now,
                        shieldRequestID: shieldRequestID,
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
                    consumePendingShieldActionAfterSuccessfulUnlock()
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
            if redeemedCategoryToken != nil {
                selectedCategoryToken = nil
            } else {
                selectNextInactiveApplication(excluding: redeemedApplicationToken)
            }
        }
        #endif
    }

    private func endSelectedRewardSession() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        if let selectedApplicationToken,
           let removed = screenTimePOCManager.relockRewardWindow(
               for: selectedApplicationToken,
               referenceDate: now
           ) {
            queueCompletedScreenTimeReceipt(screenTimeController.endConcurrentExternalUnlock(
                sessionID: removed.resolvedID,
                now: now
            ))
        } else if let selectedCategoryToken,
                  let removed = screenTimePOCManager.relockRewardWindow(
                      for: selectedCategoryToken,
                      referenceDate: now
                  ) {
            queueCompletedScreenTimeReceipt(screenTimeController.endConcurrentExternalUnlock(
                sessionID: removed.resolvedID,
                now: now
            ))
        } else if isUITestMode {
            screenTimeController.reshieldNow()
        }
        #else
        screenTimeController.reshieldNow()
        #endif
    }

    private var realDeviceExchangeReady: Bool {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        return mayExecuteDeviceControl && (
            isUITestMode || (
                selectedApplicationToken != nil &&
                    selectedAppIsAuthorizedForUnlock
            ) || (
                selectedCategoryToken != nil &&
                    selectedCategoryIsAuthorizedForUnlock
            )
        )
        #else
        return mayExecuteDeviceControl
        #endif
    }

    #if canImport(FamilyControls) && canImport(ManagedSettings)
    private var activePendingShieldAction: PersistedShieldActionRequest? {
        RewardScreenTimeUI.activeShieldAction(
            pendingShieldAction,
            consumedActionID: consumedShieldActionID
        )
    }

    private var screenTimeSetupStatusTitle: String {
        if screenTimePOCManager.selectionCounts.applications > 0 {
            return loc.pick("App 清单已保留，请家长批准设备控制", "App List Saved — Parent Approval Needed")
        }
        if screenTimePOCManager.selectionCounts.hasSelection {
            return loc.pick("正在等待家长端刷新精准 App 清单", "Waiting for Guardian App List Refresh")
        }
        return loc.pick("正在等待家长端发布 App 规则", "Waiting for the Guardian to Publish an App Policy")
    }

    private var screenTimeSetupActionTitle: String {
        if screenTimePOCManager.selectionCounts.applications > 0 {
            return loc.pick("家长重新授权", "Parent Reauthorize")
        }
        if screenTimePOCManager.selectionCounts.hasSelection {
            return loc.pick("检查家长规则同步", "Check Guardian Policy Sync")
        }
        return loc.pick("检查设备授权", "Check Device Authorization")
    }
    #endif

    #if canImport(FamilyControls) && canImport(ManagedSettings)
    private var hasDirectShieldApplication: Bool {
        guard let request = activePendingShieldAction else { return false }
        return screenTimePOCManager.applicationToken(from: request) != nil
    }

    private var hasDirectShieldCategory: Bool {
        guard let request = activePendingShieldAction else { return false }
        return screenTimePOCManager.categoryToken(from: request) != nil
    }

    private var selectedAppIsAuthorizedForUnlock: Bool {
        screenTimePOCManager.canStartSingleAppRewardWindow(
            applicationToken: selectedApplicationToken,
            shieldRequestID: activePendingShieldAction?.id,
            at: now
        )
    }

    private var selectedCategoryIsAuthorizedForUnlock: Bool {
        screenTimePOCManager.canStartCategoryRewardWindow(
            categoryToken: selectedCategoryToken,
            shieldRequestID: activePendingShieldAction?.id,
            at: now
        )
    }

    private var isSchoolShieldRequest: Bool {
        activePendingShieldAction?.intent == .requestSchoolEmergency ||
            screenTimePOCManager.schoolModeIsActive ||
            usesSchoolEmergencyUITestFixture
    }

    private var screenTimeFlow: RewardScreenTimeFlow {
        RewardScreenTimeFlow.resolve(
            isSchoolMode: isSchoolShieldRequest,
            hasPendingShieldAction: activePendingShieldAction != nil,
            hasDirectShieldApplication: hasDirectShieldApplication,
            hasDirectShieldCategory: hasDirectShieldCategory,
            selectedAppIsAuthorizedForUnlock: selectedAppIsAuthorizedForUnlock,
            isUITestMode: isUITestMode
        )
    }

    private var availableApplicationTokens: [ApplicationToken] {
        if let activePendingShieldAction,
           let token = screenTimePOCManager.applicationToken(from: activePendingShieldAction) {
            return [token]
        }
        return Array(screenTimePOCManager.selection.applicationTokens)
    }

    private var activeApplicationTokens: [ApplicationToken] {
        availableApplicationTokens.filter {
            screenTimePOCManager.rewardWindowEnd(for: $0, at: now) != nil
        }
    }

    private var allAvailableApplicationsAreActive: Bool {
        !availableApplicationTokens.isEmpty &&
            availableApplicationTokens.allSatisfy {
                screenTimePOCManager.rewardWindowEnd(for: $0, at: now) != nil
            }
    }

    private var usesSchoolEmergencyUITestFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-OctoTeacherUITestSchoolEmergencyFlow")
        #else
        false
        #endif
    }

    private func selectShieldApplicationOrFirst() {
        if let activePendingShieldAction,
           let token = screenTimePOCManager.applicationToken(from: activePendingShieldAction) {
            selectedApplicationToken = token
            selectedCategoryToken = nil
            return
        }
        if let activePendingShieldAction,
           let token = screenTimePOCManager.categoryToken(from: activePendingShieldAction) {
            selectedApplicationToken = nil
            selectedCategoryToken = token
            return
        }
        if activePendingShieldAction != nil {
            selectedApplicationToken = nil
            selectedCategoryToken = nil
            return
        }
        selectedCategoryToken = nil
        if let selectedApplicationToken,
           screenTimePOCManager.selection.applicationTokens.contains(selectedApplicationToken) {
            return
        }
        selectedApplicationToken = screenTimePOCManager.selection.applicationTokens.first
    }

    private func selectNextInactiveApplication(excluding redeemedToken: ApplicationToken?) {
        selectedApplicationToken = RewardScreenTimeUI.nextInactiveSelection(
            from: Array(screenTimePOCManager.selection.applicationTokens),
            excluding: redeemedToken,
            isActive: { screenTimePOCManager.rewardWindowEnd(for: $0, at: now) != nil }
        )
    }

    @discardableResult
    private func consumePendingShieldActionAfterSuccessfulUnlock() -> Bool {
        guard let action = activePendingShieldAction else { return false }
        screenTimePOCManager.clearPendingShieldAction(id: action.id)
        consumedShieldActionID = action.id
        onShieldActionCompleted?()
        return true
    }

    private func endRewardSession(for token: ApplicationToken) {
        guard let removed = screenTimePOCManager.relockRewardWindow(
            for: token,
            referenceDate: now
        ) else { return }
        queueCompletedScreenTimeReceipt(screenTimeController.endConcurrentExternalUnlock(
            sessionID: removed.resolvedID,
            now: now
        ))
        if selectedApplicationToken == token {
            selectNextInactiveApplication(excluding: token)
        }
    }

    private func unlockWithParentPIN() {
        guard parentGate.unlock(with: parentPIN) else {
            pinFeedback = loc.pick("PIN 不正确。", "Incorrect PIN.")
            return
        }
        do {
            let unlockMinutes: Int
            if isSchoolShieldRequest {
                unlockMinutes = 30
                let sessionID = UUID()
                let endsAt = try screenTimePOCManager.startAllAppsEmergencyWindow(
                    minutes: unlockMinutes,
                    now: now,
                    sourceLabel: "local parent PIN school emergency"
                )
                _ = try screenTimeController.adoptExternalUnlock(
                    sessionID: sessionID,
                    minutes: unlockMinutes,
                    now: now,
                    endsAt: endsAt,
                    authority: .schoolEmergency
                )
            } else {
                unlockMinutes = parentUnlockDuration.minutes(from: now)
                let externalSession: ScreenTimeExternalSession
                let appUsageRef: String?
                if let selectedApplicationToken {
                    externalSession = try screenTimePOCManager.startSingleAppRewardSession(
                        applicationToken: selectedApplicationToken,
                        minutes: unlockMinutes,
                        now: now,
                        sourceLabel: "local parent PIN unlock",
                        shieldRequestID: activePendingShieldAction?.id,
                        allowDuringSchoolMode: false,
                        authority: .parentPIN
                    )
                    appUsageRef = (try? screenTimePOCManager.encodedApplicationToken(
                        selectedApplicationToken
                    )).flatMap {
                        ScreenTimeApplicationUsageAliasStore.appUsageRef(for: $0)
                    }
                } else if let selectedCategoryToken,
                          let requestID = activePendingShieldAction?.id {
                    externalSession = try screenTimePOCManager.startCategoryRewardSession(
                        categoryToken: selectedCategoryToken,
                        minutes: unlockMinutes,
                        now: now,
                        sourceLabel: "local parent PIN category unlock",
                        shieldRequestID: requestID,
                        authority: .parentPIN
                    )
                    appUsageRef = nil
                } else {
                    pinFeedback = loc.pick("无法识别刚才点到的受控范围。", "The tapped managed scope could not be identified.")
                    return
                }
                do {
                    _ = try screenTimeController.adoptConcurrentExternalUnlock(
                        sessionID: externalSession.id,
                        minutes: unlockMinutes,
                        now: now,
                        endsAt: externalSession.endsAt,
                        authority: .parentPIN,
                        appUsageRef: appUsageRef
                    )
                } catch {
                    screenTimePOCManager.relockRewardWindow(id: externalSession.id, referenceDate: now)
                    throw error
                }
            }
            let unlockedApplicationToken = isSchoolShieldRequest ? nil : selectedApplicationToken
            parentPIN = ""
            consumePendingShieldActionAfterSuccessfulUnlock()
            if selectedCategoryToken != nil {
                selectedCategoryToken = nil
            } else {
                selectNextInactiveApplication(excluding: unlockedApplicationToken)
            }
            pinFeedback = loc.pick(
                "已解锁 \(unlockMinutes) 分钟，到期自动恢复。",
                "Unlocked for \(unlockMinutes) minutes. Controls return automatically."
            )
        } catch {
            pinFeedback = screenTimeFailureMessage(fallbackError: error)
        }
    }

    private func screenTimeFailureMessage(fallbackError: Error) -> String {
        let errorCode = ScreenTimeOperationAuditLedger.latest(
            requestID: pendingShieldAction?.id
        )?.errorCode
        switch errorCode {
        case "authorization_not_approved":
            return loc.pick("这台孩子手机还没有完成屏幕使用时间授权。", "Screen Time permission is not ready on this child device.")
        case "request_expired", "invalid_target_receipt":
            return loc.pick("刚才点的 App 请求已经失效，请返回后再点一次。", "That app request expired. Go back and tap the locked app again.")
        case "school_mode_active", "school_mode_changed":
            return loc.pick("学校模式正在生效，只能向家长申请紧急使用。", "School Mode is active. Ask a parent for emergency access.")
        case "already_active":
            return loc.pick("这个 App 已经在使用时间内，无需重复解锁。", "This app already has active time.")
        case "shield_verification_failed", "school_store_not_clear":
            return loc.pick("Apple 没有确认解除限制，成长积分不会被扣除，请重试。", "Apple did not confirm the unlock. No Growth Points were charged. Try again.")
        case "shared_lock_unavailable":
            return loc.pick("另一个屏幕时间操作正在处理，请稍后再试。", "Another Screen Time action is still processing. Try again shortly.")
        default:
            if let unlockError = fallbackError as? UnlockError,
               unlockError == .alreadyActive {
                return loc.pick("这个 App 已经在使用时间内，无需重复解锁。", "This app already has active time.")
            }
            return loc.pick("设备没有成功解锁，成长积分不会被扣除，请重试。", "The device did not unlock. No Growth Points were charged. Try again.")
        }
    }
    #endif

    private func submitEmergencyUnlockRequest() {
        guard familyCloud.isChildDevice else {
            emergencyHint = loc.pick("请先把这台手机作为孩子设备加入家庭。", "Join this phone to the family as a child device first.")
            return
        }
        isEmergencyWorking = true
        emergencyHint = nil
        Task {
            do {
                _ = try await familyCloud.submitChildScreenTimeEmergency(
                    reason: loc.pick("学校模式下需要紧急使用手机。", "I need emergency phone access during School Mode."),
                    minutes: 30,
                    localChildID: store.activeChildId
                )
                emergencyHint = loc.pick("申请已发给家长手机。", "Your request was sent to a parent's phone.")
            } catch {
                emergencyHint = error.localizedDescription
            }
            isEmergencyWorking = false
        }
    }

    private func startApprovedSchoolEmergency(_ emergency: FamilyScreenTimeEmergency?) {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        guard let emergency, let requestId = emergency.requestId, emergency.status == .approved else {
            emergencyHint = loc.pick("批准状态已变化，请刷新后重试。", "The approval changed. Refresh and try again.")
            return
        }
        let minutes = min(60, max(1, emergency.minutes ?? 30))
        isEmergencyWorking = true
        Task {
            do {
                let endsAt = try screenTimePOCManager.startAllAppsEmergencyWindow(
                    minutes: minutes,
                    now: now,
                    sourceLabel: "guardian-approved school emergency"
                )
                _ = try screenTimeController.adoptExternalUnlock(
                    minutes: minutes,
                    now: now,
                    endsAt: endsAt,
                    authority: .schoolEmergency
                )
                _ = try await familyCloud.updateChildScreenTimeEmergency(
                    action: "activate",
                    requestId: requestId,
                    sessionEndsAt: endsAt
                )
                emergencyHint = loc.pick("全部 App 已临时打开 \(minutes) 分钟。", "All apps are open for \(minutes) minutes.")
            } catch {
                screenTimePOCManager.relockRewardWindow()
                screenTimeController.reshieldNow()
                emergencyHint = loc.pick("设备或云端没有完成解锁，没有扣成长积分。请重试。", "The device or cloud did not complete the unlock. No Growth Points were used. Try again.")
            }
            isEmergencyWorking = false
        }
        #else
        emergencyHint = loc.pick("这台设备不支持 Screen Time 控制。", "This device doesn't support Screen Time control.")
        #endif
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

    private var statusTitle: String {
        switch status {
        case .active: return loc.pick("解锁中", "Unlocked")
        case .locked: return loc.pick("已锁定", "Locked")
        case .expired: return loc.pick("已到期", "Expired")
        }
    }

    private var statusIcon: String {
        switch status {
        case .active: return "lock.open.fill"
        case .locked: return "lock.fill"
        case .expired: return "clock.badge.xmark"
        }
    }
}
