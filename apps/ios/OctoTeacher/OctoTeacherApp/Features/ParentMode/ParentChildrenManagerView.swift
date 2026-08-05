import SwiftUI

/// 家长端孩子管理：多孩子家庭的成员列表、添加与档案编辑，以及家庭设置。
///
/// 兴趣标签和家长备注是 AI 生成个性化任务的「记忆」来源，
/// 只经家长自己的 BYOK 通道发送，绝不含照片/语音/证明正文。
/// 本页从软件设置可达，文案跟随家长界面语言（显式双语，不走 .strings 查找）。
struct ParentChildrenManagerView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud

    @State private var newName = ""
    @State private var newAge = 8
    @State private var editingChild: ChildProfile?
    @State private var pendingArchive: ChildProfile?
    @State private var isMutating = false
    @State private var feedback: String?

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        List {
            childrenSection
            addSection
            familyMembersSection
        }
        .navigationTitle(lang.pick("孩子管理", "Children"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingChild) { child in
            NavigationStack {
                ChildProfileEditorView(child: child)
            }
        }
        .alert(
            lang.pick("归档孩子档案？", "Archive child profile?"),
            isPresented: Binding(
                get: { pendingArchive != nil },
                set: { if !$0 { pendingArchive = nil } }
            ),
            presenting: pendingArchive
        ) { child in
            Button(lang.pick("取消", "Cancel"), role: .cancel) {
                pendingArchive = nil
            }
            Button(lang.pick("归档", "Archive"), role: .destructive) {
                archive(child)
            }
        } message: { child in
            Text(lang.pick(
                "\(child.name) 将从家庭的活跃孩子列表移除，孩子设备会解除绑定，未完成任务会取消；已批准任务、积分账本和成长记录会保留以便审计。",
                "\(child.name) will leave the active child list, child devices will be unbound, and unfinished tasks will be cancelled. Approved tasks, the point ledger, and growth history remain auditable."
            ))
        }
    }

    private var childrenSection: some View {
        Section {
            ForEach(store.children) { member in
                HStack(spacing: 12) {
                    Button {
                        store.setActiveChild(member.id)
                        feedback = lang.pick(
                            "已切换到 \(member.name)。",
                            "Now viewing \(member.name)."
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(member.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if member.id == store.activeChildId {
                                    Text(lang.pick("当前", "Current"))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                            }
                            Text(lang.pick(
                                "\(member.age) 岁 · 每日屏幕上限 \(member.dailyLimitMinutes) 分钟 · 可用成长积分 \(member.rewardBalanceMinutes)",
                                "\(member.age) yrs · Daily screen limit \(member.dailyLimitMinutes) min · Growth Points \(member.rewardBalanceMinutes)"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(lang.pick(
                                "界面语言：\(store.childInterfaceLanguage(for: member.id).label)",
                                "Interface: \(store.childInterfaceLanguage(for: member.id).label)"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            if !member.resolvedInterests.isEmpty {
                                Text(lang.pick(
                                    "兴趣：\(member.resolvedInterests.joined(separator: "、"))",
                                    "Interests: \(member.resolvedInterests.joined(separator: ", "))"
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)

                    Button {
                        editingChild = member
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(lang.pick("编辑 \(member.name)", "Edit \(member.name)"))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if member.id != store.activeChildId {
                        Button(lang.pick("设为当前", "Make current")) {
                            store.setActiveChild(member.id)
                        }
                        .tint(.blue)
                    }
                    if store.children.count > 1 {
                        Button(role: .destructive) {
                            pendingArchive = member
                        } label: {
                            Label(lang.pick("归档", "Archive"), systemImage: "archivebox")
                        }
                    }
                }
            }
        } header: {
            Text(lang.pick("家里的孩子（\(store.children.count)）", "Children (\(store.children.count))"))
        } footer: {
            Text(lang.pick(
                "点孩子可切换当前查看对象；点铅笔编辑 TA 的语言、兴趣和其他档案。",
                "Tap a child to switch the current view; tap the pencil to edit language, interests, and profile details."
            ))
        }
    }

    private var addSection: some View {
        Section {
            TextField(lang.pick("孩子昵称", "Child's nickname"), text: $newName)
                .accessibilityIdentifier("children-manager-new-name")
            Stepper(lang.pick("年龄：\(newAge) 岁", "Age: \(newAge)"), value: $newAge, in: 3...18)
            Button(lang.pick("添加孩子", "Add child")) {
                addChild()
            }
            .disabled(isMutating || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("children-manager-add")
        } header: {
            Text(lang.pick("添加孩子", "Add a Child"))
        } footer: {
            if let feedback {
                Text(feedback)
            }
        }
    }

    private var familyMembersSection: some View {
        Section {
            NavigationLink {
                FamilyMembersView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.3.sequence.fill")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lang.pick("家庭成员与设备", "Family Members & Devices"))
                            .foregroundStyle(.primary)
                        Text(lang.pick(
                            "邀请共同监护人，或绑定指定孩子手机",
                            "Invite a co-guardian or link a specific child's phone"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(store.familyNetwork.activeMembers().count)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("family-members-entry")
        } header: {
            Text(lang.pick("家庭网络", "Family Network"))
        } footer: {
            Text(lang.pick(
                "家庭只保留创建者、共同监护人和孩子设备。家庭创建者负责邀请、移除和删除家庭。",
                "A family contains its creator, co-guardians, and child devices. The creator manages invitations, removal, and family deletion."
            ))
        }
    }

    private func addChild() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isMutating = true
        feedback = nil
        Task { @MainActor in
            defer { isMutating = false }
            do {
                if familyCloud.isGuardianSignedIn {
                    guard familyCloud.family != nil else {
                        throw FamilyCloudClientError.server("family_not_ready")
                    }
                    try await familyCloud.addGuardianChild(name: name, age: newAge, local: store)
                } else {
                    guard let child = store.addChild(name: name, age: newAge) else {
                        throw FamilyCloudClientError.server("duplicate_child_name")
                    }
                    guard familyCloud.queueGuardianProfileSync(for: child.id) else {
                        throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
                    }
                }
                newName = ""
                feedback = lang.pick("已添加 \(name)。", "Added \(name).")
            } catch {
                feedback = childMutationError(error)
            }
        }
    }

    private func archive(_ child: ChildProfile) {
        pendingArchive = nil
        isMutating = true
        feedback = nil
        Task { @MainActor in
            defer { isMutating = false }
            do {
                if familyCloud.isGuardianSignedIn {
                    guard familyCloud.family != nil else {
                        throw FamilyCloudClientError.server("family_not_ready")
                    }
                    try await familyCloud.archiveGuardianChild(childID: child.id, local: store)
                } else {
                    throw FamilyCloudClientError.server("family_cloud_required")
                }
                feedback = lang.pick(
                    "已归档 \(child.name)。历史记录仍然保留。",
                    "Archived \(child.name). History remains available."
                )
            } catch {
                feedback = childMutationError(error)
            }
        }
    }

    private func childMutationError(_ error: Error) -> String {
        let code: String
        if let cloudError = error as? FamilyCloudClientError,
           case let .server(value) = cloudError {
            code = value
        } else {
            code = "request_failed"
        }
        switch code {
        case "duplicate_child_name":
            return lang.pick("孩子昵称不能重名。", "Child nicknames must be unique.")
        case "family_must_keep_one_child":
            return lang.pick("家庭至少要保留一个孩子档案。", "A family must keep at least one child profile.")
        case "family_not_ready", "family_not_found":
            return lang.pick("家庭云尚未就绪，请先刷新家庭资料。", "Family Cloud is not ready. Refresh the family first.")
        case "family_cloud_required":
            return lang.pick("请先登录并连接家庭云，再归档孩子档案。", "Sign in and connect Family Cloud before archiving a child profile.")
        case "child_profile_archived":
            return lang.pick("这个孩子档案已被另一位监护人归档，刷新后会从列表移除。", "Another guardian already archived this child profile. Refresh to update the list.")
        default:
            return lang.pick("操作没有完成，请检查网络后重试。", "The change was not completed. Check your connection and try again.")
        }
    }

}

/// 孩子档案编辑：昵称、年龄、每日上限、界面语言、学习内容语言、兴趣标签、家长备注。
struct ChildProfileEditorView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(\.dismiss) private var dismiss

    let child: ChildProfile

    @State private var name: String
    @State private var age: Int
    @State private var dailyLimit: Int
    @State private var interestsText: String
    @State private var notes: String
    @State private var preReader: Bool
    @State private var contentLanguage: FamilyLanguage?
    @State private var interfaceLanguage: AppInterfaceLanguage?
    @State private var policy: FamilyExchangePolicy
    @State private var policyBaseline: FamilyExchangePolicy

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    init(child: ChildProfile) {
        self.child = child
        _name = State(initialValue: child.name)
        _age = State(initialValue: child.age)
        _dailyLimit = State(initialValue: child.dailyLimitMinutes)
        _interestsText = State(initialValue: child.resolvedInterests.joined(separator: "、"))
        _notes = State(initialValue: child.parentNotes ?? "")
        _preReader = State(initialValue: child.isPreReader)
        _contentLanguage = State(initialValue: child.contentLanguage)
        _interfaceLanguage = State(initialValue: child.interfaceLanguage)
        _policy = State(initialValue: .default)
        _policyBaseline = State(initialValue: .default)
    }

    var body: some View {
        Form {
            Section(lang.pick("基础信息", "Basics")) {
                TextField(lang.pick("昵称", "Nickname"), text: $name)
                Stepper(lang.pick("年龄：\(age) 岁", "Age: \(age)"), value: $age, in: 3...18)
                Toggle(lang.pick("TA 还不认字（幼儿模式）", "Can't read yet (pre-reader mode)"), isOn: $preReader)
                    .accessibilityIdentifier("child-editor-pre-reader")
                Picker(lang.pick("TA 的界面语言", "Their interface language"), selection: $interfaceLanguage) {
                    Text(lang.pick("跟随家庭设置", "Follow family setting")).tag(AppInterfaceLanguage?.none)
                    ForEach(AppInterfaceLanguage.allCases) { language in
                        Text(language.label).tag(AppInterfaceLanguage?.some(language))
                    }
                }
                .accessibilityIdentifier("child-editor-interface-language")
                Picker(lang.pick("TA 的学习内容语言", "Their learning content language"), selection: $contentLanguage) {
                    Text(lang.pick("跟随家庭设置", "Follow family setting")).tag(FamilyLanguage?.none)
                    ForEach(FamilyLanguage.allCases, id: \.self) { language in
                        Text(language.label(for: lang)).tag(FamilyLanguage?.some(language))
                    }
                }
                .accessibilityIdentifier("child-editor-content-language")
            }

            Section {
                TextField(
                    lang.pick("兴趣，用、分隔（例如：恐龙、乐高、画画）", "Interests, comma-separated (e.g. dinosaurs, LEGO, drawing)"),
                    text: $interestsText,
                    axis: .vertical
                )
                .lineLimit(1...3)
                .accessibilityIdentifier("child-editor-interests")
                TextField(
                    lang.pick("家长备注（例如：刚开始学拼音）", "Parent notes (e.g. just started phonics)"),
                    text: $notes,
                    axis: .vertical
                )
                .lineLimit(1...4)
            } header: {
                Text(lang.pick("给 AI 的了解（可选）", "For the AI (Optional)"))
            } footer: {
                Text(lang.pick(
                    "这些信息帮 AI 生成更适合 TA 的任务，只经你自己的 AI 账号发送，不含任何照片或语音。开启幼儿模式后，TA 的界面会变成大图标卡片，并在文字旁显示可手动点读的小喇叭。界面语言决定 TA 看到的按钮、导航和小喇叭的朗读音色。",
                    "This helps AI create better-fitting tasks and is sent only through your own AI account, never with photos or audio. Pre-reader mode switches their screens to big icon cards with a manual read-aloud button. Interface language controls their buttons, navigation, and the read-aloud voice."
                ))
            }

            Section {
                Picker(lang.pick("每日解锁上限", "Daily unlock limit"), selection: $dailyLimit) {
                    ForEach([15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 600, 720], id: \.self) { minutes in
                        Text(dailyLimitLabel(minutes)).tag(minutes)
                    }
                }
                .accessibilityIdentifier("child-editor-daily-unlock-limit")
                Picker(lang.pick("发放周期", "Allowance cycle"), selection: Binding(
                    get: { policy.resolvedCycle },
                    set: { policy.allowanceCycle = $0 }
                )) {
                    ForEach(AllowanceCycle.allCases, id: \.self) { cycle in
                        Text(cycle.label).tag(cycle)
                    }
                }
                .pickerStyle(.segmented)
                Stepper(
                    lang.pick(
                        "\(policy.resolvedCycle.label)基础零花钱：\(policy.currencySymbol)\(policy.baseMonthlyAllowance)",
                        "Base allowance per cycle: \(policy.currencySymbol)\(policy.baseMonthlyAllowance)"
                    ),
                    value: $policy.baseMonthlyAllowance, in: 0...100_000, step: 5
                )
                if policy.resolvedCycle == .monthly {
                    Stepper(
                        lang.pick("每月 \(policy.allowanceDayOfMonth) 号入账", "Credited on day \(policy.allowanceDayOfMonth) each month"),
                        value: $policy.allowanceDayOfMonth, in: 1...28
                    )
                }
                Picker(lang.pick("屏幕时间汇率", "Screen time rate"), selection: $policy.screenRate) {
                    ForEach(ScreenExchangeRate.allCases, id: \.self) { rate in
                        Text(rate.label).tag(rate)
                    }
                }
                Stepper(
                    lang.pick(
                        "自定义时长：每份 \(policy.resolvedScreenExchangeMinutes) 分钟",
                        "Custom duration: \(policy.resolvedScreenExchangeMinutes) minutes per exchange"
                    ),
                    value: Binding(
                        get: { policy.resolvedScreenExchangeMinutes },
                        set: { policy.customScreenExchangeMinutes = $0 }
                    ),
                    in: 1...720
                )
                Stepper(
                    lang.pick(
                        "自定义价格：每份需要 \(policy.resolvedScreenPointsPer15Minutes) 成长积分",
                        "Custom price: \(policy.resolvedScreenPointsPer15Minutes) Growth Points per exchange"
                    ),
                    value: Binding(
                        get: { policy.resolvedScreenPointsPer15Minutes },
                        set: { policy.customScreenPointsPer15Minutes = $0 }
                    ),
                    in: 1...100_000
                )
                Button(lang.pick("恢复上面的预设汇率", "Use the preset rate above")) {
                    policy.customScreenPointsPer15Minutes = nil
                    policy.customScreenExchangeMinutes = nil
                }
                Stepper(
                    lang.pick(
                        "零花钱汇率：\(policy.pointsPerCurrencyUnit) 积分 = \(policy.currencySymbol)1",
                        "Money rate: \(policy.pointsPerCurrencyUnit) points = \(policy.currencySymbol)1"
                    ),
                    value: $policy.pointsPerCurrencyUnit, in: 1...100_000
                )
                Toggle(lang.pick("兑换零花钱需我批准", "Money exchanges need my approval"), isOn: $policy.pocketMoneyRequiresApproval)
                Stepper(
                    policy.monthlyPocketMoneyCap == nil
                        ? lang.pick("每月兑换上限：不限", "Monthly exchange cap: none")
                        : lang.pick(
                            "每月兑换上限：\(policy.currencySymbol)\(policy.monthlyPocketMoneyCap ?? 0)",
                            "Monthly exchange cap: \(policy.currencySymbol)\(policy.monthlyPocketMoneyCap ?? 0)"
                        ),
                    value: Binding(
                        get: { policy.monthlyPocketMoneyCap ?? 0 },
                        set: { policy.monthlyPocketMoneyCap = $0 <= 0 ? nil : $0 }
                    ),
                    in: 0...1_000_000,
                    step: 10
                )
                Picker(lang.pick("货币", "Currency"), selection: $policy.currencySymbol) {
                    Text(lang.pick("¥ 人民币", "¥ CNY")).tag("¥")
                    Text(lang.pick("$ 美元", "$ USD")).tag("$")
                }
            } header: {
                Text(lang.pick("兑换机制（成长积分经济）", "Exchange Rules (Growth Point Economy)"))
            } footer: {
                Text(lang.pick(
                    "这些规则可以随时回来修改，不是只能设置一次。完成任务得成长积分；成长积分可以换屏幕时间、零花钱或愿望。基础零花钱是无条件底薪，每月自动记账，真实的钱由你线下给。",
                    "Return here to change these rules at any time; they are not a one-time setup. Tasks earn Growth Points; points buy screen time, pocket money, or wishes. Base allowance is an unconditional stipend recorded automatically; real money changes hands offline."
                ))
            }

            Section {
                Button(lang.pick("保存", "Save")) {
                    var changedFields: Set<FamilyCloudGuardianProfileField> = []
                    if name != child.name { changedFields.insert(.displayName) }
                    if age != child.age { changedFields.insert(.birthYear) }
                    if dailyLimit != child.dailyLimitMinutes { changedFields.insert(.dailyLimitMinutes) }
                    if preReader != child.isPreReader { changedFields.insert(.preReaderMode) }
                    if contentLanguage != child.contentLanguage { changedFields.insert(.contentLanguage) }
                    if interfaceLanguage != child.interfaceLanguage { changedFields.insert(.interfaceLanguage) }
                    if policy != policyBaseline { changedFields.insert(.exchangePolicy) }
                    let currentChild = store.children.first(where: { $0.id == child.id }) ?? child
                    let interests = interestsText
                        .replacingOccurrences(of: ",", with: "、")
                        .replacingOccurrences(of: "，", with: "、")
                        .split(separator: "、")
                        .map(String.init)
                    store.updateChildProfile(
                        childId: child.id,
                        name: changedFields.contains(.displayName) ? name : currentChild.name,
                        age: changedFields.contains(.birthYear) ? age : currentChild.age,
                        dailyLimitMinutes: changedFields.contains(.dailyLimitMinutes) ? dailyLimit : currentChild.dailyLimitMinutes,
                        interests: interests,
                        parentNotes: notes
                    )
                    if changedFields.contains(.preReaderMode) {
                        store.setPreReaderMode(preReader, for: child.id)
                    }
                    if changedFields.contains(.contentLanguage) {
                        store.setContentLanguage(contentLanguage, for: child.id)
                    }
                    if changedFields.contains(.interfaceLanguage) {
                        store.setChildInterfaceLanguage(interfaceLanguage, for: child.id)
                    }
                    if changedFields.contains(.exchangePolicy) {
                        store.setExchangePolicy(policy, for: child.id)
                    }
                    familyCloud.queueGuardianProfileSync(for: child.id, fields: changedFields)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("child-editor-save")
            }
        }
        .navigationTitle(lang.pick("编辑\(child.name)的档案", "Edit \(child.name)'s Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            policy = store.policy(for: child.id)
            policyBaseline = policy
        }
    }

    private func dailyLimitLabel(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return lang.pick("\(hours) 小时", "\(hours) hr")
        }
        return lang.pick("\(minutes) 分钟", "\(minutes) min")
    }
}
