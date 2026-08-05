import SwiftUI

/// iOS 孩子创作作品展示安全壳页面。
///
/// 只消费本地 mock 投影，不打开相机/相册/文件选择器，不上传媒体，不发布作品，
/// 不通知亲友，不处理评论，不写账本、不发成长积分、不解锁设备。
struct MobileCreativeShowcaseSafetyWorkbenchView: View {
    @State private var role: MobileCreativeShowcaseViewerRole
    private let allowedRoles: [MobileCreativeShowcaseViewerRole]
    private let draft: CreatorManifestPreviewDraft

    init(
        initialRole: MobileCreativeShowcaseViewerRole = .child,
        allowedRoles: [MobileCreativeShowcaseViewerRole] = MobileCreativeShowcaseViewerRole.allCases,
        draft: CreatorManifestPreviewDraft = .growthPackContentPlayerMock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.draft = draft
    }

    private var workbench: MobileCreativeShowcaseSafetyWorkbench {
        MobileCreativeShowcaseSafetyBuilder().build(role: role, draft: draft)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            showcaseSection
            proofSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("创作展示")
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
            CreativeShowcaseMetric(title: "作品", value: workbench.publicSummary.visibleShowcaseCount, systemImage: "paintpalette")
            CreativeShowcaseMetric(title: "证明", value: workbench.publicSummary.proofRequirementCount, systemImage: "checkmark.shield")
            if role == .guardian {
                CreativeShowcaseMetric(title: "待审核", value: workbench.publicSummary.pendingReviewCount, systemImage: "person.badge.shield.checkmark")
                CreativeShowcaseMetric(title: "亲友隐藏", value: workbench.publicSummary.hiddenFromRelativeCount, systemImage: "eye.slash")
                CreativeShowcaseMetric(title: "已阻断", value: workbench.publicSummary.blockedCount, systemImage: "lock.shield")
                CreativeShowcaseMetric(title: "成长积分阻断", value: workbench.publicSummary.directCreditBlockedCount, systemImage: "creditcard.trianglebadge.exclamationmark")
            }
            NavigationLink {
                MobileRelativeCreativeCommentSafetyWorkbenchView(
                    initialRole: relativeCommentRole,
                    allowedRoles: [relativeCommentRole]
                )
            } label: {
                Label("亲友鼓励边界", systemImage: "bubble.left.and.bubble.right")
            }
            .accessibilityIdentifier("creative-showcase-link-relative-comment-safety")
        }
    }

    private var showcaseSection: some View {
        Section("作品展示") {
            if workbench.showcases.isEmpty {
                ContentUnavailableView("暂无可见作品", systemImage: "lock")
            } else {
                ForEach(workbench.showcases) { showcase in
                    CreativeShowcaseRow(showcase: showcase)
                }
            }
        }
    }

    private var proofSection: some View {
        Section("证明边界") {
            if workbench.proofs.isEmpty {
                Text("暂无作品证明要求")
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
        Section(role == .relative ? "亲友可见边界" : "安全提示") {
            if workbench.findings.isEmpty {
                Text(role == .relative ? "当前没有可公开提示" : "暂无风险提示")
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
            CreativeShowcaseBoundaryFlag(title: "相机/相册/文件", value: workbench.publicSummary.opensCamera || workbench.publicSummary.opensPhotoLibrary || workbench.publicSummary.opensFilePicker)
            CreativeShowcaseBoundaryFlag(title: "上传/发布作品", value: workbench.publicSummary.uploadsMedia || workbench.publicSummary.publishesShowcase)
            CreativeShowcaseBoundaryFlag(title: "评论/通知亲友", value: workbench.publicSummary.approvesComment || workbench.publicSummary.sendsComment || workbench.publicSummary.sendsNotification)
            CreativeShowcaseBoundaryFlag(title: "网络/社交平台", value: workbench.publicSummary.callsNetwork || workbench.publicSummary.writesSocialPlatform)
            CreativeShowcaseBoundaryFlag(title: "账本/成长积分/设备", value: workbench.publicSummary.writesLedger || workbench.publicSummary.grantsCredit || workbench.publicSummary.unlocksDevice)
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileCreativeShowcaseViewerRole]
    ) -> [MobileCreativeShowcaseViewerRole] {
        let source = roles.isEmpty ? MobileCreativeShowcaseViewerRole.allCases : roles
        return MobileCreativeShowcaseViewerRole.allCases.filter { source.contains($0) }
    }

    private var relativeCommentRole: MobileRelativeCreativeCommentViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        }
    }
}

private struct CreativeShowcaseRow: View {
    let showcase: MobileCreativeShowcaseItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "paintpalette")
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(showcase.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(showcase.state.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }

            Text(showcase.creativePrompt)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Label(showcase.audienceLabel, systemImage: "person.2")
                Label(showcase.consentLabel, systemImage: "hand.raised")
                Label(showcase.moderationLabel, systemImage: "checkmark.shield")
                Label(showcase.proofLabel, systemImage: "doc.badge.clock")
                Label(showcase.creditBoundaryLabel, systemImage: "creditcard")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Label(showcase.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(showcase.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("creative-showcase-item-\(showcase.state.rawValue)")
    }

    private var tint: Color {
        switch showcase.state {
        case .approvedPreview: return .blue
        case .waitingGuardianReview: return .orange
        case .hiddenFromRelative: return .secondary
        case .blocked: return .red
        }
    }
}

private struct CreativeShowcaseMetric: View {
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

private struct CreativeShowcaseBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
    }
}
