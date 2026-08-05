import SwiftUI

/// iOS 成长包证据时间线。
///
/// 本页只读展示本地证据状态，不打开外链/相机/相册，不上传证明，不写账本，不发成长积分。
struct MobileGrowthPackEvidenceTimelineView: View {
    @State private var role: MobileGrowthPackExecutionHubRole
    private let allowedRoles: [MobileGrowthPackExecutionHubRole]
    private let input: MobileGrowthPackEvidenceTimelineInput
    private let builder = MobileGrowthPackEvidenceTimelineBuilder()

    init(
        initialRole: MobileGrowthPackExecutionHubRole = .child,
        allowedRoles: [MobileGrowthPackExecutionHubRole] = MobileGrowthPackExecutionHubRole.allCases,
        input: MobileGrowthPackEvidenceTimelineInput = .mock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.input = input
    }

    private var timeline: MobileGrowthPackEvidenceTimeline {
        builder.build(role: role, input: input)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            timelineSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("证据时间线")
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
            Text(timeline.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(timeline.title) {
            Text(timeline.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            GrowthPackEvidenceTimelineMetric(title: "节点", value: timeline.publicSummary.visibleNodeCount, systemImage: "list.bullet.rectangle")
            GrowthPackEvidenceTimelineMetric(title: "补证明", value: timeline.publicSummary.evidenceGapCount, systemImage: "doc.badge.clock")
            GrowthPackEvidenceTimelineMetric(title: "需复核", value: timeline.publicSummary.reviewRequiredCount, systemImage: "person.badge.shield.checkmark")
            if role == .guardian {
                GrowthPackEvidenceTimelineMetric(title: "老师确认", value: timeline.publicSummary.teacherReviewCount, systemImage: "graduationcap")
                GrowthPackEvidenceTimelineMetric(title: "奖励复核", value: timeline.publicSummary.rewardReviewCount, systemImage: "gift")
            }
        }
    }

    private var timelineSection: some View {
        Section("证明节点") {
            if timeline.nodes.isEmpty {
                ContentUnavailableView("证据节点已隐藏", systemImage: "lock.shield")
            } else {
                ForEach(timeline.nodes) { node in
                    GrowthPackEvidenceTimelineRow(node: node)
                }
            }
        }
    }

    private var findingSection: some View {
        Section("安全提示") {
            if timeline.findings.isEmpty {
                Text("暂无风险提示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(timeline.findings) { finding in
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
            GrowthPackEvidenceTimelineBoundaryFlag(title: "网络 / AI / 本地模型", value: timeline.publicSummary.callsNetwork || timeline.publicSummary.callsAiProvider || timeline.publicSummary.callsLocalModel)
            GrowthPackEvidenceTimelineBoundaryFlag(title: "LMS / 学校系统", value: timeline.publicSummary.callsLms || timeline.publicSummary.writesSchoolSystem)
            GrowthPackEvidenceTimelineBoundaryFlag(title: "账本 / 成长积分 / 设备", value: timeline.publicSummary.writesLedger || timeline.publicSummary.grantsCredit || timeline.publicSummary.unlocksDevice)
            GrowthPackEvidenceTimelineBoundaryFlag(title: "链接 / 相机 / 上传", value: timeline.publicSummary.opensExternalLink || timeline.publicSummary.opensCamera || timeline.publicSummary.opensPhotoLibrary || timeline.publicSummary.opensFilePicker || timeline.publicSummary.uploadsMedia)
            GrowthPackEvidenceTimelineBoundaryFlag(title: "发布 / 订单 / 权益", value: timeline.publicSummary.publishesContent || timeline.publicSummary.createsOrder || timeline.publicSummary.writesEntitlement)
        }
    }

    private static func normalizedRoles(_ roles: [MobileGrowthPackExecutionHubRole]) -> [MobileGrowthPackExecutionHubRole] {
        let source = roles.isEmpty ? MobileGrowthPackExecutionHubRole.allCases : roles
        return MobileGrowthPackExecutionHubRole.allCases.filter { source.contains($0) }
    }
}

private struct GrowthPackEvidenceTimelineRow: View {
    let node: MobileGrowthPackEvidenceTimelineNode

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(node.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(node.status.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }
            Text(node.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(node.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(node.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var icon: String {
        switch node.kind {
        case .homeworkProof: return "doc.text"
        case .quizSelfCheck: return "questionmark.square"
        case .externalResource: return "play.rectangle"
        case .creativeProof: return "paintpalette"
        case .teacherReview: return "graduationcap"
        case .guardianReview: return "person.badge.shield.checkmark"
        case .relativeEncouragement: return "message.badge"
        case .rewardReview: return "gift"
        case .familyHonor: return "rosette"
        }
    }

    private var tint: Color {
        switch node.status {
        case .ready: return .green
        case .waitingReview: return .orange
        case .needsMoreEvidence: return .blue
        case .blocked: return .red
        }
    }
}

private struct GrowthPackEvidenceTimelineMetric: View {
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

private struct GrowthPackEvidenceTimelineBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title, value: value ? "会" : "不会")
            .foregroundStyle(value ? .red : .primary)
    }
}
