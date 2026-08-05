import SwiftUI

/// iOS 荣誉墙徽章故事线发布预览安全壳。
///
/// 本页只读展示徽章 / 能力卡 / 创作 / 成长日记 / VLOG / 故事线 / 亲友鼓励进入荣誉墙或亲友
/// 可见区前的发布前置条件：家长同意、孩子 assent、内容审核、撤回 / 删除 / 下架回滚、
/// 亲友授权范围、敏感故事线和公开摘要泄露风险。它不发布荣誉墙、不授徽章、不更新能力卡、
/// 不上传媒体、不打开相机 / 相册 / 文件、不打开外链、不写账本、不发成长积分、不通知亲友，
/// 也不控制设备或屏幕时间。
struct MobileHonorWallBadgeStorylinePublicationPreviewView: View {
    @State private var role: MobileHonorWallBadgeStorylinePublicationPreviewRole
    private let allowedRoles: [MobileHonorWallBadgeStorylinePublicationPreviewRole]
    private let input: MobileHonorWallBadgeStorylinePublicationPreviewInput
    private let builder = MobileHonorWallBadgeStorylinePublicationPreviewBuilder()

    init(
        initialRole: MobileHonorWallBadgeStorylinePublicationPreviewRole = .child,
        allowedRoles: [MobileHonorWallBadgeStorylinePublicationPreviewRole] = MobileHonorWallBadgeStorylinePublicationPreviewRole.allCases,
        input: MobileHonorWallBadgeStorylinePublicationPreviewInput = .mock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.input = input
    }

    private var preview: MobileHonorWallBadgeStorylinePublicationPreview {
        builder.build(role: role, input: input)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            candidateSection
            emotionalSafetyCenterSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("荣誉墙发布预览")
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
            Text(preview.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(preview.title) {
            Text(preview.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            HonorWallPublicationMetric(title: "可见候选", value: preview.publicSummary.visibleCandidateCount, systemImage: "rectangle.stack")
                .accessibilityIdentifier("honor-publication-metric-visible")
            HonorWallPublicationMetric(title: "等确认", value: preview.publicSummary.waitingConsentCount, systemImage: "hand.raised")
                .accessibilityIdentifier("honor-publication-metric-waiting-consent")
            HonorWallPublicationMetric(title: "需审核", value: preview.publicSummary.moderationRequiredCount, systemImage: "eye.trianglebadge.exclamationmark")
                .accessibilityIdentifier("honor-publication-metric-moderation")
            HonorWallPublicationMetric(title: "先暂停", value: preview.publicSummary.blockedCount, systemImage: "pause.circle")
                .accessibilityIdentifier("honor-publication-metric-blocked")
            if role == .guardian {
                HonorWallPublicationMetric(title: "缺家长同意", value: preview.publicSummary.guardianConsentMissingCount, systemImage: "person.badge.shield.checkmark")
                    .accessibilityIdentifier("honor-publication-metric-guardian-consent")
                HonorWallPublicationMetric(title: "缺孩子 assent", value: preview.publicSummary.childAssentMissingCount, systemImage: "figure.child")
                    .accessibilityIdentifier("honor-publication-metric-child-assent")
                HonorWallPublicationMetric(title: "已撤回 / 已下架", value: preview.publicSummary.revokedCount + preview.publicSummary.takenDownCount, systemImage: "arrow.uturn.backward")
                    .accessibilityIdentifier("honor-publication-metric-revoked")
                HonorWallPublicationMetric(title: "亲友越权", value: preview.publicSummary.relativeOverscopeCount, systemImage: "person.2.slash")
                    .accessibilityIdentifier("honor-publication-metric-relative-overscope")
                HonorWallPublicationMetric(title: "故事线泄露风险", value: preview.publicSummary.storylineLeakRiskCount, systemImage: "exclamationmark.bubble")
                    .accessibilityIdentifier("honor-publication-metric-storyline-leak")
                HonorWallPublicationMetric(title: "摘要泄露风险", value: preview.publicSummary.publicSummaryLeakRiskCount, systemImage: "doc.text.magnifyingglass")
                    .accessibilityIdentifier("honor-publication-metric-summary-leak")
            }
            if role == .relative {
                HonorWallPublicationMetric(title: "亲友可见", value: preview.publicSummary.relativeVisibleCount, systemImage: "heart.text.square")
                    .accessibilityIdentifier("honor-publication-metric-relative-visible")
            }
        }
    }

    private var candidateSection: some View {
        Section(role == .relative ? "可以看到的鼓励" : "发布候选") {
            if preview.candidates.isEmpty {
                ContentUnavailableView(
                    role == .relative ? "暂无可见的鼓励内容" : "发布候选已隐藏",
                    systemImage: "lock.shield"
                )
            } else {
                ForEach(preview.candidates) { candidate in
                    HonorWallPublicationCandidateRow(candidate: candidate, role: role)
                }
            }
        }
    }

    private var emotionalSafetyCenterSection: some View {
        Section("家庭社交反馈情绪安全中心") {
            NavigationLink {
                MobileFamilySocialFeedbackEmotionalSafetyCenterView(
                    initialRole: role == .child ? .child : (role == .relative ? .relative : .guardian),
                    allowedRoles: role == .child ? [.child] : (role == .relative ? [.relative] : [.guardian, .relative, .expert])
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .child ? "看看家人和老师的支持到哪一步了" : "复核荣誉墙反馈情绪安全")
                            .font(.subheadline.weight(.semibold))
                        Text(role == .child
                            ? "把家人和老师的支持放一起看；这里只读，看到的都是温和的话，要等家长看过再说。"
                            : "只读复核荣誉墙故事线反馈、亲友评论、成长动态、日记 / VLOG 摘要、专家 / 家长讨论和通知预览的情绪安全、审核状态、撤回 / 删除、亲友撤权与最小披露风险。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(.pink)
                }
            }
            .accessibilityIdentifier("honor-publication-link-emotional-safety")
        }
    }

    private var findingSection: some View {
        Section("安全提示") {
            if preview.findings.isEmpty {
                Text("暂无风险提示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(preview.findings) { finding in
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
                    .accessibilityIdentifier("honor-publication-finding-\(finding.code.rawValue)")
                }
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            HonorWallPublicationBoundaryFlag(title: "发布荣誉墙 / 公开内容", value: preview.publicSummary.publishesHonorWall || preview.publicSummary.publishesContent)
                .accessibilityIdentifier("honor-publication-boundary-publication")
            HonorWallPublicationBoundaryFlag(title: "授徽章 / 更新能力卡", value: preview.publicSummary.grantsBadge || preview.publicSummary.updatesAbilityCard)
                .accessibilityIdentifier("honor-publication-boundary-badge-card")
            HonorWallPublicationBoundaryFlag(title: "通知亲友 / 上传媒体", value: preview.publicSummary.notifiesRelatives || preview.publicSummary.sendsNotification || preview.publicSummary.uploadsMedia)
                .accessibilityIdentifier("honor-publication-boundary-notify-media")
            HonorWallPublicationBoundaryFlag(title: "账本 / 成长积分 / 设备", value: preview.publicSummary.writesLedger || preview.publicSummary.grantsCredit || preview.publicSummary.spendsCredit || preview.publicSummary.unlocksDevice || preview.publicSummary.controlsScreenTime)
                .accessibilityIdentifier("honor-publication-boundary-ledger-device")
            HonorWallPublicationBoundaryFlag(title: "网络 / AI / 本地模型", value: preview.publicSummary.callsNetwork || preview.publicSummary.callsAiProvider || preview.publicSummary.callsLocalModel)
                .accessibilityIdentifier("honor-publication-boundary-network-ai")
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileHonorWallBadgeStorylinePublicationPreviewRole]
    ) -> [MobileHonorWallBadgeStorylinePublicationPreviewRole] {
        let source = roles.isEmpty ? MobileHonorWallBadgeStorylinePublicationPreviewRole.allCases : roles
        return MobileHonorWallBadgeStorylinePublicationPreviewRole.allCases.filter { source.contains($0) }
    }
}

private struct HonorWallPublicationCandidateRow: View {
    let candidate: MobileHonorWallBadgeStorylinePublicationPreviewCandidate
    let role: MobileHonorWallBadgeStorylinePublicationPreviewRole

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(candidate.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(candidate.status.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }
            Text(candidate.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !candidate.gapReason.isEmpty {
                Label(candidate.gapReason, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !candidate.nextStep.isEmpty {
                Label(candidate.nextStep, systemImage: "arrow.forward.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label(candidate.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("honor-publication-candidate-\(candidate.sourceKind.rawValue)-\(candidate.status.rawValue)")
    }

    private var icon: String {
        switch candidate.sourceKind {
        case .badge: return "rosette"
        case .abilityCard: return "person.crop.square.badge.video"
        case .creativeWork: return "paintpalette"
        case .growthDiary: return "book"
        case .vlog: return "video"
        case .storyline: return "text.book.closed"
        case .relativeEncouragement: return "heart.text.square"
        }
    }

    private var tint: Color {
        if candidate.isBlocked { return .red }
        switch candidate.status {
        case .publicationCandidate, .relativeVisible: return .green
        case .waitingConsent, .needsModeration: return .orange
        case .revoked, .takenDown, .onHold: return .red
        }
    }
}

private struct HonorWallPublicationMetric: View {
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

private struct HonorWallPublicationBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title, value: value ? "会" : "不会")
            .foregroundStyle(value ? .red : .primary)
    }
}
