import Foundation

/// iOS 端「成长包移动详情快照」。
///
/// 对齐控制台 B31 契约的手机消费语义：把成长包运行结算、证据申诉时间线和离线同步状态
/// 合成一个角色感知、脱敏、无副作用的详情快照。它只服务展示，不发成长积分、不授徽章、
/// 不改任务/作业终态、不通知、不上传媒体、不解锁设备。

enum GrowthPackMobileDetailViewerRole: String, Equatable, CaseIterable {
    case child
    case guardian
    case relative
    case teacher

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        case .teacher: return "老师"
        }
    }
}

enum GrowthPackMobileDetailStatus: String, Equatable {
    case ready
    case needsProof = "needs_proof"
    case reviewRequired = "review_required"
    case appealed
    case blocked
    case voided

    var label: String {
        switch self {
        case .ready: return "可继续"
        case .needsProof: return "需要证明"
        case .reviewRequired: return "等待审核"
        case .appealed: return "申诉中"
        case .blocked: return "已阻断"
        case .voided: return "已作废"
        }
    }
}

enum GrowthPackMobileStepStatus: String, Equatable {
    case ready
    case needsProof = "needs_proof"
    case waitingReview = "waiting_review"
    case complete
    case blocked

    var label: String {
        switch self {
        case .ready: return "可继续"
        case .needsProof: return "需提交证明"
        case .waitingReview: return "等待复核"
        case .complete: return "已完成"
        case .blocked: return "已阻断"
        }
    }
}

enum GrowthPackMobileCreditPreviewState: String, Equatable {
    case availablePreview = "available_preview"
    case frozen
    case blocked
    case duplicate
    case alreadyCredited = "already_credited"

    var label: String {
        switch self {
        case .availablePreview: return "可建议"
        case .frozen: return "冻结中"
        case .blocked: return "已阻断"
        case .duplicate: return "重复忽略"
        case .alreadyCredited: return "已结算"
        }
    }
}

enum GrowthPackMobileDetailFindingCode: String, Equatable {
    case snapshotOK = "DETAIL_SNAPSHOT_OK"
    case runtimePlanBlocked = "RUNTIME_PLAN_BLOCKED"
    case settlementBlocked = "SETTLEMENT_BLOCKED"
    case creditNotUsable = "CREDIT_NOT_USABLE"
    case appealReviewRequired = "APPEAL_REVIEW_REQUIRED"
    case relativeReviewHiddenFromChild = "RELATIVE_REVIEW_HIDDEN_FROM_CHILD"
    case offlineSyncActionRequired = "OFFLINE_SYNC_ACTION_REQUIRED"
    case teacherGuardianConflict = "TEACHER_GUARDIAN_CONFLICT"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

enum GrowthPackMobileDetailSeverity: String, Equatable {
    case info
    case warning
    case blocker
    case ok
}

struct GrowthPackMobileDetailFinding: Identifiable, Equatable {
    var code: GrowthPackMobileDetailFindingCode
    var severity: GrowthPackMobileDetailSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct GrowthPackMobileDetailHeader: Equatable {
    var publicPackRef: String
    var childPublicRef: String
    var viewerRole: GrowthPackMobileDetailViewerRole
    var status: GrowthPackMobileDetailStatus
    var manifestVersion: String
    var generatedAt: String
}

struct GrowthPackMobileDetailTask: Identifiable, Equatable {
    var publicTaskRef: String
    var childPublicRef: String
    var title: String
    var category: String
    var status: GrowthPackMobileStepStatus
    var plannedFor: String
    var priority: Int
    var hasSubmittedProof: Bool

    var id: String { publicTaskRef }
}

struct GrowthPackMobileDetailStep: Identifiable, Equatable {
    var publicStepRef: String
    var publicTaskRef: String
    var childPublicRef: String
    var order: Int
    var kindLabel: String
    var systemImage: String
    var title: String
    var status: GrowthPackMobileStepStatus
    var requiresProof: Bool
    var visibleToChild: Bool
    var reason: String
    var nextStep: String

    var id: String { publicStepRef }
}

struct GrowthPackMobileDetailProofRequirement: Identifiable, Equatable {
    var publicRequirementRef: String
    var publicTaskRef: String
    var childPublicRef: String
    var kindLabel: String
    var verifierRoles: [GrowthPackMobileDetailViewerRole]
    var evidenceRefsOnly: Bool
    var visibleToChild: Bool

    var id: String { publicRequirementRef }
}

struct GrowthPackMobileDetailNextAction: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case submitProof = "submit_proof"
        case guardianReview = "guardian_review"
        case teacherReview = "teacher_review"
        case appealReview = "appeal_review"
        case offlineSync = "offline_sync"
        case readOnly = "read_only"

        var label: String {
            switch self {
            case .submitProof: return "提交证明"
            case .guardianReview: return "家长审核"
            case .teacherReview: return "老师验证"
            case .appealReview: return "申诉复核"
            case .offlineSync: return "同步处理"
            case .readOnly: return "只读查看"
            }
        }
    }

    enum Severity: String, Equatable {
        case info
        case warning
        case urgent
    }

    var publicActionRef: String
    var kind: Kind
    var title: String
    var severity: Severity
    var actionRequired: Bool
    var visibleToChild: Bool

    var id: String { publicActionRef }
}

struct GrowthPackMobileDetailCreditPreview: Identifiable, Equatable {
    var publicCreditPreviewRef: String
    var sourceStatus: GrowthRuntimeProjectionStatus
    var state: GrowthPackMobileCreditPreviewState
    var amount: Int
    var reason: String
    var usableFor: [String]

    let writesLedger = false
    let unlocksDevice = false

    var id: String { publicCreditPreviewRef }
    var creditLabel: String { "\(amount) 成长积分" }
}

struct GrowthPackMobileDetailRewardSummary: Equatable {
    var creditPreviewCount: Int
    var availableCreditPreviewCount: Int
    var frozenCreditPreviewCount: Int
    var blockedCreditPreviewCount: Int
    var totalAvailablePreviewCredit: Int
    var badgeSuggestionCount: Int
    var abilitySuggestionCount: Int
    var eventDraftCount: Int

    let grantsBadge = false
    let updatesAbilityCard = false
    let emitsEvent = false
    let publishesHonorWall = false
}

struct GrowthPackMobileDetailTimelineItem: Identifiable, Equatable {
    var publicItemRef: String
    var kindLabel: String
    var statusLabel: String
    var summary: String

    var id: String { publicItemRef }
}

struct GrowthPackMobileDetailEvidenceAppealSummary: Equatable {
    var publicCaseRef: String
    var chainEventCount: Int
    var publicTimelineCount: Int
    var appealCount: Int
    var creditFrozenCount: Int
    var creditReleasedCount: Int
    var creditBlockedCount: Int
    var conflictCount: Int
    var relativeReviewCount: Int
    var revocationActionRequiredCount: Int
    var visibleTimeline: [GrowthPackMobileDetailTimelineItem]

    let modifiesHomework = false
    let writesLedger = false
}

struct GrowthPackMobileDetailOfflineHint: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case pendingSync = "pending_sync"
        case conflict
        case rolledBack = "rolled_back"
        case clean
    }

    var publicHintRef: String
    var kind: Kind
    var severity: GrowthPackMobileDetailNextAction.Severity
    var title: String
    var message: String
    var actionRequired: Bool
    var retryable: Bool
    var visibleToChild: Bool

    let sendsNotification = false

    var id: String { publicHintRef }
}

struct GrowthPackMobileDetailRoleVisibility: Equatable {
    var viewerRole: GrowthPackMobileDetailViewerRole
    var canSeeProofRequirements: Bool
    var canSeeSettlementPreview: Bool
    var canSeeGuardianReviewQueue: Bool
    var canSeeRelativeReview: Bool
    var canSeeOfflineDeviceFailures: Bool
}

struct GrowthPackMobileDetailPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: GrowthPackMobileDetailViewerRole
    var publicPackRef: String
    var childPublicRef: String
    var status: GrowthPackMobileDetailStatus
    var taskCount: Int
    var stepCount: Int
    var proofRequirementCount: Int
    var nextActionCount: Int
    var creditPreviewCount: Int
    var availableCreditPreviewCount: Int
    var appealCount: Int
    var offlineHintCount: Int
    var findingCodes: [GrowthPackMobileDetailFindingCode]

    let writesLedger = false
    let grantsBadge = false
    let updatesAbilityCard = false
    let emitsEvent = false
    let publishesHonorWall = false
    let modifiesTaskState = false
    let modifiesHomework = false
    let sendsNotification = false
    let unlocksDevice = false
    let uploadsMedia = false
}

struct GrowthPackMobileDetailSnapshot: Equatable {
    var generatedAt: String
    var header: GrowthPackMobileDetailHeader
    var tasks: [GrowthPackMobileDetailTask]
    var steps: [GrowthPackMobileDetailStep]
    var proofRequirements: [GrowthPackMobileDetailProofRequirement]
    var nextActions: [GrowthPackMobileDetailNextAction]
    var creditPreviews: [GrowthPackMobileDetailCreditPreview]
    var rewardSummary: GrowthPackMobileDetailRewardSummary
    var evidenceAppealSummary: GrowthPackMobileDetailEvidenceAppealSummary
    var offlineHints: [GrowthPackMobileDetailOfflineHint]
    var roleVisibility: GrowthPackMobileDetailRoleVisibility
    var findings: [GrowthPackMobileDetailFinding]
    var publicSummary: GrowthPackMobileDetailPublicSummary
}

struct GrowthPackMobileDetailSnapshotBuilder {
    var generatedAt: String = "2026-06-24T03:00:00Z"
    var manifestVersion: String = "ios-local-b31-v1"
    var redactionSalt: String = "growth-pack-mobile-detail-ios-v1"

    func build(
        viewerRole: GrowthPackMobileDetailViewerRole,
        runtimeReport: GrowthRuntimeSettlementReport,
        evidenceReport: GrowthEvidenceTimelineReport,
        offlineStatus: MobileOfflinePublicStatus = .clean,
        offlineReport: MobileOfflineReplayReport = .empty
    ) -> GrowthPackMobileDetailSnapshot {
        let visibility = roleVisibility(for: viewerRole)
        let header = GrowthPackMobileDetailHeader(
            publicPackRef: publicRef("gpd", runtimeReport.packTitle.isEmpty ? "empty-pack" : runtimeReport.packTitle),
            childPublicRef: runtimeReport.publicSummary.childPublicRef.isEmpty
                ? publicRef("kid", "empty-child")
                : publicRef("kid", runtimeReport.publicSummary.childPublicRef),
            viewerRole: viewerRole,
            status: status(runtimeReport: runtimeReport, evidenceReport: evidenceReport, offlineStatus: offlineStatus),
            manifestVersion: manifestVersion,
            generatedAt: generatedAt
        )
        let tasks = mapTasks(runtimeReport)
        let steps = mapSteps(runtimeReport)
        let proofRequirements = visibility.canSeeProofRequirements ? mapProofRequirements(runtimeReport) : []
        let nextActions = mapNextActions(
            viewerRole: viewerRole,
            runtimeReport: runtimeReport,
            evidenceReport: evidenceReport,
            offlineStatus: offlineStatus,
            offlineReport: offlineReport
        )
        let rawCreditPreviews = mapCreditPreviews(runtimeReport)
        let creditPreviews = visibility.canSeeSettlementPreview ? rawCreditPreviews : []
        let reward = rewardSummary(creditPreviews: creditPreviews, canSeeSettlement: visibility.canSeeSettlementPreview)
        let evidence = evidenceSummary(evidenceReport, visibility: visibility)
        let offline = mapOfflineHints(status: offlineStatus, replay: offlineReport, visibility: visibility)
        let findings = collectFindings(
            viewerRole: viewerRole,
            runtimeReport: runtimeReport,
            evidenceReport: evidenceReport,
            offlineStatus: offlineStatus,
            offlineReport: offlineReport,
            creditPreviews: creditPreviews,
            visibility: visibility
        )
        let publicSummary = GrowthPackMobileDetailPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            publicPackRef: header.publicPackRef,
            childPublicRef: header.childPublicRef,
            status: header.status,
            taskCount: tasks.count,
            stepCount: steps.count,
            proofRequirementCount: proofRequirements.count,
            nextActionCount: nextActions.count,
            creditPreviewCount: creditPreviews.count,
            availableCreditPreviewCount: creditPreviews.filter { $0.state == .availablePreview }.count,
            appealCount: evidence.appealCount,
            offlineHintCount: offline.count,
            findingCodes: findings.map(\.code)
        )
        let snapshot = GrowthPackMobileDetailSnapshot(
            generatedAt: generatedAt,
            header: header,
            tasks: tasks,
            steps: steps,
            proofRequirements: proofRequirements,
            nextActions: nextActions,
            creditPreviews: creditPreviews,
            rewardSummary: reward,
            evidenceAppealSummary: evidence,
            offlineHints: offline,
            roleVisibility: visibility,
            findings: findings,
            publicSummary: publicSummary
        )
        return redacts(snapshot) ? snapshot : safeFallback(for: viewerRole)
    }

    func redacts(_ snapshot: GrowthPackMobileDetailSnapshot) -> Bool {
        let values = publicStrings(snapshot)
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        return !values.joined(separator: " ").localizedCaseInsensitiveContains("child:")
            && !values.joined(separator: " ").localizedCaseInsensitiveContains("family:")
            && !values.joined(separator: " ").localizedCaseInsensitiveContains("task:")
            && !values.joined(separator: " ").localizedCaseInsensitiveContains("proof:")
            && !values.joined(separator: " ").localizedCaseInsensitiveContains("ledger:")
            && !values.joined(separator: " ").localizedCaseInsensitiveContains("device:")
    }

    // MARK: - mapping

    private func roleVisibility(for role: GrowthPackMobileDetailViewerRole) -> GrowthPackMobileDetailRoleVisibility {
        switch role {
        case .guardian:
            return GrowthPackMobileDetailRoleVisibility(
                viewerRole: role,
                canSeeProofRequirements: true,
                canSeeSettlementPreview: true,
                canSeeGuardianReviewQueue: true,
                canSeeRelativeReview: true,
                canSeeOfflineDeviceFailures: true
            )
        case .teacher:
            return GrowthPackMobileDetailRoleVisibility(
                viewerRole: role,
                canSeeProofRequirements: true,
                canSeeSettlementPreview: false,
                canSeeGuardianReviewQueue: false,
                canSeeRelativeReview: false,
                canSeeOfflineDeviceFailures: false
            )
        case .child:
            return GrowthPackMobileDetailRoleVisibility(
                viewerRole: role,
                canSeeProofRequirements: true,
                canSeeSettlementPreview: false,
                canSeeGuardianReviewQueue: false,
                canSeeRelativeReview: false,
                canSeeOfflineDeviceFailures: false
            )
        case .relative:
            return GrowthPackMobileDetailRoleVisibility(
                viewerRole: role,
                canSeeProofRequirements: false,
                canSeeSettlementPreview: false,
                canSeeGuardianReviewQueue: false,
                canSeeRelativeReview: false,
                canSeeOfflineDeviceFailures: false
            )
        }
    }

    private func status(
        runtimeReport: GrowthRuntimeSettlementReport,
        evidenceReport: GrowthEvidenceTimelineReport,
        offlineStatus: MobileOfflinePublicStatus
    ) -> GrowthPackMobileDetailStatus {
        if runtimeReport.steps.contains(where: { $0.status == .voided }) { return .voided }
        if runtimeReport.steps.contains(where: { $0.status == .blocked })
            || evidenceReport.findings.contains(where: { $0.severity == .blocker }) {
            return .blocked
        }
        if runtimeReport.steps.contains(where: { $0.isAppealing })
            || evidenceReport.appealDecisions.contains(where: { $0.state == .open }) {
            return .appealed
        }
        if runtimeReport.steps.contains(where: { $0.status == .reviewRequired })
            || evidenceReport.hasAttention
            || offlineStatus.hasAttention {
            return .reviewRequired
        }
        if runtimeReport.steps.contains(where: { $0.status == .planned || $0.proofStatus == .missing }) {
            return .needsProof
        }
        return .ready
    }

    private func mapTasks(_ report: GrowthRuntimeSettlementReport) -> [GrowthPackMobileDetailTask] {
        report.steps.map { step in
            GrowthPackMobileDetailTask(
                publicTaskRef: publicRef("work", step.publicStepRef),
                childPublicRef: publicRef("kid", step.childPublicRef),
                title: step.title,
                category: step.kindLabel,
                status: stepStatus(for: step),
                plannedFor: String(report.generatedAt.prefix(10)),
                priority: max(1, step.order),
                hasSubmittedProof: step.proofStatus != .missing && step.fromStage != .planned
            )
        }
    }

    private func mapSteps(_ report: GrowthRuntimeSettlementReport) -> [GrowthPackMobileDetailStep] {
        report.steps.map { step in
            GrowthPackMobileDetailStep(
                publicStepRef: publicRef("detail-step", step.publicStepRef),
                publicTaskRef: publicRef("work", step.publicStepRef),
                childPublicRef: publicRef("kid", step.childPublicRef),
                order: step.order,
                kindLabel: step.kindLabel,
                systemImage: step.systemImage,
                title: step.title,
                status: stepStatus(for: step),
                requiresProof: step.proofStatus == .missing || step.fromStage == .planned,
                visibleToChild: true,
                reason: step.reason,
                nextStep: step.nextStep
            )
        }
    }

    private func stepStatus(for step: GrowthRuntimeStepProjection) -> GrowthPackMobileStepStatus {
        if step.status == .blocked || step.status == .voided { return .blocked }
        if step.status == .alreadyCredited || step.status == .creditSuggested { return .complete }
        if step.status == .reviewRequired || step.isAppealing { return .waitingReview }
        if step.status == .planned || step.proofStatus == .missing { return .needsProof }
        return .ready
    }

    private func mapProofRequirements(_ report: GrowthRuntimeSettlementReport) -> [GrowthPackMobileDetailProofRequirement] {
        report.steps.map { step in
            let verifiers: [GrowthPackMobileDetailViewerRole] =
                step.kind == .schoolHomework ? [.teacher, .guardian] : [.guardian]
            return GrowthPackMobileDetailProofRequirement(
                publicRequirementRef: publicRef("req", step.publicStepRef),
                publicTaskRef: publicRef("work", step.publicStepRef),
                childPublicRef: publicRef("kid", step.childPublicRef),
                kindLabel: step.proofRequirementLabel,
                verifierRoles: verifiers,
                evidenceRefsOnly: true,
                visibleToChild: true
            )
        }
    }

    private func mapNextActions(
        viewerRole: GrowthPackMobileDetailViewerRole,
        runtimeReport: GrowthRuntimeSettlementReport,
        evidenceReport: GrowthEvidenceTimelineReport,
        offlineStatus: MobileOfflinePublicStatus,
        offlineReport: MobileOfflineReplayReport
    ) -> [GrowthPackMobileDetailNextAction] {
        var actions: [GrowthPackMobileDetailNextAction] = []

        for step in runtimeReport.steps {
            if step.status == .planned || step.proofStatus == .missing {
                actions.append(action(
                    seed: "submit:\(step.publicStepRef)",
                    kind: .submitProof,
                    title: "提交「\(step.title)」的证明",
                    severity: .info,
                    actionRequired: viewerRole == .child,
                    visibleToChild: true
                ))
            }
            if step.status == .reviewRequired && !step.isAppealing {
                let isSchool = step.kind == .schoolHomework
                let kind: GrowthPackMobileDetailNextAction.Kind = isSchool ? .teacherReview : .guardianReview
                let visibleToChild = viewerRole == .guardian || viewerRole == .teacher
                if visibleToChild {
                    actions.append(action(
                        seed: "review:\(step.publicStepRef)",
                        kind: kind,
                        title: isSchool ? "等待老师/家长验证「\(step.title)」" : "等待家长审核「\(step.title)」",
                        severity: .warning,
                        actionRequired: viewerRole == .guardian || (viewerRole == .teacher && isSchool),
                        visibleToChild: false
                    ))
                }
            }
        }

        for appeal in evidenceReport.appealDecisions where appeal.state == .open {
            if viewerRole == .guardian {
                actions.append(action(
                    seed: "appeal:\(appeal.publicAppealRef)",
                    kind: .appealReview,
                    title: "申诉证据需要家长复核",
                    severity: .warning,
                    actionRequired: true,
                    visibleToChild: false
                ))
            }
        }

        if viewerRole == .guardian && (offlineStatus.hasAttention || offlineReport.hasAttention) {
            actions.append(action(
                seed: "offline:\(offlineStatus.pendingCount):\(offlineStatus.conflictCount):\(offlineStatus.rolledBackCount)",
                kind: .offlineSync,
                title: "离线同步存在冲突或回滚，需要处理",
                severity: .urgent,
                actionRequired: true,
                visibleToChild: false
            ))
        }

        if actions.isEmpty {
            actions.append(action(
                seed: "readonly:\(viewerRole.rawValue)",
                kind: .readOnly,
                title: "只读查看成长包详情",
                severity: .info,
                actionRequired: false,
                visibleToChild: viewerRole == .child
            ))
        }

        return actions.filter { viewerRole == .guardian || viewerRole == .teacher || $0.visibleToChild }
    }

    private func mapCreditPreviews(_ report: GrowthRuntimeSettlementReport) -> [GrowthPackMobileDetailCreditPreview] {
        report.steps.map { step in
            let state = creditState(for: step)
            return GrowthPackMobileDetailCreditPreview(
                publicCreditPreviewRef: publicRef("credit-preview", step.publicStepRef),
                sourceStatus: step.status,
                state: state,
                amount: state == .availablePreview ? step.settlement.suggestedCredit : 0,
                reason: step.reason,
                usableFor: state == .availablePreview ? [step.settlement.scopeLabel] : []
            )
        }
    }

    private func creditState(for step: GrowthRuntimeStepProjection) -> GrowthPackMobileCreditPreviewState {
        switch step.status {
        case .creditSuggested: return .availablePreview
        case .duplicate: return .duplicate
        case .alreadyCredited: return .alreadyCredited
        case .blocked, .voided: return .blocked
        case .planned, .reviewRequired: return .frozen
        }
    }

    private func rewardSummary(
        creditPreviews: [GrowthPackMobileDetailCreditPreview],
        canSeeSettlement: Bool
    ) -> GrowthPackMobileDetailRewardSummary {
        let available = creditPreviews.filter { $0.state == .availablePreview }
        let frozen = creditPreviews.filter { $0.state == .frozen }
        let blocked = creditPreviews.filter { $0.state == .blocked }
        return GrowthPackMobileDetailRewardSummary(
            creditPreviewCount: creditPreviews.count,
            availableCreditPreviewCount: available.count,
            frozenCreditPreviewCount: frozen.count,
            blockedCreditPreviewCount: blocked.count,
            totalAvailablePreviewCredit: available.reduce(0) { $0 + $1.amount },
            badgeSuggestionCount: canSeeSettlement ? available.count : 0,
            abilitySuggestionCount: canSeeSettlement ? available.count : 0,
            eventDraftCount: canSeeSettlement ? available.count : 0
        )
    }

    private func evidenceSummary(
        _ report: GrowthEvidenceTimelineReport,
        visibility: GrowthPackMobileDetailRoleVisibility
    ) -> GrowthPackMobileDetailEvidenceAppealSummary {
        let canSeeAdultReview = visibility.canSeeGuardianReviewQueue || visibility.viewerRole == .teacher
        let visibleTimeline = report.publicTimeline
            .filter { visibility.viewerRole == .guardian || $0.visibility != .selectedRelatives }
            .prefix(6)
            .map { item in
                GrowthPackMobileDetailTimelineItem(
                    publicItemRef: publicRef("timeline-item", item.publicItemRef),
                    kindLabel: item.kindLabel,
                    statusLabel: item.status.label,
                    summary: item.summary
                )
            }
        return GrowthPackMobileDetailEvidenceAppealSummary(
            publicCaseRef: publicRef("case", report.publicSummary.publicCaseRef.isEmpty ? "empty-case" : report.publicSummary.publicCaseRef),
            chainEventCount: canSeeAdultReview ? report.nodes.count : report.childChainNodes.count,
            publicTimelineCount: report.publicTimeline.count,
            appealCount: report.appealDecisions.count,
            creditFrozenCount: canSeeAdultReview ? report.creditControls.filter { $0.state == .frozen }.count : 0,
            creditReleasedCount: canSeeAdultReview ? report.creditControls.filter { $0.state == .released }.count : 0,
            creditBlockedCount: canSeeAdultReview ? report.creditControls.filter { $0.state == .blocked }.count : 0,
            conflictCount: canSeeAdultReview ? report.conflictNodes.count : 0,
            relativeReviewCount: visibility.canSeeRelativeReview ? report.relativePendingNodes.count : 0,
            revocationActionRequiredCount: canSeeAdultReview ? report.revocationNodes.filter(\.actionRequired).count : 0,
            visibleTimeline: Array(visibleTimeline)
        )
    }

    private func mapOfflineHints(
        status: MobileOfflinePublicStatus,
        replay: MobileOfflineReplayReport,
        visibility: GrowthPackMobileDetailRoleVisibility
    ) -> [GrowthPackMobileDetailOfflineHint] {
        if !visibility.canSeeOfflineDeviceFailures {
            if status.pendingCount > 0 {
                return [
                    GrowthPackMobileDetailOfflineHint(
                        publicHintRef: publicRef("hint", "pending:\(status.pendingCount)"),
                        kind: .pendingSync,
                        severity: .info,
                        title: "有离线动作待同步",
                        message: "联网后仍需家长、老师或服务端流程确认。",
                        actionRequired: false,
                        retryable: true,
                        visibleToChild: true
                    )
                ]
            }
            return []
        }

        var hints: [GrowthPackMobileDetailOfflineHint] = []
        if status.pendingCount > 0 {
            hints.append(GrowthPackMobileDetailOfflineHint(
                publicHintRef: publicRef("hint", "pending:\(status.pendingCount)"),
                kind: .pendingSync,
                severity: .info,
                title: "待同步",
                message: "\(status.pendingCount) 条离线动作等待同步确认。",
                actionRequired: false,
                retryable: true,
                visibleToChild: false
            ))
        }
        if status.conflictCount > 0 || replay.conflictCount > 0 {
            hints.append(GrowthPackMobileDetailOfflineHint(
                publicHintRef: publicRef("hint", "conflict:\(status.conflictCount):\(replay.conflictCount)"),
                kind: .conflict,
                severity: .urgent,
                title: "同步冲突",
                message: "有离线动作与成人审核或服务端状态冲突，需要复核。",
                actionRequired: true,
                retryable: true,
                visibleToChild: false
            ))
        }
        if status.rolledBackCount > 0 || replay.rolledBackCount > 0 {
            hints.append(GrowthPackMobileDetailOfflineHint(
                publicHintRef: publicRef("hint", "rollback:\(status.rolledBackCount):\(replay.rolledBackCount)"),
                kind: .rolledBack,
                severity: .warning,
                title: "已回滚",
                message: "部分离线动作已回滚，不会自动发成长积分或解锁设备。",
                actionRequired: true,
                retryable: false,
                visibleToChild: false
            ))
        }
        return hints
    }

    private func collectFindings(
        viewerRole: GrowthPackMobileDetailViewerRole,
        runtimeReport: GrowthRuntimeSettlementReport,
        evidenceReport: GrowthEvidenceTimelineReport,
        offlineStatus: MobileOfflinePublicStatus,
        offlineReport: MobileOfflineReplayReport,
        creditPreviews: [GrowthPackMobileDetailCreditPreview],
        visibility: GrowthPackMobileDetailRoleVisibility
    ) -> [GrowthPackMobileDetailFinding] {
        var findings: [GrowthPackMobileDetailFinding] = []
        if runtimeReport.steps.contains(where: { $0.status == .blocked || $0.status == .voided }) {
            findings.append(finding(.runtimePlanBlocked, .blocker, "成长包运行详情存在阻断或作废步骤。", "runtime"))
        }
        if runtimeReport.findings.contains(where: { $0.severity == .blocker }) {
            findings.append(finding(.settlementBlocked, .blocker, "成长包结算投影存在阻断发现项。", "settlement"))
        }
        if creditPreviews.contains(where: { $0.state != .availablePreview }) {
            findings.append(finding(.creditNotUsable, .warning, "部分成长积分预览处于冻结、阻断、重复或已结算状态。", "credit"))
        }
        if evidenceReport.appealDecisions.contains(where: { $0.state == .open }) {
            findings.append(finding(.appealReviewRequired, .warning, "存在未关闭的证据申诉，成长积分不可直接使用。", "appeal"))
        }
        if viewerRole == .child && evidenceReport.relativePendingNodes.count > 0 {
            findings.append(finding(.relativeReviewHiddenFromChild, .info, "亲友待复核内容已从孩子视图隐藏。", "relative"))
        }
        if offlineStatus.hasAttention || offlineReport.hasAttention {
            findings.append(finding(.offlineSyncActionRequired, .warning, "离线同步存在待处理、冲突或回滚提示。", "offline"))
        }
        if evidenceReport.findings.contains(where: { $0.code == .teacherGuardianConflict }) {
            findings.append(finding(.teacherGuardianConflict, .blocker, "老师与家长的证据结论存在冲突。", "conflict"))
        }
        findings.append(finding(.roleVisibilityApplied, .info, "已按 \(visibility.viewerRole.label) 视角裁剪数据。", viewerRole.rawValue))
        if !findings.contains(where: { $0.severity == .blocker || $0.severity == .warning }) {
            findings.append(finding(.snapshotOK, .ok, "成长包移动详情快照已脱敏且无副作用。", "ok"))
        }
        return unique(findings)
    }

    // MARK: - helpers

    private func publicRef(_ prefix: String, _ source: String) -> String {
        Self.stablePublicRef(prefix: prefix, source: source, salt: redactionSalt)
    }

    static func stablePublicRef(prefix: String, source: String, salt: String = "growth-pack-mobile-detail-ios-v1") -> String {
        var hash: UInt32 = 5381
        for scalar in "\(salt):\(source)".unicodeScalars {
            hash = (hash &* 33) ^ UInt32(scalar.value)
        }
        let body = String(hash, radix: 36)
        let padded = body.count >= 7 ? body : String(repeating: "0", count: 7 - body.count) + body
        return "\(prefix):\(padded)"
    }

    private func action(
        seed: String,
        kind: GrowthPackMobileDetailNextAction.Kind,
        title: String,
        severity: GrowthPackMobileDetailNextAction.Severity,
        actionRequired: Bool,
        visibleToChild: Bool
    ) -> GrowthPackMobileDetailNextAction {
        GrowthPackMobileDetailNextAction(
            publicActionRef: publicRef("action", seed),
            kind: kind,
            title: title,
            severity: severity,
            actionRequired: actionRequired,
            visibleToChild: visibleToChild
        )
    }

    private func finding(
        _ code: GrowthPackMobileDetailFindingCode,
        _ severity: GrowthPackMobileDetailSeverity,
        _ message: String,
        _ seed: String
    ) -> GrowthPackMobileDetailFinding {
        GrowthPackMobileDetailFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("detail-finding", "\(code.rawValue):\(seed)")
        )
    }

    private func unique(_ findings: [GrowthPackMobileDetailFinding]) -> [GrowthPackMobileDetailFinding] {
        var seen = Set<String>()
        return findings.filter { finding in
            let key = "\(finding.code.rawValue):\(finding.publicRef)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func safeFallback(for role: GrowthPackMobileDetailViewerRole) -> GrowthPackMobileDetailSnapshot {
        let header = GrowthPackMobileDetailHeader(
            publicPackRef: publicRef("gpd", "redacted-pack"),
            childPublicRef: publicRef("kid", "redacted-child"),
            viewerRole: role,
            status: .blocked,
            manifestVersion: "redacted",
            generatedAt: generatedAt
        )
        let fallbackFinding = finding(
            .publicSummaryLeak,
            .blocker,
            "移动详情快照未通过公开脱敏检查，已进入安全降级模式。",
            "public-summary-leak"
        )
        let emptyReward = GrowthPackMobileDetailRewardSummary(
            creditPreviewCount: 0,
            availableCreditPreviewCount: 0,
            frozenCreditPreviewCount: 0,
            blockedCreditPreviewCount: 0,
            totalAvailablePreviewCredit: 0,
            badgeSuggestionCount: 0,
            abilitySuggestionCount: 0,
            eventDraftCount: 0
        )
        let emptyEvidence = GrowthPackMobileDetailEvidenceAppealSummary(
            publicCaseRef: publicRef("case", "redacted-case"),
            chainEventCount: 0,
            publicTimelineCount: 0,
            appealCount: 0,
            creditFrozenCount: 0,
            creditReleasedCount: 0,
            creditBlockedCount: 0,
            conflictCount: 0,
            relativeReviewCount: 0,
            revocationActionRequiredCount: 0,
            visibleTimeline: []
        )
        let summary = GrowthPackMobileDetailPublicSummary(
            generatedAt: generatedAt,
            viewerRole: role,
            publicPackRef: header.publicPackRef,
            childPublicRef: header.childPublicRef,
            status: .blocked,
            taskCount: 0,
            stepCount: 0,
            proofRequirementCount: 0,
            nextActionCount: 0,
            creditPreviewCount: 0,
            availableCreditPreviewCount: 0,
            appealCount: 0,
            offlineHintCount: 0,
            findingCodes: [.publicSummaryLeak]
        )
        return GrowthPackMobileDetailSnapshot(
            generatedAt: generatedAt,
            header: header,
            tasks: [],
            steps: [],
            proofRequirements: [],
            nextActions: [],
            creditPreviews: [],
            rewardSummary: emptyReward,
            evidenceAppealSummary: emptyEvidence,
            offlineHints: [],
            roleVisibility: roleVisibility(for: role),
            findings: [fallbackFinding],
            publicSummary: summary
        )
    }

    private func publicStrings(_ snapshot: GrowthPackMobileDetailSnapshot) -> [String] {
        var values: [String] = [
            snapshot.generatedAt,
            snapshot.header.publicPackRef,
            snapshot.header.childPublicRef,
            snapshot.header.manifestVersion,
            snapshot.header.status.label
        ]
        values += snapshot.tasks.flatMap {
            [$0.publicTaskRef, $0.childPublicRef, $0.title, $0.category, $0.status.label, $0.plannedFor]
        }
        values += snapshot.steps.flatMap {
            [$0.publicStepRef, $0.publicTaskRef, $0.childPublicRef, $0.kindLabel, $0.title, $0.status.label, $0.reason, $0.nextStep]
        }
        values += snapshot.proofRequirements.flatMap {
            [$0.publicRequirementRef, $0.publicTaskRef, $0.childPublicRef, $0.kindLabel]
        }
        values += snapshot.nextActions.flatMap { [$0.publicActionRef, $0.kind.label, $0.title] }
        values += snapshot.creditPreviews.flatMap {
            [$0.publicCreditPreviewRef, $0.sourceStatus.label, $0.state.label, $0.reason] + $0.usableFor
        }
        values += snapshot.evidenceAppealSummary.visibleTimeline.flatMap {
            [$0.publicItemRef, $0.kindLabel, $0.statusLabel, $0.summary]
        }
        values += snapshot.offlineHints.flatMap { [$0.publicHintRef, $0.title, $0.message] }
        values += snapshot.findings.flatMap { [$0.publicRef, $0.code.rawValue, $0.message] }
        values += snapshot.publicSummary.findingCodes.map(\.rawValue)
        return values
    }
}
