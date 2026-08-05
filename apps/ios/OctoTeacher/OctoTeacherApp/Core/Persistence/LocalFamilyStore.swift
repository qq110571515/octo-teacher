import Foundation
import Observation

@Observable
final class LocalFamilyStore {
    /// 家庭里的所有孩子（至少保留一个）。
    var children: [ChildProfile]
    /// 当前活跃孩子：孩子端以此身份使用；家长布置任务默认给它。
    var activeChildId: UUID

    /// 当前活跃孩子的兼容视图：既有代码可继续用 `store.child` 读写，
    /// 写入会落回 children 数组里对应的孩子。
    var child: ChildProfile {
        get { children.first(where: { $0.id == activeChildId }) ?? children[0] }
        set {
            if let index = children.firstIndex(where: { $0.id == newValue.id }) {
                children[index] = newValue
            }
        }
    }

    var assignments: [TaskAssignment]
    var growthPack: GrowthPack
    var rewards: [RewardGrant] = []
    /// 私密家庭圈里的亲友，默认只读 + 建议。
    var relatives: [FamilyRelative]
    /// 亲友留下的鼓励/建议占位。
    var suggestions: [RelativeSuggestion] = []
    /// 家庭参与台事件流（审批、驳回、亲友建议），最新在前。
    var events: [FamilyEvent] = []
    /// 家庭设置（AI 生成语言等）。
    var settings: FamilySettings = .default
    /// 每孩子的兑换机制（成长积分→屏幕时间/零花钱），缺省用默认策略。
    var exchangePolicies: [UUID: FamilyExchangePolicy] = [:]
    /// 零花钱账本（纯记账，最新在前）。
    var moneyLedger: [MoneyLedgerEntry] = []
    /// 每孩子的零花钱入账游标（月 "2026-07" / 周 "2026-W27"），防重复入账。
    var allowanceCursors: [UUID: String] = [:]
    /// 愿望清单（最新在前）。
    var wishes: [WishListItem] = []
    /// 每个包的默认成长积分（家长设定后，模板与 AI 生成都按此分值布置）。
    var packDefaultPoints: [String: Int] = [:]
    /// 家庭自定义任务包模板（PackType.rawValue → 模板列表）。
    var customPackTemplates: [String: [PackTaskTemplate]] = [:]
    /// 重复任务规则（每天/每周自动生成当日实例）。
    var recurringRules: [RecurringTaskRule] = []
    /// 家庭里的大人列表；空时视为单一"家长"。
    var guardians: [GuardianProfile] = []
    /// 当前操作的大人。
    var currentGuardianId: UUID?
    /// 每孩子每学科的学习进度（千小时徽章体系）。
    var subjectProgress: [UUID: [String: SubjectProgressEntry]] = [:]
    /// 已考过试的任务，防重复刷分。
    var quizTakenAssignmentIds: Set<UUID> = []
    /// 导入的电子书书库（EPUB/PDF/TXT/HTML，仅本机）。
    var books: [FamilyBook] = []
    /// 孩子在内置阅读器里的本地阅读进度。
    var bookReadingProgress: [BookReadingProgress] = []
    /// 家庭成员、设备与二维码邀请的本地合同。跨手机数据同步接云端后复用此结构。
    var familyNetwork: FamilyNetworkState
    /// 培训市场安装回执。记录稳定条目/版本/孩子与生成的任务，防止重复安装。
    var trainingMarketplaceInstallations: [TrainingMarketplaceInstallationRecord] = []
    /// 从成长包市场安装到家庭内容工作台的书目、视频和创作模板引用。
    var installedMarketplaceResources: [TrainingMarketplaceInstalledResource] = []
    /// 每孩子独立的学校模式；家庭共享设备以 activeChildId 的规则执行。
    var schoolModeProfiles: [UUID: ChildSchoolModeProfile] = [:]
    /// 学校日历、成绩与老师反馈的本机结构化摘要；不保存邮件原文。
    var schoolDynamics: [SchoolDynamicRecord] = []

    /// 持久化端口；nil 时纯内存运行（单元测试与 UI 测试模式）。
    @ObservationIgnored
    private let persistence: (any FamilyStorePersisting)?

    /// - Parameter persistence: 传入文件持久化后，启动时恢复上次数据，
    ///   每次状态变更自动保存；恢复失败自动回退到全新种子数据。
    init(persistence: (any FamilyStorePersisting)? = nil) {
        self.persistence = persistence
        let requiresFamilyNetworkMigration: Bool

        if let snapshot = persistence?.load() {
            requiresFamilyNetworkMigration = snapshot.familyNetwork == nil
            self.children = snapshot.children
            self.activeChildId = snapshot.activeChildId
            self.assignments = snapshot.assignments
            self.growthPack = snapshot.growthPack
            self.rewards = snapshot.rewards
            self.relatives = snapshot.relatives
            self.suggestions = snapshot.suggestions
            self.events = snapshot.events
            self.settings = snapshot.settings ?? .default
            self.exchangePolicies = snapshot.exchangePolicies ?? [:]
            self.moneyLedger = snapshot.moneyLedger ?? []
            self.allowanceCursors = snapshot.allowanceCursors ?? [:]
            self.wishes = snapshot.wishes ?? []
            self.packDefaultPoints = snapshot.packDefaultPoints ?? [:]
            self.customPackTemplates = snapshot.customPackTemplates ?? [:]
            self.recurringRules = snapshot.recurringRules ?? []
            self.guardians = snapshot.guardians ?? []
            self.currentGuardianId = snapshot.currentGuardianId
            self.subjectProgress = snapshot.subjectProgress ?? [:]
            self.quizTakenAssignmentIds = Set(snapshot.quizTakenAssignmentIds ?? [])
            self.books = snapshot.books ?? []
            self.bookReadingProgress = snapshot.bookReadingProgress ?? []
            self.familyNetwork = snapshot.familyNetwork ?? Self.migratedFamilyNetwork(
                children: snapshot.children,
                guardians: snapshot.guardians ?? [],
                currentGuardianId: snapshot.currentGuardianId
            )
            self.trainingMarketplaceInstallations = snapshot.trainingMarketplaceInstallations ?? []
            self.installedMarketplaceResources = snapshot.installedMarketplaceResources ?? []
            self.schoolModeProfiles = snapshot.schoolModeProfiles ?? [:]
            self.schoolDynamics = snapshot.schoolDynamics ?? []
        } else {
            requiresFamilyNetworkMigration = false
            let child = ChildProfile.sample
            let assignments = Self.seedAssignments(for: child.id)
            let relatives = Self.seedRelatives()
            self.children = [child]
            self.activeChildId = child.id
            self.assignments = assignments
            self.growthPack = Self.seedGrowthPack(from: assignments)
            self.relatives = relatives
            self.familyNetwork = Self.migratedFamilyNetwork(
                children: [child],
                guardians: [],
                currentGuardianId: nil
            )
        }
        let migratedLegacyRewardSources = migrateLegacyRewardSources()
        // 启动时检查是否需要入账基础零花钱、生成今天到期的重复任务（均幂等）。
        creditMonthlyAllowancesIfNeeded()
        generateDueRecurringTasks()
        if requiresFamilyNetworkMigration || migratedLegacyRewardSources {
            persist()
        }
    }

    // MARK: - 持久化

    /// 当前状态的完整快照。
    var snapshot: FamilyStoreSnapshot {
        FamilyStoreSnapshot(
            schemaVersion: FamilyStoreSnapshot.currentSchemaVersion,
            children: children,
            activeChildId: activeChildId,
            assignments: assignments,
            growthPack: growthPack,
            rewards: rewards,
            relatives: relatives,
            suggestions: suggestions,
            events: events,
            settings: settings,
            exchangePolicies: exchangePolicies,
            moneyLedger: moneyLedger,
            allowanceCursors: allowanceCursors,
            wishes: wishes,
            packDefaultPoints: packDefaultPoints,
            customPackTemplates: customPackTemplates,
            recurringRules: recurringRules,
            guardians: guardians,
            currentGuardianId: currentGuardianId,
            subjectProgress: subjectProgress,
            quizTakenAssignmentIds: Array(quizTakenAssignmentIds),
            books: books,
            bookReadingProgress: bookReadingProgress,
            familyNetwork: familyNetwork,
            trainingMarketplaceInstallations: trainingMarketplaceInstallations,
            installedMarketplaceResources: installedMarketplaceResources,
            schoolModeProfiles: schoolModeProfiles,
            schoolDynamics: schoolDynamics
        )
    }

    // MARK: - 学校模式

    func schoolModeProfile(for childID: UUID) -> ChildSchoolModeProfile {
        schoolModeProfiles[childID] ?? .initial(childID: childID)
    }

    func setSchoolModeProfile(_ profile: ChildSchoolModeProfile) {
        guard children.contains(where: { $0.id == profile.childID }) else { return }
        var normalized = profile
        let uniqueRules = profile.weekdayRules.reduce(into: [Int: SchoolWeekdayRule]()) { result, rule in
            guard (1...7).contains(rule.weekday) else { return }
            result[rule.weekday] = rule
        }
        normalized.weekdayRules = uniqueRules.values.sorted { $0.weekday < $1.weekday }
        normalized.exceptions = Array(profile.exceptions.suffix(120))
        normalized.updatedAt = Date()
        schoolModeProfiles[profile.childID] = normalized
        persist()
    }

    func confirmSchoolMailFindings(
        _ findings: [SchoolMailFinding],
        for childID: UUID,
        now: Date = Date()
    ) {
        guard children.contains(where: { $0.id == childID }) else { return }
        var profile = schoolModeProfile(for: childID)

        for finding in findings.prefix(20) {
            schoolDynamics.insert(
                SchoolDynamicRecord(
                    id: UUID(),
                    childID: childID,
                    category: finding.category,
                    title: finding.title,
                    summary: finding.summary,
                    eventDateKey: finding.dateKey,
                    schoolName: finding.schoolName,
                    source: .mailAssisted,
                    createdAt: now
                ),
                at: 0
            )

            guard let dateKey = finding.dateKey, finding.canChangeSchedule else { continue }
            let kind: SchoolCalendarExceptionKind = finding.category == .holiday ? .holiday : .schoolDay
            let exception = SchoolCalendarException(
                id: UUID(),
                dateKey: dateKey,
                kind: kind,
                title: finding.title,
                startMinutes: finding.startMinutes,
                endMinutes: finding.endMinutes,
                source: .mailAssisted,
                guardianConfirmed: true
            )
            profile.exceptions.removeAll { $0.dateKey == dateKey }
            profile.exceptions.append(exception)
        }

        profile.source = .mailAssisted
        profile.updatedAt = now
        schoolModeProfiles[childID] = profile
        schoolDynamics = Array(schoolDynamics.prefix(500))
        persist()
    }

    func schoolDynamics(for childID: UUID) -> [SchoolDynamicRecord] {
        schoolDynamics.filter { $0.childID == childID }
    }

    /// 给 AI 小伙伴/家长教练的最小学校上下文。原始邮件从未进入此 store。
    func schoolDynamicsPromptSummary(for childID: UUID, limit: Int = 6) -> String {
        let items = schoolDynamics(for: childID).prefix(max(0, limit))
        guard !items.isEmpty else { return "" }
        return (["school_updates:"] + items.map { item in
            let date = item.eventDateKey.map { " date=\($0)" } ?? ""
            let school = item.schoolName.map { " school=\($0)" } ?? ""
            return "- \(item.category.rawValue)\(date)\(school): \(item.title) — \(item.summary)"
        }).joined(separator: "\n")
    }

    // MARK: - 孩子管理（多孩子家庭）

    /// 切换当前活跃孩子（孩子端身份 / 家长布置目标）。
    func setActiveChild(_ childId: UUID) {
        guard children.contains(where: { $0.id == childId }) else { return }
        activeChildId = childId
        persist()
    }

    /// 家长添加一个孩子。名字为空或重名时返回 nil。
    @discardableResult
    func addChild(name: String, age: Int, dailyLimitMinutes: Int = 60) -> ChildProfile? {
        let trimmed = Self.sanitizedChildName(name)
        guard !trimmed.isEmpty, !children.contains(where: { $0.name == trimmed }) else { return nil }

        let newChild = ChildProfile(
            id: UUID(),
            name: trimmed,
            age: max(3, min(18, age)),
            dailyLimitMinutes: min(Self.dailyLimitRange.upperBound, max(Self.dailyLimitRange.lowerBound, dailyLimitMinutes)),
            rewardBalanceMinutes: 0
        )
        children.append(newChild)
        familyNetwork.members.append(
            FamilyNetworkMember(
                id: newChild.id,
                displayName: newChild.name,
                role: .child,
                kinshipLabel: "孩子",
                childId: newChild.id,
                status: .active,
                joinedAt: Date()
            )
        )
        appendEvent(
            FamilyEvent(
                id: UUID(),
                kind: .taskAssigned,
                title: "\(trimmed)加入家庭",
                detail: "家长添加了新的孩子成员。",
                minutes: nil,
                createdAt: Date()
            )
        )
        persist()
        return newChild
    }

    /// 家长修改孩子昵称/年龄/每日上限/兴趣/备注。
    @discardableResult
    func updateChildProfile(
        childId: UUID,
        name: String,
        age: Int,
        dailyLimitMinutes: Int,
        interests: [String]? = nil,
        parentNotes: String? = nil
    ) -> Bool {
        guard let index = children.firstIndex(where: { $0.id == childId }) else { return false }
        let trimmed = Self.sanitizedChildName(name)
        guard !trimmed.isEmpty else { return false }
        children[index].name = trimmed
        if let memberIndex = familyNetwork.members.firstIndex(where: { $0.childId == childId }) {
            familyNetwork.members[memberIndex].displayName = trimmed
        }
        children[index].age = max(3, min(18, age))
        children[index].dailyLimitMinutes = min(Self.dailyLimitRange.upperBound, max(Self.dailyLimitRange.lowerBound, dailyLimitMinutes))
        if let interests {
            let cleaned = interests.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            children[index].interests = cleaned.isEmpty ? nil : cleaned
        }
        if let parentNotes {
            let cleaned = parentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            children[index].parentNotes = cleaned.isEmpty ? nil : cleaned
        }
        persist()
        return true
    }

    /// 设置家庭语言（AI 生成内容语言）。
    func setFamilyLanguage(_ language: FamilyLanguage) {
        settings.language = language
        persist()
    }

    func setParentInterfaceLanguage(_ language: AppInterfaceLanguage) {
        settings.parentInterfaceLanguage = language
        persist()
    }

    /// 设置家庭级孩子界面语言默认值（没有 per-child 设置的孩子跟随它）。
    func setChildInterfaceLanguage(_ language: AppInterfaceLanguage) {
        settings.childInterfaceLanguage = language
        persist()
    }

    /// 设置某个孩子自己的界面语言（nil = 跟随家庭级孩子界面语言）。
    func setChildInterfaceLanguage(_ language: AppInterfaceLanguage?, for childId: UUID) {
        guard let index = children.firstIndex(where: { $0.id == childId }) else { return }
        children[index].interfaceLanguage = language
        persist()
    }

    /// 某孩子的生效界面语言：孩子档案优先，其次家庭级孩子界面语言，最后跟随家庭语言。
    func childInterfaceLanguage(for childId: UUID) -> AppInterfaceLanguage {
        children.first(where: { $0.id == childId })?.interfaceLanguage
            ?? settings.resolvedChildInterfaceLanguage
    }

    func setSchoolIntegration(_ integration: SchoolIntegrationSettings) {
        settings.schoolIntegration = integration
        persist()
    }

    /// 开关儿童语音朗读。
    func setReadAloud(_ enabled: Bool) {
        settings.readAloudEnabled = enabled
        persist()
    }

    /// 设置家庭地区（购书渠道等）。
    func setRegion(_ region: FamilyRegion) {
        settings.region = region
        persist()
    }

    /// 开关云端真人语音。
    func setCloudVoice(_ enabled: Bool) {
        settings.cloudVoiceEnabled = enabled
        persist()
    }

    /// 设置某孩子的学习内容语言（nil=跟随家庭）。
    func setContentLanguage(_ language: FamilyLanguage?, for childId: UUID) {
        guard let index = children.firstIndex(where: { $0.id == childId }) else { return }
        children[index].contentLanguage = language
        persist()
    }

    /// 某孩子的生效内容语言：孩子档案优先，缺省跟随家庭。
    func effectiveContentLanguage(for childId: UUID) -> FamilyLanguage {
        children.first(where: { $0.id == childId })?.contentLanguage ?? settings.language
    }

    /// 当前活跃孩子的生效内容语言。
    var activeContentLanguage: FamilyLanguage {
        effectiveContentLanguage(for: activeChildId)
    }

    /// 当前活跃孩子的生效界面语言（多孩子家庭每个孩子可独立设置）。
    var activeChildInterfaceLanguage: AppInterfaceLanguage {
        childInterfaceLanguage(for: activeChildId)
    }

    /// 开关某孩子的幼儿模式（大图标卡片界面 + 手动小喇叭点读）。
    func setPreReaderMode(_ enabled: Bool, for childId: UUID) {
        guard let index = children.firstIndex(where: { $0.id == childId }) else { return }
        children[index].preReaderMode = enabled
        persist()
    }

    /// 孩子设备使用云端绑定档案作为唯一身份。只同步家长可配置字段，
    /// 不覆盖孩子本机的小伙伴人格、聊天、阅读进度或成长记忆。
    func applyCloudChildProfile(_ profile: ChildDeviceProfileResponse, pendingPointDelta: Int = 0) {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let resolvedID = profile.clientRef.flatMap(UUID.init(uuidString:)) ?? activeChildId
        let age = profile.birthYear.map { max(3, min(18, currentYear - $0)) } ?? child.age
        if let index = children.firstIndex(where: { $0.id == resolvedID }) {
            children[index].name = Self.sanitizedChildName(profile.displayName)
            children[index].age = age
            children[index].preReaderMode = profile.preReaderMode
            children[index].interfaceLanguage = profile.interfaceLanguage
            children[index].contentLanguage = profile.contentLanguage
            if let balance = profile.growthPointBalance {
                children[index].rewardBalanceMinutes = max(0, balance + pendingPointDelta)
            }
            children[index].dailyLimitMinutes = min(
                Self.dailyLimitRange.upperBound,
                max(Self.dailyLimitRange.lowerBound, profile.dailyLimitMinutes ?? children[index].dailyLimitMinutes)
            )
        } else {
            var bound = child
            bound = ChildProfile(
                id: resolvedID,
                name: Self.sanitizedChildName(profile.displayName),
                age: age,
                dailyLimitMinutes: min(
                    Self.dailyLimitRange.upperBound,
                    max(Self.dailyLimitRange.lowerBound, profile.dailyLimitMinutes ?? bound.dailyLimitMinutes)
                ),
                rewardBalanceMinutes: bound.rewardBalanceMinutes,
                interests: bound.interests,
                parentNotes: nil,
                preReaderMode: profile.preReaderMode,
                contentLanguage: profile.contentLanguage,
                interfaceLanguage: profile.interfaceLanguage,
                aiCompanionName: bound.aiCompanionName,
                aiCompanionVoice: bound.aiCompanionVoice,
                aiCompanionPersonality: bound.aiCompanionPersonality,
                aiCompanionAvatarDescription: bound.aiCompanionAvatarDescription
            )
            children = [bound]
            if let balance = profile.growthPointBalance {
                children[0].rewardBalanceMinutes = max(0, balance + pendingPointDelta)
            }
        }
        activeChildId = resolvedID
        if let exchangePolicy = profile.exchangePolicy {
            setExchangePolicy(exchangePolicy, for: resolvedID)
        }
        persist()
    }

    /// Applies the cloud-owned child-home projection without touching device-only memories,
    /// proof files, reading history, AI personality, or Screen Time tokens.
    func applyCloudChildSurfaceProfile(
        _ surfaceChild: FamilyChildSurface.Child,
        pendingPointDelta: Int = 0,
        makeActive: Bool = true
    ) {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let resolvedID = surfaceChild.clientRef.flatMap(UUID.init(uuidString:)) ?? activeChildId
        let age = surfaceChild.birthYear.map { max(3, min(18, currentYear - $0)) } ?? child.age
        if let index = children.firstIndex(where: { $0.id == resolvedID }) {
            children[index].name = Self.sanitizedChildName(surfaceChild.displayName)
            children[index].age = age
            children[index].preReaderMode = surfaceChild.preReaderMode
            children[index].interfaceLanguage = surfaceChild.interfaceLanguage
            children[index].contentLanguage = surfaceChild.contentLanguage
            children[index].rewardBalanceMinutes = max(0, surfaceChild.growthPointBalance + pendingPointDelta)
        } else {
            let seed = child
            children.append(ChildProfile(
                id: resolvedID,
                name: Self.sanitizedChildName(surfaceChild.displayName),
                age: age,
                dailyLimitMinutes: seed.dailyLimitMinutes,
                rewardBalanceMinutes: max(0, surfaceChild.growthPointBalance + pendingPointDelta),
                interests: seed.interests,
                parentNotes: nil,
                preReaderMode: surfaceChild.preReaderMode,
                contentLanguage: surfaceChild.contentLanguage,
                interfaceLanguage: surfaceChild.interfaceLanguage,
                aiCompanionName: seed.aiCompanionName,
                aiCompanionVoice: seed.aiCompanionVoice,
                aiCompanionPersonality: seed.aiCompanionPersonality,
                aiCompanionAvatarDescription: seed.aiCompanionAvatarDescription
            ))
        }
        if makeActive {
            activeChildId = resolvedID
        }
        persist()
    }

    /// 家长设备合并云端孩子档案。只合并家庭共享设置；本机尚未上传的显式编辑
    /// 由 `preservingClientRefs` 保护，防止周期拉取把正在重试的修改覆盖掉。
    func applyCloudGuardianProfiles(
        _ snapshot: FamilyCloudSnapshot,
        preservingClientRefs: Set<String> = []
    ) {
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        let existingByID = Dictionary(uniqueKeysWithValues: children.map { ($0.id, $0) })
        var reconciledChildren: [ChildProfile] = []
        var reconciledPolicies = exchangePolicies

        for profile in snapshot.children {
            guard let rawClientRef = profile.clientRef else { continue }
            let clientRef = rawClientRef.lowercased()
            guard let childId = UUID(uuidString: clientRef) else { continue }

            if preservingClientRefs.contains(clientRef), let existing = existingByID[childId] {
                reconciledChildren.append(existing)
                continue
            }

            let existing = existingByID[childId]
            let age = profile.birthYear.map { max(3, min(18, currentYear - $0)) }
                ?? existing?.age
                ?? 8
            let dailyLimit = min(
                Self.dailyLimitRange.upperBound,
                max(Self.dailyLimitRange.lowerBound, profile.dailyLimitMinutes ?? existing?.dailyLimitMinutes ?? 60)
            )
            let merged = ChildProfile(
                id: childId,
                name: Self.sanitizedChildName(profile.displayName),
                age: age,
                dailyLimitMinutes: dailyLimit,
                rewardBalanceMinutes: max(0, profile.growthPointBalance ?? existing?.rewardBalanceMinutes ?? 0),
                interests: existing?.interests,
                parentNotes: existing?.parentNotes,
                preReaderMode: profile.preReaderMode ?? existing?.preReaderMode,
                contentLanguage: profile.contentLanguage ?? existing?.contentLanguage,
                interfaceLanguage: profile.interfaceLanguage ?? existing?.interfaceLanguage,
                aiCompanionName: existing?.aiCompanionName,
                aiCompanionVoice: existing?.aiCompanionVoice,
                aiCompanionPersonality: existing?.aiCompanionPersonality,
                aiCompanionAvatarDescription: existing?.aiCompanionAvatarDescription
            )
            reconciledChildren.append(merged)
            if let exchangePolicy = profile.exchangePolicy {
                reconciledPolicies[childId] = exchangePolicy
            }
        }

        // Family Cloud is authoritative once a guardian is linked. Only profiles with an
        // explicit persisted upload intent may survive outside the cloud snapshot. Keeping
        // arbitrary named local rows here would resurrect children archived on another device.
        let reconciledIDs = Set(reconciledChildren.map(\.id))
        let pendingLocalChildren = children.filter { child in
            guard !reconciledIDs.contains(child.id) else { return false }
            return preservingClientRefs.contains(child.id.uuidString.lowercased())
        }
        reconciledChildren.append(contentsOf: pendingLocalChildren)
        guard !reconciledChildren.isEmpty else { return }

        let validChildIDs = Set(reconciledChildren.map(\.id))
        let removedChildIDs = Set(children.map(\.id)).subtracting(validChildIDs)
        let resolvedPolicies = reconciledPolicies.filter { validChildIDs.contains($0.key) }
        let guardianMembers = familyNetwork.members.filter { $0.role != .child }
        let childMembers = reconciledChildren.map { child -> FamilyNetworkMember in
            if var existing = familyNetwork.members.first(where: { $0.childId == child.id }) {
                existing.displayName = child.name
                existing.role = .child
                existing.status = .active
                return existing
            }
            return FamilyNetworkMember(
                id: child.id,
                displayName: child.name,
                role: .child,
                kinshipLabel: "孩子",
                childId: child.id,
                status: .active,
                joinedAt: Date()
            )
        }

        let resolvedActiveChildID = validChildIDs.contains(activeChildId)
            ? activeChildId
            : reconciledChildren[0].id
        let changed = children != reconciledChildren
            || exchangePolicies != resolvedPolicies
            || activeChildId != resolvedActiveChildID
            || familyNetwork.members != guardianMembers + childMembers
            || familyNetwork.devices.contains { binding in
                binding.childId.map { !validChildIDs.contains($0) } ?? false
            }
            || familyNetwork.invitations.contains { invite in
                invite.childId.map { !validChildIDs.contains($0) } ?? false
            }
        guard changed else { return }

        children = reconciledChildren
        exchangePolicies = resolvedPolicies
        activeChildId = resolvedActiveChildID
        familyNetwork.members = guardianMembers + childMembers
        familyNetwork.devices.removeAll { binding in
            binding.childId.map { !validChildIDs.contains($0) } ?? false
        }
        familyNetwork.invitations.removeAll { invite in
            invite.childId.map { !validChildIDs.contains($0) } ?? false
        }
        for index in assignments.indices where removedChildIDs.contains(assignments[index].childId) {
            switch assignments[index].status {
            case .approved, .cancelled:
                break
            case .open, .submitted, .rejected:
                assignments[index].status = .cancelled
            }
        }
        persist()
    }

    /// 用云端不可变积分账本的投影覆盖本机缓存。pendingDelta 代表尚未上传的本机消费，
    /// 因而即使刷新发生在离线队列完成前，UI 也不会把已经花掉的积分短暂加回来。
    func applyCloudGrowthPointBalance(_ balance: Int, pendingDelta: Int = 0, for childId: UUID? = nil) {
        let target = childId ?? activeChildId
        guard let index = children.firstIndex(where: { $0.id == target }) else { return }
        let resolved = max(0, balance + pendingDelta)
        guard children[index].rewardBalanceMinutes != resolved else { return }
        children[index].rewardBalanceMinutes = resolved
        persist()
    }

    /// 历史云任务如果没有可交付电子书，只能作为取消墓碑存在，不能继续显示给孩子。
    func quarantineUnavailableCloudTasks(_ tasks: [FamilyCloudTask]) {
        let ids = Set(tasks.compactMap { UUID(uuidString: $0.clientRef) })
        guard !ids.isEmpty else { return }
        var changed = false
        for index in assignments.indices where ids.contains(assignments[index].id) {
            if assignments[index].status != .cancelled {
                assignments[index].status = .cancelled
                changed = true
            }
        }
        if changed { persist() }
    }

    /// 孩子自定义 AI 小伙伴：只保存本机偏好，不上传、不影响家长安全边界。
    @discardableResult
    func setAICompanionProfile(
        name: String?,
        voice: AICompanionVoiceStyle,
        personality: AICompanionPersonalityStyle,
        avatarDescription: String? = nil,
        for childId: UUID? = nil
    ) -> Bool {
        let targetChildId = childId ?? activeChildId
        guard let index = children.firstIndex(where: { $0.id == targetChildId }) else { return false }
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAvatar = (avatarDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        children[index].aiCompanionName = trimmed.isEmpty ? nil : String(trimmed.prefix(12))
        children[index].aiCompanionVoice = voice
        children[index].aiCompanionPersonality = personality
        children[index].aiCompanionAvatarDescription = trimmedAvatar.isEmpty ? nil : String(trimmedAvatar.prefix(80))
        persist()
        return true
    }

    /// 当前活跃孩子是否处于幼儿模式。
    var isPreReaderActive: Bool { child.isPreReader }

    /// 朗读功能是否生效：家庭开关 或 当前孩子是幼儿模式。
    var isSpeechEnabled: Bool { settings.resolvedReadAloud || isPreReaderActive }

    /// 家长移除孩子：同时清理其任务、成长包步骤与证明照片。至少保留一个孩子。
    @discardableResult
    func removeChild(_ childId: UUID) -> Bool {
        guard children.count > 1, let index = children.firstIndex(where: { $0.id == childId }) else { return false }

        let removedAssignments = assignments.filter { $0.childId == childId }
        for assignment in removedAssignments {
            if let fileName = assignment.proof.photoFileName {
                ProofPhotoStore.shared.delete(fileName: fileName)
            }
            if let audio = assignment.proof.audioFileName {
                ProofVoiceStore.shared.delete(fileName: audio)
            }
            growthPack.steps.removeAll { $0.assignmentId == assignment.id }
        }
        assignments.removeAll { $0.childId == childId }
        for (offset, _) in growthPack.steps.enumerated() {
            growthPack.steps[offset].order = offset + 1
        }
        children.remove(at: index)
        familyNetwork.members.removeAll { $0.childId == childId }
        familyNetwork.devices.removeAll { $0.childId == childId }
        familyNetwork.invitations.removeAll { $0.childId == childId }
        if activeChildId == childId {
            activeChildId = children[0].id
        }
        persist()
        return true
    }

    /// 按 id 找孩子昵称（审批列表等展示用）。
    func childName(for childId: UUID) -> String {
        children.first(where: { $0.id == childId })?.name ?? "孩子"
    }

    var hasMultipleChildren: Bool { children.count > 1 }

    /// 状态变更后落盘。无持久化端口时是空操作。
    func persist() {
        persistence?.save(snapshot)
    }

    // MARK: - 派生视图

    /// 孩子端今日任务展示列表（只看当前活跃孩子的任务）。
    var todayTasks: [TodayTask] {
        assignments
            .filter { $0.childId == activeChildId }
            .filter { $0.status != .cancelled }
            .map { assignment in
                TodayTask(
                    id: assignment.id,
                    title: assignment.task.title,
                    category: assignment.task.category,
                    rewardMinutes: assignment.task.rewardMinutes,
                    status: assignment.status,
                    requiredProof: assignment.task.requiredProof,
                    proofStatus: assignment.proof.status
                )
            }
    }

    /// 当前活跃孩子的成长积分余额快照：可用 = 该孩子余额，
    /// 待批准 = 该孩子已提交任务的奖励合计，累计 = 该孩子历史发放合计。
    var creditBalance: CreditBalance {
        creditBalance(for: activeChildId)
    }

    /// 指定孩子的成长积分余额快照（多孩子分账）。
    func creditBalance(for childId: UUID) -> CreditBalance {
        let pending = assignments
            .filter { $0.childId == childId && $0.status == .submitted }
            .reduce(0) { $0 + $1.task.rewardMinutes }
        let lifetime = rewards
            .filter { $0.childId == childId }
            .reduce(0) { $0 + $1.minutes }
        return CreditBalance(
            availableMinutes: children.first(where: { $0.id == childId })?.rewardBalanceMinutes ?? 0,
            pendingMinutes: pending,
            lifetimeEarnedMinutes: lifetime
        )
    }

    /// 推导某个成长包步骤的运行态进度：上一步未批准则锁定。
    func progress(for step: GrowthPackStep) -> GrowthStepProgress {
        guard let assignment = assignments.first(where: { $0.id == step.assignmentId }) else {
            return .locked
        }

        if assignment.status == .cancelled {
            return .locked
        }

        if assignment.status == .approved {
            return .approved
        }

        if !isStepUnlocked(step) {
            return .locked
        }

        return assignment.status == .submitted ? .submitted : .active
    }

    /// 某个孩子的成长包步骤（多孩子时各自只看自己的序列）。
    func steps(for childId: UUID) -> [GrowthPackStep] {
        let childAssignmentIds = Set(assignments
            .filter { $0.childId == childId && $0.status != .cancelled }
            .map(\.id))
        return growthPack.steps.filter { childAssignmentIds.contains($0.assignmentId) }
    }

    /// 自由模式（默认）下所有任务永远解锁，孩子任意选择；
    /// 只有包显式开启 sequential 时才按同一孩子的步骤序列逐个解锁。
    func isStepUnlocked(_ step: GrowthPackStep) -> Bool {
        guard growthPack.resolvedSequencing == .sequential else { return true }
        guard let owner = assignments.first(where: { $0.id == step.assignmentId }) else { return true }
        let sequence = steps(for: owner.childId)
        guard let index = sequence.firstIndex(where: { $0.id == step.id }), index > 0 else {
            return true
        }
        let previous = sequence[index - 1]
        return assignments.first(where: { $0.id == previous.assignmentId })?.status == .approved
    }

    /// 当前活跃孩子「今天完成 N/M」进度。
    var todayCompletion: (done: Int, total: Int) {
        let mine = assignments.filter { $0.childId == activeChildId && $0.status != .cancelled }
        return (mine.filter { $0.status == .approved }.count, mine.count)
    }

    func assignment(for step: GrowthPackStep) -> TaskAssignment? {
        assignments.first(where: { $0.id == step.assignmentId })
    }

    // MARK: - 首次设置

    /// 是否仍是未动过的默认种子（没有提交、没有奖励、没有事件）。
    var looksLikeFreshSeed: Bool {
        rewards.isEmpty && events.isEmpty && assignments.allSatisfy { $0.status == .open && $0.proof.status == .empty }
    }

    /// 家庭每日解锁上限的硬边界：最低 15 分钟，最高 12 小时（720 分钟）。
    /// 上限是平台级规则（成长包平台化 v2 rewardPolicy.dailyCapRef=family_policy），
    /// 任何包和任何家长设置都不能超过。
    static let dailyLimitRange = 15...720

    /// 孩子昵称上限：与 AI 伙伴名同口径（12 字），防止超长名字顶爆「你好，X」大标题。
    static let childNameMaxLength = 12

    /// 昵称清洗：去首尾空白并截断到上限。空字符串原样返回，由调用方判空。
    static func sanitizedChildName(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(childNameMaxLength))
    }

    /// 家长首次设置：孩子昵称、每日上限，并决定是否保留推荐任务。
    /// 不保留时清空任务与成长包步骤，由家长从空白开始布置。
    func applyFamilySetup(childName: String, dailyLimitMinutes: Int, keepStarterTasks: Bool) {
        let trimmed = Self.sanitizedChildName(childName)
        if !trimmed.isEmpty {
            child.name = trimmed
            if let memberIndex = familyNetwork.members.firstIndex(where: { $0.childId == activeChildId }) {
                familyNetwork.members[memberIndex].displayName = trimmed
            }
            if familyNetwork.familyName.hasSuffix("的家庭") {
                familyNetwork.familyName = "\(trimmed)的家庭"
            }
        }
        child.dailyLimitMinutes = min(Self.dailyLimitRange.upperBound, max(Self.dailyLimitRange.lowerBound, dailyLimitMinutes))

        if !keepStarterTasks {
            assignments.removeAll()
            growthPack.steps.removeAll()
        }
        persist()
    }

    // MARK: - 家长布置 / 编辑 / 删除任务

    /// 家长布置一个新任务：追加到今日任务，并在成长包末尾加一个对应步骤。
    @discardableResult
    func assignNewTask(
        title: String,
        instructions: String,
        category: TaskCategory,
        difficulty: TaskDifficulty = .easy,
        rewardMinutes: Int,
        requiredProof: ProofKind,
        adultSupervisionRequired: Bool = false,
        reading: ReadingSpec? = nil,
        video: VideoSpec? = nil,
        verification: TaskVerificationSpec? = nil,
        creative: CreativeTaskSpec? = nil,
        localizedContent: [TaskLocalizedContent]? = nil,
        childId: UUID? = nil
    ) -> TaskAssignment? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, rewardMinutes > 0 else { return nil }
        let targetChildId = childId ?? activeChildId
        guard children.contains(where: { $0.id == targetChildId }) else { return nil }

        let template = TaskTemplate(
            id: UUID(),
            title: trimmedTitle,
            category: category,
            difficulty: difficulty,
            rewardMinutes: rewardMinutes,
            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
            requiredProof: requiredProof,
            adultSupervisionRequired: adultSupervisionRequired ? true : nil,
            reading: reading,
            video: video,
            verification: verification,
            creative: creative,
            localizedContent: localizedContent
        )
        let assignment = TaskAssignment(
            id: UUID(),
            childId: targetChildId,
            task: template,
            date: Date(),
            status: .open,
            proof: .empty
        )
        assignments.append(assignment)

        let nextOrder = (growthPack.steps.map(\.order).max() ?? 0) + 1
        growthPack.steps.append(
            GrowthPackStep(
                id: UUID(),
                order: nextOrder,
                title: template.title,
                detail: template.instructions,
                assignmentId: assignment.id,
                rewardMinutes: template.rewardMinutes
            )
        )

        appendEvent(
            FamilyEvent(
                id: UUID(),
                kind: .taskAssigned,
                title: template.title,
                detail: "\(currentGuardianName)布置给\(childName(for: targetChildId))，完成后奖励 \(template.rewardMinutes) 成长积分。",
                minutes: nil,
                createdAt: Date()
            )
        )
        persist()
        return assignment
    }

    /// 任务是否还允许家长编辑/删除：孩子已提交或已批准的任务不可改，保证审核与账目可信。
    func canParentModify(_ assignment: TaskAssignment) -> Bool {
        assignment.status == .open || assignment.status == .rejected
    }

    /// 任务是否允许撤销：已结算和已撤销的任务不可再次撤销。
    func canCancelAssignment(_ assignment: TaskAssignment) -> Bool {
        assignment.status != .approved && assignment.status != .cancelled
    }

    /// 家长从任务包库批量布置：每条模板生成一个今日任务和成长包步骤。
    /// 只写入一条汇总事件，避免刷屏。返回实际布置的任务数。
    /// `eventTitle` 可覆盖汇总事件标题（如「首日晚间节律包」），默认用包类型名。
    /// `usePackDefaultPoints` 为 false 时保留模板自己的积分差异，适合节律包这类精心配比的计划。
    @discardableResult
    func assignPackTemplates(
        _ templates: [PackTaskTemplate],
        packType: PackType,
        childId: UUID? = nil,
        eventTitle: String? = nil,
        usePackDefaultPoints: Bool = true
    ) -> Int {
        guard !templates.isEmpty else { return 0 }
        let targetChildId = childId ?? activeChildId
        guard children.contains(where: { $0.id == targetChildId }) else { return 0 }

        var assignedCount = 0
        for template in templates {
            let resolvedInstructions = instructionsForPackTemplate(template)
            let taskTemplate = TaskTemplate(
                id: UUID(),
                title: template.title,
                category: template.category,
                difficulty: .easy,
                rewardMinutes: usePackDefaultPoints && !template.isCustom
                    ? (defaultPoints(for: packType) ?? template.suggestedRewardMinutes)
                    : template.suggestedRewardMinutes,
                instructions: resolvedInstructions,
                requiredProof: template.requiredProof,
                adultSupervisionRequired: template.adultSupervisionRequired ? true : nil,
                reading: template.reading,
                creative: template.creative,
                packType: packType
            )
            let assignment = TaskAssignment(
                id: UUID(),
                childId: targetChildId,
                task: taskTemplate,
                date: Date(),
                status: .open,
                proof: .empty
            )
            assignments.append(assignment)

            let nextOrder = (growthPack.steps.map(\.order).max() ?? 0) + 1
            growthPack.steps.append(
                GrowthPackStep(
                    id: UUID(),
                    order: nextOrder,
                    title: taskTemplate.title,
                    detail: taskTemplate.instructions,
                    assignmentId: assignment.id,
                    rewardMinutes: taskTemplate.rewardMinutes
                )
            )
            assignedCount += 1
        }

        appendEvent(
            FamilyEvent(
                id: UUID(),
                kind: .taskAssigned,
                title: eventTitle ?? packType.label,
                detail: "从任务包库给\(childName(for: targetChildId))布置了 \(assignedCount) 个任务。",
                minutes: nil,
                createdAt: Date()
            )
        )
        persist()
        return assignedCount
    }

    /// 今天是否已给该孩子布置过「首日晚间节律包」（按模板标题匹配当天任务）。
    /// 用于防止家长一键按钮重复点击造成同一晚 8 个任务。
    func hasAssignedFirstEveningRoutinePlan(childId: UUID? = nil, on date: Date = Date()) -> Bool {
        let targetChildId = childId ?? activeChildId
        let planTitles = Set(FirstEveningRoutinePlan.templates.map(\.title))
        return assignments.contains {
            $0.childId == targetChildId
                && planTitles.contains($0.task.title)
                && Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }

    /// 一键布置「首日晚间节律包」：家务/阅读/户外/睡前放手机各 1 件。
    /// 同一天对同一孩子重复调用是 no-op（返回 0），成功时返回 4。
    @discardableResult
    func assignFirstEveningRoutinePlan(childId: UUID? = nil, now: Date = Date()) -> Int {
        let targetChildId = childId ?? activeChildId
        guard children.contains(where: { $0.id == targetChildId }) else { return 0 }
        guard !hasAssignedFirstEveningRoutinePlan(childId: targetChildId, on: now) else { return 0 }
        return assignPackTemplates(
            FirstEveningRoutinePlan.templates,
            packType: FirstEveningRoutinePlan.packType,
            childId: targetChildId,
            eventTitle: FirstEveningRoutinePlan.title,
            usePackDefaultPoints: false
        )
    }

    /// 布置 AI 生成的任务草稿（家长已勾选确认）。返回布置数量。
    @discardableResult
    func assignGeneratedDrafts(_ drafts: [GeneratedTaskDraft], packType: PackType, childId: UUID? = nil) -> Int {
        let templates = drafts.map { draft in
            PackTaskTemplate(
                id: draft.id.uuidString,
                title: draft.title,
                instructions: draft.instructions,
                category: draft.category,
                suggestedRewardMinutes: draft.rewardPoints,
                requiredProof: draft.requiredProof,
                adultSupervisionRequired: draft.adultSupervisionRequired,
                reading: draft.reading,
                creative: nil
            )
        }
        return assignPackTemplates(templates, packType: packType, childId: childId)
    }

    /// 家长编辑任务内容。仅 open / rejected 状态可编辑；同步更新成长包对应步骤。
    @discardableResult
    func updateTask(
        assignmentId: UUID,
        title: String,
        instructions: String,
        category: TaskCategory,
        rewardMinutes: Int,
        requiredProof: ProofKind,
        adultSupervisionRequired: Bool,
        reading: ReadingSpec?,
        video: VideoSpec?,
        creative: CreativeTaskSpec? = nil,
        localizedContent: [TaskLocalizedContent]? = nil
    ) -> Bool {
        guard let index = assignments.firstIndex(where: { $0.id == assignmentId }),
              canParentModify(assignments[index]) else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, rewardMinutes > 0 else { return false }

        assignments[index].task.title = trimmedTitle
        assignments[index].task.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        assignments[index].task.category = category
        assignments[index].task.rewardMinutes = rewardMinutes
        assignments[index].task.requiredProof = requiredProof
        assignments[index].task.adultSupervisionRequired = adultSupervisionRequired ? true : nil
        assignments[index].task.reading = reading
        assignments[index].task.video = video
        assignments[index].task.creative = creative
        if let localizedContent {
            assignments[index].task.localizedContent = localizedContent
        }

        if let stepIndex = growthPack.steps.firstIndex(where: { $0.assignmentId == assignmentId }) {
            growthPack.steps[stepIndex].title = trimmedTitle
            growthPack.steps[stepIndex].detail = assignments[index].task.instructions
            growthPack.steps[stepIndex].rewardMinutes = rewardMinutes
        }
        persist()
        return true
    }

    /// 只更新展示翻译，不改变任务目标、状态、奖励、证明或结算语义。
    @discardableResult
    func setTaskLocalizedContent(
        assignmentId: UUID,
        content: TaskLocalizedContent
    ) -> Bool {
        guard let index = assignments.firstIndex(where: { $0.id == assignmentId }) else { return false }
        var values = assignments[index].task.localizedContent ?? []
        values.removeAll { $0.language == content.language }
        values.append(content)
        assignments[index].task.localizedContent = values
        persist()
        return true
    }

    /// 家长删除任务。仅 open / rejected 状态可删；同步移除成长包步骤并压缩顺序。
    @discardableResult
    func removeAssignment(_ assignmentId: UUID) -> Bool {
        guard let index = assignments.firstIndex(where: { $0.id == assignmentId }),
              canParentModify(assignments[index]) else { return false }

        if let audio = assignments[index].proof.audioFileName {
            ProofVoiceStore.shared.delete(fileName: audio)
        }
        assignments.remove(at: index)
        growthPack.steps.removeAll { $0.assignmentId == assignmentId }
        for (offset, _) in growthPack.steps.enumerated() {
            growthPack.steps[offset].order = offset + 1
        }
        persist()
        return true
    }

    /// 撤销尚未结算的任务。不同于删除，撤销保留本地审计事件和历史状态，但不再出现在孩子今日任务流里。
    @discardableResult
    func cancelAssignment(_ assignmentId: UUID, actor: TaskCancellationActor) -> Bool {
        guard let index = assignments.firstIndex(where: { $0.id == assignmentId }),
              canCancelAssignment(assignments[index]) else { return false }

        assignments[index].status = .cancelled
        assignments[index].rejectionReason = nil
        assignments[index].aiReview = nil

        let title = assignments[index].task.title
        let ownerName = childName(for: assignments[index].childId)
        let detail: String
        switch actor {
        case .child:
            detail = "\(ownerName)撤销了这项任务，未获得成长积分。"
        case .guardian:
            detail = "\(currentGuardianName)撤销了布置给\(ownerName)的任务，未发放成长积分。"
        }

        appendEvent(
            FamilyEvent(
                id: UUID(),
                kind: .taskCancelled,
                title: title,
                detail: detail,
                minutes: nil,
                createdAt: Date()
            )
        )
        persist()
        return true
    }

    /// 孩子在家长确认前撤回提交，回到可编辑证明状态。
    @discardableResult
    func withdrawSubmittedAssignment(_ assignmentId: UUID) -> Bool {
        guard let index = assignments.firstIndex(where: { $0.id == assignmentId }),
              assignments[index].status == .submitted else { return false }
        assignments[index].status = .open
        assignments[index].proof.status = .drafting
        assignments[index].aiReview = nil
        appendEvent(
            FamilyEvent(
                id: UUID(),
                kind: .taskCancelled,
                title: assignments[index].task.title,
                detail: "\(childName(for: assignments[index].childId))撤回了提交，准备重新补证明。",
                minutes: nil,
                createdAt: Date()
            )
        )
        persist()
        return true
    }

    // MARK: - 状态变更

    /// 主提交入口：写入证明草稿并进入等待家长批准。
    /// 提交时同步生成一份本地确定性 AI 初评（仅供家长参考，绝不自动批准、不发成长积分）；
    /// 真实 AI provider 就绪时，云端初评稍后经 attachAIReview 覆盖本地版本。
    @discardableResult
    func submit(_ assignment: TaskAssignment, proof: ProofDraft) -> Bool {
        guard proof.hasContent,
              let index = assignments.firstIndex(where: { $0.id == assignment.id }),
              (assignments[index].status == .open || assignments[index].status == .rejected) else { return false }
        updateAssignment(assignment.id) { item in
            var submitted = proof
            submitted.status = .submitted
            item.proof = submitted
            item.status = .submitted
            item.aiReview = AIProofReviewer.localReview(
                task: item.task,
                childText: submitted.text,
                proofKind: submitted.kind,
                hasLocalPhoto: submitted.photoFileName != nil,
                childLanguage: childInterfaceLanguage(for: item.childId)
            )
        }
        persist()
        return true
    }

    /// 文本证明便捷提交，保留旧闭环可用。
    @discardableResult
    func submit(_ assignment: TaskAssignment, text: String) -> Bool {
        let proof = ProofDraft(kind: .text, text: text, photoPlaceholderName: nil, status: .submitted)
        return submit(assignment, proof: proof)
    }

    /// 家长批准任务并发放成长积分。
    /// 奖励按任务来源幂等；即使云冲突把状态恢复为 submitted，再次审核也不会重复入账。
    @discardableResult
    func approve(_ assignment: TaskAssignment) -> RewardGrant? {
        guard let index = assignments.firstIndex(where: { $0.id == assignment.id }) else { return nil }
        guard assignments[index].status != .approved else { return nil }
        guard assignments[index].status != .cancelled else { return nil }

        // 多孩子分账：奖励必须记到任务所属孩子头上，而不是当前活跃孩子。
        let ownerChildId = assignments[index].childId
        guard let ownerIndex = children.firstIndex(where: { $0.id == ownerChildId }) else { return nil }

        assignments[index].status = .approved
        assignments[index].rejectionReason = nil

        guard !rewards.contains(where: { $0.sourceAssignmentId == assignment.id }) else {
            persist()
            return nil
        }

        let reward = RewardGrant(
            id: UUID(),
            childId: ownerChildId,
            minutes: assignments[index].task.rewardMinutes,
            reason: assignments[index].task.title,
            grantedAt: Date(),
            expiresAt: nil,
            sourceAssignmentId: assignment.id
        )

        rewards.insert(reward, at: 0)
        children[ownerIndex].rewardBalanceMinutes += reward.minutes

        // 千小时徽章体系：学习类任务批准后累计学科学时。
        if let subject = LearningSubject.from(task: assignments[index].task) {
            let minutes = assignments[index].task.reading?.minMinutes
                ?? assignments[index].task.video?.minWatchMinutes
                ?? assignments[index].task.rewardMinutes
            addStudyMinutes(minutes, subject: subject, childId: ownerChildId)
        }

        appendEvent(
            FamilyEvent(
                id: UUID(),
                kind: .taskApproved,
                title: assignments[index].task.title,
                detail: "\(currentGuardianName)已批准，给\(children[ownerIndex].name)发放 \(reward.minutes) 成长积分。",
                minutes: reward.minutes,
                createdAt: Date()
            )
        )
        persist()
        return reward
    }

    /// 旧快照没有保存奖励来源。仅当孩子、标题、积分和时间关系能唯一对应到一个任务时回填，
    /// 遇到同名同分的重复任务就保持 nil，避免把两个真实任务误合并。
    @discardableResult
    private func migrateLegacyRewardSources() -> Bool {
        var didMigrate = false
        var claimedAssignmentIDs = Set(rewards.compactMap(\.sourceAssignmentId))

        for rewardIndex in rewards.indices where rewards[rewardIndex].sourceAssignmentId == nil {
            let reward = rewards[rewardIndex]
            let candidates = assignments.filter { assignment in
                guard !claimedAssignmentIDs.contains(assignment.id),
                      assignment.childId == reward.childId,
                      assignment.task.rewardMinutes == reward.minutes,
                      assignment.task.title == reward.reason,
                      assignment.status == .approved || assignment.status == .submitted
                else { return false }

                // A reward cannot predate the task that earned it. Allow a small clock-skew margin
                // for legacy snapshots written by devices whose clocks were not perfectly aligned.
                return reward.grantedAt >= assignment.date.addingTimeInterval(-300)
            }

            guard candidates.count == 1, let assignment = candidates.first else { continue }
            rewards[rewardIndex].sourceAssignmentId = assignment.id
            claimedAssignmentIDs.insert(assignment.id)
            didMigrate = true
        }

        return didMigrate
    }

    /// 家长驳回任务并记录原因；任务回到草稿态供孩子重做。驳回绝不发放任何成长积分。
    func reject(_ assignment: TaskAssignment, reason: RejectionReason = .other) {
        guard let index = assignments.firstIndex(where: { $0.id == assignment.id }) else { return }
        guard assignments[index].status != .approved && assignments[index].status != .cancelled else { return }

        assignments[index].status = .rejected
        assignments[index].proof.status = .drafting
        assignments[index].rejectionReason = reason

        appendEvent(
            FamilyEvent(
                id: UUID(),
                kind: .taskRejected,
                title: assignments[index].task.title,
                detail: "已驳回：\(reason.label)。未发放成长积分。",
                minutes: nil,
                createdAt: Date()
            )
        )
        persist()
    }

    // MARK: - 成长积分与零花钱经济（P3）

    /// 取某孩子的兑换机制；未设置时用默认策略。
    func policy(for childId: UUID) -> FamilyExchangePolicy {
        exchangePolicies[childId] ?? .default
    }

    /// 家长设定某孩子的兑换机制；随后立即检查是否需要补入本月底薪。
    func setExchangePolicy(_ policy: FamilyExchangePolicy, for childId: UUID) {
        var cleaned = policy
        cleaned.baseMonthlyAllowance = min(100_000, max(0, policy.baseMonthlyAllowance))
        cleaned.allowanceDayOfMonth = min(28, max(1, policy.allowanceDayOfMonth))
        cleaned.customScreenExchangeMinutes = min(720, max(1, policy.resolvedScreenExchangeMinutes))
        if let points = policy.customScreenPointsPer15Minutes {
            cleaned.customScreenPointsPer15Minutes = min(100_000, max(1, points))
        }
        cleaned.pointsPerCurrencyUnit = min(100_000, max(1, policy.pointsPerCurrencyUnit))
        if let cap = policy.monthlyPocketMoneyCap {
            cleaned.monthlyPocketMoneyCap = cap <= 0 ? nil : min(1_000_000, cap)
        }
        exchangePolicies[childId] = cleaned
        creditMonthlyAllowancesIfNeeded()
        persist()
    }

    private static func monthKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func weekKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
    }

    /// 基础零花钱自动入账（幂等：每孩子每周期最多一条）。
    /// 月周期到入账日之后才入账；周周期每个 ISO 周入一次。
    /// App 启动与家长改策略时调用。
    func creditMonthlyAllowancesIfNeeded(now: Date = Date()) {
        var changed = false

        for child in children {
            let policy = policy(for: child.id)
            guard policy.baseMonthlyAllowance > 0 else { continue }

            let key: String
            switch policy.resolvedCycle {
            case .monthly:
                key = Self.monthKey(for: now)
                let dayOfMonth = Calendar.current.component(.day, from: now)
                guard dayOfMonth >= policy.allowanceDayOfMonth else { continue }
            case .weekly:
                key = Self.weekKey(for: now)
            case .daily:
                key = Self.dayKey(for: now)
            }
            guard allowanceCursors[child.id] != key else { continue }

            moneyLedger.insert(
                MoneyLedgerEntry(
                    id: UUID(),
                    childId: child.id,
                    kind: .baseAllowance,
                    amount: policy.baseMonthlyAllowance,
                    pointsSpent: nil,
                    status: .pendingPayout,
                    note: ["本月基础零花钱", "本周基础零花钱", "今日基础零花钱"][[AllowanceCycle.monthly, .weekly, .daily].firstIndex(of: policy.resolvedCycle) ?? 0],
                    createdAt: now
                ),
                at: 0
            )
            allowanceCursors[child.id] = key
            changed = true
        }
        if changed { persist() }
    }

    // MARK: - 愿望清单

    /// 孩子提交愿望。
    @discardableResult
    func submitWish(title: String, note: String = "", childId: UUID? = nil) -> WishListItem? {
        let targetChildId = childId ?? activeChildId
        guard children.contains(where: { $0.id == targetChildId }) else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let wish = WishListItem(
            id: UUID(),
            childId: targetChildId,
            title: trimmed,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .proposed,
            pricePoints: nil,
            createdAt: Date()
        )
        wishes.insert(wish, at: 0)
        persist()
        return wish
    }

    /// 家长给愿望定成长积分价格。
    @discardableResult
    func priceWish(_ wishId: UUID, points: Int) -> Bool {
        guard let index = wishes.firstIndex(where: { $0.id == wishId }),
              wishes[index].status == .proposed, points > 0 else { return false }
        wishes[index].pricePoints = min(1_000_000, points)
        wishes[index].status = .priced
        persist()
        return true
    }

    /// 家长驳回愿望。
    @discardableResult
    func rejectWish(_ wishId: UUID) -> Bool {
        guard let index = wishes.firstIndex(where: { $0.id == wishId }),
              wishes[index].status == .proposed || wishes[index].status == .priced else { return false }
        wishes[index].status = .rejected
        persist()
        return true
    }

    /// 孩子兑换已定价的愿望：扣分后等家长兑现。
    @discardableResult
    func redeemWish(_ wishId: UUID) -> Bool {
        guard let index = wishes.firstIndex(where: { $0.id == wishId }),
              wishes[index].status == .priced,
              let price = wishes[index].pricePoints,
              let childIndex = children.firstIndex(where: { $0.id == wishes[index].childId }),
              children[childIndex].rewardBalanceMinutes >= price else { return false }
        children[childIndex].rewardBalanceMinutes -= price
        wishes[index].status = .redeemed
        appendEvent(
            FamilyEvent(
                id: UUID(),
                kind: .taskAssigned,
                title: "\(children[childIndex].name)兑换了愿望",
                detail: "用 \(price) 成长积分兑换「\(wishes[index].title)」，等大人兑现。",
                minutes: nil,
                createdAt: Date()
            )
        )
        persist()
        return true
    }

    /// 家长兑现愿望后划账。
    @discardableResult
    func markWishFulfilled(_ wishId: UUID) -> Bool {
        guard let index = wishes.firstIndex(where: { $0.id == wishId }),
              wishes[index].status == .redeemed else { return false }
        wishes[index].status = .fulfilled
        persist()
        return true
    }

    // MARK: - 每包默认成长积分

    /// 家长设定某个包的默认分值（模板与 AI 生成布置时统一采用）；0 = 清除。
    func setPackDefaultPoints(_ points: Int, for packType: PackType) {
        if points <= 0 {
            packDefaultPoints[packType.rawValue] = nil
        } else {
            packDefaultPoints[packType.rawValue] = min(60, max(5, points))
        }
        persist()
    }

    func defaultPoints(for packType: PackType) -> Int? {
        packDefaultPoints[packType.rawValue]
    }

    // MARK: - 家庭自定义任务包模板

    func templates(for packType: PackType) -> [PackTaskTemplate] {
        let official = ParentPackTemplateLibrary.group(for: packType)?.templates ?? []
        return official + customTemplates(for: packType)
    }

    func customTemplates(for packType: PackType) -> [PackTaskTemplate] {
        customPackTemplates[packType.rawValue] ?? []
    }

    @discardableResult
    func addCustomPackTemplate(
        packType: PackType,
        title: String,
        instructions: String,
        expectedMinutes: Int,
        rewardPoints: Int,
        requiredProof: ProofKind,
        adultSupervisionRequired: Bool
    ) -> PackTaskTemplate? {
        guard packType.supportsCustomTemplates else { return nil }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let template = PackTaskTemplate(
            id: "custom-\(UUID().uuidString)",
            title: trimmedTitle,
            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
            category: packType.defaultCustomCategory,
            suggestedRewardMinutes: min(60, max(5, rewardPoints)),
            expectedMinutes: min(180, max(5, expectedMinutes)),
            requiredProof: requiredProof,
            adultSupervisionRequired: adultSupervisionRequired
        )
        customPackTemplates[packType.rawValue, default: []].insert(template, at: 0)
        persist()
        return template
    }

    @discardableResult
    func removeCustomPackTemplate(id: String, from packType: PackType) -> Bool {
        guard var templates = customPackTemplates[packType.rawValue],
              let index = templates.firstIndex(where: { $0.id == id && $0.isCustom }) else {
            return false
        }
        templates.remove(at: index)
        customPackTemplates[packType.rawValue] = templates.isEmpty ? nil : templates
        persist()
        return true
    }

    private func instructionsForPackTemplate(_ template: PackTaskTemplate) -> String {
        var lines: [String] = []
        if let expectedMinutes = template.expectedMinutes {
            lines.append("建议用时：\(expectedMinutes) 分钟。")
        }
        let instructions = template.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            lines.append(instructions)
        }
        return lines.joined(separator: "\n")
    }

    /// 某孩子的零花钱概览：待发放 / 已发放累计 / 本月兑换额（用于月上限判断）。
    func pocketMoneySummary(for childId: UUID, now: Date = Date()) -> (pendingPayout: Int, paidTotal: Int, thisMonthExchanged: Int) {
        let mine = moneyLedger.filter { $0.childId == childId }
        let pending = mine.filter { $0.status == .pendingPayout }.reduce(0) { $0 + $1.amount }
        let paid = mine.filter { $0.status == .paid }.reduce(0) { $0 + $1.amount }
        let key = Self.monthKey(for: now)
        let exchanged = mine
            .filter { $0.kind == .creditExchange && $0.status != .rejected && Self.monthKey(for: $0.createdAt) == key }
            .reduce(0) { $0 + $1.amount }
        return (pending, paid, exchanged)
    }

    /// 成长积分兑换零花钱的只读阻塞原因；返回 nil 表示当前可提交兑换申请。
    enum PocketMoneyExchangeBlocker: Equatable {
        case unknownChild
        case belowMinimum(requiredPoints: Int)
        case insufficientCredits(requiredPoints: Int, availablePoints: Int)
        case monthlyCapReached(cap: Int, alreadyExchanged: Int)
    }

    func pocketMoneyExchangeBlocker(
        points: Int,
        childId: UUID? = nil,
        now: Date = Date()
    ) -> PocketMoneyExchangeBlocker? {
        let targetChildId = childId ?? activeChildId
        guard let child = children.first(where: { $0.id == targetChildId }) else {
            return .unknownChild
        }
        let policy = policy(for: targetChildId)
        let amount = points / policy.pointsPerCurrencyUnit
        guard amount >= 1 else {
            return .belowMinimum(requiredPoints: policy.pointsPerCurrencyUnit)
        }
        let actualPoints = amount * policy.pointsPerCurrencyUnit
        guard child.rewardBalanceMinutes >= actualPoints else {
            return .insufficientCredits(
                requiredPoints: actualPoints,
                availablePoints: child.rewardBalanceMinutes
            )
        }
        if let cap = policy.monthlyPocketMoneyCap {
            let exchanged = pocketMoneySummary(for: targetChildId, now: now).thisMonthExchanged
            if exchanged + amount > cap {
                return .monthlyCapReached(cap: cap, alreadyExchanged: exchanged)
            }
        }
        return nil
    }

    /// 孩子发起成长积分→零花钱兑换。
    /// 成长积分立即扣除（等价 hold），家长驳回时退回；App 不碰真实支付。
    @discardableResult
    func requestPocketMoneyExchange(points: Int, childId: UUID? = nil, now: Date = Date()) -> MoneyLedgerEntry? {
        let targetChildId = childId ?? activeChildId
        guard pocketMoneyExchangeBlocker(points: points, childId: targetChildId, now: now) == nil else {
            return nil
        }
        guard let childIndex = children.firstIndex(where: { $0.id == targetChildId }) else { return nil }
        let policy = policy(for: targetChildId)

        let amount = points / policy.pointsPerCurrencyUnit
        guard amount >= 1 else { return nil }
        let actualPoints = amount * policy.pointsPerCurrencyUnit
        guard children[childIndex].rewardBalanceMinutes >= actualPoints else { return nil }

        if let cap = policy.monthlyPocketMoneyCap {
            let exchanged = pocketMoneySummary(for: targetChildId, now: now).thisMonthExchanged
            guard exchanged + amount <= cap else { return nil }
        }

        children[childIndex].rewardBalanceMinutes -= actualPoints
        let entry = MoneyLedgerEntry(
            id: UUID(),
            childId: targetChildId,
            kind: .creditExchange,
            amount: amount,
            pointsSpent: actualPoints,
            status: policy.pocketMoneyRequiresApproval ? .awaitingApproval : .pendingPayout,
            note: "用 \(actualPoints) 分兑换",
            createdAt: now
        )
        moneyLedger.insert(entry, at: 0)
        appendEvent(
            FamilyEvent(
                id: UUID(),
                kind: .taskAssigned,
                title: "\(children[childIndex].name)申请兑换零花钱",
                detail: "用 \(actualPoints) 分兑换 \(policy.currencySymbol)\(amount)。",
                minutes: nil,
                createdAt: now
            )
        )
        persist()
        return entry
    }

    /// 家长批准零花钱兑换：进入待发放。
    @discardableResult
    func approvePocketMoney(_ entryId: UUID) -> Bool {
        guard let index = moneyLedger.firstIndex(where: { $0.id == entryId }),
              moneyLedger[index].status == .awaitingApproval else { return false }
        moneyLedger[index].status = .pendingPayout
        persist()
        return true
    }

    /// 家长驳回零花钱兑换：退回成长积分。
    @discardableResult
    func rejectPocketMoney(_ entryId: UUID) -> Bool {
        guard let index = moneyLedger.firstIndex(where: { $0.id == entryId }),
              moneyLedger[index].status == .awaitingApproval else { return false }
        moneyLedger[index].status = .rejected
        if let points = moneyLedger[index].pointsSpent,
           let childIndex = children.firstIndex(where: { $0.id == moneyLedger[index].childId }) {
            children[childIndex].rewardBalanceMinutes += points
        }
        persist()
        return true
    }

    /// 家长线下给完钱后划账。
    @discardableResult
    func markPocketMoneyPaid(_ entryId: UUID) -> Bool {
        guard let index = moneyLedger.firstIndex(where: { $0.id == entryId }),
              moneyLedger[index].status == .pendingPayout else { return false }
        moneyLedger[index].status = .paid
        persist()
        return true
    }

    /// 家长手动调整零花钱（奖励或扣减，必须写原因）。
    @discardableResult
    func adjustPocketMoney(childId: UUID, amount: Int, note: String) -> MoneyLedgerEntry? {
        guard children.contains(where: { $0.id == childId }), amount != 0 else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let entry = MoneyLedgerEntry(
            id: UUID(),
            childId: childId,
            kind: .parentAdjustment,
            amount: amount,
            pointsSpent: nil,
            status: .pendingPayout,
            note: trimmed,
            createdAt: Date()
        )
        moneyLedger.insert(entry, at: 0)
        persist()
        return entry
    }

    // MARK: - 家长角色（谁在操作）

    /// 当前操作的大人昵称；未配置时用"家长"。
    var currentGuardianName: String {
        guard let id = currentGuardianId,
              let guardian = guardians.first(where: { $0.id == id }) else {
            return guardians.first?.displayName ?? "家长"
        }
        return guardian.displayName
    }

    @discardableResult
    func addGuardian(name: String, role: GuardianRole) -> GuardianProfile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = trimmed.isEmpty ? role.label : trimmed
        guard !guardians.contains(where: { $0.displayName == display }) else { return nil }
        let guardian = GuardianProfile(id: UUID(), displayName: display, role: role)
        guardians.append(guardian)
        familyNetwork.members.append(
            FamilyNetworkMember(
                id: guardian.id,
                displayName: guardian.displayName,
                role: .guardian,
                kinshipLabel: guardian.role.label,
                childId: nil,
                status: .active,
                joinedAt: Date()
            )
        )
        if currentGuardianId == nil { currentGuardianId = guardian.id }
        persist()
        return guardian
    }

    func setCurrentGuardian(_ guardianId: UUID) {
        guard guardians.contains(where: { $0.id == guardianId }) else { return }
        currentGuardianId = guardianId
        persist()
    }

    @discardableResult
    func removeGuardian(_ guardianId: UUID) -> Bool {
        guard guardianId != familyNetwork.creatorMemberId,
              let index = guardians.firstIndex(where: { $0.id == guardianId }) else { return false }
        guardians.remove(at: index)
        if let memberIndex = familyNetwork.members.firstIndex(where: { $0.id == guardianId }) {
            familyNetwork.members[memberIndex].status = .revoked
        }
        for deviceIndex in familyNetwork.devices.indices where familyNetwork.devices[deviceIndex].memberId == guardianId {
            familyNetwork.devices[deviceIndex].status = .revoked
        }
        if currentGuardianId == guardianId { currentGuardianId = guardians.first?.id }
        persist()
        return true
    }

    // MARK: - 家庭成员与设备

    /// 只有家庭创建者所在设备可以分配角色、签发邀请和撤销成员。
    var canManageFamilyMembership: Bool {
        guard let device = familyNetwork.devices.first(where: { $0.id == familyNetwork.currentDeviceId }) else {
            return false
        }
        return device.memberId == familyNetwork.creatorMemberId && device.status == .active
    }

    var currentFamilyMember: FamilyNetworkMember? {
        guard let device = familyNetwork.devices.first(where: { $0.id == familyNetwork.currentDeviceId }) else {
            return nil
        }
        return familyNetwork.member(id: device.memberId)
    }

    /// 签发十分钟有效的一次性邀请。孩子邀请必须明确绑定到某个孩子档案。
    @discardableResult
    func issueFamilyJoinInvite(
        role: FamilyMemberRole,
        childId: UUID? = nil,
        suggestedDisplayName: String? = nil,
        validFor: TimeInterval = 10 * 60
    ) -> FamilyJoinInvite? {
        guard canManageFamilyMembership else { return nil }
        if role == .child {
            guard let childId, children.contains(where: { $0.id == childId }) else { return nil }
        } else if childId != nil {
            return nil
        }

        let trimmed = suggestedDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let suggestedName = trimmed.flatMap { $0.isEmpty ? nil : String($0.prefix(24)) }
        let now = Date()
        let invite = FamilyJoinInvite(
            id: UUID(),
            role: role,
            childId: childId,
            suggestedDisplayName: suggestedName,
            token: UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            status: .issued,
            createdAt: now,
            expiresAt: now.addingTimeInterval(max(60, validFor))
        )
        familyNetwork.invitations.insert(invite, at: 0)
        persist()
        return invite
    }

    func familyJoinPayload(for invite: FamilyJoinInvite, at date: Date = Date()) -> FamilyJoinPayload? {
        guard invite.status == .issued, invite.expiresAt > date else { return nil }
        return FamilyJoinPayload(
            version: FamilyJoinPayload.currentVersion,
            familyId: familyNetwork.familyId,
            familyName: familyNetwork.familyName,
            inviteId: invite.id,
            token: invite.token,
            role: invite.role,
            childId: invite.childId,
            suggestedDisplayName: invite.suggestedDisplayName,
            expiresAt: invite.expiresAt
        )
    }

    @discardableResult
    func revokeFamilyJoinInvite(_ inviteId: UUID) -> Bool {
        guard canManageFamilyMembership,
              let index = familyNetwork.invitations.firstIndex(where: { $0.id == inviteId }),
              familyNetwork.invitations[index].status == .issued else { return false }
        familyNetwork.invitations[index].status = .revoked
        persist()
        return true
    }

    @discardableResult
    func revokeFamilyMember(_ memberId: UUID) -> Bool {
        guard canManageFamilyMembership,
              memberId != familyNetwork.creatorMemberId,
              let index = familyNetwork.members.firstIndex(where: { $0.id == memberId }),
              familyNetwork.members[index].role != .child else { return false }
        familyNetwork.members[index].status = .revoked
        for deviceIndex in familyNetwork.devices.indices where familyNetwork.devices[deviceIndex].memberId == memberId {
            familyNetwork.devices[deviceIndex].status = .revoked
        }
        if let guardianIndex = guardians.firstIndex(where: { $0.id == memberId }) {
            guardians.remove(at: guardianIndex)
            if currentGuardianId == memberId { currentGuardianId = guardians.first?.id }
        }
        persist()
        return true
    }

    private static func migratedFamilyNetwork(
        children: [ChildProfile],
        guardians: [GuardianProfile],
        currentGuardianId: UUID?
    ) -> FamilyNetworkState {
        let now = Date()
        let creatorId = currentGuardianId ?? guardians.first?.id ?? UUID()
        var members = guardians.map {
            FamilyNetworkMember(
                id: $0.id,
                displayName: $0.displayName,
                role: .guardian,
                kinshipLabel: $0.role.label,
                childId: nil,
                status: .active,
                joinedAt: now
            )
        }
        if !members.contains(where: { $0.id == creatorId }) {
            members.append(
                FamilyNetworkMember(
                    id: creatorId,
                    displayName: "家长",
                    role: .guardian,
                    kinshipLabel: "家庭创建者",
                    childId: nil,
                    status: .active,
                    joinedAt: now
                )
            )
        }
        members += children.map {
            FamilyNetworkMember(
                id: $0.id,
                displayName: $0.name,
                role: .child,
                kinshipLabel: "孩子",
                childId: $0.id,
                status: .active,
                joinedAt: now
            )
        }
        let deviceId = UUID()
        return FamilyNetworkState(
            familyId: UUID(),
            familyName: "\(children.first?.name ?? "章鱼老师")的家庭",
            creatorMemberId: creatorId,
            members: members,
            devices: [
                FamilyDeviceBinding(
                    id: deviceId,
                    memberId: creatorId,
                    role: .guardian,
                    childId: nil,
                    deviceName: "家庭创建者的手机",
                    status: .active,
                    boundAt: now
                )
            ],
            invitations: [],
            currentDeviceId: deviceId
        )
    }

    // MARK: - 重复任务（每天 / 每周）

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// 家长把任务设为重复：登记规则并立即生成今天的实例（若到期）。
    @discardableResult
    func addRecurringRule(template: TaskTemplate, recurrence: TaskRecurrence, weekday: Int? = nil, childId: UUID? = nil) -> RecurringTaskRule? {
        guard recurrence != .once else { return nil }
        let targetChildId = childId ?? activeChildId
        guard children.contains(where: { $0.id == targetChildId }) else { return nil }
        let rule = RecurringTaskRule(
            id: UUID(),
            childId: targetChildId,
            template: template,
            recurrence: recurrence,
            weekday: recurrence == .weekly ? (weekday ?? Calendar.current.component(.weekday, from: Date())) : nil,
            lastGeneratedDayKey: nil
        )
        recurringRules.append(rule)
        generateDueRecurringTasks()
        persist()
        return rule
    }

    @discardableResult
    func removeRecurringRule(_ ruleId: UUID) -> Bool {
        guard let index = recurringRules.firstIndex(where: { $0.id == ruleId }) else { return false }
        recurringRules.remove(at: index)
        persist()
        return true
    }

    /// 生成今天到期的重复任务实例（幂等：每规则每天最多一条）。
    /// App 启动与回到前台时调用。
    func generateDueRecurringTasks(now: Date = Date()) {
        let todayKey = Self.dayKey(for: now)
        let todayWeekday = Calendar.current.component(.weekday, from: now)
        var changed = false

        for index in recurringRules.indices {
            let rule = recurringRules[index]
            guard rule.lastGeneratedDayKey != todayKey else { continue }
            guard children.contains(where: { $0.id == rule.childId }) else { continue }
            if rule.recurrence == .weekly, rule.weekday != todayWeekday { continue }

            var template = rule.template
            template = TaskTemplate(
                id: UUID(),
                title: template.title,
                category: template.category,
                difficulty: template.difficulty,
                rewardMinutes: template.rewardMinutes,
                instructions: template.instructions,
                requiredProof: template.requiredProof,
                adultSupervisionRequired: template.adultSupervisionRequired,
                reading: template.reading,
                video: template.video,
                packType: template.packType
            )
            let assignment = TaskAssignment(
                id: UUID(),
                childId: rule.childId,
                task: template,
                date: now,
                status: .open,
                proof: .empty
            )
            assignments.append(assignment)
            let nextOrder = (growthPack.steps.map(\.order).max() ?? 0) + 1
            growthPack.steps.append(
                GrowthPackStep(
                    id: UUID(),
                    order: nextOrder,
                    title: template.title,
                    detail: template.instructions,
                    assignmentId: assignment.id,
                    rewardMinutes: template.rewardMinutes
                )
            )
            recurringRules[index].lastGeneratedDayKey = todayKey
            changed = true
        }
        if changed { persist() }
    }

    /// 某孩子某月的零花钱与愿望消费总览。
    /// - Returns: 积分兑换的零花钱、基础零花钱、家长调整合计、愿望消费的积分。
    func monthlySpendingSummary(for childId: UUID, month: Date = Date()) -> (exchangedMoney: Int, baseAllowance: Int, adjustments: Int, wishPointsSpent: Int) {
        let key = Self.monthKey(for: month)
        let entries = moneyLedger.filter {
            $0.childId == childId && $0.status != .rejected && Self.monthKey(for: $0.createdAt) == key
        }
        let exchanged = entries.filter { $0.kind == .creditExchange }.reduce(0) { $0 + $1.amount }
        let base = entries.filter { $0.kind == .baseAllowance }.reduce(0) { $0 + $1.amount }
        let adjust = entries.filter { $0.kind == .parentAdjustment }.reduce(0) { $0 + $1.amount }
        let wishPoints = wishes
            .filter { $0.childId == childId && ($0.status == .redeemed || $0.status == .fulfilled) && Self.monthKey(for: $0.createdAt) == key }
            .reduce(0) { $0 + ($1.pricePoints ?? 0) }
        return (exchanged, base, adjust, wishPoints)
    }

    // MARK: - 任务完成统计（家长报表）

    enum StatsRange: String, CaseIterable {
        case day, week, month

        var label: String {
            switch self {
            case .day: return "今天"
            case .week: return "本周"
            case .month: return "本月"
            }
        }
    }

    /// 某孩子在时间范围内按类别统计的（完成数, 布置数）。
    func taskStats(for childId: UUID, range: StatsRange, now: Date = Date()) -> [(category: TaskCategory, done: Int, total: Int)] {
        let calendar = Calendar.current
        let start: Date
        switch range {
        case .day: start = calendar.startOfDay(for: now)
        case .week: start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .month: start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        }
        let mine = assignments.filter {
            $0.childId == childId && $0.date >= start && $0.status != .cancelled
        }
        return TaskCategory.childDisplayOrder.compactMap { category in
            let group = mine.filter { $0.task.category == category }
            guard !group.isEmpty else { return nil }
            return (category, group.filter { $0.status == .approved }.count, group.count)
        }
    }

    // MARK: - 学科进度与考试（千小时徽章体系）

    func addStudyMinutes(_ minutes: Int, subject: LearningSubject, childId: UUID) {
        guard minutes > 0 else { return }
        var byChild = subjectProgress[childId] ?? [:]
        var entry = byChild[subject.rawValue] ?? SubjectProgressEntry()
        entry.studyMinutes += minutes
        byChild[subject.rawValue] = entry
        subjectProgress[childId] = byChild
    }

    func progressEntry(subject: LearningSubject, childId: UUID) -> SubjectProgressEntry {
        subjectProgress[childId]?[subject.rawValue] ?? SubjectProgressEntry()
    }

    func hasTakenQuiz(for assignmentId: UUID) -> Bool {
        quizTakenAssignmentIds.contains(assignmentId)
    }

    /// 记录一次考试结果（每任务只记一次，防刷分）：
    /// 学科积分 +答对数×10、学时加成 +答对数×6 分钟、成长积分 +答对数。
    @discardableResult
    func recordQuizResult(assignmentId: UUID, subject: LearningSubject, correct: Int, total: Int) -> Bool {
        guard !quizTakenAssignmentIds.contains(assignmentId), total > 0 else { return false }
        guard let assignment = assignments.first(where: { $0.id == assignmentId }) else { return false }
        quizTakenAssignmentIds.insert(assignmentId)

        var byChild = subjectProgress[assignment.childId] ?? [:]
        var entry = byChild[subject.rawValue] ?? SubjectProgressEntry()
        entry.quizPoints += correct * 10
        entry.studyMinutes += correct * 6
        if correct * 2 >= total { entry.quizPassed += 1 }
        byChild[subject.rawValue] = entry
        subjectProgress[assignment.childId] = byChild

        if correct > 0, let childIndex = children.firstIndex(where: { $0.id == assignment.childId }) {
            children[childIndex].rewardBalanceMinutes += correct
        }
        persist()
        return true
    }

    // MARK: - 电子书书库

    /// 登记导入的电子书。
    @discardableResult
    func addBook(
        title: String,
        fileName: String,
        format: String,
        pageCount: Int,
        charCount: Int,
        chapters: [BookChapter] = [],
        sourceName: String? = nil,
        sourceURLString: String? = nil
    ) -> FamilyBook {
        let book = FamilyBook(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            fileName: fileName,
            format: format,
            pageCount: pageCount,
            charCount: charCount,
            chapters: chapters,
            importedAt: Date(),
            sourceName: sourceName,
            sourceURLString: sourceURLString
        )
        books.insert(book, at: 0)
        persist()
        return book
    }

    /// 在绑定孩子的手机上登记从公开来源重新下载的家庭书籍。
    /// 使用家长端原始 book id，使阅读任务的 importedBookId 在两台设备上保持一致。
    func addCloudBook(
        _ resource: FamilyCloudBookResource,
        fileName: String,
        pageCount: Int,
        charCount: Int,
        chapters: [BookChapter]
    ) {
        guard !books.contains(where: { $0.id == resource.id }) else { return }
        books.insert(FamilyBook(
            id: resource.id,
            title: resource.title,
            fileName: fileName,
            format: resource.format,
            pageCount: pageCount,
            charCount: charCount,
            chapters: chapters,
            importedAt: Date(),
            sourceName: resource.sourceName,
            sourceURLString: resource.sourceURLString
        ), at: 0)
        persist()
    }

    /// 删除书（同时删文件）。已布置的任务保留但退回"拿实体书读"模式。
    @discardableResult
    func removeBook(_ bookId: UUID) -> Bool {
        guard let index = books.firstIndex(where: { $0.id == bookId }) else { return false }
        BookFileStore.shared.delete(fileName: books[index].fileName)
        books.remove(at: index)
        bookReadingProgress.removeAll { $0.bookId == bookId }
        persist()
        return true
    }

    func book(id: UUID?) -> FamilyBook? {
        guard let id else { return nil }
        return books.first { $0.id == id }
    }

    func book(matchingTitle title: String?) -> FamilyBook? {
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !normalizedTitle.isEmpty else { return nil }
        return books.first { book in
            let imported = book.title.lowercased()
            return imported == normalizedTitle
                || imported.contains(normalizedTitle)
                || normalizedTitle.contains(imported)
        }
    }

    func book(for reading: ReadingSpec?) -> FamilyBook? {
        guard let reading else { return nil }
        return book(id: reading.importedBookId) ?? book(matchingTitle: reading.bookTitle)
    }

    func readingProgress(childId: UUID, bookId: UUID, assignmentId: UUID?) -> BookReadingProgress? {
        if let assignmentId,
           let progress = bookReadingProgress.first(where: {
               $0.childId == childId && $0.bookId == bookId && $0.assignmentId == assignmentId
           }) {
            return progress
        }
        return bookReadingProgress.first {
            $0.childId == childId && $0.bookId == bookId && $0.assignmentId == nil
        }
    }

    @discardableResult
    func updateReadingProgress(
        childId: UUID,
        bookId: UUID,
        assignmentId: UUID?,
        lastPage: Int?,
        lastCharacterOffset: Int?,
        fontSize: Double,
        speechRate: Double,
        secondsDelta: Int
    ) -> BookReadingProgress {
        let now = Date()
        if let index = bookReadingProgress.firstIndex(where: {
            $0.childId == childId && $0.bookId == bookId && $0.assignmentId == assignmentId
        }) {
            if let lastPage { bookReadingProgress[index].lastPage = lastPage }
            if let lastCharacterOffset { bookReadingProgress[index].lastCharacterOffset = lastCharacterOffset }
            bookReadingProgress[index].fontSize = fontSize
            bookReadingProgress[index].speechRate = speechRate
            bookReadingProgress[index].totalSeconds += max(0, secondsDelta)
            bookReadingProgress[index].updatedAt = now
            let progress = bookReadingProgress[index]
            persist()
            return progress
        }

        let progress = BookReadingProgress(
            childId: childId,
            bookId: bookId,
            assignmentId: assignmentId,
            lastPage: lastPage,
            lastCharacterOffset: lastCharacterOffset,
            fontSize: fontSize,
            speechRate: speechRate,
            totalSeconds: max(0, secondsDelta),
            updatedAt: now
        )
        bookReadingProgress.insert(progress, at: 0)
        persist()
        return progress
    }

    /// 缓存 App 内阅读内容（AI 生成后写回任务，重进不再重复生成）。
    func updateReadingContent(_ content: String, for assignmentId: UUID) {
        guard let index = assignments.firstIndex(where: { $0.id == assignmentId }),
              assignments[index].task.reading != nil else { return }
        assignments[index].task.reading?.inAppContent = content
        persist()
    }

    /// 累计 App 内阅读时长（进度跟进；家长审核时可见）。
    func recordReadingSeconds(_ seconds: Int, for assignmentId: UUID) {
        guard seconds > 0,
              let index = assignments.firstIndex(where: { $0.id == assignmentId }) else { return }
        assignments[index].readingSecondsSpent = (assignments[index].readingSecondsSpent ?? 0) + seconds
        persist()
    }

    /// 提交后异步挂上 AI 初评（AI 永不终审）。
    func attachAIReview(_ review: AIReviewSummary, to assignmentId: UUID) {
        guard let index = assignments.firstIndex(where: { $0.id == assignmentId }) else { return }
        assignments[index].aiReview = review
        persist()
    }

    // MARK: - 亲友参与（只读 / 建议）

    /// 亲友留下鼓励/建议占位。
    /// 仅当亲友具备 canSuggest 能力时成功；绝不发放成长积分、不改任务状态、不解锁设备。
    @discardableResult
    func relativeSuggest(from relative: FamilyRelative, message: String) -> Bool {
        guard relative.capability.canSuggest else { return false }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        suggestions.insert(
            RelativeSuggestion(id: UUID(), relativeId: relative.id, message: trimmed, createdAt: Date()),
            at: 0
        )
        appendEvent(
            FamilyEvent(
                id: UUID(),
                kind: .relativeSuggested,
                title: "\(relative.displayName)留下了鼓励",
                detail: trimmed,
                minutes: nil,
                createdAt: Date()
            )
        )
        persist()
        return true
    }

    /// 亲友参与摘要，供家长查看；其中越权能力字段按安全边界应恒为 false。
    var relativeParticipationSummary: RelativeParticipationSummary {
        RelativeParticipationSummary(
            relativeCount: relatives.count,
            suggestionCount: suggestions.count,
            anyRelativeCanGrantCredit: relatives.contains { $0.capability.canGrantCredit },
            anyRelativeCanUnlockDevice: relatives.contains { $0.capability.canUnlockDevice }
        )
    }

    /// 最近成长记录：审批后的事件摘要，最新在前。
    func recentGrowthRecords(limit: Int = 10) -> [FamilyEvent] {
        Array(events.prefix(limit))
    }

    private func appendEvent(_ event: FamilyEvent) {
        events.insert(event, at: 0)
    }

    @discardableResult
    func spendRewardMinutes(_ minutes: Int, for childId: UUID? = nil) -> Bool {
        let targetChildId = childId ?? activeChildId
        guard minutes > 0,
              let index = children.firstIndex(where: { $0.id == targetChildId }),
              children[index].rewardBalanceMinutes >= minutes
        else { return false }
        children[index].rewardBalanceMinutes -= minutes
        persist()
        return true
    }

    /// 回滚之前扣除的成长积分。用于解锁命令失败时把成长积分退回孩子余额。
    func refundRewardMinutes(_ minutes: Int, for childId: UUID? = nil) {
        let targetChildId = childId ?? activeChildId
        guard minutes > 0,
              let index = children.firstIndex(where: { $0.id == targetChildId })
        else { return }
        children[index].rewardBalanceMinutes += minutes
        persist()
    }

    private func updateAssignment(_ id: UUID, mutate: (inout TaskAssignment) -> Void) {
        guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        mutate(&assignments[index])
    }

    // MARK: - 种子数据

    private static func seedAssignments(for childId: UUID) -> [TaskAssignment] {
        let tasks = [
            TaskTemplate(
                id: UUID(),
                title: "阅读 15 分钟",
                category: .learning,
                difficulty: .easy,
                rewardMinutes: 15,
                instructions: "读一本书或一篇文章，然后写下一句今天学到的内容。",
                requiredProof: .text
            ),
            TaskTemplate(
                id: UUID(),
                title: "整理书桌",
                category: .home,
                difficulty: .easy,
                rewardMinutes: 15,
                instructions: "把书桌整理到可以写作业或阅读的状态，拍一张照片给爸爸妈妈看。",
                requiredProof: .photo
            ),
            TaskTemplate(
                id: UUID(),
                title: "运动 20 分钟",
                category: .health,
                difficulty: .medium,
                rewardMinutes: 20,
                instructions: "散步、拉伸、户外活动或做一组简单运动，并写一句完成记录。",
                requiredProof: .text
            )
        ]

        return tasks.map {
            TaskAssignment(
                id: UUID(),
                childId: childId,
                task: $0,
                date: Date(),
                status: .open,
                proof: .empty
            )
        }
    }

    /// 私密家庭圈亲友种子数据：脱敏昵称 + 只读/建议能力。
    private static func seedRelatives() -> [FamilyRelative] {
        [
            FamilyRelative(
                id: UUID(),
                displayName: "外婆",
                role: .grandparent,
                capability: .readOnlySuggest
            ),
            FamilyRelative(
                id: UUID(),
                displayName: "小姨",
                role: .auntUncle,
                capability: .viewOnly
            )
        ]
    }

    /// 用今日任务组装一个有序成长包，逐步解锁。
    private static func seedGrowthPack(from assignments: [TaskAssignment]) -> GrowthPack {
        let steps = assignments.enumerated().map { index, assignment in
            GrowthPackStep(
                id: UUID(),
                order: index + 1,
                title: assignment.task.title,
                detail: assignment.task.instructions,
                assignmentId: assignment.id,
                rewardMinutes: assignment.task.rewardMinutes
            )
        }

        return GrowthPack(
            id: UUID(),
            title: "今日成长计划",
            summary: "把今天的学习、生活和运动安排成清楚的小计划，完成后获得成长积分。",
            steps: steps
        )
    }
}
