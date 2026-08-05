import SwiftUI

/// iOS 亲友创作评论/鼓励安全壳页面。
///
/// 只消费本地 mock 投影，不发布评论、不通知亲友或孩子、不发成长积分、不解锁设备。
struct MobileRelativeCreativeCommentSafetyWorkbenchView: View {
    @State private var role: MobileRelativeCreativeCommentViewerRole
    private let allowedRoles: [MobileRelativeCreativeCommentViewerRole]

    init(
        initialRole: MobileRelativeCreativeCommentViewerRole = .child,
        allowedRoles: [MobileRelativeCreativeCommentViewerRole] = MobileRelativeCreativeCommentViewerRole.allCases
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
    }

    private var workbench: MobileRelativeCreativeCommentSafetyWorkbench {
        MobileRelativeCreativeCommentSafetyBuilder().build(role: role)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            commentSection
            emotionalSafetyCenterSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("亲友鼓励")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var roleSection: some View {
        Section {
            if allowedRoles.count > 1 {
                Picker("视角", selection: $role) {
                    ForEach(allowedRoles, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(workbench.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(workbench.title) {
            Text(workbench.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            RelativeCreativeCommentMetric(title: "可见互动", value: workbench.publicSummary.visibleCommentCount, systemImage: "bubble.left.and.bubble.right")
                .accessibilityIdentifier("relative-comment-metric-visible")
            if role == .guardian {
                RelativeCreativeCommentMetric(title: "待审核", value: workbench.publicSummary.waitingReviewCount, systemImage: "person.badge.shield.checkmark")
                    .accessibilityIdentifier("relative-comment-metric-waiting-review")
                RelativeCreativeCommentMetric(title: "孩子隐藏", value: workbench.publicSummary.hiddenFromChildCount, systemImage: "eye.slash")
                    .accessibilityIdentifier("relative-comment-metric-hidden-child")
                RelativeCreativeCommentMetric(title: "已阻断", value: workbench.publicSummary.blockedCount, systemImage: "lock.shield")
                    .accessibilityIdentifier("relative-comment-metric-blocked")
                RelativeCreativeCommentMetric(title: "奖励压力", value: workbench.publicSummary.rewardPressureBlockedCount, systemImage: "creditcard.trianglebadge.exclamationmark")
                    .accessibilityIdentifier("relative-comment-metric-reward-pressure")
            }
        }
    }

    private var commentSection: some View {
        Section("互动摘要") {
            if workbench.comments.isEmpty {
                ContentUnavailableView("暂无可见互动", systemImage: "lock")
            } else {
                ForEach(workbench.comments) { comment in
                    RelativeCreativeCommentRow(comment: comment)
                }
            }
        }
    }

    private var emotionalSafetyCenterSection: some View {
        Section("家庭社交反馈情绪安全中心") {
            NavigationLink {
                MobileFamilySocialFeedbackEmotionalSafetyCenterView(
                    initialRole: role == .child ? .child : .guardian,
                    allowedRoles: role == .child ? [.child] : [.guardian, .relative, .expert]
                )
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .child ? "看看家人和老师的支持到哪一步了" : "复核社交反馈情绪安全与审核状态")
                            .font(.subheadline.weight(.semibold))
                        Text(role == .child
                            ? "把家人和老师想给你的支持放在一起看；这里只读，看到的都是温和的话，要等家长看过再说。"
                            : "只读复核亲友评论、荣誉墙反馈、成长动态、日记 / VLOG 摘要、专家 / 家长讨论和通知预览的情绪安全、审核状态、撤回 / 删除、亲友撤权、压力语言和最小披露风险。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(.pink)
                }
            }
            .accessibilityIdentifier("relative-comment-link-emotional-safety")
        }
    }

    private var findingSection: some View {
        Section(role == .relative ? "表达边界" : "安全提示") {
            if workbench.findings.isEmpty {
                Text(role == .relative ? "当前没有可公开提示" : "暂无风险提示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(workbench.findings) { finding in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.code.rawValue)
                                .font(.caption.bold())
                            Text(finding.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: finding.actionRequired ? "exclamationmark.shield" : "checkmark.shield")
                            .foregroundStyle(finding.actionRequired ? .orange : .green)
                    }
                    .accessibilityIdentifier("relative-comment-finding-\(finding.code.rawValue)")
                }
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            RelativeCreativeCommentBoundaryFlag(title: "评论发布/审核", value: workbench.publicSummary.publishesComment || workbench.publicSummary.approvesComment)
            RelativeCreativeCommentBoundaryFlag(title: "通知", value: workbench.publicSummary.sendsNotification)
            RelativeCreativeCommentBoundaryFlag(title: "相机/相册/文件", value: workbench.publicSummary.opensCamera || workbench.publicSummary.opensPhotoLibrary || workbench.publicSummary.opensFilePicker)
            RelativeCreativeCommentBoundaryFlag(title: "上传/网络/平台", value: workbench.publicSummary.uploadsMedia || workbench.publicSummary.callsNetwork || workbench.publicSummary.writesSocialPlatform)
            RelativeCreativeCommentBoundaryFlag(title: "账本/成长积分/设备", value: workbench.publicSummary.writesLedger || workbench.publicSummary.grantsCredit || workbench.publicSummary.unlocksDevice)
        }
    }

    private static func normalizedRoles(
        _ roles: [MobileRelativeCreativeCommentViewerRole]
    ) -> [MobileRelativeCreativeCommentViewerRole] {
        let source = roles.isEmpty ? MobileRelativeCreativeCommentViewerRole.allCases : roles
        return MobileRelativeCreativeCommentViewerRole.allCases.filter { source.contains($0) }
    }
}

private struct RelativeCreativeCommentRow: View {
    let comment: MobileRelativeCreativeCommentRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(comment.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(comment.state.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }

            Text(comment.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Label(comment.authorLabel, systemImage: "person.2")
                Label(comment.reviewLabel, systemImage: "checkmark.shield")
                Label(comment.privacyLabel, systemImage: "eye")
                Label(comment.emotionalSafetyLabel, systemImage: "heart")
                Label(comment.rewardBoundaryLabel, systemImage: "creditcard")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Label(comment.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(comment.nextStep, systemImage: "arrow.forward.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("relative-comment-row-\(comment.state.rawValue)")
    }

    private var tint: Color {
        switch comment.state {
        case .approvedEncouragement: return .blue
        case .waitingGuardianReview: return .orange
        case .hiddenFromChild: return .secondary
        case .blocked: return .red
        }
    }
}

private struct RelativeCreativeCommentMetric: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        LabeledContent {
            Text("\(value)").monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct RelativeCreativeCommentBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title) {
            Text(value ? "会触发" : "不触发")
                .foregroundStyle(value ? .red : .green)
        }
    }
}
