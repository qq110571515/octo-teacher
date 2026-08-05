import SwiftUI

/// iOS 成长包证明准备安全壳。
///
/// 本页只读展示提交前准备清单，不打开外链/相机/相册/文件，不上传证明，
/// 不写账本、不发成长积分、不授徽章、不改能力卡，也不控制设备。
struct MobileGrowthPackProofPreparationView: View {
    @State private var role: MobileGrowthPackExecutionHubRole
    private let allowedRoles: [MobileGrowthPackExecutionHubRole]
    private let input: MobileGrowthPackProofPreparationInput
    private let builder = MobileGrowthPackProofPreparationBuilder()

    init(
        initialRole: MobileGrowthPackExecutionHubRole = .child,
        allowedRoles: [MobileGrowthPackExecutionHubRole] = MobileGrowthPackExecutionHubRole.allCases,
        input: MobileGrowthPackProofPreparationInput = .mock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.input = input
    }

    private var preparation: MobileGrowthPackProofPreparation {
        builder.build(role: role, input: input)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            preparationSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("准备证明")
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
            Text(preparation.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(preparation.title) {
            Text(preparation.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            GrowthPackProofPreparationMetric(title: "可以准备", value: preparation.publicSummary.readyCount, systemImage: "checkmark.circle")
            GrowthPackProofPreparationMetric(title: "已阻断", value: preparation.publicSummary.blockedCount, systemImage: "lock.shield")
            GrowthPackProofPreparationMetric(title: "等同意", value: preparation.publicSummary.consentRequiredCount, systemImage: "person.badge.shield.checkmark")
            if role == .guardian {
                GrowthPackProofPreparationMetric(title: "等审核", value: preparation.publicSummary.moderationRequiredCount, systemImage: "checkmark.seal")
                GrowthPackProofPreparationMetric(title: "需复核", value: preparation.publicSummary.reviewRequiredCount, systemImage: "exclamationmark.shield")
            }
        }
    }

    private var preparationSection: some View {
        Section("提交前清单") {
            if preparation.items.isEmpty {
                ContentUnavailableView("内容已隐藏", systemImage: "lock.shield")
            } else {
                ForEach(preparation.items) { item in
                    GrowthPackProofPreparationRow(item: item)
                }
            }
        }
    }

    private var findingSection: some View {
        Section("安全提示") {
            if preparation.findings.isEmpty {
                Text("暂无风险提示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(preparation.findings) { finding in
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
            GrowthPackProofPreparationBoundaryFlag(title: "网络 / AI / 学校系统", value: preparation.publicSummary.callsNetwork || preparation.publicSummary.callsAiProvider || preparation.publicSummary.callsLocalModel || preparation.publicSummary.callsLms || preparation.publicSummary.writesSchoolSystem)
            GrowthPackProofPreparationBoundaryFlag(title: "链接 / 相机 / 相册 / 文件 / 上传", value: preparation.publicSummary.opensExternalLink || preparation.publicSummary.opensCamera || preparation.publicSummary.opensPhotoLibrary || preparation.publicSummary.opensFilePicker || preparation.publicSummary.uploadsMedia)
            GrowthPackProofPreparationBoundaryFlag(title: "账本 / 成长积分 / 奖励", value: preparation.publicSummary.writesLedger || preparation.publicSummary.grantsCredit || preparation.publicSummary.spendsCredit || preparation.publicSummary.fulfillsReward)
            GrowthPackProofPreparationBoundaryFlag(title: "徽章 / 能力卡 / 设备", value: preparation.publicSummary.grantsBadge || preparation.publicSummary.updatesAbilityCard || preparation.publicSummary.unlocksDevice || preparation.publicSummary.controlsScreenTime)
            GrowthPackProofPreparationBoundaryFlag(title: "通知 / 发布", value: preparation.publicSummary.sendsNotification || preparation.publicSummary.publishesContent)
        }
    }

    private static func normalizedRoles(_ roles: [MobileGrowthPackExecutionHubRole]) -> [MobileGrowthPackExecutionHubRole] {
        let source = roles.isEmpty ? MobileGrowthPackExecutionHubRole.allCases : roles
        return MobileGrowthPackExecutionHubRole.allCases.filter { source.contains($0) }
    }
}

private struct GrowthPackProofPreparationRow: View {
    let item: MobileGrowthPackProofPreparationItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(item.status.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }
            Text(item.instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !item.missingReason.isEmpty {
                Label(item.missingReason, systemImage: "info.circle")
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
    }

    private var icon: String {
        switch item.kind {
        case .homeworkNote: return "doc.text"
        case .quizReflection: return "checkmark.bubble"
        case .creativeStatement: return "paintpalette"
        case .externalResourceNote: return "link.badge.plus"
        case .wearableActivitySummary: return "figure.run"
        case .guardianContext: return "person.badge.shield.checkmark"
        case .rewardBoundary: return "gift"
        }
    }

    private var tint: Color {
        switch item.status {
        case .readyToPrepare: return .green
        case .needsMoreWork: return .blue
        case .waitingConsent, .waitingReview: return .orange
        case .blocked: return .red
        }
    }
}

private struct GrowthPackProofPreparationMetric: View {
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

private struct GrowthPackProofPreparationBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title, value: value ? "会" : "不会")
            .foregroundStyle(value ? .red : .primary)
    }
}
