import SwiftUI

/// 亲友/祖辈参与中心。
///
/// 亲友可以查看家长开放的成长摘要，也可以留一句本地待审核鼓励。
/// 页面不审批、不发成长积分、不写账本、不解锁设备、不通知亲友、不上传媒体、不接网络。
struct RelativeFamilyParticipationCenterView: View {
    @Environment(LocalFamilyStore.self) private var family
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @State private var draft: String = ""
    @State private var feedback: String?

    private let achievementStore: FamilyGrowthAchievementStore
    private let composer = MobileOfflineActionComposer()

    init(achievementStore: FamilyGrowthAchievementStore = FamilyGrowthAchievementStore()) {
        self.achievementStore = achievementStore
    }

    private var center: MobileRelativeFamilyParticipationCenter {
        MobileRelativeFamilyParticipationCenterBuilder(
            family: family,
            schoolFamily: schoolFamily,
            achievementStore: achievementStore,
            offlineOutbox: offlineOutbox
        )
        .build()
    }

    var body: some View {
        List {
            headerSection(center)
            summarySection(center)
            cardsSection(center)
            commentsSection(center)
            composeSection(center)
            boundariesSection(center)
            nextActionsSection(center)
        }
        .navigationTitle("亲友参与")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func headerSection(_ center: MobileRelativeFamilyParticipationCenter) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(center.status.label, systemImage: center.status == .blocked ? "shield.slash" : "heart.text.square")
                    .font(.headline)
                    .foregroundStyle(center.status == .blocked ? Color.orange : Color.green)
                Text(center.headline)
                    .font(.title3.bold())
                Text(center.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func summarySection(_ center: MobileRelativeFamilyParticipationCenter) -> some View {
        Section {
            LabeledContent("亲友成员") {
                Text("\(center.relativeCount)")
            }
            LabeledContent("成长动态") {
                Text("\(center.visibleFeedCount)")
            }
            LabeledContent("荣誉墙") {
                Text("\(center.visibleHonorCount)")
            }
            LabeledContent("已通过鼓励") {
                Text("\(center.approvedCommentCount)")
            }
            LabeledContent("本地待审核") {
                Text("\(center.pendingLocalCommentCount)")
            }
            if let score = center.abilityAverageScore {
                LabeledContent("能力快照均分") {
                    Text("\(score)")
                }
            }
        } header: {
            Text("可见摘要")
        } footer: {
            Text("这些数字来自本地脱敏快照，只代表亲友可见范围。")
        }
    }

    private func cardsSection(_ center: MobileRelativeFamilyParticipationCenter) -> some View {
        Section {
            if center.visibleCards.isEmpty {
                Text("暂无可见成长内容")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(center.visibleCards) { card in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(card.kindLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                            Spacer()
                            Text(card.occurredLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(card.title)
                            .font(.subheadline.weight(.semibold))
                        Text(card.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(card.supportiveCopy)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("亲友可见成长")
        }
    }

    private func commentsSection(_ center: MobileRelativeFamilyParticipationCenter) -> some View {
        Section {
            if center.comments.isEmpty {
                Text("暂无可见鼓励")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(center.comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(comment.authorLabel)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(comment.statusLabel)
                                .font(.caption2)
                                .foregroundStyle(comment.statusLabel.contains("待") ? Color.orange : Color.green)
                        }
                        Text(comment.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(comment.createdLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        } footer: {
            Text("待审核留言只在本机队列里，不会自动展示给其他亲友。")
        }
    }

    private func composeSection(_ center: MobileRelativeFamilyParticipationCenter) -> some View {
        Section {
            TextField("写给孩子的一句话", text: $draft, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityIdentifier("relative-family-compose-field")
            Button {
                sendComment()
            } label: {
                Label("加入待审核队列", systemImage: "paperplane")
            }
            .accessibilityIdentifier("relative-family-compose-submit")
            .disabled(center.status == .blocked || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let feedback {
                Label(feedback, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("relative-family-compose-feedback")
            }
        } header: {
            Text("留一句鼓励")
        } footer: {
            Text("留言只进入本地 outbox，联网后仍需家长审核；不会发成长积分、不会通知、不会解锁设备。")
        }
    }

    private func boundariesSection(_ center: MobileRelativeFamilyParticipationCenter) -> some View {
        Section {
            ForEach(center.boundaries) { boundary in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(boundary.title)
                            .font(.subheadline.weight(.semibold))
                        Text(boundary.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: boundary.isBlocked ? "lock.shield" : "eye")
                        .foregroundStyle(boundary.isBlocked ? Color.orange : Color.blue)
                }
            }
        } header: {
            Text("权限边界")
        }
    }

    private func nextActionsSection(_ center: MobileRelativeFamilyParticipationCenter) -> some View {
        Section {
            ForEach(center.nextActions) { action in
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                    Text(action.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("下一步")
        }
    }

    private func sendComment() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        let request = composer.relativeComment(
            targetSeed: "family-feed",
            relativeSeed: "relative-self",
            message: message
        )
        let result = offlineOutbox.enqueue(request)
        feedback = MobileOfflineEnqueueFeedback.message(
            for: result,
            successText: "已加入离线队列，等待家长审核"
        )
        if case .success = result {
            draft = ""
        }
    }
}
