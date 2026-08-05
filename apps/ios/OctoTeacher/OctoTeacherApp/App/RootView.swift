import SwiftUI
import UserNotifications

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LocalFamilyStore.self) private var store
    @Environment(MockScreenTimeController.self) private var screenTimeController
    @Environment(WebsiteSafetyStore.self) private var websiteSafety
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @Environment(ScreenTimePOCManager.self) private var screenTimePOCManager
    @State private var pendingShieldAction: PersistedShieldActionRequest? = nil
    @State private var pendingShieldActionRefresh: Task<Void, Never>?
    #endif
    @State private var selectedTab: Int
    @State private var didResolveInitialCloudRole = false
    @State private var isCloudSyncRunning = false
    @State private var cloudSyncNeedsAnotherPass = false
    @State private var pendingCloudSync: Task<Void, Never>?
    @State private var registeredRemotePush: FamilyRemotePushRegistration?
    /// 只影响这台家长设备里的孩子端预览，不上传、不改变孩子手机语言。
    @AppStorage(GuardianChildPreviewLanguagePreference.key)
    private var guardianChildPreviewLanguageRaw = GuardianChildPreviewLanguage.followChild.rawValue
    /// 首次启动由家长完成的家庭设置是否已做完。
    @AppStorage("octoteacher.setup.completed") private var setupCompleted = false
    @AppStorage("octoteacher.screentime.notifiedEmergencyRequestIDs")
    private var notifiedEmergencyRequestIDs = ""
    @State private var guardianEmergencyAlertChildName: String?

    /// 任何 -章鱼老师UITest 前缀参数都会进入 UI 测试模式：
    /// 保留完整平台 Tab、跳过首次设置，保证既有点击路径测试确定性。
    private let isUITestMode: Bool
    /// 产品体验测试使用真实家庭四 Tab，同时仍可跳过首次设置并加载确定性夹具。
    private let usesFamilyTabsInUITests: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITestMode = arguments.contains { $0.hasPrefix("-OctoTeacherUITest") }
        self.isUITestMode = isUITestMode
        self.usesFamilyTabsInUITests = arguments.contains("-OctoTeacherUITestFamilyTabs")

        let startsInModuleAuditMode = arguments.contains("-OctoTeacherUITestModuleAudit")
        let fallbackTab: OctoTeacherRootTab = isUITestMode ? .home : .child
        let initialTab = Self.uiTestInitialTab(from: arguments)
            ?? (startsInModuleAuditMode ? .modules : fallbackTab)
        _selectedTab = State(initialValue: initialTab.tag)
    }

    private var uiTestModuleInitialRole: MobileModuleLaunchCenterViewerRole {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let flagIndex = arguments.firstIndex(of: "-OctoTeacherUITestModuleRole"),
            arguments.indices.contains(arguments.index(after: flagIndex)),
            let role = MobileModuleLaunchCenterViewerRole(rawValue: arguments[arguments.index(after: flagIndex)])
        else {
            return .child
        }
        return role
    }

    private var usesFullRoleModuleAudit: Bool {
        ProcessInfo.processInfo.arguments.contains("-OctoTeacherUITestAllRoles")
    }

    private static func uiTestInitialTab(from arguments: [String]) -> OctoTeacherRootTab? {
        guard
            let flagIndex = arguments.firstIndex(of: "-OctoTeacherUITestInitialTab"),
            arguments.indices.contains(arguments.index(after: flagIndex))
        else {
            return nil
        }

        switch arguments[arguments.index(after: flagIndex)] {
        case "home": return .home
        case "modules": return .modules
        case "child": return .child
        case "parent": return .parent
        case "school": return .school
        case "family": return .family
        case "more": return .more
        default: return nil
        }
    }

    /// 当前模式下渲染的顶层 Tab。
    private var tabs: [OctoTeacherRootTab] {
        if isUITestMode && !usesFamilyTabsInUITests { return OctoTeacherRootTab.auditOrdered }
        return familyCloud.isChildDevice ? [.child] : OctoTeacherRootTab.ordered
    }

    /// 是否需要先完成首次家庭设置（UI 测试模式跳过）。
    private var needsFamilySetup: Bool {
        !isUITestMode && !setupCompleted
    }

    /// 家长 Tab 角标：等待审核的提交数（家长的"通知提示"）。
    private var pendingApprovalCount: Int {
        store.assignments.filter { $0.status == .submitted }.count +
            familyCloud.pendingScreenTimeEmergencyChildIDs.count
    }

    /// 当前选中 surface 的统一语言：孩子/学校页面跟当前活跃孩子，其余跟家长。
    /// 整棵 TabView（含四个 Tab 标题）一次性用同一语言，切 Tab 或切孩子时整体切换。
    private var childSurfaceLanguage: AppInterfaceLanguage {
        guard !familyCloud.isChildDevice else { return store.activeChildInterfaceLanguage }
        return GuardianChildPreviewLanguagePreference.resolve(guardianChildPreviewLanguageRaw)
            .resolvedLanguage(childLanguage: store.activeChildInterfaceLanguage)
    }

    private var surfaceLanguage: AppInterfaceLanguage {
        OctoTeacherRootTab.surfaceLanguage(
            selectedTag: selectedTab,
            parentLanguage: store.settings.resolvedParentInterfaceLanguage,
            activeChildLanguage: childSurfaceLanguage
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(tabs, id: \.tag) { tab in
                rootTab(tab)
            }
        }
        .environment(\.childSurfaceLanguage, childSurfaceLanguage)
        .environment(\.locale, Locale(identifier: surfaceLanguage.localeIdentifier))
        .fullScreenCover(
            isPresented: Binding(
                get: { needsFamilySetup },
                set: { presented in
                    if !presented {
                        setupCompleted = true
                    }
                }
            )
        ) {
            FamilySetupView {
                setupCompleted = true
            }
        }
        .alert(
            store.settings.resolvedParentInterfaceLanguage.pick(
                "孩子申请紧急解锁",
                "Emergency Access Request"
            ),
            isPresented: Binding(
                get: { guardianEmergencyAlertChildName != nil },
                set: { if !$0 { guardianEmergencyAlertChildName = nil } }
            )
        ) {
            Button(store.settings.resolvedParentInterfaceLanguage.pick("查看申请", "Review Request")) {
                selectedTab = OctoTeacherRootTab.parent.tag
                guardianEmergencyAlertChildName = nil
            }
            Button(store.settings.resolvedParentInterfaceLanguage.pick("稍后", "Later"), role: .cancel) {
                guardianEmergencyAlertChildName = nil
            }
        } message: {
            if let childName = guardianEmergencyAlertChildName {
                Text(store.settings.resolvedParentInterfaceLanguage.pick(
                    "\(childName) 在学校模式下申请临时打开全部 App。",
                    "\(childName) asked to temporarily open all apps during School Mode."
                ))
            }
        }
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        .fullScreenCover(item: $pendingShieldAction) { request in
            shieldActionCover(request)
        }
        #endif
        .onAppear {
            aiProvider.attachFamilyCloud(familyCloud)
            // 云端真人语音接线：家庭开关开 + BYOK 就绪时走 OpenAI TTS，否则本机。
            SpeechReader.shared.cloudSynthesizer = { [weak store, weak aiProvider] text, voiceStyle, languageHint in
                guard let store, let aiProvider,
                      store.settings.resolvedCloudVoice,
                      aiProvider.isCloudVoiceCapable else { return nil }
                return try? await aiProvider.synthesizeSpeech(
                    text,
                    voiceStyle: voiceStyle,
                    languageHint: languageHint
                )
            }
            #if canImport(FamilyControls) && canImport(ManagedSettings)
            if screenTimePOCManager.resetStaleDeviceEnforcementIfNeeded() {
                screenTimeController.resetPersistedSessionWithoutRelock()
            }
            screenTimePOCManager.migrateLegacyIndividualAuthorizationIfNeeded(
                isChildDevice: familyCloud.isChildDevice
            )
            if familyCloud.isChildDevice {
                publishChildScreenTimeLanguage()
            }
            refreshPendingShieldActionAfterSystemLaunch()
            #endif
            if screenTimeController.tick() != nil {
                queueCompletedScreenTimeReceipts()
                scheduleCloudSync()
            }
            drainPendingRemoteScreenTimeSyncRequests()
            applySystemSafetyPolicies()
            _ = store.child
        }
        .task {
            await syncCloudFamily()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard scenePhase == .active else { continue }
                await syncCloudFamily()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .familyRemotePushRegistrationChanged)
        ) { _ in
            Task { await registerCurrentChildPushIfNeeded() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .familyScreenTimeRemoteSyncRequested)
        ) { notification in
            guard let request = notification.object as? FamilyScreenTimeRemoteSyncRequest else {
                return
            }
            guard FamilyRemoteNotificationCoordinator.shared.claim(request) else { return }
            Task { await performRemoteScreenTimeSync(request) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if screenTimeController.tick() != nil {
                queueCompletedScreenTimeReceipts()
            }
            #if canImport(FamilyControls) && canImport(ManagedSettings)
            screenTimePOCManager.refreshAuthorizationStatus()
            if familyCloud.isChildDevice {
                publishChildScreenTimeLanguage()
                screenTimePOCManager.relockIfNeeded()
            }
            refreshPendingShieldActionAfterSystemLaunch()
            #endif
            applySystemSafetyPolicies()
            Task { await syncCloudFamily() }
        }
        .onChange(of: store.activeChildId) { _, _ in
            applySystemSafetyPolicies()
            scheduleCloudSync()
        }
        .onChange(of: store.activeChildInterfaceLanguage) { _, _ in
            publishChildScreenTimeLanguage()
            applySystemSafetyPolicies()
        }
        .onChange(of: store.assignments) { _, _ in
            scheduleCloudSync()
        }
        .onChange(of: store.children) { _, _ in
            scheduleCloudSync()
        }
        .onChange(of: familyCloud.isChildDevice) { _, isChildDevice in
            #if canImport(FamilyControls) && canImport(ManagedSettings)
            screenTimePOCManager.migrateLegacyIndividualAuthorizationIfNeeded(isChildDevice: isChildDevice)
            #endif
            if isChildDevice {
                selectedTab = OctoTeacherRootTab.child.tag
                #if canImport(FamilyControls) && canImport(ManagedSettings)
                publishChildScreenTimeLanguage()
                #endif
                applySystemSafetyPolicies()
            } else {
                registeredRemotePush = nil
            }
        }
        .onChange(of: aiProvider.config) { _, _ in
            Task { try? await familyCloud.syncGuardianAI(from: aiProvider) }
        }
        .onChange(of: aiProvider.allowsChildAICompanionGuidance) { _, _ in
            Task { try? await familyCloud.syncGuardianAI(from: aiProvider) }
        }
        .onChange(of: aiProvider.allowsChildAICompanionImageUpload) { _, _ in
            Task { try? await familyCloud.syncGuardianAI(from: aiProvider) }
        }
        .onChange(of: aiProvider.allowsChildVoiceTranscription) { _, _ in
            Task { try? await familyCloud.syncGuardianAI(from: aiProvider) }
        }
    }

    @ViewBuilder
    private func rootTab(_ tab: OctoTeacherRootTab) -> some View {
        NavigationStack {
            content(for: tab)
        }
        .tabItem {
            Label(tab.label(for: surfaceLanguage), systemImage: tab.systemImage)
        }
        .badge(tab == .parent ? pendingApprovalCount : 0)
        .tag(tab.tag)
    }

    #if canImport(FamilyControls) && canImport(ManagedSettings)
    private func shieldActionCover(_ request: PersistedShieldActionRequest) -> some View {
        let requestLanguage = AppInterfaceLanguage(
            rawValue: ScreenTimeSharedContract.hostInterfaceLanguageRawValue(
                currentChildLanguage: childSurfaceLanguage.rawValue,
                request: request,
                fallback: childSurfaceLanguage.rawValue
            )
        ) ?? childSurfaceLanguage
        return NavigationStack {
            RewardRedemptionView(
                pendingShieldAction: request,
                interfaceLanguageOverride: requestLanguage,
                onShieldActionCompleted: {
                    dismissShieldAction(request)
                }
            )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(requestLanguage.pick("关闭", "Close")) {
                            dismissShieldAction(request)
                        }
                    }
                }
        }
    }

    private func dismissShieldAction(_ request: PersistedShieldActionRequest) {
        screenTimePOCManager.clearPendingShieldAction(id: request.id)
        pendingShieldAction = nil
    }

    private func refreshPendingShieldActionAfterSystemLaunch() {
        pendingShieldActionRefresh?.cancel()
        pendingShieldActionRefresh = Task { @MainActor in
            for delayMilliseconds in [0, 100, 200, 400, 800, 1_500, 3_000] {
                if delayMilliseconds > 0 {
                    try? await Task.sleep(
                        for: .milliseconds(delayMilliseconds)
                    )
                }
                guard !Task.isCancelled else { return }
                if let request = screenTimePOCManager.pendingShieldAction() {
                    pendingShieldAction = request
                    return
                }
            }
        }
    }
    #endif

    private func syncCloudFamily() async {
        guard !isCloudSyncRunning else {
            cloudSyncNeedsAnotherPass = true
            return
        }
        isCloudSyncRunning = true
        cloudSyncNeedsAnotherPass = false
        queueCompletedScreenTimeReceipts()
        await familyCloud.bootstrap()
        await registerCurrentChildPushIfNeeded()
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        if let request = screenTimePOCManager.pendingShieldAction() {
            pendingShieldAction = request
        }
        #endif
        if !isUITestMode && !didResolveInitialCloudRole {
            if familyCloud.isChildDevice {
                selectedTab = OctoTeacherRootTab.child.tag
                didResolveInitialCloudRole = true
            } else if familyCloud.isGuardianSignedIn {
                selectedTab = OctoTeacherRootTab.parent.tag
                didResolveInitialCloudRole = true
            }
        }
        if familyCloud.isChildDevice {
            do {
                try await familyCloud.refreshChildSurface(into: store)
                publishChildScreenTimeLanguage()
                #if canImport(FamilyControls) && canImport(ManagedSettings)
                await syncLocalChildScreenTimeCatalogIfNeeded()
                await reconcileChildScreenTimeEmergency()
                let screenTimePolicy = familyCloud.childDeviceProfile?.screenTimePolicy
                let status = screenTimePOCManager.applySyncedPolicy(screenTimePolicy)
                if status.enforcement == .applied,
                   let control = screenTimePolicy?.control,
                   status.appliedControlCommandId == control.commandId {
                    _ = screenTimeController.reconcileGuardianControl(control)
                    queueCompletedScreenTimeReceipts()
                }
                try? await familyCloud.syncChildScreenTimeStatus(status)
                applySystemSafetyPolicies()
                #endif
            } catch {
                // The session store keeps a visible retry state for the child home.
            }
        } else if familyCloud.isGuardianSignedIn, familyCloud.family != nil {
            do {
                try await familyCloud.syncGuardianTasks(from: store)
            } catch {
                // AI relay refresh remains independent from task/profile sync failures.
            }
            try? await familyCloud.syncGuardianAI(from: aiProvider)
            await notifyGuardianAboutScreenTimeEmergencies()
        }
        isCloudSyncRunning = false
        if cloudSyncNeedsAnotherPass {
            cloudSyncNeedsAnotherPass = false
            await syncCloudFamily()
        }
    }

    #if canImport(FamilyControls) && canImport(ManagedSettings)
    private func syncLocalChildScreenTimeCatalogIfNeeded() async {
        guard familyCloud.childDeviceProfile?.screenTimeCatalog == nil,
              screenTimePOCManager.isChildFamilyAuthorizationReady,
              !screenTimePOCManager.requiresExplicitAppReselection,
              !screenTimePOCManager.selection.applicationTokens.isEmpty
        else { return }
        do {
            let upload = try screenTimePOCManager.makeChildCatalogUpload(
                from: screenTimePOCManager.selection,
                capturedAt: ISO8601DateFormatter().string(from: Date())
            )
            guard upload.applicationCount > 0 else { return }
            let catalog = try await familyCloud.syncChildScreenTimeCatalog(upload)
            screenTimePOCManager.loadGuardianCatalog(catalog)
        } catch {
            // Foreground polling retries after transient network or binding failures.
        }
    }
    #endif

    private func registerCurrentChildPushIfNeeded() async {
        guard familyCloud.isChildDevice,
              let registration = FamilyRemoteNotificationStore.registration,
              registeredRemotePush != registration else { return }
        do {
            try await familyCloud.registerChildPush(registration)
            registeredRemotePush = registration
        } catch {
            // Foreground polling remains the fallback until the next registration retry.
        }
    }

    private func performRemoteScreenTimeSync(
        _ request: FamilyScreenTimeRemoteSyncRequest
    ) async {
        guard familyCloud.isChildDevice else {
            request.finish(.noData)
            return
        }
        await syncCloudFamily()
        while isCloudSyncRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        request.finish(.newData)
    }

    private func drainPendingRemoteScreenTimeSyncRequests() {
        let requests = FamilyRemoteNotificationCoordinator.shared
            .takePendingScreenTimeRequests()
        for request in requests {
            Task { await performRemoteScreenTimeSync(request) }
        }
    }

    private func scheduleCloudSync() {
        pendingCloudSync?.cancel()
        pendingCloudSync = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await syncCloudFamily()
        }
    }

    private func queueCompletedScreenTimeReceipts() {
        for receipt in screenTimeController.pendingActivityReceipts {
            if familyCloud.queueScreenTimeAuthorizationReceipt(receipt) {
                screenTimeController.markActivityReceiptQueued(receipt.id)
            }
        }
    }

    @ViewBuilder
    private func content(for tab: OctoTeacherRootTab) -> some View {
        switch tab {
        case .home:
            MobileHomeView()
        case .modules:
            MobileModuleLaunchCenterView(
                initialRole: uiTestModuleInitialRole,
                allowedRoles: usesFullRoleModuleAudit ? MobileModuleLaunchCenterViewerRole.allCases : [.child]
            )
        case .child:
            ChildHomeView()
        case .parent:
            ParentModeView()
        case .school:
            SchoolHomeworkView()
        case .family:
            FamilyGrowthView()
        case .more:
            MoreTabView()
        }
    }

    private func applySystemSafetyPolicies() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        screenTimePOCManager.migrateLegacyIndividualAuthorizationIfNeeded(
            isChildDevice: familyCloud.isChildDevice
        )
        // ManagedSettings is device-scoped. A guardian phone authors policies only;
        // all shielding, school mode, and website safety must execute on the child phone.
        guard familyCloud.isChildDevice else { return }
        publishChildScreenTimeLanguage()
        guard screenTimePOCManager.isChildFamilyAuthorizationReady else { return }
        screenTimePOCManager.reapplyConfiguredShieldIfNeeded()
        screenTimePOCManager.applyWebsiteSafety(
            enabledDomains: websiteSafety.enabledDomains,
            automaticAdultContentFilter: websiteSafety.automaticAdultContentFilterEnabled
        )
        screenTimePOCManager.synchronizeSchoolMode(
            profile: store.schoolModeProfile(for: store.activeChildId)
        )
        #endif
    }

    private func publishChildScreenTimeLanguage() {
        // The App Group is device-scoped. A guardian previewing another child's
        // language must never rewrite this phone's Shield/Screen Time language.
        guard familyCloud.isChildDevice else { return }
        ScreenTimeSharedContract.publishChildInterfaceLanguage(
            store.activeChildInterfaceLanguage.rawValue
        )
    }

    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @MainActor
    private func reconcileChildScreenTimeEmergency(referenceDate: Date = Date()) async {
        guard familyCloud.isChildDevice,
              let emergency = familyCloud.childDeviceProfile?.screenTimeEmergency,
              let requestId = emergency.requestId
        else { return }

        let shouldExpire: Bool
        switch emergency.status {
        case .requested:
            shouldExpire = (
                emergency.date(from: emergency.requestedAt)?.addingTimeInterval(30 * 60)
                    ?? .distantFuture
            ) <= referenceDate
        case .approved:
            shouldExpire = (emergency.approvalExpirationDate ?? .distantFuture) <= referenceDate
        case .active:
            shouldExpire = (emergency.sessionEndDate ?? .distantFuture) <= referenceDate
            if shouldExpire {
                screenTimePOCManager.relockRewardWindow()
                screenTimeController.reshieldNow()
                applySystemSafetyPolicies()
            }
        case .idle, .denied, .completed, .expired:
            shouldExpire = false
        }

        guard shouldExpire else { return }
        _ = try? await familyCloud.updateChildScreenTimeEmergency(
            action: "expire",
            requestId: requestId
        )
    }
    #endif

    private func notifyGuardianAboutScreenTimeEmergencies() async {
        guard familyCloud.isGuardianSignedIn else { return }
        var notified = Set(notifiedEmergencyRequestIDs.split(separator: ",").map(String.init))
        let requests = store.children.compactMap { child -> (ChildProfile, FamilyScreenTimeEmergency)? in
            guard let emergency = familyCloud.screenTimeEmergency(for: child.id),
                  emergency.status == .requested,
                  let requestId = emergency.requestId,
                  !notified.contains(requestId) else { return nil }
            return (child, emergency)
        }
        guard !requests.isEmpty else { return }

        if guardianEmergencyAlertChildName == nil {
            guardianEmergencyAlertChildName = requests.first?.0.name
        }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
        for (child, emergency) in requests {
            guard let requestId = emergency.requestId else { continue }
            if granted {
                let content = UNMutableNotificationContent()
                content.title = store.settings.resolvedParentInterfaceLanguage.pick(
                    "\(child.name) 申请紧急解锁",
                    "Emergency Access Request from \(child.name)"
                )
                content.body = emergency.reason ?? store.settings.resolvedParentInterfaceLanguage.pick(
                    "打开章鱼老师，在家长页批准或拒绝。",
                    "Open Octo Teacher and approve or deny it in the Parent tab."
                )
                content.sound = .default
                try? await center.add(UNNotificationRequest(
                    identifier: "screen-time-emergency-\(requestId)",
                    content: content,
                    trigger: nil
                ))
            }
            notified.insert(requestId)
        }
        notifiedEmergencyRequestIDs = notified.suffix(100).joined(separator: ",")
    }

}
