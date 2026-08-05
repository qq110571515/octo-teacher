import SwiftUI

#if canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
#endif

/// 孩子端与家长本机预览共用的轻量设置页。
/// 孩子真机语言写回云端孩子档案；家长预览语言只保存在家长当前设备。
struct ChildSurfaceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @AppStorage(GuardianChildPreviewLanguagePreference.key)
    private var guardianPreviewLanguageRaw = GuardianChildPreviewLanguage.followChild.rawValue
    @State private var isSavingLanguage = false
    @State private var localError: String?

    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(loc.pick("语言", "Language")) {
                    if familyCloud.isChildDevice {
                        Picker(
                            loc.pick("这台孩子手机", "This child device"),
                            selection: Binding(
                                get: { store.activeChildInterfaceLanguage },
                                set: { updateChildDeviceLanguage($0) }
                            )
                        ) {
                            ForEach(AppInterfaceLanguage.allCases) { language in
                                Text(language.label).tag(language)
                            }
                        }
                        Text(loc.pick(
                            "保存后会通过家庭云同步到家长端；任务内容和进度不会改变。",
                            "This setting syncs through Family Cloud. Tasks and progress do not change."
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        Picker(
                            loc.pick("这台家长手机的孩子端预览", "Child preview on this parent phone"),
                            selection: Binding(
                                get: { GuardianChildPreviewLanguagePreference.resolve(guardianPreviewLanguageRaw) },
                                set: { guardianPreviewLanguageRaw = $0.rawValue }
                            )
                        ) {
                            ForEach(GuardianChildPreviewLanguage.allCases) { language in
                                Text(language.label(for: store.settings.resolvedParentInterfaceLanguage))
                                    .tag(language)
                            }
                        }
                        Text(loc.pick(
                            "这里只改变家长手机的预览语言，不会覆盖孩子手机。",
                            "This only changes the preview on this parent phone, not the child's device."
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                Section(loc.pick("家庭云", "Family Cloud")) {
                    Button {
                        Task { await syncNow() }
                    } label: {
                        HStack {
                            Label(loc.pick("立即同步", "Sync now"), systemImage: "arrow.clockwise")
                            Spacer()
                            if familyCloud.isWorking || isSavingLanguage {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(familyCloud.isWorking || isSavingLanguage)
                    .accessibilityIdentifier("child-settings-cloud-refresh")

                    if let lastSyncAt = familyCloud.lastSyncAt {
                        LabeledContent(
                            loc.pick("上次同步", "Last sync"),
                            value: lastSyncAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    if let error = localError ?? familyCloud.lastSyncError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section(loc.pick("关于", "About")) {
                    LabeledContent(
                        loc.pick("孩子", "Child"),
                        value: store.childDisplayName(store.child, for: childSurfaceLanguage)
                    )
                    LabeledContent(
                        loc.pick("版本", "Version"),
                        value: BuildIdentity.shortVersionText
                    )
                    .accessibilityIdentifier("child-settings-version")
                }
            }
            .navigationTitle(loc.pick("孩子端设置", "Child settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(loc.pick("完成", "Done")) { dismiss() }
                }
            }
        }
    }

    private func updateChildDeviceLanguage(_ language: AppInterfaceLanguage) {
        store.setChildInterfaceLanguage(language, for: store.activeChildId)
        localError = nil
        isSavingLanguage = true
        Task {
            defer { isSavingLanguage = false }
            do {
                try await familyCloud.updateChildInterfaceLanguage(language, in: store)
            } catch {
                localError = error.localizedDescription
            }
        }
    }

    private func syncNow() async {
        localError = nil
        do {
            try await familyCloud.refreshChildSurface(into: store, forceFullSnapshot: true)
        } catch {
            localError = error.localizedDescription
        }
    }
}

/// 孩子首页：打开就知道「现在先做什么」。
///
/// 第一屏顺序：现在先做这个 → AI 小伙伴 → 今日任务 → 我的成长积分 → 任务包进度 → 更多。
/// 不在孩子首页展示结算、审计、同步等技术区块。
struct ChildHomeView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(MockScreenTimeController.self) private var screenTimeController
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @Environment(ScreenTimePOCManager.self) private var screenTime
    #endif
    private let taskWorkbenchBuilder = MobileTodayTaskPackageWorkbenchBuilder()
    @State private var isRewardMenuExpanded: Bool
    @State private var isMoreExpanded: Bool
    @State private var showsScreenTimeManagement = false
    @State private var showsChildSurfaceSettings = false

    init() {
        let isUITest = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-OctoTeacherUITest") }
        _isRewardMenuExpanded = State(initialValue: isUITest)
        _isMoreExpanded = State(initialValue: isUITest)
    }

    /// 当前孩子的界面语言上下文：本页所有文案统一从这里取，跟随活跃孩子切换。
    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    var body: some View {
        if familyCloud.childDeviceRebindRequired {
            return AnyView(ChildDeviceRebindView(language: childSurfaceLanguage))
        }
        // 幼儿模式：整页换成大图标卡片界面 + 手动小喇叭点读。
        if store.isPreReaderActive {
            return AnyView(PreReaderHomeView())
        }
        let taskWorkbench = taskWorkbenchBuilder.build(
            store: store,
            offlineStatus: offlineOutbox.publicStatus
        )
        let rows = taskRows(for: taskWorkbench)
        let activeRows = rows.filter { $0.card.state != .done }
        let completedRows = rows.filter { $0.card.state == .done }

        return AnyView(
            List {
                cloudSyncSection
                growthPointsSummarySection
                screenTimeSetupSection
                schoolModeSection
                nextStepSection(rows: rows)
                aiCompanionSection
                todayTasksSection(
                    rows: activeRows,
                    hasCompletedTasks: !completedRows.isEmpty
                )
                completedTasksSection(rows: completedRows)
                creativeCenterSection
                creditSection
                moreSection
                versionFooterSection
            }
            .navigationTitle(loc.pick(
                "\(store.childDisplayName(store.child, for: .chinese))的成长计划",
                "\(store.childDisplayName(store.child, for: .english))'s Growth Plan"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.top, 8, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(ChildVisualTheme.pageBackground)
            .tint(ChildVisualTheme.action)
            .refreshable { await refreshCloudTasks(forceFullSnapshot: true) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshCloudTasks(forceFullSnapshot: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(familyCloud.isWorking)
                    .accessibilityLabel(loc.pick("同步家庭任务", "Sync family tasks"))
                    .accessibilityIdentifier("child-home-cloud-refresh")

                    Button {
                        showsChildSurfaceSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(loc.pick("孩子端设置", "Child settings"))
                    .accessibilityIdentifier("child-home-settings")

                    if store.hasMultipleChildren {
                        Menu {
                            ForEach(store.children) { member in
                                Button {
                                    store.setActiveChild(member.id)
                                } label: {
                                    if member.id == store.activeChildId {
                                        Label(member.name, systemImage: "checkmark")
                                    } else {
                                        Text(member.name)
                                    }
                                }
                            }
                        } label: {
                            Label(loc.pick("换人", "Switch"), systemImage: "person.2")
                        }
                        .accessibilityIdentifier("child-home-switch-child")
                    }
                }
            }
            .sheet(isPresented: $showsChildSurfaceSettings) {
                ChildSurfaceSettingsView()
            }
            .task { await refreshCloudTasks(forceFullSnapshot: false) }
        )
    }

    @ViewBuilder
    private var screenTimeSetupSection: some View {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let screenTimeStatus = familyCloud.childDeviceProfile?.screenTimeStatus
        let needsRecovery = screenTimeStatus?.enforcement == .error ||
            screenTimeStatus?.authorization == .denied ||
            screenTimeStatus?.authorization == .error
        if familyCloud.isChildDevice,
           !screenTime.localChildSetupIsComplete || needsRecovery {
            Section {
                ChildScreenTimeAuthorizationCard(language: loc.language)
            }
        }
        #endif
    }

    private func refreshCloudTasks(forceFullSnapshot: Bool) async {
        do {
            try await familyCloud.refreshChildSurface(
                into: store,
                forceFullSnapshot: forceFullSnapshot
            )
        } catch {
            // The sync row remains visible and explains how to retry.
        }
    }

    @ViewBuilder
    private var cloudSyncSection: some View {
        if familyCloud.isWorking || familyCloud.lastSyncError != nil {
            Section {
                HStack(spacing: 10) {
                    if familyCloud.isWorking {
                        ProgressView()
                        Text(loc.pick("正在更新家庭任务…", "Updating family tasks…"))
                    } else {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundStyle(.orange)
                        Text(loc.pick("同步暂时失败，请向下拉重试。", "Sync paused. Pull down to try again."))
                    }
                }
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("child-cloud-sync-status")
            }
        }
    }

    private var growthPointsSummarySection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.green)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc.pick("我的成长积分", "My Growth Points"))
                        .font(.subheadline.weight(.semibold))
                    Text(loc.pick("家庭云已对齐的可用积分", "Available points synced through Family Cloud"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(store.creditBalance.availableMinutes)")
                    .font(.title2.bold())
                    .monospacedDigit()
            }
            .accessibilityIdentifier("child-home-growth-points")
        }
    }

    @ViewBuilder
    private var schoolModeSection: some View {
        let profile = store.schoolModeProfile(for: store.activeChildId)
        let evaluation = SchoolModeRuleEngine.evaluate(profile: profile, at: Date())
        if profile.isEnabled {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: evaluation.isActive ? "building.columns.fill" : "calendar.badge.clock")
                        .foregroundStyle(evaluation.isActive ? Color.blue : Color.secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.pick("学校模式", "School Mode"))
                            .font(.subheadline.bold())
                        Text(schoolModeMessage(evaluation))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    SpeakButton(text: schoolModeMessage(evaluation))
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func schoolModeMessage(_ evaluation: SchoolModeEvaluation) -> String {
        if evaluation.isActive, let end = evaluation.endsAt {
            return loc.pick(
                "现在是学校时间，娱乐 App 会在 \(end.formatted(date: .omitted, time: .shortened)) 后恢复。",
                "School time is active. Entertainment apps return after \(end.formatted(date: .omitted, time: .shortened))."
            )
        }
        return loc.pick("学校模式已安排，当前不在上学时段。", "School Mode is scheduled, but school hours are not active now.")
    }

    private var creativeCenterSection: some View {
        let snapshot = CreativeCenterSnapshot.build(
            assignments: store.assignments,
            childId: store.activeChildId
        )
        return Section {
            NavigationLink {
                ChildCreativeCenterView()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(.purple)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(loc.pick("创作广场", "Creation Plaza"))
                            .font(.subheadline.bold())
                        Text(snapshot.totalCount == 0
                             ? loc.pick(
                                "画画、音乐、手工、积木、乐高、故事和表演，都可以成为你的作品。",
                                "Drawing, music, crafts, blocks, LEGO, stories, and performances can all become your works."
                             )
                             : loc.pick(
                                "\(snapshot.active.count) 个等你开始 · \(snapshot.submittedWorkCount) 件作品",
                                "\(snapshot.active.count) waiting for you · \(snapshot.submittedWorkCount) works"
                             ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    SpeakButton(text: loc.pick(
                        "创作广场。画画、音乐、手工、积木、乐高、玩具、故事和表演，都可以成为你的作品。",
                        "Creation Plaza. Drawing, music, crafts, blocks, LEGO, toys, stories, and performances can all become your works."
                    ))
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("child-creative-center-entry")
        }
    }

    // MARK: - AI 章鱼老师

    private var aiCompanionSection: some View {
        Section {
            NavigationLink {
                ChildAICompanionView()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(BrandIdentity.logoAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.child.companionDisplayName(for: loc.language))
                            .font(.subheadline.bold())
                        Text(loc.pick(
                            "聊天、拍照、说话，或请我把困难拆成下一小步。",
                            "Chat, share a photo, talk, or ask me to break a hard thing into one small step."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    SpeakButton(text: loc.pick(
                        "\(store.child.companionDisplayName(for: loc.language))。你可以聊天、拍照、说话，或者让我帮你想下一小步。",
                        "\(store.child.companionDisplayName(for: loc.language)). You can chat, share a photo, talk, or ask me for one small next step."
                    ))
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("child-home-ai-companion")
        }
    }

    // MARK: - 现在先做这个

    @ViewBuilder
    private func nextStepSection(rows: [TodayTaskPackageRow]) -> some View {
        let next = rows.first { $0.card.state == .active || $0.card.state == .redo }
        let completion = store.todayCompletion

        Section {
            if completion.total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(loc.pick(
                            "今天完成 \(completion.done)/\(completion.total)",
                            "Done today \(completion.done)/\(completion.total)"
                        ))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if completion.done == completion.total {
                            Text(loc.pick("全部完成！🎉", "All done! 🎉"))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                        }
                    }
                    ProgressView(value: Double(completion.done), total: Double(max(1, completion.total)))
                        .tint(.green)
                }
                .accessibilityIdentifier("child-home-progress")
            }
            if let next {
                NavigationLink {
                    TaskDetailView(assignment: next.assignment)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            next.card.state == .redo
                                ? loc.pick("再试一次", "Try again")
                                : loc.pick("现在先做这个", "Do this first"),
                            systemImage: next.card.state == .redo ? "arrow.uturn.backward.circle.fill" : "star.fill"
                        )
                        .font(.caption.weight(.bold))
                        .foregroundStyle(next.card.state == .redo ? Color.red : Color.orange)
                        Text(next.assignment.task.displayTitle(for: childSurfaceLanguage))
                            .font(.title3.bold())
                        HStack {
                            Text(loc.pick(
                                "做完可以获得 \(GrowthCreditCopy.label(points: next.card.rewardMinutes, language: loc.language))",
                                "Finish it to earn \(GrowthCreditCopy.label(points: next.card.rewardMinutes, language: loc.language))"
                            ))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            SpeakButton(text: loc.pick(
                                "现在先做这个：\(next.assignment.task.displayTitle(for: childSurfaceLanguage))。做完可以获得 \(GrowthCreditCopy.label(points: next.card.rewardMinutes, language: loc.language))。",
                                "Do this first: \(next.assignment.task.displayTitle(for: childSurfaceLanguage)). Finish it to earn \(GrowthCreditCopy.label(points: next.card.rewardMinutes, language: loc.language))."
                            ))
                        }
                        HStack(spacing: 6) {
                            Label(
                                next.card.state == .redo
                                    ? loc.pick("补充证明", "Add proof")
                                    : loc.pick("开始", "Start"),
                                systemImage: next.card.state == .redo ? "arrow.uturn.forward.circle.fill" : "play.circle.fill"
                            )
                            .accessibilityIdentifier("child-home-next-step-action")
                            Image(systemName: next.card.state == .redo ? "exclamationmark.circle.fill" : "circle.fill")
                                .font(.system(size: 7))
                                .accessibilityLabel(next.card.state == .redo ? loc.pick("需要重做", "Needs another try") : loc.pick("可以开始", "Ready to start"))
                                .accessibilityIdentifier("child-home-task-status-\(next.card.publicTaskRef)")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(next.card.state == .redo ? Color.red : Color.blue)
                    }
                    .padding(.vertical, 6)
                }
                .accessibilityIdentifier("child-home-next-step")
            } else if rows.contains(where: { $0.card.state == .waitingCheck }) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(loc.pick("等大人确认中", "Waiting for a grown-up's check"), systemImage: "hourglass")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text(loc.pick(
                        "你已经提交啦，等爸爸妈妈看过就能拿到成长积分。",
                        "You handed it in — once Mom or Dad takes a look, you'll get your Growth Points."
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(loc.pick("今天的任务都完成啦", "All of today's tasks are done"), systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(loc.pick(
                        "太棒了！可以用成长积分去换屏幕时间、零花钱或愿望，或者休息一下。",
                        "Amazing! Trade your Growth Points for screen time, pocket money, or a wish — or just take a break."
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(loc.pick("今天还没有任务", "No tasks yet today"), systemImage: "moon.stars")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(loc.pick(
                        "等爸爸妈妈在「家长」里布置任务，这里就会出现。",
                        "Once Mom or Dad assigns tasks in Parent, they'll show up here."
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .accessibilityIdentifier("child-home-next-step-empty")
            }
        }
    }

    // MARK: - 今日任务

    @ViewBuilder
    private func todayTasksSection(
        rows: [TodayTaskPackageRow],
        hasCompletedTasks: Bool
    ) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(taskSections(rows: rows)) { section in
                    DisclosureGroup {
                        ForEach(childTaskDisplayItems(for: section.rows)) { item in
                            switch item {
                            case .task(let row):
                                NavigationLink {
                                    TaskDetailView(assignment: row.assignment)
                                } label: {
                                    HStack(spacing: 8) {
                                        ChildTaskIconBadge(
                                            icon: TaskIconProvider.icon(
                                                for: row.assignment.task,
                                                displayTitle: row.assignment.task.displayTitle(for: childSurfaceLanguage)
                                            ),
                                            size: 38,
                                            accent: ChildVisualTheme.accent(for: row.assignment.task)
                                        )
                                        TodayTaskPackageCardView(card: row.card, task: row.assignment.task)
                                        Spacer(minLength: 4)
                                        SpeakButton(text: loc.pick(
                                            "\(section.title)任务：\(row.assignment.task.displayTitle(for: childSurfaceLanguage))，奖励 \(GrowthCreditCopy.label(points: row.card.rewardMinutes))。",
                                            "\(section.title) task: \(row.assignment.task.displayTitle(for: childSurfaceLanguage)). Reward: \(GrowthCreditCopy.label(points: row.card.rewardMinutes, language: .english))."
                                        ))
                                    }
                                }
                                .accessibilityIdentifier("child-home-task-\(row.card.publicTaskRef)")
                            case .readingBook(let group):
                                NavigationLink {
                                    ChildReadingBookTaskGroupDetailView(group: group)
                                } label: {
                                    ChildReadingBookTaskGroupRow(group: group, sectionTitle: section.title)
                                }
                                .accessibilityIdentifier("child-home-reading-book-\(group.id)")
                            }
                        }
                    } label: {
                        HStack {
                            Label(section.title, systemImage: section.systemImage)
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Text(section.progressText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(loc.pick("今日成长计划", "Today's Growth Plan"))
            }
        } else if hasCompletedTasks {
            Section(loc.pick("今日成长计划", "Today's Growth Plan")) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(loc.pick("今天待做已清空", "Nothing left to do today"), systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(loc.pick(
                        "已完成的内容单独放在下面「完成回看」，可以回顾自己今天做成了什么。",
                        "Finished items live in Completed Review below, so you can look back at what you achieved today."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("child-home-active-tasks-cleared")
            }
        } else {
            Section(loc.pick("今日成长计划", "Today's Growth Plan")) {
                NavigationLink {
                    ChildAICompanionView()
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(loc.pick("今天没有新任务", "No new tasks today"), systemImage: "checklist")
                            .font(.subheadline.weight(.semibold))
                        Text(loc.pick(
                            "可以先复习徽章、看看成长积分，或者问 \(store.child.companionDisplayName(for: loc.language)) 帮你想一个小练习。",
                            "Review your badges, check your Growth Points, or ask \(store.child.companionDisplayName(for: loc.language)) for a little practice idea."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(loc.pick("问问 \(store.child.companionDisplayName(for: loc.language))", "Ask \(store.child.companionDisplayName(for: loc.language))"), systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(loc.pick(
                    "今天没有新任务，可以问 AI 章鱼老师帮你想一个小练习",
                    "No new tasks today; ask AI Octo Teacher for a little practice idea"
                ))
                .accessibilityIdentifier("child-home-empty-tasks-ai")
            }
        }
    }

    @ViewBuilder
    private func completedTasksSection(rows: [TodayTaskPackageRow]) -> some View {
        if !rows.isEmpty {
            Section {
                DisclosureGroup {
                    ForEach(childTaskDisplayItems(for: rows)) { item in
                        switch item {
                        case .task(let row):
                            NavigationLink {
                                TaskDetailView(assignment: row.assignment)
                            } label: {
                                HStack(spacing: 8) {
                                    ChildTaskIconBadge(
                                        icon: TaskIconProvider.icon(
                                            for: row.assignment.task,
                                            displayTitle: row.assignment.task.displayTitle(for: childSurfaceLanguage)
                                        ),
                                        size: 34,
                                        accent: ChildVisualTheme.accent(for: row.assignment.task)
                                    )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(row.assignment.task.displayTitle(for: childSurfaceLanguage))
                                            .font(.subheadline.weight(.semibold))
                                        Text(loc.pick(
                                            "已获得 \(GrowthCreditCopy.label(points: row.card.rewardMinutes))",
                                            "Earned \(GrowthCreditCopy.label(points: row.card.rewardMinutes, language: .english))"
                                        ))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    SpeakButton(text: loc.pick(
                                        "已完成：\(row.assignment.task.displayTitle(for: childSurfaceLanguage))。你已经获得 \(GrowthCreditCopy.label(points: row.card.rewardMinutes))。",
                                        "Completed: \(row.assignment.task.displayTitle(for: childSurfaceLanguage)). You earned \(GrowthCreditCopy.label(points: row.card.rewardMinutes, language: .english))."
                                    ))
                                }
                            }
                            .accessibilityIdentifier("child-home-completed-task-\(row.card.publicTaskRef)")
                        case .readingBook(let group):
                            NavigationLink {
                                ChildReadingBookTaskGroupDetailView(group: group)
                            } label: {
                                ChildReadingBookTaskGroupRow(group: group, sectionTitle: loc.pick("已完成阅读", "Completed reading"))
                            }
                            .accessibilityIdentifier("child-home-completed-reading-book-\(group.id)")
                        }
                    }
                } label: {
                    HStack {
                        Label(loc.pick("已完成任务", "Completed tasks"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.green)
                        Spacer()
                        Text(loc.pick("\(rows.count) 个", "\(rows.count)"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("child-home-completed-tasks")
            } header: {
                Text(loc.pick("完成回看", "Completed Review"))
            } footer: {
                Text(loc.pick(
                    "这里只放已经确认完成的任务，孩子能清楚看到自己做成了哪些事。",
                    "Only confirmed, finished tasks live here, so kids can clearly see what they accomplished."
                ))
            }
        }
    }

    private func taskSections(rows: [TodayTaskPackageRow]) -> [TodayTaskDisplaySection] {
        let packSections = PackType.allCases.compactMap { packType -> TodayTaskDisplaySection? in
            let group = rows.filter { $0.assignment.task.packType == packType }
            guard !group.isEmpty else { return nil }
            return TodayTaskDisplaySection(
                id: "pack-\(packType.rawValue)",
                title: packType.label(for: loc.language),
                summary: packageSummary(for: packType, rows: group),
                systemImage: packType.systemImage,
                rows: group
            )
        }

        let categorySections = TaskCategory.childDisplayOrder.compactMap { category -> TodayTaskDisplaySection? in
            let group = rows.filter { $0.assignment.task.packType == nil && $0.assignment.task.category == category }
            guard !group.isEmpty else { return nil }
            return TodayTaskDisplaySection(
                id: "category-\(category.rawValue)",
                title: category.label(for: loc.language),
                summary: "",
                systemImage: category.systemImage,
                rows: group
            )
        }

        return packSections + categorySections
    }

    private func packageSummary(for packType: PackType, rows: [TodayTaskPackageRow]) -> String {
        switch packType {
        case .basicHabits:
            return loc.pick(
                "这是一个大项：点开后完成睡觉、洗漱、穿衣、书包、房间等独立小步骤。",
                "This is one big item: open it to finish small steps like bedtime, washing up, dressing, school bag, and room."
            )
        case .chores:
            return loc.pick(
                "这是一个大项：点开后完成餐桌、垃圾、植物、整理等家庭协作小步骤。",
                "This is one big item: open it to finish small family steps like the table, trash, plants, and tidying."
            )
        case .outdoorSports:
            return loc.pick(
                "这是一个大项：点开后完成跳绳、骑车、公园活动或家长自定义的户外运动。",
                "This is one big item: open it for jump rope, biking, park time, or parent-made outdoor activities."
            )
        default:
            let remaining = rows.filter { $0.card.state == .active || $0.card.state == .redo }.count
            return remaining > 0
                ? loc.pick("还有 \(remaining) 个分项可以推进。", "\(remaining) sub-items left to move forward.")
                : loc.pick("分项都在下面。", "All sub-items are below.")
        }
    }

    // MARK: - 我的成长积分

    private var creditSection: some View {
        let rewardPathway = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTimeController,
            viewerRole: .child
        )

        return Section(loc.pick("我的成长积分", "My Growth Points")) {
            CreditBalanceCard(balance: store.creditBalance)
            NavigationLink {
                ChildCreditWalletView()
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            loc.pick("我的奖励", "My Rewards"),
                            systemImage: "wallet.pass.fill"
                        )
                        Text(loc.pick("玩一会儿、许愿或看徽章", "Play time, wishes, and badges"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    SpeakButton(text: loc.pick(
                        "打开我的奖励，看看成长积分能换什么。",
                        "Open My Rewards to see what your Growth Points can get."
                    ))
                }
            }
            .accessibilityIdentifier("child-home-quick-access-creditWallet")

            DisclosureGroup(isExpanded: $isRewardMenuExpanded) {
                ForEach(rewardPathway.outlets) { outlet in
                    rewardOutletLink(outlet)
                }
            } label: {
                Label(loc.pick("我想换……", "I want to get…"), systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }

            NavigationLink {
                ChildBadgesView()
            } label: {
                HStack {
                    Label(loc.pick("我的徽章馆", "My Badge Hall"), systemImage: "trophy.fill")
                    Spacer()
                    SpeakButton(text: loc.pick(
                        "徽章馆：看看你每个学科学了多久，拿到了什么徽章。",
                        "Badge Hall: see how long you've studied each subject and which badges you earned."
                    ))
                }
            }
            .accessibilityIdentifier("child-home-badges")
        }
    }

    @ViewBuilder
    private func rewardOutletLink(_ outlet: RewardPathwayOutlet) -> some View {
        switch outlet.kind {
        case .screenTime:
            NavigationLink {
                if outlet.suggestedRoute == .earnCredits {
                    ChildCreditWalletView()
                } else {
                    RewardRedemptionView()
                }
            } label: {
                rewardOutletLabel(outlet)
            }
            .accessibilityIdentifier("child-home-reward-redemption")
        case .pocketMoney:
            NavigationLink {
                ChildPocketMoneyView()
            } label: {
                rewardOutletLabel(outlet)
            }
            .accessibilityIdentifier("child-home-pocket-money")
        case .wishList:
            NavigationLink {
                ChildPocketMoneyView()
            } label: {
                rewardOutletLabel(outlet)
            }
            .accessibilityIdentifier("child-home-wish-list")
        }
    }

    private func rewardOutletLabel(_ outlet: RewardPathwayOutlet) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon(for: outlet.kind))
                .foregroundStyle(tint(for: outlet.kind, status: outlet.status))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(childRewardTitle(for: outlet.kind))
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(outlet.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint(for: outlet.kind, status: outlet.status))
                }
                Text(childRewardHint(for: outlet.kind))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            SpeakButton(text: loc.pick(
                "\(outlet.title)：\(outlet.status)。\(outlet.nextStep)。\(outlet.speakText)",
                "\(outlet.title): \(outlet.status). \(outlet.nextStep). \(outlet.speakText)"
            ))
        }
    }

    private func childRewardTitle(for kind: RewardPathwayOutletKind) -> String {
        switch kind {
        case .screenTime: return loc.pick("玩一会儿", "Play Time")
        case .pocketMoney: return loc.pick("零花钱", "Pocket Money")
        case .wishList: return loc.pick("我的愿望", "My Wishes")
        }
    }

    private func childRewardHint(for kind: RewardPathwayOutletKind) -> String {
        switch kind {
        case .screenTime: return loc.pick("选一个 App 和使用时间", "Choose an app and time")
        case .pocketMoney: return loc.pick("交给大人确认", "A grown-up checks it")
        case .wishList: return loc.pick("把想要的东西记下来", "Save something you want")
        }
    }

    private func icon(for kind: RewardPathwayOutletKind) -> String {
        switch kind {
        case .screenTime: return "gamecontroller.fill"
        case .pocketMoney: return "banknote.fill"
        case .wishList: return "gift.fill"
        }
    }

    private func tint(for kind: RewardPathwayOutletKind, status: String) -> Color {
        let positiveMarkers = ["可以", "兑换", "正在", "Ready", "redeem", "In use"]
        if positiveMarkers.contains(where: { status.localizedCaseInsensitiveContains($0) }) {
            return .green
        }
        switch kind {
        case .screenTime: return .orange
        case .pocketMoney, .wishList: return .secondary
        }
    }

    // MARK: - 任务包进度

    @ViewBuilder
    private var growthPackSection: some View {
        let workbench = taskWorkbenchBuilder.build(
            store: store,
            offlineStatus: offlineOutbox.publicStatus
        )
        let rows = taskRows(for: workbench)
        if !rows.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc.pick(
                        "把今天的学习、生活和运动收在一起。读书按书名折起来，点进去再看章节。",
                        "Today's learning, life, and exercise, all in one place. Books fold up by title — open one to see its chapters."
                    ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Label(
                            workbench.counts.done == workbench.counts.total
                                ? loc.pick("今天完成啦", "Done for today")
                                : loc.pick("\(workbench.counts.done)/\(workbench.counts.total) 已完成", "\(workbench.counts.done)/\(workbench.counts.total) done"),
                            systemImage: "sparkles"
                        )
                        Spacer()
                        Text(GrowthCreditCopy.label(points: rows.reduce(0) { $0 + $1.card.rewardMinutes }, language: loc.language))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                ForEach(childTaskDisplayItems(for: rows)) { item in
                    switch item {
                    case .task(let row):
                        NavigationLink {
                            TaskDetailView(assignment: row.assignment)
                        } label: {
                            GrowthPlanTaskRow(row: row)
                        }
                        .accessibilityIdentifier("child-growth-plan-task-\(row.card.publicTaskRef)")
                    case .readingBook(let group):
                        NavigationLink {
                            ChildReadingBookTaskGroupDetailView(group: group)
                        } label: {
                            ChildReadingBookTaskGroupRow(group: group, sectionTitle: loc.pick("今日成长计划", "Today's Growth Plan"))
                        }
                        .accessibilityIdentifier("child-growth-plan-reading-book-\(group.id)")
                    }
                }
            } header: {
                Text(loc.pick("今日成长计划", "Today's Growth Plan"))
            } footer: {
                Text(loc.pick(
                    "这里是今天的总计划视角；上面的「今日任务」负责告诉孩子下一步先做什么。",
                    "This is today's full plan; Today's Tasks above tells you what to do next."
                ))
                    .font(.footnote)
            }
        }
    }

    // MARK: - 更多

    private var moreSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isMoreExpanded) {
                ForEach(moreQuickAccess, id: \.self) { item in
                    NavigationLink {
                        quickAccessDestination(for: item)
                    } label: {
                        Label(item.label(for: loc.language), systemImage: item.systemImage)
                    }
                    .accessibilityIdentifier("child-home-quick-access-\(item.rawValue)")
                }
                #if canImport(FamilyControls) && canImport(ManagedSettings)
                if familyCloud.isChildDevice {
                    Button {
                        showsScreenTimeManagement = true
                    } label: {
                        Label(
                            loc.pick("家长设置", "Parent Setup"),
                            systemImage: "lock.shield"
                        )
                    }
                    .accessibilityIdentifier("child-home-screen-time-management")
                }
                #endif
            } label: {
                Label(loc.pick("成长工具", "Growth tools"), systemImage: "square.grid.2x2")
                    .font(.subheadline.weight(.semibold))
            }
        } header: {
            Text(loc.pick("更多", "More"))
        }
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        .sheet(isPresented: $showsScreenTimeManagement) {
            ChildScreenTimeLocalSetupView(language: loc.language)
        }
        #endif
    }

    private var versionFooterSection: some View {
        Section {
            HStack {
                Spacer()
                Text("\(loc.pick("章鱼老师", "Octo Teacher")) · \(BuildIdentity.shortVersionText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("child-home-version")
        }
    }

    /// 「更多」里保留的孩子端入口；成长积分钱包已上移到积分区，不再重复。
    private var moreQuickAccess: [ChildHomeQuickAccess] {
        ChildHomeQuickAccess.ordered.filter { $0 != .creditWallet }
    }

    private func taskRows(for workbench: MobileTodayTaskPackageWorkbench) -> [TodayTaskPackageRow] {
        let orderedSteps = store.steps(for: store.activeChildId).sorted { $0.order < $1.order }
        return orderedSteps.compactMap { step in
            guard
                let assignment = store.assignment(for: step),
                let card = workbench.cards.first(where: { $0.order == step.order })
            else { return nil }
            return TodayTaskPackageRow(card: card, assignment: assignment)
        }
    }

    @ViewBuilder
    private func quickAccessDestination(for item: ChildHomeQuickAccess) -> some View {
        switch item {
        case .creditWallet:
            ChildCreditWalletView()
        case .basicHabitChore:
            BasicHabitChoreCheckinWorkbenchView(initialRole: .child, allowedRoles: [.child])
        case .growthDiaryVlog:
            GrowthDiaryVlogStorylineWorkbenchView(initialRole: .child, allowedRoles: [.child])
        case .reportsPreview:
            ReportsWorkbenchView(initialRole: .child, allowedRoles: [.child])
        case .appSelectionPreview:
            AppSelectionWorkbenchView(initialRole: .child, allowedRoles: [.child])
        case .onboardingGuide:
            OnboardingWorkbenchView(initialRole: .child, allowedRoles: [.child])
        }
    }
}

private struct ChildDeviceRebindView: View {
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @State private var showsScanner = false
    @State private var pendingInvite: FamilyCloudJoinPayload?
    @State private var errorMessage: String?

    let language: AppInterfaceLanguage

    var body: some View {
        List {
            Section {
                Label(
                    language.pick("需要重新绑定孩子手机", "Child Phone Rebind Required"),
                    systemImage: "iphone.and.arrow.forward"
                )
                .font(.headline)
                .foregroundStyle(.orange)
                Text(language.pick(
                    "这台手机的家庭接口已经升级。旧绑定不会继续访问任务、积分或屏幕时间规则。",
                    "This phone's family protocol was upgraded. The old binding can no longer access tasks, points, or Screen Time policies."
                ))
                .foregroundStyle(.secondary)
                Button {
                    showsScanner = true
                } label: {
                    Label(
                        language.pick("扫描新的孩子设备二维码", "Scan New Child-Device QR Code"),
                        systemImage: "qrcode.viewfinder"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("child-device-rebind-scan")
            } footer: {
                Text(language.pick(
                    "请让家庭创建者在家长 App 的“家庭成员与设备”中，为这个孩子重新生成二维码。重新绑定会重新采集 App 目录并由家长发布新规则。",
                    "Ask the family creator to generate a new QR code for this child in Family Members & Devices. Rebinding captures a fresh app catalog before a guardian publishes a new policy."
                ))
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(language.pick("重新连接家庭", "Reconnect Family"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsScanner) {
            FamilyJoinScannerView { value in
                guard let payload = FamilyCloudJoinPayload.decode(value), payload.isChildDevice else {
                    errorMessage = language.pick(
                        "这不是当前家庭生成的孩子设备二维码。",
                        "This is not a child-device QR code generated by the current family."
                    )
                    return
                }
                pendingInvite = payload
            }
        }
        .sheet(item: $pendingInvite) { invite in
            NavigationStack {
                Form {
                    FamilyCloudAccountView(pendingInvite: invite) {
                        pendingInvite = nil
                    }
                }
                .navigationTitle(language.pick("确认重新绑定", "Confirm Rebind"))
            }
        }
    }
}

#if canImport(FamilyControls) && canImport(ManagedSettings)
struct ChildScreenTimeAuthorizationCard: View {
    @Environment(ScreenTimePOCManager.self) private var screenTime
    @State private var showsLocalSetup = false
    let language: AppInterfaceLanguage

    private var needsReconnect: Bool {
        !screenTime.isChildFamilyAuthorizationReady && screenTime.selectionCounts.hasSelection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                needsReconnect
                    ? language.pick("请家长重新授权设备控制", "Ask a Parent to Reauthorize Device Control")
                    : language.pick("连接孩子设备控制", "Connect Child Device Controls"),
                systemImage: "lock.shield.fill"
            )
            .font(.headline)
            Text(screenTime.childAuthorizationGuidance(for: language))
            .font(.caption)
            .foregroundStyle(.secondary)
            Button {
                showsLocalSetup = true
            } label: {
                Label(
                    needsReconnect
                        ? language.pick("家长重新授权", "Parent Reauthorize")
                        : language.pick("完成一次设备授权", "Complete One-Time Device Authorization"),
                    systemImage: "person.badge.key.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("child-screen-time-authorize")
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showsLocalSetup) {
            ChildScreenTimeLocalSetupView(language: language)
        }
    }

}

struct ChildScreenTimeLocalSetupView: View {
    @Environment(ScreenTimePOCManager.self) private var screenTime
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(ParentGate.self) private var parentGate
    @Environment(\.dismiss) private var dismiss
    @State private var showsPicker = false
    @State private var pickerSelection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var didAutoPresentPicker = false
    @State private var feedback: String?
    @State private var isWorking = false

    let language: AppInterfaceLanguage
    let autoPresentPickerAfterParentUnlock: Bool

    init(
        language: AppInterfaceLanguage,
        autoPresentPickerAfterParentUnlock: Bool = false
    ) {
        self.language = language
        self.autoPresentPickerAfterParentUnlock = autoPresentPickerAfterParentUnlock
    }

    var body: some View {
        localSetupBody
    }

    private var capturedCatalog: FamilyScreenTimeCatalog? {
        familyCloud.childDeviceProfile?.screenTimeCatalog
    }

    private var remoteSetupBody: some View {
        NavigationStack {
            Group {
                if parentGate.isUnlocked {
                    List {
                        Section {
                            Label(
                                remoteStatusTitle,
                                systemImage: screenTime.localChildSetupIsComplete
                                    ? "checkmark.shield.fill"
                                    : "lock.shield.fill"
                            )
                            .foregroundStyle(
                                screenTime.localChildSetupIsComplete ? Color.green : Color.orange
                            )
                            Text(screenTime.childAuthorizationGuidance(for: language))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                Task {
                                    if screenTime.isChildFamilyAuthorizationReady {
                                        await refreshRemotePolicy()
                                    } else {
                                        await authorizeRemoteControls()
                                    }
                                }
                            } label: {
                                if isWorking {
                                    ProgressView().frame(maxWidth: .infinity)
                                } else {
                                    Label(remoteActionTitle, systemImage: remoteActionIcon)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isWorking)
                            .accessibilityIdentifier("child-screen-time-authorize")
                        } header: {
                            Text(language.pick("设备执行状态", "Device Enforcement"))
                        } footer: {
                            Text(language.pick(
                                "孩子手机只完成一次 Apple 授权并执行家长规则；这里不再选择或修改上锁 App。",
                                "The child phone completes one Apple authorization and enforces guardian rules. Managed apps are no longer selected or changed here."
                            ))
                        }

                        if let feedback {
                            Section {
                                Text(feedback)
                                    .font(.caption)
                                    .foregroundStyle(
                                        screenTime.localChildSetupIsComplete ? Color.green : Color.orange
                                    )
                            }
                        }

                        Section {
                            DisclosureGroup(language.pick("授权无法恢复？", "Authorization Still Failing?")) {
                                Text(screenTime.childAuthorizationFailureGuidance(for: language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    Task { await resetRemoteAuthorization() }
                                } label: {
                                    Label(
                                        language.pick("重置设备授权", "Reset Device Authorization"),
                                        systemImage: "arrow.counterclockwise"
                                    )
                                }
                                .disabled(isWorking)
                            }
                        }
                    }
                } else {
                    ParentGateView()
                }
            }
            .navigationTitle(language.pick("孩子手机屏幕时间", "Child Phone Screen Time"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.pick("完成", "Done")) { dismiss() }
                }
            }
            .task {
                guard autoPresentPickerAfterParentUnlock,
                      parentGate.isUnlocked,
                      screenTime.isChildFamilyAuthorizationReady else { return }
                await refreshRemotePolicy()
            }
        }
    }

    private var remoteStatusTitle: String {
        if !screenTime.isChildFamilyAuthorizationReady {
            return language.pick("需要家长批准 Apple 家庭控制", "Parent Approval Required")
        }
        return screenTime.localChildSetupIsComplete
            ? language.pick("家长规则已在本机执行", "Guardian Policy Active on This Phone")
            : language.pick("等待家长手机发布规则", "Waiting for Guardian Policy")
    }

    private var remoteActionTitle: String {
        screenTime.isChildFamilyAuthorizationReady
            ? language.pick("刷新家长规则", "Refresh Guardian Policy")
            : language.pick("连接 Apple 家庭控制", "Connect Apple Family Controls")
    }

    private var remoteActionIcon: String {
        screenTime.isChildFamilyAuthorizationReady ? "arrow.clockwise" : "person.badge.key.fill"
    }

    @MainActor
    private func authorizeRemoteControls() async {
        guard !isWorking else { return }
        isWorking = true
        await screenTime.requestChildFamilyAuthorization()
        let status = screenTime.applySyncedPolicy(
            familyCloud.childDeviceProfile?.screenTimePolicy
        )
        try? await familyCloud.syncChildScreenTimeStatus(status)
        feedback = screenTime.isChildFamilyAuthorizationReady
            ? language.pick(
                "设备授权完成。家长手机发布规则后会自动执行。",
                "Device authorization complete. Guardian policies apply automatically."
            )
            : screenTime.childAuthorizationFailureGuidance(for: language)
        isWorking = false
    }

    @MainActor
    private func refreshRemotePolicy() async {
        guard !isWorking else { return }
        isWorking = true
        await familyCloud.bootstrap()
        let policy = familyCloud.childDeviceProfile?.screenTimePolicy
        let status = screenTime.applySyncedPolicy(policy)
        try? await familyCloud.syncChildScreenTimeStatus(status)
        feedback = policy.map { status.acknowledgesCurrentLockedPolicy($0) ||
            status.controlMode == .unlocked &&
            status.appliedPolicyRevision == $0.revision &&
            status.appliedSelectionHash == $0.selectionHash &&
            status.appliedControlCommandId == $0.control?.commandId
        } == true
            ? language.pick("家长规则已同步并验证。", "Guardian policy synced and verified.")
            : language.pick(
                "设备已刷新，但还没有取得当前规则的准确执行回执。",
                "The device refreshed but has not acknowledged the current policy yet."
            )
        isWorking = false
    }

    @MainActor
    private func resetRemoteAuthorization() async {
        guard !isWorking else { return }
        isWorking = true
        await screenTime.resetChildDeviceControls()
        let status = screenTime.currentDeviceStatus()
        try? await familyCloud.syncChildScreenTimeStatus(status)
        feedback = language.pick(
            "设备控制已清理，可以重新连接；上锁清单仍由家长手机发布。",
            "Device controls were cleared and can be reconnected. The guardian phone still owns the app policy."
        )
        isWorking = false
    }

    private var localSetupBody: some View {
        @Bindable var screenTime = screenTime
        return NavigationStack {
            Group {
                if parentGate.isUnlocked {
                    List {
                        Section {
                            Label(
                                screenTime.isChildFamilyAuthorizationReady
                                    ? capturedCatalog == nil
                                        ? language.pick("请采集本机 App 目录", "Capture This Phone's App Catalog")
                                        : language.pick("App 目录已同步给家长", "App Catalog Synced to Guardian")
                                    : language.pick("需要家长完成设备连接", "A Parent Must Connect This Device"),
                                systemImage: capturedCatalog != nil
                                    ? "checkmark.shield.fill"
                                    : "lock.shield.fill"
                            )
                            .foregroundStyle(
                                capturedCatalog != nil
                                    ? Color.green
                                    : Color.orange
                            )

                            if let capturedCatalog {
                                Label(
                                    capturedCatalog.applicationCount > 0
                                        ? language.pick(
                                            "已采集具体 App，等待家长发布规则",
                                            "Specific Apps Captured; Waiting for Guardian Policy"
                                        )
                                        : language.pick(
                                            "目录仍只有分类，请重新采集具体 App",
                                            "Catalog Still Has Categories Only; Capture Specific Apps Again"
                                        ),
                                    systemImage: capturedCatalog.applicationCount > 0
                                        ? "checkmark.circle.fill"
                                        : "exclamationmark.triangle.fill"
                                )
                                .font(.subheadline)
                                .foregroundStyle(
                                    capturedCatalog.applicationCount > 0
                                        ? Color.green
                                        : Color.orange
                                )
                            }

                            Button {
                                if screenTime.isChildFamilyAuthorizationReady {
                                    presentCategoryExpandingPicker()
                                } else {
                                    Task { await authorizeAndContinue() }
                                }
                            } label: {
                                if isWorking {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label(primaryActionTitle, systemImage: "person.badge.key.fill")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isWorking)
                            .accessibilityIdentifier("child-screen-time-open-picker")

                            if let capturedCatalog {
                                Text(language.pick(
                                    "目录包含 \(capturedCatalog.applicationCount) 个具体 App 和 \(capturedCatalog.categoryCount) 个分类。只有通过家长 PIN 才能刷新目录。",
                                    "The catalog contains \(capturedCatalog.applicationCount) specific apps and \(capturedCatalog.categoryCount) categories. Refreshing it requires the Parent PIN."
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        } header: {
                            Text(language.pick("一次性真机设置", "One-Time Device Setup"))
                        } footer: {
                            Text(language.pick(
                                "请在这台孩子手机上一次性采集具体 App。这里只同步 Apple 不透明令牌作为候选目录，不会直接改变锁定；之后由家长手机选择并发布规则。",
                                "Capture specific apps once on this child phone. This syncs only Apple's opaque tokens as a candidate catalog and never changes locks directly; the guardian phone chooses and publishes the policy afterward."
                            ))
                        }

                        if let feedback {
                            Section {
                                Text(feedback)
                                    .font(.caption)
                                    .foregroundStyle(capturedCatalog != nil ? Color.green : Color.orange)
                            }
                        }

                        Section {
                            DisclosureGroup(language.pick("仍然无法使用？", "Still Not Working?")) {
                                Text(screenTime.childAuthorizationFailureGuidance(for: language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    Task { await reset() }
                                } label: {
                                    Label(language.pick("清除设置并重新开始", "Clear Setup and Start Again"), systemImage: "arrow.counterclockwise")
                                }
                                .disabled(isWorking)
                            }
                        }
                    }
                } else {
                    ParentGateView()
                }
            }
            .navigationTitle(language.pick("孩子手机屏幕时间", "Child Phone Screen Time"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.pick("完成", "Done")) { dismiss() }
                }
            }
            .familyActivityPicker(isPresented: $showsPicker, selection: $pickerSelection)
            .onChange(of: showsPicker) { _, isPresented in
                guard !isPresented else { return }
                Task { await saveSelection() }
            }
            .onAppear {
                autoPresentPickerIfNeeded()
            }
            .onChange(of: parentGate.isUnlocked) { _, isUnlocked in
                guard isUnlocked else { return }
                autoPresentPickerIfNeeded()
            }
        }
    }

    private var primaryActionTitle: String {
        if !screenTime.isChildFamilyAuthorizationReady {
            return language.pick("连接 Apple 家庭控制", "Connect Apple Family Controls")
        }
        return capturedCatalog == nil
            ? language.pick("采集具体 App", "Capture Specific Apps")
            : language.pick("刷新 App 目录", "Refresh App Catalog")
    }

    @MainActor
    private func presentCategoryExpandingPicker() {
        screenTime.loadGuardianCatalog(capturedCatalog)
        let base = capturedCatalog == nil
            ? ScreenTimeSelectionStore.emptyExpandedSelection()
            : screenTime.guardianCatalogSelection
        pickerSelection = ScreenTimeSelectionStore.categoryExpandingPickerSelection(
            from: base
        )
        showsPicker = true
    }

    @MainActor
    private func autoPresentPickerIfNeeded() {
        guard autoPresentPickerAfterParentUnlock,
              parentGate.isUnlocked,
              screenTime.isChildFamilyAuthorizationReady,
              !didAutoPresentPicker
        else { return }
        didAutoPresentPicker = true
        presentCategoryExpandingPicker()
    }

    @MainActor
    private func authorizeAndContinue() async {
        guard !isWorking else { return }
        isWorking = true
        await screenTime.requestChildFamilyAuthorization()
        let status = screenTime.currentDeviceStatus()
        try? await familyCloud.syncChildScreenTimeStatus(status)
        if screenTime.isChildFamilyAuthorizationReady {
            feedback = language.pick(
                "设备已连接。现在请选择需要锁定并允许积分兑换的 App。",
                "Device connected. Now choose the apps to lock and make exchangeable with Growth Points."
            )
            isWorking = false
            presentCategoryExpandingPicker()
            return
        } else {
            feedback = screenTime.childAuthorizationFailureGuidance(for: language)
        }
        isWorking = false
    }

    @MainActor
    private func saveSelection() async {
        guard !isWorking else { return }
        isWorking = true
        do {
            let upload = try screenTime.makeChildCatalogUpload(
                from: pickerSelection,
                capturedAt: ISO8601DateFormatter().string(from: Date())
            )
            guard upload.applicationCount > 0 else {
                feedback = language.pick(
                    "仍然没有采集到具体 App。请展开分类并勾选具体 App 后再完成。",
                    "No specific apps were captured. Expand categories and select individual apps before finishing."
                )
                isWorking = false
                return
            }
            if let capturedCatalog,
               capturedCatalog.selectionHash == upload.selectionHash,
               capturedCatalog.applicationCount == upload.applicationCount,
               capturedCatalog.categoryCount == upload.categoryCount,
               capturedCatalog.webDomainCount == upload.webDomainCount {
                feedback = language.pick(
                    "App 目录没有变化，家长现有选择仍然有效。",
                    "The app catalog is unchanged, so the guardian's current selection remains valid."
                )
                isWorking = false
                return
            }
            let catalog = try await familyCloud.syncChildScreenTimeCatalog(upload)
            screenTime.loadGuardianCatalog(catalog)
            feedback = language.pick(
                "已把 \(upload.applicationCount) 个具体 App 同步给家长。目录没有直接改变当前锁定。",
                "Synced \(upload.applicationCount) specific apps to the guardian. The catalog did not directly change current locks."
            )
        } catch {
            feedback = language.pick(
                "App 目录还没有同步到家庭账户。请保持联网并重新完成选择。",
                "The app catalog has not synced to the family account. Stay online and complete the selection again."
            )
        }
        isWorking = false
    }

    @MainActor
    private func reset() async {
        guard !isWorking else { return }
        isWorking = true
        await screenTime.resetChildDeviceControls()
        let status = screenTime.currentDeviceStatus()
        try? await familyCloud.syncChildScreenTimeStatus(status)
        feedback = language.pick("旧设置已清除。请重新连接并选择 App。", "Old setup cleared. Reconnect and choose apps again.")
        isWorking = false
    }

    @MainActor
    private func applyLockNow() {
        guard !isWorking else { return }
        isWorking = true
        let applied = screenTime.applyConfiguredShieldNow()
        feedback = applied
            ? language.pick(
                "锁定规则已写入 Apple 系统。请返回主屏幕确认所选 App 出现沙漏。",
                "The lock policy was written to Apple. Return to the Home Screen and confirm the selected apps show hourglasses."
            )
            : shieldErrorMessage(screenTime.lastShieldError ?? "managed_settings_write_failed")
        isWorking = false
    }

    @MainActor
    private func unlockAllNow() {
        guard !isWorking else { return }
        isWorking = true
        screenTime.unshieldAll()
        feedback = language.pick(
            "已解除章鱼老师管理的全部 App 锁定。清单仍保留，稍后可点“立即应用上锁”。",
            "All Octo Teacher app locks are cleared. The list is kept so you can apply it again later."
        )
        isWorking = false
    }

    private func shieldErrorMessage(_ code: String) -> String {
        if code == "application_selection_exceeds_apple_limit" {
            return language.pick(
                "所选 App 数量超过章鱼老师当前支持的安全容量。请减少单选 App 或改用分类；上一套有效规则已保留。",
                "The selected app count exceeds Octo Teacher's current safe capacity. Reduce the explicit selection or use categories; the previous working policy was preserved."
            )
        }
        if code == "family_controls_tokens_expired" ||
            code == "family_controls_selection_requires_reselection" {
            return language.pick(
                "Apple 已让旧 App 令牌失效。请点“更改受控 App”，重新确认一次清单后再应用。",
                "Apple expired the old app tokens. Tap Change Managed Apps, confirm the list again, then apply."
            )
        }
        if code == "family_controls_not_authorized" {
            return screenTime.childAuthorizationFailureGuidance(for: language)
        }
        return language.pick(
            "锁定规则尚未被 Apple 接受。请重新打开 App 选择器确认清单后再试。",
            "Apple has not accepted the lock policy yet. Reopen the app picker, confirm the list, and try again."
        )
    }
}
#endif

struct TodayTaskPackageRow: Identifiable {
    var card: MobileTodayTaskCard
    var assignment: TaskAssignment

    var id: String { card.id }
}

enum ChildTaskDisplayItem: Identifiable {
    case task(TodayTaskPackageRow)
    case readingBook(ChildReadingTaskGroup)

    var id: String {
        switch self {
        case .task(let row): return "task-\(row.id)"
        case .readingBook(let group): return "reading-\(group.id)"
        }
    }
}

struct ChildReadingTaskGroup: Identifiable {
    let id: String
    let title: String
    let rows: [TodayTaskPackageRow]

    var assignments: [TaskAssignment] { rows.map(\.assignment) }
    var progressText: String { ReadingTaskGrouping.progressText(for: assignments) }
    var statusSummary: String { ReadingTaskGrouping.statusSummary(for: assignments) }

    func statusSummary(for language: AppInterfaceLanguage) -> String {
        ReadingTaskGrouping.statusSummary(for: assignments, language: language)
    }

    var rewardText: String {
        GrowthCreditCopy.label(points: ReadingTaskGrouping.totalReward(for: assignments))
    }

    func rewardText(for language: AppInterfaceLanguage) -> String {
        GrowthCreditCopy.label(points: ReadingTaskGrouping.totalReward(for: assignments), language: language)
    }
}

func childTaskDisplayItems(for rows: [TodayTaskPackageRow]) -> [ChildTaskDisplayItem] {
    var groupedRows: [String: [TodayTaskPackageRow]] = [:]
    for row in rows {
        guard let key = ReadingTaskGrouping.key(for: row.assignment) else { continue }
        groupedRows[key, default: []].append(row)
    }

    var emittedGroups: Set<String> = []
    return rows.compactMap { row in
        guard let key = ReadingTaskGrouping.key(for: row.assignment),
              let groupRows = groupedRows[key],
              groupRows.count > 1 else {
            return .task(row)
        }
        guard !emittedGroups.contains(key) else { return nil }
        emittedGroups.insert(key)
        let title = ReadingTaskGrouping.title(for: groupRows[0].assignment) ?? "阅读任务"
        return .readingBook(ChildReadingTaskGroup(id: key, title: title, rows: groupRows))
    }
}

private struct ChildReadingBookTaskGroupRow: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    let group: ChildReadingTaskGroup
    let sectionTitle: String

    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("📚")
                .font(.title)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(representativeState.label(for: loc.language))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tint(for: representativeState))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tint(for: representativeState).opacity(0.14), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(tint(for: representativeState).opacity(0.35), lineWidth: 1)
                        }
                        .accessibilityIdentifier("child-home-task-status-\(group.rows[0].card.publicTaskRef)")
                }
                Text(loc.pick(
                    "\(group.rows.count) 个章节任务 · \(group.statusSummary(for: loc.language))",
                    "\(group.rows.count) chapter tasks · \(group.statusSummary(for: loc.language))"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(group.progressText, systemImage: "book.circle.fill")
                    Label(group.rewardText(for: loc.language), systemImage: "leaf.fill")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            }
            Spacer(minLength: 4)
            SpeakButton(text: loc.pick(
                "\(sectionTitle)：\(group.title)。一共有 \(group.rows.count) 个章节任务，进度 \(group.progressText)。",
                "\(sectionTitle): \(group.title). There are \(group.rows.count) chapter tasks; progress \(group.progressText)."
            ))
        }
    }

    private var representativeState: MobileTodayTaskCardState {
        group.rows.first { $0.card.state == .active || $0.card.state == .redo || $0.card.state == .waitingCheck }?.card.state
            ?? group.rows.first?.card.state
            ?? .locked
    }

    private func tint(for state: MobileTodayTaskCardState) -> Color {
        switch state {
        case .locked: return .secondary
        case .active: return .blue
        case .waitingCheck: return .orange
        case .done: return .green
        case .redo: return .red
        }
    }
}

struct ChildReadingBookTaskGroupDetailView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    let group: ChildReadingTaskGroup

    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    var body: some View {
        List {
            Section {
                ForEach(group.rows) { row in
                    NavigationLink {
                        TaskDetailView(assignment: row.assignment)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: row.card.state.systemImage)
                                .foregroundStyle(tint(for: row.card.state))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ReadingTaskGrouping.chapterLabel(for: row.assignment))
                                    .font(.subheadline.weight(.semibold))
                                Text("\(row.card.state.label(for: loc.language)) · \(GrowthCreditCopy.label(points: row.card.rewardMinutes, language: loc.language))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            SpeakButton(text: loc.pick(
                                "\(group.title)，\(ReadingTaskGrouping.chapterLabel(for: row.assignment))。状态：\(row.card.state.label(for: loc.language))。",
                                "\(group.title), \(ReadingTaskGrouping.chapterLabel(for: row.assignment)). Status: \(row.card.state.label(for: loc.language))."
                            ))
                        }
                    }
                    .accessibilityIdentifier("child-reading-book-chapter-\(row.card.publicTaskRef)")
                }
            } header: {
                Text(loc.pick("章节任务", "Chapter Tasks"))
            } footer: {
                Text(loc.pick(
                    "先进入章节任务，再开始阅读、提交证明或查看完成状态。",
                    "Open a chapter task first, then start reading, hand in proof, or check its status."
                ))
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tint(for state: MobileTodayTaskCardState) -> Color {
        switch state {
        case .locked: return .secondary
        case .active: return .blue
        case .waitingCheck: return .orange
        case .done: return .green
        case .redo: return .red
        }
    }
}

private struct TodayTaskDisplaySection: Identifiable {
    let id: String
    var title: String
    var summary: String
    var systemImage: String
    var rows: [TodayTaskPackageRow]

    var progressText: String {
        let done = rows.filter { $0.card.state == .done }.count
        return "\(done)/\(rows.count)"
    }
}

private struct CreditBalanceCard: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    let balance: CreditBalance

    var body: some View {
        let loc = ChildLocalizationContext(language: childSurfaceLanguage)
        HStack(spacing: 16) {
            metric(loc.pick("可以用", "Available"), GrowthCreditCopy.label(points: balance.availableMinutes, language: loc.language))
            metric(loc.pick("等确认", "Waiting"), GrowthCreditCopy.label(points: balance.pendingMinutes, language: loc.language))
            metric(loc.pick("一共挣到", "Total earned"), GrowthCreditCopy.label(points: balance.lifetimeEarnedMinutes, language: loc.language))
        }
        .padding(.vertical, 6)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TodayTaskPackageCardView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    let card: MobileTodayTaskCard
    let task: TaskTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: card.state.systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(task.displayTitle(for: childSurfaceLanguage))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(card.state.label(for: childSurfaceLanguage))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(tint.opacity(0.14), in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(tint.opacity(0.35), lineWidth: 1)
                            }
                            .accessibilityIdentifier("child-home-task-status-\(card.id)")
                    }
                    Text(card.nextStep)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Label(card.proof.label(for: childSurfaceLanguage), systemImage: card.proof.systemImage)
                        Label(GrowthCreditCopy.label(points: card.rewardMinutes, language: childSurfaceLanguage), systemImage: "leaf.fill")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch card.state {
        case .locked: return .secondary
        case .active: return .blue
        case .waitingCheck: return .orange
        case .done: return .green
        case .redo: return .red
        }
    }
}

private struct GrowthPlanTaskRow: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    let row: TodayTaskPackageRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.assignment.task.displayTitle(for: childSurfaceLanguage))
                    .font(.subheadline.bold())
                    .foregroundStyle(row.card.state == .locked ? .secondary : .primary)
                Text("\(GrowthCreditCopy.label(points: row.card.rewardMinutes, language: childSurfaceLanguage)) · \(row.card.state.label(for: childSurfaceLanguage))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch row.card.state {
        case .locked: return "lock.fill"
        case .active: return "circle"
        case .waitingCheck: return "hourglass"
        case .done: return "checkmark.circle.fill"
        case .redo: return "arrow.uturn.backward.circle.fill"
        }
    }

    private var tint: Color {
        switch row.card.state {
        case .locked: return .secondary
        case .active: return .blue
        case .waitingCheck: return .orange
        case .done: return .green
        case .redo: return .red
        }
    }
}
