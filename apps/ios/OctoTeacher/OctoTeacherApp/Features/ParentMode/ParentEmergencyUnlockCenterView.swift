import SwiftUI

struct ParentEmergencyUnlockCenterView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(FamilyCloudSessionStore.self) private var cloud
    @State private var processingChildID: UUID?
    @State private var feedback: String?

    private var language: AppInterfaceLanguage { family.settings.resolvedParentInterfaceLanguage }

    private var requests: [(child: ChildProfile, emergency: FamilyScreenTimeEmergency)] {
        family.children.compactMap { child in
            guard let emergency = cloud.screenTimeEmergency(for: child.id), emergency.status != .idle else {
                return nil
            }
            return (child, emergency)
        }
        .sorted { ($0.emergency.updatedAt) > ($1.emergency.updatedAt) }
    }

    private var pending: [(child: ChildProfile, emergency: FamilyScreenTimeEmergency)] {
        requests.filter { $0.emergency.status == .requested }
    }

    var body: some View {
        List {
            if pending.isEmpty {
                ContentUnavailableView(
                    language.pick("没有待处理申请", "No Pending Requests"),
                    systemImage: "checkmark.shield",
                    description: Text(language.pick(
                        "学校模式下，孩子申请紧急解锁后会出现在这里。",
                        "School-mode emergency requests appear here."
                    ))
                )
            } else {
                Section(language.pick("等待家长决定", "Waiting for a Parent")) {
                    ForEach(pending, id: \.child.id) { item in
                        requestCard(child: item.child, emergency: item.emergency)
                    }
                }
            }

            if let feedback {
                Section {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let history = requests.filter { $0.emergency.status != .requested }.prefix(20)
            if !history.isEmpty {
                Section(language.pick("最近记录", "Recent Activity")) {
                    ForEach(Array(history), id: \.child.id) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.child.name)
                                Text(item.emergency.reason ?? language.pick("学校紧急解锁", "School emergency access"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(statusText(item.emergency.status))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusColor(item.emergency.status))
                        }
                    }
                }
            }
        }
        .navigationTitle(language.pick("紧急解锁审批", "Emergency Access"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                await cloud.bootstrap()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func requestCard(child: ChildProfile, emergency: FamilyScreenTimeEmergency) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(child.name).font(.headline)
            Text(emergency.reason ?? language.pick("孩子申请学校模式紧急解锁。", "The child requested emergency access during School Mode."))
                .font(.subheadline)
            Text(language.pick(
                "批准后，孩子可在 10 分钟内启用；启用后全部 App 临时开放 \(emergency.minutes ?? 30) 分钟，然后自动恢复学校锁定。",
                "After approval, the child has 10 minutes to start. All apps then open for \(emergency.minutes ?? 30) minutes before School Mode relocks them."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                Button(language.pick("批准", "Approve")) {
                    decide(child: child, emergency: emergency, approve: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(processingChildID != nil)
                .accessibilityIdentifier("emergency-unlock-approve-\(child.id.uuidString.lowercased())")

                Button(language.pick("拒绝", "Deny"), role: .destructive) {
                    decide(child: child, emergency: emergency, approve: false)
                }
                .buttonStyle(.bordered)
                .disabled(processingChildID != nil)
                .accessibilityIdentifier("emergency-unlock-deny-\(child.id.uuidString.lowercased())")

                if processingChildID == child.id { ProgressView() }
            }
        }
        .padding(.vertical, 4)
    }

    private func decide(child: ChildProfile, emergency: FamilyScreenTimeEmergency, approve: Bool) {
        guard let requestId = emergency.requestId else { return }
        processingChildID = child.id
        feedback = nil
        Task {
            do {
                _ = try await cloud.decideGuardianScreenTimeEmergency(
                    for: child.id,
                    requestId: requestId,
                    approve: approve,
                    minutes: min(60, emergency.minutes ?? 30)
                )
                feedback = language.pick(
                    approve ? "已批准，等待孩子启用。" : "已拒绝这次申请。",
                    approve ? "Approved. Waiting for the child to start." : "The request was denied."
                )
            } catch {
                feedback = error.localizedDescription
                await cloud.bootstrap()
            }
            processingChildID = nil
        }
    }

    private func statusText(_ status: FamilyScreenTimeEmergencyStatus) -> String {
        switch status {
        case .idle: return language.pick("无申请", "Idle")
        case .requested: return language.pick("等待决定", "Waiting")
        case .approved: return language.pick("已批准", "Approved")
        case .active: return language.pick("使用中", "Active")
        case .denied: return language.pick("已拒绝", "Denied")
        case .expired: return language.pick("已过期", "Expired")
        case .completed: return language.pick("已结束", "Completed")
        }
    }

    private func statusColor(_ status: FamilyScreenTimeEmergencyStatus) -> Color {
        switch status {
        case .requested: return .orange
        case .approved, .active: return .green
        case .denied: return .red
        case .idle, .expired, .completed: return .secondary
        }
    }
}
