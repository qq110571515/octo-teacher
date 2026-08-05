import SwiftUI

/// iOS 能力卡回退 / 冻结 / 申诉解释预览安全壳。
///
/// 本页只读展示能力卡回退、冻结、申诉 / 复核、证据撤回、学校作业退回 / 重提交、
/// 可穿戴异常、创作撤权、公开 / 亲友可见边界和敏感摘要泄露风险的温和解释。
/// 它不回退能力卡、不降低能力分、不处理申诉、不提交 / 退回作业、不验证老师、不确认家长、
/// 不通知亲友、不写账本、不发 / 扣成长积分、不兑换奖励、不控制屏幕时间、不解锁设备，
/// 也不接网络 / 云 API / AI / 本地模型 / LMS。导航只传角色与安全枚举。
struct MobileAbilityCardRegressionAppealExplanationPreviewView: View {
    @State private var role: MobileAbilityCardRegressionAppealExplanationPreviewRole
    private let allowedRoles: [MobileAbilityCardRegressionAppealExplanationPreviewRole]
    private let input: MobileAbilityCardRegressionAppealExplanationPreviewInput
    private let builder = MobileAbilityCardRegressionAppealExplanationPreviewBuilder()

    init(
        initialRole: MobileAbilityCardRegressionAppealExplanationPreviewRole = .child,
        allowedRoles: [MobileAbilityCardRegressionAppealExplanationPreviewRole] = MobileAbilityCardRegressionAppealExplanationPreviewRole.allCases,
        input: MobileAbilityCardRegressionAppealExplanationPreviewInput = .mock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.input = input
    }

    private var preview: MobileAbilityCardRegressionAppealExplanationPreview {
        builder.build(role: role, input: input)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            entrySection
            findingSection
            sideEffectSection
        }
        .navigationTitle("回退申诉解释")
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
            AbilityRegressionAppealMetric(title: "解释条目", value: preview.publicSummary.visibleEntryCount, systemImage: "text.justify.left")
            if role == .child {
                AbilityRegressionAppealMetric(title: "申诉中", value: preview.publicSummary.appealInProgressCount, systemImage: "hand.raised")
                AbilityRegressionAppealMetric(title: "等待复核", value: preview.publicSummary.waitingReviewCount, systemImage: "hourglass")
                AbilityRegressionAppealMetric(title: "稳定优势", value: preview.publicSummary.stableStrengthCount, systemImage: "checkmark.seal")
            }
            if role == .guardian {
                AbilityRegressionAppealMetric(title: "能力回退", value: preview.publicSummary.revertedCount, systemImage: "arrow.uturn.backward")
                AbilityRegressionAppealMetric(title: "能力卡冻结", value: preview.publicSummary.frozenCount, systemImage: "snowflake")
                AbilityRegressionAppealMetric(title: "申诉中", value: preview.publicSummary.appealInProgressCount, systemImage: "hand.raised")
                AbilityRegressionAppealMetric(title: "证据撤回", value: preview.publicSummary.evidenceRevokedCount, systemImage: "doc.badge.ellipsis")
                AbilityRegressionAppealMetric(title: "作业退回", value: preview.publicSummary.homeworkReturnCount, systemImage: "arrow.uturn.left.square")
                AbilityRegressionAppealMetric(title: "可穿戴异常", value: preview.publicSummary.wearableAnomalyCount, systemImage: "waveform.path.ecg")
                AbilityRegressionAppealMetric(title: "创作撤权", value: preview.publicSummary.creationRevokedCount, systemImage: "paintpalette")
                AbilityRegressionAppealMetric(title: "泄露风险", value: preview.publicSummary.leakRiskCount, systemImage: "eye.trianglebadge.exclamationmark")
            }
            if role == .relative {
                AbilityRegressionAppealMetric(title: "稳定优势", value: preview.publicSummary.stableStrengthCount, systemImage: "checkmark.seal")
            }
            if role == .teacher {
                AbilityRegressionAppealMetric(title: "作业退回", value: preview.publicSummary.homeworkReturnCount, systemImage: "arrow.uturn.left.square")
            }
        }
    }

    private var entrySection: some View {
        Section(entrySectionTitle) {
            if preview.entries.isEmpty {
                ContentUnavailableView("解释内容已隐藏", systemImage: "lock.shield")
            } else {
                ForEach(preview.entries) { entry in
                    AbilityRegressionAppealEntryRow(entry: entry, role: role)
                }
            }
        }
    }

    private var entrySectionTitle: String {
        switch role {
        case .child: return "发生了什么 · 下一步"
        case .guardian: return "回退 / 申诉解释复核"
        case .relative: return "稳定优势与已公开成长"
        case .teacher: return "作业退回 / 重提交"
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
                }
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            AbilityRegressionAppealBoundaryFlag(title: "网络 / AI / 本地模型 / LMS", value: preview.publicSummary.callsNetwork || preview.publicSummary.callsAiProvider || preview.publicSummary.callsLocalModel || preview.publicSummary.callsLms)
            AbilityRegressionAppealBoundaryFlag(title: "回退能力卡 / 降低能力分", value: preview.publicSummary.revertsAbilityCard || preview.publicSummary.lowersAbilityScore)
            AbilityRegressionAppealBoundaryFlag(title: "处理申诉 / 撤回证据", value: preview.publicSummary.processesAppeal || preview.publicSummary.revokesEvidence)
            AbilityRegressionAppealBoundaryFlag(title: "提交 / 退回作业 / 验证老师", value: preview.publicSummary.returnsHomework || preview.publicSummary.verifiesTeacher || preview.publicSummary.writesSchoolSystem)
            AbilityRegressionAppealBoundaryFlag(title: "账本 / 成长积分 / 设备 / 屏幕时间", value: preview.publicSummary.writesLedger || preview.publicSummary.grantsCredit || preview.publicSummary.spendsCredit || preview.publicSummary.unlocksDevice || preview.publicSummary.controlsScreenTime)
            AbilityRegressionAppealBoundaryFlag(title: "通知亲友 / 公开内容", value: preview.publicSummary.notifiesRelative || preview.publicSummary.publishesContent || preview.publicSummary.sendsNotification)
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileAbilityCardRegressionAppealExplanationPreviewRole]
    ) -> [MobileAbilityCardRegressionAppealExplanationPreviewRole] {
        let source = roles.isEmpty ? MobileAbilityCardRegressionAppealExplanationPreviewRole.allCases : roles
        return MobileAbilityCardRegressionAppealExplanationPreviewRole.allCases.filter { source.contains($0) }
    }
}

private struct AbilityRegressionAppealEntryRow: View {
    let entry: MobileAbilityCardRegressionAppealExplanationPreviewEntry
    let role: MobileAbilityCardRegressionAppealExplanationPreviewRole

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(entry.status.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }
            if !entry.explanation.isEmpty {
                Text(entry.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.nextStep.isEmpty {
                Label(entry.nextStep, systemImage: "arrow.forward.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label(entry.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var icon: String {
        switch entry.category {
        case .abilityRegression: return "arrow.uturn.backward"
        case .abilityCardFrozen: return "snowflake"
        case .appealReview: return "hand.raised"
        case .evidenceRevoked: return "doc.badge.ellipsis"
        case .schoolHomeworkReturn: return "arrow.uturn.left.square"
        case .wearableAnomaly: return "waveform.path.ecg"
        case .creationRevoked: return "paintpalette"
        case .visibilityBoundary: return "person.badge.shield.checkmark"
        case .sensitiveSummaryRisk: return "eye.trianglebadge.exclamationmark"
        case .stableStrength: return "checkmark.seal"
        case .consentedPublicGrowth: return "hand.thumbsup"
        }
    }

    private var tint: Color {
        if entry.isOnHold { return .red }
        switch entry.status {
        case .stable, .keepGoing: return .green
        case .appealInProgress, .waitingReview, .teacherReturn, .guardianReview: return .orange
        case .onHold, .blocked: return .red
        }
    }
}

private struct AbilityRegressionAppealMetric: View {
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

private struct AbilityRegressionAppealBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title, value: value ? "会" : "不会")
            .foregroundStyle(value ? .red : .primary)
    }
}
