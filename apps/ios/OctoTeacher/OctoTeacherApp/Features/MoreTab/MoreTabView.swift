import SwiftUI

/// Guardian-only account, device, and app settings surface.
///
/// Product builds keep engineering dashboards out of the family journey. They remain
/// available only when an explicit developer/UI-test flag is enabled.
struct MoreTabView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var cloud

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    private var showsDeveloperPreviews: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-OctoTeacherDeveloperPreviews")
            || arguments.contains(where: { $0.hasPrefix("-OctoTeacherUITest") })
            || UserDefaults.standard.bool(forKey: "OctoTeacherShowDeveloperPreviews")
    }

    var body: some View {
        List {
            familySection
            settingsSection

            if showsDeveloperPreviews {
                developerSection
            }

            aboutSection
        }
        .navigationTitle(lang.pick("更多", "More"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await cloud.bootstrap()
        }
    }

    private var familySection: some View {
        Section {
            NavigationLink {
                FamilyCloudAccountGateView()
            } label: {
                row(
                    title: lang.pick("家庭账号与设备", "Family Account & Devices"),
                    detail: familyStatusDetail,
                    systemImage: cloud.family == nil ? "person.3" : "person.3.fill",
                    status: cloud.family == nil ? nil : lang.pick("已连接", "Connected")
                )
            }
            .accessibilityIdentifier("more-tab-family-account")
        } header: {
            Text(lang.pick("家庭", "Family"))
        } footer: {
            Text(lang.pick(
                "家长登录后可连接其他监护人和孩子手机。孩子无需注册账号。",
                "Guardians can link other guardians and child devices. Children do not need an account."
            ))
        }
    }

    private var settingsSection: some View {
        Section {
            NavigationLink {
                SoftwareSettingsGateView()
            } label: {
                row(
                    title: lang.pick("软件设置", "App Settings"),
                    detail: lang.pick(
                        "语言、地区、AI、朗读、学校与隐私",
                        "Language, region, AI, read-aloud, school, and privacy"
                    ),
                    systemImage: "gearshape"
                )
            }
            .accessibilityIdentifier("more-tab-software-settings")
        } header: {
            Text(lang.pick("设置", "Settings"))
        } footer: {
            Text(lang.pick(
                "敏感设置受家长 PIN 保护，孩子无法修改。",
                "Sensitive settings are protected by the guardian PIN."
            ))
        }
    }

    private var developerSection: some View {
        Section {
            NavigationLink {
                MobileModuleLaunchCenterView(initialRole: .child, allowedRoles: [.child])
            } label: {
                row(
                    title: lang.pick("开发者模块预览", "Developer Module Preview"),
                    detail: lang.pick("检查模块关系和验收页面", "Inspect module boundaries and test surfaces"),
                    systemImage: "square.grid.2x2"
                )
            }
            .accessibilityIdentifier("more-tab-modules")

            NavigationLink {
                MobileHomeView()
            } label: {
                row(
                    title: lang.pick("开发者平台总览", "Developer Platform Overview"),
                    detail: lang.pick("查看发布质量门和风险聚合", "Review release gates and aggregated risks"),
                    systemImage: "gauge.with.dots.needle.67percent"
                )
            }
            .accessibilityIdentifier("more-tab-home")
        } header: {
            Text(lang.pick("开发者预览", "Developer Preview"))
        } footer: {
            Text(lang.pick(
                "仅用于工程验收，家庭测试默认不会显示。",
                "Engineering-only surfaces hidden from normal family use."
            ))
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent(lang.pick("版本", "Version"), value: BuildIdentity.shortVersionText)

            if showsDeveloperPreviews {
                LabeledContent(lang.pick("测试包", "Bundle"), value: BuildIdentity.bundleIdentifier)
                LabeledContent(lang.pick("提交", "Commit"), value: BuildIdentity.commit)
            }

            Label {
                Text(lang.pick(
                    "聊天、照片、邮件正文和 AI 成长记忆保存在本机；启用家庭同步后，只同步家庭成员、设备、任务和状态。",
                    "Chats, photos, email content, and AI growth memory stay on this device. Family sync shares only members, devices, tasks, and status."
                ))
            } icon: {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.green)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("more-tab-privacy-summary")
        } header: {
            Text(lang.pick("关于章鱼老师", "About Octo Teacher"))
        }
    }

    private var familyStatusDetail: String {
        guard let family = cloud.family else {
            return cloud.isGuardianSignedIn
                ? lang.pick("完成家庭设置并连接孩子手机", "Finish family setup and link child devices")
                : lang.pick("登录、创建家庭并邀请成员", "Sign in, create a family, and invite members")
        }

        let activeDevices = family.devices.filter { $0.status == "active" }.count
        return lang.pick(
            "\(family.children.count) 个孩子 · \(activeDevices) 台设备",
            "\(family.children.count) children · \(activeDevices) devices"
        )
    }

    private func row(
        title: String,
        detail: String,
        systemImage: String,
        status: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.body.weight(.medium))
                    if let status {
                        Text(status)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct FamilyCloudAccountGateView: View {
    @Environment(ParentGate.self) private var gate
    @Environment(LocalFamilyStore.self) private var store

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        Group {
            if gate.isUnlocked {
                FamilyCloudAccountView()
            } else {
                ParentGateView()
                    .navigationTitle(lang.pick("家长验证", "Guardian Verification"))
            }
        }
    }
}
