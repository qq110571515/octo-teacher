import SwiftUI

/// 家庭荣誉墙与成长故事线同意入口。
///
/// 展示三层可见性与同意状态，不执行发布、通知、上传、发成长积分或解锁设备。
struct FamilyHonorStorylineConsentView: View {
    private let store: FamilyGrowthAchievementStore
    @State private var role: FamilyHonorStorylineConsentViewerRole
    private let allowsRoleSwitching: Bool

    init(
        store: FamilyGrowthAchievementStore,
        initialRole: FamilyHonorStorylineConsentViewerRole = .guardian,
        allowsRoleSwitching: Bool = true
    ) {
        self.store = store
        _role = State(initialValue: initialRole)
        self.allowsRoleSwitching = allowsRoleSwitching
    }

    private var snapshot: FamilyHonorStorylineConsentSnapshot {
        FamilyHonorStorylineConsentBuilder(store: store).snapshot(for: role)
    }

    var body: some View {
        List {
            roleSection
            policyLinkSection
            releaseGateSection
            overviewSection
            layerSections
            findingSection
            sideEffectSection
        }
        .navigationTitle("荣誉同意")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var roleSection: some View {
        Section {
            if allowsRoleSwitching {
                Picker("视角", selection: $role) {
                    ForEach(FamilyHonorStorylineConsentViewerRole.allCases, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(snapshot.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var policyLinkSection: some View {
        Section {
            NavigationLink {
                GuardianChildConsentPolicyView(
                    initialRole: GuardianChildConsentPolicyViewerRole(honorRole: role),
                    allowsRoleSwitching: allowsRoleSwitching
                )
            } label: {
                Label("查看统一同意策略", systemImage: "person.badge.shield.checkmark")
            }
            .accessibilityIdentifier("family-storyline-consent-policy-link")
        }
    }

    private var overviewSection: some View {
        Section(snapshot.headline) {
            LabeledContent("可见节点") {
                Text("\(snapshot.publicSummary.visibleNodeCount)").monospacedDigit()
            }
            LabeledContent("被隐藏节点") {
                Text("\(snapshot.hiddenNodeCount)").monospacedDigit()
            }
            LabeledContent("家庭引用") {
                Text(snapshot.familyPublicRef)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            LabeledContent("孩子引用") {
                Text(snapshot.childPublicRef)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var releaseGateSection: some View {
        Section("故事线发布门禁") {
            Label(snapshot.releaseGate.title, systemImage: releaseGateSystemImage(snapshot.releaseGate.status))
                .font(.subheadline.bold())
                .foregroundStyle(releaseGateTint(snapshot.releaseGate.status))
                .accessibilityIdentifier("family-storyline-release-gate-\(snapshot.releaseGate.status.rawValue)")

            Text(role == .child ? snapshot.releaseGate.childCopy : snapshot.releaseGate.guardianSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LabeledContent("主原因") {
                Text(snapshot.releaseGate.primaryReason.label)
            }
            LabeledContent("候选预览") {
                Text("\(snapshot.releaseGate.publishCandidateCount)").monospacedDigit()
            }
            LabeledContent("待处理/阻断") {
                Text("\(snapshot.releaseGate.manualGateCount)/\(snapshot.releaseGate.blockedCount)")
                    .monospacedDigit()
            }

            Label(snapshot.releaseGate.nextAction, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(snapshot.releaseGate.evidenceChecklist) { evidence in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: releaseGateSystemImage(evidence.status))
                        .foregroundStyle(releaseGateTint(evidence.status))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(evidence.title)
                            .font(.caption.bold())
                        Text(evidence.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("family-storyline-release-evidence-\(evidence.status.rawValue)")
            }
        }
    }

    private var layerSections: some View {
        ForEach(FamilyHonorStorylineLayer.allCases, id: \.self) { layer in
            let nodes = snapshot.nodes(in: layer)
            Section {
                if nodes.isEmpty {
                    Text(emptyText(for: layer))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(nodes) { node in
                        FamilyHonorStorylineConsentNodeRow(node: node)
                    }
                }
            } header: {
                Label(layer.label, systemImage: layer.systemImage)
            }
        }
    }

    private var findingSection: some View {
        Section("安全检查") {
            ForEach(snapshot.findings) { finding in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: finding.actionRequired ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(finding.actionRequired ? .orange : .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title).font(.subheadline.bold())
                        Text("数量 \(finding.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("family-storyline-consent-finding-\(finding.code.rawValue)")
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            BoundaryFlag(id: "publish-honor-wall", title: "发布荣誉墙", value: snapshot.publicSummary.publishesHonorWall)
            BoundaryFlag(id: "mutate-storyline", title: "改写故事线", value: snapshot.publicSummary.mutatesStoryline)
            BoundaryFlag(id: "credit-badge", title: "发成长积分/授徽章", value: snapshot.publicSummary.writesLedger || snapshot.publicSummary.grantsBadge)
            BoundaryFlag(id: "media-notification", title: "上传媒体/通知", value: snapshot.publicSummary.uploadsMedia || snapshot.publicSummary.sendsNotification)
            BoundaryFlag(id: "network-ai", title: "调用网络/AI", value: snapshot.publicSummary.callsNetwork || snapshot.publicSummary.callsAIProvider)
            BoundaryFlag(id: "unlock-device", title: "解锁设备", value: snapshot.publicSummary.unlocksDevice)
            BoundaryFlag(id: "release-write", title: "发布门禁写入", value: snapshot.releaseGate.writesStoryline || snapshot.releaseGate.publishesHonorWall)
            BoundaryFlag(id: "release-notify-reward", title: "发布门禁通知/奖励", value: snapshot.releaseGate.notifiesRelatives || snapshot.releaseGate.grantsCredit || snapshot.releaseGate.awardsBadges)
        }
    }

    private func releaseGateSystemImage(_ status: FamilyStorylineReleaseGateStatus) -> String {
        switch status {
        case .ready: return "checkmark.seal"
        case .manualGate: return "person.crop.circle.badge.questionmark"
        case .blocked: return "exclamationmark.shield"
        }
    }

    private func releaseGateTint(_ status: FamilyStorylineReleaseGateStatus) -> Color {
        switch status {
        case .ready: return .green
        case .manualGate: return .orange
        case .blocked: return .red
        }
    }

    private func emptyText(for layer: FamilyHonorStorylineLayer) -> String {
        switch (role, layer) {
        case (.relative, .privateFamily):
            return "亲友视角不显示家庭私密内容"
        case (.publicViewer, .privateFamily), (.publicViewer, .relativeVisible):
            return "公开访客不可见这一层"
        default:
            return "暂无可见节点"
        }
    }
}

private extension GuardianChildConsentPolicyViewerRole {
    init(honorRole: FamilyHonorStorylineConsentViewerRole) {
        switch honorRole {
        case .child:
            self = .child
        case .guardian:
            self = .guardian
        case .relative:
            self = .relative
        case .publicViewer:
            self = .publicViewer
        }
    }
}

private struct FamilyHonorStorylineConsentNodeRow: View {
    let node: FamilyHonorStorylineConsentNode

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: node.kind.systemImage)
                    .foregroundStyle(.orange)
                Text(node.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(node.occurredLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                FamilyHonorStorylineLayerBadge(layer: node.layer)
                ConsentStateBadge(state: node.consentState)
            }

            Text(node.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label(node.supportiveCopy, systemImage: "heart")
                .font(.caption)
                .foregroundStyle(.pink)

            Label(node.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

            if node.showsWithdrawalReason {
                Label("家长可见撤回/阻断原因入口，暂不展示给亲友或公开访客。", systemImage: node.consentState.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if node.showsConsentControls {
                Label("同意控制为本地只读入口，真正审批由后续策略服务承接。", systemImage: "slider.horizontal.3")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            if !node.tags.isEmpty {
                Text(node.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Label("\(node.reactionCount)", systemImage: "hands.clap")
                Label("\(node.approvedCommentCount)", systemImage: "text.bubble")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("family-storyline-consent-node-\(node.layer.rawValue)-\(node.consentState.rawValue)")
    }
}

private struct FamilyHonorStorylineLayerBadge: View {
    let layer: FamilyHonorStorylineLayer

    var body: some View {
        Label(layer.label, systemImage: layer.systemImage)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.thinMaterial, in: Capsule())
    }
}

private struct ConsentStateBadge: View {
    let state: FamilyHonorStorylineConsentState

    private var tint: Color {
        switch state {
        case .ready: return .green
        case .needsGuardianConsent, .frozen: return .orange
        case .withdrawn: return .gray
        case .blocked: return .red
        }
    }

    var body: some View {
        Label(state.label, systemImage: state.systemImage)
            .font(.caption2.bold())
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(tint.opacity(0.4)))
    }
}

private struct BoundaryFlag: View {
    let id: String
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Label(value ? "会执行" : "不执行", systemImage: value ? "xmark.octagon" : "checkmark.shield")
                .font(.caption.bold())
                .foregroundStyle(value ? .red : .green)
        }
        .accessibilityIdentifier("family-storyline-boundary-\(id)")
    }
}
