import Foundation

/// iOS 端「学校成长积分快照」。
///
/// 把学校作业、成长包结算预览、证据申诉时间线与离线同步状态合成一份角色感知、
/// 脱敏、无副作用的手机端只读快照。它只回答「现在谁该做什么」和「成长积分是否可建议」，
/// 绝不写学校作业终态、不调用学校系统、不发成长积分、不解锁设备、不上传附件。

enum SchoolGrowthCreditViewerRole: String, Equatable, CaseIterable {
    case child
    case guardian
    case teacher

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .teacher: return "老师"
        }
    }
}

enum SchoolGrowthCreditSnapshotStatus: String, Equatable {
    case ready
    case reviewRequired = "review_required"
    case appealed
    case offlineConflict = "offline_conflict"
    case blocked

    var label: String {
        switch self {
        case .ready: return "可继续"
        case .reviewRequired: return "等待验证"
        case .appealed: return "申诉冻结"
        case .offlineConflict: return "离线冲突"
        case .blocked: return "已阻断"
        }
    }
}

enum SchoolGrowthCreditAssignmentStatus: String, Equatable {
    case assigned
    case submitted
    case teacherVerified = "teacher_verified"
    case guardianConfirmed = "guardian_confirmed"
    case reviewRequired = "review_required"
    case appealed
    case offlineConflict = "offline_conflict"
    case blocked

    var label: String {
        switch self {
        case .assigned: return "待完成"
        case .submitted: return "已提交"
        case .teacherVerified: return "老师已验证"
        case .guardianConfirmed: return "家长已确认"
        case .reviewRequired: return "待复核"
        case .appealed: return "申诉中"
        case .offlineConflict: return "离线冲突"
        case .blocked: return "已阻断"
        }
    }
}

enum SchoolGrowthCreditPreviewState: String, Equatable {
    case availablePreview = "available_preview"
    case reviewRequired = "review_required"
    case frozen
    case blocked
    case duplicate
    case alreadyCredited = "already_credited"
    case voided

    var label: String {
        switch self {
        case .availablePreview: return "可建议"
        case .reviewRequired: return "待复核"
        case .frozen: return "已冻结"
        case .blocked: return "已阻断"
        case .duplicate: return "重复忽略"
        case .alreadyCredited: return "已结算"
        case .voided: return "已作废"
        }
    }
}

enum SchoolGrowthCreditFindingCode: String, Equatable {
    case snapshotOK = "SCHOOL_CREDIT_SNAPSHOT_OK"
    case schoolHomeworkBlocked = "SCHOOL_HOMEWORK_BLOCKED"
    case aiDirectAnswerBlocked = "AI_DIRECT_ANSWER_BLOCKED"
    case teacherGuardianConflict = "TEACHER_GUARDIAN_CONFLICT"
    case appealOrFreezeActive = "APPEAL_OR_FREEZE_ACTIVE"
    case offlineConflictActive = "OFFLINE_CONFLICT_ACTIVE"
    case creditNotUsable = "CREDIT_NOT_USABLE"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

enum SchoolGrowthCreditSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

struct SchoolGrowthCreditFinding: Identifiable, Equatable {
    var code: SchoolGrowthCreditFindingCode
    var severity: SchoolGrowthCreditSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct SchoolGrowthCreditHeader: Equatable {
    var viewerRole: SchoolGrowthCreditViewerRole
    var status: SchoolGrowthCreditSnapshotStatus
    var generatedAt: String
    var privacyScope: String
    var childPublicRefs: [String]
}

struct SchoolGrowthCreditAssignmentSnapshot: Identifiable, Equatable {
    var publicAssignmentRef: String
    var childPublicRef: String
    var title: String
    var subject: String
    var dueLabel: String
    var verificationMode: String
    var status: SchoolGrowthCreditAssignmentStatus
    var submissionCount: Int
    var canShowCreditAsUsable: Bool
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToTeacher: Bool

    var id: String { publicAssignmentRef }
}

struct SchoolGrowthCreditPreview: Identifiable, Equatable {
    var publicCreditPreviewRef: String
    var sourceStatus: GrowthRuntimeProjectionStatus
    var state: SchoolGrowthCreditPreviewState
    var amount: Int
    var reason: String

    let writesLedger = false
    let unlocksDevice = false

    var id: String { publicCreditPreviewRef }
    var amountLabel: String { "\(amount) 成长积分" }
}

struct SchoolGrowthCreditHomeworkStatus: Equatable {
    var assignmentCount: Int
    var submissionCount: Int
    var verificationCount: Int
    var schoolFindingCount: Int
    var aiBoundaryBlockedCount: Int

    let writesSchoolHomework = false
}

struct SchoolGrowthCreditEvidenceStatus: Equatable {
    var publicCaseRef: String
    var timelineEventCount: Int
    var appealCount: Int
    var openAppealCount: Int
    var creditFrozenCount: Int
    var creditBlockedCount: Int

    let modifiesHomework = false
    let writesLedger = false
}

struct SchoolGrowthCreditOfflineStatus: Equatable {
    var cardCount: Int
    var conflictCount: Int
    var rollbackRequiredCount: Int
    var actionRequiredCount: Int

    let sendsNotification = false
    let writesTask = false
    let writesCredit = false
}

struct SchoolGrowthCreditVisibility: Equatable {
    var viewerRole: SchoolGrowthCreditViewerRole
    var canSeeSubmission: Bool
    var canSeeTeacherVerification: Bool
    var canSeeGuardianConfirmation: Bool
    var canSeeCreditPreview: Bool
    var canSeeOfflineConflicts: Bool
    var canSeeAppealState: Bool
}

struct SchoolGrowthCreditNextAction: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case submitHomework = "submit_homework"
        case teacherVerify = "teacher_verify"
        case guardianConfirm = "guardian_confirm"
        case resolveAppeal = "resolve_appeal"
        case resolveOfflineConflict = "resolve_offline_conflict"
        case readOnly = "read_only"

        var label: String {
            switch self {
            case .submitHomework: return "提交作业"
            case .teacherVerify: return "老师验证"
            case .guardianConfirm: return "家长确认"
            case .resolveAppeal: return "处理申诉"
            case .resolveOfflineConflict: return "处理离线冲突"
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

struct SchoolGrowthCreditPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: SchoolGrowthCreditViewerRole
    var status: SchoolGrowthCreditSnapshotStatus
    var assignmentCount: Int
    var creditPreviewCount: Int
    var usableCreditPreviewCount: Int
    var appealCount: Int
    var offlineConflictCount: Int
    var findingCodes: [SchoolGrowthCreditFindingCode]

    let writesSchoolHomework = false
    let modifiesHomework = false
    let writesLedger = false
    let sendsNotification = false
    let unlocksDevice = false
    let uploadsAttachment = false
    let callsSchoolSystem = false
    let usesAiToAnswer = false
}

struct SchoolGrowthCreditSnapshot: Equatable {
    var generatedAt: String
    var header: SchoolGrowthCreditHeader
    var assignments: [SchoolGrowthCreditAssignmentSnapshot]
    var creditPreviews: [SchoolGrowthCreditPreview]
    var homeworkStatus: SchoolGrowthCreditHomeworkStatus
    var evidenceStatus: SchoolGrowthCreditEvidenceStatus
    var offlineStatus: SchoolGrowthCreditOfflineStatus
    var visibility: SchoolGrowthCreditVisibility
    var nextActions: [SchoolGrowthCreditNextAction]
    var findings: [SchoolGrowthCreditFinding]
    var publicSummary: SchoolGrowthCreditPublicSummary
}

struct SchoolGrowthCreditSnapshotBuilder {
    private let generatedAt: String
    private let redactionSalt: String

    init(
        generatedAt: String = "2026-06-24T06:00:00Z",
        redactionSalt: String = "school-growth-credit-ios-snapshot-v1"
    ) {
        self.generatedAt = generatedAt
        self.redactionSalt = redactionSalt
    }

    func build(
        viewerRole: SchoolGrowthCreditViewerRole,
        homeworks: [SchoolHomework],
        runtimeReport: GrowthRuntimeSettlementReport = .empty,
        evidenceReport: GrowthEvidenceTimelineReport = .empty,
        offlineStatus: MobileOfflinePublicStatus = .clean,
        offlineReport: MobileOfflineReplayReport = .empty
    ) -> SchoolGrowthCreditSnapshot {
        let visibility = visibility(for: viewerRole)
        if hasUnsafeInput(homeworks: homeworks, runtimeReport: runtimeReport, evidenceReport: evidenceReport) {
            return safeFallback(viewerRole: viewerRole, visibility: visibility)
        }

        let evidenceFrozen = hasEvidenceFreeze(evidenceReport)
        let offlineNeedsAttention = hasOfflineConflict(offlineStatus: offlineStatus, offlineReport: offlineReport)
        let aiBlockedCount = homeworks.filter { hasDirectAnswerRisk($0.guidance) }.count
        let assignments = homeworks.enumerated().map { index, homework in
            assignment(
                homework,
                order: index,
                visibility: visibility,
                evidenceFrozen: evidenceFrozen,
                offlineNeedsAttention: offlineNeedsAttention,
                aiBlocked: hasDirectAnswerRisk(homework.guidance)
            )
        }
        let creditPreviews = visibility.canSeeCreditPreview
            ? previews(
                for: homeworks,
                runtimeReport: runtimeReport,
                evidenceFrozen: evidenceFrozen,
                offlineNeedsAttention: offlineNeedsAttention,
                aiBlockedCount: aiBlockedCount
            )
            : []
        let findings = findings(
            viewerRole: viewerRole,
            visibility: visibility,
            homeworks: homeworks,
            evidenceReport: evidenceReport,
            offlineStatus: offlineStatus,
            offlineReport: offlineReport,
            creditPreviews: creditPreviews,
            aiBlockedCount: aiBlockedCount
        )
        let status = headerStatus(
            viewerRole: viewerRole,
            homeworks: homeworks,
            evidenceFrozen: evidenceFrozen,
            offlineNeedsAttention: offlineNeedsAttention,
            aiBlockedCount: aiBlockedCount
        )
        let body = SchoolGrowthCreditSnapshot(
            generatedAt: generatedAt,
            header: SchoolGrowthCreditHeader(
                viewerRole: viewerRole,
                status: status,
                generatedAt: generatedAt,
                privacyScope: viewerRole == .child ? "private" : "care_team",
                childPublicRefs: [publicRef("pupil", "school-credit-child")]
            ),
            assignments: assignments,
            creditPreviews: creditPreviews,
            homeworkStatus: SchoolGrowthCreditHomeworkStatus(
                assignmentCount: assignments.count,
                submissionCount: homeworks.filter { $0.status == .submitted || $0.status == .verified }.count,
                verificationCount: homeworks.filter { $0.status == .verified }.count,
                schoolFindingCount: homeworks.filter { $0.status == .returned }.count,
                aiBoundaryBlockedCount: aiBlockedCount
            ),
            evidenceStatus: evidenceStatus(evidenceReport, visibility: visibility),
            offlineStatus: mapOfflineStatus(
                offlineStatus,
                offlineReport: offlineReport,
                visibility: visibility
            ),
            visibility: visibility,
            nextActions: nextActions(
                viewerRole: viewerRole,
                homeworks: homeworks,
                evidenceFrozen: evidenceFrozen,
                offlineNeedsAttention: offlineNeedsAttention,
                visibility: visibility
            ),
            findings: findings,
            publicSummary: SchoolGrowthCreditPublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: status,
                assignmentCount: assignments.count,
                creditPreviewCount: creditPreviews.count,
                usableCreditPreviewCount: creditPreviews.filter { $0.state == .availablePreview }.count,
                appealCount: visibility.canSeeAppealState ? evidenceReport.appealDecisions.count : 0,
                offlineConflictCount: visibility.canSeeOfflineConflicts ? visibleOfflineConflictCount(offlineStatus, offlineReport) : 0,
                findingCodes: findings.map(\.code)
            )
        )

        if !redacts(body) {
            return safeFallback(viewerRole: viewerRole, visibility: visibility)
        }
        return body
    }

    func redacts(_ snapshot: SchoolGrowthCreditSnapshot) -> Bool {
        !hasUnsafeDisplayValues(displayValues(snapshot))
    }

    // MARK: - Visibility

    private func visibility(for role: SchoolGrowthCreditViewerRole) -> SchoolGrowthCreditVisibility {
        switch role {
        case .child:
            return SchoolGrowthCreditVisibility(
                viewerRole: role,
                canSeeSubmission: true,
                canSeeTeacherVerification: false,
                canSeeGuardianConfirmation: false,
                canSeeCreditPreview: false,
                canSeeOfflineConflicts: false,
                canSeeAppealState: false
            )
        case .guardian:
            return SchoolGrowthCreditVisibility(
                viewerRole: role,
                canSeeSubmission: true,
                canSeeTeacherVerification: true,
                canSeeGuardianConfirmation: true,
                canSeeCreditPreview: true,
                canSeeOfflineConflicts: true,
                canSeeAppealState: true
            )
        case .teacher:
            return SchoolGrowthCreditVisibility(
                viewerRole: role,
                canSeeSubmission: true,
                canSeeTeacherVerification: true,
                canSeeGuardianConfirmation: false,
                canSeeCreditPreview: false,
                canSeeOfflineConflicts: false,
                canSeeAppealState: true
            )
        }
    }

    // MARK: - Mapping

    private func assignment(
        _ homework: SchoolHomework,
        order: Int,
        visibility: SchoolGrowthCreditVisibility,
        evidenceFrozen: Bool,
        offlineNeedsAttention: Bool,
        aiBlocked: Bool
    ) -> SchoolGrowthCreditAssignmentSnapshot {
        let status: SchoolGrowthCreditAssignmentStatus
        if homework.status == .returned || aiBlocked {
            status = .blocked
        } else if visibility.canSeeAppealState && evidenceFrozen && homework.status == .verified {
            status = .appealed
        } else if visibility.canSeeOfflineConflicts && offlineNeedsAttention && homework.status == .verified {
            status = .offlineConflict
        } else {
            switch homework.status {
            case .assigned, .inProgress:
                status = .assigned
            case .submitted:
                status = .submitted
            case .verified:
                status = .teacherVerified
            case .returned:
                status = .blocked
            }
        }

        return SchoolGrowthCreditAssignmentSnapshot(
            publicAssignmentRef: publicRef("hw", "\(homework.id.uuidString):\(order)"),
            childPublicRef: publicRef("pupil", "school-credit-child"),
            title: homework.title,
            subject: homework.subject.label,
            dueLabel: homework.dueLabel,
            verificationMode: verificationMode(for: homework),
            status: status,
            submissionCount: homework.status == .submitted || homework.status == .verified ? 1 : 0,
            canShowCreditAsUsable: status == .guardianConfirmed,
            visibleToChild: true,
            visibleToGuardian: true,
            visibleToTeacher: visibility.canSeeTeacherVerification
        )
    }

    private func previews(
        for homeworks: [SchoolHomework],
        runtimeReport: GrowthRuntimeSettlementReport,
        evidenceFrozen: Bool,
        offlineNeedsAttention: Bool,
        aiBlockedCount: Int
    ) -> [SchoolGrowthCreditPreview] {
        let runtimeSchoolSteps = runtimeReport.steps.filter { $0.kind == .schoolHomework }
        return homeworks.enumerated().compactMap { index, homework in
            guard homework.status != .assigned && homework.status != .inProgress else { return nil }
            let runtimeStep = runtimeSchoolSteps[safe: index]
            let sourceStatus = sourceStatus(for: homework, runtimeStep: runtimeStep)
            let state = previewState(
                homework: homework,
                sourceStatus: sourceStatus,
                evidenceFrozen: evidenceFrozen,
                offlineNeedsAttention: offlineNeedsAttention,
                aiBlockedCount: aiBlockedCount
            )
            let amount = state == .availablePreview ? max(runtimeStep?.settlement.suggestedCredit ?? 12, 1) : 0
            return SchoolGrowthCreditPreview(
                publicCreditPreviewRef: publicRef("cred", "\(homework.id.uuidString):\(sourceStatus.rawValue):\(index)"),
                sourceStatus: sourceStatus,
                state: state,
                amount: amount,
                reason: previewReason(homework: homework, state: state, runtimeStep: runtimeStep)
            )
        }
    }

    private func sourceStatus(
        for homework: SchoolHomework,
        runtimeStep: GrowthRuntimeStepProjection?
    ) -> GrowthRuntimeProjectionStatus {
        if let runtimeStep { return runtimeStep.status }
        switch homework.status {
        case .assigned, .inProgress:
            return .planned
        case .submitted:
            return .reviewRequired
        case .verified:
            return .creditSuggested
        case .returned:
            return .blocked
        }
    }

    private func previewState(
        homework: SchoolHomework,
        sourceStatus: GrowthRuntimeProjectionStatus,
        evidenceFrozen: Bool,
        offlineNeedsAttention: Bool,
        aiBlockedCount: Int
    ) -> SchoolGrowthCreditPreviewState {
        if homework.status == .returned || aiBlockedCount > 0 { return .blocked }
        if evidenceFrozen { return .frozen }
        if offlineNeedsAttention { return .reviewRequired }
        switch sourceStatus {
        case .creditSuggested:
            return homework.status == .verified ? .availablePreview : .reviewRequired
        case .reviewRequired, .planned:
            return .reviewRequired
        case .blocked:
            return .blocked
        case .duplicate:
            return .duplicate
        case .alreadyCredited:
            return .alreadyCredited
        case .voided:
            return .voided
        }
    }

    private func previewReason(
        homework: SchoolHomework,
        state: SchoolGrowthCreditPreviewState,
        runtimeStep: GrowthRuntimeStepProjection?
    ) -> String {
        switch state {
        case .availablePreview:
            return runtimeStep?.reason ?? "作业已验证，可进入家长确认后的成长积分建议。"
        case .reviewRequired:
            return homework.status == .submitted ? "已提交，等待老师验证与家长确认。" : "需要复核后才能展示可用成长积分。"
        case .frozen:
            return "证据链存在申诉或成长积分冻结，暂不展示可用成长积分。"
        case .blocked:
            return homework.status == .returned ? "作业被退回，需要孩子重新完成后再提交。" : "安全边界阻断了成长积分建议。"
        case .duplicate:
            return "检测到重复结算建议，本地只读忽略。"
        case .alreadyCredited:
            return "该作业过去已经结算，不重复建议。"
        case .voided:
            return "该作业结算投影已作废。"
        }
    }

    private func evidenceStatus(
        _ report: GrowthEvidenceTimelineReport,
        visibility: SchoolGrowthCreditVisibility
    ) -> SchoolGrowthCreditEvidenceStatus {
        let canSeeAppeal = visibility.canSeeAppealState
        return SchoolGrowthCreditEvidenceStatus(
            publicCaseRef: publicRef("caseview", report.publicSummary.publicCaseRef.isEmpty ? "school-growth-case" : report.publicSummary.publicCaseRef),
            timelineEventCount: report.nodes.count,
            appealCount: canSeeAppeal ? report.appealDecisions.count : 0,
            openAppealCount: canSeeAppeal ? report.appealDecisions.filter { $0.state == .open }.count : 0,
            creditFrozenCount: canSeeAppeal ? report.creditControls.filter { $0.state == .frozen }.count : 0,
            creditBlockedCount: canSeeAppeal ? report.creditControls.filter { $0.state == .blocked }.count : 0
        )
    }

    private func mapOfflineStatus(
        _ status: MobileOfflinePublicStatus,
        offlineReport: MobileOfflineReplayReport,
        visibility: SchoolGrowthCreditVisibility
    ) -> SchoolGrowthCreditOfflineStatus {
        let visibleConflicts = visibility.canSeeOfflineConflicts ? visibleOfflineConflictCount(status, offlineReport) : 0
        let visibleRollback = visibility.canSeeOfflineConflicts
            ? max(status.rolledBackCount, offlineReport.rolledBackCount)
            : 0
        let actionCount = visibility.canSeeOfflineConflicts
            ? visibleConflicts + visibleRollback
            : 0
        return SchoolGrowthCreditOfflineStatus(
            cardCount: visibility.canSeeOfflineConflicts ? status.pendingCount + status.conflictCount + status.rolledBackCount : status.pendingCount,
            conflictCount: visibleConflicts,
            rollbackRequiredCount: visibleRollback,
            actionRequiredCount: actionCount
        )
    }

    // MARK: - Status, actions, findings

    private func headerStatus(
        viewerRole: SchoolGrowthCreditViewerRole,
        homeworks: [SchoolHomework],
        evidenceFrozen: Bool,
        offlineNeedsAttention: Bool,
        aiBlockedCount: Int
    ) -> SchoolGrowthCreditSnapshotStatus {
        if aiBlockedCount > 0 { return .blocked }
        if homeworks.allSatisfy({ $0.status == .returned }) && !homeworks.isEmpty { return .blocked }
        if viewerRole != .child && evidenceFrozen { return .appealed }
        if viewerRole == .guardian && offlineNeedsAttention { return .offlineConflict }
        if homeworks.contains(where: { $0.status == .submitted || $0.status == .returned || $0.status == .verified }) {
            return .reviewRequired
        }
        return .ready
    }

    private func nextActions(
        viewerRole: SchoolGrowthCreditViewerRole,
        homeworks: [SchoolHomework],
        evidenceFrozen: Bool,
        offlineNeedsAttention: Bool,
        visibility: SchoolGrowthCreditVisibility
    ) -> [SchoolGrowthCreditNextAction] {
        var actions: [SchoolGrowthCreditNextAction] = []
        func push(_ kind: SchoolGrowthCreditNextAction.Kind, _ title: String, _ severity: SchoolGrowthCreditNextAction.Severity, _ required: Bool, _ visibleToChild: Bool) {
            actions.append(SchoolGrowthCreditNextAction(
                publicActionRef: publicRef("act", "\(viewerRole.rawValue):\(kind.rawValue):\(actions.count)"),
                kind: kind,
                title: title,
                severity: severity,
                actionRequired: required,
                visibleToChild: visibleToChild
            ))
        }

        if viewerRole == .child {
            if homeworks.contains(where: { $0.status.acceptsSubmission }) {
                push(.submitHomework, "完成作业并提交脱敏证明，等待老师或家长验证。", .info, true, true)
            } else {
                push(.readOnly, "作业已经提交，等待大人验证结果。", .info, false, true)
            }
            return actions
        }

        if homeworks.contains(where: { $0.status == .submitted }) {
            push(.teacherVerify, "已提交作业需要老师验证。", .urgent, true, false)
        }
        if viewerRole == .guardian && homeworks.contains(where: { $0.status == .verified }) {
            push(.guardianConfirm, "已验证作业可由家长确认后进入成长积分建议。", .warning, true, false)
        }
        if viewerRole == .guardian && evidenceFrozen && visibility.canSeeAppealState {
            push(.resolveAppeal, "存在申诉或冻结，需要先处理再展示可用成长积分。", .urgent, true, false)
        }
        if viewerRole == .guardian && offlineNeedsAttention && visibility.canSeeOfflineConflicts {
            push(.resolveOfflineConflict, "离线冲突或回滚需要家长处理。", .warning, true, false)
        }
        if actions.isEmpty {
            push(.readOnly, "学校成长积分快照可只读查看。", .info, false, false)
        }
        return actions
    }

    private func findings(
        viewerRole: SchoolGrowthCreditViewerRole,
        visibility: SchoolGrowthCreditVisibility,
        homeworks: [SchoolHomework],
        evidenceReport: GrowthEvidenceTimelineReport,
        offlineStatus: MobileOfflinePublicStatus,
        offlineReport: MobileOfflineReplayReport,
        creditPreviews: [SchoolGrowthCreditPreview],
        aiBlockedCount: Int
    ) -> [SchoolGrowthCreditFinding] {
        var result: [SchoolGrowthCreditFinding] = []
        func push(_ code: SchoolGrowthCreditFindingCode, _ severity: SchoolGrowthCreditSeverity, _ message: String) {
            result.append(SchoolGrowthCreditFinding(
                code: code,
                severity: severity,
                message: message,
                publicRef: publicRef("find", "\(viewerRole.rawValue):\(code.rawValue):\(result.count)")
            ))
        }

        if homeworks.contains(where: { $0.status == .returned }) {
            push(.schoolHomeworkBlocked, .warning, "存在被退回的作业，相关作业不能进入可用成长积分。")
        }
        if aiBlockedCount > 0 {
            push(.aiDirectAnswerBlocked, .blocker, "AI 引导疑似包含直接答案，成长积分建议被阻断。")
        }
        if viewerRole != .child && !evidenceReport.conflictNodes.isEmpty {
            push(.teacherGuardianConflict, .blocker, "老师与家长结论存在冲突，需要成人复核。")
        }
        if visibility.canSeeAppealState && hasEvidenceFreeze(evidenceReport) {
            push(.appealOrFreezeActive, .blocker, "申诉或成长积分冻结期间不能展示可用成长积分。")
        }
        if visibility.canSeeOfflineConflicts && hasOfflineConflict(offlineStatus: offlineStatus, offlineReport: offlineReport) {
            push(.offlineConflictActive, .warning, "离线冲突或回滚需要处理后再继续。")
        }
        if visibility.canSeeCreditPreview && !creditPreviews.isEmpty && creditPreviews.allSatisfy({ $0.state != .availablePreview }) {
            push(.creditNotUsable, .warning, "当前没有可用的学校作业成长积分建议。")
        }
        push(.roleVisibilityApplied, .info, "已按当前角色应用可见性规则。")
        if !result.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            push(.snapshotOK, .ok, "学校成长积分快照只读、脱敏且无副作用。")
        }
        return result
    }

    private func safeFallback(
        viewerRole: SchoolGrowthCreditViewerRole,
        visibility: SchoolGrowthCreditVisibility
    ) -> SchoolGrowthCreditSnapshot {
        let finding = SchoolGrowthCreditFinding(
            code: .publicSummaryLeak,
            severity: .blocker,
            message: "学校成长积分快照命中公开摘要泄露保护，已降级为安全阻断态。",
            publicRef: publicRef("find", "public-summary-leak")
        )
        return SchoolGrowthCreditSnapshot(
            generatedAt: generatedAt,
            header: SchoolGrowthCreditHeader(
                viewerRole: viewerRole,
                status: .blocked,
                generatedAt: generatedAt,
                privacyScope: "private",
                childPublicRefs: []
            ),
            assignments: [],
            creditPreviews: [],
            homeworkStatus: SchoolGrowthCreditHomeworkStatus(
                assignmentCount: 0,
                submissionCount: 0,
                verificationCount: 0,
                schoolFindingCount: 0,
                aiBoundaryBlockedCount: 0
            ),
            evidenceStatus: SchoolGrowthCreditEvidenceStatus(
                publicCaseRef: publicRef("caseview", "redacted"),
                timelineEventCount: 0,
                appealCount: 0,
                openAppealCount: 0,
                creditFrozenCount: 0,
                creditBlockedCount: 0
            ),
            offlineStatus: SchoolGrowthCreditOfflineStatus(
                cardCount: 0,
                conflictCount: 0,
                rollbackRequiredCount: 0,
                actionRequiredCount: 0
            ),
            visibility: visibility,
            nextActions: [],
            findings: [finding],
            publicSummary: SchoolGrowthCreditPublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: .blocked,
                assignmentCount: 0,
                creditPreviewCount: 0,
                usableCreditPreviewCount: 0,
                appealCount: 0,
                offlineConflictCount: 0,
                findingCodes: [.publicSummaryLeak]
            )
        )
    }

    // MARK: - Helpers

    private func verificationMode(for homework: SchoolHomework) -> String {
        switch homework.status {
        case .verified:
            return "老师验证后，等待家长确认成长积分建议"
        case .submitted:
            return "老师验证 + 家长确认"
        case .returned:
            return "退回重做后重新提交"
        case .assigned, .inProgress:
            return "孩子提交证明后进入验证"
        }
    }

    private func hasEvidenceFreeze(_ report: GrowthEvidenceTimelineReport) -> Bool {
        report.appealDecisions.contains { $0.state == .open || $0.creditState == .frozen } ||
            report.creditControls.contains { $0.state == .frozen || $0.state == .blocked }
    }

    private func hasOfflineConflict(
        offlineStatus: MobileOfflinePublicStatus,
        offlineReport: MobileOfflineReplayReport
    ) -> Bool {
        visibleOfflineConflictCount(offlineStatus, offlineReport) > 0 ||
            max(offlineStatus.rolledBackCount, offlineReport.rolledBackCount) > 0
    }

    private func visibleOfflineConflictCount(
        _ status: MobileOfflinePublicStatus,
        _ report: MobileOfflineReplayReport
    ) -> Int {
        max(status.conflictCount, report.conflictCount)
    }

    private func hasDirectAnswerRisk(_ guidance: AIHomeworkGuidance) -> Bool {
        let text = (guidance.hints + guidance.checklist + [guidance.nextStep]).joined(separator: " ")
        let riskyPhrases = ["答案是", "最终答案", "直接答案", "标准答案"]
        return riskyPhrases.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func hasUnsafeInput(
        homeworks: [SchoolHomework],
        runtimeReport: GrowthRuntimeSettlementReport,
        evidenceReport: GrowthEvidenceTimelineReport
    ) -> Bool {
        var values = homeworks.flatMap { homework in
            [homework.title, homework.instructions, homework.dueLabel, homework.subject.label]
        }
        values.append(contentsOf: runtimeReport.steps.flatMap { [$0.title, $0.reason, $0.nextStep] })
        values.append(contentsOf: evidenceReport.nodes.flatMap { [$0.title, $0.reason, $0.nextStep] })
        return hasUnsafeDisplayValues(values)
    }

    private func hasUnsafeDisplayValues(_ values: [String]) -> Bool {
        let rawPatterns = [
            "(?i)\\b(child|family|school|class|teacher|homework|submission|proof|ledger|notification|event|ref):[a-z0-9_-]+",
            "(?i)\\b(taskId|claimId|server-secret|device-token)\\b"
        ]
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        return values.contains { value in
            rawPatterns.contains { pattern in
                value.range(of: pattern, options: .regularExpression) != nil
            }
        }
    }

    private func displayValues(_ snapshot: SchoolGrowthCreditSnapshot) -> [String] {
        var values = [
            snapshot.header.privacyScope,
            snapshot.header.viewerRole.rawValue,
            snapshot.header.status.rawValue,
            snapshot.evidenceStatus.publicCaseRef
        ]
        values.append(contentsOf: snapshot.header.childPublicRefs)
        values.append(contentsOf: snapshot.assignments.flatMap {
            [
                $0.publicAssignmentRef,
                $0.childPublicRef,
                $0.title,
                $0.subject,
                $0.dueLabel,
                $0.verificationMode,
                $0.status.rawValue
            ]
        })
        values.append(contentsOf: snapshot.creditPreviews.flatMap {
            [
                $0.publicCreditPreviewRef,
                $0.sourceStatus.rawValue,
                $0.state.rawValue,
                $0.reason
            ]
        })
        values.append(contentsOf: snapshot.nextActions.flatMap {
            [
                $0.publicActionRef,
                $0.kind.rawValue,
                $0.title,
                $0.severity.rawValue
            ]
        })
        values.append(contentsOf: snapshot.findings.flatMap {
            [$0.publicRef, $0.code.rawValue, $0.message, $0.severity.rawValue]
        })
        return values
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        var hash = 5381
        for scalar in "\(redactionSalt):\(source)".unicodeScalars {
            hash = ((hash << 5) &+ hash) ^ Int(scalar.value)
        }
        return "\(prefix)-\(String(UInt(bitPattern: hash), radix: 36))"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
