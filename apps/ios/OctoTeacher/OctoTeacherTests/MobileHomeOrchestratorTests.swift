import XCTest
@testable import OctoTeacher

/// 移动平台首页编排器测试。
///
/// 覆盖安全边界与编排正确性：
/// - 角色感知：孩子视角只有今日任务/作业/成长/成长积分/下一步，绝无审批入口；
///   家长视角才有待审批、亲友待审核、成长积分/奖励风险。
/// - 待审批数量等于三个数据源里实际待处理项之和。
/// - 亲友待审核摘要明确声明亲友只读，且越权能力恒为 false。
/// - 风险提示能反映进行中的奖励会话（且强调未真正解锁设备）。
/// - 所有展示文本脱敏：不泄露原始 publicRef、token、密钥、路径或局域网地址。
final class MobileHomeOrchestratorTests: XCTestCase {

    private func makeOrchestrator() throws -> MobileHomeOrchestrator {
        MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: SchoolFamilyStore(),
            family: LocalFamilyStore()
        )
    }

    /// 收集一个视图模型里全部对用户可见的字符串，用于脱敏断言。
    private func displayedStrings(_ vm: MobileHomeViewModel) -> [String] {
        var strings: [String] = [vm.greeting, vm.headline]
        for metric in vm.metrics {
            strings.append(contentsOf: [metric.title, metric.value, metric.caption].compactMap { $0 })
        }
        for section in vm.sections {
            strings.append(contentsOf: [section.title, section.subtitle, section.emptyText].compactMap { $0 })
            for item in section.items {
                strings.append(contentsOf: [item.title, item.detail, item.badge].compactMap { $0 })
            }
        }
        return strings
    }

    // MARK: - 孩子视角

    func testChildPerspectiveOrchestratesSelfFacingSections() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)

        XCTAssertEqual(vm.perspective, .child)
        XCTAssertTrue(vm.greeting.contains("小阳"), "孩子视角应问候主孩子昵称")

        let ids = Set(vm.sections.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: ["today", "homework", "ai-homework-inbox", "school-joint-approval", "growth", "growth-pack-entitlements", "growth-pack-cloud-sync", "module-configuration-draft", "credit", "next"]))
        // 孩子视角绝不能出现审批/风险编排分区。
        XCTAssertFalse(ids.contains("approvals"))
        XCTAssertFalse(ids.contains("relatives"))
    }

    func testChildTodayTasksMatchActionableCount() throws {
        let sync = try MobileSyncClient.makeMock()
        let orchestrator = MobileHomeOrchestrator(
            sync: sync,
            schoolFamily: SchoolFamilyStore(),
            family: LocalFamilyStore()
        )
        let child = try XCTUnwrap(sync.snapshot.children.first)
        let session = MobileSyncSession(
            actorPublicRef: child.publicRef,
            actorRole: .child,
            familyPublicRef: child.familyPublicRef,
            childPublicRef: child.publicRef
        )
        let tasks = try sync.todayTasks(session: session).get()
        let actionable = tasks.filter { MobileHomeOrchestrator.isActionable($0.status) }

        let vm = orchestrator.makeViewModel(for: .child)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "today-tasks" })
        XCTAssertEqual(metric.value, "\(actionable.count)")

        let today = try XCTUnwrap(vm.sections.first { $0.id == "today" })
        XCTAssertEqual(today.items.count, tasks.count)
    }

    func testChildPerspectiveNeverExposesApprovalActions() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)
        let texts = displayedStrings(vm).joined()
        // 不出现批准/发成长积分/解锁等会让孩子越权的动作承诺。
        XCTAssertFalse(texts.contains("批准任务"))
        // 明确告知孩子不能自行解锁/发成长积分。
        XCTAssertTrue(displayedStrings(vm).contains { $0.contains("不能") && $0.contains("解锁设备") })
    }

    func testChildGrowthPackEntitlementSectionIsSafeAndRedacted() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)
        let section = try XCTUnwrap(vm.sections.first { $0.id == "growth-pack-entitlements" })
        XCTAssertFalse(section.items.isEmpty)
        XCTAssertTrue(section.items.contains { $0.badge == GrowthPackInstallDecisionState.installed.label })
        let states: [GrowthPackInstallDecisionState] = [.installable, .installed, .pendingGuardianConfirmation, .frozen, .blocked, .hidden]
        let allowedBadges = Set(states.map(\.label))
        let allowedChildDetails = Set(states.map(MobileHomeOrchestrator.childGrowthPackHomeDetail))
        XCTAssertTrue(
            section.items.allSatisfy { item in
                allowedBadges.contains(item.badge ?? "")
                    && allowedChildDetails.contains(item.detail ?? "")
            },
            "孩子首页成长包说明必须来自状态白名单，不直接展示成长包原始摘要"
        )

        let texts = displayedStrings(vm).joined(separator: " ")
        for marker in ["$4.99", "$2.99", "order-morning", "ent-morning", "order:", "entitlement:", "gpi-order", "gpi-ent"] {
            XCTAssertFalse(texts.localizedCaseInsensitiveContains(marker), "孩子首页不应泄露成长包订单/权益/价格：\(marker)")
        }
    }

    func testChildGrowthPackCloudSyncSectionIsSafeAndReadOnly() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "growth-pack-cloud-sync" })
        let section = try XCTUnwrap(vm.sections.first { $0.id == "growth-pack-cloud-sync" })

        XCTAssertEqual(metric.title, "成长包云同步")
        XCTAssertFalse(section.items.isEmpty)
        XCTAssertTrue(section.subtitle?.contains("不会购买") == true)
        XCTAssertTrue(section.subtitle?.contains("解锁设备") == true)

        let states: [GrowthPackCloudSyncMobileBridgeState] = [.ready, .reviewRequired, .conflict, .frozen, .revoked, .blocked]
        let allowedBadges = Set(states.map(\.label))
        let allowedChildDetails = Set(states.map(MobileHomeOrchestrator.childGrowthPackCloudSyncHomeDetail))
        XCTAssertTrue(
            section.items.allSatisfy { item in
                allowedBadges.contains(item.badge ?? "")
                    && allowedChildDetails.contains(item.detail ?? "")
            },
            "孩子首页云同步说明必须来自状态白名单，不直接展示云同步桥接原始文案"
        )

        let texts = displayedStrings(vm).joined(separator: " ")
        for marker in ["order:", "entitlement:", "refund:", "ledger:", "credit:", "cloud:", "gpcm-", "http://", "https://", "192.168.", "/Users/", "/Volumes/"] {
            XCTAssertFalse(texts.localizedCaseInsensitiveContains(marker), "孩子首页云同步不应泄露内部标记：\(marker)")
        }
    }

    func testChildAIHomeworkInboxSectionIsSafeAndReadOnly() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "ai-homework-inbox" })
        let section = try XCTUnwrap(vm.sections.first { $0.id == "ai-homework-inbox" })

        XCTAssertEqual(metric.title, "家校作业")
        XCTAssertFalse(section.items.isEmpty)
        XCTAssertTrue(section.subtitle?.contains("不会调用 AI") == true)
        XCTAssertTrue(section.subtitle?.contains("发成长积分") == true)

        let statuses: [AIHomeworkFamilySchoolInboxStatus] = [.ready, .empty, .reviewRequired, .blocked]
        let allowedBadges = Set(statuses.map(\.label))
        let allowedChildDetails = Set(statuses.map(MobileHomeOrchestrator.childAIHomeworkInboxHomeDetail))
        XCTAssertTrue(
            section.items.allSatisfy { item in
                allowedBadges.contains(item.badge ?? "")
                    && allowedChildDetails.contains(item.detail ?? "")
            },
            "孩子首页家校收件箱说明必须来自状态白名单，不直接展示收件箱内部条目文案"
        )

        let texts = displayedStrings(vm).joined(separator: " ")
        for marker in ["provider", "model", "transcript", "答案键", "老师私密", "家长私密", "成长积分金额", "家长收件箱", "afs-", "http://", "https://", "192.168.", "/Users/", "/Volumes/"] {
            XCTAssertFalse(texts.localizedCaseInsensitiveContains(marker), "孩子首页家校收件箱不应泄露内部标记：\(marker)")
        }
    }

    func testChildSchoolJointApprovalSectionIsSafeAndReadOnly() throws {
        let schoolFamily = SchoolFamilyStore()
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: schoolFamily,
            family: LocalFamilyStore()
        )
        let vm = orchestrator.makeViewModel(for: .child)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "school-joint-approval" })
        let section = try XCTUnwrap(vm.sections.first { $0.id == "school-joint-approval" })
        let schoolCredit = SchoolGrowthCreditSnapshotBuilder().build(viewerRole: .child, homeworks: schoolFamily.homeworks)
        let joint = SchoolJointApprovalSnapshotBuilder().build(
            viewerRole: .child,
            homeworks: schoolFamily.homeworks,
            schoolCredit: schoolCredit
        )
        let status = MobileHomeOrchestrator.visibleSchoolJointApprovalStatus(joint)

        XCTAssertEqual(metric.title, "家校确认")
        XCTAssertEqual(metric.value, "\(joint.publicSummary.visibleItemCount)")
        XCTAssertEqual(metric.caption, MobileHomeOrchestrator.childSchoolJointApprovalHomeDetail(status))
        XCTAssertTrue(section.subtitle?.contains("不会验证老师") == true)
        XCTAssertTrue(section.subtitle?.contains("发成长积分") == true)

        let allowedDetails = Set(SchoolJointApprovalStage.allCases.map(\.childSafeCopy))
        let allowedBadges = Set(SchoolJointApprovalStage.allCases.map(\.label))
        XCTAssertTrue(
            section.items.allSatisfy { item in
                allowedDetails.contains(item.detail ?? "")
                    && allowedBadges.contains(item.badge ?? "")
            },
            "孩子首页联合审批只能显示阶段安全文案和阶段标签"
        )

        let texts = displayedStrings(vm).joined(separator: " ")
        for marker in ["优先级", "成长积分建议", "金额", "冻结原因", "申诉原因", "离线冲突", "写账本", "家长原因", "joint-", "homework:", "credit:", "ledger:", "teacher:", "guardian:", "http://", "https://", "192.168.", "/Users/", "/Volumes/"] {
            XCTAssertFalse(texts.localizedCaseInsensitiveContains(marker), "孩子首页联合审批不应泄露内部或成人信息：\(marker)")
        }
        XCTAssertFalse(joint.publicSummary.writesLedger)
        XCTAssertFalse(joint.publicSummary.confirmsGuardian)
        XCTAssertFalse(joint.publicSummary.callsLms)
    }

    func testChildModuleConfigurationDraftSectionIsSafeAndReadOnly() throws {
        let schoolFamily = SchoolFamilyStore()
        let family = LocalFamilyStore()
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: schoolFamily,
            family: family
        )
        let vm = orchestrator.makeViewModel(for: .child)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "module-configuration-draft" })
        let section = try XCTUnwrap(vm.sections.first { $0.id == "module-configuration-draft" })
        let draft = MobileModuleConfigurationDraftBuilder().build(
            viewerRole: .child,
            family: family,
            schoolFamily: schoolFamily
        )
        let status = MobileHomeOrchestrator.visibleModuleConfigurationDraftStatus(draft)

        XCTAssertEqual(metric.title, "模块安排")
        XCTAssertEqual(metric.value, "\(draft.publicSummary.visibleItemCount)")
        XCTAssertEqual(metric.caption, MobileHomeOrchestrator.childModuleConfigurationDraftHomeDetail(status))
        XCTAssertTrue(section.subtitle?.contains("不会配置模块") == true)
        XCTAssertTrue(section.subtitle?.contains("解锁设备") == true)
        XCTAssertTrue(section.items.contains { $0.badge == status.label })
        XCTAssertTrue(section.items.allSatisfy { $0.detail == MobileHomeOrchestrator.childModuleConfigurationDraftHomeDetail(status) })
        XCTAssertTrue(section.items.allSatisfy { $0.destination == nil })
        XCTAssertNil(draft.publicSummary.creditPreviewTotal)
        XCTAssertTrue(draft.reviewActions.isEmpty)
        XCTAssertEqual(draft.publicSummary.reviewActionCount, 0)
        XCTAssertEqual(draft.publicSummary.blockingActionCount, 0)
        XCTAssertFalse(draft.sideEffects.hasTriggeredSideEffect)

        let text = section.items.flatMap { [$0.title, $0.detail, $0.badge].compactMap { $0 } }.joined(separator: " ")
        for marker in ["成长积分预览", "积分预估", "待复核行动", "复核前阻断", "配置控制", "写任务", "写账本", "发成长积分", "发布", "mcd-", "task:", "credit:", "ledger:", "device:", "http://", "https://", "192.168.", "/Users/", "/Volumes/"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "孩子首页模块配置草稿不应展示内部或成人信息：\(marker)")
        }
    }

    func testGrowthPackHomeDisplaySanitizesGenericInternalPatterns() {
        let fallback = "已隐藏"
        let unsafeValues = [
            "order:raw-123",
            "entitlement:raw-456",
            "refund:raw-789",
            "ledger:credit-raw",
            "cloud:mirror-internal",
            "taskId-raw-value",
            "claimId-raw-value",
            "gpcm-card-raw",
            "gpi-order-abcd",
            "https://example.com/private",
            "100.66.90.59",
            "/Users/developer/private",
            "/Volumes/AIShare/private",
            "123e4567-e89b-12d3-a456-426614174000",
            "abcdef1234567890abcdef1234567890"
        ]

        for value in unsafeValues {
            XCTAssertEqual(
                MobileHomeOrchestrator.growthPackDisplayText(value, fallback: fallback),
                fallback,
                "成长包首页展示文本应过滤内部模式：\(value)"
            )
        }
        XCTAssertEqual(
            MobileHomeOrchestrator.growthPackDetailText(["已安装", "继续完成成长任务。"], fallback: fallback),
            "已安装 · 继续完成成长任务。"
        )
    }

    func testChildPermissionGatewayUsesSharedReadModelAndHidesSensitiveModules() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)
        let section = try XCTUnwrap(vm.sections.first { $0.id == "permission-gateway" })

        XCTAssertTrue(section.items.allSatisfy { $0.id.hasPrefix("permission-module-") })
        XCTAssertTrue(section.items.contains { $0.id == "permission-module-growth_pack_install" })
        XCTAssertTrue(section.items.contains { $0.id == "permission-module-ai_homework_review" })
        XCTAssertTrue(section.items.contains { $0.id == "permission-module-school_lms_boundary" })
        XCTAssertTrue(section.items.contains { $0.id == "permission-module-offline_status" })
        XCTAssertTrue(section.items.contains { $0.id == "permission-module-device_control" && $0.badge == "需家长" })
        XCTAssertFalse(section.items.contains { $0.id == "permission-module-marketplace_entitlement" })
        XCTAssertFalse(section.items.contains { $0.id == "permission-module-credit_consent_reconciliation" })

        let text = section.items.flatMap { [$0.title, $0.detail, $0.badge].compactMap { $0 } }.joined(separator: " ")
        for marker in ["订单", "权益 ID", "provider", "model", "transcript", "老师私密", "跨孩子", "发成长积分", "批准"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "孩子首页权限闸门不应展示敏感模块内容：\(marker)")
        }
    }

    // MARK: - 家长视角

    func testParentPendingApprovalCountMatchesSources() throws {
        let sync = try MobileSyncClient.makeMock()
        let schoolFamily = SchoolFamilyStore()
        let family = LocalFamilyStore()
        family.submit(family.assignments[0], text: "完成了")
        let orchestrator = MobileHomeOrchestrator(sync: sync, schoolFamily: schoolFamily, family: family)

        let expected = sync.snapshot.submissions.filter { $0.status == "submitted" }.count
            + family.assignments.filter { $0.status == .submitted }.count
            + schoolFamily.homeworks.filter { $0.status == .submitted }.count

        let vm = orchestrator.makeViewModel(for: .parent)
        let approvals = try XCTUnwrap(vm.sections.first { $0.id == "approvals" })
        XCTAssertEqual(approvals.items.count, expected)
        XCTAssertTrue(approvals.items.contains { $0.badge == "任务包待批准" && $0.detail?.contains("成长积分") == true })
        XCTAssertFalse(approvals.items.contains { $0.detail?.contains("奖励 15 分钟") == true })

        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "pending" })
        XCTAssertEqual(metric.value, "\(expected)")
    }

    func testParentRelativeReviewSummaryIsReadOnlyAndCountsPending() throws {
        let sync = try MobileSyncClient.makeMock()
        let schoolFamily = SchoolFamilyStore()
        let family = LocalFamilyStore()
        let orchestrator = MobileHomeOrchestrator(sync: sync, schoolFamily: schoolFamily, family: family)

        let expectedPending = schoolFamily.relativeComments.filter { $0.status == .pending }.count
            + schoolFamily.honorWall.filter { $0.approval == .pending }.count

        let vm = orchestrator.makeViewModel(for: .parent)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "relative-review" })
        XCTAssertEqual(metric.value, "\(expectedPending)")

        // 越权能力恒为 false（数据源保证），首页不应出现越权风险条目。
        let summary = family.relativeParticipationSummary
        XCTAssertFalse(summary.anyRelativeCanGrantCredit)
        XCTAssertFalse(summary.anyRelativeCanUnlockDevice)

        let relatives = try XCTUnwrap(vm.sections.first { $0.id == "relatives" })
        XCTAssertTrue(
            relatives.items.contains { $0.detail?.contains("不能批准任务") == true },
            "亲友摘要必须声明只读边界"
        )
    }

    func testParentRiskSectionReflectsActiveRewardSessions() throws {
        let sync = try MobileSyncClient.makeMock()
        let orchestrator = MobileHomeOrchestrator(
            sync: sync,
            schoolFamily: SchoolFamilyStore(),
            family: LocalFamilyStore()
        )
        let activeRewards = sync.snapshot.rewardSessions.filter { $0.status == .active }
        XCTAssertFalse(activeRewards.isEmpty, "前置条件：mock 应有进行中的奖励会话")

        let vm = orchestrator.makeViewModel(for: .parent)
        let risk = try XCTUnwrap(vm.sections.first { $0.id == "risk" })
        XCTAssertTrue(risk.items.contains { $0.badge == "奖励进行中" })
        // 强调首页不真正解锁设备。
        XCTAssertTrue(risk.items.contains { $0.detail?.contains("未真正解锁设备") == true })
    }

    func testParentGrowthPackEntitlementSectionReflectsInstallStates() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "growth-pack-entitlements" })
        let section = try XCTUnwrap(vm.sections.first { $0.id == "growth-pack-entitlements" })

        XCTAssertEqual(metric.title, "成长包需关注")
        XCTAssertNotEqual(metric.value, "0")
        XCTAssertFalse(section.items.isEmpty)
        XCTAssertTrue(section.items.contains { $0.badge == GrowthPackInstallDecisionState.installable.label })
        XCTAssertTrue(section.items.contains { $0.badge == GrowthPackInstallDecisionState.frozen.label })
        XCTAssertTrue(section.items.contains { $0.badge == GrowthPackInstallDecisionState.blocked.label })
        let attentionBadges = Set([
            GrowthPackInstallDecisionState.pendingGuardianConfirmation.label,
            GrowthPackInstallDecisionState.frozen.label,
            GrowthPackInstallDecisionState.blocked.label
        ])
        let expectedAttentionCount = section.items.filter { attentionBadges.contains($0.badge ?? "") }.count
        XCTAssertEqual(metric.value, "\(expectedAttentionCount)")
        XCTAssertFalse(
            section.items.filter { $0.badge == GrowthPackInstallDecisionState.installable.label }.isEmpty,
            "可安装成长包应保留在家长列表里作为可选项"
        )
        XCTAssertTrue(
            Int(metric.value).map { $0 < section.items.count } == true,
            "首页需关注指标不应把普通可安装项计入待处理数量"
        )
        let states: [GrowthPackInstallDecisionState] = [.installable, .installed, .pendingGuardianConfirmation, .frozen, .blocked, .hidden]
        let allowedParentDetails = Set(states.map(MobileHomeOrchestrator.parentGrowthPackHomeDetail))
        XCTAssertTrue(
            section.items.allSatisfy { item in
                allowedParentDetails.contains(item.detail ?? "")
            },
            "家长首页成长包说明必须来自状态白名单；详细原因留在专属页面"
        )
        XCTAssertTrue(section.items.contains { $0.detail?.contains("首页不触发") == true })
        XCTAssertTrue(section.subtitle?.contains("只读提醒") == true)
    }

    func testParentGrowthPackCloudSyncSectionShowsReviewCounts() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "growth-pack-cloud-sync" })
        let section = try XCTUnwrap(vm.sections.first { $0.id == "growth-pack-cloud-sync" })
        let bridge = GrowthPackCloudSyncMobileBridgeBuilder().build(viewerRole: .guardian)

        XCTAssertEqual(metric.title, "云同步复核")
        XCTAssertEqual(metric.value, "\(bridge.publicSummary.actionRequiredCount)")
        XCTAssertTrue(section.subtitle?.contains("只读提示") == true)
        XCTAssertTrue(section.subtitle?.contains("专属流程") == true)
        XCTAssertTrue(section.items.contains { $0.badge == bridge.state.label })
        XCTAssertTrue(section.items.contains { $0.detail == MobileHomeOrchestrator.parentGrowthPackCloudSyncHomeDetail(bridge.state) })
        if bridge.publicSummary.actionRequiredCount > 0 {
            XCTAssertTrue(section.items.contains { $0.detail?.contains("首页不自动修复") == true })
        } else {
            XCTAssertEqual(metric.caption, "正常")
        }
        XCTAssertFalse(bridge.sideEffects.hasTriggeredSideEffect)
    }

    func testParentAIHomeworkInboxSectionShowsReviewCounts() throws {
        let schoolFamily = SchoolFamilyStore()
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: schoolFamily,
            family: LocalFamilyStore()
        )
        let vm = orchestrator.makeViewModel(for: .parent)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "ai-homework-inbox" })
        let section = try XCTUnwrap(vm.sections.first { $0.id == "ai-homework-inbox" })
        let inbox = AIHomeworkFamilySchoolInboxBuilder().build(viewerRole: .guardian, homeworks: schoolFamily.homeworks)
        let status = MobileHomeOrchestrator.visibleAIHomeworkInboxStatus(inbox)

        XCTAssertEqual(metric.title, "家校复核")
        XCTAssertEqual(metric.value, "\(inbox.publicSummary.actionRequiredCount)")
        XCTAssertTrue(section.subtitle?.contains("首页只读提示") == true)
        XCTAssertTrue(section.subtitle?.contains("专属流程") == true)
        XCTAssertTrue(section.items.contains { $0.badge == status.label })
        XCTAssertTrue(section.items.contains { $0.detail == MobileHomeOrchestrator.parentAIHomeworkInboxHomeDetail(status) })
        if inbox.publicSummary.actionRequiredCount > 0 {
            XCTAssertTrue(section.items.contains { $0.detail?.contains("不调用模型") == true })
            XCTAssertTrue(section.items.contains { $0.detail?.contains("不写账本") == true })
        } else {
            XCTAssertEqual(metric.caption, "正常")
        }
        XCTAssertFalse(inbox.sideEffects.hasTriggeredSideEffect)
    }

    func testParentSchoolJointApprovalSectionShowsCountsAndReadOnlyGuardrails() throws {
        let schoolFamily = SchoolFamilyStore()
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: schoolFamily,
            family: LocalFamilyStore()
        )
        let vm = orchestrator.makeViewModel(for: .parent)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "school-joint-approval" })
        let section = try XCTUnwrap(vm.sections.first { $0.id == "school-joint-approval" })
        let schoolCredit = SchoolGrowthCreditSnapshotBuilder().build(viewerRole: .guardian, homeworks: schoolFamily.homeworks)
        let joint = SchoolJointApprovalSnapshotBuilder().build(
            viewerRole: .guardian,
            homeworks: schoolFamily.homeworks,
            schoolCredit: schoolCredit
        )
        let status = MobileHomeOrchestrator.visibleSchoolJointApprovalStatus(joint)
        let expectedActionCount = MobileHomeOrchestrator.parentSchoolJointApprovalActionCount(joint)

        XCTAssertEqual(metric.title, "联合审批")
        XCTAssertEqual(metric.value, "\(expectedActionCount)")
        XCTAssertEqual(metric.caption, expectedActionCount == 0 ? "正常" : "待处理")
        XCTAssertTrue(section.subtitle?.contains("首页只读提示") == true)
        XCTAssertTrue(section.subtitle?.contains("专属流程") == true)
        XCTAssertTrue(section.items.contains { $0.badge == status.label })
        XCTAssertTrue(section.items.contains { $0.detail == MobileHomeOrchestrator.parentSchoolJointApprovalHomeDetail(status) })
        if joint.publicSummary.awaitingTeacherCount > 0 {
            XCTAssertTrue(section.items.contains { $0.title.contains("等老师验证") && $0.detail?.contains("不写回学校系统") == true })
        }
        if joint.publicSummary.awaitingGuardianCount > 0 {
            XCTAssertTrue(section.items.contains { $0.title.contains("等家长确认") && $0.detail?.contains("不发成长积分") == true })
        }
        if joint.publicSummary.creditNoteCount > 0 {
            XCTAssertTrue(section.items.contains { $0.title.contains("成长积分建议") && $0.detail?.contains("不写账本") == true })
        }

        XCTAssertFalse(joint.publicSummary.verifiesTeacher)
        XCTAssertFalse(joint.publicSummary.confirmsGuardian)
        XCTAssertFalse(joint.publicSummary.writesSchoolHomework)
        XCTAssertFalse(joint.publicSummary.writesLedger)
        XCTAssertFalse(joint.publicSummary.sendsNotification)
        XCTAssertFalse(joint.publicSummary.unlocksDevice)
        XCTAssertFalse(joint.publicSummary.callsSchoolSystem)
        XCTAssertFalse(joint.publicSummary.callsLms)
        XCTAssertFalse(joint.publicSummary.usesAiToAnswer)
    }

    func testParentModuleConfigurationDraftSectionShowsCountsAndReadOnlyGuardrails() throws {
        let schoolFamily = SchoolFamilyStore()
        let family = LocalFamilyStore()
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: schoolFamily,
            family: family
        )
        let vm = orchestrator.makeViewModel(for: .parent)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "module-configuration-draft" })
        let section = try XCTUnwrap(vm.sections.first { $0.id == "module-configuration-draft" })
        let draft = MobileModuleConfigurationDraftBuilder().build(
            viewerRole: .guardian,
            family: family,
            schoolFamily: schoolFamily
        )
        let status = MobileHomeOrchestrator.visibleModuleConfigurationDraftStatus(draft)
        let expectedActionCount = MobileHomeOrchestrator.parentModuleConfigurationDraftActionCount(draft)
        let expectedBlockingActionCount = MobileHomeOrchestrator.parentModuleConfigurationDraftBlockingActionCount(draft)

        XCTAssertEqual(metric.title, "配置草稿")
        XCTAssertEqual(metric.value, "\(expectedActionCount)")
        XCTAssertEqual(expectedActionCount, draft.reviewActions.count)
        XCTAssertEqual(expectedActionCount, draft.publicSummary.reviewActionCount)
        XCTAssertEqual(expectedBlockingActionCount, draft.reviewActions.filter(\.blockedUntilReviewed).count)
        XCTAssertEqual(expectedBlockingActionCount, draft.publicSummary.blockingActionCount)
        XCTAssertEqual(metric.caption, expectedActionCount == 0 ? "正常" : "待复核")
        XCTAssertTrue(section.subtitle?.contains("首页只读提示") == true)
        XCTAssertTrue(section.subtitle?.contains("发布") == true)
        XCTAssertTrue(section.subtitle?.contains("写任务") == true)
        XCTAssertTrue(section.subtitle?.contains("发成长积分") == true)
        XCTAssertTrue(section.items.contains { $0.badge == status.label })
        XCTAssertTrue(section.items.contains { $0.detail == MobileHomeOrchestrator.parentModuleConfigurationDraftHomeDetail(status) })
        XCTAssertTrue(section.items.contains { $0.title.contains("已编排 \(draft.publicSummary.visibleItemCount) 个模块安排") })
        XCTAssertTrue(section.items.contains { $0.detail?.contains("首页只读，不写入任务") == true })
        if let creditPreviewTotal = draft.publicSummary.creditPreviewTotal {
            let visibleCreditPreviewTotal = draft.items.compactMap(\.creditPreviewMinutes).reduce(0, +)
            XCTAssertGreaterThanOrEqual(creditPreviewTotal, 0)
            XCTAssertEqual(creditPreviewTotal, visibleCreditPreviewTotal)
            XCTAssertTrue(section.items.contains { $0.title == "成长积分预估 \(creditPreviewTotal)" })
            XCTAssertTrue(section.items.contains { $0.detail?.contains("单位是成长积分") == true })
            XCTAssertFalse(section.items.contains { $0.detail?.contains("单位是可兑换分钟") == true })
            XCTAssertTrue(section.items.contains { $0.detail?.contains("屏幕时间、零花钱或愿望") == true })
            XCTAssertTrue(section.items.contains { $0.detail?.contains("不写账本") == true && $0.detail?.contains("不发成长积分") == true })
        }
        if expectedActionCount > 0 {
            XCTAssertTrue(section.items.contains { $0.badge == "复核" })
            XCTAssertTrue(section.items.contains { $0.title == "待复核行动 \(expectedActionCount)" })
            XCTAssertTrue(section.items.contains { $0.detail?.contains("来自草稿行动队列") == true })
            XCTAssertTrue(section.items.contains { $0.detail?.contains("不发布配置") == true })
            XCTAssertTrue(section.items.contains { $0.id == "module-configuration-draft-action-1" })
            XCTAssertTrue(section.items.contains { $0.id == "module-configuration-draft-review-actions" && $0.destination == .moduleConfigurationDraft })
            XCTAssertTrue(section.items.contains { $0.id == "module-configuration-draft-action-1" && $0.destination == .moduleConfigurationDraft })
            if let firstAction = draft.reviewActions.first {
                XCTAssertTrue(section.items.contains { $0.title == "\(firstAction.moduleKey.title)复核" })
                XCTAssertFalse(section.items.contains { $0.title == firstAction.title })
                XCTAssertFalse(section.items.contains { $0.detail == firstAction.reason })
            }
            XCTAssertTrue(section.items.contains { $0.detail?.contains("复核前不发布配置") == true || $0.detail?.contains("首页不写任务") == true })
        }
        if expectedBlockingActionCount > 0 {
            XCTAssertTrue(section.items.contains { $0.title == "复核前阻断 \(expectedBlockingActionCount)" })
            XCTAssertTrue(section.items.contains { $0.detail?.contains("学校作业") == true && $0.detail?.contains("不写任务") == true })
            XCTAssertTrue(section.items.contains { $0.id == "module-configuration-draft-blocking-actions" && $0.destination == .moduleConfigurationDraft })
        }
        XCTAssertTrue(section.items.contains { $0.id == "module-configuration-draft-summary" && $0.destination == .moduleConfigurationDraft })
        XCTAssertTrue(section.items.contains { $0.id == "module-configuration-draft-visible-items" && $0.destination == nil })
        let routeText = section.items.compactMap(\.destination?.rawValue).joined(separator: " ")
        for marker in ["mcd-", "task:", "credit:", "ledger:", "device:", "order:", "entitlement:", "provider:", "model:", "transcript", "http://", "https://", "192.168.", "/Users/", "/Volumes/"] {
            XCTAssertFalse(routeText.localizedCaseInsensitiveContains(marker), "家长首页模块配置草稿快捷路由不应泄露内部标记：\(marker)")
        }

        XCTAssertFalse(draft.publicSummary.writesAssignments)
        XCTAssertFalse(draft.publicSummary.writesLedger)
        XCTAssertFalse(draft.publicSummary.grantsCredit)
        XCTAssertFalse(draft.publicSummary.unlocksDevice)
        XCTAssertFalse(draft.publicSummary.sendsNotification)
        XCTAssertFalse(draft.publicSummary.callsNetwork)
        XCTAssertFalse(draft.publicSummary.callsAiProvider)
        XCTAssertFalse(draft.publicSummary.callsLocalModel)
        XCTAssertFalse(draft.publicSummary.callsLms)
        XCTAssertFalse(draft.publicSummary.writesSchoolSystem)
        XCTAssertFalse(draft.publicSummary.writesEntitlement)
        XCTAssertFalse(draft.publicSummary.createsOrder)
        XCTAssertFalse(draft.sideEffects.hasTriggeredSideEffect)

        let text = section.items.flatMap { [$0.title, $0.detail, $0.badge].compactMap { $0 } }.joined(separator: " ")
        for marker in ["mcd-", "task:", "credit:", "ledger:", "device:", "order:", "entitlement:", "provider:", "model:", "transcript", "baseUrl", "api_key", "http://", "https://", "192.168.", "/Users/", "/Volumes/"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "家长首页模块配置草稿不应泄露内部标记：\(marker)")
        }
        let itemIDs = section.items.map(\.id).joined(separator: " ")
        for marker in ["DRAFT_READY", "CREDIT_BUDGET_REVIEW", "SCHOOL_PRIORITY", "UNSAFE_INPUT_BLOCKED", "mcd-"] {
            XCTAssertFalse(itemIDs.contains(marker), "家长首页模块配置草稿 item id 不应暴露内部枚举或草稿引用：\(marker)")
        }
    }

    func testParentPermissionGatewayShowsSharedReadModelModules() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let section = try XCTUnwrap(vm.sections.first { $0.id == "permission-gateway" })
        let ids = Set(section.items.map(\.id))

        XCTAssertTrue(ids.isSuperset(of: [
            "permission-module-growth_pack_install",
            "permission-module-marketplace_entitlement",
            "permission-module-ai_homework_review",
            "permission-module-school_lms_boundary",
            "permission-module-credit_consent_reconciliation",
            "permission-module-offline_status",
            "permission-module-device_control"
        ]))
        XCTAssertFalse(ids.contains("permission-module-operations_review"))
        XCTAssertTrue(section.items.contains { $0.badge == "需家长" })
        XCTAssertTrue(section.items.allSatisfy { $0.id.hasPrefix("permission-module-") })
    }

    // MARK: - 视角切换

    func testPerspectiveSwitchProducesDifferentOrchestration() throws {
        let orchestrator = try makeOrchestrator()
        let child = orchestrator.makeViewModel(for: .child)
        let parent = orchestrator.makeViewModel(for: .parent)

        XCTAssertNotEqual(child.greeting, parent.greeting)
        XCTAssertNotEqual(Set(child.sections.map(\.id)), Set(parent.sections.map(\.id)))
    }

    // MARK: - 脱敏

    func testNoPerspectiveLeaksSensitivePayload() throws {
        let orchestrator = try makeOrchestrator()
        for perspective in MobileHomePerspective.allCases {
            let vm = orchestrator.makeViewModel(for: perspective)
            for text in displayedStrings(vm) {
                XCTAssertFalse(
                    MobileSyncPayloadGuard.isUnsafe(text),
                    "展示文本不应命中不安全负载：\(text)"
                )
                // 不泄露原始公开引用（形如 kind:token）。
                for prefix in ["child:", "family:", "task:", "proof:", "decision:", "hold:", "reward:", "feed:", "guardian:", "teacher:", "pack:", "creator:", "order:", "entitlement:", "refund:", "ledger:", "credit:", "cloud:", "homework:", "transcript:", "taskId", "claimId", "afs-", "joint-", "provider:", "model:", "baseUrl", "api_key", "http://", "https://", "192.168.", "file://", "/Users/", "/Volumes/"] {
                    XCTAssertFalse(text.contains(prefix), "展示文本不应包含原始引用 \(prefix)：\(text)")
                }
            }
        }
    }

    // MARK: - A66 家校作业收件箱快捷路由

    func testChildAIHomeworkInboxItemHasCorrectDestination() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)
        let section = try XCTUnwrap(vm.sections.first { $0.id == "ai-homework-inbox" })
        let nextItem = try XCTUnwrap(section.items.first { $0.id == "ai-homework-inbox-next" })

        XCTAssertEqual(nextItem.destination, .aiHomeworkInbox, "孩子首页家校收件箱主条目必须指向 aiHomeworkInbox")

        let rawValue = try XCTUnwrap(nextItem.destination?.rawValue)
        let sensitiveMarkers = [
            "public", "ref", "task", "ledger", "device", "order", "entitlement",
            "provider", "model", "transcript", "http://", "https://", "192.168.",
            "/users/", "/volumes/", "token", "secret", "apikey", "api_key"
        ]
        for marker in sensitiveMarkers {
            XCTAssertFalse(rawValue.localizedCaseInsensitiveContains(marker),
                "孩子首页 ai-homework-inbox destination rawValue 不应含敏感标记：\(marker)")
        }
    }

    func testParentAIHomeworkInboxSummaryItemHasCorrectDestination() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let section = try XCTUnwrap(vm.sections.first { $0.id == "ai-homework-inbox" })
        let summaryItem = try XCTUnwrap(section.items.first { $0.id == "ai-homework-inbox-summary" })

        XCTAssertEqual(summaryItem.destination, .aiHomeworkInbox, "家长首页家校收件箱汇总条目必须指向 aiHomeworkInbox")

        let rawValue = try XCTUnwrap(summaryItem.destination?.rawValue)
        let sensitiveMarkers = [
            "public", "ref", "task", "ledger", "device", "order", "entitlement",
            "provider", "model", "transcript", "http://", "https://", "192.168.",
            "/users/", "/volumes/", "token", "secret", "apikey", "api_key"
        ]
        for marker in sensitiveMarkers {
            XCTAssertFalse(rawValue.localizedCaseInsensitiveContains(marker),
                "家长首页 ai-homework-inbox destination rawValue 不应含敏感标记：\(marker)")
        }
    }

    func testAIHomeworkInboxDestinationAllowedPerspectives() {
        XCTAssertTrue(MobileHomeDestination.aiHomeworkInbox.allowedPerspectives.contains(.child),
            "aiHomeworkInbox 应允许孩子视角进入")
        XCTAssertTrue(MobileHomeDestination.aiHomeworkInbox.allowedPerspectives.contains(.parent),
            "aiHomeworkInbox 应允许家长视角进入")
        XCTAssertEqual(MobileHomeDestination.moduleConfigurationDraft.allowedPerspectives, [.parent],
            "moduleConfigurationDraft 应只允许家长视角（parent-only）")
    }

    func testChildModuleConfigurationDraftItemsHaveNilDestination() throws {
        let schoolFamily = SchoolFamilyStore()
        let family = LocalFamilyStore()
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: schoolFamily,
            family: family
        )
        let vm = orchestrator.makeViewModel(for: .child)
        let section = try XCTUnwrap(vm.sections.first { $0.id == "module-configuration-draft" })

        XCTAssertTrue(section.items.allSatisfy { $0.destination == nil },
            "孩子视角模块配置草稿所有条目 destination 必须为 nil（parent-only 路由）")
    }

    func testParentModuleConfigurationDraftSummaryItemHasParentOnlyDestination() throws {
        let schoolFamily = SchoolFamilyStore()
        let family = LocalFamilyStore()
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: schoolFamily,
            family: family
        )
        let vm = orchestrator.makeViewModel(for: .parent)
        let section = try XCTUnwrap(vm.sections.first { $0.id == "module-configuration-draft" })
        let summaryItem = try XCTUnwrap(section.items.first { $0.id == "module-configuration-draft-summary" })

        XCTAssertEqual(summaryItem.destination, .moduleConfigurationDraft,
            "家长首页模块配置草稿汇总条目必须指向 moduleConfigurationDraft")
        XCTAssertFalse(MobileHomeDestination.moduleConfigurationDraft.allowedPerspectives.contains(.child),
            "moduleConfigurationDraft 路由不允许孩子视角进入")
    }

    // MARK: - A67 学校联合审批首页快捷路由

    func testChildSchoolJointApprovalItemHasCorrectDestination() throws {
        let schoolFamily = SchoolFamilyStore()
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: schoolFamily,
            family: LocalFamilyStore()
        )
        let vm = orchestrator.makeViewModel(for: .child)
        let section = try XCTUnwrap(vm.sections.first { $0.id == "school-joint-approval" })
        let routeItems = section.items.filter { $0.destination != nil }

        XCTAssertFalse(routeItems.isEmpty, "孩子首页联合审批应至少有一个可进入联合审批台的安全条目")
        XCTAssertTrue(routeItems.allSatisfy { $0.destination == .schoolJointApproval },
            "孩子首页联合审批所有带 destination 的条目必须指向 schoolJointApproval")

        let rawValue = MobileHomeDestination.schoolJointApproval.rawValue
        let sensitiveMarkers = [
            "publicref", "homework", "task", "ledger", "device", "order", "entitlement",
            "provider", "model", "transcript", "http://", "https://", "192.168.",
            "/users/", "/volumes/", "token", "secret", "apikey", "api_key"
        ]
        for marker in sensitiveMarkers {
            XCTAssertFalse(rawValue.localizedCaseInsensitiveContains(marker),
                "孩子首页 school-joint-approval destination rawValue 不应含敏感标记：\(marker)")
        }
    }

    func testParentSchoolJointApprovalSummaryItemHasCorrectDestination() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let section = try XCTUnwrap(vm.sections.first { $0.id == "school-joint-approval" })
        let summaryItem = try XCTUnwrap(section.items.first { $0.id == "school-joint-approval-summary" })

        XCTAssertEqual(summaryItem.destination, .schoolJointApproval,
            "家长首页联合审批汇总条目必须指向 schoolJointApproval")

        let rawValue = try XCTUnwrap(summaryItem.destination?.rawValue)
        let sensitiveMarkers = [
            "publicref", "homework", "task", "ledger", "device", "order", "entitlement",
            "provider", "model", "transcript", "http://", "https://", "192.168.",
            "/users/", "/volumes/", "token", "secret", "apikey", "api_key"
        ]
        for marker in sensitiveMarkers {
            XCTAssertFalse(rawValue.localizedCaseInsensitiveContains(marker),
                "家长首页 school-joint-approval destination rawValue 不应含敏感标记：\(marker)")
        }
    }

    func testSchoolJointApprovalDestinationAllowedPerspectives() {
        XCTAssertTrue(MobileHomeDestination.schoolJointApproval.allowedPerspectives.contains(.child),
            "schoolJointApproval 应允许孩子视角进入")
        XCTAssertTrue(MobileHomeDestination.schoolJointApproval.allowedPerspectives.contains(.parent),
            "schoolJointApproval 应允许家长视角进入")
        XCTAssertEqual(MobileHomeDestination.moduleConfigurationDraft.allowedPerspectives, [.parent],
            "moduleConfigurationDraft 应只允许家长视角（parent-only）")
        XCTAssertEqual(MobileHomeDestination.aiHomeworkInbox.allowedPerspectives, [.child, .parent],
            "aiHomeworkInbox 应允许孩子和家长视角")
    }

    // MARK: - A70 奖励兑换/状态首页快捷路由

    func testChildRewardCreditItemsRouteToRedemptionOnly() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)
        let section = try XCTUnwrap(vm.sections.first { $0.id == "credit" })

        let creditItem = try XCTUnwrap(section.items.first { $0.id == "credit-available" })
        let guardItem = try XCTUnwrap(section.items.first { $0.id == "reward-guard" })
        XCTAssertEqual(creditItem.destination, .rewardRedemption,
            "孩子首页可用积分应进入兑换页")
        XCTAssertEqual(guardItem.destination, .rewardRedemption,
            "孩子首页奖励安全提示也应进入兑换页查看可申请项")

        let activeRewardItems = section.items.filter { $0.id.hasPrefix("reward-") && $0.id != "reward-guard" }
        XCTAssertFalse(activeRewardItems.isEmpty, "mock 应有进行中的奖励会话供孩子查看")
        XCTAssertTrue(activeRewardItems.allSatisfy { $0.destination == .rewardRedemption },
            "孩子首页进行中奖励条目必须进入 rewardRedemption")

        XCTAssertEqual(MobileHomeDestination.rewardRedemption.allowedPerspectives, [.child],
            "rewardRedemption 只能由孩子视角进入")
        XCTAssertFalse(MobileHomeDestination.rewardRedemption.allowedPerspectives.contains(.parent),
            "家长视角不应进入孩子兑换页快捷入口")
    }

    func testParentRewardRiskItemsRouteToStatusOnly() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let section = try XCTUnwrap(vm.sections.first { $0.id == "risk" })
        let rewardRiskItems = section.items.filter {
            $0.id.hasPrefix("risk-expire-")
                || $0.id.hasPrefix("risk-held-")
                || $0.id.hasPrefix("risk-reward-")
        }

        XCTAssertFalse(rewardRiskItems.isEmpty, "家长首页应有成长积分/奖励风险条目供跳转状态页")
        XCTAssertTrue(rewardRiskItems.allSatisfy { $0.destination == .rewardStatus },
            "家长首页成长积分/奖励风险条目必须进入 rewardStatus")
        XCTAssertEqual(MobileHomeDestination.rewardStatus.allowedPerspectives, [.parent],
            "rewardStatus 只能由家长视角进入")
        XCTAssertFalse(MobileHomeDestination.rewardStatus.allowedPerspectives.contains(.child),
            "孩子视角不应进入家长奖励状态页快捷入口")
    }

    func testRewardDestinationsDoNotCarrySensitivePayload() {
        let rawValues = [
            MobileHomeDestination.rewardRedemption.rawValue,
            MobileHomeDestination.rewardStatus.rawValue
        ]
        let sensitiveMarkers = [
            "public", "ref", "task", "ledger", "device", "order", "entitlement",
            "provider", "model", "transcript", "http://", "https://", "192.168.",
            "/users/", "/volumes/", "token", "secret", "apikey", "api_key"
        ]

        for rawValue in rawValues {
            for marker in sensitiveMarkers {
                XCTAssertFalse(rawValue.localizedCaseInsensitiveContains(marker),
                    "奖励首页 destination rawValue 不应含敏感标记：\(marker)")
            }
        }
    }

    // MARK: - A71 成长包首页快捷路由

    func testChildGrowthPackItemsRouteToRoleLockedLocalPages() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)
        let entitlementSection = try XCTUnwrap(vm.sections.first { $0.id == "growth-pack-entitlements" })
        let cloudSection = try XCTUnwrap(vm.sections.first { $0.id == "growth-pack-cloud-sync" })
        let cloudItem = try XCTUnwrap(cloudSection.items.first { $0.id == "growth-pack-cloud-sync-next" })

        XCTAssertFalse(entitlementSection.items.isEmpty, "孩子首页应显示可运行成长包摘要")
        XCTAssertTrue(entitlementSection.items.allSatisfy { $0.destination == .growthPackEntitlements },
            "孩子首页成长包权益条目必须进入成长包安装权益页")
        XCTAssertEqual(cloudItem.destination, .growthPackCloudSync,
            "孩子首页成长包云同步下一步必须进入云同步桥接页")
        XCTAssertEqual(MobileHomeDestination.growthPackEntitlements.allowedPerspectives, [.child, .parent])
        XCTAssertEqual(MobileHomeDestination.growthPackCloudSync.allowedPerspectives, [.child, .parent])
    }

    func testParentGrowthPackItemsRouteToRoleLockedLocalPages() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let entitlementSection = try XCTUnwrap(vm.sections.first { $0.id == "growth-pack-entitlements" })
        let cloudSection = try XCTUnwrap(vm.sections.first { $0.id == "growth-pack-cloud-sync" })

        XCTAssertFalse(entitlementSection.items.isEmpty, "家长首页应显示成长包权益复核摘要")
        XCTAssertTrue(entitlementSection.items.allSatisfy { $0.destination == .growthPackEntitlements },
            "家长首页成长包权益条目必须进入成长包安装权益页")
        XCTAssertFalse(cloudSection.items.isEmpty, "家长首页应显示云同步复核摘要")
        XCTAssertTrue(cloudSection.items.allSatisfy { $0.destination == .growthPackCloudSync },
            "家长首页云同步条目必须进入云同步桥接页")
    }

    func testGrowthPackHomeDestinationsDoNotCarrySensitivePayload() {
        let rawValues = [
            MobileHomeDestination.growthPackEntitlements.rawValue,
            MobileHomeDestination.growthPackCloudSync.rawValue
        ]
        let sensitiveMarkers = [
            "public", "ref", "task", "ledger", "device", "order", "entitlement",
            "provider", "model", "transcript", "cloud", "http://", "https://", "192.168.",
            "/users/", "/volumes/", "token", "secret", "apikey", "api_key"
        ]

        for rawValue in rawValues {
            for marker in sensitiveMarkers {
                XCTAssertFalse(rawValue.localizedCaseInsensitiveContains(marker),
                    "成长包首页 destination rawValue 不应含敏感标记：\(marker)")
            }
        }
    }

    // MARK: - 成长包闭环首页投影

    func testChildHomeShowsGrowthRuntimeNextActions() throws {
        let family = LocalFamilyStore()
        let schoolFamily = SchoolFamilyStore()
        let runtime = GrowthPackRuntimeStore().refresh(family: family, schoolFamily: schoolFamily)
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: schoolFamily,
            family: family,
            growthRuntimeReport: runtime
        )
        let vm = orchestrator.makeViewModel(for: .child)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "growth-runtime-actions" })
        let section = try XCTUnwrap(vm.sections.first { $0.id == "growth-runtime-actions" })
        let next = try XCTUnwrap(vm.sections.first { $0.id == "next" })

        XCTAssertEqual(metric.title, "成长闭环")
        XCTAssertEqual(metric.value, "\(runtime.publicSummary.stepCount)")
        XCTAssertFalse(section.items.isEmpty)
        XCTAssertTrue(section.subtitle?.contains("不会发成长积分") == true)
        XCTAssertTrue(section.subtitle?.contains("解锁设备") == true)
        XCTAssertTrue(section.items.allSatisfy { $0.destination == .growthPackExecutionHub })
        XCTAssertTrue(section.items.contains { $0.badge == GrowthRuntimeProjectionStatus.creditSuggested.label })
        XCTAssertTrue(next.items.contains { $0.id == "next-growth-runtime" && $0.destination == .growthPackExecutionHub })

        let text = section.items.flatMap { [$0.title, $0.detail, $0.badge].compactMap { $0 } }.joined(separator: " ")
        for marker in ["runstep:", "runpack:", "kid:", "child:", "family:", "pack:", "proof:", "ledger:", "credit:", "device:", "http://", "https://", "192.168.", "/Users/", "/Volumes/"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(marker),
                "孩子首页成长闭环不应泄露内部标记：\(marker)")
        }
    }

    func testParentHomeShowsGrowthRuntimeReviewSummary() throws {
        let family = LocalFamilyStore()
        let schoolFamily = SchoolFamilyStore()
        let runtime = GrowthPackRuntimeStore().refresh(family: family, schoolFamily: schoolFamily)
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: schoolFamily,
            family: family,
            growthRuntimeReport: runtime
        )
        let vm = orchestrator.makeViewModel(for: .parent)
        let metric = try XCTUnwrap(vm.metrics.first { $0.id == "growth-runtime-actions" })
        let section = try XCTUnwrap(vm.sections.first { $0.id == "growth-runtime-actions" })
        let expectedActionCount = runtime.publicSummary.creditSuggestedCount
            + runtime.publicSummary.reviewRequiredCount
            + runtime.publicSummary.appealingCount
            + runtime.publicSummary.blockedCount

        XCTAssertEqual(metric.title, "成长闭环复核")
        XCTAssertEqual(metric.value, "\(expectedActionCount)")
        XCTAssertTrue(section.subtitle?.contains("首页只读投影") == true)
        XCTAssertTrue(section.subtitle?.contains("真实批准") == true)
        XCTAssertTrue(section.items.contains { $0.id == "growth-runtime-parent-summary" && $0.destination == .growthPackExecutionHub })
        XCTAssertTrue(section.items.contains { $0.id == "growth-runtime-parent-credit-suggested" })
        XCTAssertTrue(section.items.contains { $0.id == "growth-runtime-parent-review" })
        XCTAssertTrue(section.items.contains { $0.id == "growth-runtime-parent-blocked" })

        let detail = section.items.compactMap(\.detail).joined(separator: " ")
        XCTAssertTrue(detail.contains("成长积分建议"))
        XCTAssertFalse(detail.contains("分钟建议"))
        XCTAssertTrue(detail.contains("不写账本"))
        XCTAssertTrue(detail.contains("不发成长积分"))
        XCTAssertTrue(detail.contains("不解锁设备"))
        for marker in ["runstep:", "runpack:", "kid:", "child:", "family:", "pack:", "proof:", "ledger:", "credit:", "device:", "http://", "https://", "192.168.", "/Users/", "/Volumes/"] {
            XCTAssertFalse(detail.localizedCaseInsensitiveContains(marker),
                "家长首页成长闭环不应泄露内部标记：\(marker)")
        }
    }

    func testUnsafeGrowthRuntimeReportFallsBackToEmptyHomeProjection() throws {
        var leaked = GrowthRuntimeSettlementReport.empty
        leaked.packTitle = "http://192.168.1.2/private"
        leaked.publicSummary = GrowthRuntimePublicSummary(
            generatedAt: "",
            packPublicRef: "pack:secret",
            childPublicRef: "child:secret",
            stepCount: 1,
            plannedCount: 0,
            reviewRequiredCount: 0,
            creditSuggestedCount: 1,
            appealingCount: 0,
            blockedCount: 0,
            duplicateCount: 0,
            alreadyCreditedCount: 0,
            voidedCount: 0,
            totalSuggestedCredit: 10,
            badgeSuggestionCount: 1,
            abilitySuggestionCount: 1,
            findingCodes: []
        )
        let orchestrator = MobileHomeOrchestrator(
            sync: try MobileSyncClient.makeMock(),
            schoolFamily: SchoolFamilyStore(),
            family: LocalFamilyStore(),
            growthRuntimeReport: leaked
        )
        let child = orchestrator.makeViewModel(for: .child)
        let metric = try XCTUnwrap(child.metrics.first { $0.id == "growth-runtime-actions" })
        let section = try XCTUnwrap(child.sections.first { $0.id == "growth-runtime-actions" })

        XCTAssertEqual(metric.value, "0")
        XCTAssertTrue(section.items.contains { $0.id == "growth-runtime-child-summary" })
        XCTAssertFalse(displayedStrings(child).joined(separator: " ").contains("192.168."))
        XCTAssertFalse(displayedStrings(child).joined(separator: " ").contains("pack:secret"))
    }

    // MARK: - 成长积分账本复核快捷路由（A72）

    func testParentRiskSectionHasCreditLedgerReviewEntry() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let risk = try XCTUnwrap(vm.sections.first { $0.id == "risk" })

        let entry = try XCTUnwrap(
            risk.items.first { $0.id == "credit-ledger-review" },
            "家长风险区必须有成长积分账本复核台入口"
        )
        XCTAssertEqual(entry.destination, .creditLedgerReview)
        XCTAssertEqual(entry.title, "成长积分账本复核台")
        // 只读语义：不发放成长积分、不扣成长积分、不解锁设备。
        let detail = try XCTUnwrap(entry.detail)
        XCTAssertTrue(detail.contains("不发放成长积分"))
        XCTAssertTrue(detail.contains("不扣成长积分"))
        XCTAssertTrue(detail.contains("不解锁设备"))
        // 不改变已有 rewardStatus 路由：风险区仍可指向 rewardStatus。
        XCTAssertFalse(
            risk.items.contains { $0.id == "credit-ledger-review" && $0.destination == .rewardStatus },
            "复核台入口不应复用 rewardStatus 路由"
        )
    }

    func testChildPerspectiveNeverExposesCreditLedgerReview() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)

        for section in vm.sections {
            for item in section.items {
                XCTAssertNotEqual(
                    item.destination, .creditLedgerReview,
                    "孩子任意分区都不应出现 creditLedgerReview 入口（section=\(section.id) item=\(item.id)）"
                )
                XCTAssertNotEqual(
                    item.id, "credit-ledger-review",
                    "孩子任意分区都不应出现成长积分账本复核台条目"
                )
            }
        }
    }

    func testCreditLedgerReviewDestinationAllowedPerspectivesIsParentOnly() {
        XCTAssertEqual(
            MobileHomeDestination.creditLedgerReview.allowedPerspectives, [.parent],
            "creditLedgerReview 应只允许家长视角（parent-only）"
        )
        XCTAssertFalse(
            MobileHomeDestination.creditLedgerReview.allowedPerspectives.contains(.child),
            "creditLedgerReview 绝不允许孩子视角"
        )
    }

    func testCreditLedgerReviewDestinationRawValueHasNoSensitiveMarkers() {
        let rawValue = MobileHomeDestination.creditLedgerReview.rawValue
        let sensitiveMarkers = [
            "public", "ref", "task", "homework", "ledger", "device", "order",
            "entitlement", "provider", "model", "transcript", "cloud", "http",
            "path", "token", "secret", "apikey", "api_key", "192.168.",
            "/users/", "/volumes/"
        ]
        for marker in sensitiveMarkers {
            XCTAssertFalse(
                rawValue.localizedCaseInsensitiveContains(marker),
                "creditLedgerReview destination rawValue 不应含敏感标记：\(marker)"
            )
        }
    }

    // MARK: - 移动发布质量门快捷路由（A73）

    func testParentHomeHasReleaseGateEntry() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let section = try XCTUnwrap(
            vm.sections.first { $0.id == "release-quality" },
            "家长首页必须有平台发布质量门只读分区"
        )
        let entry = try XCTUnwrap(
            section.items.first { $0.id == "mobile-release-gate" },
            "平台发布质量门分区必须有移动发布质量门入口"
        )
        XCTAssertEqual(entry.destination, .releaseGate)
        XCTAssertEqual(entry.title, "移动发布质量门")
        // 入口文案体现只读、不发布、不写账本、不解锁设备。
        let detail = try XCTUnwrap(entry.detail)
        XCTAssertTrue(detail.contains("只读"))
        XCTAssertTrue(detail.contains("不发布"))
        XCTAssertTrue(detail.contains("不写账本"))
        XCTAssertTrue(detail.contains("不解锁设备"))
        // 摘要体现状态、阻断/复核/待办。
        XCTAssertTrue(detail.contains("状态"))
        XCTAssertTrue(detail.contains("阻断"))
        XCTAssertTrue(detail.contains("复核"))
        XCTAssertTrue(detail.contains("待办"))
    }

    func testChildPerspectiveNeverExposesReleaseGate() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)

        for section in vm.sections {
            XCTAssertNotEqual(
                section.id, "release-quality",
                "孩子任意分区都不应出现平台发布质量门分区（section=\(section.id)）"
            )
            for item in section.items {
                XCTAssertNotEqual(
                    item.destination, .releaseGate,
                    "孩子任意分区都不应出现 releaseGate 入口（section=\(section.id) item=\(item.id)）"
                )
                XCTAssertNotEqual(
                    item.id, "mobile-release-gate",
                    "孩子任意分区都不应出现移动发布质量门条目"
                )
            }
        }
    }

    func testReleaseGateDestinationAllowedPerspectivesIsParentOnly() {
        XCTAssertEqual(
            MobileHomeDestination.releaseGate.allowedPerspectives, [.parent],
            "releaseGate 应只允许家长视角（parent-only）"
        )
        XCTAssertFalse(
            MobileHomeDestination.releaseGate.allowedPerspectives.contains(.child),
            "releaseGate 绝不允许孩子视角"
        )
    }

    func testReleaseGateDestinationRawValueHasNoSensitiveMarkers() {
        let rawValue = MobileHomeDestination.releaseGate.rawValue
        let sensitiveMarkers = [
            "public", "ref", "task", "homework", "ledger", "device", "order",
            "entitlement", "provider", "model", "transcript", "cloud", "http",
            "path", "token", "secret", "apikey", "api_key", "192.168.",
            "/users/", "/volumes/"
        ]
        for marker in sensitiveMarkers {
            XCTAssertFalse(
                rawValue.localizedCaseInsensitiveContains(marker),
                "releaseGate destination rawValue 不应含敏感标记：\(marker)"
            )
        }
    }

    // MARK: - 家庭故事线发布门禁快捷路由

    func testParentHomeHasFamilyStorylineReleaseGateEntry() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let section = try XCTUnwrap(
            vm.sections.first { $0.id == "relatives" },
            "家长首页必须保留亲友/家庭荣誉审核分区"
        )
        let entry = try XCTUnwrap(
            section.items.first { $0.id == "family-storyline-release-gate" },
            "亲友审核分区应提供故事线发布门禁入口"
        )

        XCTAssertEqual(entry.destination, .familyStorylineConsent)
        XCTAssertEqual(entry.title, "故事线发布门禁")
        XCTAssertEqual(entry.badge, "只读")
        let detail = try XCTUnwrap(entry.detail)
        XCTAssertTrue(detail.contains("候选"))
        XCTAssertTrue(detail.contains("待处理"))
        XCTAssertTrue(detail.contains("阻断"))
        XCTAssertTrue(detail.contains("只读预览"))
        XCTAssertTrue(detail.contains("不发布"))
        XCTAssertTrue(detail.contains("不通知"))
        XCTAssertTrue(detail.contains("不发成长积分"))
        XCTAssertTrue(detail.contains("不解锁设备"))
    }

    func testChildPerspectiveNeverExposesFamilyStorylineReleaseGate() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)

        for section in vm.sections {
            XCTAssertNotEqual(
                section.id,
                "relatives",
                "孩子视角不应出现亲友审核/故事线发布门禁分区"
            )
            for item in section.items {
                XCTAssertNotEqual(item.destination, .familyStorylineConsent)
                XCTAssertNotEqual(item.id, "family-storyline-release-gate")
            }
        }
    }

    func testFamilyStorylineConsentDestinationAllowedPerspectivesIsParentOnly() {
        XCTAssertEqual(MobileHomeDestination.familyStorylineConsent.allowedPerspectives, [.parent])
        XCTAssertFalse(MobileHomeDestination.familyStorylineConsent.allowedPerspectives.contains(.child))
    }

    func testFamilyStorylineConsentDestinationRawValueHasNoSensitiveMarkers() {
        let rawValue = MobileHomeDestination.familyStorylineConsent.rawValue
        let sensitiveMarkers = [
            "public", "ref", "task", "homework", "ledger", "device", "order",
            "entitlement", "provider", "model", "transcript", "cloud", "http",
            "path", "token", "secret", "apikey", "api_key", "192.168.",
            "/users/", "/volumes/"
        ]
        for marker in sensitiveMarkers {
            XCTAssertFalse(
                rawValue.localizedCaseInsensitiveContains(marker),
                "familyStorylineConsent destination rawValue 不应含敏感标记：\(marker)"
            )
        }
    }

    // MARK: - 情绪安全中心首页快捷路由

    func testChildHomeHasFamilySocialFeedbackEmotionalSafetyEntry() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)
        let section = try XCTUnwrap(
            vm.sections.first { $0.id == "family-social-feedback-safety" },
            "孩子首页必须有情绪安全中心只读入口分区"
        )
        let entry = try XCTUnwrap(
            section.items.first { $0.id == "family-social-feedback-safety-entry" },
            "情绪安全中心分区必须有快捷入口条目"
        )

        XCTAssertEqual(entry.destination, .familySocialFeedbackEmotionalSafety)
        XCTAssertEqual(entry.badge, "只读")
        let detail = try XCTUnwrap(entry.detail)
        XCTAssertTrue(detail.contains("安全鼓励"))
        XCTAssertTrue(detail.contains("下一步"))
        XCTAssertTrue(detail.contains("请家长看一看"))
        XCTAssertFalse(detail.contains("审核原因"))
        XCTAssertFalse(detail.contains("评分"))
        XCTAssertFalse(detail.contains("成长积分"))
        XCTAssertFalse(detail.contains("设备"))
        XCTAssertFalse(detail.contains("成人"))
        XCTAssertFalse(detail.contains("家庭规则"))
        XCTAssertFalse(detail.contains("写账本"))
    }

    func testParentHomeHasFamilySocialFeedbackEmotionalSafetyEntry() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let section = try XCTUnwrap(
            vm.sections.first { $0.id == "relatives" },
            "家长首页亲友分区必须包含情绪安全复核入口"
        )
        let entry = try XCTUnwrap(
            section.items.first { $0.id == "family-social-feedback-safety-entry" },
            "亲友分区必须有情绪安全复核入口"
        )

        XCTAssertEqual(entry.destination, .familySocialFeedbackEmotionalSafety)
        XCTAssertEqual(entry.title, "情绪安全复核中心")
        XCTAssertEqual(entry.badge, "只读")
        let detail = try XCTUnwrap(entry.detail)
        XCTAssertTrue(detail.contains("亲友鼓励"))
        XCTAssertTrue(detail.contains("通知预览"))
        XCTAssertTrue(detail.contains("不发布"))
        XCTAssertTrue(detail.contains("不通知"))
        XCTAssertTrue(detail.contains("不写账本"))
        XCTAssertTrue(detail.contains("不发成长积分"))
        XCTAssertTrue(detail.contains("不解锁设备"))
    }

    func testFamilySocialFeedbackEmotionalSafetyDestinationAllowedPerspectives() {
        XCTAssertEqual(
            MobileHomeDestination.familySocialFeedbackEmotionalSafety.allowedPerspectives,
            [.child, .parent],
            "情绪安全中心首页入口应允许孩子和家长视角进入"
        )
        XCTAssertTrue(MobileHomeDestination.familySocialFeedbackEmotionalSafety.allowedPerspectives.contains(.child))
        XCTAssertTrue(MobileHomeDestination.familySocialFeedbackEmotionalSafety.allowedPerspectives.contains(.parent))
    }

    func testFamilySocialFeedbackEmotionalSafetyDestinationRawValueHasNoSensitiveMarkers() {
        let rawValue = MobileHomeDestination.familySocialFeedbackEmotionalSafety.rawValue
        let sensitiveMarkers = [
            "public", "ref", "task", "homework", "ledger", "device", "order",
            "entitlement", "provider", "model", "transcript", "cloud", "http",
            "path", "token", "secret", "apikey", "api_key", "192.168.",
            "/users/", "/volumes/"
        ]
        for marker in sensitiveMarkers {
            XCTAssertFalse(
                rawValue.localizedCaseInsensitiveContains(marker),
                "familySocialFeedbackEmotionalSafety destination rawValue 不应含敏感标记：\(marker)"
            )
        }
    }

    // MARK: - 离线同步复核台首页快捷路由（A74）

    func testChildHomeHasOfflineSyncReviewEntry() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)
        let section = try XCTUnwrap(
            vm.sections.first { $0.id == "offline-sync-review" },
            "孩子首页必须有同步复核台只读入口分区"
        )
        let entry = try XCTUnwrap(
            section.items.first { $0.id == "offline-sync-review-entry" },
            "同步复核台分区必须有快捷入口条目"
        )
        XCTAssertEqual(entry.destination, .offlineSyncReview)
        XCTAssertEqual(entry.badge, "只读")
        // 孩子端文案体现只读边界，不暴露冲突/回滚等成人复核语义。
        let detail = try XCTUnwrap(entry.detail)
        XCTAssertTrue(detail.contains("不会发积分"))
        XCTAssertTrue(detail.contains("不会解锁设备"))
        XCTAssertFalse(detail.contains("写账本"), "孩子首页入口文案不应出现账本写入等成人复核语义")
        XCTAssertFalse(detail.contains("回滚"), "孩子首页入口文案不应出现回滚等成人复核语义")
    }

    func testParentHomeHasOfflineSyncReviewEntry() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let section = try XCTUnwrap(
            vm.sections.first { $0.id == "offline-sync-review" },
            "家长首页必须有离线同步复核台只读入口分区"
        )
        let entry = try XCTUnwrap(
            section.items.first { $0.id == "offline-sync-review-entry" },
            "离线同步复核台分区必须有快捷入口条目"
        )
        XCTAssertEqual(entry.destination, .offlineSyncReview)
        XCTAssertEqual(entry.badge, "只读")
        let detail = try XCTUnwrap(entry.detail)
        XCTAssertTrue(detail.contains("冲突"))
        XCTAssertTrue(detail.contains("回滚"))
        XCTAssertTrue(detail.contains("不写账本"))
        XCTAssertTrue(detail.contains("不发成长积分"))
        XCTAssertTrue(detail.contains("不解锁设备"))
    }

    func testOfflineSyncReviewDestinationAllowedPerspectives() {
        XCTAssertEqual(
            MobileHomeDestination.offlineSyncReview.allowedPerspectives, [.child, .parent],
            "offlineSyncReview 应允许孩子和家长视角进入"
        )
        XCTAssertTrue(MobileHomeDestination.offlineSyncReview.allowedPerspectives.contains(.child))
        XCTAssertTrue(MobileHomeDestination.offlineSyncReview.allowedPerspectives.contains(.parent))
    }

    func testOfflineSyncReviewDestinationRawValueHasNoSensitiveMarkers() {
        let rawValue = MobileHomeDestination.offlineSyncReview.rawValue
        let sensitiveMarkers = [
            "public", "ref", "task", "homework", "ledger", "device", "order",
            "entitlement", "provider", "model", "transcript", "cloud", "http",
            "path", "token", "secret", "apikey", "api_key", "192.168.",
            "/users/", "/volumes/"
        ]
        for marker in sensitiveMarkers {
            XCTAssertFalse(
                rawValue.localizedCaseInsensitiveContains(marker),
                "offlineSyncReview destination rawValue 不应含敏感标记：\(marker)"
            )
        }
    }

    /// 首页编排不应触发任何离线副作用：编排器不持有 outbox/replay store，
    /// 因此构建首页视图模型时不会跑重放、不回填冲突、不落定任何状态。
    func testBuildingHomeDoesNotTriggerOfflineReplaySideEffects() throws {
        let outbox = MobileOfflineOutboxStore.mock()
        let replay = MobileOfflineReplayStore()
        let pendingBefore = outbox.publicStatus.pendingCount

        let orchestrator = try makeOrchestrator()
        _ = orchestrator.makeViewModel(for: .child)
        _ = orchestrator.makeViewModel(for: .parent)

        XCTAssertFalse(replay.hasReplayed, "首页编排不应触发本地重放")
        XCTAssertTrue(replay.report.isEmpty, "首页编排不应产出重放报告")
        XCTAssertEqual(outbox.publicStatus.pendingCount, pendingBefore, "首页编排不应改动 outbox 队列")
    }

    // MARK: - 空数据回退

    func testEmptySnapshotProducesUsableChildHome() {
        let orchestrator = MobileHomeOrchestrator(
            sync: MobileSyncClient(snapshot: .empty),
            schoolFamily: SchoolFamilyStore(),
            family: LocalFamilyStore()
        )
        let vm = orchestrator.makeViewModel(for: .child)
        XCTAssertEqual(vm.perspective, .child)
        XCTAssertFalse(vm.greeting.isEmpty)
        XCTAssertFalse(vm.headline.isEmpty)
    }

    // MARK: - 奖励商店库存履约首页快捷路由（A97）

    func testChildHomeHasReadOnlyRewardStoreEntry() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)
        let section = try XCTUnwrap(
            vm.sections.first { $0.id == "reward-store-fulfillment" },
            "孩子首页必须有奖励商店只读入口分区"
        )
        let entry = try XCTUnwrap(
            section.items.first { $0.id == "reward-store-fulfillment-entry" },
            "奖励商店分区必须有快捷入口条目"
        )
        XCTAssertEqual(entry.destination, .rewardStoreFulfillment)
        XCTAssertEqual(entry.badge, "只读")
        // 孩子端文案只说明奖励库存只读，不暴露家长复核/履约/账本/地址语义。
        let detail = try XCTUnwrap(entry.detail)
        XCTAssertTrue(detail.contains("不会真的兑换"))
        XCTAssertFalse(detail.contains("履约"), "孩子首页入口文案不应出现履约等成人复核语义")
        XCTAssertFalse(detail.contains("退款"), "孩子首页入口文案不应出现退款原因等成人复核语义")
        XCTAssertFalse(detail.contains("账本"), "孩子首页入口文案不应出现账本明细")
        XCTAssertFalse(detail.contains("地址"), "孩子首页入口文案不应出现履约地址")
    }

    /// 孩子首页只能进入奖励商店（孩子视角），任何分区都不应出现指向家长复核页的入口。
    /// 角色锁在进入页（allowedRoles: [.child]）；首页层保证孩子拿到的入口文案是孩子框架。
    func testChildPerspectiveRewardStoreStaysChildFramedAndCannotReachGuardianReview() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .child)

        // 不会出现家长复核框架的标题/文案。
        let allStrings = displayedStrings(vm)
        XCTAssertFalse(allStrings.contains { $0.contains("奖励库存履约复核") },
            "孩子视角不应出现家长奖励库存履约复核入口")

        // 孩子可见的奖励商店入口仍指向同一受控 destination，但进入页会锁定孩子视角。
        let entries = vm.sections
            .flatMap(\.items)
            .filter { $0.destination == .rewardStoreFulfillment }
        XCTAssertFalse(entries.isEmpty, "孩子首页应有奖励商店入口")
        XCTAssertTrue(entries.allSatisfy { $0.title == "奖励商店" },
            "孩子首页奖励入口标题必须是孩子框架的「奖励商店」")
    }

    func testParentHomeHasRewardStoreFulfillmentReviewEntry() throws {
        let orchestrator = try makeOrchestrator()
        let vm = orchestrator.makeViewModel(for: .parent)
        let section = try XCTUnwrap(
            vm.sections.first { $0.id == "reward-store-fulfillment" },
            "家长首页必须有奖励库存履约复核只读入口分区"
        )
        let entry = try XCTUnwrap(
            section.items.first { $0.id == "reward-store-fulfillment-entry" },
            "奖励库存履约复核分区必须有快捷入口条目"
        )
        XCTAssertEqual(entry.destination, .rewardStoreFulfillment)
        XCTAssertEqual(entry.title, "奖励库存履约复核")
        XCTAssertEqual(entry.badge, "只读")
        // 家长端文案体现只读复核与不发货/不扣成长积分/不解锁设备边界。
        let detail = try XCTUnwrap(entry.detail)
        XCTAssertTrue(detail.contains("只读复核"))
        XCTAssertTrue(detail.contains("不真实兑换"))
        XCTAssertTrue(detail.contains("不扣成长积分"))
        XCTAssertTrue(detail.contains("不发货"))
        XCTAssertTrue(detail.contains("不解锁设备"))
    }

    func testRewardStoreFulfillmentDestinationAllowedPerspectives() {
        XCTAssertEqual(
            MobileHomeDestination.rewardStoreFulfillment.allowedPerspectives, [.child, .parent],
            "rewardStoreFulfillment 应允许孩子和家长视角进入（进入页按视角锁定单一角色）"
        )
        XCTAssertTrue(MobileHomeDestination.rewardStoreFulfillment.allowedPerspectives.contains(.child))
        XCTAssertTrue(MobileHomeDestination.rewardStoreFulfillment.allowedPerspectives.contains(.parent))
    }

    func testRewardStoreFulfillmentDestinationRawValueHasNoSensitiveMarkers() {
        let rawValue = MobileHomeDestination.rewardStoreFulfillment.rawValue
        let sensitiveMarkers = [
            "public", "ref", "task", "homework", "ledger", "device", "order",
            "inventory", "redemption", "gift", "address", "entitlement", "provider",
            "model", "transcript", "cloud", "http", "path", "token", "secret",
            "apikey", "api_key", "192.168.", "/users/", "/volumes/", "claimid", "taskid"
        ]
        for marker in sensitiveMarkers {
            XCTAssertFalse(
                rawValue.localizedCaseInsensitiveContains(marker),
                "rewardStoreFulfillment destination rawValue 不应含敏感标记：\(marker)"
            )
        }
    }

    /// 既有 rewardRedemption/rewardStatus 首页路由不回归：新增入口不夺走也不复用旧路由。
    func testRewardStoreFulfillmentDoesNotRegressExistingRewardRoutes() throws {
        let orchestrator = try makeOrchestrator()
        let childVM = orchestrator.makeViewModel(for: .child)
        let parentVM = orchestrator.makeViewModel(for: .parent)

        // 孩子成长积分区仍指向 rewardRedemption。
        let creditSection = try XCTUnwrap(childVM.sections.first { $0.id == "credit" })
        XCTAssertTrue(creditSection.items.contains { $0.destination == .rewardRedemption },
            "孩子成长积分区应仍有 rewardRedemption 入口")
        // 家长风险区仍指向 rewardStatus。
        let riskSection = try XCTUnwrap(parentVM.sections.first { $0.id == "risk" })
        XCTAssertTrue(riskSection.items.contains { $0.destination == .rewardStatus },
            "家长风险区应仍有 rewardStatus 入口")
        // 新增奖励商店入口不复用旧奖励兑换/状态路由。
        let storeEntries = (childVM.sections + parentVM.sections)
            .flatMap(\.items)
            .filter { $0.id == "reward-store-fulfillment-entry" }
        XCTAssertFalse(storeEntries.isEmpty)
        XCTAssertTrue(storeEntries.allSatisfy { $0.destination == .rewardStoreFulfillment },
            "奖励商店入口必须使用独立的 rewardStoreFulfillment 路由")
    }
}
