import Foundation

/// iOS 端「学校老师家长联合审批台」只读快照。
///
/// 把已有的学校作业 / 成长包结算 / 家长审批 / 成长积分建议本地快照组合成一份
/// 角色感知、脱敏、无副作用的联合审批视图：展示老师验证、家长确认、退回、
/// 申诉冻结、离线回滚和成长积分建议的只读审批阶段。
///
/// 它只回答「现在卡在哪个审批阶段、谁该看什么」，绝不真正验证老师、确认家长、
/// 发成长积分、冻结成长积分、退回作业、通知任何人，也不调用 LMS / 学校系统 / 账本 / 设备。
///
/// 角色边界：
/// - 家长可见完整审批队列、内部原因、优先级与成长积分建议金额（只读）。
/// - 老师只看学校相关验证状态，看不到家长内部优先级、申诉内部原因、成长积分金额。
/// - 孩子只看安全进度文案，看不到优先级、内部原因、成长积分金额、冲突或回滚细节。

enum SchoolJointApprovalViewerRole: String, Equatable, CaseIterable {
    case guardian
    case teacher
    case child

    var label: String {
        switch self {
        case .guardian: return "家长"
        case .teacher: return "老师"
        case .child: return "孩子"
        }
    }
}

enum SchoolJointApprovalBoardStatus: String, Equatable {
    case ready
    case awaitingTeacher = "awaiting_teacher"
    case awaitingGuardian = "awaiting_guardian"
    case appealFrozen = "appeal_frozen"
    case offlineRollback = "offline_rollback"
    case blocked
    case empty

    var label: String {
        switch self {
        case .ready: return "已对齐"
        case .awaitingTeacher: return "等老师验证"
        case .awaitingGuardian: return "等家长确认"
        case .appealFrozen: return "申诉冻结"
        case .offlineRollback: return "离线回滚"
        case .blocked: return "已阻断"
        case .empty: return "暂无审批"
        }
    }
}

/// 联合审批阶段：一条作业在「老师验证 → 家长确认」联合流程中的只读位置。
enum SchoolJointApprovalStage: String, Equatable, CaseIterable {
    case awaitingSubmission = "awaiting_submission"
    case awaitingTeacher = "awaiting_teacher"
    case awaitingGuardian = "awaiting_guardian"
    case confirmed
    case returned
    case appealFrozen = "appeal_frozen"
    case offlineRollback = "offline_rollback"
    case blocked

    var label: String {
        switch self {
        case .awaitingSubmission: return "待提交"
        case .awaitingTeacher: return "等老师验证"
        case .awaitingGuardian: return "等家长确认"
        case .confirmed: return "双方已确认"
        case .returned: return "退回重做"
        case .appealFrozen: return "申诉冻结"
        case .offlineRollback: return "离线回滚"
        case .blocked: return "已阻断"
        }
    }

    /// 孩子端安全进度文案：不暴露老师/家长内部优先级、申诉原因或冲突细节。
    var childSafeCopy: String {
        switch self {
        case .awaitingSubmission: return "作业还可以继续完成。"
        case .awaitingTeacher: return "作业已提交，正在等老师看看。"
        case .awaitingGuardian: return "老师看过啦，正在等家长确认。"
        case .confirmed: return "老师和家长都确认啦，做得好！"
        case .returned: return "这次作业需要再完成一遍。"
        case .appealFrozen: return "这条作业正在复核中，请稍等。"
        case .offlineRollback: return "正在同步最新进度，请稍候。"
        case .blocked: return "这条作业暂时不能继续，等大人看看。"
        }
    }
}

enum SchoolJointApprovalPriority: String, Equatable, CaseIterable {
    case low
    case medium
    case high
    case urgent

    var label: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        case .urgent: return "紧急"
        }
    }
}

enum SchoolJointApprovalFindingCode: String, Equatable {
    case boardOK = "JOINT_APPROVAL_BOARD_OK"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case awaitingTeacherVerify = "AWAITING_TEACHER_VERIFY"
    case awaitingGuardianConfirm = "AWAITING_GUARDIAN_CONFIRM"
    case homeworkReturned = "HOMEWORK_RETURNED"
    case appealOrFreezeActive = "APPEAL_OR_FREEZE_ACTIVE"
    case offlineRollbackActive = "OFFLINE_ROLLBACK_ACTIVE"
    case creditSuggestionReview = "CREDIT_SUGGESTION_REVIEW"
    case upstreamBlocked = "UPSTREAM_BLOCKED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

enum SchoolJointApprovalSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

struct SchoolJointApprovalFinding: Identifiable, Equatable {
    var code: SchoolJointApprovalFindingCode
    var severity: SchoolJointApprovalSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct SchoolJointApprovalVisibility: Equatable {
    var viewerRole: SchoolJointApprovalViewerRole
    var canSeeQueue: Bool
    var canSeeGuardianReason: Bool
    var canSeeInternalPriority: Bool
    var canSeeCreditAmount: Bool
    var canSeeAppealReason: Bool
    var canSeeOfflineDetail: Bool
}

/// 单条联合审批项：已按当前角色裁剪过的只读阶段卡片。
struct SchoolJointApprovalItem: Identifiable, Equatable {
    var publicItemRef: String
    var stage: SchoolJointApprovalStage
    var subjectLabel: String
    var headline: String
    var childSafeCopy: String
    var guardianReason: String?
    var priority: SchoolJointApprovalPriority?
    var teacherActionNeeded: Bool
    var visibleToChild: Bool

    // 护栏：恒为 false，编译期表明这是只读阶段卡片而非落定动作。
    let verifiesTeacher = false
    let confirmsGuardian = false
    let returnsHomework = false
    let freezesCredit = false
    let writesLedger = false
    let sendsNotification = false
    let callsSchoolSystem = false

    var id: String { publicItemRef }
}

/// 成长积分建议只读条目：仅家长可见金额与原因，老师/孩子看不到金额。
struct SchoolJointApprovalCreditNote: Identifiable, Equatable {
    var publicNoteRef: String
    var stateLabel: String
    var amount: Int?
    var reason: String?
    var actionRequired: Bool

    let writesLedger = false
    let issuesCredit = false
    let unlocksDevice = false

    var id: String { publicNoteRef }
}

struct SchoolJointApprovalStageSummary: Equatable {
    var totalCount: Int
    var awaitingTeacherCount: Int
    var awaitingGuardianCount: Int
    var confirmedCount: Int
    var returnedCount: Int
    var appealFrozenCount: Int
    var offlineRollbackCount: Int
    var blockedCount: Int

    let readOnly = true
    let verifiesTeacher = false
    let confirmsGuardian = false
    let writesLedger = false
}

struct SchoolJointApprovalPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: SchoolJointApprovalViewerRole
    var status: SchoolJointApprovalBoardStatus
    var visibleItemCount: Int
    var awaitingTeacherCount: Int
    var awaitingGuardianCount: Int
    var returnedCount: Int
    var appealFrozenCount: Int
    var offlineRollbackCount: Int
    var creditNoteCount: Int
    var findingCodes: [SchoolJointApprovalFindingCode]

    let verifiesTeacher = false
    let confirmsGuardian = false
    let returnsHomework = false
    let freezesCredit = false
    let writesLedger = false
    let writesSchoolHomework = false
    let sendsNotification = false
    let unlocksDevice = false
    let callsSchoolSystem = false
    let callsLms = false
    let usesAiToAnswer = false
}

struct SchoolJointApprovalHeader: Equatable {
    var viewerRole: SchoolJointApprovalViewerRole
    var status: SchoolJointApprovalBoardStatus
    var generatedAt: String
    var privacyScope: String
}

struct SchoolJointApprovalSnapshot: Equatable {
    var generatedAt: String
    var header: SchoolJointApprovalHeader
    var visibility: SchoolJointApprovalVisibility
    var items: [SchoolJointApprovalItem]
    var creditNotes: [SchoolJointApprovalCreditNote]
    var stageSummary: SchoolJointApprovalStageSummary
    var findings: [SchoolJointApprovalFinding]
    var publicSummary: SchoolJointApprovalPublicSummary
}

struct SchoolJointApprovalSnapshotBuilder {
    private let generatedAt: String
    private let redactionSalt: String

    init(
        generatedAt: String = "2026-06-24T10:00:00Z",
        redactionSalt: String = "school-joint-approval-ios-v1"
    ) {
        self.generatedAt = generatedAt
        self.redactionSalt = redactionSalt
    }

    func build(
        viewerRole: SchoolJointApprovalViewerRole,
        homeworks: [SchoolHomework] = [],
        schoolCredit: SchoolGrowthCreditSnapshot,
        creditSettlement: MobileCreditSettlementReport = .empty,
        offlineStatus: MobileOfflinePublicStatus = .clean,
        offlineReport: MobileOfflineReplayReport = .empty
    ) -> SchoolJointApprovalSnapshot {
        let visibility = visibility(for: viewerRole)
        if hasUnsafeInput(homeworks: homeworks, schoolCredit: schoolCredit, creditSettlement: creditSettlement) {
            return safeFallback(viewerRole: viewerRole, visibility: visibility)
        }

        let offlineRollback = visibility.canSeeOfflineDetail
            && hasOfflineRollback(offlineStatus: offlineStatus, offlineReport: offlineReport)
        let items = collectItems(
            viewerRole: viewerRole,
            visibility: visibility,
            homeworks: homeworks,
            schoolCredit: schoolCredit,
            offlineRollback: offlineRollback
        )
        let creditNotes = creditNotes(
            visibility: visibility,
            schoolCredit: schoolCredit,
            creditSettlement: creditSettlement
        )
        let boardFindings = findings(
            viewerRole: viewerRole,
            visibility: visibility,
            items: items,
            creditNotes: creditNotes,
            schoolCredit: schoolCredit,
            offlineRollback: offlineRollback
        )
        let status = boardStatus(
            viewerRole: viewerRole,
            items: items,
            schoolCredit: schoolCredit,
            offlineRollback: offlineRollback
        )
        let summary = stageSummary(items)
        let body = SchoolJointApprovalSnapshot(
            generatedAt: generatedAt,
            header: SchoolJointApprovalHeader(
                viewerRole: viewerRole,
                status: status,
                generatedAt: generatedAt,
                privacyScope: viewerRole == .child ? "private" : "care_team"
            ),
            visibility: visibility,
            items: items,
            creditNotes: creditNotes,
            stageSummary: summary,
            findings: boardFindings,
            publicSummary: publicSummary(
                viewerRole: viewerRole,
                status: status,
                items: items,
                creditNotes: creditNotes,
                findings: boardFindings
            )
        )
        return redacts(body) ? body : safeFallback(viewerRole: viewerRole, visibility: visibility)
    }

    func redacts(_ snapshot: SchoolJointApprovalSnapshot) -> Bool {
        !hasUnsafeDisplayValues(displayValues(snapshot))
    }

    // MARK: - Visibility

    private func visibility(for role: SchoolJointApprovalViewerRole) -> SchoolJointApprovalVisibility {
        switch role {
        case .guardian:
            return SchoolJointApprovalVisibility(
                viewerRole: role,
                canSeeQueue: true,
                canSeeGuardianReason: true,
                canSeeInternalPriority: true,
                canSeeCreditAmount: true,
                canSeeAppealReason: true,
                canSeeOfflineDetail: true
            )
        case .teacher:
            return SchoolJointApprovalVisibility(
                viewerRole: role,
                canSeeQueue: true,
                canSeeGuardianReason: false,
                canSeeInternalPriority: false,
                canSeeCreditAmount: false,
                canSeeAppealReason: false,
                canSeeOfflineDetail: false
            )
        case .child:
            return SchoolJointApprovalVisibility(
                viewerRole: role,
                canSeeQueue: false,
                canSeeGuardianReason: false,
                canSeeInternalPriority: false,
                canSeeCreditAmount: false,
                canSeeAppealReason: false,
                canSeeOfflineDetail: false
            )
        }
    }

    // MARK: - Items

    private func collectItems(
        viewerRole: SchoolJointApprovalViewerRole,
        visibility: SchoolJointApprovalVisibility,
        homeworks: [SchoolHomework],
        schoolCredit: SchoolGrowthCreditSnapshot,
        offlineRollback: Bool
    ) -> [SchoolJointApprovalItem] {
        schoolCredit.assignments.enumerated().compactMap { index, assignment in
            let stage = stage(
                for: assignment,
                homeworkStatus: homeworks[safe: index]?.status,
                offlineRollback: offlineRollback
            )
            guard isVisible(stage: stage, to: viewerRole) else { return nil }
            return item(
                viewerRole: viewerRole,
                visibility: visibility,
                assignment: assignment,
                stage: stage,
                order: index
            )
        }
    }

    /// 老师只看学校相关验证阶段；申诉冻结、离线回滚属于家长内部流程，对老师隐藏。
    private func isVisible(stage: SchoolJointApprovalStage, to role: SchoolJointApprovalViewerRole) -> Bool {
        switch role {
        case .guardian:
            return true
        case .teacher:
            switch stage {
            case .appealFrozen, .offlineRollback:
                return false
            default:
                return true
            }
        case .child:
            return true
        }
    }

    /// 学校快照把退回作业折叠为 `.blocked`，这里借 homework 原始状态把「退回重做」
    /// 单独还原成一个只读阶段，其余阶段沿用学校快照已裁剪过的角色感知状态。
    private func stage(
        for assignment: SchoolGrowthCreditAssignmentSnapshot,
        homeworkStatus: HomeworkStatus?,
        offlineRollback: Bool
    ) -> SchoolJointApprovalStage {
        switch assignment.status {
        case .blocked:
            return homeworkStatus == .returned ? .returned : .blocked
        case .appealed:
            return .appealFrozen
        case .offlineConflict:
            return .offlineRollback
        case .assigned:
            return .awaitingSubmission
        case .submitted, .reviewRequired:
            return offlineRollback ? .offlineRollback : .awaitingTeacher
        case .teacherVerified:
            return .awaitingGuardian
        case .guardianConfirmed:
            return .confirmed
        }
    }

    private func item(
        viewerRole: SchoolJointApprovalViewerRole,
        visibility: SchoolJointApprovalVisibility,
        assignment: SchoolGrowthCreditAssignmentSnapshot,
        stage: SchoolJointApprovalStage,
        order: Int
    ) -> SchoolJointApprovalItem {
        let priority = priority(for: stage)
        return SchoolJointApprovalItem(
            publicItemRef: publicRef("joint-item", "\(stage.rawValue)-\(order)"),
            stage: stage,
            subjectLabel: assignment.subject,
            headline: headline(viewerRole: viewerRole, subject: assignment.subject, stage: stage),
            childSafeCopy: stage.childSafeCopy,
            guardianReason: visibility.canSeeGuardianReason ? guardianReason(stage: stage, assignment: assignment) : nil,
            priority: visibility.canSeeInternalPriority ? priority : nil,
            teacherActionNeeded: stage == .awaitingTeacher,
            visibleToChild: true
        )
    }

    private func headline(
        viewerRole: SchoolJointApprovalViewerRole,
        subject: String,
        stage: SchoolJointApprovalStage
    ) -> String {
        switch viewerRole {
        case .child:
            return "\(subject)作业"
        case .teacher:
            return "\(subject) · \(stage == .awaitingTeacher ? "等老师验证" : stage.label)"
        case .guardian:
            return "\(subject) · \(stage.label)"
        }
    }

    private func guardianReason(
        stage: SchoolJointApprovalStage,
        assignment: SchoolGrowthCreditAssignmentSnapshot
    ) -> String {
        switch stage {
        case .awaitingSubmission:
            return "作业还在进行中，等待孩子提交脱敏证明。"
        case .awaitingTeacher:
            return "孩子已提交，等待老师在学校侧验证后再进入家长确认。"
        case .awaitingGuardian:
            return "老师已验证，等待家长确认后才会进入成长积分建议。"
        case .confirmed:
            return "老师验证与家长确认均已完成，可只读查看成长积分建议。"
        case .returned:
            return "作业被退回，需要孩子重新完成后再提交，期间不进入成长积分建议。"
        case .appealFrozen:
            return "证据链存在申诉或成长积分冻结，联合审批暂停直到复核完成。"
        case .offlineRollback:
            return "存在离线冲突或回滚，需要家长复核后离线更改才会应用。"
        case .blocked:
            return "安全边界阻断了这条作业的联合审批。"
        }
    }

    private func priority(for stage: SchoolJointApprovalStage) -> SchoolJointApprovalPriority {
        switch stage {
        case .blocked, .appealFrozen, .offlineRollback:
            return .urgent
        case .returned:
            return .high
        case .awaitingTeacher:
            return .high
        case .awaitingGuardian:
            return .medium
        case .awaitingSubmission:
            return .low
        case .confirmed:
            return .low
        }
    }

    // MARK: - Credit notes

    private func creditNotes(
        visibility: SchoolJointApprovalVisibility,
        schoolCredit: SchoolGrowthCreditSnapshot,
        creditSettlement: MobileCreditSettlementReport
    ) -> [SchoolJointApprovalCreditNote] {
        guard visibility.canSeeCreditAmount else { return [] }
        let fromPreviews = schoolCredit.creditPreviews.enumerated().map { index, preview in
            SchoolJointApprovalCreditNote(
                publicNoteRef: publicRef("joint-credit", "preview-\(index)"),
                stateLabel: preview.state.label,
                amount: preview.state == .availablePreview ? preview.amount : nil,
                reason: preview.reason,
                actionRequired: preview.state == .reviewRequired || preview.state == .frozen
            )
        }
        let settlementSchool = creditSettlement.proposals.filter { $0.source == .schoolHomeworkMobileFlow }
        let fromSettlement = settlementSchool.enumerated().map { index, proposal in
            SchoolJointApprovalCreditNote(
                publicNoteRef: publicRef("joint-credit", "settle-\(index)"),
                stateLabel: proposal.statusLabel,
                amount: proposal.status == .proposed ? proposal.amount : nil,
                reason: proposal.reason,
                actionRequired: proposal.actionRequired
            )
        }
        return fromPreviews + fromSettlement
    }

    // MARK: - Status, findings

    private func boardStatus(
        viewerRole: SchoolJointApprovalViewerRole,
        items: [SchoolJointApprovalItem],
        schoolCredit: SchoolGrowthCreditSnapshot,
        offlineRollback: Bool
    ) -> SchoolJointApprovalBoardStatus {
        if viewerRole != .child && schoolCredit.header.status == .blocked { return .blocked }
        if items.contains(where: { $0.stage == .blocked }) { return .blocked }
        // Offline rollback means the local approval picture may be stale, so it outranks appeal freeze.
        if offlineRollback || items.contains(where: { $0.stage == .offlineRollback }) { return .offlineRollback }
        if items.contains(where: { $0.stage == .appealFrozen }) { return .appealFrozen }
        if items.contains(where: { $0.stage == .awaitingTeacher || $0.stage == .returned }) { return .awaitingTeacher }
        if items.contains(where: { $0.stage == .awaitingGuardian }) { return .awaitingGuardian }
        if items.isEmpty { return .empty }
        return .ready
    }

    private func findings(
        viewerRole: SchoolJointApprovalViewerRole,
        visibility: SchoolJointApprovalVisibility,
        items: [SchoolJointApprovalItem],
        creditNotes: [SchoolJointApprovalCreditNote],
        schoolCredit: SchoolGrowthCreditSnapshot,
        offlineRollback: Bool
    ) -> [SchoolJointApprovalFinding] {
        var result: [SchoolJointApprovalFinding] = []
        func push(_ code: SchoolJointApprovalFindingCode, _ severity: SchoolJointApprovalSeverity, _ message: String) {
            result.append(SchoolJointApprovalFinding(
                code: code,
                severity: severity,
                message: message,
                publicRef: publicRef("joint-find", "\(viewerRole.rawValue):\(code.rawValue):\(result.count)")
            ))
        }

        if viewerRole != .child && schoolCredit.header.status == .blocked {
            push(.upstreamBlocked, .blocker, "上游学校成长积分快照处于阻断态，联合审批暂停。")
        }
        if items.contains(where: { $0.stage == .returned }) {
            push(.homeworkReturned, .warning, "存在被退回的作业，相关作业暂不进入成长积分建议。")
        }
        if items.contains(where: { $0.stage == .awaitingTeacher }) {
            push(.awaitingTeacherVerify, .info, "有作业已提交，正在等待老师在学校侧验证。")
        }
        if items.contains(where: { $0.stage == .awaitingGuardian }) {
            push(.awaitingGuardianConfirm, .info, "有作业老师已验证，正在等待家长确认。")
        }
        if visibility.canSeeAppealReason && items.contains(where: { $0.stage == .appealFrozen }) {
            push(.appealOrFreezeActive, .warning, "申诉或成长积分冻结期间联合审批暂停。")
        }
        if visibility.canSeeOfflineDetail && (offlineRollback || items.contains(where: { $0.stage == .offlineRollback })) {
            push(.offlineRollbackActive, .warning, "离线冲突或回滚需要家长复核后才会应用。")
        }
        if visibility.canSeeCreditAmount && creditNotes.contains(where: { $0.actionRequired }) {
            push(.creditSuggestionReview, .info, "存在需要家长复核的成长积分建议，仅只读展示。")
        }
        push(.roleVisibilityApplied, .info, "已按 \(viewerRole.label) 视角裁剪联合审批台。")
        if !result.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            push(.boardOK, .ok, "学校老师家长联合审批台只读、脱敏且无副作用。")
        }
        return result
    }

    private func stageSummary(_ items: [SchoolJointApprovalItem]) -> SchoolJointApprovalStageSummary {
        SchoolJointApprovalStageSummary(
            totalCount: items.count,
            awaitingTeacherCount: items.filter { $0.stage == .awaitingTeacher }.count,
            awaitingGuardianCount: items.filter { $0.stage == .awaitingGuardian }.count,
            confirmedCount: items.filter { $0.stage == .confirmed }.count,
            returnedCount: items.filter { $0.stage == .returned }.count,
            appealFrozenCount: items.filter { $0.stage == .appealFrozen }.count,
            offlineRollbackCount: items.filter { $0.stage == .offlineRollback }.count,
            blockedCount: items.filter { $0.stage == .blocked }.count
        )
    }

    private func publicSummary(
        viewerRole: SchoolJointApprovalViewerRole,
        status: SchoolJointApprovalBoardStatus,
        items: [SchoolJointApprovalItem],
        creditNotes: [SchoolJointApprovalCreditNote],
        findings: [SchoolJointApprovalFinding]
    ) -> SchoolJointApprovalPublicSummary {
        SchoolJointApprovalPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            visibleItemCount: items.count,
            awaitingTeacherCount: items.filter { $0.stage == .awaitingTeacher }.count,
            awaitingGuardianCount: items.filter { $0.stage == .awaitingGuardian }.count,
            returnedCount: items.filter { $0.stage == .returned }.count,
            appealFrozenCount: items.filter { $0.stage == .appealFrozen }.count,
            offlineRollbackCount: items.filter { $0.stage == .offlineRollback }.count,
            creditNoteCount: creditNotes.count,
            findingCodes: findings.map(\.code)
        )
    }

    // MARK: - Safety

    private func safeFallback(
        viewerRole: SchoolJointApprovalViewerRole,
        visibility: SchoolJointApprovalVisibility
    ) -> SchoolJointApprovalSnapshot {
        let finding = SchoolJointApprovalFinding(
            code: .publicSummaryLeak,
            severity: .blocker,
            message: "学校老师家长联合审批台未通过公开脱敏检查，已进入安全降级模式。",
            publicRef: publicRef("joint-find", "public-summary-leak")
        )
        let emptyItems: [SchoolJointApprovalItem] = []
        return SchoolJointApprovalSnapshot(
            generatedAt: generatedAt,
            header: SchoolJointApprovalHeader(
                viewerRole: viewerRole,
                status: .blocked,
                generatedAt: generatedAt,
                privacyScope: "private"
            ),
            visibility: visibility,
            items: emptyItems,
            creditNotes: [],
            stageSummary: stageSummary(emptyItems),
            findings: [finding],
            publicSummary: publicSummary(
                viewerRole: viewerRole,
                status: .blocked,
                items: emptyItems,
                creditNotes: [],
                findings: [finding]
            )
        )
    }

    private func hasOfflineRollback(
        offlineStatus: MobileOfflinePublicStatus,
        offlineReport: MobileOfflineReplayReport
    ) -> Bool {
        max(offlineStatus.conflictCount, offlineReport.conflictCount) > 0
            || max(offlineStatus.rolledBackCount, offlineReport.rolledBackCount) > 0
    }

    private func hasUnsafeInput(
        homeworks: [SchoolHomework],
        schoolCredit: SchoolGrowthCreditSnapshot,
        creditSettlement: MobileCreditSettlementReport
    ) -> Bool {
        var values = schoolCredit.assignments.flatMap { [$0.title, $0.subject, $0.dueLabel, $0.verificationMode] }
        values.append(contentsOf: schoolCredit.creditPreviews.map(\.reason))
        values.append(contentsOf: homeworks.flatMap { [$0.title, $0.instructions, $0.dueLabel, $0.subject.label] })
        values.append(contentsOf: creditSettlement.proposals.flatMap { [$0.reason, $0.scopeLabel] })
        return hasUnsafeDisplayValues(values)
    }

    private func hasUnsafeDisplayValues(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let rawPatterns = [
            "(?i)\\b(child|family|school|class|teacher|guardian|homework|submission|proof|ledger|credit|event|ref):[a-z0-9_-]+",
            "(?i)\\b(taskId|claimId|server-secret|device-token)\\b"
        ]
        return values.contains { value in
            rawPatterns.contains { pattern in
                value.range(of: pattern, options: .regularExpression) != nil
            }
        }
    }

    private func displayValues(_ snapshot: SchoolJointApprovalSnapshot) -> [String] {
        var values = [
            snapshot.generatedAt,
            snapshot.header.privacyScope,
            snapshot.header.viewerRole.rawValue,
            snapshot.header.status.rawValue
        ]
        values.append(contentsOf: snapshot.items.flatMap { item in
            [
                item.publicItemRef,
                item.subjectLabel,
                item.headline,
                item.childSafeCopy,
                item.guardianReason ?? "",
                item.stage.rawValue
            ]
        })
        values.append(contentsOf: snapshot.creditNotes.flatMap { note in
            [note.publicNoteRef, note.stateLabel, note.reason ?? ""]
        })
        values.append(contentsOf: snapshot.findings.flatMap { [$0.publicRef, $0.message] })
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
