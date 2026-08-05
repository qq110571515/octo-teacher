import SwiftUI

/// 章鱼老师 / Octo Teacher 本地入门页。
///
/// 不登录、不联网、不申请权限；只帮助孩子/家长理解首屏能做什么。
struct OnboardingWorkbenchView: View {
    @State private var role: OnboardingViewerRole
    private let allowedRoles: [OnboardingViewerRole]

    init(
        initialRole: OnboardingViewerRole = .guardian,
        allowedRoles: [OnboardingViewerRole] = OnboardingViewerRole.allCases
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
    }

    private var workbench: OnboardingWorkbench {
        OnboardingWorkbenchBuilder().build(role: role)
    }

    var body: some View {
        List {
            brandSection
            roleSection
            stepsSection
            boundariesSection
            sideEffectSection
        }
        .navigationTitle(BrandIdentity.systemName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var brandSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                Image(BrandIdentity.logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel(BrandIdentity.systemName)

                VStack(alignment: .leading, spacing: 4) {
                    Text(workbench.title)
                        .font(.title2.bold())
                        .accessibilityIdentifier("onboarding-title")
                    Text(workbench.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("onboarding-subtitle")
                    Text(BrandIdentity.systemTagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("准备完成", value: "\(workbench.publicSummary.readyStepCount)/\(workbench.publicSummary.visibleStepCount)")
                .accessibilityIdentifier("onboarding-ready-summary")
        }
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
                .accessibilityIdentifier("onboarding-role-picker")
            } else {
                LabeledContent("视角", value: role.label)
                    .accessibilityIdentifier("onboarding-role-\(role.rawValue)")
            }
        }
    }

    private var stepsSection: some View {
        Section("入门清单") {
            if workbench.steps.isEmpty {
                ContentUnavailableView("暂无可展示入口", systemImage: "lock")
            } else {
                ForEach(workbench.steps) { step in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .font(.subheadline.bold())
                            Text(step.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: icon(for: step.kind))
                            .foregroundStyle(step.ready ? .green : .orange)
                    }
                    .accessibilityIdentifier("onboarding-step-\(step.id)")
                }
            }
        }
    }

    private var boundariesSection: some View {
        Section("护栏") {
            ForEach(workbench.boundaries) { boundary in
                VStack(alignment: .leading, spacing: 4) {
                    Text(boundary.title)
                        .font(.subheadline.bold())
                    Text(boundary.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("onboarding-boundary-\(boundary.id)")
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            OnboardingBoundaryFlag(
                title: "登录 / 创建家庭",
                value: workbench.publicSummary.startsLogin || workbench.publicSummary.createsAccount || workbench.publicSummary.writesFamily,
                identifier: "onboarding-boundary-login-family"
            )
            OnboardingBoundaryFlag(
                title: "申请权限",
                value: workbench.publicSummary.requestsApplePermission,
                identifier: "onboarding-boundary-permission"
            )
            OnboardingBoundaryFlag(
                title: "网络 / 通知",
                value: workbench.publicSummary.callsNetwork || workbench.publicSummary.sendsNotification,
                identifier: "onboarding-boundary-network-notification"
            )
            OnboardingBoundaryFlag(
                title: "账本 / 设备",
                value: workbench.publicSummary.writesLedger || workbench.publicSummary.unlocksDevice,
                identifier: "onboarding-boundary-ledger-device"
            )
        }
    }

    private func icon(for kind: OnboardingStepKind) -> String {
        switch kind {
        case .role: return "person.2"
        case .tasks: return "checklist"
        case .school: return "graduationcap"
        case .credit: return "wallet.pass"
        case .reports: return "doc.text"
        case .privacy: return "lock.shield"
        }
    }

    private static func normalizedRoles(_ roles: [OnboardingViewerRole]) -> [OnboardingViewerRole] {
        let source = roles.isEmpty ? OnboardingViewerRole.allCases : roles
        return OnboardingViewerRole.allCases.filter { source.contains($0) }
    }
}

private struct OnboardingBoundaryFlag: View {
    let title: String
    let value: Bool
    let identifier: String

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
        .accessibilityIdentifier(identifier)
    }
}
