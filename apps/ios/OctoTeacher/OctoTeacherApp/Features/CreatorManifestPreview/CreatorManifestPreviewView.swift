import SwiftUI

/// 创作者成长包 Manifest V1 本地预览 / 校验页。
///
/// 页面只消费本地 fixture snapshot，不上传、不发布、不收费、不调用 AI。
struct CreatorManifestPreviewView: View {
    @State private var viewerRole: CreatorManifestPreviewViewerRole = .guardian
    private let builder = CreatorManifestPreviewSnapshotBuilder()

    private var snapshot: CreatorManifestPreviewSnapshot {
        builder.build(viewerRole: viewerRole)
    }

    var body: some View {
        List {
            headerSection(snapshot)
            contentSection(snapshot)
            proofSection(snapshot)
            rewardSection(snapshot)
            licenseSection(snapshot)
            rubricAgeSection(snapshot)
            findingsSection(snapshot)
        }
        .navigationTitle("Manifest 预览")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func headerSection(_ snapshot: CreatorManifestPreviewSnapshot) -> some View {
        Section {
            Picker("视角", selection: $viewerRole) {
                ForEach(CreatorManifestPreviewViewerRole.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(snapshot.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text(snapshot.status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color(for: snapshot.status))
                }
                Text(snapshot.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(snapshot.manifestVersion) · 内容 \(snapshot.publicSummary.visibleContentCount) · 证明 \(snapshot.publicSummary.visibleProofCount)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("适龄", value: "\(snapshot.ageRating.minAge)-\(snapshot.ageRating.maxAge) 岁")
                LabeledContent("年级", value: snapshot.ageRating.gradeBand)
                LabeledContent("家长许可", value: snapshot.ageRating.requiresGuardianConsent ? "需要" : "未设置")
            }
        } footer: {
            Text("本页只展示本地 Manifest 草稿快照；成长积分、徽章和能力卡均为审核前建议。")
        }
    }

    private func contentSection(_ snapshot: CreatorManifestPreviewSnapshot) -> some View {
        Section("内容块") {
            if snapshot.contentBlocks.isEmpty {
                Text("该视角暂无可见内容块")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.contentBlocks) { block in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: block.kind.systemImage)
                            .foregroundStyle(color(for: block.status))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(block.title)
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Text(block.kind.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(block.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("证明 \(block.requiredProofCount) · \(block.status.label)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func proofSection(_ snapshot: CreatorManifestPreviewSnapshot) -> some View {
        Section("证明要求") {
            if snapshot.proofRequirements.isEmpty {
                Text(snapshot.visibility.canSeeProofRequirements ? "暂无证明要求" : "该视角不可查看证明要求")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.proofRequirements) { proof in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(proof.kind.label)
                            .font(.subheadline.weight(.semibold))
                        Text("验证角色：\(proof.verifierRoles.map(\.label).joined(separator: " / "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(proof.instructions)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func rewardSection(_ snapshot: CreatorManifestPreviewSnapshot) -> some View {
        Section("成长积分、徽章与能力草稿") {
            if snapshot.creditDrafts.isEmpty && snapshot.badgeAbilityDrafts.isEmpty {
                Text("该视角不显示成人审核前奖励草稿")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.creditDrafts) { credit in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(credit.amountLabel) · \(credit.scopeLabel)")
                            .font(.subheadline.weight(.semibold))
                        Text(credit.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                ForEach(snapshot.badgeAbilityDrafts) { draft in
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(draft.kind.label) · \(draft.title)")
                                .font(.subheadline.weight(.semibold))
                            Text("\(draft.category) · \(draft.requiresHumanReview ? "人工审核" : "未设置审核")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: draft.kind == .badge ? "rosette" : "rectangle.stack.badge.person.crop")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func licenseSection(_ snapshot: CreatorManifestPreviewSnapshot) -> some View {
        Section("许可边界") {
            if let license = snapshot.licenseBoundary {
                LabeledContent("外部视频", value: license.allowsExternalVideo ? "允许" : "阻断")
                LabeledContent("创作上传", value: license.allowsCreatorUpload ? "允许" : "阻断")
                LabeledContent("学校挂钩", value: license.allowsSchoolHook ? "允许" : "阻断")
                LabeledContent("市场发布", value: license.marketPublishReady ? "就绪" : "待审核")
            } else {
                Text("该视角不显示许可和市场边界")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rubricAgeSection(_ snapshot: CreatorManifestPreviewSnapshot) -> some View {
        Section("量规与适龄") {
            NavigationLink {
                MobileCreatorSkillPackRubricAgeSuitabilityWorkbenchView(
                    initialRole: rubricRole,
                    allowedRoles: [rubricRole]
                )
            } label: {
                Label("量规年龄适配安全壳", systemImage: "checklist")
            }
            .accessibilityIdentifier("creator-manifest-rubric-age-link")
            Text(snapshot.viewerRole == .child ? "孩子只看适龄目标和证明下一步。" : "只读检查学习目标、证明闭环、徽章/能力卡与成长积分建议边界。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func findingsSection(_ snapshot: CreatorManifestPreviewSnapshot) -> some View {
        Section("校验发现") {
            ForEach(snapshot.findings) { finding in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon(for: finding.severity))
                        .foregroundStyle(color(for: finding.severity))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(finding.code.rawValue)
                            .font(.caption.monospaced().weight(.semibold))
                        Text(finding.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func color(for status: CreatorManifestPreviewStatus) -> Color {
        switch status {
        case .readyForReview: return .green
        case .needsWork: return .orange
        case .blocked: return .red
        case .hidden: return .secondary
        }
    }

    private func color(for status: CreatorManifestDraftBlockStatus) -> Color {
        switch status {
        case .complete: return .green
        case .draft: return .orange
        case .missing: return .red
        }
    }

    private func color(for severity: CreatorManifestPreviewSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }

    private func icon(for severity: CreatorManifestPreviewSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.seal"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private var rubricRole: MobileCreatorSkillPackRubricViewerRole {
        switch viewerRole {
        case .child:
            return .child
        case .creator:
            return .creator
        case .guardian, .relative, .teacher:
            return .guardian
        }
    }
}
