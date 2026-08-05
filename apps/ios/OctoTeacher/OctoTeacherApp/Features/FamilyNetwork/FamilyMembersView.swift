import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// 家庭创建者的成员与设备工作台。云家庭是唯一身份来源。
struct FamilyMembersView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var cloud
    @State private var presentedCloudInvite: FamilyCloudInvite?
    @State private var isShowingJoinScanner = false
    @State private var pendingCloudJoin: FamilyCloudJoinPayload?
    @State private var cloudError: String?

    private var lang: AppInterfaceLanguage { store.settings.resolvedParentInterfaceLanguage }

    var body: some View {
        List {
            Section {
                FamilyCloudAccountView()
            } header: {
                Text(lang.pick("多手机家庭", "Family Devices"))
            } footer: {
                Text(lang.pick(
                    "监护人使用审核通过的邮箱账号连接家庭。孩子手机扫码加入，不需要邮箱账号。",
                    "Guardians connect with an approved email account. A child's phone joins by QR code without an email account."
                ))
            }

            if let family = cloud.family {
                Section {
                    LabeledContent(lang.pick("家庭", "Family"), value: family.family.displayName)
                    LabeledContent(
                        lang.pick("当前账号", "Current account"),
                        value: cloud.guardian?.displayName ?? lang.pick("已登录监护人", "Signed-in guardian")
                    )
                    LabeledContent(
                        lang.pick("家庭角色", "Family role"),
                        value: family.family.isCreator
                            ? lang.pick("家庭创建者", "Family creator")
                            : lang.pick("共同监护人", "Co-guardian")
                    )
                } header: {
                    Text(lang.pick("家庭身份", "Family identity"))
                } footer: {
                    Text(lang.pick(
                        "家庭名称、成员、角色和设备全部来自同一个云家庭。",
                        "The family name, members, roles, and devices all come from one cloud family."
                    ))
                }

                memberSection(role: .guardian, title: "监护人", footer: "所有监护人都能布置、审核任务和查看孩子成长。")
                memberSection(role: .child, title: "孩子", footer: "每台孩子手机只绑定一个孩子档案，不要求邮箱或独立账号。")
            }

            if let family = cloud.family, family.family.isCreator {
                Section(lang.pick("家庭邀请", "Family Invitations")) {
                    Button {
                        createCloudInvite(kind: "guardian")
                    } label: {
                        Label(lang.pick("邀请一位监护人", "Invite a guardian"), systemImage: "person.badge.plus")
                    }
                    ForEach(family.children) { child in
                        Button {
                            createCloudInvite(kind: "child_device", childId: child.id)
                        } label: {
                            Label(lang.pick("绑定\(child.displayName)的手机", "Link \(child.displayName)'s phone"), systemImage: "iphone.gen3")
                        }
                    }
                }
            }

            Section(lang.pick("设备状态", "Devices")) {
                if let family = cloud.family {
                    ForEach(family.devices.filter { $0.status != "revoked" }) { device in
                        HStack {
                            Label(device.displayName, systemImage: device.role == "child" ? "iphone" : "iphone.gen3")
                            Spacer()
                            Text(device.requiresRebind == true
                                ? lang.pick("需要重新绑定", "Rebind required")
                                : lang.pick("已绑定", "Linked"))
                                .font(.caption)
                                .foregroundStyle(device.requiresRebind == true ? Color.orange : Color.green)
                        }
                        .swipeActions {
                            if family.family.isCreator {
                                Button(role: .destructive) {
                                    Task { await revokeCloudDevice(device) }
                                } label: {
                                    Label(lang.pick("撤销", "Revoke"), systemImage: "iphone.slash")
                                }
                            }
                        }
                    }
                } else {
                    Text(lang.pick("尚未连接云家庭。", "No cloud family is connected."))
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await syncTasks() }
                } label: {
                    Label(lang.pick("立即同步家庭任务", "Sync family tasks now"), systemImage: "arrow.triangle.2.circlepath.icloud")
                }
                .disabled(cloud.family == nil || cloud.isWorking)
                if let cloudError {
                    Text(cloudError).font(.caption).foregroundStyle(.red)
                }
            } footer: {
                Text(lang.pick(
                    "只同步成员、设备和最小任务状态；照片、聊天、邮件和孩子记忆不会上传。",
                    "Only members, devices, and minimal task status are synced. Photos, chats, email, and child memory are not uploaded."
                ))
            }
        }
        .navigationTitle(lang.pick("家庭成员与设备", "Family Members & Devices"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedCloudInvite) { invite in
            NavigationStack {
                CloudFamilyJoinInviteView(invite: invite)
            }
        }
        .sheet(isPresented: $isShowingJoinScanner) {
            FamilyJoinScannerView { value in
                guard let payload = FamilyCloudJoinPayload.decode(value) else {
                    cloudError = lang.pick("这不是有效的云家庭二维码。", "This is not a valid Family Cloud QR code.")
                    return
                }
                pendingCloudJoin = payload
            }
        }
        .sheet(item: $pendingCloudJoin) { payload in
            NavigationStack {
                Form {
                    Section {
                        FamilyCloudAccountView(pendingInvite: payload) {
                            pendingCloudJoin = nil
                        }
                    }
                }
                .navigationTitle(lang.pick("加入家庭", "Join Family"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(lang.pick("取消", "Cancel")) { pendingCloudJoin = nil }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func memberSection(role: FamilyMemberRole, title: String, footer: String) -> some View {
        Section {
            if role == .guardian, let family = cloud.family {
                ForEach(family.guardians) { guardian in
                    cloudMemberRow(
                        name: guardian.displayName,
                        icon: "person.badge.key.fill",
                        tint: .blue,
                        isCreator: guardian.isCreator
                    )
                }
            } else if role == .child, let family = cloud.family {
                ForEach(family.children) { child in
                    cloudMemberRow(
                        name: child.displayName,
                        icon: "figure.child",
                        tint: .orange,
                        isCreator: false
                    )
                }
            } else {
                ForEach(store.familyNetwork.activeMembers(role: role)) { member in
                HStack(spacing: 12) {
                    Image(systemName: memberIcon(role))
                        .foregroundStyle(role == .guardian ? .blue : role == .relative ? .purple : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(member.displayName)
                            if member.id == store.familyNetwork.creatorMemberId {
                                Text("创建者")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.15), in: Capsule())
                            }
                        }
                        if let kinship = member.kinshipLabel {
                            Text(kinship)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if store.canManageFamilyMembership,
                       member.id != store.familyNetwork.creatorMemberId,
                       member.role != .child {
                        Button(role: .destructive) {
                            _ = store.revokeFamilyMember(member.id)
                        } label: {
                            Label("移除", systemImage: "person.crop.circle.badge.minus")
                        }
                    }
                }
                }
            }
        } header: {
            Text("\(title)（\(memberCount(for: role))）")
        } footer: {
            Text(footer)
        }
    }

    private func memberCount(for role: FamilyMemberRole) -> Int {
        if role == .guardian, let family = cloud.family { return family.guardians.count }
        if role == .child, let family = cloud.family { return family.children.count }
        return store.familyNetwork.activeMembers(role: role).count
    }

    private func cloudMemberRow(
        name: String,
        icon: String,
        tint: Color,
        isCreator: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(name)
            if isCreator {
                Text(lang.pick("创建者", "Creator"))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
            }
        }
    }

    private func createCloudInvite(kind: String, childId: String? = nil) {
        Task {
            do {
                presentedCloudInvite = try await cloud.issueInvite(kind: kind, childId: childId)
                cloudError = nil
            } catch {
                cloudError = error.localizedDescription
            }
        }
    }

    private func syncTasks() async {
        do {
            try await cloud.syncGuardianTasks(from: store)
            cloudError = nil
        } catch {
            cloudError = error.localizedDescription
        }
    }

    private func revokeCloudDevice(_ device: FamilyCloudSnapshot.Device) async {
        do {
            try await cloud.revokeDevice(device)
            cloudError = nil
        } catch {
            cloudError = error.localizedDescription
        }
    }

    private func memberIcon(_ role: FamilyMemberRole) -> String {
        switch role {
        case .guardian: return "person.badge.key.fill"
        case .relative: return "person.2.fill"
        case .child: return "figure.child"
        }
    }

}

private struct CloudFamilyJoinInviteView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let invite: FamilyCloudInvite

    private var lang: AppInterfaceLanguage { store.settings.resolvedParentInterfaceLanguage }

    var body: some View {
        VStack(spacing: 22) {
            Text(invite.kind == "child_device"
                 ? lang.pick("用孩子手机扫码", "Scan with the child's phone")
                 : lang.pick("用监护人手机扫码", "Scan with the guardian's phone"))
                .font(.title2.bold())
            if let image = FamilyQRCodeRenderer.image(for: invite.payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                ShareLink(item: invite.payload) {
                    Label(lang.pick("发送邀请", "Share invite"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            Text(lang.pick(
                "二维码十分钟内有效且只能使用一次。二维码中的密钥不会进入日志或普通本地设置。",
                "This QR code is valid for ten minutes and can be used once. Its secret is never stored in logs or regular settings."
            ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .navigationTitle(lang.pick("加入家庭", "Join Family"))
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(lang.pick("完成", "Done")) { dismiss() } } }
    }
}

enum FamilyQRCodeRenderer {
    static func image(for value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else {
            return nil
        }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
