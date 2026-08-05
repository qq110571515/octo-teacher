import SwiftUI

/// 家长工作台。
///
/// 解锁后第一屏聚焦三件事：审核孩子提交的任务、布置/调整任务、看奖励余额。
/// 深度工作台与只读审计视图收在「更多功能与预览」里，不挤占日常操作。
struct ParentModeView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(ParentGate.self) private var gate
    @Environment(MockScreenTimeController.self) private var screenTime
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @State private var offlineHint: String?
    @State private var offlineHintIsError = false
    @State private var isComposingTask = false
    @State private var composingPreset: ParentTaskStarterPreset?
    @State private var editingTaskTarget: ParentTaskEditTarget?
    @State private var isQuickTaskGroupExpanded: Bool
    @State private var isTaskCenterExpanded: Bool
    @State private var isFamilyDataExpanded = false

    init() {
        let isUITest = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-OctoTeacherUITest") }
        _isQuickTaskGroupExpanded = State(initialValue: isUITest)
        _isTaskCenterExpanded = State(initialValue: isUITest)
    }

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var pendingAssignments: [TaskAssignment] {
        store.assignments.filter { $0.status == .submitted }
    }

    /// 全家范围的愿望待办（待定价 / 待兑现）；与待确认证明同级提醒。
    private var wishReminder: ParentWishActionReminder? {
        ParentWishActionReminder.build(wishes: store.wishes)
    }

    var body: some View {
        NavigationStack {
            Group {
                if gate.isUnlocked {
                    workbenchList
                } else {
                    ParentGateView()
                }
            }
            .navigationTitle(lang.pick("家长工作台", "Parent Workspace"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $editingTaskTarget) { target in
                ParentTaskComposerView(editingAssignment: target.assignment)
            }
            .toolbar {
                if gate.isUnlocked {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            gate.lock()
                        } label: {
                            Image(systemName: "lock")
                        }
                        .accessibilityLabel(lang.pick("锁定家长模式", "Lock Parent Mode"))
                        .accessibilityIdentifier("parent-mode-lock")
                    }
                }
            }
        }
    }

    private var workbenchList: some View {
        List {
            dailyFocusSection
            parentQuickActionsSection
            familyAccountSection
            if !pendingAssignments.isEmpty {
                approvalSection
            }
            if offlineHint != nil {
                reviewFeedbackSection
            }
            if activeChildAssignments.isEmpty && !store.hasAssignedFirstEveningRoutinePlan() {
                ParentFirstEveningPlanSection()
            }
            taskManagementSection
            contentCenterSection
            familyDataSection

            Section {
                NavigationLink {
                    ParentAdvancedToolsView()
                } label: {
                    Label(lang.pick("更多功能与预览", "Advanced Tools & Previews"), systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("parent-mode-advanced-tools")
            }
        }
        .sheet(isPresented: $isComposingTask, onDismiss: {
            composingPreset = nil
        }) {
            NavigationStack {
                ParentTaskComposerView(starterPreset: composingPreset)
            }
        }
    }

    // MARK: - 家庭账户

    private var familyAccountSection: some View {
        let language = store.settings.resolvedParentInterfaceLanguage
        let isConnected = familyCloud.family != nil
        let isSignedIn = familyCloud.isGuardianSignedIn

        return Section {
            NavigationLink {
                FamilyMembersView()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isConnected ? "checkmark.icloud.fill" : "person.crop.circle.badge.plus")
                        .font(.title3)
                        .foregroundStyle(isConnected ? Color.green : Color.blue)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(language.pick(
                            isConnected ? "家庭账户已连接" : (isSignedIn ? "完成家庭创建" : "注册或加入家庭"),
                            isConnected ? "Family account connected" : (isSignedIn ? "Finish creating your family" : "Create or join a family")
                        ))
                            .font(.headline)
                        Text(familyAccountDetail(language: language, isConnected: isConnected, isSignedIn: isSignedIn))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.vertical, 6)
            }
            .accessibilityIdentifier("parent-mode-family-account")
        } header: {
            Text(language.pick("家庭", "Family"))
        }
    }

    private func familyAccountDetail(
        language: AppInterfaceLanguage,
        isConnected: Bool,
        isSignedIn: Bool
    ) -> String {
        if isConnected {
            return language.pick(
                "\(familyCloud.family?.guardians.count ?? 0) 位监护人 · \(familyCloud.family?.children.count ?? 0) 个孩子 · 同步正常",
                "\(familyCloud.family?.guardians.count ?? 0) guardians · \(familyCloud.family?.children.count ?? 0) children · Synced"
            )
        }
        if isSignedIn {
            return language.pick(
                "创建家庭，开始多手机同步。",
                "Create your family to start syncing devices."
            )
        }
        return language.pick(
            "登录创建家庭，或扫码加入。",
            "Sign in to create a family, or scan to join."
        )
    }

    // MARK: - 常用操作

    private var parentQuickActionsSection: some View {
        Section {
            Button {
                composingPreset = nil
                isComposingTask = true
            } label: {
                ParentCompactNavigationRow(
                    title: lang.pick("布置任务", "Assign a Task"),
                    subtitle: lang.pick("临时任务或按家庭场景快速开始", "Start a one-off or guided family task"),
                    systemImage: "plus.circle.fill",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("parent-mode-today-compose-task")

            NavigationLink {
                ParentAICompanionOverviewView()
            } label: {
                ParentCompactNavigationRow(
                    title: lang.pick("问 AI 教练", "Ask AI Coach"),
                    subtitle: lang.pick("聊天、家庭洞察和育儿建议", "Chat, family insights, and parenting guidance"),
                    systemImage: "sparkles",
                    tint: .purple
                )
            }
            .accessibilityIdentifier("parent-mode-ai-coach-home")

            NavigationLink {
                ParentEmergencyUnlockCenterView()
            } label: {
                let pendingEmergencyCount = familyCloud.pendingScreenTimeEmergencyChildIDs.count
                ParentCompactNavigationRow(
                    title: lang.pick("设备与解锁", "Devices & Unlock"),
                    subtitle: pendingEmergencyCount == 0
                        ? lang.pick("屏幕时间、安全和紧急申请", "Screen time, safety, and emergency requests")
                        : lang.pick("\(pendingEmergencyCount) 个申请待处理", "\(pendingEmergencyCount) requests need attention"),
                    systemImage: "lock.shield",
                    tint: pendingEmergencyCount == 0 ? .teal : .orange
                )
            }
            .accessibilityIdentifier("parent-mode-emergency-unlock-entry")

            NavigationLink {
                ParentTrainingMarketplaceView()
            } label: {
                ParentCompactNavigationRow(
                    title: lang.pick("成长包市场", "Learning Packs"),
                    subtitle: lang.pick("选择可直接安装的完整成长计划", "Browse complete plans ready to install"),
                    systemImage: "storefront.fill",
                    tint: .green
                )
            }
            .accessibilityIdentifier("parent-mode-training-marketplace")
        } header: {
            Text(lang.pick("常用操作", "Quick Actions"))
        }
    }

    private var creativeCenterSection: some View {
        let snapshot = CreativeCenterSnapshot.build(
            assignments: store.assignments,
            childId: store.activeChildId
        )
        return Section {
            NavigationLink {
                ParentCreativeCenterView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(.purple)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lang.pick("创作广场", "Creation Plaza"))
                            .font(.subheadline.weight(.semibold))
                        Text(lang.pick(
                            "布置绘画、音乐、手工、积木、乐高、故事等创作；回看作品和小伙伴点评。",
                            "Assign drawing, music, crafts, blocks, LEGO, and stories; revisit work and companion feedback."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if snapshot.waitingForParent.count > 0 {
                        Text(lang.pick(
                            "\(snapshot.waitingForParent.count) 待确认",
                            "\(snapshot.waitingForParent.count) to review"
                        ))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .accessibilityIdentifier("parent-creative-center-entry")
        } header: {
            Text(lang.pick("作品与创造", "Works & Creation"))
        }
    }

    private var contentCenterSection: some View {
        Section {
            NavigationLink {
                ParentBookCenterView()
            } label: {
                ParentCompactNavigationRow(
                    title: lang.pick("图书馆", "Library"),
                    subtitle: lang.pick("书籍、下载与阅读进度", "Books, downloads, and reading progress"),
                    systemImage: "books.vertical.fill",
                    tint: .blue
                )
            }
            .accessibilityIdentifier("parent-book-center-entry")

            NavigationLink {
                ParentVideoCenterView()
            } label: {
                ParentCompactNavigationRow(
                    title: lang.pick("教育视频", "Educational Videos"),
                    subtitle: lang.pick("已安排的视频与学习结果", "Assigned videos and learning results"),
                    systemImage: "play.rectangle.fill",
                    tint: .red
                )
            }
            .accessibilityIdentifier("parent-video-center-entry")

            NavigationLink {
                ParentCreativeCenterView()
            } label: {
                ParentCompactNavigationRow(
                    title: lang.pick("创作广场", "Creation Plaza"),
                    subtitle: lang.pick("作品、创作任务与 AI 点评", "Projects, creative tasks, and AI feedback"),
                    systemImage: "paintpalette.fill",
                    tint: .purple
                )
            }
            .accessibilityIdentifier("parent-creative-center-entry")
        } header: {
            Text(lang.pick("内容与作品", "Content & Creations"))
        }
    }

    private var familyDataSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isFamilyDataExpanded) {
                NavigationLink {
                    RewardStatusView()
                } label: {
                    ParentCompactNavigationRow(
                        title: lang.pick("成长积分与兑换", "Growth Points & Rewards"),
                        subtitle: lang.pick(
                            "可用 \(store.creditBalance.availableMinutes) · 待确认 \(store.creditBalance.pendingMinutes)",
                            "\(store.creditBalance.availableMinutes) available · \(store.creditBalance.pendingMinutes) pending"
                        ),
                        systemImage: "star.circle.fill",
                        tint: .green
                    )
                }

                NavigationLink {
                    ParentScreenTimeActivityView()
                } label: {
                    ParentCompactNavigationRow(
                        title: lang.pick("App 授权时长", "App Authorized Time"),
                        subtitle: authorizedTimeSubtitle,
                        systemImage: "clock.badge.checkmark",
                        tint: .blue
                    )
                }

                let records = store.recentGrowthRecords()
                if records.isEmpty {
                    Text(lang.pick("还没有成长记录", "No growth activity yet"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(event.title, systemImage: icon(for: event.kind))
                                .font(.subheadline.weight(.semibold))
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                }

                NavigationLink {
                    FamilyMembersView()
                } label: {
                    ParentCompactNavigationRow(
                        title: lang.pick("家庭成员与亲友", "Family & Relatives"),
                        subtitle: lang.pick(
                            "\(store.relativeParticipationSummary.relativeCount) 位亲友 · \(store.relativeParticipationSummary.suggestionCount) 条鼓励",
                            "\(store.relativeParticipationSummary.relativeCount) relatives · \(store.relativeParticipationSummary.suggestionCount) notes"
                        ),
                        systemImage: "person.3.fill",
                        tint: .orange
                    )
                }
            } label: {
                taskCenterGroupLabel(
                    title: lang.pick("成长与家庭数据", "Growth & Family Data"),
                    subtitle: lang.pick("积分、记录、成员和亲友", "Points, activity, members, and relatives"),
                    systemImage: "chart.line.uptrend.xyaxis",
                    count: store.recentGrowthRecords().count
                )
            }
        }
    }

    private var authorizedTimeSubtitle: String {
        let isCurrentChild = familyCloud.guardianActivityLocalChildID == store.activeChildId
        let today = isCurrentChild ? familyCloud.guardianTodayActivitySummary : nil
        let history = isCurrentChild ? familyCloud.guardianActivitySummary : nil
        let todayMinutes = (today?.screenTimeAuthorizedSeconds ?? 0) / 60
        let todayCount = today?.screenTimeAuthorizationCount ?? 0
        let historyMinutes = (history?.screenTimeAuthorizedSeconds ?? 0) / 60
        let days = history?.windowDays ?? 90
        return lang.pick(
            "今日 \(todayMinutes) 分钟 / \(todayCount) 次 · 近 \(days) 天 \(historyMinutes) 分钟",
            "\(todayMinutes) min / \(todayCount) windows today · \(historyMinutes) min in \(days) days"
        )
    }

    // MARK: - 家长 AI 教练

    private var parentAICoachHomeSection: some View {
        let language = store.settings.resolvedParentInterfaceLanguage
        return Section {
            NavigationLink {
                ParentAICompanionOverviewView()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.purple)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.pick("家长 AI 中心", "Parent AI Center"))
                            .font(.subheadline.weight(.bold))
                        Text(language.pick(
                            "多模态聊天与家庭洞察：看今日变化、待处理事项、成长模式和沟通建议，并生成任务草稿。",
                            "Multimodal chat and family insights: review today's changes, action items, growth patterns, communication ideas, and task drafts."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("parent-mode-ai-coach-home")
        }
    }

    // MARK: - 今日待办摘要

    private func selectActiveChild(_ childID: UUID) {
        store.setActiveChild(childID)
        Task {
            try? await familyCloud.refreshGuardianActivitySummaries(for: store)
        }
    }

    private var dailyFocusSection: some View {
        let balance = store.creditBalance

        return Section {
            VStack(alignment: .leading, spacing: 12) {
                if store.hasMultipleChildren {
                    Picker(lang.pick("当前孩子", "Current Child"), selection: Binding(
                        get: { store.activeChildId },
                        set: { selectActiveChild($0) }
                    )) {
                        ForEach(store.children) { child in
                            Text(child.name).tag(child.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("parent-mode-primary-child-picker")
                }

                Label(dailyFocusTitle, systemImage: dailyFocusIcon)
                    .font(.headline)
                    .foregroundStyle(pendingAssignments.isEmpty ? Color.primary : Color.orange)

                Text(dailyFocusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("parent-mode-today-summary-message")

                HStack(spacing: 8) {
                    ParentTodayMetric(
                        title: store.hasMultipleChildren
                            ? lang.pick("全家待确认", "Family Reviews")
                            : lang.pick("待确认", "To Review"),
                        value: "\(pendingAssignments.count)",
                        systemImage: "tray.full",
                        tint: .orange
                    )
                    .accessibilityIdentifier("parent-mode-today-pending")

                    ParentTodayMetric(
                        title: store.hasMultipleChildren
                            ? lang.pick(
                                "\(store.childDisplayName(store.child, for: .chinese))进行中",
                                "\(store.childDisplayName(store.child, for: .english)) Active"
                            )
                            : lang.pick("进行中", "Active"),
                        value: "\(actionableAssignmentCount)",
                        systemImage: "checklist",
                        tint: .blue
                    )
                    .accessibilityIdentifier("parent-mode-today-open")

                    ParentTodayMetric(
                        title: store.hasMultipleChildren
                            ? lang.pick(
                                "\(store.childDisplayName(store.child, for: .chinese))成长积分",
                                "\(store.childDisplayName(store.child, for: .english)) Points"
                            )
                            : lang.pick("可用成长积分", "Available Points"),
                        value: "\(balance.availableMinutes)",
                        systemImage: "star.circle",
                        tint: .green
                    )
                    .accessibilityIdentifier("parent-mode-today-credit")
                }
            }
            .padding(.vertical, 4)

            if let assignment = firstModifiableAssignment {
                NavigationLink {
                    ParentTaskComposerView(editingAssignment: assignment)
                } label: {
                    ParentCompactNavigationRow(
                        title: assignment.task.displayTitle(for: lang),
                        subtitle: lang.pick("最近布置 · 点击编辑", "Recently assigned · Tap to edit"),
                        systemImage: "pencil.circle.fill",
                        tint: .blue
                    )
                }
                .accessibilityIdentifier("parent-mode-edit-current-task")
            }

            if let wishReminder {
                NavigationLink {
                    ParentPocketMoneyWorkbenchView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(wishReminder.headline, systemImage: "gift.fill")
                            .foregroundStyle(Color.orange)
                        Text(wishReminder.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("parent-mode-today-wish-reminder")
            }
        } header: {
            Text(lang.pick("今天", "Today"))
        }
    }

    private var dailyFocusTitle: String {
        if pendingAssignments.isEmpty {
            return lang.pick("没有等待确认的提交", "No submissions waiting")
        }
        return lang.pick(
            "有 \(pendingAssignments.count) 个证明等你确认",
            "\(pendingAssignments.count) submissions need your review"
        )
    }

    private var dailyFocusMessage: String {
        if pendingAssignments.isEmpty {
            if actionableAssignmentCount == 0 {
                let otherChildrenCount = max(0, familyActionableAssignmentCount - actionableAssignmentCount)
                if store.hasMultipleChildren && otherChildrenCount > 0 {
                    return lang.pick(
                        "当前查看的\(store.child.name)暂时没有可推进任务。其他孩子还有 \(otherChildrenCount) 个进行中或待补充任务，可在下面切换孩子查看。",
                        "\(store.childDisplayName(store.child, for: .english)) has no active tasks right now. Other children have \(otherChildrenCount) active or incomplete tasks; switch children below to review them."
                    )
                }
                return lang.pick(
                    "\(store.child.name)今天还没有任务，可以先布置一件小事。",
                    "\(store.childDisplayName(store.child, for: .english)) has no tasks yet. Start with one small action."
                )
            }
            return lang.pick(
                "\(store.child.name)有 \(actionableAssignmentCount) 个任务进行中。",
                "\(store.childDisplayName(store.child, for: .english)) has \(actionableAssignmentCount) active tasks."
            )
        }

        let pendingMinutes = pendingAssignments.reduce(0) { $0 + $1.task.rewardMinutes }
        if store.hasMultipleChildren {
            let breakdown = pendingBreakdown
                .map { "\($0.name) \($0.count) 个" }
                .joined(separator: "，")
            return lang.pick(
                "全家有 \(pendingAssignments.count) 份提交待确认（\(breakdown)），最多发 \(pendingMinutes) 成长积分。",
                "\(pendingAssignments.count) family submissions are waiting, worth up to \(pendingMinutes) Growth Points."
            )
        }
        return lang.pick(
            "\(store.child.name)的提交待确认，最多发 \(pendingMinutes) 成长积分。",
            "\(store.childDisplayName(store.child, for: .english)) has work to review, worth up to \(pendingMinutes) Growth Points."
        )
    }

    private var dailyFocusIcon: String {
        pendingAssignments.isEmpty ? "checkmark.circle" : "exclamationmark.circle.fill"
    }

    private var actionableAssignmentCount: Int {
        activeChildAssignments.filter { $0.status == .open || $0.status == .rejected }.count
    }

    private var firstModifiableAssignment: TaskAssignment? {
        activeChildAssignments
            .filter { store.canParentModify($0) }
            .max { lhs, rhs in
                if lhs.date == rhs.date {
                    return assignmentOrder(lhs.id) < assignmentOrder(rhs.id)
                }
                return lhs.date < rhs.date
            }
    }

    /// Cloud snapshots do not guarantee array order. Use the local array position only
    /// as a deterministic tie-breaker when two assignments share the same timestamp.
    private func assignmentOrder(_ id: UUID) -> Int {
        store.assignments.firstIndex { $0.id == id } ?? -1
    }

    private var familyActionableAssignmentCount: Int {
        store.assignments.filter { $0.status == .open || $0.status == .rejected }.count
    }

    private var pendingBreakdown: [(name: String, count: Int)] {
        store.children.compactMap { child in
            let count = pendingAssignments.filter { $0.childId == child.id }.count
            guard count > 0 else { return nil }
            return (name: child.name, count: count)
        }
    }

    // MARK: - 待确认提交

    private var approvalSection: some View {
        Section {
            ForEach(pendingAssignments) { assignment in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(assignment.task.displayTitle(for: lang))
                            .font(.headline)
                        Spacer(minLength: 8)
                        Text("\(assignment.task.rewardMinutes) \(lang.pick("积分", "points"))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                    if store.hasMultipleChildren {
                        Text(store.childName(for: assignment.childId))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ProofSummary(proof: assignment.proof)
                    if let progress = readingProgressText(for: assignment) {
                        Label(progress, systemImage: "book.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if let review = assignment.aiReview {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(review.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let childFeedback = review.childFeedback,
                                   !childFeedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(lang.pick("给孩子：\(childFeedback)", "For the child: \(childFeedback)"))
                                        .font(.caption)
                                        .foregroundStyle(.purple)
                                }
                                Text(lang.pick("AI 仅提供建议，最终由家长决定。", "AI advice only; the guardian decides."))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            Label(
                                review.recommendation == "suggest_approve"
                                    ? lang.pick("AI 建议通过 · \(Int(review.confidence * 100))%", "AI suggests approval · \(Int(review.confidence * 100))%")
                                    : lang.pick("AI 建议家长判断 · \(Int(review.confidence * 100))%", "AI asks for your judgment · \(Int(review.confidence * 100))%"),
                                systemImage: "sparkles"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(review.recommendation == "suggest_approve" ? .green : .orange)
                        }
                    }
                    HStack(spacing: 10) {
                        Button(lang.pick("批准", "Approve")) {
                            approveWithDraft(assignment)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .accessibilityIdentifier("parent-mode-approve-\(assignment.id)")

                        Menu(lang.pick("退回补充", "Return")) {
                            ForEach(RejectionReason.allCases, id: \.self) { reason in
                                Button(reason.label(for: lang)) {
                                    rejectWithDraft(assignment, reason: reason)
                                }
                                .accessibilityIdentifier("parent-mode-reject-\(assignment.id)-\(reason.rawValue)")
                            }
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("parent-mode-return-menu")
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text(lang.pick("待确认 · \(pendingAssignments.count)", "To Review · \(pendingAssignments.count)"))
        }
    }

    private var reviewFeedbackSection: some View {
        Section {
            if let offlineHint {
                Label(
                    offlineHint,
                    systemImage: offlineHintIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                    .font(.subheadline)
                    .foregroundStyle(offlineHintIsError ? Color.red : Color.secondary)
                    .accessibilityIdentifier("parent-mode-offline-hint")
            }
        } header: {
            Text(lang.pick("最近操作", "Recent Action"))
        }
    }

    /// Cloud approval is durably queued before the local reward is committed.
    /// Assignment-scoped reward ids keep a fresh review from paying the same task twice.
    private func approveWithDraft(_ assignment: TaskAssignment) {
        guard queueGuardianDecision(
            assignmentId: assignment.id,
            status: .approved,
            successText: lang.pick("已批准并发放奖励", "Approved and reward issued")
        ) else { return }
        let reward = store.approve(assignment)
        if reward == nil {
            offlineHintIsError = false
            offlineHint = lang.pick("已批准；该任务奖励此前已发放", "Approved; this task's reward was already issued")
        }
    }

    /// 驳回：先走本地驳回闭环，再把一条「建议驳回」审批草稿脱敏排进离线 outbox。
    private func rejectWithDraft(_ assignment: TaskAssignment, reason: RejectionReason) {
        guard queueGuardianDecision(
            assignmentId: assignment.id,
            status: .rejected,
            successText: lang.pick("已退回，孩子可以重新提交", "Returned so the child can try again")
        ) else { return }
        store.reject(assignment, reason: reason)
    }

    private func readingProgressText(for assignment: TaskAssignment) -> String? {
        guard let reading = assignment.task.reading,
              let spent = assignment.readingSecondsSpent,
              spent > 0 else { return nil }
        let targetSeconds = max(1, reading.minMinutes * 60)
        let percent = min(100, Int((Double(spent) / Double(targetSeconds) * 100).rounded()))
        return lang.pick(
            "App 内阅读 \(spent / 60) 分 \(spent % 60) 秒 · 进度 \(percent)%",
            "Read in app for \(spent / 60)m \(spent % 60)s · \(percent)% complete"
        )
    }

    @discardableResult
    private func queueGuardianDecision(
        assignmentId: UUID,
        status: TaskAssignmentStatus,
        successText: String
    ) -> Bool {
        if familyCloud.hasCloudTask(for: assignmentId),
           !familyCloud.queueGuardianTaskDecision(assignmentId: assignmentId, status: status) {
            offlineHintIsError = true
            offlineHint = lang.pick(
                "审批未保存，请刷新任务后重试。",
                "Approval was not saved. Refresh tasks and try again."
            )
            return false
        }
        offlineHintIsError = false
        offlineHint = successText
        Task {
            do {
                try await familyCloud.syncGuardianTasks(from: store)
            } catch {
                offlineHintIsError = false
                offlineHint = lang.pick(
                    "已保存在本机，联网后会自动同步。",
                    "Saved on this device and will sync automatically."
                )
            }
        }
        return true
    }

    // MARK: - 布置与管理任务

    private var taskManagementSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isTaskCenterExpanded) {
            if store.guardians.count > 1 {
                Picker(lang.pick("当前监护人", "Current Guardian"), selection: Binding(
                    get: { store.currentGuardianId ?? store.guardians.first?.id ?? UUID() },
                    set: { store.setCurrentGuardian($0) }
                )) {
                    ForEach(store.guardians) { guardian in
                        Text(guardian.displayName).tag(guardian.id)
                    }
                }
                .accessibilityIdentifier("parent-mode-current-guardian")
            }
            if store.hasMultipleChildren {
                Picker(lang.pick("选择孩子", "Choose Child"), selection: Binding(
                    get: { store.activeChildId },
                    set: { selectActiveChild($0) }
                )) {
                    ForEach(store.children) { member in
                        Text(member.name).tag(member.id)
                    }
                }
                .accessibilityIdentifier("parent-mode-target-child")
            }

            DisclosureGroup(isExpanded: $isQuickTaskGroupExpanded) {
                Button {
                    composingPreset = nil
                    isComposingTask = true
                } label: {
                    Label(lang.pick("布置今天第一件事", "Assign Today's First Task"), systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .accessibilityIdentifier("parent-mode-compose-task")

                Menu {
                    ForEach(ParentTaskStarterPreset.allCases) { preset in
                        Button {
                            composingPreset = preset
                            isComposingTask = true
                        } label: {
                            Label(preset.menuTitle(for: lang), systemImage: preset.systemImage)
                        }
                    }
                } label: {
                    Label(lang.pick("按家庭场景快速开始", "Quick Start by Scenario"), systemImage: "sparkles")
                        .font(.headline)
                }
                .accessibilityIdentifier("parent-mode-quick-task-presets")
            } label: {
                taskCenterGroupLabel(
                    title: lang.pick("快速布置", "Quick Assign"),
                    subtitle: lang.pick(
                        "临时任务、睡前、家务和学习场景",
                        "One-off tasks, bedtime, chores, and learning"
                    ),
                    systemImage: "bolt.circle.fill",
                    count: ParentTaskStarterPreset.allCases.count + 1
                )
                .accessibilityIdentifier("parent-mode-quick-task-group")
            }

            DisclosureGroup {
                NavigationLink {
                    ParentPackPickerView()
                } label: {
                    Label(lang.pick("从任务包库布置", "Assign from Pack Library"), systemImage: "square.grid.2x2")
                        .font(.headline)
                }
                .accessibilityIdentifier("parent-mode-pack-picker")

                NavigationLink {
                    ParentAIReadingComposerView()
                } label: {
                    Label(lang.pick("AI 布置阅读", "Plan Reading with AI"), systemImage: "book.closed")
                        .font(.headline)
                }
                .accessibilityIdentifier("parent-mode-ai-reading")

                NavigationLink {
                    ParentAIVideoComposerView()
                } label: {
                    Label(lang.pick("布置视频学习", "Assign Video Learning"), systemImage: "play.rectangle")
                        .font(.headline)
                }
                .accessibilityIdentifier("parent-mode-ai-video")
            } label: {
                taskCenterGroupLabel(
                    title: lang.pick("任务包与 AI 布置", "Packs & AI Planning"),
                    subtitle: lang.pick(
                        "任务包、阅读和视频学习",
                        "Task packs, reading, and video learning"
                    ),
                    systemImage: "square.grid.2x2",
                    count: 3
                )
                .accessibilityIdentifier("parent-mode-task-planning-group")
            }

            DisclosureGroup {
                NavigationLink {
                    ParentChildrenManagerView()
                } label: {
                    Label(lang.pick("孩子管理", "Children"), systemImage: "person.2.badge.plus")
                }
                .accessibilityIdentifier("parent-mode-children-manager")

                NavigationLink {
                    ParentPocketMoneyWorkbenchView()
                } label: {
                    Label(lang.pick("零花钱与愿望清单", "Allowance & Wishes"), systemImage: "banknote")
                }
                .accessibilityIdentifier("parent-mode-pocket-money")

                NavigationLink {
                    ParentTaskStatsView()
                } label: {
                    Label(lang.pick("任务完成报表", "Task Reports"), systemImage: "chart.bar.fill")
                }
                .accessibilityIdentifier("parent-mode-task-stats")
            } label: {
                taskCenterGroupLabel(
                    title: lang.pick("家庭后台", "Family Management"),
                    subtitle: lang.pick(
                        "孩子、零花钱、愿望和任务报表",
                        "Children, allowance, wishes, and reports"
                    ),
                    systemImage: "folder.badge.gearshape",
                    count: 3
                )
                .accessibilityIdentifier("parent-mode-family-management-group")
            }

            if activeChildAssignments.isEmpty {
                Text(lang.pick(
                    "还没有任务。先给孩子安排一件容易开始的小事。",
                    "No tasks yet. Start with one small, easy action."
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(parentAssignmentSections) { section in
                    DisclosureGroup {
                        ForEach(parentTaskDisplayItems(for: section.assignments)) { item in
                            switch item {
                            case .assignment(let assignment):
                                parentTaskRow(assignment)
                            case .readingBook(let group):
                                NavigationLink {
                                    ParentReadingTaskGroupDetailView(
                                        group: group,
                                        canModify: { store.canParentModify($0) },
                                        canCancel: { store.canCancelAssignment($0) },
                                        onEdit: { editingTaskTarget = ParentTaskEditTarget(assignment: $0) },
                                        onCancel: { cancelAssignment($0) }
                                    )
                                } label: {
                                    ParentReadingTaskGroupRow(group: group)
                                }
                                .accessibilityIdentifier("parent-mode-reading-book-\(group.id)")
                            }
                        }
                    } label: {
                        taskCenterGroupLabel(
                            title: section.title,
                            subtitle: section.summary,
                            systemImage: section.systemImage,
                            count: parentTaskDisplayItems(for: section.assignments).count
                        )
                    }
                }
            }
            } label: {
                taskCenterGroupLabel(
                    title: lang.pick("任务中心", "Task Center"),
                    subtitle: lang.pick(
                        "为\(store.child.name)布置、编辑和查看任务",
                        "Assign, edit, and review \(store.childDisplayName(store.child, for: .english))'s tasks"
                    ),
                    systemImage: "checklist",
                    count: activeChildAssignments.count
                )
                .accessibilityIdentifier("parent-mode-task-center-toggle")
            }
        } header: {
            Text(lang.pick("任务管理", "Task Management"))
        }
    }

    @ViewBuilder
    private func parentTaskRow(_ assignment: TaskAssignment) -> some View {
        let editIdentifier = assignment.id == firstModifiableAssignment?.id
            ? "parent-mode-edit-latest-task"
            : "parent-mode-edit-task-\(assignment.id)"
        let rowIdentifier = assignment.id == firstModifiableAssignment?.id
            ? "parent-mode-latest-task-row"
            : "parent-mode-task-\(assignment.id)"
        ParentTaskRow(
            assignment: assignment,
            canModify: store.canParentModify(assignment),
            canCancel: store.canCancelAssignment(assignment),
            editAccessibilityIdentifier: editIdentifier,
            rowAccessibilityIdentifier: rowIdentifier
        ) {
            editingTaskTarget = ParentTaskEditTarget(assignment: assignment)
        } onCancel: {
            cancelAssignment(assignment)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if store.canCancelAssignment(assignment) {
                Button(role: .destructive) {
                    cancelAssignment(assignment)
                } label: {
                    Label(lang.pick("撤销", "Cancel"), systemImage: "xmark.circle")
                }
            }
            if store.canParentModify(assignment) {
                Button(role: .destructive) {
                    removeAssignment(assignment)
                } label: {
                    Label(lang.pick("删除", "Delete"), systemImage: "trash")
                }
                Button {
                    editingTaskTarget = ParentTaskEditTarget(assignment: assignment)
                } label: {
                    Label(lang.pick("编辑", "Edit"), systemImage: "pencil")
                }
            }
        }
    }

    private func taskCenterGroupLabel(
        title: String,
        subtitle: String,
        systemImage: String,
        count: Int
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .padding(.vertical, 2)
    }

    /// 当前所选孩子的任务列表（与「布置给谁」保持同一上下文）。
    private var activeChildAssignments: [TaskAssignment] {
        store.assignments.filter { $0.childId == store.activeChildId && $0.status != .cancelled }
    }

    private var parentAssignmentSections: [ParentAssignmentSection] {
        TaskCategory.childDisplayOrder.compactMap { category in
            let assignments = activeChildAssignments.filter { $0.task.category == category }
            guard !assignments.isEmpty else { return nil }
            return ParentAssignmentSection(
                id: category.rawValue,
                title: category.label(for: lang),
                summary: statusSummary(for: assignments),
                systemImage: category.systemImage,
                assignments: assignments
            )
        }
    }

    private func statusSummary(for assignments: [TaskAssignment]) -> String {
        let open = assignments.filter { $0.status == .open || $0.status == .rejected }.count
        let waiting = assignments.filter { $0.status == .submitted }.count
        let done = assignments.filter { $0.status == .approved }.count
        var parts: [String] = []
        if open > 0 { parts.append(lang.pick("进行中 \(open)", "Active \(open)")) }
        if waiting > 0 { parts.append(lang.pick("待确认 \(waiting)", "To review \(waiting)")) }
        if done > 0 { parts.append(lang.pick("已完成 \(done)", "Completed \(done)")) }
        return parts.isEmpty ? lang.pick("暂无进展", "No activity") : parts.joined(separator: " · ")
    }

    private func removeAssignment(_ assignment: TaskAssignment) {
        if familyCloud.hasCloudTask(for: assignment.id) {
            cancelAssignment(assignment)
            return
        }
        if let fileName = assignment.proof.photoFileName {
            ProofPhotoStore.shared.delete(fileName: fileName)
        }
        store.removeAssignment(assignment.id)
    }

    private func cancelAssignment(_ assignment: TaskAssignment) {
        guard store.cancelAssignment(assignment.id, actor: .guardian) else { return }
        queueGuardianDecision(
            assignmentId: assignment.id,
            status: .cancelled,
            successText: lang.pick("任务已撤销", "Task cancelled")
        )
    }

    // MARK: - 成长积分余额

    private var creditSection: some View {
        Section("孩子的成长积分") {
            let balance = store.creditBalance
            LabeledContent("可用积分", value: "\(balance.availableMinutes) 积分")
            LabeledContent("待确认", value: "\(balance.pendingMinutes) 积分")
            LabeledContent("累计获得", value: "\(balance.lifetimeEarnedMinutes) 积分")
            NavigationLink {
                RewardStatusView()
            } label: {
                Label("娱乐时间使用情况", systemImage: "hourglass")
            }
        }
    }

    // MARK: - 最近成长记录

    private var growthRecordSection: some View {
        Section("最近记录") {
            let records = store.recentGrowthRecords()
            if records.isEmpty {
                Text("还没有审批或参与记录")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(event.title, systemImage: icon(for: event.kind))
                            .font(.subheadline)
                        Text(event.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func icon(for kind: FamilyEventKind) -> String {
        switch kind {
        case .taskApproved: return "checkmark.seal"
        case .taskRejected: return "arrow.uturn.backward"
        case .relativeSuggested: return "heart.text.square"
        case .taskAssigned: return "plus.circle"
        case .taskCancelled: return "xmark.circle"
        }
    }

    // MARK: - 亲友参与摘要（只读）

    private var relativeSection: some View {
        Section("亲友参与（只读 / 建议）") {
            let summary = store.relativeParticipationSummary
            LabeledContent("家庭圈亲友", value: "\(summary.relativeCount) 位")
            LabeledContent("亲友鼓励", value: "\(summary.suggestionCount) 条")
            ForEach(store.relatives) { relative in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(relative.displayName) · \(relative.role.label)")
                        .font(.subheadline)
                    Text(relative.capability.canSuggest ? "可查看摘要、可留鼓励" : "仅可查看摘要")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("不可批准任务、不可发成长积分、不可解锁设备")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct ParentTaskEditTarget: Identifiable, Hashable {
    let assignment: TaskAssignment

    var id: UUID { assignment.id }

    static func == (lhs: ParentTaskEditTarget, rhs: ParentTaskEditTarget) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct ParentAssignmentSection: Identifiable {
    let id: String
    let title: String
    let summary: String
    let systemImage: String
    let assignments: [TaskAssignment]
}

private enum ParentTaskDisplayItem: Identifiable {
    case assignment(TaskAssignment)
    case readingBook(ParentReadingTaskGroup)

    var id: String {
        switch self {
        case .assignment(let assignment): return "assignment-\(assignment.id.uuidString)"
        case .readingBook(let group): return "reading-\(group.id)"
        }
    }
}

private struct ParentReadingTaskGroup: Identifiable {
    let id: String
    let title: String
    let assignments: [TaskAssignment]

    var progressText: String { ReadingTaskGrouping.progressText(for: assignments) }
    var statusSummary: String { ReadingTaskGrouping.statusSummary(for: assignments) }
    var rewardText: String {
        GrowthCreditCopy.label(points: ReadingTaskGrouping.totalReward(for: assignments))
    }
}

private func parentTaskDisplayItems(for assignments: [TaskAssignment]) -> [ParentTaskDisplayItem] {
    var groupedAssignments: [String: [TaskAssignment]] = [:]
    for assignment in assignments {
        guard let key = ReadingTaskGrouping.key(for: assignment) else { continue }
        groupedAssignments[key, default: []].append(assignment)
    }

    var emittedGroups: Set<String> = []
    return assignments.compactMap { assignment in
        guard let key = ReadingTaskGrouping.key(for: assignment),
              let group = groupedAssignments[key],
              group.count > 1 else {
            return .assignment(assignment)
        }
        guard !emittedGroups.contains(key) else { return nil }
        emittedGroups.insert(key)
        let title = ReadingTaskGrouping.title(for: group[0]) ?? "阅读任务"
        return .readingBook(ParentReadingTaskGroup(id: key, title: title, assignments: group))
    }
}

private struct ParentReadingTaskGroupRow: View {
    let group: ParentReadingTaskGroup

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(group.assignments.count) 个章节任务 · \(group.statusSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(group.progressText, systemImage: "book.circle.fill")
                    Label(group.rewardText, systemImage: "leaf.fill")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ParentReadingTaskGroupDetailView: View {
    let group: ParentReadingTaskGroup
    let canModify: (TaskAssignment) -> Bool
    let canCancel: (TaskAssignment) -> Bool
    let onEdit: (TaskAssignment) -> Void
    let onCancel: (TaskAssignment) -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.statusSummary)
                        .font(.subheadline.weight(.semibold))
                    Text("\(group.assignments.count) 个章节任务 · 总计 \(group.rewardText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("阅读项目")
            }

            Section {
                ForEach(group.assignments) { assignment in
                    ParentTaskRow(
                        assignment: assignment,
                        canModify: canModify(assignment),
                        canCancel: canCancel(assignment),
                        editAccessibilityIdentifier: "parent-mode-edit-reading-task-\(assignment.id)",
                        rowAccessibilityIdentifier: "parent-mode-reading-task-\(assignment.id)"
                    ) {
                        onEdit(assignment)
                    } onCancel: {
                        onCancel(assignment)
                    }
                }
            } header: {
                Text("章节任务")
            } footer: {
                Text("家长先看书名项目，再进入这里管理每一次阅读任务。")
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 成熟设置/管理类 App 常用的紧凑导航行：图标、标题、单行状态。
private struct ParentCompactNavigationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

enum ParentScreenTimeActivityFormatter {
    struct AppAuthorizationSummary: Equatable {
        var appRef: String
        var durationSeconds: Int
        var eventCount: Int
    }

    struct AppAuthorizationHistoryRow: Equatable {
        var appRef: String
        var authority: String
        var durationSeconds: Int
        var eventCount: Int

        var id: String { "\(appRef)|\(authority)" }
    }

    struct AppAuthorizationHistoryDay: Equatable {
        var date: String
        var durationSeconds: Int
        var eventCount: Int
        var rows: [AppAuthorizationHistoryRow]
    }

    private static let appAuthorityPattern =
        #"^authority:([a-z0-9_]+):app:([a-f0-9]{32})$"#

    static func recentEvents(
        today: FamilyCloudActivitySummary?,
        history: FamilyCloudActivitySummary?
    ) -> [FamilyCloudActivitySummary.RecentEvent] {
        var eventsByID: [String: FamilyCloudActivitySummary.RecentEvent] = [:]
        for event in (history?.recent ?? []) + (today?.recent ?? [])
        where event.kind == .screenTime {
            eventsByID[event.eventId] = event
        }
        return eventsByID.values.sorted { $0.occurredAt > $1.occurredAt }
    }

    static func todayAppAuthorizationSummaries(
        today: FamilyCloudActivitySummary?,
        localDate: String = localDateIdentifier()
    ) -> [AppAuthorizationSummary] {
        let rows = today?.screenTimeAppDaily ?? []
        var summaries: [String: AppAuthorizationSummary] = [:]
        for row in rows where row.date == localDate {
            var summary = summaries[row.appRef] ?? AppAuthorizationSummary(
                appRef: row.appRef,
                durationSeconds: 0,
                eventCount: 0
            )
            summary.durationSeconds += max(0, row.durationSeconds)
            summary.eventCount += max(0, row.eventCount)
            summaries[row.appRef] = summary
        }
        return summaries.values.sorted {
            if $0.durationSeconds == $1.durationSeconds {
                return $0.appRef < $1.appRef
            }
            return $0.durationSeconds > $1.durationSeconds
        }
    }

    static func appAuthorizationHistory(
        history: FamilyCloudActivitySummary?,
        limitDays: Int = 7
    ) -> [AppAuthorizationHistoryDay] {
        guard limitDays > 0 else { return [] }
        let rowsByDate = Dictionary(grouping: history?.screenTimeAppDaily ?? [], by: \.date)
        return rowsByDate.keys.sorted(by: >).prefix(limitDays).map { date in
            var mergedRows: [String: AppAuthorizationHistoryRow] = [:]
            for row in rowsByDate[date] ?? [] {
                let key = "\(row.appRef)|\(row.authority)"
                var merged = mergedRows[key] ?? AppAuthorizationHistoryRow(
                    appRef: row.appRef,
                    authority: row.authority,
                    durationSeconds: 0,
                    eventCount: 0
                )
                merged.durationSeconds += max(0, row.durationSeconds)
                merged.eventCount += max(0, row.eventCount)
                mergedRows[key] = merged
            }
            let rows = mergedRows.values.sorted {
                if $0.durationSeconds == $1.durationSeconds {
                    return $0.appRef < $1.appRef
                }
                return $0.durationSeconds > $1.durationSeconds
            }
            return AppAuthorizationHistoryDay(
                date: date,
                durationSeconds: rows.reduce(0) { $0 + $1.durationSeconds },
                eventCount: rows.reduce(0) { $0 + $1.eventCount },
                rows: rows
            )
        }
    }

    static func localDateIdentifier(
        for date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func appDisplayLabel(
        appRef: String,
        language: AppInterfaceLanguage
    ) -> String {
        let suffix = appRef
            .replacingOccurrences(of: "app:", with: "")
            .prefix(4)
            .uppercased()
        return language.pick("受控 App • \(suffix)", "Controlled App • \(suffix)")
    }

    static func sourceIcon(resourceRef: String?) -> String {
        switch authority(resourceRef: resourceRef) {
        case "growth_points": return "leaf.fill"
        case "parent_pin": return "person.badge.key.fill"
        case "guardian_remote": return "iphone.radiowaves.left.and.right"
        case "school_emergency": return "graduationcap.fill"
        default: return "clock.badge.checkmark"
        }
    }

    static func sourceLabel(
        resourceRef: String?,
        language: AppInterfaceLanguage
    ) -> String {
        switch authority(resourceRef: resourceRef) {
        case "growth_points":
            return language.pick("成长积分", "Growth Points")
        case "parent_pin":
            return language.pick("家长 PIN", "Parent PIN")
        case "guardian_remote":
            return language.pick("家长远程授权", "Guardian Remote")
        case "school_emergency":
            return language.pick("学校紧急批准", "School Emergency")
        default:
            return language.pick("其他批准", "Other Approval")
        }
    }

    private static func authority(resourceRef: String?) -> String? {
        guard let resourceRef else { return nil }
        if resourceRef.hasPrefix("authority:"),
           !resourceRef.contains(":app:") {
            return String(resourceRef.dropFirst("authority:".count))
        }
        guard let expression = try? NSRegularExpression(pattern: appAuthorityPattern) else {
            return nil
        }
        let range = NSRange(resourceRef.startIndex..<resourceRef.endIndex, in: resourceRef)
        guard let match = expression.firstMatch(in: resourceRef, range: range),
              let authorityRange = Range(match.range(at: 1), in: resourceRef) else {
            return nil
        }
        return String(resourceRef[authorityRange])
    }
}

private struct ParentScreenTimeActivityView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @State private var refreshError: String?

    private var language: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    private var today: FamilyCloudActivitySummary? {
        isShowingActiveChild ? familyCloud.guardianTodayActivitySummary : nil
    }

    private var history: FamilyCloudActivitySummary? {
        isShowingActiveChild ? familyCloud.guardianActivitySummary : nil
    }

    private var isShowingActiveChild: Bool {
        familyCloud.guardianActivityLocalChildID == store.activeChildId
    }

    private var activeChildName: String {
        store.children.first(where: { $0.id == store.activeChildId })?.name
            ?? language.pick("当前孩子", "Current Child")
    }

    private var recentEvents: [FamilyCloudActivitySummary.RecentEvent] {
        ParentScreenTimeActivityFormatter.recentEvents(today: today, history: history)
    }

    private var appAuthorizationSummaries: [ParentScreenTimeActivityFormatter.AppAuthorizationSummary] {
        ParentScreenTimeActivityFormatter.todayAppAuthorizationSummaries(today: today)
    }

    private var appAuthorizationHistory: [ParentScreenTimeActivityFormatter.AppAuthorizationHistoryDay] {
        ParentScreenTimeActivityFormatter.appAuthorizationHistory(history: history)
    }

    var body: some View {
        List {
            Section {
                Label(
                    language.pick(
                        "\(activeChildName) 的授权解锁",
                        "\(activeChildName)'s Authorized Unlocks"
                    ),
                    systemImage: "person.crop.circle.badge.checkmark"
                )
                .font(.headline)
            } footer: {
                Text(language.pick(
                    "切换孩子后，这里会独立刷新该孩子的记录。",
                    "Switching children refreshes that child's records independently."
                ))
            }

            Section {
                HStack(spacing: 12) {
                    activityMetric(
                        value: "\((today?.screenTimeAuthorizedSeconds ?? 0) / 60)",
                        label: language.pick("今日授权分钟", "Authorized Today")
                    )
                    activityMetric(
                        value: "\(today?.screenTimeAuthorizationCount ?? 0)",
                        label: language.pick("今日次数", "Windows Today")
                    )
                    activityMetric(
                        value: "\((history?.screenTimeAuthorizedSeconds ?? 0) / 60)",
                        label: language.pick("近 \(history?.windowDays ?? 90) 天", "Last \(history?.windowDays ?? 90) Days")
                    )
                }
            } header: {
                Text(language.pick("授权窗口汇总", "Authorized Window Summary"))
            } footer: {
                Text(language.pick(
                    "这里记录章鱼老师批准的使用窗口，不代表 Apple 实际前台使用时长。",
                    "This records time windows authorized by Octo Teacher, not Apple's measured foreground usage."
                ))
            }

            if !appAuthorizationSummaries.isEmpty {
                Section {
                    ForEach(appAuthorizationSummaries, id: \.appRef) { summary in
                        HStack(spacing: 12) {
                            Image(systemName: "app.badge.checkmark.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ParentScreenTimeActivityFormatter.appDisplayLabel(
                                    appRef: summary.appRef,
                                    language: language
                                ))
                                    .font(.subheadline.weight(.semibold))
                                Text(language.pick(
                                    "今日授权 \(summary.durationSeconds / 60) 分钟 · \(summary.eventCount) 次",
                                    "\(summary.durationSeconds / 60) minutes today · \(summary.eventCount) windows"
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(language.pick("今日逐 App 授权", "Today by App"))
                } footer: {
                    Text(language.pick(
                        "为保护隐私，云端只保存匿名 App 标识。相同标识始终代表同一个 App。",
                        "For privacy, the cloud stores anonymous app references only. The same reference always represents the same app."
                    ))
                }
            }

            if !appAuthorizationHistory.isEmpty {
                Section {
                    ForEach(appAuthorizationHistory, id: \.date) { day in
                        DisclosureGroup {
                            ForEach(day.rows, id: \.id) { row in
                                HStack(spacing: 12) {
                                    Image(systemName: ParentScreenTimeActivityFormatter.sourceIcon(
                                        resourceRef: "authority:\(row.authority)"
                                    ))
                                        .foregroundStyle(.blue)
                                        .frame(width: 26)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(ParentScreenTimeActivityFormatter.appDisplayLabel(
                                            appRef: row.appRef,
                                            language: language
                                        ))
                                            .font(.subheadline.weight(.semibold))
                                        Text(ParentScreenTimeActivityFormatter.sourceLabel(
                                            resourceRef: "authority:\(row.authority)",
                                            language: language
                                        ))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(language.pick(
                                            "\(row.durationSeconds / 60) 分钟",
                                            "\(row.durationSeconds / 60) min"
                                        ))
                                            .font(.subheadline.weight(.semibold))
                                            .monospacedDigit()
                                        Text(language.pick(
                                            "\(row.eventCount) 次",
                                            "\(row.eventCount) windows"
                                        ))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } label: {
                            HStack {
                                Text(day.date)
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 0)
                                Text(language.pick(
                                    "\(day.durationSeconds / 60) 分钟 · \(day.eventCount) 次",
                                    "\(day.durationSeconds / 60) min · \(day.eventCount) windows"
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text(language.pick("最近 7 天逐 App 授权", "Last 7 Days by App"))
                }
            }

            Section {
                if recentEvents.isEmpty {
                    ContentUnavailableView(
                        language.pick("还没有授权记录", "No Authorization History"),
                        systemImage: "clock.badge.questionmark",
                        description: Text(language.pick(
                            "孩子完成一次积分兑换或家长 PIN 解锁后，会在这里显示。",
                            "Growth Point exchanges and Parent PIN unlocks will appear here."
                        ))
                    )
                } else {
                    ForEach(recentEvents, id: \.eventId) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: ParentScreenTimeActivityFormatter.sourceIcon(
                                resourceRef: event.resourceRef
                            ))
                                .foregroundStyle(.blue)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ParentScreenTimeActivityFormatter.sourceLabel(
                                    resourceRef: event.resourceRef,
                                    language: language
                                ))
                                    .font(.subheadline.weight(.semibold))
                                Text(language.pick(
                                    "批准 \((event.durationSeconds ?? 0) / 60) 分钟",
                                    "\((event.durationSeconds ?? 0) / 60) minutes authorized"
                                ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(formattedDate(event.occurredAt))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text(language.pick("逐次记录", "Authorization History"))
            } footer: {
                Text(language.pick(
                    "为保护孩子隐私，云端不保存 App 名称、选择令牌或真实使用轨迹。",
                    "For child privacy, the cloud does not store app names, selection tokens, or detailed usage traces."
                ))
            }

            if let refreshError {
                Section {
                    Label(refreshError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(language.pick("App 授权时长", "App Authorized Time"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.activeChildId) {
            await refresh()
        }
        .refreshable {
            await refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(language.pick("刷新授权记录", "Refresh authorization history"))
            }
        }
    }

    private func activityMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedDate(_ rawValue: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: rawValue) else { return rawValue }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    @MainActor
    private func refresh() async {
        refreshError = nil
        do {
            try await familyCloud.refreshGuardianActivitySummaries(for: store)
        } catch {
            refreshError = language.pick(
                "刷新失败，请检查网络后重试。",
                "Refresh failed. Check your connection and try again."
            )
        }
    }
}

/// 家长工作台顶部的紧凑指标，帮助第一眼判断今天要先处理什么。
private struct ParentTodayMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.headline.monospacedDigit().bold())
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

/// 家长任务管理列表里的单行任务。
private struct ParentTaskRow: View {
    let assignment: TaskAssignment
    let canModify: Bool
    let canCancel: Bool
    let editAccessibilityIdentifier: String
    let rowAccessibilityIdentifier: String
    let onEdit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: assignment.task.category.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(statusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusTint)
                    Text("\(assignment.task.rewardMinutes) 成长积分 · \(assignment.task.requiredProof.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let readingProgress {
                    Label(readingProgress, systemImage: "book.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            if canCancel {
                Button(role: .destructive) {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .accessibilityLabel("撤销任务")
                .accessibilityIdentifier("parent-mode-cancel-task-\(assignment.id)")
            }
            if canModify {
                NavigationLink {
                    ParentTaskComposerView(editingAssignment: assignment)
                } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .accessibilityLabel("编辑任务")
                .accessibilityIdentifier(editAccessibilityIdentifier)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if canModify {
                onEdit()
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier(rowAccessibilityIdentifier)
    }

    private var statusLabel: String {
        switch assignment.status {
        case .open: return "进行中"
        case .submitted: return "等待确认"
        case .approved: return "已完成"
        case .rejected: return "已退回重做"
        case .cancelled: return "已撤销"
        }
    }

    private var statusTint: Color {
        switch assignment.status {
        case .open: return .blue
        case .submitted: return .orange
        case .approved: return .green
        case .rejected: return .red
        case .cancelled: return .secondary
        }
    }

    private var readingProgress: String? {
        guard let reading = assignment.task.reading,
              let spent = assignment.readingSecondsSpent,
              spent > 0 else { return nil }
        let percent = min(100, Int((Double(spent) / Double(max(1, reading.minMinutes * 60)) * 100).rounded()))
        return "\(spent / 60) 分钟 · \(percent)%"
    }
}

/// 家长审核时看到的证明摘要：文字 + 真实照片缩略图。
struct ProofSummary: View {
    let proof: ProofDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if proof.photoFileName != nil || proof.kind == .photo {
                if let fileName = proof.photoFileName,
                   let image = ProofPhotoStore.shared.loadImage(fileName: fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("任务证明照片")
                } else {
                    Label("照片读取失败", systemImage: "photo")
                        .font(.caption)
                }
            }
            if proof.kind == .photoPlaceholder, proof.photoFileName == nil {
                Label(
                    proof.photoPlaceholderName != nil ? "已有照片证明记录" : "还没有照片证明",
                    systemImage: "photo"
                )
                .font(.caption)
            }
            if let audioFileName = proof.audioFileName {
                Button {
                    if let url = ProofVoiceStore.shared.url(fileName: audioFileName) {
                        VoicePlayer.shared.play(url: url)
                    }
                } label: {
                    Label("听孩子的语音说明", systemImage: "play.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("proof-summary-play-audio")
            }
            if !proof.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(proof.text)
            }
        }
        .foregroundStyle(.secondary)
    }
}
