import SwiftUI

/// 家长模块配置草稿中心。
///
/// 这里只预览“今天如何组合模块”，不保存任务、不发成长积分、不解锁设备。
struct MobileModuleConfigurationDraftView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @State private var viewerRole: MobileModuleConfigurationDraftViewerRole
    private let allowedRoles: [MobileModuleConfigurationDraftViewerRole]

    private let builder = MobileModuleConfigurationDraftBuilder()

    init(
        initialRole: MobileModuleConfigurationDraftViewerRole = .guardian,
        allowedRoles: [MobileModuleConfigurationDraftViewerRole] = MobileModuleConfigurationDraftViewerRole.allCases
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _viewerRole = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
    }

    private var snapshot: MobileModuleConfigurationDraftSnapshot {
        builder.build(viewerRole: viewerRole, family: family, schoolFamily: schoolFamily)
    }

    var body: some View {
        List {
            roleSection(snapshot)
            summarySection(snapshot)
            preinstallTrialSection()
            draftItemsSection(snapshot)
            reviewActionsSection(snapshot)
            findingsSection(snapshot)
            sideEffectSection(snapshot)
        }
        .navigationTitle("模块配置草稿")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func roleSection(_ snapshot: MobileModuleConfigurationDraftSnapshot) -> some View {
        Section {
            if allowedRoles.count > 1 {
                Picker("视角", selection: $viewerRole) {
                    ForEach(allowedRoles, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("module-configuration-draft-role-picker")
            } else {
                LabeledContent("视角", value: viewerRole.label)
                    .accessibilityIdentifier("module-configuration-draft-role-\(viewerRole.rawValue)")
            }
            Text(snapshot.headline)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("module-configuration-draft-headline")
        } footer: {
            Text("草稿只用于家长规划和孩子预览；真正创建任务、确认成长积分和开启奖励窗口仍在各自模块完成。")
        }
    }

    private func summarySection(_ snapshot: MobileModuleConfigurationDraftSnapshot) -> some View {
        Section("草稿概览") {
            LabeledContent("状态", value: snapshot.status.label)
                .accessibilityIdentifier("module-configuration-draft-status")
            LabeledContent("可见模块", value: "\(snapshot.publicSummary.visibleItemCount)")
                .accessibilityIdentifier("module-configuration-draft-visible-count")
            LabeledContent("预计时长", value: "\(snapshot.publicSummary.estimatedMinutesTotal) 分钟")
                .accessibilityIdentifier("module-configuration-draft-estimated-minutes")
            if let creditPreviewTotal = snapshot.publicSummary.creditPreviewTotal {
                LabeledContent("成长积分预览", value: "\(creditPreviewTotal) 积分")
                    .accessibilityIdentifier("module-configuration-draft-credit-preview")
            }
            if snapshot.publicSummary.reviewActionCount > 0 {
                LabeledContent("复核行动", value: "\(snapshot.publicSummary.reviewActionCount)")
                    .accessibilityIdentifier("module-configuration-draft-review-action-count")
                LabeledContent("阻断项", value: "\(snapshot.publicSummary.blockingActionCount)")
                    .accessibilityIdentifier("module-configuration-draft-blocking-action-count")
            }
        }
    }

    private func preinstallTrialSection() -> some View {
        Section("成长包试运行") {
            NavigationLink {
                MobileGrowthPackPreinstallTrialSandboxWorkbenchView(
                    initialRole: preinstallTrialRole,
                    allowedRoles: [preinstallTrialRole]
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("安装前配置试运行")
                            .font(.subheadline.weight(.semibold))
                        Text("把成长包安装、今日草稿和学校优先级合成只读预览，不保存配置。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "play.square.stack")
                        .foregroundStyle(.blue)
                }
            }
            .accessibilityIdentifier("module-configuration-draft-link-preinstall-trial")
        }
    }

    private func draftItemsSection(_ snapshot: MobileModuleConfigurationDraftSnapshot) -> some View {
        Section("今日草稿") {
            if snapshot.items.isEmpty {
                Text("当前视角暂无可见草稿")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: item.moduleKey))
                            .foregroundStyle(color(for: item))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(item.dayPart.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("预计 \(item.estimatedMinutes) 分钟")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let credit = item.creditPreviewMinutes {
                                Text("成长积分预览：\(credit) 积分，仍需家长确认")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.green)
                            }
                            if let warning = item.warning {
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("module-configuration-draft-item-\(item.moduleKey.rawValue)-\(item.dayPart.rawValue)")
                }
            }
        }
    }

    @ViewBuilder
    private func reviewActionsSection(_ snapshot: MobileModuleConfigurationDraftSnapshot) -> some View {
        if snapshot.reviewActions.isEmpty {
            EmptyView()
        } else {
            Section("家长复核行动") {
                ForEach(snapshot.reviewActions) { action in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(for: action.priority))
                            .foregroundStyle(color(for: action.priority))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(action.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(action.priority.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(color(for: action.priority))
                            }
                            Text(action.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(action.reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if action.blockedUntilReviewed {
                                Label("复核前不会发布", systemImage: "lock")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("module-configuration-draft-review-action-\(action.moduleKey.rawValue)")
                }
            }
        }
    }

    private func findingsSection(_ snapshot: MobileModuleConfigurationDraftSnapshot) -> some View {
        Section("护栏") {
            ForEach(snapshot.findings) { finding in
                Label {
                    Text(finding.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: icon(for: finding.severity))
                        .foregroundStyle(color(for: finding.severity))
                }
                .accessibilityIdentifier("module-configuration-draft-finding-\(finding.code.rawValue)")
            }
        }
    }

    private func sideEffectSection(_ snapshot: MobileModuleConfigurationDraftSnapshot) -> some View {
        Section("无副作用") {
            LabeledContent("写任务 / 账本", value: (snapshot.publicSummary.writesAssignments || snapshot.publicSummary.writesLedger) ? "会" : "不会")
                .accessibilityIdentifier("module-configuration-draft-boundary-task-ledger")
            LabeledContent("发成长积分 / 解锁", value: (snapshot.publicSummary.grantsCredit || snapshot.publicSummary.unlocksDevice) ? "会" : "不会")
                .accessibilityIdentifier("module-configuration-draft-boundary-credit-device")
            LabeledContent("网络 / AI", value: (snapshot.publicSummary.callsNetwork || snapshot.publicSummary.callsAiProvider || snapshot.publicSummary.callsLocalModel) ? "会" : "不会")
                .accessibilityIdentifier("module-configuration-draft-boundary-network-ai")
            LabeledContent("学校 / LMS", value: (snapshot.publicSummary.writesSchoolSystem || snapshot.publicSummary.callsLms) ? "会" : "不会")
                .accessibilityIdentifier("module-configuration-draft-boundary-school-lms")
            LabeledContent("通知 / 支付", value: (snapshot.publicSummary.sendsNotification || snapshot.publicSummary.createsOrder || snapshot.publicSummary.writesEntitlement) ? "会" : "不会")
                .accessibilityIdentifier("module-configuration-draft-boundary-notification-payment")
        }
    }

    private func icon(for key: MobileModuleLaunchModuleKey) -> String {
        switch key {
        case .todayTasks: return "checklist"
        case .growthPackRuntime: return "shippingbox"
        case .growthPackExecutionHub: return "square.stack.3d.up"
        case .growthPackMarket: return "square.and.arrow.down"
        case .schoolHomework: return "graduationcap"
        case .aiHomeworkGuide: return "questionmark.bubble"
        case .schoolJointApproval: return "person.2.badge.gearshape"
        case .notificationDigestConsent: return "bell.badge"
        case .familyStoryline: return "sparkles"
        case .honorWall: return "trophy"
        case .creditLedger: return "checklist.checked"
        case .rewardWindow: return "timer"
        case .appSelectionPolicy: return "app.badge"
        case .rewardStoreFulfillment: return "gift"
        case .reportsPreview: return "chart.line.uptrend.xyaxis"
        case .onboardingGuide: return "sparkles"
        case .offlineSyncReview: return "arrow.triangle.2.circlepath"
        case .moduleConfigurationDraft: return "rectangle.grid.2x2"
        case .releaseGate: return "checkmark.shield"
        case .familySocialFeedbackEmotionalSafety: return "heart.text.square"
        }
    }

    private func icon(for severity: MobileModuleConfigurationFindingSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func icon(for priority: MobileModuleConfigurationReviewPriority) -> String {
        switch priority {
        case .normal: return "checkmark.circle"
        case .high: return "exclamationmark.circle"
        case .urgent: return "exclamationmark.octagon"
        }
    }

    private func color(for item: MobileModuleConfigurationDraftItem) -> Color {
        item.warning == nil ? .blue : .orange
    }

    private func color(for priority: MobileModuleConfigurationReviewPriority) -> Color {
        switch priority {
        case .normal: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }

    private func color(for severity: MobileModuleConfigurationFindingSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }

    private var preinstallTrialRole: MobileGrowthPackPreinstallTrialRole {
        switch viewerRole {
        case .child: return .child
        case .guardian, .operations: return .guardian
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileModuleConfigurationDraftViewerRole]
    ) -> [MobileModuleConfigurationDraftViewerRole] {
        let source = roles.isEmpty ? MobileModuleConfigurationDraftViewerRole.allCases : roles
        return MobileModuleConfigurationDraftViewerRole.allCases.filter { source.contains($0) }
    }
}
