import SwiftUI

struct FamilyCloudAccountView: View {
    @Environment(FamilyCloudSessionStore.self) private var cloud
    @Environment(LocalFamilyStore.self) private var local
    @Environment(\.openURL) private var openURL

    var pendingInvite: FamilyCloudJoinPayload?
    var onJoined: (() -> Void)?

    @State private var consentAccepted = false
    @State private var emailLogin: EmailDeviceLoginStart?
    @State private var errorMessage: String?
    @State private var exportURL: URL?
    @State private var portalLink: FamilyCloudPortalLink?
    @State private var isConfirmingDeletion = false

    private var lang: AppInterfaceLanguage {
        pendingInvite?.isChildDevice == true
            ? local.activeChildInterfaceLanguage
            : local.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        @Bindable var cloud = cloud
        Group {
            if let pendingInvite, pendingInvite.isChildDevice {
                childJoinContent(pendingInvite)
            } else if !cloud.isGuardianSignedIn {
                guardianSignInContent
            } else if let pendingInvite {
                guardianJoinContent(pendingInvite)
            } else if cloud.family == nil {
                familyCreationContent
            } else {
                connectedContent
            }
        }
        .task {
            await cloud.bootstrap()
            if let family = cloud.family {
                local.applyCloudFamilyIdentity(family)
            }
        }
        .confirmationDialog(
            lang.pick("永久删除云家庭？", "Permanently delete this cloud family?"),
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button(lang.pick("永久删除", "Delete permanently"), role: .destructive) {
                Task { await deleteFamily() }
            }
            Button(lang.pick("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(lang.pick(
                "这会删除云端成员、设备、邀请和任务，并让所有家庭手机退出。手机本地的聊天、照片和 AI 记忆不会被删除。",
                "This deletes cloud members, devices, invitations, and tasks, and signs out every family phone. Local chats, photos, and AI memory are not deleted."
            ))
        }
    }

    private var guardianSignInContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(lang.pick("我同意同步家庭成员和任务状态", "I agree to sync family members and task status"), isOn: $consentAccepted)
            Text(lang.pick(
                "聊天、照片、邮件正文、AI 伙伴记忆和证明文件仍只保存在本机。",
                "Chats, photos, email content, AI buddy memory, and proof files stay on this device."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let emailLogin {
                Label(lang.pick("一次性设备码", "One-time device code"), systemImage: "iphone.and.arrow.forward")
                    .font(.subheadline.weight(.semibold))
                Text(emailLogin.code)
                    .font(.system(.title2, design: .monospaced, weight: .bold))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("family-cloud-email-device-code")
                Text(lang.pick(
                    "网页会要求你用已审核邮箱登录，再批准这台手机。App 不保存邮箱密码。",
                    "The website asks you to sign in with your approved email and approve this phone. The app never stores your email password."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    openURL(emailLogin.verificationURL)
                } label: {
                    Label(lang.pick("打开网页并登录邮箱", "Open website and sign in"), systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    Task { await finishEmailLogin(emailLogin) }
                } label: {
                    Label(lang.pick("我已批准，完成连接", "Approved — finish connecting"), systemImage: "checkmark.icloud")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(cloud.isWorking)
                Button(lang.pick("重新生成设备码", "Generate a new code")) {
                    Task { await startEmailLogin() }
                }
                .font(.caption)
                .disabled(cloud.isWorking)
            } else {
                Button {
                    Task { await startEmailLogin() }
                } label: {
                    Label(lang.pick("使用邮箱账号登录", "Sign in with email account"), systemImage: "envelope.badge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!consentAccepted || cloud.isWorking)
            }
            feedback
        }
    }

    private var familyCreationContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(lang.pick("邮箱账号登录完成", "Email account connected"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Button {
                Task { await createFamily() }
            } label: {
                Label(lang.pick("启用多手机家庭同步", "Enable family sync"), systemImage: "icloud.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(cloud.isWorking)
            feedback
        }
    }

    private func childJoinContent(_ invite: FamilyCloudJoinPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(lang.pick("孩子手机无需注册账号", "No account is needed on the child's phone"), systemImage: "figure.child")
            Text(lang.pick("确认后，这台手机只会收到二维码绑定孩子的任务。", "This phone will receive tasks only for the child linked by this QR code."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await claim(invite) }
            } label: {
                Label(lang.pick("完成孩子手机绑定", "Finish linking this child's phone"), systemImage: "iphone.gen3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(cloud.isWorking)
            feedback
        }
    }

    private func guardianJoinContent(_ invite: FamilyCloudJoinPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(lang.pick("监护人身份已验证", "Guardian identity verified"), systemImage: "person.badge.key.fill")
                .foregroundStyle(.green)
            Button {
                Task { await claim(invite) }
            } label: {
                Label(lang.pick("加入这个家庭", "Join this family"), systemImage: "person.3.sequence.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(cloud.isWorking)
            feedback
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(cloud.family?.family.displayName ?? lang.pick("家庭云同步", "Family Cloud Sync"), systemImage: "icloud.fill")
                .foregroundStyle(.blue)
            Text(lang.pick(
                "已连接 \(cloud.family?.guardians.count ?? 0) 位监护人、\(cloud.family?.children.count ?? 0) 个孩子、\(cloud.family?.devices.filter { $0.status == "active" }.count ?? 0) 台设备。",
                "Connected: \(cloud.family?.guardians.count ?? 0) guardians, \(cloud.family?.children.count ?? 0) children, and \(cloud.family?.devices.filter { $0.status == "active" }.count ?? 0) devices."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let lastSyncAt = cloud.lastSyncAt {
                Label {
                    Text(lang.pick("最近同步：\(lastSyncAt.formatted(date: .abbreviated, time: .shortened))", "Last sync: \(lastSyncAt.formatted(date: .abbreviated, time: .shortened))"))
                } icon: {
                    Image(systemName: cloud.lastSyncError == nil ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                }
                .font(.caption)
                .foregroundStyle(cloud.lastSyncError == nil ? Color.green : Color.orange)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label(lang.pick("网页版家庭控制台", "Web Family Console"), systemImage: "rectangle.connected.to.line.below")
                    .font(.subheadline.weight(.semibold))
                Text(lang.pick(
                    "用一次性链接码把已审核的网页账号连接到这个家庭。网页只显示任务、积分和活动摘要，不显示聊天、照片、密钥或 Screen Time 令牌。",
                    "Use a one-time link code to connect an approved web account to this family. The web console shows task, point, and activity summaries, never chats, photos, credentials, or Screen Time tokens."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let portalLink {
                    Text(portalLink.code)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("family-cloud-portal-link-code")
                    Text(lang.pick("链接码 10 分钟内有效，并且只能使用一次。", "The code is valid for 10 minutes and can be used only once."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        ShareLink(item: portalLink.code) {
                            Label(lang.pick("分享链接码", "Share code"), systemImage: "square.and.arrow.up")
                        }
                        Link(destination: URL(string: "https://octoteacher.com/family")!) {
                            Label(lang.pick("打开网页", "Open website"), systemImage: "safari")
                        }
                    }
                    .font(.subheadline)
                }
                Button {
                    Task { await generatePortalLink() }
                } label: {
                    Label(
                        portalLink == nil ? lang.pick("生成一次性链接码", "Generate one-time link code") : lang.pick("重新生成链接码", "Generate a new code"),
                        systemImage: "link.badge.plus"
                    )
                }
                .disabled(cloud.isWorking)
                .accessibilityIdentifier("family-cloud-generate-portal-link")
            }
            if cloud.family?.family.isCreator == true {
                Button {
                    Task { await prepareExport() }
                } label: {
                    Label(lang.pick("导出云家庭数据", "Export cloud family data"), systemImage: "square.and.arrow.up")
                }
                .disabled(cloud.isWorking)
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label(lang.pick("分享导出文件", "Share export file"), systemImage: "doc.badge.arrow.up")
                    }
                }
                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    Label(lang.pick("删除云家庭", "Delete cloud family"), systemImage: "trash")
                }
                .disabled(cloud.isWorking)
            }
            Button {
                Task { await disconnect() }
            } label: {
                Label(lang.pick("退出这台监护人设备", "Sign out this guardian device"), systemImage: "rectangle.portrait.and.arrow.right")
            }
            .disabled(cloud.isWorking)
            feedback
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if cloud.isWorking {
            ProgressView()
        }
        if let message = errorMessage ?? cloud.localizedMessage(for: lang) {
            Text(message)
                .font(.caption)
                .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
        }
    }

    private func startEmailLogin() async {
        guard consentAccepted else { return }
        do {
            let login = try await cloud.startEmailSignIn()
            emailLogin = login
            errorMessage = nil
            openURL(login.verificationURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishEmailLogin(_ login: EmailDeviceLoginStart) async {
        do {
            if try await cloud.completeEmailSignIn(requestToken: login.requestToken) {
                emailLogin = nil
                if let family = cloud.family {
                    local.applyCloudFamilyIdentity(family)
                }
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createFamily() async {
        do {
            try await cloud.createFamily(from: local)
            try await cloud.syncGuardianTasks(from: local)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func claim(_ invite: FamilyCloudJoinPayload) async {
        do {
            try await cloud.claim(invite)
            if let family = cloud.family {
                local.applyCloudFamilyIdentity(family)
            }
            if invite.isChildDevice { try await cloud.refreshChildSurface(into: local) }
            errorMessage = nil
            onJoined?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareExport() async {
        do {
            let export = try await cloud.exportCloudFamily()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("OctoTeacher-family-cloud-export.json")
            try encoder.encode(export).write(to: url, options: .atomic)
            exportURL = url
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() async {
        do {
            try await cloud.disconnectGuardian()
            exportURL = nil
            portalLink = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generatePortalLink() async {
        do {
            portalLink = try await cloud.createPortalLink()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFamily() async {
        do {
            let receipt = try await cloud.deleteCloudFamily()
            exportURL = nil
            errorMessage = lang.pick(
                "云家庭已删除。删除凭证：\(receipt.receiptId)",
                "Cloud family deleted. Receipt: \(receipt.receiptId)"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
