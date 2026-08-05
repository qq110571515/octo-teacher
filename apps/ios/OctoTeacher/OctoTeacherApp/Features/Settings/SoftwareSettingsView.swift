import SwiftUI

/// 「更多」里的统一软件设置入口。任何敏感配置都先经过家长 PIN 门禁。
struct SoftwareSettingsGateView: View {
    @Environment(ParentGate.self) private var gate
    @Environment(LocalFamilyStore.self) private var store

    var body: some View {
        Group {
            if gate.isUnlocked {
                SoftwareSettingsView()
            } else {
                ParentGateView()
                    .navigationTitle(
                        store.settings.resolvedParentInterfaceLanguage.pick("家长验证", "Parent Verification")
                    )
            }
        }
    }
}

/// 软件设置页。所有标题/说明必须在家长界面语言下完整显示：
/// 文案统一走 `AppInterfaceLanguage.pick` 的显式 String（不做 .strings 查找），
/// 保证不被系统语言驱动的 en.lproj 覆盖，也不会英文模式漏中文。
struct SoftwareSettingsView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @AppStorage(GuardianChildPreviewLanguagePreference.key)
    private var guardianChildPreviewLanguageRaw = GuardianChildPreviewLanguage.followChild.rawValue
    @State private var isTranslatingExistingTasks = false
    @State private var translationFeedback: String?

    private let supportedRegions: [FamilyRegion] = [.china, .usa]

    /// 家长界面语言：本页所有文案的唯一语言来源。
    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        Form {
            regionSection
            languageSection
            childRewardRulesSection
            accessibilitySection
            aiSection
            schoolSection
            familySection
            privacySection
            aboutSection
        }
        .navigationTitle(lang.pick("软件设置", "Software Settings"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var childRewardRulesSection: some View {
        Section {
            ForEach(store.children) { child in
                NavigationLink {
                    ChildProfileEditorView(child: child)
                } label: {
                    let policy = store.policy(for: child.id)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(child.name)
                            .font(.body.weight(.semibold))
                        Text(lang.pick(
                            "每日最多 \(dailyLimitLabel(child.dailyLimitMinutes)) · \(policy.resolvedScreenPointsPer15Minutes) 积分换 \(policy.resolvedScreenExchangeMinutes) 分钟",
                            "Up to \(dailyLimitLabel(child.dailyLimitMinutes)) daily · \(policy.resolvedScreenPointsPer15Minutes) points for \(policy.resolvedScreenExchangeMinutes) min"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("software-settings-reward-rules-\(child.id.uuidString.lowercased())")
            }
        } header: {
            Text(lang.pick("每个孩子的奖励规则", "Reward Rules for Each Child"))
        } footer: {
            Text(lang.pick(
                "这里不是首次设置。家长可以随时调整每个孩子每天最多可兑换多久、多少成长积分换多少分钟，以及零花钱和愿望规则；保存后会同步到该孩子的设备。",
                "These are ongoing controls, not first-run setup. Change each child's daily play-time cap, Growth Point rate, pocket-money rules, and wish rules at any time; saving syncs them to that child's device."
            ))
        }
    }

    private func dailyLimitLabel(_ minutes: Int) -> String {
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return lang.pick("\(minutes / 60) 小时", "\(minutes / 60) hr")
        }
        return lang.pick("\(minutes) 分钟", "\(minutes) min")
    }

    private var regionSection: some View {
        Section {
            Picker(lang.pick("软件使用地区", "Region"), selection: Binding(
                get: { store.settings.resolvedRegion == .usa ? .usa : .china },
                set: { store.setRegion($0) }
            )) {
                ForEach(supportedRegions, id: \.self) { region in
                    Text(region.label(for: lang)).tag(region)
                }
            }
            .accessibilityIdentifier("software-settings-region")
        } header: {
            Text(lang.pick("地区", "Region"))
                .accessibilityIdentifier("software-settings-region-header")
        } footer: {
            Text(lang.pick(
                "地区决定默认内容渠道、货币和学校接入区域；目前正式支持中国和美国。",
                "Region decides default content channels, currency, and school integration; China and the United States are officially supported."
            ))
        }
    }

    private var languageSection: some View {
        Section {
            Picker(lang.pick("家长界面", "Parent interface"), selection: Binding(
                get: { store.settings.resolvedParentInterfaceLanguage },
                set: {
                    translationFeedback = nil
                    store.setParentInterfaceLanguage($0)
                }
            )) {
                ForEach(AppInterfaceLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .accessibilityIdentifier("software-settings-parent-language")

            Picker(lang.pick("这台手机查看孩子端", "Child view on this phone"), selection: Binding(
                get: { GuardianChildPreviewLanguagePreference.resolve(guardianChildPreviewLanguageRaw) },
                set: { guardianChildPreviewLanguageRaw = $0.rawValue }
            )) {
                ForEach(GuardianChildPreviewLanguage.allCases) { language in
                    Text(language.label(for: lang)).tag(language)
                }
            }
            .accessibilityIdentifier("software-settings-child-preview-language")

            Picker(activeChildInterfaceLabel, selection: Binding(
                get: { store.activeChildInterfaceLanguage },
                set: { language in
                    store.setChildInterfaceLanguage(language, for: store.activeChildId)
                    familyCloud.queueGuardianProfileSync(
                        for: store.activeChildId,
                        fields: [.interfaceLanguage]
                    )
                    Task { await translateExistingTasksIfNeeded(target: language) }
                }
            )) {
                ForEach(AppInterfaceLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .accessibilityIdentifier("software-settings-child-language")

            Picker(lang.pick("家长 AI 内容", "Parent AI content"), selection: Binding(
                get: { store.settings.language },
                set: { store.setFamilyLanguage($0) }
            )) {
                ForEach(FamilyLanguage.allCases, id: \.self) { language in
                    Text(language.label(for: lang)).tag(language)
                }
            }

            Picker(childLearningContentLabel, selection: Binding(
                get: { store.activeContentLanguage },
                set: {
                    store.setContentLanguage($0, for: store.activeChildId)
                    familyCloud.queueGuardianProfileSync(
                        for: store.activeChildId,
                        fields: [.contentLanguage]
                    )
                }
            )) {
                ForEach(FamilyLanguage.allCases, id: \.self) { language in
                    Text(language.label(for: lang)).tag(language)
                }
            }

            NavigationLink {
                ParentChildrenManagerView()
            } label: {
                Label(
                    lang.pick("分别设置其他孩子", "Set each child separately"),
                    systemImage: "person.2"
                )
            }
            .accessibilityIdentifier("software-settings-per-child-language")

            if untranslatedTaskCount > 0 {
                Button {
                    Task { await translateExistingTasksIfNeeded(target: interfaceLanguageForChild) }
                } label: {
                    Label(
                        translateExistingButtonTitle,
                        systemImage: "character.book.closed"
                    )
                }
                .disabled(isTranslatingExistingTasks)
            }
            if let translationFeedback {
                Text(translationFeedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(lang.pick("语言", "Language"))
                .accessibilityIdentifier("software-settings-language-header")
        } footer: {
            Text(lang.pick(
                "“这台手机查看孩子端”只改变家长本机的预览，不会同步到孩子；“孩子手机的实际界面”会按孩子同步到其设备。学习内容语言控制任务、阅读与 AI 内容。家长可以中文预览，孩子手机同时保持英文。",
                "Child view on this phone changes only the guardian's local preview and never syncs to the child. The child's actual device setting syncs per child. Learning content language controls tasks, reading, and AI content. A guardian can preview in Chinese while the child's phone stays in English."
            ))
        }
    }

    private var accessibilitySection: some View {
        Section {
            Toggle(lang.pick("显示点读小喇叭", "Show read-aloud button"), isOn: Binding(
                get: { store.settings.resolvedReadAloud },
                set: { store.setReadAloud($0) }
            ))
            Toggle(lang.pick("云端真人语音", "Cloud natural voice"), isOn: Binding(
                get: { store.settings.resolvedCloudVoice },
                set: { store.setCloudVoice($0) }
            ))
        } header: {
            Text(lang.pick("朗读与无障碍", "Read-Aloud & Accessibility"))
        } footer: {
            Text(lang.pick(
                "小喇叭只在孩子主动点击后朗读，并跟随每个孩子自己的界面语言选择音色。云端语音需要家长配置的 AI 服务，失败时自动回落本机语音。",
                "The read-aloud button only speaks when the child taps it, and its voice follows each child's own interface language. Cloud voice needs the parent-configured AI service and falls back to the on-device voice on failure."
            ))
        }
    }

    private var aiSection: some View {
        Section {
            NavigationLink {
                ParentAIProviderSettingsView()
            } label: {
                HStack {
                    Label(lang.pick("AI 小伙伴与 API", "AI Buddy & API"), systemImage: "sparkles")
                    Spacer()
                    Text(aiProvider.isReadyForAIComposer ? connectedLabel : notConfiguredLabel)
                        .font(.caption)
                        .foregroundStyle(aiProvider.isReadyForAIComposer ? .green : .secondary)
                }
            }
            .accessibilityIdentifier("software-settings-ai-provider")
        } header: {
            Text(lang.pick("AI 服务", "AI Services"))
        } footer: {
            Text(lang.pick(
                "API 密钥只保存在这台设备的 Keychain；孩子记忆与家庭数据不会作为完整档案上传。",
                "API keys stay in this device's Keychain; child memories and family data are never uploaded as complete profiles."
            ))
        }
    }

    private var schoolSection: some View {
        Section {
            NavigationLink {
                ParentSchoolModeView()
            } label: {
                Label(lang.pick("学校模式与时间表", "School Mode & Schedule"), systemImage: "calendar.badge.clock")
            }
            .accessibilityIdentifier("software-settings-school-mode")

            NavigationLink {
                SchoolIntegrationSettingsView()
            } label: {
                HStack {
                    Label(lang.pick("学校后台接入", "School Integration"), systemImage: "building.columns")
                    Spacer()
                    Text(schoolStatusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("software-settings-school-integration")
        } header: {
            Text(lang.pick("学校", "School"))
        } footer: {
            Text(lang.pick(
                "学校模式在本机执行时间表与受控 App 遮挡；学校后台是未来的机构连接。未连接前不会上传作业、成绩或孩子信息。",
                "School Mode enforces schedules and app shields on-device; School Integration is the future institution connection. Nothing about homework, grades, or the child is uploaded before connecting."
            ))
        }
    }

    private var familySection: some View {
        Section {
            NavigationLink {
                ParentChildrenManagerView()
            } label: {
                Label(lang.pick("孩子档案", "Child Profiles"), systemImage: "person.2")
            }
            NavigationLink {
                FamilyMembersView()
            } label: {
                Label(lang.pick("家庭成员与设备", "Family Members & Devices"), systemImage: "person.3.sequence")
            }
        } header: {
            Text(lang.pick("家庭", "Family"))
        }
    }

    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacyAndDataSettingsView()
            } label: {
                Label(lang.pick("隐私与本机数据", "Privacy & Local Data"), systemImage: "hand.raised")
            }
        }
    }

    private var aboutSection: some View {
        Section(lang.pick("关于 章鱼老师", "About 章鱼老师")) {
            LabeledContent(lang.pick("版本", "Version"), value: BuildIdentity.shortVersionText)
            LabeledContent(lang.pick("构建提交", "Build Commit"), value: BuildIdentity.commit)
        }
    }

    private var schoolStatusLabel: String {
        switch store.settings.resolvedSchoolIntegration.status {
        case .notConnected: return lang.pick("未连接", "Not connected")
        case .pending: return lang.pick("等待学校确认", "Waiting for school")
        case .connected: return lang.pick("已连接", "Connected")
        case .suspended: return lang.pick("已暂停", "Paused")
        }
    }

    private var activeChildInterfaceLabel: String {
        let name = store.childDisplayName(store.child, for: lang)
        return lang.pick("\(name) 手机的实际界面", "\(name)'s actual device")
    }

    private var childLearningContentLabel: String {
        let name = store.childDisplayName(store.child, for: lang)
        return lang.pick("\(name) 的学习内容", "\(name)'s learning content")
    }

    private var connectedLabel: String { lang.pick("已连接", "Connected") }
    private var notConfiguredLabel: String { lang.pick("未配置", "Not configured") }

    private var interfaceLanguageForChild: AppInterfaceLanguage {
        store.activeChildInterfaceLanguage
    }

    private var untranslatedAssignments: [TaskAssignment] {
        store.assignments.filter { assignment in
            assignment.childId == store.activeChildId
                && assignment.status != .cancelled
                && assignment.task.localizedContent?.contains(where: {
                    $0.language == interfaceLanguageForChild
                }) != true
                && AITaskTranslator.needsTranslation(
                    title: assignment.task.title,
                    instructions: assignment.task.instructions,
                    target: interfaceLanguageForChild
                )
        }
    }

    private var untranslatedTaskCount: Int { untranslatedAssignments.count }

    private var translateExistingButtonTitle: String {
        if isTranslatingExistingTasks {
            return lang.pick("正在翻译已有任务……", "Translating existing tasks…")
        }
        return lang.pick(
            "翻译已有任务（\(untranslatedTaskCount)）",
            "Translate existing tasks (\(untranslatedTaskCount))"
        )
    }

    @MainActor
    private func translateExistingTasksIfNeeded(target: AppInterfaceLanguage) async {
        let pending = store.assignments.filter { assignment in
            assignment.childId == store.activeChildId
                && assignment.status != .cancelled
                && assignment.task.localizedContent?.contains(where: { $0.language == target }) != true
                && AITaskTranslator.needsTranslation(
                    title: assignment.task.title,
                    instructions: assignment.task.instructions,
                    target: target
                )
        }
        guard !pending.isEmpty else {
            translationFeedback = nil
            return
        }
        guard aiProvider.isReadyForAIComposer else {
            translationFeedback = lang.pick(
                "还有 \(pending.count) 个已有任务需要翻译。请先配置 AI API，再点这里重试。",
                "\(pending.count) existing tasks still need translation. Configure the AI API, then retry."
            )
            return
        }

        isTranslatingExistingTasks = true
        defer { isTranslatingExistingTasks = false }
        var translatedCount = 0
        do {
            for chunk in pending.chunked(into: 20) {
                let inputs = chunk.map {
                    AITaskTranslator.BatchInput(
                        id: $0.id,
                        title: $0.task.title,
                        instructions: $0.task.instructions
                    )
                }
                let expected = Set(inputs.map(\.id))
                let raw = try await aiProvider.completeDraftJSON(
                    system: AITaskTranslator.batchSystemPrompt(target: target),
                    user: AITaskTranslator.batchUserPrompt(inputs),
                    using: OpenAIStyleChatClient()
                )
                guard let translations = AITaskTranslator.parseBatch(
                    raw,
                    language: target,
                    expectedIDs: expected
                ) else { throw AIChatError.badResponse }
                for (assignmentID, content) in translations {
                    if store.setTaskLocalizedContent(assignmentId: assignmentID, content: content) {
                        translatedCount += 1
                    }
                }
            }
            translationFeedback = lang.pick(
                "已准备 \(translatedCount) 个已有任务的孩子端版本。",
                "Prepared child-facing versions for \(translatedCount) existing tasks."
            )
        } catch {
            translationFeedback = lang.pick(
                "已有任务翻译未完成，请检查 AI 连接后重试；原任务没有被修改。",
                "Existing task translation did not finish. Check the AI connection and retry; original tasks were not changed."
            )
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private struct SchoolIntegrationSettingsView: View {
    @Environment(LocalFamilyStore.self) private var store

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(lang.pick("状态", "Status"), value: statusLabel)
                if let school = integration.schoolDisplayName, !school.isEmpty {
                    LabeledContent(lang.pick("学校", "School"), value: school)
                }
            } header: {
                Text(lang.pick("接入状态", "Connection Status"))
            }

            Section {
                Label(lang.pick("扫描学校二维码", "Scan school QR code"), systemImage: "qrcode.viewfinder")
                    .foregroundStyle(.secondary)
                Label(lang.pick("输入学校机构代码", "Enter school institution code"), systemImage: "number.square")
                    .foregroundStyle(.secondary)
            } header: {
                Text(lang.pick("未来接入方式", "Future Connection Methods"))
            } footer: {
                Text(lang.pick(
                    "学校后台上线后，这两个入口才会开放。家庭不能自行伪造学校连接。",
                    "These entries open once the school backend is live. Families cannot forge a school connection."
                ))
            }

            Section {
                Toggle(lang.pick("允许老师布置家庭作业", "Allow teachers to assign homework"), isOn: binding(\.allowsTeacherAssignments))
                Toggle(lang.pick("向老师共享作业完成状态", "Share homework completion with teachers"), isOn: binding(\.sharesHomeworkCompletion))
            } header: {
                Text(lang.pick("数据权限", "Data Permissions"))
            } footer: {
                Text(lang.pick(
                    "当前未连接，开关只记录家庭意愿，不会传输任何数据。正式连接时会再次向家长确认。",
                    "While disconnected these switches only record family intent; no data is transferred. Parents confirm again at real connection time."
                ))
            }
        }
        .navigationTitle(lang.pick("学校后台接入", "School Integration"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var integration: SchoolIntegrationSettings {
        store.settings.resolvedSchoolIntegration
    }

    private var statusLabel: String {
        switch integration.status {
        case .notConnected: return lang.pick("未连接", "Not connected")
        case .pending: return lang.pick("等待学校确认", "Waiting for school")
        case .connected: return lang.pick("已连接", "Connected")
        case .suspended: return lang.pick("已暂停", "Paused")
        }
    }

    private func binding(_ keyPath: WritableKeyPath<SchoolIntegrationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { integration[keyPath: keyPath] },
            set: { value in
                var updated = integration
                updated[keyPath: keyPath] = value
                store.setSchoolIntegration(updated)
            }
        )
    }
}

private struct PrivacyAndDataSettingsView: View {
    @Environment(LocalFamilyStore.self) private var store

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        List {
            Section(lang.pick("本机保存", "Stored on This Device")) {
                Label(lang.pick("孩子档案、任务、成长记录与 AI 记忆", "Child profiles, tasks, growth records, and AI memories"), systemImage: "iphone")
                Label(lang.pick("电子书、阅读进度与聊天记录", "Books, reading progress, and chat history"), systemImage: "internaldrive")
            }
            Section(lang.pick("只在需要时发送", "Sent Only When Needed")) {
                Label(lang.pick("AI 请求只发送当前任务所需的裁剪内容", "AI requests send only the trimmed content the current task needs"), systemImage: "shield.lefthalf.filled")
                Label(lang.pick("学校数据在家长授权并正式连接前不会发送", "School data is never sent before parent authorization and a real connection"), systemImage: "building.columns")
            }
            Section {
                Text(lang.pick(
                    "后续运营版会在这里加入家庭数据导出、删除、授权记录与设备迁移。",
                    "Later releases will add family data export, deletion, authorization logs, and device migration here."
                ))
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(lang.pick("隐私与本机数据", "Privacy & Local Data"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
