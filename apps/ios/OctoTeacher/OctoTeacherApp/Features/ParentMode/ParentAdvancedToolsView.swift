import SwiftUI

/// 家长端「更多功能与预览」：收纳所有高级工作台与只读审计视图。
///
/// 家长日常审批、布置任务都在家长工作台第一屏完成；这里的模块面向
/// 后续版本的深度能力，当前多为本地预览，不影响核心闭环。
struct ParentAdvancedToolsView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(SchoolFamilyStore.self) private var schoolFamily
    @Environment(MockScreenTimeController.self) private var screenTime
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(MobileOfflineReplayStore.self) private var offlineReplay
    @Environment(MobileCreditSettlementStore.self) private var creditSettlement
    @Environment(GrowthPackRuntimeStore.self) private var growthRuntime
    @Environment(GrowthEvidenceTimelineStore.self) private var evidenceTimeline
    @State private var isPlanningExpanded = false
    @State private var isAuditExpanded = false

    private var lang: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    private let everydayTools: [ParentModeQuickAccess] = [
        .todayTaskReview,
        .basicHabitChore,
        .approvalInbox,
        .creditLedgerReview,
        .reportsPreview
    ]

    private var planningTools: [ParentModeQuickAccess] {
        ParentModeQuickAccess.ordered.filter { !everydayTools.contains($0) }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ParentSchoolModeView()
                } label: {
                    Label(
                        store.settings.resolvedParentInterfaceLanguage.pick("学校模式与时间表", "School Mode & Schedule"),
                        systemImage: "calendar.badge.clock"
                    )
                }
                .accessibilityIdentifier("parent-mode-school-mode")

                NavigationLink {
                    ScreenTimeDebugView()
                } label: {
                    Label(lang.pick("屏幕时间控制", "Screen Time Controls"), systemImage: "lock.shield")
                }
                .accessibilityIdentifier("parent-mode-screen-time-debug")

                NavigationLink {
                    ParentWebsiteSafetyView()
                } label: {
                    Label(lang.pick("网站安全", "Website Safety"), systemImage: "network.badge.shield.half.filled")
                }
                .accessibilityIdentifier("parent-mode-website-safety")

                NavigationLink {
                    ParentEmergencyUnlockCenterView()
                } label: {
                    Label(lang.pick("紧急解锁", "Emergency Unlock"), systemImage: "lock.open.trianglebadge.exclamationmark")
                }
                .accessibilityIdentifier("parent-mode-emergency-unlocks")
            } header: {
                Text(lang.pick("设备与安全", "Devices & Safety"))
            }

            Section {
                ForEach(everydayTools, id: \.self) { item in
                    NavigationLink {
                        quickAccessDestination(for: item)
                    } label: {
                        quickAccessRow(for: item)
                    }
                    .accessibilityIdentifier("parent-mode-quick-access-\(item.rawValue)")
                }
            } header: {
                Text(lang.pick("常用管理", "Everyday Management"))
            }

            Section {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPlanningExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Label(lang.pick("规划与发布检查", "Planning & Publishing Checks"), systemImage: "checkmark.shield")
                        Spacer()
                        Text("\(planningTools.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: isPlanningExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("parent-mode-planning-tools-toggle")

                if isPlanningExpanded {
                    ForEach(planningTools, id: \.self) { item in
                        NavigationLink {
                            quickAccessDestination(for: item)
                        } label: {
                            quickAccessRow(for: item)
                        }
                        .accessibilityIdentifier("parent-mode-quick-access-\(item.rawValue)")
                    }
                }
            }

            Section {
                NavigationLink {
                    ParentAICompanionOverviewView()
                } label: {
                    Label(
                        store.settings.resolvedParentInterfaceLanguage.pick("家长 AI 中心", "Parent AI Center"),
                        systemImage: "person.crop.circle.badge.questionmark"
                    )
                }
                .accessibilityIdentifier("parent-mode-ai-companion-overview")
            } header: {
                Text(lang.pick("家长 AI", "Parent AI"))
            }

            Section {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isAuditExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Label(lang.pick("系统审计与内测", "System Audit & Testing"), systemImage: "wrench.and.screwdriver")
                        Spacer()
                        Image(systemName: isAuditExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("parent-mode-audit-tools-toggle")

                if isAuditExpanded {
                    Text(lang.pick(
                        "用于内测排查同步、结算、证据链和学校接入问题；日常使用不需要展开。",
                        "Use during testing to inspect sync, settlement, evidence, and school integration."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if isAuditExpanded {
                aiHomeworkGuidanceSection
                settlementSection
                runtimeSection
                evidenceTimelineSection
                replaySection
                MobileOfflineSyncReviewNavigationLink(perspective: .parent)
            }
        }
        .navigationTitle(lang.pick("更多功能与预览", "Advanced Tools & Previews"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshSettlement()
            refreshRuntime()
            refreshEvidence()
        }
    }

    @ViewBuilder
    private func quickAccessDestination(for item: ParentModeQuickAccess) -> some View {
        switch item {
        case .todayTaskReview:
            ParentTodayTaskPackageReviewView()
        case .basicHabitChore:
            BasicHabitChoreCheckinWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        case .growthDiaryVlogReview:
            GrowthDiaryVlogStorylineWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        case .moduleConfigurationDraft:
            MobileModuleConfigurationDraftView()
        case .approvalInbox:
            ParentApprovalInboxView()
        case .schoolJointApproval:
            SchoolJointApprovalBoardView()
        case .aiHomeworkCreditHandoff:
            AIHomeworkSchoolCreditHandoffView(initialRole: .guardian, allowsRoleSwitching: true)
        case .aiLmsBoundary:
            AIHomeworkSchoolLmsBoundaryView(initialRole: .guardian, allowsRoleSwitching: true)
        case .guardianConsentPolicy:
            GuardianChildConsentPolicyView(initialRole: .guardian, allowsRoleSwitching: true)
        case .creatorManifestPreview:
            CreatorManifestPreviewView()
        case .growthPackInstallEntitlement:
            GrowthPackInstallEntitlementView(initialRole: .guardian, allowsRoleSwitching: true)
        case .creditLedgerReview:
            CreditLedgerReviewView(viewerRole: .guardian)
        case .appSelectionPolicy:
            AppSelectionWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        case .reportsPreview:
            ReportsWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        case .onboardingBoundary:
            OnboardingWorkbenchView(initialRole: .guardian, allowedRoles: [.guardian])
        }
    }

    private func quickAccessRow(for item: ParentModeQuickAccess) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(item.label(for: lang), systemImage: item.systemImage)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(item.statusLabel(for: lang))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.label(for: lang)). \(item.detail(for: lang))")
    }

    // MARK: - AI 作业引导会话（脱敏摘要）

    /// 家长端 AI 作业引导会话脱敏摘要：只看意图标签、风险标签和是否需要人工介入。
    /// 会话样例为本地确定性 mock，不接真实 AI、网络、学校系统或账本。
    private var aiHomeworkGuidanceSection: some View {
        AIHomeworkGuidanceCareSection(
            viewerRole: .guardian,
            homeworks: schoolFamily.homeworks,
            sampleMessages: Self.aiHomeworkSampleMessages(for: schoolFamily.homeworks)
        )
    }

    /// 把本地作业映射成一组确定性会话输入样例，方便家长只读查看不同风险态。
    private static func aiHomeworkSampleMessages(
        for homeworks: [SchoolHomework]
    ) -> [UUID: [AIHomeworkSessionMessage]] {
        var result: [UUID: [AIHomeworkSessionMessage]] = [:]
        for (index, homework) in homeworks.enumerated() {
            switch index % 3 {
            case 0:
                // 多次想要答案 + 反复卡住：触发「建议人工跟进」。
                result[homework.id] = [
                    .init(preset: .stuckOnStep),
                    .init(freeText: "你直接告诉我答案吧"),
                    .init(preset: .stuckOnStep),
                    .init(freeText: "还是不会，给我答案"),
                ]
            case 1:
                // 正常引导流程。
                result[homework.id] = [
                    .init(preset: .whereToStart),
                    .init(preset: .howToCheck),
                ]
            default:
                // 还没开始提问。
                result[homework.id] = []
            }
        }
        return result
    }

    // MARK: - 只读审计摘要

    /// 结算建议：家长端展示全部分组，重点关注「待审核 / 已阻断」。
    /// 这些建议账本中立——批准前不会发任何成长积分，也不会解锁设备或改作业终态。
    private var settlementSection: some View {
        MobileCreditSettlementSummarySection(report: creditSettlement.report) {
            offlineReplay.replay(outbox: offlineOutbox)
            refreshSettlement()
        }
    }

    /// 成长包运行结算摘要：家长端按待审核/可建议/已阻断/申诉中分组。
    /// 这些摘要账本中立——审核前不会发任何成长积分、不授徽章、不解锁设备。
    private var runtimeSection: some View {
        GrowthPackRuntimeParentSection(report: growthRuntime.report) {
            refreshRuntime()
        }
    }

    /// 证据链申诉时间线摘要：家长端按冲突 / 申诉 / 撤销 / 亲友待复核 / 已阻断分组。
    /// 这些摘要账本中立——申诉不绕过家长 / 老师边界，亲友不能审批或发成长积分。
    private var evidenceTimelineSection: some View {
        GrowthEvidenceTimelineParentSection(report: evidenceTimeline.report) {
            refreshEvidence()
        }
    }

    /// 审批草稿的同步重放结果：草稿永不被本地重放落定，只显示「待家长联网确认」。
    private var replaySection: some View {
        MobileOfflineReplaySummarySection(
            report: offlineReplay.report,
            focus: [.guardianApproval]
        ) {
            offlineReplay.replay(outbox: offlineOutbox)
        }
    }

    /// 基于最新离线重放报告与本地 store 重新生成结算建议。只读不写。
    private func refreshSettlement() {
        creditSettlement.refresh(
            offlineReport: offlineReplay.report,
            family: store,
            schoolFamily: schoolFamily,
            screenTime: screenTime
        )
    }

    /// 基于本地任务与学校作业重新装配成长包运行结算摘要。只读不写。
    private func refreshRuntime() {
        growthRuntime.refresh(family: store, schoolFamily: schoolFamily)
    }

    /// 基于本地任务、学校作业与运行结算计数重新装配证据时间线。只读不写。
    private func refreshEvidence() {
        let runtime = GrowthEvidenceTimelineRuntimeContext(report: growthRuntime.report)
        evidenceTimeline.refresh(family: store, schoolFamily: schoolFamily, runtime: runtime)
    }
}
