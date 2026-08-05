import SwiftUI

/// 家庭端成长动态视图。
///
/// 展示成长动态、徽章、成长球星卡、荣誉墙、亲友评论、成长视频日记和励志故事线摘要。
/// 默认家庭私密：顶部可切换「家庭视角 / 亲友视角」，亲友视角只能看到已批准且非私密内容，
/// 用来直观验证隐私边界。亲友评论默认待审核，不会泄露私密内容。
struct FamilyGrowthView: View {
    @Environment(SchoolFamilyStore.self) private var store
    @Environment(LocalFamilyStore.self) private var localFamily
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay
    // 这是家庭设备内的亲友预览开关，不替代真实亲友账号/角色门禁。
    @State private var audience: FamilyFeedAudience = .household
    @State private var relativeDraft: String = ""
    @State private var relativeHint: String?

    private let composer = MobileOfflineActionComposer()

    var body: some View {
        List {
            Section {
                Picker("视角", selection: $audience) {
                    Text("家庭视角").tag(FamilyFeedAudience.household)
                    Text("亲友视角").tag(FamilyFeedAudience.relative)
                }
                .pickerStyle(.segmented)
                Text(audience == .household
                     ? "家庭视角可看到全部内容，包括私密和待审核内容。"
                     : "亲友视角只读，只能看到已批准且非私密的内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text(audience == .household
                     ? "本页用于查看家庭成长记录和亲友可见边界；真实任务状态会在下面同步展示，动态、徽章和荣誉仍是本地预览内容。"
                     : "切到亲友视角时，只展示家长已批准且适合亲友查看的内容；真实任务明细保留在家庭视角。")
            }

            realTaskRecordSection
            storylineSection
            feedSection
            badgesSection
            starCardSection
            honorWallSection
            relativeCommentsSection
            if audience == .relative {
                relativeComposeSection
            }
            vlogSection

            Section {
                NavigationLink {
                    RelativeFamilyParticipationCenterView()
                } label: {
                    Label("亲友参与中心", systemImage: "person.2.wave.2")
                }
                .accessibilityIdentifier("family-growth-link-relative-participation")

                NavigationLink {
                    FamilyGrowthAchievementView()
                } label: {
                    Label("荣誉卡片", systemImage: "trophy")
                }
                .accessibilityIdentifier("family-growth-link-achievement-cards")

                NavigationLink {
                    FamilyAchievementSnapshotDashboardView()
                } label: {
                    Label("成就快照仪表盘", systemImage: "chart.bar.doc.horizontal")
                }
                .accessibilityIdentifier("family-growth-link-achievement-dashboard")

                NavigationLink {
                    GrowthPackMobileDetailView()
                } label: {
                    Label("成长包详情快照", systemImage: "iphone.gen3")
                }
                .accessibilityIdentifier("family-growth-link-mobile-detail")

                NavigationLink {
                    GrowthPackInstallEntitlementView(initialRole: .guardian, allowsRoleSwitching: true)
                } label: {
                    Label("成长包安装权益", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("family-growth-link-install-entitlement")

                NavigationLink {
                    FamilyHonorStorylineConsentView(store: FamilyGrowthAchievementStore())
                } label: {
                    Label("荣誉墙故事线同意", systemImage: "checkmark.seal.text.page")
                }
                .accessibilityIdentifier("family-growth-link-storyline-consent")
            } header: {
                Text("更多能力")
            } footer: {
                Text("这些深度视图用于预览隐私、权益和分享边界；未开放能力会在进入页面后标注为本地预览。")
            }

            MobileOfflineReplaySummarySection(
                report: offlineReplay.report,
                focus: [.relativeComment]
            ) {
                offlineReplay.replay(outbox: offlineOutbox)
            }
        }
        .navigationTitle("家庭成长")
    }

    // MARK: - 真实任务记录

    private var realTaskRecordSection: some View {
        let records = recentTaskRecords
        return Section {
            if audience == .relative {
                Label("亲友视角不展示孩子的真实任务明细", systemImage: "lock.shield")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("family-growth-real-task-relative-boundary")
                Text("亲友只能看到家长已批准、并且允许亲友查看的成长内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if records.isEmpty {
                EmptyHint(text: "家长布置任务后，这里会出现真实成长记录。")
                    .accessibilityIdentifier("family-growth-real-task-empty")
            } else {
                ForEach(records) { assignment in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: assignment.status.familyGrowthSystemImage)
                            .foregroundStyle(assignment.status.familyGrowthTint)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(assignment.task.title)
                                    .font(.subheadline.weight(.semibold))
                                    .accessibilityIdentifier("family-growth-real-task-title")
                                Spacer()
                                Text(assignment.status.familyGrowthLabel)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(assignment.status.familyGrowthTint)
                            }
                            Text("\(localFamily.childName(for: assignment.childId)) · \(assignment.familyGrowthRewardText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("family-growth-real-task-reward-text")
                            Text(assignment.status.familyGrowthNextStep)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("family-growth-real-task-row")
                }
            }
        } header: {
            Text("真实任务记录")
                .accessibilityIdentifier("family-growth-real-task-records")
        } footer: {
            Text(audience == .relative
                 ? "真实任务明细只在家庭视角展示，避免亲友看到孩子的日常安排。"
                 : "这里直接读取本机任务状态：进行中、待确认、已确认和需补充都会同步展示。")
        }
    }

    private var recentTaskRecords: [TaskAssignment] {
        Array(localFamily.assignments
            .sorted { $0.date > $1.date }
            .prefix(4))
    }

    // MARK: - 励志故事线摘要

    private var storylineSection: some View {
        Section(store.storyline.headline) {
            ForEach(store.storyline.milestones) { milestone in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(milestone.title).font(.subheadline.bold())
                        Spacer()
                        Text(milestone.occurredLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(milestone.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 成长动态

    private var feedSection: some View {
        let items = store.visibleFeed(for: audience)
        return Section("成长动态") {
            if items.isEmpty {
                EmptyHint(text: "暂无可见动态")
            } else {
                ForEach(items) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.title).font(.headline)
                            Spacer()
                            VisibilityChip(visibility: entry.visibility, approval: entry.approval)
                        }
                        Text(entry.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !entry.tags.isEmpty {
                            Text(entry.tags.map { "#\($0)" }.joined(separator: " "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 徽章

    private var badgesSection: some View {
        Section("徽章") {
            if store.badges.isEmpty {
                EmptyHint(text: "还没有徽章")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(store.badges) { badge in
                            VStack(spacing: 6) {
                                Image(systemName: badge.systemImage)
                                    .font(.title)
                                    .foregroundStyle(.orange)
                                Text(badge.name)
                                    .font(.caption.bold())
                                Text(badge.earnedLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 96)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - 成长球星卡

    private var starCardSection: some View {
        let cards = store.visibleStarCards(for: audience)
        return Section("成长球星卡") {
            if cards.isEmpty {
                EmptyHint(text: "暂无可见球星卡")
            } else {
                ForEach(cards) { card in
                    StarCardView(card: card)
                }
            }
        }
    }

    // MARK: - 荣誉墙

    private var honorWallSection: some View {
        let items = store.visibleHonorWall(for: audience)
        return Section("荣誉墙") {
            if items.isEmpty {
                EmptyHint(text: "暂无可见荣誉")
            } else {
                ForEach(items) { item in
                    HStack {
                        Image(systemName: "rosette").foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.bold())
                            Text(item.category).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.approval == .pending {
                            Text("待审核")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 亲友评论

    private var relativeCommentsSection: some View {
        let comments = store.visibleComments(for: audience)
        return Section {
            if comments.isEmpty {
                EmptyHint(text: "暂无可见评论")
            } else {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(comment.relativeNickname).font(.subheadline.bold())
                            Spacer()
                            if comment.status == .pending {
                                Text("待审核").font(.caption2).foregroundStyle(.orange)
                            }
                            Text(comment.createdLabel).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(comment.message).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("亲友评论")
        } footer: {
            Text("亲友只读、可留言；留言需家长审核后才会对其他亲友展示，亲友不能批准任务或发放奖励。")
        }
    }

    // MARK: - 亲友留言（离线入队，待家长审核）

    private var relativeComposeSection: some View {
        Section {
            TextField("给孩子留一句鼓励", text: $relativeDraft, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityIdentifier("relative-family-compose-field")
            Button {
                sendRelativeComment()
            } label: {
                Label("发送鼓励（待家长审核）", systemImage: "paperplane")
            }
            .disabled(relativeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("relative-family-compose-submit")
            if let relativeHint {
                Label(relativeHint, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("relative-family-compose-feedback")
            }
        } header: {
            Text("亲友留言")
        } footer: {
            Text("留言只进入本地队列，需家长联网审核后才对其他亲友展示；亲友不能批准任务、发成长积分或解锁设备。")
        }
    }

    private func sendRelativeComment() {
        let message = relativeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        // 亲友身份与家庭动态目标都用稳定脱敏 seed，绝不写真实 relative/family 标识。
        let request = composer.relativeComment(
            targetSeed: "family-feed",
            relativeSeed: "relative-self",
            message: message
        )
        let result = offlineOutbox.enqueue(request)
        relativeHint = MobileOfflineEnqueueFeedback.message(
            for: result,
            successText: "已加入离线队列，等家长审核"
        )
        if case .success = result {
            relativeDraft = ""
        }
    }

    // MARK: - 成长视频日记

    private var vlogSection: some View {
        let items = store.visibleVLOGs(for: audience)
        return Section {
            if items.isEmpty {
                EmptyHint(text: "还没有视频日记")
            } else {
                ForEach(items) { vlog in
                    HStack(spacing: 12) {
                        Image(systemName: "film")
                            .font(.title2)
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vlog.title).font(.subheadline.bold())
                            Text("\(vlog.durationLabel) · \(vlog.placeholderNote)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("成长视频日记")
        } footer: {
            Text("视频日记的拍摄和导入需要家长确认开启；应用不会自动读取或上传任何媒体。")
        }
    }
}

// MARK: - 复用小组件

private struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct VisibilityChip: View {
    let visibility: FamilyFeedVisibility
    let approval: FamilyApprovalState

    var body: some View {
        HStack(spacing: 4) {
            if approval == .pending {
                Text("待审核")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
            Text(visibility.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StarCardView: View {
    let card: GrowthStarCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.childNickname).font(.headline)
                    Text(card.seasonLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("\(card.overall)")
                        .font(.title.bold())
                        .monospacedDigit()
                    Text("综合").font(.caption2).foregroundStyle(.secondary)
                }
            }

            ForEach(AbilityDimension.allCases, id: \.self) { dimension in
                let value = card.rating(for: dimension)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(dimension.label).font(.caption)
                        Spacer()
                        Text("\(value)").font(.caption.bold()).monospacedDigit()
                    }
                    ProgressView(value: Double(value), total: 99)
                        .tint(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private extension TaskAssignmentStatus {
    var familyGrowthLabel: String {
        switch self {
        case .open: return "进行中"
        case .submitted: return "待家长确认"
        case .approved: return "已确认"
        case .rejected: return "需补充"
        case .cancelled: return "已撤销"
        }
    }

    var familyGrowthNextStep: String {
        switch self {
        case .open: return "孩子完成后提交证明，这里会更新状态。"
        case .submitted: return "家长在家长工作台确认后，会发放奖励并沉淀记录。"
        case .approved: return "这条任务已经被家长确认，可以作为成长记录回顾。"
        case .rejected: return "孩子按家长意见补充证明后，可以重新提交。"
        case .cancelled: return "这条任务已撤销，不再计入今天的待办和成长积分。"
        }
    }

    var familyGrowthSystemImage: String {
        switch self {
        case .open: return "circle"
        case .submitted: return "hourglass.circle.fill"
        case .approved: return "checkmark.seal.fill"
        case .rejected: return "arrow.uturn.backward.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    var familyGrowthTint: Color {
        switch self {
        case .open: return .secondary
        case .submitted: return .orange
        case .approved: return .green
        case .rejected: return .red
        case .cancelled: return .secondary
        }
    }
}

private extension TaskAssignment {
    var familyGrowthRewardText: String {
        let reward = GrowthCreditCopy.label(points: task.rewardMinutes)
        switch status {
        case .open: return "完成后奖励 \(reward)"
        case .submitted: return "待确认 \(reward)"
        case .approved: return "已获得 \(reward)"
        case .rejected: return "补充后可获得 \(reward)"
        case .cancelled: return "已撤销"
        }
    }
}
