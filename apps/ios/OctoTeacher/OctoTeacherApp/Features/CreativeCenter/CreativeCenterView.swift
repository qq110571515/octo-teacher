import SwiftUI

struct ParentCreativeCenterView: View {
    @Environment(LocalFamilyStore.self) private var store
    @State private var selectedKind: CreativeTaskKind?

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    private var snapshot: CreativeCenterSnapshot {
        .build(assignments: store.assignments, childId: store.activeChildId)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(lang.pick("把想法变成作品", "Turn Ideas into Creations"), systemImage: "paintpalette.fill")
                        .font(.headline)
                        .foregroundStyle(.purple)
                    Text(lang.pick(
                        "家长给一个清楚但不替孩子决定答案的创作提示；孩子可以拍作品、录语音或写说明，小伙伴先给鼓励式点评，再由家长确认和发放成长积分。",
                        "Give a clear prompt without deciding the answer. Children can photograph, record, or describe their work; the AI buddy encourages first, then a parent reviews and awards growth points."
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        CreativeMetric(value: snapshot.active.count, label: lang.pick("进行中", "Active"), color: .blue)
                        CreativeMetric(value: snapshot.waitingForParent.count, label: lang.pick("待确认", "To Review"), color: .orange)
                        CreativeMetric(value: snapshot.completed.count, label: lang.pick("已收藏", "Saved"), color: .green)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(CreativeTaskKind.allCases) { kind in
                    Button {
                        selectedKind = kind
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.systemImage)
                                .foregroundStyle(.purple)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(kind.label(for: lang))
                                    .foregroundStyle(.primary)
                                Text(kind.starterTitle(for: lang))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .accessibilityIdentifier("parent-creative-create-\(kind.rawValue)")
                }
            } header: {
                Text(lang.pick("快速创建", "Quick Create"))
            } footer: {
                Text(lang.pick(
                    "点一种创作，会自动填好孩子能理解的起步模板；标题、材料、时长、积分和安全要求都能继续修改。",
                    "Choose a creation type to start with a child-friendly template. You can still edit its title, materials, duration, points, and safety needs."
                ))
            }

            creativeAssignmentSection(
                title: lang.pick("等待家长确认", "Waiting for Parent Review"),
                assignments: snapshot.waitingForParent,
                emptyText: lang.pick("孩子提交作品后，会连同小伙伴初评一起出现在这里。", "Submitted work and the AI buddy's first review will appear here.")
            )
            creativeAssignmentSection(
                title: lang.pick("进行中的创作", "Active Creations"),
                assignments: snapshot.active,
                emptyText: lang.pick("还没有进行中的创作任务。", "There are no active creation tasks yet.")
            )
            creativeAssignmentSection(
                title: lang.pick("作品回顾", "Creation Review"),
                assignments: snapshot.completed,
                emptyText: lang.pick("家长批准后的作品会留在这里，并进入成长记录。", "Parent-approved work stays here and enters the growth record.")
            )
        }
        .navigationTitle(lang.pick("创作广场", "Creation Plaza"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedKind) { kind in
            NavigationStack {
                ParentTaskComposerView(creativeStarterKind: kind)
            }
        }
    }

    @ViewBuilder
    private func creativeAssignmentSection(
        title: String,
        assignments: [TaskAssignment],
        emptyText: String
    ) -> some View {
        Section(title) {
            if assignments.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(assignments) { assignment in
                    CreativeWorkRow(assignment: assignment, showParentSummary: true)
                }
            }
        }
    }
}

struct ChildCreativeCenterView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage

    private var snapshot: CreativeCenterSnapshot {
        .build(assignments: store.assignments, childId: store.activeChildId)
    }

    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(loc.pick("我的创作空间", "My Creation Space"), systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.purple)
                    Text(loc.pick(
                        "画、搭、做、演、拍、讲都可以。作品不用和别人一样，完成后拍照或录语音，小伙伴和大人都会看到。",
                        "Draw, build, make, perform, photograph, or tell a story. Your work doesn't have to match anyone else's — photograph it or record a voice note, and your buddy and grown-ups will see it."
                    ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SpeakButton(text: loc.pick(
                        "这是你的创作广场。画画、音乐、手工、积木、乐高、玩具、故事、摄影、黏土和表演都可以放在这里。作品不用和别人一样。",
                        "This is your Creation Plaza. Drawing, music, crafts, blocks, LEGO, toys, stories, photography, clay, and performances all belong here. Your work doesn't have to match anyone else's."
                    ), language: loc.language)
                }
                .padding(.vertical, 4)
            }

            Section(loc.pick("等你开始", "Waiting for You")) {
                if snapshot.active.isEmpty {
                    Text(loc.pick(
                        "暂时没有新的创作任务。可以先看看自己的作品。",
                        "No new creative tasks right now. Take a look at your works first."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.active) { assignment in
                        NavigationLink {
                            TaskDetailView(assignment: assignment)
                        } label: {
                            CreativeWorkRow(assignment: assignment, showParentSummary: false)
                        }
                        .accessibilityIdentifier("child-creative-task-\(assignment.id)")
                    }
                }
            }

            Section(loc.pick("等大人确认", "Waiting for a Grown-up")) {
                if snapshot.waitingForParent.isEmpty {
                    Text(loc.pick("交出的作品会先放在这里。", "Handed-in works wait here first."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.waitingForParent) { assignment in
                        CreativeWorkRow(assignment: assignment, showParentSummary: false)
                    }
                }
            }

            Section(loc.pick("我的作品", "My Works")) {
                if snapshot.completed.isEmpty {
                    Text(loc.pick("家长确认后的作品会收藏在这里。", "Works confirmed by a parent are collected here."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.completed) { assignment in
                        CreativeWorkRow(assignment: assignment, showParentSummary: false)
                    }
                }
            }
        }
        .navigationTitle(loc.pick("创作广场", "Creation Plaza"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CreativeMetric: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CreativeWorkRow: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    let assignment: TaskAssignment
    let showParentSummary: Bool

    private var kind: CreativeTaskKind { CreativeCenterCopy.kind(for: assignment.task) }

    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            workThumbnail
            VStack(alignment: .leading, spacing: 4) {
                Label(kind.label(for: loc.language), systemImage: kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                Text(assignment.task.displayTitle(for: loc.language))
                    .font(.subheadline.weight(.semibold))
                if let creative = assignment.task.creative {
                    Text(loc.pick(
                        "约 \(creative.estimatedMinutes) 分钟 · \(GrowthCreditCopy.label(points: assignment.task.rewardMinutes))",
                        "About \(creative.estimatedMinutes) min · \(GrowthCreditCopy.label(points: assignment.task.rewardMinutes, language: .english))"
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showParentSummary, let review = assignment.aiReview {
                    Text(loc.pick("小伙伴初评：\(review.summary)", "Buddy's first look: \(review.summary)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else if assignment.status == .submitted || assignment.status == .approved || assignment.status == .rejected {
                    Text(CreativeCenterCopy.childFeedback(for: assignment, language: loc.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var workThumbnail: some View {
        if let fileName = assignment.proof.photoFileName,
           let image = ProofPhotoStore.shared.loadImage(fileName: fileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: kind.systemImage)
                .font(.title2)
                .foregroundStyle(.purple)
                .frame(width: 58, height: 58)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
