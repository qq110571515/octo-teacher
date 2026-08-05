import SwiftUI

/// iOS 家庭社交反馈情绪安全中心安全壳。
///
/// 本页只读展示亲友鼓励、荣誉墙故事线、成长动态、成长日记 / VLOG 连续性、专家 / 家长
/// 主题讨论和通知预览的情绪安全与审核状态：家长同意、孩子 assent、审核、压力语言、
/// 奖励承诺、成长积分数值泄露、跨孩子内容、专家讨论泄露、连续性缺口、通知情绪安全、
/// 亲友越权和最小披露风险。它不发布评论、不审核内容、不批准荣誉墙、不治理讨论、
/// 不通知亲友 / 孩子、不上传媒体、不打开相机 / 相册 / 文件、不打开外链、不写账本、
/// 不发成长积分，也不控制设备或屏幕时间。
struct MobileFamilySocialFeedbackEmotionalSafetyCenterView: View {
    @State private var role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole
    private let allowedRoles: [MobileFamilySocialFeedbackEmotionalSafetyCenterRole]
    private let input: MobileFamilySocialFeedbackEmotionalSafetyCenterInput
    private let builder = MobileFamilySocialFeedbackEmotionalSafetyCenterBuilder()

    init(
        initialRole: MobileFamilySocialFeedbackEmotionalSafetyCenterRole = .child,
        allowedRoles: [MobileFamilySocialFeedbackEmotionalSafetyCenterRole] = MobileFamilySocialFeedbackEmotionalSafetyCenterRole.allCases,
        input: MobileFamilySocialFeedbackEmotionalSafetyCenterInput = .mock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.input = input
    }

    private var center: MobileFamilySocialFeedbackEmotionalSafetyCenter {
        builder.build(role: role, input: input)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            itemSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("情绪安全中心")
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
            Text(center.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(center.title) {
            Text(center.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            FamilySocialFeedbackMetric(title: "可见反馈", value: center.publicSummary.visibleItemCount, systemImage: "bubble.left.and.bubble.right")
                .accessibilityIdentifier("emotional-safety-metric-visible")
            if role == .child {
                FamilySocialFeedbackMetric(title: "温和支持", value: center.publicSummary.gentleSupportCount, systemImage: "heart")
                    .accessibilityIdentifier("emotional-safety-metric-gentle-support")
                FamilySocialFeedbackMetric(title: "等家长看", value: center.publicSummary.waitingReviewCount, systemImage: "hand.raised")
                    .accessibilityIdentifier("emotional-safety-metric-waiting-review")
            }
            if role == .relative {
                FamilySocialFeedbackMetric(title: "已通过鼓励", value: center.publicSummary.relativeVisibleCount, systemImage: "heart.text.square")
                    .accessibilityIdentifier("emotional-safety-metric-relative-visible")
                FamilySocialFeedbackMetric(title: "等家长看", value: center.publicSummary.waitingReviewCount, systemImage: "hand.raised")
                    .accessibilityIdentifier("emotional-safety-metric-waiting-review")
            }
            if role == .guardian {
                FamilySocialFeedbackMetric(title: "需审核", value: center.publicSummary.moderationRequiredCount, systemImage: "eye.trianglebadge.exclamationmark")
                    .accessibilityIdentifier("emotional-safety-metric-moderation")
                FamilySocialFeedbackMetric(title: "压力语言", value: center.publicSummary.pressureLanguageRiskCount, systemImage: "exclamationmark.bubble")
                    .accessibilityIdentifier("emotional-safety-metric-pressure")
                FamilySocialFeedbackMetric(title: "奖励承诺", value: center.publicSummary.rewardPromiseRiskCount, systemImage: "creditcard.trianglebadge.exclamationmark")
                    .accessibilityIdentifier("emotional-safety-metric-reward-promise")
                FamilySocialFeedbackMetric(title: "缺同意 / assent", value: center.publicSummary.guardianConsentMissingCount + center.publicSummary.childAssentMissingCount, systemImage: "person.badge.shield.checkmark")
                FamilySocialFeedbackMetric(title: "撤回 / 删除", value: center.publicSummary.revokedCount + center.publicSummary.removedCount, systemImage: "arrow.uturn.backward")
                FamilySocialFeedbackMetric(title: "跨孩子 / 专家泄露", value: center.publicSummary.crossChildLeakRiskCount + center.publicSummary.expertDiscussionLeakRiskCount, systemImage: "person.2.slash")
                FamilySocialFeedbackMetric(title: "通知情绪风险", value: center.publicSummary.notificationRiskCount, systemImage: "bell.badge")
                FamilySocialFeedbackMetric(title: "亲友越权", value: center.publicSummary.relativeOverscopeCount, systemImage: "lock.slash")
            }
        }
    }

    private var itemSection: some View {
        Section(itemSectionTitle) {
            if center.items.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "lock.shield"
                )
            } else {
                ForEach(center.items) { item in
                    FamilySocialFeedbackItemRow(item: item, role: role)
                }
            }
        }
    }

    private var findingSection: some View {
        Section("安全提示") {
            if center.findings.isEmpty {
                Text("暂无风险提示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(center.findings) { finding in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.code.label)
                                .font(.caption.bold())
                            Text(finding.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: finding.actionRequired ? "exclamationmark.shield" : "checkmark.shield")
                            .foregroundStyle(finding.actionRequired ? .orange : .green)
                    }
                    .accessibilityIdentifier("emotional-safety-finding-\(finding.code.rawValue)")
                }
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            FamilySocialFeedbackBoundaryFlag(title: "发布评论 / 审核内容", value: center.publicSummary.postsComment || center.publicSummary.moderatesContent || center.publicSummary.reviewsCreativeWork)
            FamilySocialFeedbackBoundaryFlag(title: "批准荣誉墙 / 治理讨论", value: center.publicSummary.approvesStoryline || center.publicSummary.governsDiscussion || center.publicSummary.publishesHonorWall)
            FamilySocialFeedbackBoundaryFlag(title: "通知亲友 / 孩子", value: center.publicSummary.notifiesRelatives || center.publicSummary.notifiesChild || center.publicSummary.sendsNotification)
            FamilySocialFeedbackBoundaryFlag(title: "账本 / 成长积分 / 设备", value: center.publicSummary.writesLedger || center.publicSummary.grantsCredit || center.publicSummary.spendsCredit || center.publicSummary.unlocksDevice || center.publicSummary.controlsScreenTime)
            FamilySocialFeedbackBoundaryFlag(title: "网络 / AI / 本地模型", value: center.publicSummary.callsNetwork || center.publicSummary.callsAiProvider || center.publicSummary.callsLocalModel)
        }
    }

    private var itemSectionTitle: String {
        switch role {
        case .child: return "家人和老师的支持"
        case .guardian: return "社交反馈"
        case .relative: return "你的鼓励"
        case .expert: return "通用主题边界"
        }
    }

    private var emptyTitle: String {
        switch role {
        case .child: return "暂无可看的支持"
        case .guardian: return "反馈已隐藏"
        case .relative: return "暂无可见的鼓励内容"
        case .expert: return "暂无通用主题内容"
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileFamilySocialFeedbackEmotionalSafetyCenterRole]
    ) -> [MobileFamilySocialFeedbackEmotionalSafetyCenterRole] {
        let source = roles.isEmpty ? MobileFamilySocialFeedbackEmotionalSafetyCenterRole.allCases : roles
        return MobileFamilySocialFeedbackEmotionalSafetyCenterRole.allCases.filter { source.contains($0) }
    }
}

private struct FamilySocialFeedbackItemRow: View {
    let item: MobileFamilySocialFeedbackEmotionalSafetyCenterItem
    let role: MobileFamilySocialFeedbackEmotionalSafetyCenterRole

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(item.statusDisplayLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }
            if !item.summary.isEmpty {
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !item.gapReason.isEmpty {
                Label(item.gapReason, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !item.nextStep.isEmpty {
                Label(item.nextStep, systemImage: "arrow.forward.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label(item.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("emotional-safety-item-\(item.channel.rawValue)-\(item.status.rawValue)")
    }

    private var icon: String {
        switch item.channel {
        case .relativeEncouragement: return "heart.text.square"
        case .honorWallStoryline: return "rosette"
        case .growthMoment: return "sparkles"
        case .diaryVlogContinuity: return "book"
        case .expertTopicDiscussion: return "lightbulb"
        case .parentTopicDiscussion: return "person.2.wave.2"
        case .notificationPreview: return "bell.badge"
        }
    }

    private var tint: Color {
        if item.isBlocked { return .red }
        switch item.status {
        case .gentleSupport, .relativeVisible, .expertBoundary: return .green
        case .waitingReview, .needsModeration: return .orange
        case .revoked, .removed, .onHold: return .red
        }
    }
}

private struct FamilySocialFeedbackMetric: View {
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

private struct FamilySocialFeedbackBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title, value: value ? "会" : "不会")
            .foregroundStyle(value ? .red : .primary)
    }
}
