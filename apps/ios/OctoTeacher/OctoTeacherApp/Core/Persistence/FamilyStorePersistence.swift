import Foundation

/// 家庭数据快照：一次性编码 LocalFamilyStore 的全部可持久化状态。
/// 只存本机 App 沙盒，不上传网络，不含设备标识。
///
/// v2（2026-07-04）：单孩子 `child` 升级为多孩子 `children` + `activeChildId`。
/// v3（2026-07-08）：增加电子书阅读进度，用于孩子端内置阅读器续读。
/// v4（2026-07-08）：增加家庭自定义任务包模板，用于家务/独立/户外等包的自定义条目。
/// v5（2026-07-09）：增加家庭成员、设备绑定和一次性二维码邀请合同。
/// v6（2026-07-10）：增加培训市场安装回执，保证同一孩子不会重复安装同一任务包。
/// v7（2026-07-10）：增加每孩子学校模式规则与本机学校动态摘要。
/// v8（2026-07-12）：增加成长包市场安装后的家庭内容资源引用。
/// 解码兼容 v1 旧文件：读到 legacy `child` 字段时自动迁移为单元素数组。
struct FamilyStoreSnapshot: Codable, Equatable {
    /// 快照结构版本，用于未来迁移。
    var schemaVersion: Int
    var children: [ChildProfile]
    /// 当前在孩子端使用的孩子（共享设备上的身份切换）。
    var activeChildId: UUID
    var assignments: [TaskAssignment]
    var growthPack: GrowthPack
    var rewards: [RewardGrant]
    var relatives: [FamilyRelative]
    var suggestions: [RelativeSuggestion]
    var events: [FamilyEvent]
    /// 家庭设置（语言等）；旧数据缺省为默认设置。
    var settings: FamilySettings?
    /// 每孩子的兑换机制；旧数据缺省为默认策略。
    var exchangePolicies: [UUID: FamilyExchangePolicy]?
    /// 零花钱账本；旧数据缺省为空。
    var moneyLedger: [MoneyLedgerEntry]?
    /// 每孩子的月度零花钱入账游标（"2026-07"），防重复入账。
    var allowanceCursors: [UUID: String]?
    /// 愿望清单；旧数据缺省为空。
    var wishes: [WishListItem]?
    /// 每个包的默认成长积分（PackType.rawValue → 分值）；旧数据缺省为空。
    var packDefaultPoints: [String: Int]?
    /// 家庭自定义任务包模板（PackType.rawValue → 自定义模板列表）；旧数据缺省为空。
    var customPackTemplates: [String: [PackTaskTemplate]]?
    /// 重复任务规则；旧数据缺省为空。
    var recurringRules: [RecurringTaskRule]?
    /// 家庭里的大人列表；旧数据缺省为空（默认"家长"）。
    var guardians: [GuardianProfile]?
    /// 当前操作的大人。
    var currentGuardianId: UUID?
    /// 每孩子每学科的学习进度（childId → subject → 进度）。
    var subjectProgress: [UUID: [String: SubjectProgressEntry]]?
    /// 已考过试的任务，防重复刷分。
    var quizTakenAssignmentIds: [UUID]?
    /// 导入的电子书书库；旧数据缺省为空。
    var books: [FamilyBook]?
    /// 孩子在 App 内阅读导入书籍的本地进度；旧数据缺省为空。
    var bookReadingProgress: [BookReadingProgress]?
    /// 家庭成员/设备/邀请合同；旧数据由 guardians、relatives、children 自动迁移。
    var familyNetwork: FamilyNetworkState?
    /// 培训市场安装回执；旧数据缺省为空。
    var trainingMarketplaceInstallations: [TrainingMarketplaceInstallationRecord]?
    /// 市场安装后进入图书馆、教育视频或创作广场的资源引用；旧数据缺省为空。
    var installedMarketplaceResources: [TrainingMarketplaceInstalledResource]?
    /// 每孩子的学校模式时间表；旧数据缺省为未开启的默认周计划。
    var schoolModeProfiles: [UUID: ChildSchoolModeProfile]?
    /// 学校邮件提取后的结构化动态；不包含邮件原文、邮箱地址或消息标识。
    var schoolDynamics: [SchoolDynamicRecord]?

    static let currentSchemaVersion = 8

    init(
        schemaVersion: Int,
        children: [ChildProfile],
        activeChildId: UUID,
        assignments: [TaskAssignment],
        growthPack: GrowthPack,
        rewards: [RewardGrant],
        relatives: [FamilyRelative],
        suggestions: [RelativeSuggestion],
        events: [FamilyEvent],
        settings: FamilySettings? = nil,
        exchangePolicies: [UUID: FamilyExchangePolicy]? = nil,
        moneyLedger: [MoneyLedgerEntry]? = nil,
        allowanceCursors: [UUID: String]? = nil,
        wishes: [WishListItem]? = nil,
        packDefaultPoints: [String: Int]? = nil,
        customPackTemplates: [String: [PackTaskTemplate]]? = nil,
        recurringRules: [RecurringTaskRule]? = nil,
        guardians: [GuardianProfile]? = nil,
        currentGuardianId: UUID? = nil,
        subjectProgress: [UUID: [String: SubjectProgressEntry]]? = nil,
        quizTakenAssignmentIds: [UUID]? = nil,
        books: [FamilyBook]? = nil,
        bookReadingProgress: [BookReadingProgress]? = nil,
        familyNetwork: FamilyNetworkState? = nil,
        trainingMarketplaceInstallations: [TrainingMarketplaceInstallationRecord]? = nil,
        installedMarketplaceResources: [TrainingMarketplaceInstalledResource]? = nil,
        schoolModeProfiles: [UUID: ChildSchoolModeProfile]? = nil,
        schoolDynamics: [SchoolDynamicRecord]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.children = children
        self.activeChildId = activeChildId
        self.assignments = assignments
        self.growthPack = growthPack
        self.rewards = rewards
        self.relatives = relatives
        self.suggestions = suggestions
        self.events = events
        self.settings = settings
        self.exchangePolicies = exchangePolicies
        self.moneyLedger = moneyLedger
        self.allowanceCursors = allowanceCursors
        self.wishes = wishes
        self.packDefaultPoints = packDefaultPoints
        self.customPackTemplates = customPackTemplates
        self.recurringRules = recurringRules
        self.guardians = guardians
        self.currentGuardianId = currentGuardianId
        self.subjectProgress = subjectProgress
        self.quizTakenAssignmentIds = quizTakenAssignmentIds
        self.books = books
        self.bookReadingProgress = bookReadingProgress
        self.familyNetwork = familyNetwork
        self.trainingMarketplaceInstallations = trainingMarketplaceInstallations
        self.installedMarketplaceResources = installedMarketplaceResources
        self.schoolModeProfiles = schoolModeProfiles
        self.schoolDynamics = schoolDynamics
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case children
        case activeChildId
        case child // v1 legacy
        case assignments
        case growthPack
        case rewards
        case relatives
        case suggestions
        case events
        case settings
        case exchangePolicies
        case moneyLedger
        case allowanceCursors
        case wishes
        case packDefaultPoints
        case customPackTemplates
        case recurringRules
        case guardians
        case currentGuardianId
        case subjectProgress
        case quizTakenAssignmentIds
        case books
        case bookReadingProgress
        case familyNetwork
        case trainingMarketplaceInstallations
        case installedMarketplaceResources
        case schoolModeProfiles
        case schoolDynamics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)

        if let migrated = try container.decodeIfPresent([ChildProfile].self, forKey: .children),
           !migrated.isEmpty {
            children = migrated
            let savedActive = try container.decodeIfPresent(UUID.self, forKey: .activeChildId)
            activeChildId = migrated.contains(where: { $0.id == savedActive }) ? savedActive! : migrated[0].id
        } else {
            // v1 旧文件：单孩子迁移为数组。
            let legacy = try container.decode(ChildProfile.self, forKey: .child)
            children = [legacy]
            activeChildId = legacy.id
        }

        assignments = try container.decode([TaskAssignment].self, forKey: .assignments)
        growthPack = try container.decode(GrowthPack.self, forKey: .growthPack)
        rewards = try container.decode([RewardGrant].self, forKey: .rewards)
        relatives = try container.decode([FamilyRelative].self, forKey: .relatives)
        suggestions = try container.decode([RelativeSuggestion].self, forKey: .suggestions)
        events = try container.decode([FamilyEvent].self, forKey: .events)
        settings = try container.decodeIfPresent(FamilySettings.self, forKey: .settings)
        exchangePolicies = try container.decodeIfPresent([UUID: FamilyExchangePolicy].self, forKey: .exchangePolicies)
        moneyLedger = try container.decodeIfPresent([MoneyLedgerEntry].self, forKey: .moneyLedger)
        allowanceCursors = try container.decodeIfPresent([UUID: String].self, forKey: .allowanceCursors)
        wishes = try container.decodeIfPresent([WishListItem].self, forKey: .wishes)
        packDefaultPoints = try container.decodeIfPresent([String: Int].self, forKey: .packDefaultPoints)
        customPackTemplates = try container.decodeIfPresent([String: [PackTaskTemplate]].self, forKey: .customPackTemplates)
        recurringRules = try container.decodeIfPresent([RecurringTaskRule].self, forKey: .recurringRules)
        guardians = try container.decodeIfPresent([GuardianProfile].self, forKey: .guardians)
        currentGuardianId = try container.decodeIfPresent(UUID.self, forKey: .currentGuardianId)
        subjectProgress = try container.decodeIfPresent([UUID: [String: SubjectProgressEntry]].self, forKey: .subjectProgress)
        quizTakenAssignmentIds = try container.decodeIfPresent([UUID].self, forKey: .quizTakenAssignmentIds)
        books = try container.decodeIfPresent([FamilyBook].self, forKey: .books)
        bookReadingProgress = try container.decodeIfPresent([BookReadingProgress].self, forKey: .bookReadingProgress)
        familyNetwork = try container.decodeIfPresent(FamilyNetworkState.self, forKey: .familyNetwork)
        trainingMarketplaceInstallations = try container.decodeIfPresent(
            [TrainingMarketplaceInstallationRecord].self,
            forKey: .trainingMarketplaceInstallations
        )
        installedMarketplaceResources = try container.decodeIfPresent(
            [TrainingMarketplaceInstalledResource].self,
            forKey: .installedMarketplaceResources
        )
        schoolModeProfiles = try container.decodeIfPresent(
            [UUID: ChildSchoolModeProfile].self,
            forKey: .schoolModeProfiles
        )
        schoolDynamics = try container.decodeIfPresent([SchoolDynamicRecord].self, forKey: .schoolDynamics)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(children, forKey: .children)
        try container.encode(activeChildId, forKey: .activeChildId)
        try container.encode(assignments, forKey: .assignments)
        try container.encode(growthPack, forKey: .growthPack)
        try container.encode(rewards, forKey: .rewards)
        try container.encode(relatives, forKey: .relatives)
        try container.encode(suggestions, forKey: .suggestions)
        try container.encode(events, forKey: .events)
        try container.encodeIfPresent(settings, forKey: .settings)
        try container.encodeIfPresent(exchangePolicies, forKey: .exchangePolicies)
        try container.encodeIfPresent(moneyLedger, forKey: .moneyLedger)
        try container.encodeIfPresent(allowanceCursors, forKey: .allowanceCursors)
        try container.encodeIfPresent(wishes, forKey: .wishes)
        try container.encodeIfPresent(packDefaultPoints, forKey: .packDefaultPoints)
        try container.encodeIfPresent(customPackTemplates, forKey: .customPackTemplates)
        try container.encodeIfPresent(recurringRules, forKey: .recurringRules)
        try container.encodeIfPresent(guardians, forKey: .guardians)
        try container.encodeIfPresent(currentGuardianId, forKey: .currentGuardianId)
        try container.encodeIfPresent(subjectProgress, forKey: .subjectProgress)
        try container.encodeIfPresent(quizTakenAssignmentIds, forKey: .quizTakenAssignmentIds)
        try container.encodeIfPresent(books, forKey: .books)
        try container.encodeIfPresent(bookReadingProgress, forKey: .bookReadingProgress)
        try container.encodeIfPresent(familyNetwork, forKey: .familyNetwork)
        try container.encodeIfPresent(trainingMarketplaceInstallations, forKey: .trainingMarketplaceInstallations)
        try container.encodeIfPresent(installedMarketplaceResources, forKey: .installedMarketplaceResources)
        try container.encodeIfPresent(schoolModeProfiles, forKey: .schoolModeProfiles)
        try container.encodeIfPresent(schoolDynamics, forKey: .schoolDynamics)
    }
}

/// 家庭数据持久化端口。为 nil 时 store 退化为纯内存（测试与 UI 测试模式）。
protocol FamilyStorePersisting: AnyObject {
    /// 读取上次保存的快照；文件缺失或解码失败返回 nil，由调用方回退种子数据。
    func load() -> FamilyStoreSnapshot?
    /// 覆盖保存快照。失败静默丢弃，下一次变更会再次尝试。
    func save(_ snapshot: FamilyStoreSnapshot)
}

/// JSON 文件持久化：写入 App 沙盒 Documents 下的单文件。
/// 家庭测试版数据量很小（几十条任务/事件），整文件原子读写足够可靠。
final class FileFamilyStorePersistence: FamilyStorePersisting {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 默认位置：Documents/octoteacher-family.json。
    static func documents() -> FileFamilyStorePersistence {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileFamilyStorePersistence(fileURL: directory.appendingPathComponent("octoteacher-family.json"))
    }

    func load() -> FamilyStoreSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(FamilyStoreSnapshot.self, from: data) else { return nil }
        guard snapshot.schemaVersion <= FamilyStoreSnapshot.currentSchemaVersion else { return nil }
        return snapshot
    }

    func save(_ snapshot: FamilyStoreSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
