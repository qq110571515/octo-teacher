import SwiftUI

/// iOS 成长包徽章能力卡预览安全壳。
///
/// 本页只读展示“完成后可能沉淀成什么”的本地预览：徽章候选、成长球星卡能力卡候选、
/// 荣誉墙/故事线候选、家庭成就记录、亲友可见候选和家长可见性/撤回/回滚边界。
/// 它不授徽章、不更新能力卡、不发布荣誉墙、不提交证明、不上传媒体、不打开相机/相册/文件、
/// 不打开外链、不写账本、不发成长积分、不发通知，也不控制设备或屏幕时间。
struct MobileGrowthPackAchievementCardPreviewView: View {
    @State private var role: MobileGrowthPackExecutionHubRole
    private let allowedRoles: [MobileGrowthPackExecutionHubRole]
    private let input: MobileGrowthPackAchievementCardPreviewInput
    private let builder = MobileGrowthPackAchievementCardPreviewBuilder()

    init(
        initialRole: MobileGrowthPackExecutionHubRole = .child,
        allowedRoles: [MobileGrowthPackExecutionHubRole] = MobileGrowthPackExecutionHubRole.allCases,
        input: MobileGrowthPackAchievementCardPreviewInput = .mock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.input = input
    }

    private var preview: MobileGrowthPackAchievementCardPreview {
        builder.build(role: role, input: input)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            candidateSection
            abilityHintSection
            honorWallPublicationPreviewSection
            regressionAppealExplanationPreviewSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("徽章能力卡预览")
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
            GrowthPackAchievementCardMetric(title: "候选", value: preview.publicSummary.visibleCandidateCount, systemImage: "rosette")
                .accessibilityIdentifier("achievement-card-metric-candidates")
            GrowthPackAchievementCardMetric(title: "可能沉淀", value: preview.publicSummary.previewReadyCount, systemImage: "checkmark.seal")
                .accessibilityIdentifier("achievement-card-metric-preview-ready")
            GrowthPackAchievementCardMetric(title: "先暂停", value: preview.publicSummary.blockedCount, systemImage: "pause.circle")
                .accessibilityIdentifier("achievement-card-metric-blocked")
            GrowthPackAchievementCardMetric(title: "能力提示", value: preview.publicSummary.abilityHintCount, systemImage: "chart.line.uptrend.xyaxis")
                .accessibilityIdentifier("achievement-card-metric-ability-hints")
            if role == .guardian {
                GrowthPackAchievementCardMetric(title: "待验证", value: preview.publicSummary.verificationRequiredCount, systemImage: "shield.lefthalf.filled")
                    .accessibilityIdentifier("achievement-card-metric-verification")
                GrowthPackAchievementCardMetric(title: "待同意", value: preview.publicSummary.consentRequiredCount, systemImage: "hand.raised")
                    .accessibilityIdentifier("achievement-card-metric-consent")
                GrowthPackAchievementCardMetric(title: "待审核", value: preview.publicSummary.moderationRequiredCount, systemImage: "eye.trianglebadge.exclamationmark")
                    .accessibilityIdentifier("achievement-card-metric-moderation")
                GrowthPackAchievementCardMetric(title: "跳变风险", value: preview.publicSummary.abilityJumpRiskCount, systemImage: "exclamationmark.triangle")
                    .accessibilityIdentifier("achievement-card-metric-ability-jump")
            }
        }
    }

    private var candidateSection: some View {
        Section("完成后可能沉淀成什么") {
            if preview.candidates.isEmpty {
                ContentUnavailableView("徽章能力卡候选已隐藏", systemImage: "lock.shield")
            } else {
                ForEach(preview.candidates) { candidate in
                    GrowthPackAchievementCardCandidateRow(candidate: candidate, role: role)
                }
            }
        }
    }

    private var abilityHintSection: some View {
        Section("能力维度成长方向") {
            if preview.abilityHints.isEmpty {
                Text("暂无能力提示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(preview.abilityHints) { hint in
                    GrowthPackAchievementCardAbilityRow(hint: hint, role: role)
                }
            }
        }
    }

    private var honorWallPublicationPreviewSection: some View {
        Section("荣誉墙发布预览") {
            NavigationLink {
                MobileHonorWallBadgeStorylinePublicationPreviewView(
                    initialRole: role == .child ? .child : .guardian,
                    allowedRoles: role == .child ? [.child] : [.guardian, .relative]
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .child ? "看想公开的内容到哪一步了" : "复核荣誉墙发布同意与边界")
                            .font(.subheadline.weight(.semibold))
                        Text(role == .child
                            ? "公开到荣誉墙或分享给亲友前要等家长 / 老师确认；这里只读看状态和下一步。"
                            : "只读查看家长同意、孩子 assent、内容审核、撤回 / 删除 / 下架回滚、亲友授权范围和公开摘要泄露风险。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "star.square.on.square")
                        .foregroundStyle(.purple)
                }
            }
            .accessibilityIdentifier("achievement-card-link-honor-wall-publication")
        }
    }

    private var regressionAppealExplanationPreviewSection: some View {
        Section("回退 / 申诉解释预览") {
            NavigationLink {
                MobileAbilityCardRegressionAppealExplanationPreviewView(
                    initialRole: role == .child ? .child : .guardian,
                    allowedRoles: role == .child ? [.child] : [.guardian, .relative, .teacher]
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .child ? "看看能力卡为什么先暂停、下一步怎么办" : "复核能力卡回退 / 冻结 / 申诉解释边界")
                            .font(.subheadline.weight(.semibold))
                        Text(role == .child
                            ? "用温和的话说明能力卡为什么先暂停，以及现在是申诉中、等待复核还是继续努力；这里只读。"
                            : "只读查看能力维度回退、冻结、申诉、证据撤回、学校作业退回、可穿戴异常、创作撤权和公开 / 亲友可见边界。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(.orange)
                }
            }
            .accessibilityIdentifier("achievement-card-link-regression-appeal")
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
                    .accessibilityIdentifier("achievement-card-finding-\(finding.code.rawValue)")
                }
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            GrowthPackAchievementCardBoundaryFlag(title: "网络 / AI / 本地模型", value: preview.publicSummary.callsNetwork || preview.publicSummary.callsAiProvider || preview.publicSummary.callsLocalModel)
                .accessibilityIdentifier("achievement-card-boundary-network-ai")
            GrowthPackAchievementCardBoundaryFlag(title: "授徽章 / 更新能力卡", value: preview.publicSummary.grantsBadge || preview.publicSummary.updatesAbilityCard)
                .accessibilityIdentifier("achievement-card-boundary-badge-card")
            GrowthPackAchievementCardBoundaryFlag(title: "发布荣誉墙 / 公开内容", value: preview.publicSummary.publishesHonorWall || preview.publicSummary.publishesContent)
                .accessibilityIdentifier("achievement-card-boundary-honor-publication")
            GrowthPackAchievementCardBoundaryFlag(title: "账本 / 成长积分 / 设备", value: preview.publicSummary.writesLedger || preview.publicSummary.grantsCredit || preview.publicSummary.spendsCredit || preview.publicSummary.unlocksDevice || preview.publicSummary.controlsScreenTime)
                .accessibilityIdentifier("achievement-card-boundary-ledger-device")
            GrowthPackAchievementCardBoundaryFlag(title: "相机 / 相册 / 上传 / 提交", value: preview.publicSummary.opensCamera || preview.publicSummary.opensPhotoLibrary || preview.publicSummary.opensFilePicker || preview.publicSummary.uploadsMedia || preview.publicSummary.submitsProof)
                .accessibilityIdentifier("achievement-card-boundary-media-submit")
        }
    }

    private static func normalizedRoles(_ roles: [MobileGrowthPackExecutionHubRole]) -> [MobileGrowthPackExecutionHubRole] {
        let source = roles.isEmpty ? MobileGrowthPackExecutionHubRole.allCases : roles
        return MobileGrowthPackExecutionHubRole.allCases.filter { source.contains($0) }
    }
}

private struct GrowthPackAchievementCardCandidateRow: View {
    let candidate: MobileGrowthPackAchievementCardPreviewCandidate
    let role: MobileGrowthPackExecutionHubRole

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
        .accessibilityIdentifier("achievement-card-candidate-\(candidate.category.rawValue)-\(candidate.status.rawValue)")
    }

    private var icon: String {
        switch candidate.category {
        case .badge: return "rosette"
        case .abilityCard: return "person.crop.square.badge.video"
        case .honorWall: return "star.square"
        case .storyline: return "book"
        case .familyAchievement: return "house"
        case .relativeShare: return "person.2"
        case .guardianBoundary: return "person.badge.shield.checkmark"
        }
    }

    private var tint: Color {
        if candidate.isBlocked { return .red }
        switch candidate.status {
        case .previewReady: return .green
        case .needsMoreEvidence: return .blue
        case .waitingConsent, .waitingReview: return .orange
        case .blocked: return .red
        }
    }
}

private struct GrowthPackAchievementCardAbilityRow: View {
    let hint: MobileGrowthPackAchievementCardPreviewAbilityHint
    let role: MobileGrowthPackExecutionHubRole

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(hint.jumpRisk ? Color.orange : Color.green)
                    .frame(width: 24)
                Text(hint.dimension.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if role == .guardian, hint.jumpRisk {
                    Text("跳变风险")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
            }
            Text(hint.growthNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(hint.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("achievement-card-ability-\(hint.dimension.rawValue)")
    }
}

private struct GrowthPackAchievementCardMetric: View {
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

private struct GrowthPackAchievementCardBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title, value: value ? "会" : "不会")
            .foregroundStyle(value ? .red : .primary)
    }
}
