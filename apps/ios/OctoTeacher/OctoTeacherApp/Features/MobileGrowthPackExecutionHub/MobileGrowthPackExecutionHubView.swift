import SwiftUI

/// iOS 成长包执行中心。
///
/// 本页只聚合本地安全壳入口，不调用网络/AI/LMS，不写账本，不发成长积分，不解锁设备。
struct MobileGrowthPackExecutionHubView: View {
    @State private var role: MobileGrowthPackExecutionHubRole
    @State private var familyAchievementStore = FamilyGrowthAchievementStore()
    private let allowedRoles: [MobileGrowthPackExecutionHubRole]
    private let input: MobileGrowthPackExecutionHubInput
    private let builder = MobileGrowthPackExecutionHubBuilder()

    init(
        initialRole: MobileGrowthPackExecutionHubRole = .child,
        allowedRoles: [MobileGrowthPackExecutionHubRole] = MobileGrowthPackExecutionHubRole.allCases,
        input: MobileGrowthPackExecutionHubInput = .mock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.input = input
    }

    private var hub: MobileGrowthPackExecutionHub {
        builder.build(role: role, input: input)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            adaptiveScheduleSection
            proofPreparationSection
            evidenceTimelineSection
            achievementCardPreviewSection
            honorWallPublicationPreviewSection
            stepSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("成长包执行")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var roleSection: some View {
        Section {
            if allowedRoles.count > 1 {
                Picker("视角", selection: $role) {
                    ForEach(allowedRoles, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(hub.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(hub.title) {
            Text(hub.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            GrowthPackExecutionMetric(title: "步骤", value: hub.publicSummary.visibleStepCount, systemImage: "square.stack.3d.up")
            GrowthPackExecutionMetric(title: "需复核", value: hub.publicSummary.reviewRequiredCount, systemImage: "person.badge.shield.checkmark")
            if role == .guardian {
                GrowthPackExecutionMetric(title: "老师确认", value: hub.publicSummary.teacherReviewCount, systemImage: "graduationcap")
                GrowthPackExecutionMetric(title: "家长确认", value: hub.publicSummary.guardianReviewCount, systemImage: "person.badge.key")
                GrowthPackExecutionMetric(title: "奖励复核", value: hub.publicSummary.rewardReviewCount, systemImage: "gift")
            }
        }
    }

    private var adaptiveScheduleSection: some View {
        Section("今日计划") {
            NavigationLink {
                MobileGrowthPackAdaptiveScheduleView(initialRole: role, allowedRoles: [role])
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .child ? "查看今天适合做什么" : "复核今日排期与窗口风险")
                            .font(.subheadline.weight(.semibold))
                        Text(role == .child
                            ? "按顺序看今天适合做什么、为什么现在先不做；不会自动安排或发奖励。"
                            : "只读查看排期冲突、睡眠/作业/家务/奖励窗口风险、证据缺口和复核边界。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.blue)
                }
            }
            .accessibilityIdentifier("growth-pack-execution-link-adaptive-schedule")
        }
    }

    private var proofPreparationSection: some View {
        Section("准备证明") {
            NavigationLink {
                MobileGrowthPackProofPreparationView(initialRole: role, allowedRoles: [role])
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .child ? "检查提交前要准备什么" : "复核证明准备与提交边界")
                            .font(.subheadline.weight(.semibold))
                        Text(role == .child
                            ? "只看说明、缺口和下一步；不会提交、上传或发奖励。"
                            : "只读查看证明缺口、同意/审核、外部资源、运动异常和奖励前置条件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "doc.badge.clock")
                        .foregroundStyle(.purple)
                }
            }
            .accessibilityIdentifier("growth-pack-execution-link-proof-preparation")
        }
    }

    private var evidenceTimelineSection: some View {
        Section("证据时间线") {
            NavigationLink {
                MobileGrowthPackEvidenceTimelineView(initialRole: role, allowedRoles: [role])
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .child ? "查看证明进度" : "复核证明链")
                            .font(.subheadline.weight(.semibold))
                        Text(role == .child
                            ? "按顺序看哪些证明已准备、哪些还要补充；不会上传或发奖励。"
                            : "只读查看作业、测验、创作、家校确认、亲友鼓励和奖励履约建议。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundStyle(.blue)
                }
            }
            .accessibilityIdentifier("growth-pack-execution-link-evidence-timeline")
        }
    }

    private var achievementCardPreviewSection: some View {
        Section("徽章能力卡预览") {
            NavigationLink {
                MobileGrowthPackAchievementCardPreviewView(initialRole: role, allowedRoles: [role])
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .child ? "看完成后可能沉淀成什么" : "复核徽章能力卡候选与发布边界")
                            .font(.subheadline.weight(.semibold))
                        Text(role == .child
                            ? "把努力可能变成的徽章、能力和记录放在一起看；不会真的发徽章或更新能力卡。"
                            : "只读查看徽章/能力卡候选、证据缺口、可见性/同意/撤回/回滚边界、能力跳变风险和荣誉墙前置条件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "rosette")
                        .foregroundStyle(.pink)
                }
            }
            .accessibilityIdentifier("growth-pack-execution-link-achievement-card-preview")
        }
    }

    private var honorWallPublicationPreviewSection: some View {
        Section("荣誉墙发布预览") {
            NavigationLink {
                MobileHonorWallBadgeStorylinePublicationPreviewView(
                    initialRole: honorWallPreviewRole,
                    allowedRoles: honorWallPreviewAllowedRoles
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .child ? "看想公开的内容到哪一步了" : "复核荣誉墙发布同意与边界")
                            .font(.subheadline.weight(.semibold))
                        Text(role == .child
                            ? "把想放到荣誉墙或分享给亲友的内容放在一起看；不会真的公开、发徽章或通知亲友。"
                            : "只读查看证据缺口、家长同意、孩子 assent、内容审核、撤回 / 删除 / 下架回滚、亲友授权范围和公开摘要泄露风险。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "star.square.on.square")
                        .foregroundStyle(.purple)
                }
            }
            .accessibilityIdentifier("growth-pack-execution-link-honor-wall-publication-preview")
        }
    }

    private var honorWallPreviewRole: MobileHonorWallBadgeStorylinePublicationPreviewRole {
        role == .child ? .child : .guardian
    }

    private var honorWallPreviewAllowedRoles: [MobileHonorWallBadgeStorylinePublicationPreviewRole] {
        // 孩子入口只锁孩子视角；家长入口可只读预览家长与亲友可见两层，不暴露相反视角。
        role == .child ? [.child] : [.guardian, .relative]
    }

    private var stepSection: some View {
        Section("执行步骤") {
            if hub.steps.isEmpty {
                ContentUnavailableView("成长包步骤已隐藏", systemImage: "lock.shield")
            } else {
                ForEach(hub.steps) { step in
                    NavigationLink {
                        destinationView(for: step.destination)
                    } label: {
                        GrowthPackExecutionStepRow(step: step)
                    }
                    .accessibilityIdentifier("growth-pack-execution-step-\(step.kind.rawValue)")
                }
            }
        }
    }

    private var findingSection: some View {
        Section("安全提示") {
            if hub.findings.isEmpty {
                Text("暂无风险提示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(hub.findings) { finding in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.code.rawValue)
                                .font(.caption.bold())
                            Text(finding.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: finding.actionRequired ? "exclamationmark.shield" : "checkmark.shield")
                            .foregroundStyle(finding.actionRequired ? .orange : .green)
                    }
                }
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            GrowthPackExecutionBoundaryFlag(title: "网络 / AI / 本地模型", value: hub.publicSummary.callsNetwork || hub.publicSummary.callsAiProvider || hub.publicSummary.callsLocalModel)
            GrowthPackExecutionBoundaryFlag(title: "LMS / 学校系统", value: hub.publicSummary.callsLms || hub.publicSummary.writesSchoolSystem)
            GrowthPackExecutionBoundaryFlag(title: "账本 / 成长积分 / 设备", value: hub.publicSummary.writesLedger || hub.publicSummary.grantsCredit || hub.publicSummary.unlocksDevice)
            GrowthPackExecutionBoundaryFlag(title: "链接 / 相机 / 上传", value: hub.publicSummary.opensExternalLink || hub.publicSummary.opensCamera || hub.publicSummary.opensPhotoLibrary || hub.publicSummary.opensFilePicker || hub.publicSummary.uploadsMedia)
            GrowthPackExecutionBoundaryFlag(title: "订单 / 权益 / 通知", value: hub.publicSummary.createsOrder || hub.publicSummary.writesEntitlement || hub.publicSummary.sendsNotification)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: MobileGrowthPackExecutionHubDestination) -> some View {
        switch destination {
        case .schoolHomework:
            let targetRole = schoolHomeworkRole
            MobileSchoolHomeworkGrowthPackLinkageWorkbenchView(initialRole: targetRole, allowedRoles: [targetRole])
        case .quizSelfCheck:
            let targetRole = quizRole
            MobileQuizSelfCheckPracticeWorkbenchView(initialRole: targetRole, allowedRoles: [targetRole])
        case .externalResource:
            let targetRole = externalResourceRole
            MobileExternalLearningResourceSafetyWorkbenchView(initialRole: targetRole, allowedRoles: [targetRole])
        case .creativeShowcase:
            let targetRole = creativeShowcaseRole
            MobileCreativeShowcaseSafetyWorkbenchView(initialRole: targetRole, allowedRoles: [targetRole])
        case .creatorRubric:
            let targetRole = creatorRubricRole
            MobileCreatorSkillPackRubricAgeSuitabilityWorkbenchView(initialRole: targetRole, allowedRoles: [targetRole])
        case .rewardFulfillment:
            let targetRole = rewardFulfillmentRole
            MobileRewardStoreInventoryFulfillmentWorkbenchView(initialRole: targetRole, allowedRoles: [targetRole])
        case .familyHonor:
            FamilyAchievementSnapshotDashboardView(
                store: familyAchievementStore,
                initialRole: familyHonorRole,
                allowsRoleSwitching: false
            )
        }
    }

    private var schoolHomeworkRole: MobileSchoolHomeworkGrowthPackLinkageViewerRole {
        role == .child ? .child : .guardian
    }

    private var quizRole: MobileQuizSelfCheckViewerRole {
        role == .child ? .child : .guardian
    }

    private var externalResourceRole: MobileExternalLearningResourceViewerRole {
        role == .child ? .child : .guardian
    }

    private var creativeShowcaseRole: MobileCreativeShowcaseViewerRole {
        role == .child ? .child : .guardian
    }

    private var creatorRubricRole: MobileCreatorSkillPackRubricViewerRole {
        role == .child ? .child : .guardian
    }

    private var rewardFulfillmentRole: MobileRewardStoreFulfillmentRole {
        role == .child ? .child : .guardian
    }

    private var familyHonorRole: FamilyGrowthViewerRole {
        role == .child ? .child : .guardian
    }

    private static func normalizedRoles(_ roles: [MobileGrowthPackExecutionHubRole]) -> [MobileGrowthPackExecutionHubRole] {
        let source = roles.isEmpty ? MobileGrowthPackExecutionHubRole.allCases : roles
        return MobileGrowthPackExecutionHubRole.allCases.filter { source.contains($0) }
    }
}

private struct GrowthPackExecutionStepRow: View {
    let step: MobileGrowthPackExecutionHubStep

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(step.badge)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }
            Text(step.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(step.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(step.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var icon: String {
        switch step.kind {
        case .schoolHomework: return "book.closed"
        case .quizSelfCheck: return "questionmark.square"
        case .externalResource: return "play.rectangle"
        case .creativeShowcase: return "paintpalette"
        case .creatorRubric: return "checklist"
        case .rewardFulfillment: return "gift"
        case .familyHonor: return "rosette"
        }
    }

    private var tint: Color {
        switch step.status {
        case .ready: return .green
        case .active: return .blue
        case .reviewRequired: return .orange
        case .blocked: return .red
        }
    }
}

private struct GrowthPackExecutionMetric: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        LabeledContent {
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct GrowthPackExecutionBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title, value: value ? "会" : "不会")
            .foregroundStyle(value ? .red : .primary)
    }
}
