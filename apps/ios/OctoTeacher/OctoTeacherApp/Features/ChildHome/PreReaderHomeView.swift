import SwiftUI

enum PreReaderHomeCopy {
    static let emptyTaskTitle = "今天还没有任务"
    static let emptyTaskDetail = "等大人布置好任务，这里就会出现大卡片。"
    static let emptyTaskSpeech = "今天还没有任务。等大人布置好任务，这里就会出现任务卡片。可以先找小伙伴说话，或者看看徽章。"

    static func emptyTaskTitle(for language: AppInterfaceLanguage) -> String {
        language.pick(emptyTaskTitle, "No tasks yet today")
    }

    static func emptyTaskDetail(for language: AppInterfaceLanguage) -> String {
        language.pick(emptyTaskDetail, "Once a grown-up sets up tasks, big cards will show up here.")
    }

    static func emptyTaskSpeech(for language: AppInterfaceLanguage) -> String {
        language.pick(
            emptyTaskSpeech,
            "No tasks yet today. Once a grown-up sets up tasks, task cards will show up here. You can chat with your buddy first, or look at your badges."
        )
    }

    static func rewardLabel(points: Int, language: AppInterfaceLanguage = .chinese) -> String {
        GrowthCreditCopy.label(points: points, language: language)
    }

    static func taskSpeech(
        category: String,
        title: String,
        rewardPoints: Int,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        let safeCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return language.pick(
            "\(safeCategory.isEmpty ? "任务" : safeCategory)：\(safeTitle.isEmpty ? "小任务" : safeTitle)。做完有 \(GrowthCreditCopy.label(points: rewardPoints))。",
            "\(safeCategory.isEmpty ? "Task" : safeCategory): \(safeTitle.isEmpty ? "a little task" : safeTitle). Finish it to get \(GrowthCreditCopy.label(points: rewardPoints, language: .english))."
        )
    }

    static func greetingSpeech(
        childName: String,
        done: Int,
        total: Int,
        nextTaskTitle: String?,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        let safeName = childName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = safeName.isEmpty ? language.pick("小朋友", "little friend") : safeName
        if total == 0 {
            return language.pick(
                "你好，\(name)！今天还没有任务，去玩吧！",
                "Hi, \(name)! No tasks yet today — go play!"
            )
        }
        if done == total {
            return language.pick(
                "你好，\(name)！今天的任务全部做完啦，太棒了！",
                "Hi, \(name)! All of today's tasks are done — amazing!"
            )
        }
        let safeNext = nextTaskTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let safeNext, !safeNext.isEmpty {
            return language.pick(
                "你好，\(name)！今天有 \(total) 个任务，已经完成 \(done) 个。现在可以先做：\(safeNext)。",
                "Hi, \(name)! You have \(total) tasks today and finished \(done). You can start with: \(safeNext)."
            )
        }
        return language.pick(
            "你好，\(name)！今天有 \(total) 个任务，已经完成 \(done) 个。点一个卡片开始吧！",
            "Hi, \(name)! You have \(total) tasks today and finished \(done). Tap a card to start!"
        )
    }

    static func progressStars(done: Int, total: Int, maxVisible: Int = 10) -> [String] {
        let safeTotal = max(0, total)
        guard safeTotal > 0 else { return [] }
        let safeDone = min(max(0, done), safeTotal)
        let visibleTotal = min(safeTotal, max(1, maxVisible))
        let filled: Int
        if safeTotal <= visibleTotal {
            filled = safeDone
        } else if safeDone == 0 {
            filled = 0
        } else {
            let scaled = Double(safeDone) / Double(safeTotal) * Double(visibleTotal)
            filled = min(visibleTotal, max(1, Int(scaled.rounded(.toNearestOrAwayFromZero))))
        }
        return (0..<visibleTotal).map { $0 < filled ? "⭐" : "☆" }
    }

    static func progressSummary(
        done: Int,
        total: Int,
        maxVisible: Int = 10,
        language: AppInterfaceLanguage = .chinese
    ) -> String? {
        let safeTotal = max(0, total)
        guard safeTotal > max(1, maxVisible) else { return nil }
        let safeDone = min(max(0, done), safeTotal)
        return language.pick("已完成 \(safeDone)/\(safeTotal)", "Done \(safeDone)/\(safeTotal)")
    }
}

enum PreReaderHomeIcon {
    static let companion = TaskIconProvider.Icon(emoji: "🐙", assetName: BrandIdentity.logoAssetName)
    static let screenTime = TaskIconProvider.Icon(emoji: "🎮", systemImageName: "gamecontroller.fill")
    static let wish = TaskIconProvider.Icon(emoji: "🎁", systemImageName: "gift.fill")
    static let badge = TaskIconProvider.Icon(emoji: "🏆", systemImageName: "trophy.fill")
    static let creative = TaskIconProvider.Icon(emoji: "🎨", systemImageName: "paintpalette.fill")
}

enum ChildVisualTheme {
    static let cornerRadius: CGFloat = 8
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let outline = Color.primary.opacity(0.08)
    static let action = Color.orange

    static func accent(for category: TaskCategory) -> Color {
        switch category {
        case .home: return .orange
        case .learning: return .blue
        case .health: return .green
        case .creative: return .purple
        case .family: return .pink
        case .school: return .indigo
        }
    }

    static func accent(for task: TaskTemplate) -> Color {
        if task.video != nil {
            return TaskIconProvider.isYouTubeVideo(task) ? .red : .blue
        }
        return accent(for: task.category)
    }
}

struct ChildTaskIconBadge: View {
    let icon: TaskIconProvider.Icon
    let size: CGFloat
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius, style: .continuous)
                .fill(accent.opacity(0.13))
                .overlay {
                    RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                }

            if let systemImageName = icon.systemImageName {
                Image(systemName: systemImageName)
                    .font(.system(size: max(14, size * 0.44), weight: .semibold))
                    .foregroundStyle(accent)
            } else if icon.assetName == BrandIdentity.logoAssetName {
                Image(BrandIdentity.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .padding(max(3, size * 0.07))
            } else {
                Text(icon.emoji)
                    .font(.system(size: max(14, size * 0.44), weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 幼儿首页只把当前最重要的动作放在首屏，其余能力保持一跳可达。
/// 这些常量同时给布局回归测试使用，避免页面以后再次无边界变长。
enum PreReaderHomeLayout {
    static let primaryTaskLimit = 2
    static let bottomContentMargin: CGFloat = 24
    static let tasksExpandedByDefault = false
    static let toolsExpandedByDefault = false
    static let completedExpandedByDefault = false

    static func visibleTaskCount(total: Int, isExpanded: Bool) -> Int {
        let safeTotal = max(0, total)
        return isExpanded ? safeTotal : min(primaryTaskLimit, safeTotal)
    }
}

/// 幼儿模式首页：给还不认字的孩子。
///
/// 设计原则：大图标 + 稳定的语义颜色表达动作，文字只是辅助；
/// 所有语音都由孩子点击小喇叭触发，进入页面保持安静。
struct PreReaderHomeView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MockScreenTimeController.self) private var screenTimeController
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @Environment(ScreenTimePOCManager.self) private var screenTime
    @State private var showsScreenTimeManagement = false
    #endif
    private let taskWorkbenchBuilder = MobileTodayTaskPackageWorkbenchBuilder()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    @State private var isTaskListExpanded: Bool
    @State private var isToolsExpanded: Bool
    @State private var isCompletedExpanded: Bool
    @State private var showsChildSurfaceSettings = false

    init() {
        // Tests and production intentionally share the same compact first-load state.
        _isTaskListExpanded = State(initialValue: PreReaderHomeLayout.tasksExpandedByDefault)
        _isToolsExpanded = State(initialValue: PreReaderHomeLayout.toolsExpandedByDefault)
        _isCompletedExpanded = State(initialValue: PreReaderHomeLayout.completedExpandedByDefault)
    }

    /// 当前孩子的界面语言：幼儿版所有可见文案与小喇叭 speech 都从这里取。
    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    var body: some View {
        let workbench = taskWorkbenchBuilder.build(store: store, offlineStatus: offlineOutbox.publicStatus)
        let rows = taskRows(for: workbench)
        let activeRows = rows.filter { $0.card.state != .done }
        let completedRows = rows.filter { $0.card.state == .done }
        let completion = store.todayCompletion

        ScrollView(.vertical) {
            LazyVStack(spacing: 14) {
                header(rows: rows, completion: completion)
                growthPointsSummary
                cloudSyncStatus
                screenTimeSetupCard
                schoolModeCard
                if activeRows.isEmpty && completedRows.isEmpty {
                    emptyTaskCard
                } else if activeRows.isEmpty {
                    allDoneCard(completedCount: completedRows.count)
                } else {
                    taskGrid(rows: activeRows)
                }
                companionQuickAction
                if !completedRows.isEmpty {
                    completedTaskShelf(rows: completedRows)
                }
                bottomButtons
                versionFooter
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .background(ChildVisualTheme.pageBackground.ignoresSafeArea())
        .tint(ChildVisualTheme.action)
        .refreshable { await refreshCloudTasks(forceFullSnapshot: true) }
        .contentMargins(.bottom, PreReaderHomeLayout.bottomContentMargin, for: .scrollContent)
        .scrollBounceBehavior(.always)
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await refreshCloudTasks(forceFullSnapshot: true) }
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title2)
                }
                .disabled(familyCloud.isWorking)
                .accessibilityLabel(loc.pick("同步家庭任务", "Sync family tasks"))
                .accessibilityIdentifier("pre-reader-cloud-refresh")

                Button {
                    showsChildSurfaceSettings = true
                } label: {
                    Image(systemName: "gearshape.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel(loc.pick("孩子端设置", "Child settings"))
                .accessibilityIdentifier("pre-reader-settings")

                if store.hasMultipleChildren {
                    Menu {
                        ForEach(store.children) { member in
                            Button(member.name) { store.setActiveChild(member.id) }
                        }
                    } label: {
                        Image(systemName: "person.2.circle.fill")
                            .font(.title2)
                    }
                }
            }
        }
        .sheet(isPresented: $showsChildSurfaceSettings) {
            ChildSurfaceSettingsView()
        }
        .task { await refreshCloudTasks(forceFullSnapshot: false) }
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        .sheet(isPresented: $showsScreenTimeManagement) {
            ChildScreenTimeLocalSetupView(language: loc.language)
        }
        #endif

    }

    @ViewBuilder
    private var screenTimeSetupCard: some View {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        if familyCloud.isChildDevice, !screenTime.localChildSetupIsComplete {
            ChildScreenTimeAuthorizationCard(language: loc.language)
                .padding(14)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius))
        }
        #endif
    }

    @ViewBuilder
    private var cloudSyncStatus: some View {
        if familyCloud.isWorking || familyCloud.lastSyncError != nil {
            HStack(spacing: 12) {
                if familyCloud.isWorking {
                    ProgressView()
                    Text(loc.pick("正在拿新任务…", "Getting new tasks…"))
                } else if familyCloud.lastSyncError != nil {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.orange)
                    Text(loc.pick("往下拉，再试一次", "Pull down and try again"))
                }
                Spacer()

                if familyCloud.lastSyncError != nil, !familyCloud.isWorking {
                    Button(loc.pick("重试", "Retry")) {
                        Task { await refreshCloudTasks(forceFullSnapshot: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.headline)
            .padding(14)
            .background(ChildVisualTheme.surface, in: RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius))
            .accessibilityIdentifier("pre-reader-cloud-sync-status")
        }
    }

    private func refreshCloudTasks(forceFullSnapshot: Bool) async {
        do {
            try await familyCloud.refreshChildSurface(
                into: store,
                forceFullSnapshot: forceFullSnapshot
            )
        } catch {
            // The large retry card remains visible for pre-readers and caregivers.
        }
    }

    // MARK: - 头部：问候 + 星星进度

    private func header(rows: [TodayTaskPackageRow], completion: (done: Int, total: Int)) -> some View {
        let nextTitle = rows.first { $0.card.state == .active || $0.card.state == .redo }?
            .assignment.task.displayTitle(for: childSurfaceLanguage)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(loc.pick(
                    "你好，\(store.childDisplayName(store.child, for: .chinese))！",
                    "Hi, \(store.childDisplayName(store.child, for: .english))!"
                ))
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                SpeakButton(text: PreReaderHomeCopy.greetingSpeech(
                    childName: store.childDisplayName(store.child, for: loc.language),
                    done: completion.done,
                    total: completion.total,
                    nextTaskTitle: nextTitle,
                    language: loc.language
                ))
                Spacer(minLength: 0)
            }

            if completion.total > 0 {
                let stars = PreReaderHomeCopy.progressStars(done: completion.done, total: completion.total, maxVisible: 5)
                HStack(spacing: 5) {
                    ForEach(Array(stars.enumerated()), id: \.offset) { _, star in
                        Image(systemName: star == "⭐" ? "star.fill" : "star")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(star == "⭐" ? Color.orange : Color.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(loc.pick("\(completion.done)/\(completion.total) 完成", "\(completion.done)/\(completion.total) done"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(completion.done == completion.total ? Color.green : Color.secondary)
                }
                .accessibilityIdentifier("pre-reader-progress")
                ProgressView(value: Double(completion.done), total: Double(max(1, completion.total)))
                    .tint(.orange)
                if completion.done == completion.total {
                    Label(loc.pick("全部做完啦！", "All done!"), systemImage: "checkmark.seal.fill")
                        .font(.headline.bold())
                        .foregroundStyle(.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityIdentifier("pre-reader-home-top")
    }

    private var growthPointsSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text(loc.pick("我的成长积分", "My Growth Points"))
                .font(.headline)
            Spacer()
            Text("\(store.creditBalance.availableMinutes)")
                .font(.title.bold())
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius, style: .continuous)
                .fill(ChildVisualTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius, style: .continuous)
                        .stroke(Color.green.opacity(0.18), lineWidth: 1)
                }
        )
        .accessibilityIdentifier("pre-reader-growth-points")
    }

    @ViewBuilder
    private var schoolModeCard: some View {
        let profile = store.schoolModeProfile(for: store.activeChildId)
        let evaluation = SchoolModeRuleEngine.evaluate(profile: profile, at: Date())
        if profile.isEnabled {
            HStack(spacing: 14) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(evaluation.isActive ? Color.blue : Color.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.pick("学校模式", "School Mode"))
                        .font(.title3.bold())
                    Text(evaluation.isActive
                         ? loc.pick("现在是上学时间", "School time is active")
                         : loc.pick("现在可以正常使用", "Not school hours now"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                SpeakButton(text: evaluation.isActive
                    ? loc.pick("现在是上学时间。娱乐应用暂时休息。", "School time is active. Entertainment apps are taking a break.")
                    : loc.pick("学校模式已经安排。现在不在上学时间。", "School Mode is scheduled. It is not school time now."))
            }
            .padding(18)
            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 无任务空状态

    /// 今天没有任务时的大卡片提示：不识字的孩子看月亮表情，点小喇叭听说明。
    private var emptyTaskCard: some View {
        HStack(spacing: 14) {
            ChildTaskIconBadge(
                icon: TaskIconProvider.Icon(emoji: "🌙", systemImageName: "moon.stars.fill"),
                size: 48,
                accent: .indigo
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(PreReaderHomeCopy.emptyTaskTitle(for: loc.language))
                        .font(.headline.bold())
                    SpeakButton(text: PreReaderHomeCopy.emptyTaskSpeech(for: loc.language))
                }
                Text(PreReaderHomeCopy.emptyTaskDetail(for: loc.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                        .stroke(ChildVisualTheme.outline, lineWidth: 1)
                }
        )
        .accessibilityIdentifier("pre-reader-empty-tasks")
    }

    private func allDoneCard(completedCount: Int) -> some View {
        HStack(spacing: 14) {
            ChildTaskIconBadge(
                icon: TaskIconProvider.Icon(emoji: "✓", systemImageName: "checkmark.seal.fill"),
                size: 48,
                accent: .green
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(loc.pick("今天做完啦", "Done for today"))
                        .font(.headline.bold())
                    SpeakButton(text: loc.pick(
                        "今天的任务都做完啦，一共有 \(completedCount) 个完成的任务。可以看看下面的完成回看。",
                        "All of today's tasks are done — \(completedCount) finished in total. Check out Completed Review below."
                    ))
                }
                Text(loc.pick("完成了 \(completedCount) 项", "\(completedCount) finished"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                .fill(ChildVisualTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                        .stroke(Color.green.opacity(0.18), lineWidth: 1)
                }
        )
        .accessibilityIdentifier("pre-reader-all-done-card")
    }

    // MARK: - 任务大卡片网格

    private func taskGrid(rows: [TodayTaskPackageRow]) -> some View {
        let items = childTaskDisplayItems(for: rows)
        let visibleCount = PreReaderHomeLayout.visibleTaskCount(
            total: items.count,
            isExpanded: isTaskListExpanded
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                Text(loc.pick("现在先做", "Do this now"))
                    .font(.title3.bold())
                Spacer()
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(items.prefix(visibleCount))) { item in
                    switch item {
                    case .task(let row):
                        NavigationLink {
                            TaskDetailView(assignment: row.assignment)
                        } label: {
                            taskCard(row: row)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pre-reader-task-\(row.card.publicTaskRef)")
                    case .readingBook(let group):
                        NavigationLink {
                            ChildReadingBookTaskGroupDetailView(group: group)
                        } label: {
                            readingBookCard(group: group, isCompletedShelf: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pre-reader-reading-book-\(group.id)")
                    }
                }
            }

            if items.count > PreReaderHomeLayout.primaryTaskLimit {
                foldButton(
                    title: isTaskListExpanded
                        ? loc.pick("收起任务", "Show less")
                        : loc.pick("全部任务 · \(items.count)", "All tasks · \(items.count)"),
                    systemImage: "checklist",
                    isExpanded: isTaskListExpanded,
                    identifier: "pre-reader-task-list-toggle"
                ) {
                    isTaskListExpanded.toggle()
                }
            }
        }
    }

    private func completedTaskShelf(rows: [TodayTaskPackageRow]) -> some View {
        let items = childTaskDisplayItems(for: rows)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                foldButton(
                    title: loc.pick("完成回看 · \(items.count)", "Done today · \(items.count)"),
                    systemImage: "checkmark.circle.fill",
                    isExpanded: isCompletedExpanded,
                    identifier: "pre-reader-completed-toggle"
                ) {
                    isCompletedExpanded.toggle()
                }
                SpeakButton(text: loc.pick(
                    "完成回看，这里有今天做完的 \(items.count) 项。",
                    "Completed Review. You finished \(items.count) things today."
                ))
            }

            if isCompletedExpanded {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { item in
                        switch item {
                        case .task(let row):
                            NavigationLink {
                                TaskDetailView(assignment: row.assignment)
                            } label: {
                                VStack(spacing: 6) {
                                    iconView(
                                        TaskIconProvider.icon(
                                            for: row.assignment.task,
                                            displayTitle: row.assignment.task.displayTitle(for: childSurfaceLanguage)
                                        ),
                                        size: 46,
                                        accent: cardColor(row.assignment.task)
                                    )
                                    Text(row.assignment.task.displayTitle(for: childSurfaceLanguage))
                                        .font(.caption.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                    Text(loc.pick("已完成", "Done"))
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.green)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                                        .fill(ChildVisualTheme.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                                                .stroke(Color.green.opacity(0.16), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("pre-reader-completed-task-\(row.card.publicTaskRef)")
                        case .readingBook(let group):
                            NavigationLink {
                                ChildReadingBookTaskGroupDetailView(group: group)
                            } label: {
                                readingBookCard(group: group, isCompletedShelf: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("pre-reader-completed-reading-book-\(group.id)")
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityIdentifier("pre-reader-completed-tasks")
    }

    private func readingBookCard(group: ChildReadingTaskGroup, isCompletedShelf: Bool) -> some View {
        let accent: Color = isCompletedShelf ? .green : .blue
        let bookID = group.assignments.compactMap { $0.task.reading?.importedBookId }.first
        let isBookReady = bookID.map { store.book(id: $0) != nil } ?? true
        let isLoading = bookID.map { familyCloud.downloadingBookIDs.contains($0) } ?? false
        return VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                iconView(
                    TaskIconProvider.Icon(emoji: "📚", systemImageName: "book.closed.fill"),
                    size: isCompletedShelf ? 52 : 64,
                    accent: accent
                )
                iconView(
                    statusIcon(isCompletedShelf ? .done : .active),
                    size: 30,
                    accent: statusAccent(isCompletedShelf ? .done : .active)
                )
                    .offset(x: 8, y: -4)
            }
            Text(group.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(loc.pick("读 \(group.progressText)", "Read \(group.progressText)"))
                .font(.caption.weight(.bold))
                .foregroundStyle(isCompletedShelf ? .green : .orange)
            if !isBookReady {
                HStack(spacing: 5) {
                    if isLoading { ProgressView().controlSize(.small) }
                    Text(loc.pick(
                        isLoading ? "书籍正在后台加载" : "书籍等待重新加载",
                        isLoading ? "Book loading in background" : "Book waiting to reload"
                    ))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.green)
                Text(group.rewardText(for: loc.language))
                    .font(.headline)
                SpeakButton(text: loc.pick(
                    "\(group.title)。一共有 \(group.rows.count) 个阅读小任务，进度 \(group.progressText)。点进去看每一次要读哪里。",
                    "\(group.title). There are \(group.rows.count) little reading tasks; progress \(group.progressText). Tap in to see what to read each time."
                ))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isCompletedShelf ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                .fill(cardGradient(accent: accent, completed: isCompletedShelf))
                .overlay(
                    RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                        .stroke(accent.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private func taskCard(row: TodayTaskPackageRow) -> some View {
        let accent = cardColor(row.assignment.task)
        return VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                iconView(
                    TaskIconProvider.icon(
                        for: row.assignment.task,
                        displayTitle: row.assignment.task.displayTitle(for: childSurfaceLanguage)
                    ),
                    size: 64,
                    accent: accent
                )
                iconView(statusIcon(row.card.state), size: 30, accent: statusAccent(row.card.state))
                    .offset(x: 8, y: -4)
            }
            Text(row.assignment.task.displayTitle(for: childSurfaceLanguage))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.green)
                Text(PreReaderHomeCopy.rewardLabel(points: row.card.rewardMinutes, language: loc.language))
                    .font(.subheadline.weight(.semibold))
                SpeakButton(text: PreReaderHomeCopy.taskSpeech(
                    category: row.assignment.task.category.label(for: loc.language),
                    title: row.assignment.task.displayTitle(for: childSurfaceLanguage),
                    rewardPoints: row.card.rewardMinutes,
                    language: loc.language
                ))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                .fill(cardGradient(accent: accent))
                .overlay(
                    RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                        .stroke(accent.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private func cardColor(_ category: TaskCategory) -> Color {
        ChildVisualTheme.accent(for: category)
    }

    private func cardColor(_ task: TaskTemplate) -> Color {
        ChildVisualTheme.accent(for: task)
    }

    private func statusIcon(_ state: MobileTodayTaskCardState) -> TaskIconProvider.Icon {
        switch state {
        case .active: return TaskIconProvider.Icon(emoji: "▶", systemImageName: "play.fill")
        case .waitingCheck: return TaskIconProvider.Icon(emoji: "⏳", systemImageName: "hourglass")
        case .done: return TaskIconProvider.Icon(emoji: "✓", systemImageName: "checkmark.circle.fill")
        case .redo: return TaskIconProvider.Icon(emoji: "↻", systemImageName: "arrow.counterclockwise")
        case .locked: return TaskIconProvider.Icon(emoji: "🔒", systemImageName: "lock.fill")
        }
    }

    private func statusAccent(_ state: MobileTodayTaskCardState) -> Color {
        switch state {
        case .active: return .orange
        case .waitingCheck: return .yellow
        case .done: return .green
        case .redo: return .red
        case .locked: return .gray
        }
    }

    private func cardGradient(accent: Color, completed: Bool = false) -> LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(completed ? 0.06 : 0.09),
                ChildVisualTheme.surface
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func iconView(_ icon: TaskIconProvider.Icon, size: CGFloat, accent: Color = .orange) -> some View {
        ChildTaskIconBadge(icon: icon, size: size, accent: accent)
    }

    // MARK: - AI 主入口与低频工具

    private var companionQuickAction: some View {
        NavigationLink {
            ChildAICompanionView()
        } label: {
            HStack(spacing: 12) {
                iconView(PreReaderHomeIcon.companion, size: 52, accent: .purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text(loc.pick("AI 章鱼老师", "AI Octo Teacher"))
                        .font(.headline.bold())
                    Text(loc.pick("说说话 · 问问题", "Talk · Ask · Explore"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                SpeakButton(text: loc.pick(
                    "AI 章鱼老师在这里。可以说话、拍照，也可以问问题。",
                    "AI Octo Teacher is here. You can talk, share a photo, or ask a question."
                ))
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                    .fill(cardGradient(accent: .purple))
                    .overlay(
                        RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                            .stroke(Color.purple.opacity(0.16), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pre-reader-companion-button")
    }

    private var bottomButtons: some View {
        let rewardPathway = RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTimeController,
            viewerRole: .child
        )
        let screenOutlet = rewardPathway.outlets.first { $0.kind == .screenTime }
        let wishOutlet = rewardPathway.outlets.first { $0.kind == .wishList }

        return VStack(spacing: 10) {
            foldButton(
                title: loc.pick("更多好玩的", "More to explore"),
                systemImage: "square.grid.2x2.fill",
                isExpanded: isToolsExpanded,
                identifier: "pre-reader-tools-toggle"
            ) {
                isToolsExpanded.toggle()
            }

            if isToolsExpanded {
                VStack(spacing: 12) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        bigButton(
                            icon: PreReaderHomeIcon.screenTime,
                            title: loc.pick("玩一会儿", "Play Time"),
                            subtitle: screenOutlet?.status,
                            accent: .blue,
                            speech: rewardSpeech(
                                for: screenOutlet,
                                fallback: loc.pick("用成长积分换玩的时间。", "Trade Growth Points for play time.")
                            ),
                            identifier: "pre-reader-screen-button"
                        ) {
                            if screenOutlet?.suggestedRoute == .earnCredits {
                                ChildCreditWalletView()
                            } else {
                                RewardRedemptionView()
                            }
                        }
                        bigButton(
                            icon: PreReaderHomeIcon.wish,
                            title: loc.pick("我的愿望", "My Wish"),
                            subtitle: wishOutlet?.status,
                            accent: .pink,
                            speech: rewardSpeech(
                                for: wishOutlet,
                                fallback: loc.pick(
                                    "换零花钱，或者说一个愿望给大人听。",
                                    "Trade for pocket money, or tell a grown-up a wish."
                                )
                            ),
                            identifier: "pre-reader-wish-button"
                        ) {
                            ChildPocketMoneyView()
                        }
                        bigButton(
                            icon: PreReaderHomeIcon.creative,
                            title: loc.pick("创作广场", "Create"),
                            accent: .purple,
                            speech: loc.pick(
                                "打开创作广场。画画、做手工、搭积木、讲故事，完成后可以拍照或用语音介绍作品。",
                                "Open the Creation Plaza. Draw, craft, build blocks, or tell a story, then take a photo or talk about your work."
                            ),
                            identifier: "pre-reader-creative-button"
                        ) {
                            ChildCreativeCenterView()
                        }
                        bigButton(
                            icon: PreReaderHomeIcon.badge,
                            title: loc.pick("我的徽章", "Badges"),
                            accent: .yellow,
                            speech: loc.pick("看看你拿到了什么徽章。", "See which badges you've earned."),
                            identifier: "pre-reader-badge-button"
                        ) {
                            ChildBadgesView()
                        }
                    }
                    #if canImport(FamilyControls) && canImport(ManagedSettings)
                    if familyCloud.isChildDevice {
                        Button {
                            showsScreenTimeManagement = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.headline)
                                    .foregroundStyle(.orange)
                                Text(loc.pick("家长设置", "Parent Setup"))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                                    .fill(ChildVisualTheme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                                            .stroke(ChildVisualTheme.outline, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(loc.pick("家长设置", "Parent Setup"))
                        .accessibilityIdentifier("pre-reader-screen-time-management")
                    }
                    #endif
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var versionFooter: some View {
        Text("\(loc.pick("章鱼老师", "Octo Teacher")) · \(BuildIdentity.shortVersionText)")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .accessibilityIdentifier("pre-reader-version")
    }

    private func foldButton(
        title: String,
        systemImage: String,
        isExpanded: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
    }

    private func bigButton<Destination: View>(
        icon: TaskIconProvider.Icon,
        title: String,
        subtitle: String? = nil,
        accent: Color,
        speech: String,
        identifier: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(spacing: 6) {
                iconView(icon, size: 56, accent: accent)
                HStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    SpeakButton(text: speech)
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                    .fill(cardGradient(accent: accent))
                    .overlay(
                        RoundedRectangle(cornerRadius: ChildVisualTheme.cornerRadius)
                            .stroke(accent.opacity(0.16), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func rewardSpeech(for outlet: RewardPathwayOutlet?, fallback: String) -> String {
        guard let outlet else { return fallback }
        return loc.pick(
            "\(outlet.title)：\(outlet.status)。\(outlet.nextStep)。",
            "\(outlet.title): \(outlet.status). \(outlet.nextStep)."
        )
    }

    // MARK: - 数据与朗读

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

}
