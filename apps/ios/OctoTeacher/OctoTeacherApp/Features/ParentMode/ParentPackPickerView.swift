import SwiftUI

/// 家长从任务包库批量布置任务。
///
/// 结构：包类型列表 → 包详情勾选模板 → 一键布置。
/// 模板是官方种子，成长积分为建议值；需要自定义细节时用「布置新任务」表单。
struct ParentPackPickerView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud

    var body: some View {
        List {
            featuredEveningPlanSection

            Section("全部任务包") {
                ForEach(ParentPackTemplateLibrary.groups) { group in
                    NavigationLink {
                        ParentPackWorkbenchView(group: group)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: group.packType.systemImage)
                                .font(.title3)
                                .frame(width: 32)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.title)
                                    .font(.headline)
                                Text(group.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityIdentifier("pack-group-\(group.id)")
                }
            }
        }
        .navigationTitle("任务包库")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 库首位的「首日晚间节律包」：不用逐个勾选，一键布置 4 件小事。
    private var featuredEveningPlanSection: some View {
        let planAssignedToday = store.hasAssignedFirstEveningRoutinePlan()

        return Section {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.title3)
                    .frame(width: 32)
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text(FirstEveningRoutinePlan.title)
                        .font(.headline)
                    Text(FirstEveningRoutinePlan.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            if planAssignedToday {
                Label("今天已经布置过了，明天可以再来一次。", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("pack-first-evening-plan-done")
            } else {
                Button {
                    let existingIDs = Set(store.assignments.map(\.id))
                    let count = store.assignFirstEveningRoutinePlan()
                    let createdIDs = store.assignments.map(\.id).filter { !existingIDs.contains($0) }
                    if count > 0, familyCloud.isGuardianSignedIn {
                        _ = familyCloud.queueGuardianTaskUpserts(
                            assignmentIds: createdIDs,
                            local: store
                        )
                    }
                } label: {
                    Label("给\(store.child.name)一键布置这 4 件小事", systemImage: "wand.and.stars")
                        .font(.headline)
                }
                .accessibilityIdentifier("pack-first-evening-plan-assign")
            }
        } header: {
            Text("今晚推荐")
        }
    }
}

/// 单个任务包详情：勾选模板并批量布置。
struct ParentPackGroupDetailView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(\.dismiss) private var dismiss

    let group: PackTemplateGroup

    @State private var selectedIds: Set<String> = []
    @State private var assignedMessage: String?

    private var templates: [PackTaskTemplate] {
        store.templates(for: group.packType)
    }

    private var selectedTemplates: [PackTaskTemplate] {
        templates.filter { selectedIds.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                ForEach(templates) { template in
                    Button {
                        toggle(template)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedIds.contains(template.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIds.contains(template.id) ? Color.accentColor : Color.secondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(template.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if template.adultSupervisionRequired {
                                        Label("需要大人在场", systemImage: "figure.and.child.holdinghands")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.orange.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.orange)
                                    }
                                    if template.isCustom {
                                        Text("自定义")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.blue.opacity(0.12), in: Capsule())
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Text(template.instructions)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 10) {
                                    Label("\(template.suggestedRewardMinutes) 积分", systemImage: "leaf.fill")
                                    if let expectedMinutes = template.expectedMinutes {
                                        Label("\(expectedMinutes) 分钟", systemImage: "clock")
                                    }
                                    Label(template.requiredProof.label, systemImage: template.requiredProof == .photo ? "camera" : "text.bubble")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if template.isCustom {
                            Button(role: .destructive) {
                                selectedIds.remove(template.id)
                                _ = store.removeCustomPackTemplate(id: template.id, from: group.packType)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    .accessibilityIdentifier("pack-template-\(template.id)")
                }
            } header: {
                Text(group.summary)
            } footer: {
                if group.packType == .financeLiteracy {
                    Text("金融任务只做记录和模拟，真实买卖由大人在 App 外完成。")
                } else if group.packType.supportsCustomTemplates {
                    Text("自定义任务会保存到这个家庭的任务包里；左滑自定义条目可以删除。")
                }
            }

            Section {
                Button {
                    assignSelected()
                } label: {
                    Text(selectedIds.isEmpty ? "先勾选上面的任务" : "布置所选的 \(selectedIds.count) 个任务")
                        .frame(maxWidth: .infinity)
                }
                .disabled(selectedIds.isEmpty)
                .accessibilityIdentifier("pack-assign-selected")
            } footer: {
                Text("布置后会出现在孩子的今日任务里，成长积分可在任务编辑里调整。")
            }
        }
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let assignedMessage {
                Text(assignedMessage)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }

    private func toggle(_ template: PackTaskTemplate) {
        if selectedIds.contains(template.id) {
            selectedIds.remove(template.id)
        } else {
            selectedIds.insert(template.id)
        }
    }

    private func assignSelected() {
        let assignmentIDsBeforeSave = Set(store.assignments.map(\.id))
        let count = store.assignPackTemplates(selectedTemplates, packType: group.packType)
        guard count > 0 else { return }
        let createdAssignmentIDs = store.assignments.map(\.id).filter { !assignmentIDsBeforeSave.contains($0) }
        if familyCloud.isGuardianSignedIn,
           !familyCloud.queueGuardianTaskUpserts(assignmentIds: createdAssignmentIDs, local: store) {
            assignedMessage = "任务已保存在本机，但还没有进入家庭云同步队列。"
            return
        }
        assignedMessage = "已布置 \(count) 个任务"
        selectedIds.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            dismiss()
        }
    }
}
