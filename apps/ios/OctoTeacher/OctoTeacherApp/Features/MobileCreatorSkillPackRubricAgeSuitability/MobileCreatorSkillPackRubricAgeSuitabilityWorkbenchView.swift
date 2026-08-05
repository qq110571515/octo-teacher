import SwiftUI

/// iOS 创作者技能包量规与年龄适配安全壳页面。
///
/// 只消费本地 Manifest 草稿投影，不提交审核、不发布市场、不收费、不写账本、
/// 不发成长积分、不授徽章、不改能力卡、不解锁设备。
struct MobileCreatorSkillPackRubricAgeSuitabilityWorkbenchView: View {
    @State private var role: MobileCreatorSkillPackRubricViewerRole
    private let allowedRoles: [MobileCreatorSkillPackRubricViewerRole]
    private let draft: CreatorManifestPreviewDraft

    init(
        initialRole: MobileCreatorSkillPackRubricViewerRole = .guardian,
        allowedRoles: [MobileCreatorSkillPackRubricViewerRole] = MobileCreatorSkillPackRubricViewerRole.allCases,
        draft: CreatorManifestPreviewDraft = .mock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.draft = draft
    }

    private var workbench: MobileCreatorSkillPackRubricAgeSuitabilityWorkbench {
        MobileCreatorSkillPackRubricAgeSuitabilityBuilder().build(role: role, draft: draft)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            moduleSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("量规适龄")
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
            Text(workbench.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(workbench.title) {
            Text(workbench.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            CreatorRubricMetric(title: "可见模块", value: workbench.publicSummary.visibleModuleCount, systemImage: "square.grid.2x2")
            if role != .child {
                CreatorRubricMetric(title: "已阻断", value: workbench.publicSummary.blockedCount, systemImage: "lock.shield")
                CreatorRubricMetric(title: "年龄阻断", value: workbench.publicSummary.ageBlockedCount, systemImage: "person.crop.circle.badge.exclamationmark")
                CreatorRubricMetric(title: "量规缺证据", value: workbench.publicSummary.rubricEvidenceMissingCount, systemImage: "checklist.unchecked")
                CreatorRubricMetric(title: "成长积分/设备阻断", value: workbench.publicSummary.creditDevicePromiseBlockedCount, systemImage: "creditcard.trianglebadge.exclamationmark")
                CreatorRubricMetric(title: "市场文案阻断", value: workbench.publicSummary.marketplaceBlockedCount, systemImage: "cart.badge.questionmark")
            }
        }
    }

    private var moduleSection: some View {
        Section("模块量规") {
            if workbench.rows.isEmpty {
                ContentUnavailableView("暂无可见模块", systemImage: "lock")
            } else {
                ForEach(workbench.rows) { row in
                    CreatorRubricRow(row: row)
                }
            }
        }
    }

    private var findingSection: some View {
        Section(role == .child ? "安全提示" : "发布前检查") {
            if workbench.findings.isEmpty {
                Text(role == .child ? "暂无风险提示" : "暂无待修项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workbench.findings) { finding in
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
            CreatorRubricBoundaryFlag(title: "提交/发布市场", value: workbench.publicSummary.submitsReview || workbench.publicSummary.publishesMarketplace)
            CreatorRubricBoundaryFlag(title: "收费/权益", value: workbench.publicSummary.chargesPayment || workbench.publicSummary.writesEntitlement)
            CreatorRubricBoundaryFlag(title: "网络/AI/Web", value: workbench.publicSummary.callsNetwork || workbench.publicSummary.callsAI || workbench.publicSummary.opensWebView)
            CreatorRubricBoundaryFlag(title: "账本/成长积分/设备", value: workbench.publicSummary.writesLedger || workbench.publicSummary.grantsCredit || workbench.publicSummary.unlocksDevice)
            CreatorRubricBoundaryFlag(title: "徽章/能力卡写入", value: workbench.publicSummary.grantsBadge || workbench.publicSummary.mutatesAbilityCard)
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileCreatorSkillPackRubricViewerRole]
    ) -> [MobileCreatorSkillPackRubricViewerRole] {
        let source = roles.isEmpty ? MobileCreatorSkillPackRubricViewerRole.allCases : roles
        return MobileCreatorSkillPackRubricViewerRole.allCases.filter { source.contains($0) }
    }
}

private struct CreatorRubricRow: View {
    let row: MobileCreatorSkillPackRubricRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "checklist")
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(row.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(row.state.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }

            Text(row.learningGoal)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Label(row.ageLabel, systemImage: "person.crop.circle")
                Label(row.rubricLabel, systemImage: "list.clipboard")
                Label(row.proofLabel, systemImage: "checkmark.shield")
                Label(row.badgeAbilityLabel, systemImage: "rosette")
                Label(row.creditBoundaryLabel, systemImage: "creditcard")
                Label(row.marketplaceLabel, systemImage: "cart")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Label(row.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(row.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var tint: Color {
        switch row.state {
        case .readyForPractice: return .blue
        case .needsGuardianReview, .needsCreatorFix: return .orange
        case .hiddenFromChild: return .secondary
        case .blocked: return .red
        }
    }
}

private struct CreatorRubricMetric: View {
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

private struct CreatorRubricBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
    }
}
