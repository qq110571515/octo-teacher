import SwiftUI

/// 成长日记 / VLOG / 故事线工作台。
///
/// 页面只展示本地安全快照，不调用媒体权限、网络、AI、成长积分账本、通知或设备控制。
struct GrowthDiaryVlogStorylineWorkbenchView: View {
    @State private var store: FamilyGrowthAchievementStore
    @State private var role: MobileGrowthDiaryVlogViewerRole
    private let availableRoles: [MobileGrowthDiaryVlogViewerRole]

    init(
        store: FamilyGrowthAchievementStore = FamilyGrowthAchievementStore(),
        initialRole: MobileGrowthDiaryVlogViewerRole = .guardian,
        allowedRoles: [MobileGrowthDiaryVlogViewerRole] = MobileGrowthDiaryVlogViewerRole.allCases
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _store = State(initialValue: store)
        _role = State(initialValue: resolvedRole)
        self.availableRoles = normalized
    }

    private var workbench: MobileGrowthDiaryVlogStorylineWorkbench {
        MobileGrowthDiaryVlogStorylineBuilder(store: store).build(role: role)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            itemSection
            consentBoundarySection
            emotionalSafetyCenterSection
            nextActionSection
            boundarySection
            sideEffectSection
        }
        .navigationTitle("成长日记")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var roleSection: some View {
        Section {
            if availableRoles.count > 1 {
                Picker("视角", selection: $role) {
                    ForEach(availableRoles, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(workbench.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(workbench.headline) {
            MetricLine(title: "可见素材", value: workbench.publicSummary.visibleItemCount, systemImage: "rectangle.stack")
            MetricLine(title: "日记", value: workbench.publicSummary.diaryCount, systemImage: "book")
            MetricLine(title: "VLOG 草稿", value: workbench.publicSummary.vlogDraftCount, systemImage: "film")
            if role == .guardian {
                MetricLine(title: "待复核", value: workbench.publicSummary.pendingReviewCount, systemImage: "clock")
                MetricLine(title: "已保护", value: workbench.publicSummary.blockedCount, systemImage: "exclamationmark.shield")
            }
            if role == .relative {
                MetricLine(title: "亲友可见", value: workbench.publicSummary.relativeVisibleCount, systemImage: "person.2")
                MetricLine(title: "被隐藏", value: workbench.publicSummary.hiddenItemCount, systemImage: "lock")
            }
        }
    }

    private var itemSection: some View {
        Section("故事素材") {
            if workbench.items.isEmpty {
                ContentUnavailableView(
                    role == .relative ? "暂无亲友可见片段" : "暂无可展示素材",
                    systemImage: role == .relative ? "lock" : "square.and.pencil"
                )
            } else {
                ForEach(workbench.items) { item in
                    GrowthDiaryVlogItemRow(item: item)
                }
            }
        }
    }

    private var consentBoundarySection: some View {
        Section("同意边界") {
            NavigationLink {
                FamilyHonorStorylineConsentView(
                    store: store,
                    initialRole: consentRole(for: role),
                    allowsRoleSwitching: false
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .child ? "看看哪些故事可以被分享" : "复核成长故事线同意边界")
                            .font(.subheadline.weight(.semibold))
                        Text(role == .relative
                            ? "只读查看亲友可见层，不展示家庭私密、撤回或阻断原因。"
                            : "查看家庭私密、亲友可见、公开脱敏三层，以及发布门禁、撤回传播和无副作用边界。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.badge.shield.checkmark")
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityIdentifier("growth-diary-vlog-link-consent-boundary")
        }
    }

    private var emotionalSafetyCenterSection: some View {
        Section("家庭社交反馈情绪安全中心") {
            NavigationLink {
                MobileFamilySocialFeedbackEmotionalSafetyCenterView(
                    initialRole: role == .child ? .child : .guardian,
                    allowedRoles: role == .child ? [.child] : [.guardian, .relative, .expert]
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .child ? "看看家人和老师的支持到哪一步了" : "复核日记 / VLOG 反馈情绪安全")
                            .font(.subheadline.weight(.semibold))
                        Text(role == .child
                            ? "把家人和老师的支持放一起看；这里只读，看到的都是温和的话，要等家长看过再说。"
                            : "只读复核成长日记 / VLOG 连续性、亲友评论、荣誉墙反馈、专家 / 家长讨论和通知预览的情绪安全、审核状态、撤回 / 删除、亲友撤权与最小披露风险。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(.pink)
                }
            }
            .accessibilityIdentifier("growth-diary-vlog-link-emotional-safety")
        }
    }

    private var nextActionSection: some View {
        Section("下一步") {
            ForEach(workbench.nextActions) { action in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.subheadline.bold())
                        Text(action.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: action.actionRequired ? "exclamationmark.circle" : "arrow.forward.circle")
                        .foregroundStyle(action.actionRequired ? .orange : .blue)
                }
            }
        }
    }

    private var boundarySection: some View {
        Section("安全边界") {
            ForEach(workbench.boundaries) { boundary in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(boundary.title)
                            .font(.subheadline.bold())
                        Text(boundary.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: boundary.isBlocked ? "hand.raised" : "checkmark.shield")
                        .foregroundStyle(boundary.isBlocked ? .orange : .green)
                }
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            GrowthDiaryBoundaryFlag(title: "打开相机/相册", value: workbench.publicSummary.opensCamera || workbench.publicSummary.opensPhotoLibrary)
            GrowthDiaryBoundaryFlag(title: "上传媒体/发布", value: workbench.publicSummary.uploadsMedia || workbench.publicSummary.publishesStoryline)
            GrowthDiaryBoundaryFlag(title: "评论/通知", value: workbench.publicSummary.sendsComment || workbench.publicSummary.sendsNotification)
            GrowthDiaryBoundaryFlag(title: "网络/AI", value: workbench.publicSummary.callsNetwork || workbench.publicSummary.callsAIProvider)
            GrowthDiaryBoundaryFlag(title: "成长积分/账本/设备", value: workbench.publicSummary.grantsCredit || workbench.publicSummary.writesLedger || workbench.publicSummary.unlocksDevice)
            GrowthDiaryBoundaryFlag(title: "学校系统", value: workbench.publicSummary.writesSchoolSystem)
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileGrowthDiaryVlogViewerRole]
    ) -> [MobileGrowthDiaryVlogViewerRole] {
        let source = roles.isEmpty ? MobileGrowthDiaryVlogViewerRole.allCases : roles
        return MobileGrowthDiaryVlogViewerRole.allCases.filter { source.contains($0) }
    }

    private func consentRole(for role: MobileGrowthDiaryVlogViewerRole) -> FamilyHonorStorylineConsentViewerRole {
        switch role {
        case .child:
            return .child
        case .guardian:
            return .guardian
        case .relative:
            return .relative
        }
    }
}

private struct GrowthDiaryVlogItemRow: View {
    let item: MobileGrowthDiaryVlogStorylineItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(item.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(item.occurredLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(item.kind.label)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                Text(item.reviewState.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }

            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(item.mediaStateLabel, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(item.supportiveCopy, systemImage: "heart")
                .font(.caption)
                .foregroundStyle(.pink)

            Label(item.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            if item.showsGuardianReviewHint {
                Label("家长正式处理入口尚未执行；这里仅显示需要把关。", systemImage: "person.badge.shield.checkmark")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if item.canContinueDraft {
                Label("继续草稿不会打开媒体权限或上传内容。", systemImage: "square.and.pencil")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            if item.canRelativeEncourage {
                Label("鼓励需要家长审核，不会直接发成长积分。", systemImage: "text.bubble")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            if !item.tags.isEmpty {
                Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("growth-diary-vlog-item-\(item.kind.rawValue)-\(item.reviewState.rawValue)")
    }

    private var tint: Color {
        switch item.reviewState {
        case .savedPrivate: return .blue
        case .pendingGuardianReview: return .orange
        case .relativeVisible, .familyVisible, .publicRedacted: return .green
        case .withdrawn: return .secondary
        case .blocked: return .red
        }
    }
}

private struct MetricLine: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        LabeledContent {
            Text("\(value)").monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct GrowthDiaryBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
    }
}
