import SwiftUI

struct FamilySchoolNotificationDigestCenterView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily

    @State private var viewerRole: MobileFamilySchoolNotificationDigestViewerRole
    private let allowedRoles: [MobileFamilySchoolNotificationDigestViewerRole]
    private let builder = MobileFamilySchoolNotificationDigestCenterBuilder()

    init(
        initialRole: MobileFamilySchoolNotificationDigestViewerRole = .guardian,
        allowedRoles: [MobileFamilySchoolNotificationDigestViewerRole] = MobileFamilySchoolNotificationDigestViewerRole.allCases
    ) {
        let normalized = allowedRoles.isEmpty ? MobileFamilySchoolNotificationDigestViewerRole.allCases : allowedRoles
        self.allowedRoles = normalized
        _viewerRole = State(initialValue: normalized.contains(initialRole) ? initialRole : normalized[0])
    }

    private var snapshot: MobileFamilySchoolNotificationDigestSnapshot {
        builder.build(viewerRole: viewerRole, family: family, schoolFamily: schoolFamily)
    }

    var body: some View {
        List {
            roleSection
            headerSection(snapshot)
            boundarySection(snapshot)
            cardsSection(snapshot)
            findingsSection(snapshot)
            guardrailSection(snapshot)
        }
        .navigationTitle("通知摘要同意")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var roleSection: some View {
        if allowedRoles.count > 1 {
            Section {
                Picker("视角", selection: $viewerRole) {
                    ForEach(allowedRoles, id: \.self) { role in
                        Text(role.label).tag(role)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("这里只读展示摘要边界，不发送通知、不写队列、不调用学校或 AI。")
            }
        } else {
            Section {
                LabeledContent("视角", value: viewerRole.label)
            }
        }
    }

    private func headerSection(_ snapshot: MobileFamilySchoolNotificationDigestSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(snapshot.status.label, systemImage: icon(for: snapshot.status))
                        .font(.headline)
                        .foregroundStyle(tint(for: snapshot.status))
                    Spacer()
                    Text("\(snapshot.publicSummary.visibleCardCount) 条")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(snapshot.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("抑制 \(snapshot.publicSummary.suppressedCardCount) · 复核 \(snapshot.publicSummary.reviewCardCount)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityIdentifier("notification-digest-header")
        }
    }

    private func boundarySection(_ snapshot: MobileFamilySchoolNotificationDigestSnapshot) -> some View {
        Section("同意与送达边界") {
            NotificationDigestBoundaryFlagRow(title: "家长同意", value: snapshot.boundary.guardianConsentGranted, positiveIsGood: true)
            NotificationDigestBoundaryFlagRow(title: "孩子 assent", value: snapshot.boundary.childAssentActive, positiveIsGood: true)
            NotificationDigestBoundaryFlagRow(title: "孩子撤回", value: snapshot.boundary.childWithdrawn, positiveIsGood: false)
            NotificationDigestBoundaryFlagRow(title: "亲友许可", value: snapshot.boundary.relativeConsentGranted, positiveIsGood: true)
            NotificationDigestBoundaryFlagRow(title: "老师名册有效", value: snapshot.boundary.teacherRosterActive, positiveIsGood: true)
            NotificationDigestBoundaryFlagRow(title: "安静窗口紧急覆盖", value: snapshot.boundary.urgentQuietOverrideAllowed, positiveIsGood: true)
            LabeledContent("发送通知", value: snapshot.boundary.sendsNotification ? "会" : "不会")
            LabeledContent("写队列", value: snapshot.boundary.writesQueue ? "会" : "不会")
        }
    }

    private func cardsSection(_ snapshot: MobileFamilySchoolNotificationDigestSnapshot) -> some View {
        Section("摘要卡片") {
            if snapshot.cards.isEmpty {
                Label("暂无可见摘要", systemImage: "bell.slash")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.cards) { card in
                    if card.kind == .guardianRewardPending, viewerRole == .guardian {
                        NavigationLink {
                            ParentPocketMoneyWorkbenchView()
                        } label: {
                            cardLabel(card)
                        }
                        .accessibilityIdentifier("notification-digest-card-\(card.kind.rawValue)")
                    } else {
                        cardLabel(card)
                            .accessibilityIdentifier("notification-digest-card-\(card.kind.rawValue)")
                    }
                }
            }
        }
    }

    private func cardLabel(_ card: MobileFamilySchoolNotificationDigestCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(card.title, systemImage: icon(for: card.kind))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(card.state.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint(for: card.state))
            }
            Text(card.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func findingsSection(_ snapshot: MobileFamilySchoolNotificationDigestSnapshot) -> some View {
        Section("发现") {
            ForEach(snapshot.findings) { finding in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.code.label)
                            .font(.caption.bold())
                        Text(finding.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: icon(for: finding.severity))
                        .foregroundStyle(tint(for: finding.severity))
                }
                .accessibilityIdentifier("notification-digest-finding-\(finding.code.rawValue)")
            }
        }
    }

    private func guardrailSection(_ snapshot: MobileFamilySchoolNotificationDigestSnapshot) -> some View {
        Section("只读护栏") {
            LabeledContent("调用网络/AI", value: (snapshot.publicSummary.callsNetwork || snapshot.publicSummary.callsAiProvider || snapshot.publicSummary.callsLocalModel) ? "会" : "不会")
            LabeledContent("学校/LMS", value: (snapshot.publicSummary.writesSchoolSystem || snapshot.publicSummary.callsLms) ? "会" : "不会")
            LabeledContent("通知/队列", value: (snapshot.publicSummary.sendsNotification || snapshot.publicSummary.writesQueue) ? "会" : "不会")
            LabeledContent("账本/成长积分/设备", value: (snapshot.publicSummary.writesLedger || snapshot.publicSummary.grantsCredit || snapshot.publicSummary.unlocksDevice) ? "会" : "不会")
            LabeledContent("保存原始对话", value: snapshot.publicSummary.storesRawTranscript ? "会" : "不会")
        }
    }

    private func icon(for status: MobileFamilySchoolNotificationDigestStatus) -> String {
        switch status {
        case .ready: return "checkmark.circle"
        case .reviewRequired: return "exclamationmark.triangle"
        case .blocked: return "xmark.octagon"
        case .empty: return "tray"
        }
    }

    private func icon(for kind: MobileFamilySchoolNotificationDigestCardKind) -> String {
        switch kind {
        case .guardianReview: return "person.badge.shield.checkmark"
        case .guardianRewardPending: return "gift"
        case .childHomework: return "book"
        case .teacherSchool: return "studentdesk"
        case .relativeFamily: return "person.2"
        case .quietWindow: return "moon"
        case .eventEvidence: return "link.badge.plus"
        }
    }

    private func icon(for severity: MobileFamilySchoolNotificationDigestSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func tint(for status: MobileFamilySchoolNotificationDigestStatus) -> Color {
        switch status {
        case .ready: return .green
        case .reviewRequired: return .orange
        case .blocked: return .red
        case .empty: return .secondary
        }
    }

    private func tint(for state: MobileFamilySchoolNotificationDigestCardState) -> Color {
        switch state {
        case .deliverable: return .green
        case .needsReview: return .orange
        case .suppressed: return .red
        }
    }

    private func tint(for severity: MobileFamilySchoolNotificationDigestSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .blue
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}

private struct NotificationDigestBoundaryFlagRow: View {
    let title: String
    let value: Bool
    let positiveIsGood: Bool

    private var isGood: Bool {
        positiveIsGood ? value : !value
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Label(value ? "是" : "否", systemImage: isGood ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(isGood ? .green : .orange)
                .font(.caption.weight(.semibold))
        }
        .accessibilityIdentifier("notification-digest-boundary-\(title)")
    }
}
