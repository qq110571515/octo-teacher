import SwiftUI

/// iOS 外部学习资源安全壳页面。
///
/// 只消费本地 mock 投影，不打开外链、WebView、浏览器、视频平台或媒体权限。
struct MobileExternalLearningResourceSafetyWorkbenchView: View {
    @State private var role: MobileExternalLearningResourceViewerRole
    private let allowedRoles: [MobileExternalLearningResourceViewerRole]
    private let draft: CreatorManifestPreviewDraft

    init(
        initialRole: MobileExternalLearningResourceViewerRole = .child,
        allowedRoles: [MobileExternalLearningResourceViewerRole] = MobileExternalLearningResourceViewerRole.allCases,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.draft = draft
    }

    private var workbench: MobileExternalLearningResourceSafetyWorkbench {
        MobileExternalLearningResourceSafetyBuilder().build(role: role, draft: draft)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            resourceSection
            proofSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("外部资源")
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
            ExternalResourceMetric(title: "资源", value: workbench.publicSummary.visibleResourceCount, systemImage: "play.rectangle")
            ExternalResourceMetric(title: "证明", value: workbench.publicSummary.proofRequirementCount, systemImage: "checkmark.shield")
            if role == .guardian {
                ExternalResourceMetric(title: "需复核", value: workbench.publicSummary.guardianReviewCount, systemImage: "person.badge.shield.checkmark")
                ExternalResourceMetric(title: "已阻断", value: workbench.publicSummary.blockedResourceCount, systemImage: "lock.shield")
                ExternalResourceMetric(title: "成长积分阻断", value: workbench.publicSummary.directCreditBlockedCount, systemImage: "creditcard.trianglebadge.exclamationmark")
            }
        }
    }

    private var resourceSection: some View {
        Section("学习资源") {
            if workbench.resources.isEmpty {
                ContentUnavailableView("暂无可见外部资源", systemImage: "lock")
            } else {
                ForEach(workbench.resources) { resource in
                    ExternalResourceRow(resource: resource)
                }
            }
        }
    }

    private var proofSection: some View {
        Section("证明边界") {
            if workbench.proofs.isEmpty {
                Text("暂无外部资源证明要求")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workbench.proofs) { proof in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(proof.title, systemImage: "checkmark.shield")
                            .font(.subheadline.bold())
                        Text(proof.instructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("验证角色：\(proof.verifierLabels.joined(separator: " / "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var findingSection: some View {
        Section(role == .child ? "学习提示" : "家长边界") {
            if workbench.findings.isEmpty {
                Text(role == .child ? "当前没有需要展示的风险" : "暂无风险提示")
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
            ExternalResourceBoundaryFlag(title: "URL/域名", value: workbench.publicSummary.showsRawURL || workbench.publicSummary.showsDomain)
            ExternalResourceBoundaryFlag(title: "外链/WebView/浏览器", value: workbench.publicSummary.opensExternalURL || workbench.publicSummary.opensWebView || workbench.publicSummary.opensBrowser)
            ExternalResourceBoundaryFlag(title: "下载/网络/AI", value: workbench.publicSummary.downloadsMedia || workbench.publicSummary.callsNetwork || workbench.publicSummary.callsAIProvider)
            ExternalResourceBoundaryFlag(title: "上传证明", value: workbench.publicSummary.uploadsProof)
            ExternalResourceBoundaryFlag(title: "账本/成长积分/设备", value: workbench.publicSummary.writesLedger || workbench.publicSummary.grantsCredit || workbench.publicSummary.unlocksDevice)
            ExternalResourceBoundaryFlag(title: "市场写入", value: workbench.publicSummary.writesMarketplace)
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileExternalLearningResourceViewerRole]
    ) -> [MobileExternalLearningResourceViewerRole] {
        let source = roles.isEmpty ? MobileExternalLearningResourceViewerRole.allCases : roles
        return MobileExternalLearningResourceViewerRole.allCases.filter { source.contains($0) }
    }
}

private struct ExternalResourceRow: View {
    let resource: MobileExternalLearningResourceRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "play.rectangle")
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(resource.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(resource.state.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }

            Label(resource.sourceLabel, systemImage: "shield.lefthalf.filled")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(resource.resourceKindLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Label(resource.ageLabel, systemImage: "person.crop.circle.badge.checkmark")
                Label(resource.licenseLabel, systemImage: "doc.text.magnifyingglass")
                Label(resource.proofLabel, systemImage: "checkmark.shield")
                Label(resource.creditBoundaryLabel, systemImage: "creditcard")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Label(resource.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(resource.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var tint: Color {
        switch resource.state {
        case .ready: return .blue
        case .guardianReview: return .orange
        case .blocked: return .red
        case .hiddenFromChild: return .secondary
        }
    }
}

private struct ExternalResourceMetric: View {
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

private struct ExternalResourceBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
    }
}
