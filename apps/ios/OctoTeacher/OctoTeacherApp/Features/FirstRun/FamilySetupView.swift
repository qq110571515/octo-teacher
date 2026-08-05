import SwiftUI

/// 首次启动的家庭设置：由家长完成，孩子昵称 + 每日奖励上限 + 是否保留推荐任务。
/// 完成后进入正常使用；数据只存本机。
struct FamilySetupView: View {
    @Environment(LocalFamilyStore.self) private var store
    /// 完成回调：由外层写入「已完成首次设置」标记并关闭本页。
    let onFinished: () -> Void

    @State private var childName = ""
    @State private var dailyLimitMinutes = 60
    @State private var keepStarterTasks = true
    @State private var mode: FamilySetupMode = .create
    @State private var isShowingScanner = false
    @State private var pastedInvite = ""
    @State private var validatedCloudInvite: FamilyCloudJoinPayload?
    @State private var inviteFeedback: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(BrandIdentity.logoAssetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(BrandIdentity.systemLanguage == .english ? "Welcome to Octo Teacher" : "欢迎使用章鱼老师")
                                .font(.title3.bold())
                        }
                        Text(BrandIdentity.systemTagline)
                            .font(.subheadline.weight(.semibold))
                        Text("孩子完成任务，家长确认后获得成长积分。成长积分可以兑换屏幕时间、零花钱或愿望。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("开始方式", selection: $mode) {
                        ForEach(FamilySetupMode.allCases, id: \.self) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .create {
                    Section("孩子怎么称呼") {
                        TextField("孩子的昵称，例如：乐乐", text: $childName)
                            .accessibilityIdentifier("family-setup-child-name")
                    }

                    Section {
                        Picker("每天最多可兑换", selection: $dailyLimitMinutes) {
                            ForEach([15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 600, 720], id: \.self) { minutes in
                                Text(minutes >= 60 && minutes.isMultiple(of: 60) ? "\(minutes / 60) 小时" : "\(minutes) 分钟")
                                    .tag(minutes)
                            }
                        }
                    } header: {
                        Text("每日屏幕时间上限")
                    } footer: {
                        Text("孩子用成长积分兑换屏幕时间，每天不超过这个上限。之后可以调整。")
                    }

                    Section {
                        Toggle("放入 3 个推荐任务", isOn: $keepStarterTasks)
                    } footer: {
                        Text("阅读 15 分钟、整理书桌、运动 20 分钟。关掉则从空白开始，由你自己布置。")
                    }

                    Section {
                        Button {
                            finishSetup()
                        } label: {
                            Text("创建家庭并开始")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("family-setup-finish")
                    } footer: {
                        Text("当前数据只保存在这台手机上，不会上传。")
                    }
                } else {
                    Section {
                        Button {
                            isShowingScanner = true
                        } label: {
                            Label("扫描家庭二维码", systemImage: "qrcode.viewfinder")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        TextField("也可以粘贴邀请内容", text: $pastedInvite, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("验证邀请") {
                            validateInvite(pastedInvite)
                        }
                        .disabled(pastedInvite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: {
                        Text("加入已有家庭")
                    } footer: {
                        Text("成人与孩子都不需要在这里新建邮箱账号。家庭创建者生成对应角色的二维码即可。")
                    }

                    if let payload = validatedCloudInvite {
                        Section("云家庭邀请") {
                            LabeledContent("角色", value: payload.isGuardian ? "监护人" : "孩子手机")
                            FamilyCloudAccountView(pendingInvite: payload) {
                                onFinished()
                            }
                        }
                    }
                    if let inviteFeedback {
                        Section {
                            Text(inviteFeedback)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("开始之前")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $isShowingScanner) {
            FamilyJoinScannerView { value in
                pastedInvite = value
                validateInvite(value)
            }
        }
    }

    private func finishSetup() {
        store.applyFamilySetup(
            childName: childName,
            dailyLimitMinutes: dailyLimitMinutes,
            keepStarterTasks: keepStarterTasks
        )
        onFinished()
    }

    private func validateInvite(_ rawValue: String) {
        if let payload = FamilyCloudJoinPayload.decode(rawValue) {
            validatedCloudInvite = payload
            inviteFeedback = nil
            return
        }
        validatedCloudInvite = nil
        inviteFeedback = "这不是有效的云家庭二维码，请让家庭创建者重新生成。"
    }
}

private enum FamilySetupMode: CaseIterable {
    case create
    case join

    var label: String {
        switch self {
        case .create: return "创建家庭"
        case .join: return "扫码加入"
        }
    }
}
