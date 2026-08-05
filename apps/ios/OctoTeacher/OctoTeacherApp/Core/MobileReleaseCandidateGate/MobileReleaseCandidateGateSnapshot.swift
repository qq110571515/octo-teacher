import Foundation

/// iOS 端移动 ReadModel 发布候选质量门。
///
/// 它只组合本地已经脱敏的 read models，回答“这一批移动端首页/详情/权限/家校投影
/// 是否可以进入发布候选”。这里不发布、不联网、不写账本、不通知、不解锁设备。
enum MobileReleaseCandidateGateViewerRole: String, CaseIterable, Equatable {
    case guardian
    case operations
    case child

    var label: String {
        switch self {
        case .guardian: return "家长"
        case .operations: return "运营"
        case .child: return "孩子"
        }
    }
}

enum MobileReleaseCandidateGateStatus: String, Equatable {
    case ready
    case warning
    case blocked

    var label: String {
        switch self {
        case .ready: return "可进入候选"
        case .warning: return "需要复核"
        case .blocked: return "阻断发布"
        }
    }
}

enum MobileReleaseCandidateGateCheckKind: String, CaseIterable, Equatable {
    case moduleKeys = "module_keys"
    case roleVisibility = "role_visibility"
    case nextAction = "next_action"
    case sideEffects = "side_effects"
    case publicSummary = "public_summary"
    case evidence = "evidence"
    case rollbackGate = "rollback_gate"
    case permissionGateway = "permission_gateway"
    case offlineSync = "offline_sync"
    case homeworkInbox = "homework_inbox"
    case jointApproval = "joint_approval"

    var title: String {
        switch self {
        case .moduleKeys: return "模块 key 稳定"
        case .roleVisibility: return "角色可见性"
        case .nextAction: return "下一步一致性"
        case .sideEffects: return "副作用护栏"
        case .publicSummary: return "公开摘要脱敏"
        case .evidence: return "测试与证据"
        case .rollbackGate: return "回滚门禁"
        case .permissionGateway: return "权限闸门"
        case .offlineSync: return "离线同步"
        case .homeworkInbox: return "作业家校收件箱"
        case .jointApproval: return "学校联合审批"
        }
    }
}

enum MobileReleaseCandidateGateFindingCode: String, Equatable {
    case gateOK = "MOBILE_RELEASE_CANDIDATE_GATE_OK"
    case moduleKeyDrift = "MODULE_KEY_DRIFT"
    case roleVisibilityConflict = "ROLE_VISIBILITY_CONFLICT"
    case nextActionWritesSystem = "NEXT_ACTION_WRITES_SYSTEM"
    case sideEffectDetected = "SIDE_EFFECT_DETECTED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
    case missingEvidence = "MISSING_EVIDENCE"
    case missingRollbackGate = "MISSING_ROLLBACK_GATE"
    case permissionGatewayBlocked = "PERMISSION_GATEWAY_BLOCKED"
    case offlineConflictActive = "OFFLINE_CONFLICT_ACTIVE"
    case homeworkInboxPending = "HOMEWORK_INBOX_PENDING"
    case jointApprovalPending = "JOINT_APPROVAL_PENDING"
}

enum MobileReleaseCandidateGateSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker

    var label: String {
        switch self {
        case .ok: return "通过"
        case .info: return "提示"
        case .warning: return "复核"
        case .blocker: return "阻断"
        }
    }
}

struct MobileReleaseCandidateGateEvidence: Equatable {
    var hasIosUnitTests: Bool
    var hasSnapshotFixtures: Bool
    var hasQwenReview: Bool
    var hasBridgeReport: Bool
    var hasRollbackGate: Bool

    static let complete = MobileReleaseCandidateGateEvidence(
        hasIosUnitTests: true,
        hasSnapshotFixtures: true,
        hasQwenReview: true,
        hasBridgeReport: true,
        hasRollbackGate: true
    )
}

struct MobileReleaseCandidateGateInput: Equatable {
    var generatedAt: String
    var aggregate: MobilePlatformAggregateSnapshot
    var permissionGateway: MobilePlatformPermissionGatewayReadModelReport
    var growthCloudSync: GrowthPackCloudSyncMobileBridgeSnapshot
    var homeworkInbox: AIHomeworkFamilySchoolInboxSnapshot
    var jointApproval: SchoolJointApprovalSnapshot
    var evidence: MobileReleaseCandidateGateEvidence
    var unsafePayload: [String]

    static func mock(
        viewerRole: MobileReleaseCandidateGateViewerRole,
        evidence: MobileReleaseCandidateGateEvidence = .complete,
        unsafePayload: [String] = []
    ) -> MobileReleaseCandidateGateInput {
        // This fixture factory composes deterministic in-memory stores only.
        // It never calls network, AI, LMS, ledger, notification, device, StoreKit,
        // FamilyControls, or cloud runtimes; all writes stay inside local mock
        // objects used to produce already-redacted read models.
        let family = LocalFamilyStore()
        let school = SchoolFamilyStore()
        let runtime = GrowthPackRuntimeStore().refresh(family: family, schoolFamily: school)
        let evidenceTimeline = GrowthEvidenceTimelineStore().refresh(
            family: family,
            schoolFamily: school,
            runtime: GrowthEvidenceTimelineRuntimeContext(report: runtime)
        )
        let offlineOutbox = MobileOfflineOutboxStore.mock()
        let offlineReplayStore = MobileOfflineReplayStore()
        let replay = offlineReplayStore.replay(outbox: offlineOutbox)
        let creditStore = MobileCreditSettlementStore()
        creditStore.refresh(
            offlineReport: replay,
            family: family,
            schoolFamily: school,
            screenTime: MockScreenTimeController()
        )

        let aggregateRole = aggregateRole(for: viewerRole)
        let growth = GrowthPackMobileDetailSnapshotBuilder().build(
            viewerRole: growthRole(for: aggregateRole),
            runtimeReport: runtime,
            evidenceReport: evidenceTimeline,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: replay
        )
        let schoolCredit = SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: schoolRole(for: aggregateRole),
            homeworks: school.homeworks,
            runtimeReport: runtime,
            evidenceReport: evidenceTimeline,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: replay
        )
        let achievement = FamilyAchievementSnapshotDashboardBuilder()
            .dashboard(for: familyRole(for: aggregateRole))
        let aggregate = MobilePlatformAggregateSnapshotBuilder().build(
            viewerRole: aggregateRole,
            mobileSnapshot: MobileSyncClient.makeMockOrEmpty().snapshot,
            familyAchievement: achievement,
            growthPack: growth,
            schoolCredit: schoolCredit,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: replay,
            creditSettlement: creditStore.report
        )
        let permission = MobilePlatformPermissionGatewayAdapter().buildReadModel(
            viewerRole: permissionRole(for: viewerRole),
            aggregate: aggregate
        )
        let cloud = GrowthPackCloudSyncMobileBridgeBuilder().build(
            viewerRole: cloudRole(for: viewerRole)
        )
        let inbox = AIHomeworkFamilySchoolInboxBuilder().build(
            viewerRole: inboxRole(for: viewerRole),
            homeworks: school.homeworks
        )
        let joint = SchoolJointApprovalSnapshotBuilder().build(
            viewerRole: jointRole(for: viewerRole),
            homeworks: school.homeworks,
            schoolCredit: schoolCredit,
            creditSettlement: creditStore.report,
            offlineStatus: offlineOutbox.publicStatus,
            offlineReport: replay
        )

        return MobileReleaseCandidateGateInput(
            generatedAt: "2026-06-24T15:30:00Z",
            aggregate: aggregate,
            permissionGateway: permission,
            growthCloudSync: cloud,
            homeworkInbox: inbox,
            jointApproval: joint,
            evidence: evidence,
            unsafePayload: unsafePayload
        )
    }

    private static func aggregateRole(for role: MobileReleaseCandidateGateViewerRole) -> MobilePlatformAggregateViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .operations: return .guardian
        }
    }

    private static func permissionRole(for role: MobileReleaseCandidateGateViewerRole) -> MobilePlatformPermissionGatewayViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .operations: return .guardian
        }
    }

    private static func cloudRole(for role: MobileReleaseCandidateGateViewerRole) -> GrowthPackCloudSyncMobileBridgeViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .operations: return .operations
        }
    }

    private static func inboxRole(for role: MobileReleaseCandidateGateViewerRole) -> AIHomeworkFamilySchoolInboxViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .operations: return .operations
        }
    }

    private static func jointRole(for role: MobileReleaseCandidateGateViewerRole) -> SchoolJointApprovalViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .operations: return .guardian
        }
    }

    private static func growthRole(for role: MobilePlatformAggregateViewerRole) -> GrowthPackMobileDetailViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        case .teacher: return .teacher
        }
    }

    private static func schoolRole(for role: MobilePlatformAggregateViewerRole) -> SchoolGrowthCreditViewerRole {
        switch role {
        case .child, .relative: return .child
        case .guardian: return .guardian
        case .teacher: return .teacher
        }
    }

    private static func familyRole(for role: MobilePlatformAggregateViewerRole) -> FamilyGrowthViewerRole {
        switch role {
        case .child, .teacher: return .child
        case .guardian: return .guardian
        case .relative: return .relative
        }
    }
}

struct MobileReleaseCandidateGateCheck: Identifiable, Equatable {
    var publicCheckRef: String
    var kind: MobileReleaseCandidateGateCheckKind
    var title: String
    var detail: String
    var severity: MobileReleaseCandidateGateSeverity
    var findingCode: MobileReleaseCandidateGateFindingCode
    var passed: Bool
    var actionRequired: Bool
    var visibleToChild: Bool

    var id: String { publicCheckRef }
}

struct MobileReleaseCandidateGateNextAction: Identifiable, Equatable {
    var publicActionRef: String
    var title: String
    var detail: String
    var severity: MobileReleaseCandidateGateSeverity
    var visibleToChild: Bool

    let writesSystem = false
    let sendsNotification = false

    var id: String { publicActionRef }
}

struct MobileReleaseCandidateGatePublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: MobileReleaseCandidateGateViewerRole
    var status: MobileReleaseCandidateGateStatus
    var visibleCheckCount: Int
    var blockerCount: Int
    var warningCount: Int
    var actionRequiredCount: Int
    var findingCodes: [MobileReleaseCandidateGateFindingCode]

    let writesLedger = false
    let unlocksDevice = false
    let writesSchoolSystem = false
    let callsLms = false
    let sendsNotification = false
    let uploadsAttachment = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsCloud = false
    let writesEntitlement = false
    let createsOrder = false
}

struct MobileReleaseCandidateGateSideEffects: Equatable {
    let writesLedger = false
    let unlocksDevice = false
    let writesSchoolSystem = false
    let callsLms = false
    let sendsNotification = false
    let uploadsAttachment = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsCloud = false
    let writesEntitlement = false
    let createsOrder = false

    var hasTriggeredSideEffect: Bool {
        writesLedger || unlocksDevice || writesSchoolSystem || callsLms || sendsNotification
            || uploadsAttachment || callsAiProvider || callsLocalModel || callsCloud
            || writesEntitlement || createsOrder
    }
}

struct MobileReleaseCandidateGateSnapshot: Equatable {
    var generatedAt: String
    var viewerRole: MobileReleaseCandidateGateViewerRole
    var status: MobileReleaseCandidateGateStatus
    var headline: String
    var checks: [MobileReleaseCandidateGateCheck]
    var nextActions: [MobileReleaseCandidateGateNextAction]
    var publicSummary: MobileReleaseCandidateGatePublicSummary
    var sideEffects: MobileReleaseCandidateGateSideEffects

    var displayValues: [String] {
        [generatedAt, viewerRole.rawValue, status.rawValue, headline]
            + checks.flatMap { [$0.publicCheckRef, $0.kind.rawValue, $0.title, $0.detail, $0.severity.rawValue, $0.findingCode.rawValue] }
            + nextActions.flatMap { [$0.publicActionRef, $0.title, $0.detail, $0.severity.rawValue] }
            + publicSummary.findingCodes.map(\.rawValue)
    }
}

struct MobileReleaseCandidateGateBuilder {
    var redactionSalt = "mobile-release-candidate-gate-ios-v1"

    private static let sensitiveDisplayMarkers = [
        "child:", "family:", "school:", "teacher:", "relative:", "guardian:",
        "task:", "claim:", "proof:", "ledger:", "device:", "order:", "entitlement:",
        "gpi-order", "gpi-ent", "publicref", "provider:", "model:", "baseurl",
        "api_key", "apikey", "token", "secret", "qwen", "claude", "openai",
        "http://", "https://", "file://", "/users/", "/volumes/", "192.168."
    ]

    private static let sensitiveDisplayPatterns = [
        #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
        #"(?i)\b[0-9a-f]{24,}\b"#,
        #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
    ]

    func build(
        viewerRole: MobileReleaseCandidateGateViewerRole,
        input: MobileReleaseCandidateGateInput? = nil
    ) -> MobileReleaseCandidateGateSnapshot {
        let resolved = input ?? .mock(viewerRole: viewerRole)
        if hasUnsafeInput(resolved) {
            return safeFallback(viewerRole: viewerRole, generatedAt: resolved.generatedAt)
        }

        let rawChecks = makeChecks(input: resolved, viewerRole: viewerRole)
        let visibleChecks = rawChecks
            .filter { viewerRole != .child || $0.visibleToChild }
            .map { viewerRole == .child ? childSafeCheck($0) : $0 }
        let status = status(for: rawChecks)
        let actions = nextActions(from: rawChecks, viewerRole: viewerRole)
        let snapshot = MobileReleaseCandidateGateSnapshot(
            generatedAt: resolved.generatedAt,
            viewerRole: viewerRole,
            status: status,
            headline: headline(for: status, viewerRole: viewerRole),
            checks: visibleChecks,
            nextActions: actions,
            publicSummary: MobileReleaseCandidateGatePublicSummary(
                generatedAt: resolved.generatedAt,
                viewerRole: viewerRole,
                status: status,
                visibleCheckCount: visibleChecks.count,
                blockerCount: rawChecks.filter { $0.severity == .blocker }.count,
                warningCount: rawChecks.filter { $0.severity == .warning }.count,
                actionRequiredCount: rawChecks.filter(\.actionRequired).count,
                findingCodes: rawChecks.filter { !$0.passed }.map(\.findingCode)
            ),
            sideEffects: MobileReleaseCandidateGateSideEffects()
        )

        return redacts(snapshot) ? snapshot : safeFallback(viewerRole: viewerRole, generatedAt: resolved.generatedAt)
    }

    func redacts(_ snapshot: MobileReleaseCandidateGateSnapshot) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(snapshot.displayValues) { return false }
        let joined = snapshot.displayValues.joined(separator: " ").lowercased()
        if Self.sensitiveDisplayMarkers.contains(where: { joined.contains($0) }) { return false }
        return !Self.sensitiveDisplayPatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func makeChecks(
        input: MobileReleaseCandidateGateInput,
        viewerRole: MobileReleaseCandidateGateViewerRole
    ) -> [MobileReleaseCandidateGateCheck] {
        var checks: [MobileReleaseCandidateGateCheck] = []

        let expectedModules = Set(MobilePlatformPermissionGatewayModuleKey.allCases)
        let actualModules = Set(input.permissionGateway.modules.map(\.module))
        checks.append(check(
            .moduleKeys,
            passed: actualModules == expectedModules,
            severity: actualModules == expectedModules ? .ok : .blocker,
            finding: actualModules == expectedModules ? .gateOK : .moduleKeyDrift,
            detail: actualModules == expectedModules ? "8 个共享权限模块 key 保持稳定。" : "共享权限模块 key 发生漂移，发布候选需阻断。",
            visibleToChild: false
        ))

        let roleOk = roleVisibilityIsConsistent(input: input, viewerRole: viewerRole)
        checks.append(check(
            .roleVisibility,
            passed: roleOk,
            severity: roleOk ? .ok : .blocker,
            finding: roleOk ? .gateOK : .roleVisibilityConflict,
            detail: roleOk ? "当前视角的模块可见性与移动端规则一致。" : "当前视角出现不应可见的内部模块或成人字段。",
            visibleToChild: true
        ))

        let nextActionsReadOnly = input.permissionGateway.nextActions.allSatisfy { !$0.writesSystem && !$0.sendsNotification }
            && input.homeworkInbox.nextActions.allSatisfy { !$0.writesSystem && !$0.sendsNotification }
        checks.append(check(
            .nextAction,
            passed: nextActionsReadOnly,
            severity: nextActionsReadOnly ? .ok : .blocker,
            finding: nextActionsReadOnly ? .gateOK : .nextActionWritesSystem,
            detail: nextActionsReadOnly ? "下一步只展示只读提示，不触发系统写入。" : "发现下一步会写系统或通知，必须阻断。",
            visibleToChild: false
        ))

        let sideEffectsOk = sideEffectsAreFalse(input)
        checks.append(check(
            .sideEffects,
            passed: sideEffectsOk,
            severity: sideEffectsOk ? .ok : .blocker,
            finding: sideEffectsOk ? .gateOK : .sideEffectDetected,
            detail: sideEffectsOk ? "所有上游快照副作用均为 false。" : "发现上游快照存在真实副作用标记。",
            visibleToChild: true
        ))

        let summariesRedact = redactsDisplayValues(input)
        checks.append(check(
            .publicSummary,
            passed: summariesRedact,
            severity: summariesRedact ? .ok : .blocker,
            finding: summariesRedact ? .gateOK : .publicSummaryLeak,
            detail: summariesRedact ? "公开摘要未发现 URL、路径、token、订单、权益或原始引用泄露。" : "公开摘要脱敏失败，发布候选阻断。",
            visibleToChild: true
        ))

        let evidenceOk = input.evidence.hasIosUnitTests
            && input.evidence.hasSnapshotFixtures
            && input.evidence.hasQwenReview
            && input.evidence.hasBridgeReport
        checks.append(check(
            .evidence,
            passed: evidenceOk,
            severity: evidenceOk ? .ok : .warning,
            finding: evidenceOk ? .gateOK : .missingEvidence,
            detail: evidenceOk ? "iOS 测试、快照证据、QWEN 复核和交接报告齐备。" : "测试或复核证据不完整，需要主控补齐。",
            visibleToChild: false
        ))

        checks.append(check(
            .rollbackGate,
            passed: input.evidence.hasRollbackGate,
            severity: input.evidence.hasRollbackGate ? .ok : .blocker,
            finding: input.evidence.hasRollbackGate ? .gateOK : .missingRollbackGate,
            detail: input.evidence.hasRollbackGate ? "回滚门禁已登记。" : "缺少回滚门禁，不能进入发布候选。",
            visibleToChild: false
        ))

        let permissionOk = input.permissionGateway.accepted && input.permissionGateway.state != .blocked
        checks.append(check(
            .permissionGateway,
            passed: permissionOk,
            severity: permissionOk ? .ok : .blocker,
            finding: permissionOk ? .gateOK : .permissionGatewayBlocked,
            detail: permissionOk ? "权限闸门未阻断发布候选。" : "权限闸门阻断，发布候选必须暂停。",
            visibleToChild: true
        ))

        let offlineAttention = input.aggregate.offlineSync.conflictCount
            + input.aggregate.offlineSync.rollbackRequiredCount
            + input.growthCloudSync.publicSummary.offlineAttentionCount
        checks.append(check(
            .offlineSync,
            passed: offlineAttention == 0,
            severity: offlineAttention == 0 ? .ok : .warning,
            finding: offlineAttention == 0 ? .gateOK : .offlineConflictActive,
            detail: offlineAttention == 0 ? "离线同步没有候选阻断。" : "\(offlineAttention) 个离线冲突或回滚信号需要复核。",
            visibleToChild: true
        ))

        let inboxPending = input.homeworkInbox.publicSummary.actionRequiredCount
            + input.homeworkInbox.publicSummary.lmsBlockedCount
        checks.append(check(
            .homeworkInbox,
            passed: inboxPending == 0,
            severity: inboxPending == 0 ? .ok : .warning,
            finding: inboxPending == 0 ? .gateOK : .homeworkInboxPending,
            detail: inboxPending == 0 ? "作业家校收件箱没有候选阻断。" : "\(inboxPending) 个家校作业事项需要复核。",
            visibleToChild: true
        ))

        let jointPending = input.jointApproval.publicSummary.awaitingTeacherCount
            + input.jointApproval.publicSummary.awaitingGuardianCount
            + input.jointApproval.publicSummary.returnedCount
            + input.jointApproval.publicSummary.appealFrozenCount
            + input.jointApproval.publicSummary.offlineRollbackCount
            + input.jointApproval.publicSummary.creditNoteCount
        checks.append(check(
            .jointApproval,
            passed: jointPending == 0,
            severity: jointPending == 0 ? .ok : .warning,
            finding: jointPending == 0 ? .gateOK : .jointApprovalPending,
            detail: jointPending == 0 ? "学校联合审批没有候选阻断。" : "\(jointPending) 个联合审批信号仍需复核。",
            visibleToChild: true
        ))

        return checks
    }

    private func roleVisibilityIsConsistent(
        input: MobileReleaseCandidateGateInput,
        viewerRole: MobileReleaseCandidateGateViewerRole
    ) -> Bool {
        switch viewerRole {
        case .child:
            let sensitiveModules: Set<MobilePlatformPermissionGatewayModuleKey> = [
                .marketplaceEntitlement,
                .creditConsentReconciliation,
                .operationsReview
            ]
            let hiddenSensitive = input.permissionGateway.modules
                .filter { sensitiveModules.contains($0.module) }
                .allSatisfy { $0.visibility == .hidden }
            return hiddenSensitive
                && input.homeworkInbox.publicSummary.viewerRole == .child
                && input.jointApproval.publicSummary.viewerRole == .child
                && !input.homeworkInbox.publicSummary.showsCreditAmount
                && !input.homeworkInbox.publicSummary.revealsProviderOrModel
        case .guardian:
            return input.permissionGateway.viewer.role == .guardian
                && input.homeworkInbox.publicSummary.viewerRole == .guardian
                && input.jointApproval.publicSummary.viewerRole == .guardian
        case .operations:
            return input.growthCloudSync.publicSummary.viewerRole == .operations
                && input.homeworkInbox.publicSummary.viewerRole == .operations
        }
    }

    private func sideEffectsAreFalse(_ input: MobileReleaseCandidateGateInput) -> Bool {
        !input.permissionGateway.sideEffects.hasTriggeredSideEffect
            && !input.growthCloudSync.sideEffects.hasTriggeredSideEffect
            && !input.homeworkInbox.sideEffects.hasTriggeredSideEffect
            && !input.jointApproval.publicSummary.verifiesTeacher
            && !input.jointApproval.publicSummary.confirmsGuardian
            && !input.jointApproval.publicSummary.returnsHomework
            && !input.jointApproval.publicSummary.freezesCredit
            && !input.jointApproval.publicSummary.writesLedger
            && !input.jointApproval.publicSummary.writesSchoolHomework
            && !input.jointApproval.publicSummary.sendsNotification
            && !input.jointApproval.publicSummary.unlocksDevice
            && !input.jointApproval.publicSummary.callsSchoolSystem
            && !input.jointApproval.publicSummary.callsLms
            && !input.jointApproval.publicSummary.usesAiToAnswer
            && !input.aggregate.publicSummary.writesLedger
            && !input.aggregate.publicSummary.unlocksDevice
            && !input.aggregate.publicSummary.callsCloud
            && !input.aggregate.publicSummary.usesAiToAnswer
    }

    private func redactsDisplayValues(_ input: MobileReleaseCandidateGateInput) -> Bool {
        var values: [String] = []
        values.append(contentsOf: input.permissionGateway.displayValues)
        values.append(input.growthCloudSync.headline)
        values.append(contentsOf: input.growthCloudSync.findings.map(\.message))
        values.append(input.homeworkInbox.headline)
        values.append(contentsOf: input.homeworkInbox.findings.map(\.message))
        values.append(contentsOf: input.jointApproval.items.flatMap { [$0.headline, $0.childSafeCopy, $0.guardianReason ?? ""] })
        values.append(contentsOf: input.aggregate.moduleCards.flatMap { [$0.title, $0.subtitle, $0.metricLabel] })
        return redacts(values)
    }

    private func hasUnsafeInput(_ input: MobileReleaseCandidateGateInput) -> Bool {
        MobileSyncPayloadGuard.isUnsafe(input.unsafePayload) || !redacts(input.unsafePayload)
    }

    private func redacts(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ").lowercased()
        if Self.sensitiveDisplayMarkers.contains(where: { joined.contains($0) }) { return false }
        return !Self.sensitiveDisplayPatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func status(for checks: [MobileReleaseCandidateGateCheck]) -> MobileReleaseCandidateGateStatus {
        if checks.contains(where: { $0.severity == .blocker }) { return .blocked }
        if checks.contains(where: { $0.severity == .warning }) { return .warning }
        return .ready
    }

    private func nextActions(
        from checks: [MobileReleaseCandidateGateCheck],
        viewerRole: MobileReleaseCandidateGateViewerRole
    ) -> [MobileReleaseCandidateGateNextAction] {
        checks
            .filter { !$0.passed && (viewerRole != .child || $0.visibleToChild) }
            .map { check in
                MobileReleaseCandidateGateNextAction(
                    publicActionRef: publicRef("mrc-action", "\(check.kind.rawValue)-\(check.findingCode.rawValue)"),
                    title: actionTitle(for: check),
                    detail: viewerRole == .child ? "请等家长复核后再继续。" : check.detail,
                    severity: check.severity,
                    visibleToChild: check.visibleToChild
                )
            }
    }

    private func check(
        _ kind: MobileReleaseCandidateGateCheckKind,
        passed: Bool,
        severity: MobileReleaseCandidateGateSeverity,
        finding: MobileReleaseCandidateGateFindingCode,
        detail: String,
        visibleToChild: Bool
    ) -> MobileReleaseCandidateGateCheck {
        MobileReleaseCandidateGateCheck(
            publicCheckRef: publicRef("mrc-check", "\(kind.rawValue)-\(finding.rawValue)-\(detail)"),
            kind: kind,
            title: kind.title,
            detail: sanitize(detail, fallback: "请查看发布候选质量门。"),
            severity: severity,
            findingCode: finding,
            passed: passed,
            actionRequired: !passed,
            visibleToChild: visibleToChild
        )
    }

    private func childSafeCheck(_ check: MobileReleaseCandidateGateCheck) -> MobileReleaseCandidateGateCheck {
        MobileReleaseCandidateGateCheck(
            publicCheckRef: check.publicCheckRef,
            kind: check.kind,
            title: check.title,
            detail: check.passed ? "这一项对孩子端是安全的。" : "这一项需要家长复核后再继续。",
            severity: check.severity,
            findingCode: check.findingCode,
            passed: check.passed,
            actionRequired: check.actionRequired,
            visibleToChild: true
        )
    }

    private func actionTitle(for check: MobileReleaseCandidateGateCheck) -> String {
        switch check.findingCode {
        case .missingRollbackGate: return "补齐回滚门禁"
        case .missingEvidence: return "补齐测试与复核证据"
        case .permissionGatewayBlocked: return "复核权限闸门"
        case .offlineConflictActive: return "处理离线冲突"
        case .homeworkInboxPending: return "复核家校作业事项"
        case .jointApprovalPending: return "复核学校联合审批"
        case .moduleKeyDrift: return "冻结模块 key 漂移"
        case .roleVisibilityConflict: return "修复角色可见性"
        case .nextActionWritesSystem, .sideEffectDetected, .publicSummaryLeak: return "阻断候选并修复安全问题"
        case .gateOK: return "保持只读候选"
        }
    }

    private func headline(
        for status: MobileReleaseCandidateGateStatus,
        viewerRole: MobileReleaseCandidateGateViewerRole
    ) -> String {
        if viewerRole == .child {
            return status == .ready ? "移动端可以继续体验" : "移动端正在等家长复核"
        }
        switch status {
        case .ready: return "移动端发布候选质量门通过"
        case .warning: return "移动端发布候选需要复核"
        case .blocked: return "移动端发布候选已阻断"
        }
    }

    private func sanitize(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return redacts([trimmed]) ? trimmed : fallback
    }

    private func publicRef(_ prefix: String, _ seed: String) -> String {
        "\(prefix)-\(stableHash("\(redactionSalt):\(seed)"))"
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return String(hash, radix: 16)
    }

    private func safeFallback(
        viewerRole: MobileReleaseCandidateGateViewerRole,
        generatedAt: String
    ) -> MobileReleaseCandidateGateSnapshot {
        let fallback = check(
            .publicSummary,
            passed: false,
            severity: .blocker,
            finding: .publicSummaryLeak,
            detail: "发布候选质量门未通过脱敏检查，已进入安全保护模式。",
            visibleToChild: true
        )
        return MobileReleaseCandidateGateSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: .blocked,
            headline: "发布候选质量门已安全阻断",
            checks: [viewerRole == .child ? childSafeCheck(fallback) : fallback],
            nextActions: [
                MobileReleaseCandidateGateNextAction(
                    publicActionRef: publicRef("mrc-action", "fallback"),
                    title: viewerRole == .child ? "等待家长复核" : "阻断候选并修复脱敏问题",
                    detail: viewerRole == .child ? "请等家长复核后再继续。" : "发布候选质量门未通过公开摘要脱敏检查。",
                    severity: .blocker,
                    visibleToChild: true
                )
            ],
            publicSummary: MobileReleaseCandidateGatePublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: .blocked,
                visibleCheckCount: 1,
                blockerCount: 1,
                warningCount: 0,
                actionRequiredCount: 1,
                findingCodes: [.publicSummaryLeak]
            ),
            sideEffects: MobileReleaseCandidateGateSideEffects()
        )
    }
}
