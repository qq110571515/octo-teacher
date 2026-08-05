import SwiftUI

struct ParentWebsiteSafetyView: View {
    @Environment(WebsiteSafetyStore.self) private var safetyStore
    #if canImport(FamilyControls) && canImport(ManagedSettings)
    @Environment(ScreenTimePOCManager.self) private var screenTimeManager
    #endif
    @State private var domainInput = ""
    @State private var feedback: String?

    var body: some View {
        @Bindable var safetyStore = safetyStore

        List {
            Section {
                Toggle(
                    "自动拦截成人内容",
                    isOn: Binding(
                        get: { safetyStore.automaticAdultContentFilterEnabled },
                        set: { value in
                            safetyStore.setAutomaticAdultContentFilterEnabled(value)
                            applyPolicy()
                        }
                    )
                )
                .accessibilityIdentifier("website-safety-automatic-filter")

                #if canImport(FamilyControls) && canImport(ManagedSettings)
                Label(
                    screenTimeManager.websiteSafetyIsApplied ? "系统过滤已生效" : "等待 Screen Time 授权",
                    systemImage: screenTimeManager.websiteSafetyIsApplied ? "checkmark.shield.fill" : "exclamationmark.shield"
                )
                .foregroundStyle(screenTimeManager.websiteSafetyIsApplied ? Color.green : Color.orange)
                #endif
            } header: {
                Text("未成年网站保护")
            } footer: {
                Text("使用 iOS 系统成人内容过滤，并叠加家庭禁止名单。章鱼老师 不保存浏览记录，也不会让积分兑换或紧急解锁关闭网站保护。")
            }

            Section {
                TextField("例如 example.com", text: $domainInput)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("website-safety-domain-input")

                Button {
                    addDomain()
                } label: {
                    Label("加入禁止名单", systemImage: "plus.circle.fill")
                }
                .disabled(domainInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("website-safety-add-domain")

                if let feedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("家长自定义")
            } footer: {
                Text("只填写域名即可。系统会自动去掉 https://、路径和 www。最多保存 50 个禁止域名。")
            }

            if !safetyStore.guardianEntries.isEmpty {
                Section("家庭禁止名单") {
                    ForEach(safetyStore.guardianEntries) { entry in
                        WebsiteSafetyDomainRow(entry: entry, canDelete: true) {
                            safetyStore.setEnabled($0, for: entry.id)
                            applyPolicy()
                        } onDelete: {
                            safetyStore.removeGuardianDomain(entry.id)
                            applyPolicy()
                        }
                    }
                }
            }

            Section {
                DisclosureGroup("推荐保护名单（20 个）") {
                    ForEach(safetyStore.recommendedEntries) { entry in
                        WebsiteSafetyDomainRow(entry: entry, canDelete: false) {
                            safetyStore.setEnabled($0, for: entry.id)
                            applyPolicy()
                        }
                    }
                }

                Button("恢复推荐保护") {
                    safetyStore.restoreRecommendedProtection()
                    applyPolicy()
                    feedback = "已恢复自动过滤和 20 个推荐禁止域名。"
                }
            } footer: {
                Text("推荐名单只是补充。Apple 的自动成人内容分类仍是主要防线，可覆盖未列出的新网站。")
            }
        }
        .navigationTitle("网站安全中心")
        .navigationBarTitleDisplayMode(.inline)
        .task { applyPolicy() }
    }

    private func addDomain() {
        switch safetyStore.addGuardianDomain(domainInput) {
        case .added:
            feedback = "已加入禁止名单。"
            domainInput = ""
            applyPolicy()
        case .duplicate:
            feedback = "这个网站已经在禁止名单中。"
        case .invalidDomain:
            feedback = "域名格式不正确，请只填写网站域名。"
        case .capacityReached:
            feedback = "已达到 iOS 支持的 50 个补充域名上限。"
        }
    }

    private func applyPolicy() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        screenTimeManager.applyWebsiteSafety(
            enabledDomains: safetyStore.enabledDomains,
            automaticAdultContentFilter: safetyStore.automaticAdultContentFilterEnabled
        )
        #endif
    }
}

private struct WebsiteSafetyDomainRow: View {
    let entry: BlockedWebsiteEntry
    let canDelete: Bool
    let onToggle: (Bool) -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.domain)
                    .font(.subheadline.monospaced())
                Text(entry.source == .recommended ? "推荐保护" : "家长添加")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { entry.isEnabled }, set: { value in onToggle(value) }))
                .labelsHidden()
            if canDelete {
                Button(role: .destructive) { onDelete?() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("删除 \(entry.domain)")
            }
        }
    }
}
