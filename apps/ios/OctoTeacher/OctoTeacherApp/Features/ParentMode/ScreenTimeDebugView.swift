import SwiftUI

#if canImport(FamilyControls) && canImport(ManagedSettings)
import FamilyControls
import ManagedSettings

/// Guardian control plane. It authors opaque FamilyControls policies for a linked child and
/// never writes ManagedSettings on the guardian phone.
struct ScreenTimeDebugView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var cloud
    @Environment(ScreenTimePOCManager.self) private var manager

    @State private var selectedChildID = UUID()
    @State private var showsPicker = false
    @State private var isSaving = false
    @State private var feedback: String?
    @State private var showsResetConfirmation = false
    @State private var showsDiagnostics = false
    @State private var remoteUnlockMinutes = 30

    private let policyStore = GuardianScreenTimePolicyStore()

    private var lang: AppInterfaceLanguage { store.settings.resolvedParentInterfaceLanguage }
    private var selectedChild: ChildProfile? { store.children.first { $0.id == selectedChildID } }
    private var cloudPolicy: FamilyScreenTimePolicy? { cloud.screenTimePolicy(for: selectedChildID) }
    private var cloudCatalog: FamilyScreenTimeCatalog? { cloud.screenTimeCatalog(for: selectedChildID) }
    private var deviceStatus: FamilyScreenTimeDeviceStatus? { cloud.screenTimeStatus(for: selectedChildID) }
    private var childDevices: [FamilyCloudSnapshot.Device] { cloud.activeChildDevices(for: selectedChildID) }

    var body: some View {
        @Bindable var manager = manager
        List {
            childSection
            connectionSection
            appSelectionSection
            actionSection
            recoverySection
            diagnosticsSection
        }
        .navigationTitle(lang.pick("屏幕时间管控", "Screen Time Controls"))
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $showsPicker, selection: $manager.selection)
        .task { await prepare() }
        .onChange(of: selectedChildID) { _, _ in loadDraftForSelectedChild() }
        .onChange(of: showsPicker) { _, isPresented in
            guard !isPresented else { return }
            manager.refreshGuardianDraftCounts()
            manager.clearGuardianCatalogBinding()
            saveDraftLocally()
        }
        .refreshable { await refreshStatus() }
        .confirmationDialog(
            lang.pick("重置这个孩子的屏幕时间规则？", "Reset this child's Screen Time policy?"),
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(lang.pick("重置规则", "Reset Policy"), role: .destructive) {
                Task { await resetPolicy() }
            }
            Button(lang.pick("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(lang.pick(
                "孩子手机同步后会停止章鱼老师的 App 遮挡。",
                "The child phone will stop Octo Teacher app shielding after it syncs."
            ))
        }
    }

    private var childSection: some View {
        Section {
            Picker(lang.pick("管理孩子", "Manage child"), selection: $selectedChildID) {
                ForEach(store.children) { child in
                    Text(child.name).tag(child.id)
                }
            }
            .pickerStyle(.menu)
        } footer: {
            Text(lang.pick(
                "每个孩子拥有独立的设备、App 清单和规则；这里发布的规则只发送给当前孩子。",
                "Each child has separate devices, app selections, and policies. Rules published here target only the current child."
            ))
        }
    }

    private var connectionSection: some View {
        Section(lang.pick("孩子设备", "Child Device")) {
            if !cloud.isGuardianSignedIn || cloud.family == nil {
                NavigationLink {
                    FamilyMembersView()
                } label: {
                    StatusRow(
                        icon: "person.crop.circle.badge.exclamationmark",
                        color: .orange,
                        title: lang.pick("先启用多手机家庭", "Enable Multi-Device Family"),
                        detail: lang.pick("登录家庭账号并创建家庭。", "Sign in and create your family.")
                    )
                }
            } else if childDevices.isEmpty {
                NavigationLink {
                    FamilyMembersView()
                } label: {
                    StatusRow(
                        icon: "qrcode.viewfinder",
                        color: .orange,
                        title: lang.pick("绑定\(childName)的手机", "Link \(childName)'s phone"),
                        detail: lang.pick("生成孩子二维码，在孩子手机扫码加入。", "Create a child QR code and scan it on the child's phone.")
                    )
                }
            } else {
                ForEach(childDevices) { device in
                    StatusRow(
                        icon: "iphone.gen3",
                        color: deviceStatus?.authorization == .approved ? .green : .orange,
                        title: device.displayName,
                        detail: authorizationDetail
                    )
                }
            }
        }
    }

    private var appSelectionSection: some View {
        Section {
            Button {
                openGuardianPicker()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(manager.selectionCounts.hasSelection
                             ? lang.pick("更改管理的 App", "Change Managed Apps")
                             : lang.pick("选择要管理的 App", "Choose Apps to Manage"))
                            .font(.headline)
                        Text(selectionSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .disabled(childDevices.isEmpty)
            .accessibilityIdentifier("screen-time-debug-open-picker")

            if let cloudCatalog {
                HStack {
                    Label(
                        lang.pick(
                            "孩子目录 · \(cloudCatalog.applicationCount) 个 App",
                            "Child Catalog · \(cloudCatalog.applicationCount) Apps"
                        ),
                        systemImage: "iphone.gen3.radiowaves.left.and.right"
                    )
                    Spacer()
                    Text("v\(cloudCatalog.revision)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        manager.useCompleteGuardianCatalog()
                        saveDraftLocally()
                    } label: {
                        Label(lang.pick("选择全部", "Select All"), systemImage: "checkmark.circle")
                    }
                    Spacer()
                    Button {
                        manager.clearGuardianCatalogApplications()
                        saveDraftLocally()
                    } label: {
                        Label(lang.pick("清空 App", "Clear Apps"), systemImage: "circle")
                    }
                }

                ForEach(Array(manager.guardianCatalogSelection.applicationTokens), id: \.self) { token in
                    Button {
                        manager.toggleGuardianCatalogApplication(token)
                        saveDraftLocally()
                    } label: {
                        HStack(spacing: 12) {
                            Label(token)
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Image(systemName: manager.selection.applicationTokens.contains(token)
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .foregroundStyle(
                                    manager.selection.applicationTokens.contains(token)
                                        ? Color.blue
                                        : Color.secondary
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                StatusRow(
                    icon: "iphone.gen3",
                    color: .orange,
                    title: lang.pick("等待孩子手机采集 App 目录", "Waiting for Child App Catalog"),
                    detail: lang.pick(
                        "目录采集需要在孩子手机通过家长 PIN 完成一次。",
                        "Capture the catalog once on the child phone behind the Parent PIN."
                    )
                )
            }
        } header: {
            Text(lang.pick("App 范围", "App Scope"))
        } footer: {
            Text(lang.pick(
                "孩子目录提供具体 App；Apple 选择器继续用于分类兜底。正式规则只有在这里保存并发送后才会执行。",
                "The child catalog provides specific apps; Apple's picker remains available for category fallback. Nothing is enforced until the policy is saved and sent here."
            ))
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                Task { await sendPolicy() }
            } label: {
                HStack {
                    if isSaving { ProgressView() }
                    Label(primaryActionTitle, systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSendPolicy || isSaving || (policyIsApplied && !draftDiffersFromCloud))
            .accessibilityIdentifier("screen-time-debug-save-policy")

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(feedbackIsError ? Color.orange : Color.green)
            }

            if let cloudPolicy {
                StatusRow(
                    icon: policyIsApplied ? "checkmark.shield.fill" : "arrow.triangle.2.circlepath",
                    color: policyIsApplied ? .green : .blue,
                    title: policyIsApplied
                        ? lang.pick("已在孩子手机生效", "Active on Child Phone")
                        : lang.pick("已发布，等待孩子手机回执", "Published; Waiting for Child Acknowledgement"),
                    detail: lang.pick(
                        "规则版本 \(cloudPolicy.revision)",
                        "Policy revision \(cloudPolicy.revision)"
                    )
                )
            }

            if cloudPolicy != nil {
                Picker(lang.pick("远程解锁时长", "Remote Unlock Duration"), selection: $remoteUnlockMinutes) {
                    Text(lang.pick("15 分钟", "15 min")).tag(15)
                    Text(lang.pick("30 分钟", "30 min")).tag(30)
                    Text(lang.pick("60 分钟", "60 min")).tag(60)
                }
                .pickerStyle(.segmented)

                HStack {
                    Button {
                        Task { await sendControl(action: "unlock", minutes: remoteUnlockMinutes) }
                    } label: {
                        Label(lang.pick("远程解锁", "Remote Unlock"), systemImage: "lock.open.fill")
                    }
                    .disabled(isSaving)

                    Spacer()

                    Button {
                        Task { await sendControl(action: "lock") }
                    } label: {
                        Label(lang.pick("立即上锁", "Lock Now"), systemImage: "lock.fill")
                    }
                    .disabled(isSaving)
                }

                if let control = cloudPolicy?.control {
                    StatusRow(
                        icon: controlIsApplied ? "checkmark.circle.fill" : "clock.arrow.circlepath",
                        color: controlIsApplied ? .green : .orange,
                        title: controlIsApplied
                            ? lang.pick("孩子设备已执行", "Applied by Child Device")
                            : lang.pick("命令已发送，等待设备", "Command Sent; Waiting for Device"),
                        detail: control.mode == .locked
                            ? lang.pick("当前命令：上锁", "Current command: locked")
                            : lang.pick(
                                "当前命令：解锁至 \(formattedControlEnd(control))",
                                "Current command: unlock until \(formattedControlEnd(control))"
                            )
                    )
                }
            }
        } footer: {
            Text(lang.pick(
                "只有收到孩子手机的实际执行回执后，这里才显示“已生效”。",
                "This shows Active only after the child phone acknowledges real enforcement."
            ))
        }
    }

    private var recoverySection: some View {
        Section(lang.pick("检查与恢复", "Check & Recovery")) {
            Button {
                Task { await refreshStatus() }
            } label: {
                Label(lang.pick("刷新孩子设备状态", "Refresh Child Device Status"), systemImage: "arrow.clockwise")
            }
            Button {
                openGuardianPicker()
            } label: {
                Label(lang.pick("重新选择 App", "Choose Apps Again"), systemImage: "square.grid.3x3")
            }
            .disabled(childDevices.isEmpty)
            Button(role: .destructive) {
                showsResetConfirmation = true
            } label: {
                Label(lang.pick("重置这位孩子的规则", "Reset This Child's Policy"), systemImage: "arrow.counterclockwise")
            }
            .disabled(cloudPolicy == nil && !manager.selectionCounts.hasSelection)
        }
    }

    private var diagnosticsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showsDiagnostics) {
                LabeledContent(lang.pick("云端家庭", "Cloud family"), value: cloud.family == nil ? "—" : "OK")
                LabeledContent(lang.pick("孩子设备", "Child devices"), value: "\(childDevices.count)")
                LabeledContent(lang.pick("授权", "Authorization"), value: deviceStatus?.authorization.rawValue ?? "—")
                LabeledContent(lang.pick("执行状态", "Enforcement"), value: deviceStatus?.enforcement.rawValue ?? "—")
                LabeledContent(lang.pick("已选 App", "Selected apps"), value: "\(deviceStatus?.applicationCount ?? 0)")
                LabeledContent(lang.pick("已选分类", "Selected categories"), value: "\(deviceStatus?.categoryCount ?? 0)")
                LabeledContent(
                    lang.pick("云端规则版本", "Cloud revision"),
                    value: (cloudPolicy?.revision).map(String.init) ?? "—"
                )
                LabeledContent(
                    lang.pick("设备规则版本", "Applied revision"),
                    value: (deviceStatus?.appliedPolicyRevision).map(String.init) ?? "—"
                )
                if let code = deviceStatus?.lastErrorCode {
                    LabeledContent(lang.pick("错误代码", "Error code"), value: code)
                }
            } label: {
                Label(lang.pick("技术诊断", "Technical Diagnostics"), systemImage: "wrench.and.screwdriver")
            }
        }
    }

    private var childName: String { selectedChild?.name ?? lang.pick("孩子", "Child") }

    private var canSendPolicy: Bool {
        cloud.isGuardianSignedIn &&
            cloud.family != nil &&
            !childDevices.isEmpty &&
            manager.guardianCatalogBindingIsCurrent &&
            manager.selectionCounts.hasSelection
    }

    private var primaryActionTitle: String {
        policyIsApplied && !draftDiffersFromCloud
            ? lang.pick("规则已是最新", "Policy Is Up to Date")
            : lang.pick("保存并发送给孩子", "Save and Send to Child")
    }

    private var policyIsApplied: Bool {
        guard let policy = cloudPolicy else { return false }
        return deviceStatus?.authorization == .approved &&
            deviceStatus?.enforcement == .applied &&
            deviceStatus?.appliedPolicyRevision == policy.revision &&
            deviceStatus?.appliedSelectionHash == policy.selectionHash
    }

    private var controlIsApplied: Bool {
        guard let commandID = cloudPolicy?.control?.commandId else { return policyIsApplied }
        return policyIsApplied && deviceStatus?.appliedControlCommandId == commandID
    }

    private var draftDiffersFromCloud: Bool {
        guard manager.selectionCounts.hasSelection else { return cloudPolicy != nil }
        guard let draft = try? manager.makeGuardianPolicy(
            revision: cloudPolicy?.revision ?? 0,
            updatedAt: ""
        ) else {
            return true
        }
        return draft.selectionHash != cloudPolicy?.selectionHash
    }

    private var feedbackIsError: Bool {
        guard let feedback else { return false }
        return feedback == cloud.lastSyncError ||
            feedback.localizedCaseInsensitiveContains("failed") ||
            feedback.contains("失败")
    }

    private var authorizationDetail: String {
        switch deviceStatus?.authorization {
        case .approved: return lang.pick("Apple 儿童设备授权已完成", "Apple child-device authorization approved")
        case .denied: return lang.pick("授权被拒绝，请在孩子手机重试", "Authorization denied; retry on the child phone")
        case .unavailable: return lang.pick("这台设备暂不支持", "Unavailable on this device")
        case .error: return lang.pick("授权遇到问题，请在孩子手机重试", "Authorization needs attention on the child phone")
        case .notRequested, .none: return lang.pick("等待在孩子手机完成一次授权", "Waiting for one-time authorization on child phone")
        }
    }

    private var selectionSummary: String {
        guard manager.selectionCounts.hasSelection else {
            return lang.pick("尚未选择", "Nothing selected")
        }
        return lang.pick(
            "\(manager.selectionCounts.applications) 个 App · \(manager.selectionCounts.categories) 个分类",
            "\(manager.selectionCounts.applications) apps · \(manager.selectionCounts.categories) categories"
        )
    }

    @MainActor
    private func prepare() async {
        if !store.children.contains(where: { $0.id == selectedChildID }) {
            selectedChildID = store.activeChildId
        }
        await cloud.bootstrap()
        loadDraftForSelectedChild()
    }

    @MainActor
    private func openGuardianPicker() {
        // On a guardian device, FamilyActivityPicker discovers authorized child devices from
        // Apple Family Sharing. AuthorizationCenter reflects this phone, not the linked child.
        manager.prepareGuardianSelectionForPicker()
        feedback = nil
        showsPicker = true
    }

    @MainActor
    private func refreshStatus() async {
        await cloud.bootstrap()
        feedback = cloud.lastSyncError ?? lang.pick("孩子设备状态已刷新。", "Child device status refreshed.")
        loadDraftForSelectedChild(preservingFeedback: true)
    }

    @MainActor
    private func loadDraftForSelectedChild(preservingFeedback: Bool = false) {
        manager.loadGuardianCatalog(cloudCatalog)
        manager.loadGuardianDraft(policyStore.policy(for: selectedChildID) ?? cloudPolicy)
        if !preservingFeedback {
            feedback = nil
        }
    }

    @MainActor
    private func saveDraftLocally() {
        guard manager.selectionCounts.hasSelection,
              let policy = try? manager.makeGuardianPolicy(
                  revision: cloudPolicy?.revision ?? 0,
                  updatedAt: ISO8601DateFormatter().string(from: Date())
              ) else { return }
        try? policyStore.save(policy, for: selectedChildID)
        feedback = lang.pick(
            "App 已选择，请保存并发送给孩子。",
            "Apps selected. Save and send the policy to the child."
        )
    }

    @MainActor
    private func sendPolicy() async {
        guard canSendPolicy else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let revision = max(
                cloudPolicy?.revision ?? 0,
                policyStore.policy(for: selectedChildID)?.revision ?? 0
            ) + 1
            let policy = try manager.makeGuardianPolicy(
                revision: revision,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
            try policyStore.save(policy, for: selectedChildID)
            try await cloud.syncGuardianScreenTimePolicy(policy, for: selectedChildID)
            feedback = lang.pick(
                "规则已发布，正在等待孩子手机执行。",
                "Policy published; waiting for the child phone to enforce it."
            )
        } catch {
            feedback = error.localizedDescription
        }
    }

    @MainActor
    private func resetPolicy() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await cloud.syncGuardianScreenTimePolicy(nil, for: selectedChildID)
            policyStore.clear(for: selectedChildID)
            manager.loadGuardianDraft(nil)
            feedback = lang.pick(
                "重置命令已发布，等待孩子手机同步。",
                "Reset published; waiting for the child phone to sync."
            )
        } catch {
            feedback = error.localizedDescription
        }
    }

    @MainActor
    private func sendControl(action: String, minutes: Int? = nil) async {
        guard cloudPolicy != nil else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await cloud.sendGuardianScreenTimeControl(
                action: action,
                minutes: minutes,
                for: selectedChildID
            )
            feedback = action == "lock"
                ? lang.pick("上锁命令已发送，等待孩子手机执行。", "Lock command sent; waiting for the child phone.")
                : lang.pick("定时解锁命令已发送，等待孩子手机执行。", "Timed unlock sent; waiting for the child phone.")
        } catch {
            feedback = error.localizedDescription
        }
    }

    private func formattedControlEnd(_ control: FamilyScreenTimeControl) -> String {
        guard let date = control.unlockEndDate else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

}

private struct StatusRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#else
struct ScreenTimeDebugView: View {
    var body: some View {
        ContentUnavailableView(
            "Screen Time API unavailable",
            systemImage: "lock.trianglebadge.exclamationmark",
            description: Text("This device cannot load FamilyControls / ManagedSettings.")
        )
        .navigationTitle("Screen Time")
    }
}
#endif
