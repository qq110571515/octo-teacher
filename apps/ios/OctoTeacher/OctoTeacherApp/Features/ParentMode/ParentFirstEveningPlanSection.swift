import SwiftUI

/// 家长工作台首屏的「今晚先这样开始」引导卡（C-PARENT-001）。
///
/// 针对「孩子沉迷手机 + 不睡觉 + 不做家务」的首日行动引导：
/// 三步话术 + 一键布置「首日晚间节律包」（家务/阅读/户外/睡前放手机各 1 件）。
/// 按天去重：当天已布置则显示完成状态，第二天自动恢复可用。
struct ParentFirstEveningPlanSection: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(FamilyCloudSessionStore.self) private var familyCloud

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        let planAssignedToday = store.hasAssignedFirstEveningRoutinePlan()

        Section {
            if planAssignedToday {
                Label(
                    lang.pick("今晚的计划已布置", "Tonight's plan is ready"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .accessibilityIdentifier("parent-mode-first-evening-plan-done")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang.pick("不知道先布置什么？", "Not sure where to start?"))
                        .font(.subheadline.weight(.semibold))
                    Text(lang.pick(
                        "用一套轻量晚间计划开始：家务、阅读、户外和按时放下手机。",
                        "Start with a light evening plan: chores, reading, outdoor time, and putting the phone away."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("parent-mode-first-evening-plan-steps")

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
                    Label(
                        lang.pick("给\(store.child.name)布置今晚计划", "Assign tonight's plan to \(store.childDisplayName(store.child, for: .english))"),
                        systemImage: "moon.stars.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("parent-mode-first-evening-plan-assign")
            }
        } header: {
            Text(lang.pick("新手建议", "Starter Suggestion"))
        }
    }
}
