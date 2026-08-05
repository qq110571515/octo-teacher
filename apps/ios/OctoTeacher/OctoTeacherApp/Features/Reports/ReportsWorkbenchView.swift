import SwiftUI

/// iOS 成长报告 / 周报预览。
///
/// 只读聚合本地 mock 数据，不生成文件、不上传、不通知、不发成长积分、不解锁设备。
struct ReportsWorkbenchView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(MockScreenTimeController.self) private var screenTime
    @Environment(AICompanionSessionStore.self) private var aiCompanionSessions
    @State private var role: ReportsViewerRole
    private let allowedRoles: [ReportsViewerRole]

    init(
        initialRole: ReportsViewerRole = .guardian,
        allowedRoles: [ReportsViewerRole] = ReportsViewerRole.allCases
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
    }

    private var workbench: ReportsWorkbench {
        ReportsWorkbenchBuilder().build(
            role: role,
            family: family,
            schoolFamily: schoolFamily,
            screenTime: screenTime,
            aiCompanionSessions: aiCompanionSessions.records
        )
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            metricsSection
            sectionsSection
            findingsSection
            boundarySection
        }
        .navigationTitle("成长报告")
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
            } else {
                LabeledContent("视角", value: role.label)
            }
            Text(workbench.note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(workbench.title) {
            Text(workbench.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            ReportsMetricRow(id: "section-count", title: "报告模块", value: workbench.publicSummary.sectionCount, suffix: "个", systemImage: "doc.text")
            ReportsMetricRow(id: "average-progress", title: "平均进度", value: workbench.publicSummary.averageProgress, suffix: "%", systemImage: "chart.line.uptrend.xyaxis")
            if role == .guardian {
                ReportsMetricRow(id: "action-required", title: "待处理", value: workbench.publicSummary.actionRequiredCount, suffix: "项", systemImage: "exclamationmark.circle")
            }
        }
    }

    private var metricsSection: some View {
        Section("本周数字") {
            if workbench.metrics.isEmpty {
                ContentUnavailableView("暂无报告数字", systemImage: "chart.bar")
            } else {
                ForEach(workbench.metrics) { metric in
                    ReportsMetricRow(
                        id: metric.id,
                        title: metric.title,
                        value: metric.value,
                        suffix: metric.suffix,
                        systemImage: icon(for: metric.id)
                    )
                }
            }
        }
    }

    private var sectionsSection: some View {
        Section("报告草稿") {
            if workbench.sections.isEmpty {
                ContentUnavailableView("暂无报告草稿", systemImage: "lock")
            } else {
                ForEach(workbench.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: icon(for: section.kind))
                                .foregroundStyle(tint(for: section.status))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(section.title)
                                    .font(.subheadline.bold())
                                Text(section.kind.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(section.status.label)
                                .font(.caption2.bold())
                                .foregroundStyle(tint(for: section.status))
                        }
                        Text(section.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(section.progress), total: 100)
                    }
                    .padding(.vertical, 3)
                    .accessibilityIdentifier("reports-section-\(section.publicSectionRef)")
                }
            }
        }
    }

    @ViewBuilder
    private var findingsSection: some View {
        let visibleFindings = workbench.findings.filter { role == .guardian || $0.visibleToChild }
        if !visibleFindings.isEmpty {
            Section(role == .child ? "报告边界" : "复核提醒") {
                ForEach(visibleFindings) { finding in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title)
                                .font(.subheadline.bold())
                            Text(finding.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: finding.actionRequired ? "exclamationmark.shield" : "checkmark.shield")
                            .foregroundStyle(finding.actionRequired ? .orange : .green)
                    }
                    .accessibilityIdentifier("reports-finding-\(finding.id)")
                }
            }
        }
    }

    private var boundarySection: some View {
        Section("执行边界") {
            ReportsBoundaryFlag(id: "file-pdf-upload", title: "文件 / PDF / 上传", value: workbench.publicSummary.writesReportFile || workbench.publicSummary.exportsPdf || workbench.publicSummary.uploadsReport)
            ReportsBoundaryFlag(id: "network-ai", title: "网络 / AI", value: workbench.publicSummary.callsNetwork || workbench.publicSummary.callsAiProvider)
            ReportsBoundaryFlag(id: "notification", title: "通知", value: workbench.publicSummary.sendsNotification)
            ReportsBoundaryFlag(id: "ledger-credit-device", title: "账本 / 成长积分 / 设备", value: workbench.publicSummary.writesLedger || workbench.publicSummary.grantsCredit || workbench.publicSummary.unlocksDevice)
            ReportsBoundaryFlag(id: "health-screentime", title: "健康 / 屏幕时间读取", value: workbench.publicSummary.readsHealthKit || workbench.publicSummary.readsScreenTime)
        }
    }

    private func icon(for metricID: String) -> String {
        switch metricID {
        case "task-approved": return "checkmark.circle"
        case "homework-submitted": return "book.closed"
        case "honor-visible": return "star"
        case "ai-companion-interactions": return "bubble.left.and.bubble.right"
        case "wish-list-open": return "gift"
        case "credit-available": return "wallet.pass"
        case "ai-companion-guardian-actions": return "person.crop.circle.badge.exclamationmark"
        case "reward-guardian-actions": return "checklist.checked"
        case "review-pending": return "hourglass"
        default: return "number"
        }
    }

    private func icon(for kind: ReportsSectionKind) -> String {
        switch kind {
        case .tasks: return "checklist"
        case .school: return "graduationcap"
        case .growthPack: return "shippingbox"
        case .familyHonor: return "star.circle"
        case .creditReward: return "wallet.pass"
        case .aiCompanion: return "sparkles"
        case .wellbeing: return "heart"
        }
    }

    private func tint(for status: ReportsStatus) -> Color {
        switch status {
        case .ready: return .green
        case .inProgress: return .blue
        case .reviewRequired: return .orange
        case .blocked: return .red
        }
    }

    private static func normalizedRoles(_ roles: [ReportsViewerRole]) -> [ReportsViewerRole] {
        let source = roles.isEmpty ? ReportsViewerRole.allCases : roles
        return ReportsViewerRole.allCases.filter { source.contains($0) }
    }
}

private struct ReportsMetricRow: View {
    let id: String
    let title: String
    let value: Int
    let suffix: String
    let systemImage: String

    var body: some View {
        LabeledContent {
            Text("\(value)\(suffix)")
                .monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
        }
        .accessibilityIdentifier("reports-metric-\(id)")
    }
}

private struct ReportsBoundaryFlag: View {
    let id: String
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
        .accessibilityIdentifier("reports-boundary-\(id)")
    }
}
