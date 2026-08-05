import SwiftUI

@main
struct OctoTeacherApp: App {
    @UIApplicationDelegateAdaptor(OctoTeacherAppDelegate.self)
    private var appDelegate

    /// UI 测试模式：数据不落盘，每次启动都是干净的种子状态，保证测试确定性。
    private static var isUITestMode: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-OctoTeacherUITest") }
    }

    /// 首启路径测试专用：清空本机数据后按真实模式启动（不是 UI 测试模式，
    /// 仍走文件持久化、4 Tab、首次设置引导）。真实用户不会带该参数。
    private static func resetForFirstRunTestIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-OctoTeacherResetForFirstRunTest") else { return }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("octoteacher-family.json"))
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("octoteacher-website-safety.json"))
        try? FileManager.default.removeItem(at: documents.appendingPathComponent("octoteacher-emergency-unlocks.json"))
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "octoteacher.setup.completed")
        defaults.removeObject(forKey: "octoteacher.parent.pin")
        defaults.removeObject(forKey: "octoteacher.screentime.session")
    }

    private static func applyUITestFixtures(to store: LocalFamilyStore) {
        guard isUITestMode else { return }
        // 英文幼儿夹具：活跃孩子直接进入英文幼儿模式（测英文幼儿首页与小喇叭标签）。
        if ProcessInfo.processInfo.arguments.contains("-OctoTeacherUITestEnglishPreReaderChild") {
            store.setChildInterfaceLanguage(.english, for: store.activeChildId)
            store.setPreReaderMode(true, for: store.activeChildId)
        }
        // 全英文界面巡检夹具：父母 surface 与当前孩子 surface 同时使用英文，
        // 用来发现新增页面里遗漏的硬编码中文或动态内容翻译。
        if ProcessInfo.processInfo.arguments.contains("-OctoTeacherUITestEnglishFamily") {
            store.setParentInterfaceLanguage(.english)
            store.setChildInterfaceLanguage(.english, for: store.activeChildId)
        }
        // 英文界面巡检使用英文孩子姓名，避免把家庭自定义姓名误判为未翻译的产品文案。
        if ProcessInfo.processInfo.arguments.contains("-OctoTeacherUITestEnglishChildName"),
           let child = store.children.first(where: { $0.id == store.activeChildId }) {
            store.updateChildProfile(
                childId: child.id,
                name: "Alex",
                age: child.age,
                dailyLimitMinutes: child.dailyLimitMinutes
            )
        }
        guard ProcessInfo.processInfo.arguments.contains("-OctoTeacherUITestEmptyChildTasks") else { return }
        let childId = store.activeChildId
        let removedIds = Set(store.assignments.filter { $0.childId == childId }.map(\.id))
        store.assignments.removeAll { $0.childId == childId }
        store.growthPack.steps.removeAll { removedIds.contains($0.assignmentId) }
        for (offset, _) in store.growthPack.steps.enumerated() {
            store.growthPack.steps[offset].order = offset + 1
        }
    }

    /// 注意：@State 默认值先于 init 执行，因此重置逻辑放在第一个属性的
    /// 初始化闭包里，保证它在任何 store 读取本机数据之前完成。
    @State private var store: LocalFamilyStore = {
        OctoTeacherApp.resetForFirstRunTestIfRequested()
        let store = LocalFamilyStore(
            persistence: isUITestMode ? nil : FileFamilyStorePersistence.documents()
        )
        OctoTeacherApp.applyUITestFixtures(to: store)
        return store
    }()
    @State private var screenTimeController = MockScreenTimeController(
        persistenceKey: isUITestMode ? nil : "octoteacher.screentime.session"
    )
    @State private var websiteSafety = WebsiteSafetyStore(
        persistence: isUITestMode ? nil : FileWebsiteSafetyPersistence.documents()
    )
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @State private var screenTimePOCManager = ScreenTimePOCManager()
    #endif
    @State private var parentGate = ParentGate()
    @State private var schoolFamilyStore = SchoolFamilyStore()
    /// 真实模式从空队列开始（孩子/家长的动作才会入队）；
    /// UI 测试模式保留演示队列，供同步状态点击路径测试使用。
    @State private var offlineOutbox = isUITestMode ? MobileOfflineOutboxStore.mock() : MobileOfflineOutboxStore()
    @State private var offlineReplay = MobileOfflineReplayStore()
    @State private var creditSettlement = MobileCreditSettlementStore()
    @State private var growthRuntime = GrowthPackRuntimeStore()
    @State private var evidenceTimeline = GrowthEvidenceTimelineStore()
    /// 家长 BYOK AI 配置；UI 测试模式用内存密钥库和纯内存配置，保证确定性。
    @State private var aiProvider = ParentAIProviderStore(
        keyStore: isUITestMode ? InMemoryAIProviderKeyStore() : KeychainAIProviderKeyStore(),
        defaults: isUITestMode ? nil : .standard
    )
    @State private var aiCompanionSessions = AICompanionSessionStore(
        persistence: isUITestMode ? nil : FileAICompanionSessionPersistence.documents()
    )
    @State private var aiCompanionMemory = AICompanionMemoryStore(
        persistence: isUITestMode ? nil : FileAICompanionMemoryPersistence.documents()
    )
    @State private var aiCompanionTranscript = AICompanionTranscriptStore(
        persistence: isUITestMode ? nil : FileAICompanionTranscriptPersistence.documents()
    )
    @State private var parentAICompanionCoach = ParentAICompanionCoachStore(
        persistence: isUITestMode ? nil : FileParentAICompanionCoachPersistence.documents()
    )
    @State private var growthMemory = GrowthMemoryStore(
        persistence: isUITestMode ? nil : FileGrowthMemoryPersistence.documents()
    )
    @State private var familyCloud = FamilyCloudSessionStore(
        secrets: isUITestMode ? InMemoryFamilyCloudSecretStore() : KeychainFamilyCloudSecretStore(),
        syncStateStore: isUITestMode ? InMemoryFamilyCloudSyncStateStore() : FileFamilyCloudSyncStateStore.documents()
    )

    var body: some Scene {
        WindowGroup {
            let root = RootView()
                .environment(store)
                .environment(screenTimeController)
                .environment(websiteSafety)
                .environment(parentGate)
                .environment(schoolFamilyStore)
                .environment(offlineOutbox)
                .environment(offlineReplay)
                .environment(creditSettlement)
                .environment(growthRuntime)
                .environment(evidenceTimeline)
                .environment(aiProvider)
                .environment(aiCompanionSessions)
                .environment(aiCompanionMemory)
                .environment(aiCompanionTranscript)
                .environment(parentAICompanionCoach)
                .environment(growthMemory)
                .environment(familyCloud)
            #if canImport(FamilyControls) && canImport(ManagedSettings)
            root.environment(screenTimePOCManager)
            #else
            root
            #endif
        }
    }
}
