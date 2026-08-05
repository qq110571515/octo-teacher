import SwiftUI

/// iOS 成长包自适应日程安全壳。
///
/// 本页只读展示本地今日计划，不打开系统日历/外链/相机/相册，不读取睡眠数据，
/// 不控制屏幕时间，不上传证明，不写账本，不发成长积分，也不兑换奖励。
struct MobileGrowthPackAdaptiveScheduleView: View {
    @State private var role: MobileGrowthPackExecutionHubRole
    private let allowedRoles: [MobileGrowthPackExecutionHubRole]
    private let input: MobileGrowthPackAdaptiveScheduleInput
    private let builder = MobileGrowthPackAdaptiveScheduleBuilder()

    init(
        initialRole: MobileGrowthPackExecutionHubRole = .child,
        allowedRoles: [MobileGrowthPackExecutionHubRole] = MobileGrowthPackExecutionHubRole.allCases,
        input: MobileGrowthPackAdaptiveScheduleInput = .mock
    ) {
        let normalized = Self.normalizedRoles(allowedRoles)
        let resolvedRole = normalized.contains(initialRole) ? initialRole : normalized[0]
        _role = State(initialValue: resolvedRole)
        self.allowedRoles = normalized
        self.input = input
    }

    private var schedule: MobileGrowthPackAdaptiveSchedule {
        builder.build(role: role, input: input)
    }

    var body: some View {
        List {
            roleSection
            overviewSection
            slotSection
            findingSection
            sideEffectSection
        }
        .navigationTitle("今日计划")
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
            Text(schedule.audienceNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var overviewSection: some View {
        Section(schedule.title) {
            Text(schedule.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            GrowthPackAdaptiveScheduleMetric(title: "现在适合", value: schedule.publicSummary.suitableNowCount, systemImage: "checkmark.circle")
            GrowthPackAdaptiveScheduleMetric(title: "现在不适合", value: schedule.publicSummary.notNowCount, systemImage: "moon.zzz")
            GrowthPackAdaptiveScheduleMetric(title: "补说明", value: schedule.publicSummary.evidenceGapCount, systemImage: "doc.badge.clock")
            if role == .guardian {
                GrowthPackAdaptiveScheduleMetric(title: "睡眠保护", value: schedule.publicSummary.sleepConflictCount, systemImage: "bed.double")
                GrowthPackAdaptiveScheduleMetric(title: "作业优先", value: schedule.publicSummary.homeworkConflictCount, systemImage: "book.closed")
                GrowthPackAdaptiveScheduleMetric(title: "奖励窗口", value: schedule.publicSummary.rewardConflictCount, systemImage: "gift")
                GrowthPackAdaptiveScheduleMetric(title: "需复核", value: schedule.publicSummary.guardianReviewCount, systemImage: "person.badge.shield.checkmark")
            }
        }
    }

    private var slotSection: some View {
        Section("今日排期") {
            if schedule.slots.isEmpty {
                ContentUnavailableView("日程已隐藏", systemImage: "lock.shield")
            } else {
                ForEach(schedule.slots) { slot in
                    GrowthPackAdaptiveScheduleRow(slot: slot)
                }
            }
        }
    }

    private var findingSection: some View {
        Section("安全提示") {
            if schedule.findings.isEmpty {
                Text("暂无风险提示")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(schedule.findings) { finding in
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
                }
            }
        }
    }

    private var sideEffectSection: some View {
        Section("执行边界") {
            GrowthPackAdaptiveScheduleBoundaryFlag(title: "网络 / AI / 本地模型", value: schedule.publicSummary.callsNetwork || schedule.publicSummary.callsAiProvider || schedule.publicSummary.callsLocalModel)
            GrowthPackAdaptiveScheduleBoundaryFlag(title: "系统日历 / 睡眠数据 / 屏幕时间", value: schedule.publicSummary.opensSystemCalendar || schedule.publicSummary.readsHealthKit || schedule.publicSummary.controlsScreenTime)
            GrowthPackAdaptiveScheduleBoundaryFlag(title: "账本 / 成长积分 / 设备", value: schedule.publicSummary.writesLedger || schedule.publicSummary.grantsCredit || schedule.publicSummary.unlocksDevice)
            GrowthPackAdaptiveScheduleBoundaryFlag(title: "链接 / 相机 / 上传", value: schedule.publicSummary.opensExternalLink || schedule.publicSummary.opensCamera || schedule.publicSummary.opensPhotoLibrary || schedule.publicSummary.opensFilePicker || schedule.publicSummary.uploadsMedia)
            GrowthPackAdaptiveScheduleBoundaryFlag(title: "发布 / 订单 / 权益 / 通知", value: schedule.publicSummary.publishesContent || schedule.publicSummary.createsOrder || schedule.publicSummary.writesEntitlement || schedule.publicSummary.sendsNotification)
        }
    }

    private static func normalizedRoles(_ roles: [MobileGrowthPackExecutionHubRole]) -> [MobileGrowthPackExecutionHubRole] {
        let source = roles.isEmpty ? MobileGrowthPackExecutionHubRole.allCases : roles
        return MobileGrowthPackExecutionHubRole.allCases.filter { source.contains($0) }
    }
}

private struct GrowthPackAdaptiveScheduleRow: View {
    let slot: MobileGrowthPackAdaptiveScheduleSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 24)
                Text(slot.title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(slot.windowLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(slot.status.label)
                    .font(.caption2.bold())
                    .foregroundStyle(tint)
            }
            if !slot.detail.isEmpty {
                Text(slot.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !slot.reasonNotNow.isEmpty {
                Label(slot.reasonNotNow, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !slot.nextStep.isEmpty {
                Label(slot.nextStep, systemImage: "arrow.forward.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label(slot.safetyNote, systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var icon: String {
        switch slot.kind {
        case .growthPackStep: return "square.stack.3d.up"
        case .schoolHomework: return "book.closed"
        case .habitChore: return "checklist"
        case .evidenceReview: return "doc.text.magnifyingglass"
        case .familyCalendar: return "calendar"
        case .sleepQuietWindow: return "moon.zzz"
        case .rewardWindow: return "gift"
        case .reviewCadence: return "arrow.triangle.2.circlepath"
        }
    }

    private var tint: Color {
        switch slot.status {
        case .suitableNow: return .green
        case .later: return .blue
        case .notNow: return .orange
        case .waitingReview: return .orange
        case .blocked: return .red
        }
    }
}

private struct GrowthPackAdaptiveScheduleMetric: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        LabeledContent {
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct GrowthPackAdaptiveScheduleBoundaryFlag: View {
    let title: String
    let value: Bool

    var body: some View {
        LabeledContent(title, value: value ? "会" : "不会")
            .foregroundStyle(value ? .red : .primary)
    }
}
