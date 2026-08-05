import SwiftUI

/// 成长包内容播放器 / 证明工作台。
///
/// 该页面只消费本地 mock 快照，不打开外链、WebView、媒体权限或上传入口。
struct GrowthPackContentPlayerWorkbenchView: View {
    @State private var role: GrowthPackContentPlayerViewerRole
    private let allowedRoles: [GrowthPackContentPlayerViewerRole]
    private let draft: CreatorManifestPreviewDraft

    init(
        initialRole: GrowthPackContentPlayerViewerRole = .child,
        allowedRoles: [GrowthPackContentPlayerViewerRole] = GrowthPackContentPlayerViewerRole.allCases,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.draft = draft
    }

    private var workbench: GrowthPackContentPlayerWorkbench {
        GrowthPackContentPlayerWorkbenchBuilder().build(role: role, draft: draft)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            contentSection
            proofSection
            riskSection
            sideEffectSection
        }
        .navigationTitle("内容播放器")
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
            PlayerMetric(title: "内容块", value: workbench.publicSummary.visibleItemCount, systemImage: "square.grid.2x2")
            PlayerMetric(title: "证明要求", value: workbench.publicSummary.proofRequirementCount, systemImage: "checkmark.shield")
            PlayerMetric(title: "视频引用", value: workbench.publicSummary.externalVideoCount, systemImage: "play.rectangle")
            PlayerMetric(title: "截图证明", value: workbench.publicSummary.screenshotProofCount, systemImage: "gamecontroller")
            if role == .guardian {
                PlayerMetric(title: "需家长复核", value: workbench.publicSummary.guardianReviewCount, systemImage: "person.badge.shield.checkmark")
                PlayerMetric(title: "孩子隐藏", value: workbench.publicSummary.hiddenItemCount, systemImage: "lock")
            }
        }
    }

    private var contentSection: some View {
        Section("学习内容") {
            if workbench.items.isEmpty {
                ContentUnavailableView("暂无可见内容", systemImage: "lock")
            } else {
                ForEach(workbench.items) { item in
                    contentRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private func contentRow(_ item: GrowthPackContentPlayerItem) -> some View {
        if item.mode == .quizPractice {
            NavigationLink {
                MobileQuizSelfCheckPracticeWorkbenchView(
                    initialRole: role == .guardian ? .guardian : .child,
                    allowedRoles: [role == .guardian ? .guardian : .child]
                )
            } label: {
                GrowthPackContentPlayerItemRow(item: item)
            }
            .accessibilityIdentifier("content-player-item-\(item.mode.rawValue)")
        } else if item.mode == .schoolHook {
            NavigationLink {
                MobileSchoolHomeworkGrowthPackLinkageWorkbenchView(
                    initialRole: role == .guardian ? .guardian : .child,
                    allowedRoles: [role == .guardian ? .guardian : .child]
                )
            } label: {
                GrowthPackContentPlayerItemRow(item: item)
            }
            .accessibilityIdentifier("content-player-item-\(item.mode.rawValue)")
        } else if item.mode == .externalVideoReference {
            NavigationLink {
                MobileExternalLearningResourceSafetyWorkbenchView(
                    initialRole: role == .guardian ? MobileExternalLearningResourceViewerRole.guardian : .child,
                    allowedRoles: [role == .guardian ? MobileExternalLearningResourceViewerRole.guardian : .child],
                    draft: draft
                )
            } label: {
                GrowthPackContentPlayerItemRow(item: item)
            }
            .accessibilityIdentifier("content-player-item-\(item.mode.rawValue)")
        } else if item.mode == .uploadPlaceholder {
            NavigationLink {
                MobileCreativeShowcaseSafetyWorkbenchView(
                    initialRole: role == .guardian ? MobileCreativeShowcaseViewerRole.guardian : .child,
                    allowedRoles: [role == .guardian ? MobileCreativeShowcaseViewerRole.guardian : .child],
                    draft: draft
                )
            } label: {
                GrowthPackContentPlayerItemRow(item: item)
            }
            .accessibilityIdentifier("content-player-item-\(item.mode.rawValue)")
        } else {
            GrowthPackContentPlayerItemRow(item: item)
        }
    }

    private var proofSection: some View {
        Section("证明要求") {
            if workbench.proofs.isEmpty {
                Text(role == .child ? "当前没有需要你查看的证明要求" : "暂无证明要求")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workbench.proofs) { proof in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(proof.kind.label, systemImage: "checkmark.shield")
                            .font(.subheadline.bold())
                        Text(proof.instructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("验证角色：\(proof.verifierLabels.joined(separator: " / "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(proof.evidenceRefsOnly ? "只保存脱敏证明引用" : "需要修正证明规则")
                            .font(.caption2)
                            .foregroundStyle(proof.evidenceRefsOnly ? .green : .red)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var riskSection: some View {
        Section("家长边界") {
            if workbench.risks.isEmpty {
                Text(role == .child ? "孩子视角不展示家长审核风险" : "暂无风险提示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workbench.risks) { risk in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(risk.title)
                                .font(.subheadline.bold())
                            Text(risk.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: risk.actionRequired ? "exclamationmark.shield" : "checkmark.shield")
                            .foregroundStyle(risk.actionRequired ? .orange : .green)
                    }
                }
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            PlayerBoundaryFlag(title: "外链/WebView", value: workbench.publicSummary.opensExternalURL || workbench.publicSummary.opensWebView)
            PlayerBoundaryFlag(title: "下载媒体", value: workbench.publicSummary.downloadsMedia)
            PlayerBoundaryFlag(title: "相机/相册/文件", value: workbench.publicSummary.opensCamera || workbench.publicSummary.opensPhotoLibrary || workbench.publicSummary.opensFilePicker)
            PlayerBoundaryFlag(title: "上传/证明", value: workbench.publicSummary.uploadsMedia || workbench.publicSummary.uploadsProof)
            PlayerBoundaryFlag(title: "测验自动判分", value: workbench.publicSummary.autoGradesQuiz)
            PlayerBoundaryFlag(title: "网络/AI", value: workbench.publicSummary.callsNetwork || workbench.publicSummary.callsAIProvider)
            PlayerBoundaryFlag(title: "成长积分/设备/学校", value: workbench.publicSummary.writesLedger || workbench.publicSummary.grantsCredit || workbench.publicSummary.unlocksDevice || workbench.publicSummary.writesSchoolSystem)
        }
    }

    private static func normalizedRoles(
        _ roles: [GrowthPackContentPlayerViewerRole]
    ) -> [GrowthPackContentPlayerViewerRole] {
        let source = roles.isEmpty ? GrowthPackContentPlayerViewerRole.allCases : roles
        return GrowthPackContentPlayerViewerRole.allCases.filter { source.contains($0) }
    }
}

private struct GrowthPackContentPlayerItemRow: View {
    let item: GrowthPackContentPlayerItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: item.mode.systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(item.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(item.state.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }

            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Label(item.mode.label, systemImage: item.mode.systemImage)
                Label("\(item.proofCount)", systemImage: "checkmark.shield")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Label(item.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(item.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            if item.guardianReviewRequired {
                Label("这里只提示需要家长复核，不执行批准或驳回。", systemImage: "person.badge.shield.checkmark")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }

    private var tint: Color {
        switch item.state {
        case .ready, .practiceOnly: return .blue
        case .proofRequired: return .orange
        case .guardianReview: return .purple
        case .hiddenFromChild: return .secondary
        case .blocked: return .red
        }
    }
}

private struct PlayerMetric: View {
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

private struct PlayerBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
    }
}
