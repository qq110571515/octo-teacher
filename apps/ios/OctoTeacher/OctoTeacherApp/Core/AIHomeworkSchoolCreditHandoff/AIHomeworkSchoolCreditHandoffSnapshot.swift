import Foundation

/// iOS 端「AI 作业学校成长积分交接复核入口」只读快照。
///
/// 把 A39 的本地 `AIHomeworkGuidanceSessionSnapshot`（AI 作业引导会话）和 B46 的
/// 「AI 作业引导 → 学校 / 成长积分交接」语义，组合成一份角色感知、脱敏、无副作用的本地复核入口：
/// 展示作业接入状态、引导是否不直给答案、引用 / 自检数量、老师 / 家长确认、成长积分建议是否
/// 冻结 / 阻断、孩子下一步，以及家长 / 老师脱敏摘要。
///
/// 它只回答「这条作业能不能从引导交接到学校 / 成长积分复核、现在卡在哪个环节、谁该看什么」，
/// 绝不真正调用 AI / 网络 / 数据库 / 队列 / 登录 / 支付 / AI provider / 本地 QWEN / LMS /
/// 学校系统 / 通知 / 账本 / HealthKit / FamilyControls / ManagedSettings 或设备，也绝不给作业
/// 答案、展示 answer key、生成真实评分、自动发成长积分、写 ledger、通知学校 / 老师 / 家长、改变
/// 作业终态、上传附件或解锁设备。所有内容都是本地确定性派生的只读投影。
///
/// 角色边界：
/// - 孩子可见作业接入状态、引导不直给答案的安抚、引用 / 自检数量、成长积分 / 审批的安全状态文案与下一步；
///   看不到成长积分建议金额、老师答案键、成人风险细节、成人审批优先级、原始 transcript、provider / model、
///   跨孩子内容、离线冲突详情或退款 / 回滚原因。
/// - 家长 / 老师可见审批确认状态、成长积分建议是否冻结 / 阻断的脱敏计数与脱敏摘要、下一步；
///   看不到孩子原始输入 transcript，只看脱敏意图、风险标签、摘要和下一步。

// MARK: - 查看角色

enum AIHomeworkSchoolCreditHandoffViewerRole: String, Equatable, CaseIterable {
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

    /// 是否属于照护团队（家长 / 老师）视角。
    var isCareTeam: Bool { self != .child }
}

// MARK: - 交接状态

/// 交接复核入口整体状态。与 B46 契约的 ready / review_required / frozen / blocked 对齐，
/// 额外保留 `empty`（暂无可交接作业）。
enum AIHomeworkSchoolCreditHandoffState: String, Equatable {
    case ready
    case reviewRequired = "review_required"
    case frozen
    case blocked
    case empty

    var label: String {
        switch self {
        case .ready: return "可交接复核"
        case .reviewRequired: return "需复核"
        case .frozen: return "成长积分冻结"
        case .blocked: return "已阻断"
        case .empty: return "暂无作业"
        }
    }

    /// 孩子端安全状态文案：不暴露成长积分金额、风险细节、冲突或回滚原因。
    var childSafeCopy: String {
        switch self {
        case .ready: return "作业引导和学校确认都对齐啦，可以继续。"
        case .reviewRequired: return "作业正在等老师或家长再确认一下。"
        case .frozen: return "成长积分正在等大人复核，先把作业完成好。"
        case .blocked: return "这条作业暂时不能继续，等大人看看。"
        case .empty: return "现在还没有需要交接的作业。"
        }
    }
}

// MARK: - 成长积分交接子状态

enum AIHomeworkSchoolCreditCreditState: String, Equatable {
    case reviewable
    case frozen
    case blocked

    var label: String {
        switch self {
        case .reviewable: return "可复核"
        case .frozen: return "已冻结"
        case .blocked: return "已阻断"
        }
    }
}

// MARK: - 孩子下一步

enum AIHomeworkSchoolCreditChildNextStepKind: String, Equatable {
    case continueGuidance = "continue_guidance"
    case waitForAssignmentReview = "wait_for_assignment_review"
    case waitForAdultReview = "wait_for_adult_review"
    case waitForCreditReview = "wait_for_credit_review"
    case removeAnswerMaterial = "remove_answer_material"
    case readOnly = "read_only"

    var title: String {
        switch self {
        case .continueGuidance: return "继续按引导一步步完成作业。"
        case .waitForAssignmentReview: return "先等学校把这条作业接入复核。"
        case .waitForAdultReview: return "等老师和家长确认一下。"
        case .waitForCreditReview: return "等大人复核成长积分，先把作业做好。"
        case .removeAnswerMaterial: return "只用提示和自检，不要直接看答案。"
        case .readOnly: return "这条作业先保持只读，等会儿再继续。"
        }
    }

    /// 是否需要孩子主动等待 / 调整（用于入口高亮）。
    var actionRequired: Bool {
        switch self {
        case .continueGuidance, .readOnly:
            return false
        default:
            return true
        }
    }
}

// MARK: - 发现项

enum AIHomeworkSchoolCreditHandoffSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

enum AIHomeworkSchoolCreditHandoffFindingCode: String, Equatable {
    case handoffReady = "HANDOFF_READY"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case childVisibilityRedacted = "CHILD_VISIBILITY_REDACTED"
    case awaitingChildInput = "AWAITING_CHILD_INPUT"
    case schoolAssignmentReturned = "SCHOOL_ASSIGNMENT_RETURNED"
    case schoolAssignmentBlocked = "SCHOOL_ASSIGNMENT_BLOCKED"
    case guidanceNotAccepted = "GUIDANCE_NOT_ACCEPTED"
    case guidanceDirectAnswerBlocked = "GUIDANCE_DIRECT_ANSWER_BLOCKED"
    case teacherReviewRequired = "TEACHER_REVIEW_REQUIRED"
    case guardianConfirmationRequired = "GUARDIAN_CONFIRMATION_REQUIRED"
    case adultReviewBlocked = "ADULT_REVIEW_BLOCKED"
    case creditReviewFrozen = "CREDIT_REVIEW_FROZEN"
    case creditConflictBlocked = "CREDIT_CONFLICT_BLOCKED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

struct AIHomeworkSchoolCreditHandoffFinding: Identifiable, Equatable {
    var code: AIHomeworkSchoolCreditHandoffFindingCode
    var severity: AIHomeworkSchoolCreditHandoffSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

// MARK: - 可见性

struct AIHomeworkSchoolCreditHandoffVisibility: Equatable {
    var viewerRole: AIHomeworkSchoolCreditHandoffViewerRole
    /// 引用 / 自检 / 不直给答案等引导计数（孩子与照护团队均可见的安全事实）。
    var canSeeGuidanceFacts: Bool
    /// 成人审批确认明细（待老师 / 待家长 / 已确认计数）。
    var canSeeAdultReviewDetail: Bool
    /// 成长积分建议冻结 / 阻断的脱敏计数与状态。
    var canSeeCreditDetail: Bool
    /// 家长 / 老师脱敏摘要与风险标签。
    var canSeeCareSummary: Bool
    /// 孩子下一步引导（任何角色都能看到这条安全文案）。
    var canSeeChildNextStep: Bool
}

// MARK: - 作业接入投影

/// 作业接入状态：只展示脱敏科目与状态标签，绝不写学校系统或 LMS。
struct AIHomeworkSchoolCreditAssignmentView: Equatable {
    var subjectLabel: String
    var statusLabel: String
    /// 是否已接入（存在可交接的作业且未被退回 / 阻断）。
    var accepted: Bool
    /// 是否被退回需重做（进入复核前不交接成长积分）。
    var needsRedo: Bool

    let writesSchoolSystem = false
    let callsLms = false
    let uploadsAttachment = false
}

// MARK: - 引导投影

/// 引导投影：只读地反映 A39 引导会话「不直给答案 + 引用 / 自检数量」的事实，
/// 绝不含答案、answer key、原始 transcript 或 provider / model。
struct AIHomeworkSchoolCreditGuidanceView: Equatable {
    /// 引导是否被接受（会话未进入安全阻断态）。
    var guidanceAccepted: Bool
    /// 是否不直接给答案（恒应为 true；为 false 即触发阻断）。
    var noDirectAnswer: Bool
    /// 引用 / 提示数量（A39 思路提示步骤数）。
    var referenceHintCount: Int
    /// 自检数量（A39 自检清单项数）。
    var selfCheckCount: Int
    /// 引导步骤总数。
    var guidanceStepCount: Int

    let showsFinalAnswer = false
    let showsAnswerKey = false
    let showsProviderDetails = false
    let storesRawTranscript = false
    let createsScore = false
}

// MARK: - 成人审批投影

/// 成人审批投影：老师验证 / 家长确认的脱敏状态。绝不真正验证、确认或通知。
struct AIHomeworkSchoolCreditAdultReviewView: Equatable {
    var boardStatusLabel: String
    var teacherReviewRequired: Bool
    var guardianConfirmationRequired: Bool
    var confirmedCount: Int
    var blocked: Bool
    /// 孩子端安全文案（不含优先级、内部原因、风险评分）。
    var childVisibleMessage: String

    let verifiesTeacher = false
    let confirmsGuardian = false
    let notifiesSchool = false
    let sendsNotification = false
}

// MARK: - 成长积分交接投影

/// 成长积分交接投影：只读地反映成长积分建议是否可复核 / 冻结 / 阻断的脱敏计数。
/// **绝不暴露金额给任何角色**，也绝不写账本、发成长积分或冻结成长积分。
struct AIHomeworkSchoolCreditCreditView: Equatable {
    var state: AIHomeworkSchoolCreditCreditState
    var settleableCount: Int
    var frozenCount: Int
    var conflictCount: Int
    var reviewRequiredCount: Int
    var blockedCount: Int
    /// 孩子端安全文案（不含金额、原因、退款 / 回滚原因）。
    var childVisibleCopy: String

    let showsAmountToChild = false
    let showsAmountToCareTeam = false
    let writesLedger = false
    let issuesCredit = false
    let freezesCredit = false
    let refundsCredit = false
    let unlocksDevice = false
}

// MARK: - 孩子下一步

struct AIHomeworkSchoolCreditChildNextStep: Equatable {
    var publicActionRef: String
    var kind: AIHomeworkSchoolCreditChildNextStepKind
    var title: String
    var actionRequired: Bool

    let showsCreditAmount = false
    let showsAnswerKey = false
    let sendsNotification = false
}

// MARK: - 脱敏摘要（仅照护团队）

/// 家长 / 老师脱敏摘要：只给脱敏意图、风险标签、整体摘要与下一步，
/// 绝不含孩子原始输入 transcript、答案、成长积分金额、内部风险评分或 provider / model。
struct AIHomeworkSchoolCreditCareSummary: Equatable {
    var subjectLabel: String
    var stateLabel: String
    var intentLabels: [String]
    var riskLabels: [String]
    var headline: String
    var recommendedAction: String

    let exposesRawTranscript = false
    let exposesChildAnswer = false
    let exposesCreditAmount = false
    let exposesInternalRiskScore = false
    let exposesModelOrProvider = false
}

// MARK: - 头部与公开摘要

struct AIHomeworkSchoolCreditHandoffHeader: Equatable {
    var viewerRole: AIHomeworkSchoolCreditHandoffViewerRole
    var state: AIHomeworkSchoolCreditHandoffState
    var generatedAt: String
    var privacyScope: String
}

struct AIHomeworkSchoolCreditHandoffPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: AIHomeworkSchoolCreditHandoffViewerRole
    var state: AIHomeworkSchoolCreditHandoffState
    var subjectLabel: String
    var accepted: Bool
    var noDirectAnswer: Bool
    var referenceHintCount: Int
    var selfCheckCount: Int
    var teacherReviewRequired: Bool
    var guardianConfirmationRequired: Bool
    var creditState: AIHomeworkSchoolCreditCreditState
    var childNextStepKind: AIHomeworkSchoolCreditChildNextStepKind
    var findingCodes: [AIHomeworkSchoolCreditHandoffFindingCode]

    // 护栏：复核入口只读、脱敏、无副作用。
    let callsAiProvider = false
    let callsNetwork = false
    let writesDatabase = false
    let writesSchoolSystem = false
    let callsLms = false
    let sendsNotification = false
    let writesLedger = false
    let issuesCredit = false
    let freezesCredit = false
    let createsScore = false
    let storesRawTranscript = false
    let revealsModelOrProvider = false
    let showsCreditAmount = false
    let unlocksDevice = false
}

// MARK: - 快照

struct AIHomeworkSchoolCreditHandoffSnapshot: Equatable {
    var generatedAt: String
    var header: AIHomeworkSchoolCreditHandoffHeader
    var visibility: AIHomeworkSchoolCreditHandoffVisibility
    var state: AIHomeworkSchoolCreditHandoffState
    var assignment: AIHomeworkSchoolCreditAssignmentView
    var guidance: AIHomeworkSchoolCreditGuidanceView
    var adultReview: AIHomeworkSchoolCreditAdultReviewView
    var credit: AIHomeworkSchoolCreditCreditView
    var childNextStep: AIHomeworkSchoolCreditChildNextStep
    /// 脱敏摘要仅照护团队可见；孩子为 nil。
    var careSummary: AIHomeworkSchoolCreditCareSummary?
    var findings: [AIHomeworkSchoolCreditHandoffFinding]
    var publicSummary: AIHomeworkSchoolCreditHandoffPublicSummary

    /// 一句话总览（脱敏，按角色裁剪）。
    var headline: String {
        if state == .empty { return "暂无需要交接复核的作业" }
        if !visibility.viewerRole.isCareTeam { return childNextStep.title }
        var parts: [String] = ["\(assignment.subjectLabel) · \(state.label)"]
        if adultReview.teacherReviewRequired { parts.append("等老师验证") }
        if adultReview.guardianConfirmationRequired { parts.append("等家长确认") }
        if credit.state != .reviewable { parts.append("成长积分\(credit.state.label)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Builder

/// AI 作业学校成长积分交接复核入口构建器（纯逻辑、无副作用、无网络、无随机、无时钟）。
///
/// 输入一条本地学校作业、A39 引导会话消息，以及可选的联合审批 / 成长积分复核快照；
/// 输出按孩子、家长、老师三种角色裁剪后的只读交接复核快照。给定相同输入恒定输出。
struct AIHomeworkSchoolCreditHandoffBuilder {
    private let generatedAt: String
    private let redactionSalt: String
    private let guidanceBuilder: AIHomeworkGuidanceSessionBuilder

    init(
        generatedAt: String = "2026-06-24T10:00:00Z",
        redactionSalt: String = "ai-homework-school-credit-handoff-ios-v1"
    ) {
        self.generatedAt = generatedAt
        self.redactionSalt = redactionSalt
        self.guidanceBuilder = AIHomeworkGuidanceSessionBuilder(
            generatedAt: generatedAt,
            redactionSalt: "\(redactionSalt):guidance"
        )
    }

    func build(
        viewerRole: AIHomeworkSchoolCreditHandoffViewerRole,
        homework: SchoolHomework?,
        messages: [AIHomeworkSessionMessage] = [],
        jointApproval: SchoolJointApprovalSnapshot? = nil,
        creditReview: CreditLedgerReviewConsole? = nil
    ) -> AIHomeworkSchoolCreditHandoffSnapshot {
        let visibility = visibility(for: viewerRole)
        if hasUnsafeInput(homework: homework, messages: messages, jointApproval: jointApproval, creditReview: creditReview) {
            return safeFallback(viewerRole: viewerRole, visibility: visibility, code: .publicSummaryLeak)
        }

        guard let homework else {
            return emptySnapshot(viewerRole: viewerRole, visibility: visibility)
        }

        let guidance = guidanceBuilder.build(
            viewerRole: guidanceRole(viewerRole),
            homework: homework,
            messages: messages
        )
        let guidanceFacts = viewerRole == .child
            ? guidance
            : guidanceBuilder.build(viewerRole: .child, homework: homework, messages: messages)
        let assignment = assignmentView(homework)
        let adult = adultReviewView(homework: homework, jointApproval: jointApproval)
        let directAnswerBlocked = messages.contains { $0.intent == .wantsDirectAnswer || $0.containsUnsafeInput }
            || guidance.header.status == .blocked
            || guidanceFacts.header.status == .blocked
            || guidanceFacts.publicSummary.givesAnswer
        let credit = creditView(
            homework: homework,
            directAnswerBlocked: directAnswerBlocked,
            adultReview: adult,
            creditReview: creditReview
        )
        let state = handoffState(
            assignment: assignment,
            guidance: guidanceFacts,
            directAnswerBlocked: directAnswerBlocked,
            adultReview: adult,
            credit: credit
        )
        let nextStep = childNextStep(
            state: state,
            homework: homework,
            directAnswerBlocked: directAnswerBlocked,
            adultReview: adult,
            credit: credit
        )
        let findings = findings(
            viewerRole: viewerRole,
            visibility: visibility,
            homework: homework,
            messages: messages,
            guidance: guidanceFacts,
            assignment: assignment,
            adultReview: adult,
            credit: credit,
            state: state,
            directAnswerBlocked: directAnswerBlocked
        )
        let care = visibility.canSeeCareSummary
            ? careSummary(
                viewerRole: viewerRole,
                homework: homework,
                guidance: guidance,
                state: state,
                directAnswerBlocked: directAnswerBlocked,
                adultReview: adult,
                credit: credit
            )
            : nil
        let visibleAdult = visibleAdultReview(adult, visibility: visibility)
        let visibleCredit = visibleCredit(credit, visibility: visibility)

        let snapshot = AIHomeworkSchoolCreditHandoffSnapshot(
            generatedAt: generatedAt,
            header: AIHomeworkSchoolCreditHandoffHeader(
                viewerRole: viewerRole,
                state: state,
                generatedAt: generatedAt,
                privacyScope: privacyScope(for: viewerRole)
            ),
            visibility: visibility,
            state: state,
            assignment: assignment,
            guidance: guidanceView(guidance: guidanceFacts, directAnswerBlocked: directAnswerBlocked),
            adultReview: visibleAdult,
            credit: visibleCredit,
            childNextStep: nextStep,
            careSummary: care,
            findings: findings,
            publicSummary: publicSummary(
                viewerRole: viewerRole,
                visibility: visibility,
                state: state,
                assignment: assignment,
                guidance: guidanceFacts,
                directAnswerBlocked: directAnswerBlocked,
                adultReview: adult,
                credit: credit,
                nextStep: nextStep,
                findings: findings
            )
        )
        return redacts(snapshot)
            ? snapshot
            : safeFallback(viewerRole: viewerRole, visibility: visibility, code: .publicSummaryLeak)
    }

    func redacts(_ snapshot: AIHomeworkSchoolCreditHandoffSnapshot) -> Bool {
        !hasUnsafeDisplayValues(displayValues(snapshot))
    }

    // MARK: - Role & visibility

    private func guidanceRole(_ role: AIHomeworkSchoolCreditHandoffViewerRole) -> AIHomeworkSessionViewerRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .teacher: return .teacher
        }
    }

    private func privacyScope(for role: AIHomeworkSchoolCreditHandoffViewerRole) -> String {
        switch role {
        case .child: return "private"
        case .guardian: return "family_care"
        case .teacher: return "school_care"
        }
    }

    private func visibility(for role: AIHomeworkSchoolCreditHandoffViewerRole) -> AIHomeworkSchoolCreditHandoffVisibility {
        switch role {
        case .child:
            return AIHomeworkSchoolCreditHandoffVisibility(
                viewerRole: role,
                canSeeGuidanceFacts: true,
                canSeeAdultReviewDetail: false,
                canSeeCreditDetail: false,
                canSeeCareSummary: false,
                canSeeChildNextStep: true
            )
        case .guardian:
            return AIHomeworkSchoolCreditHandoffVisibility(
                viewerRole: role,
                canSeeGuidanceFacts: true,
                canSeeAdultReviewDetail: true,
                canSeeCreditDetail: true,
                canSeeCareSummary: true,
                canSeeChildNextStep: true
            )
        case .teacher:
            return AIHomeworkSchoolCreditHandoffVisibility(
                viewerRole: role,
                canSeeGuidanceFacts: true,
                canSeeAdultReviewDetail: true,
                canSeeCreditDetail: false,
                canSeeCareSummary: true,
                canSeeChildNextStep: true
            )
        }
    }

    // MARK: - Views

    private func assignmentView(_ homework: SchoolHomework) -> AIHomeworkSchoolCreditAssignmentView {
        AIHomeworkSchoolCreditAssignmentView(
            subjectLabel: homework.subject.label,
            statusLabel: homework.status.label,
            accepted: homework.status != .returned,
            needsRedo: homework.status == .returned
        )
    }

    private func guidanceView(
        guidance: AIHomeworkGuidanceSessionSnapshot,
        directAnswerBlocked: Bool
    ) -> AIHomeworkSchoolCreditGuidanceView {
        AIHomeworkSchoolCreditGuidanceView(
            guidanceAccepted: guidance.header.status != .blocked && !directAnswerBlocked,
            noDirectAnswer: !directAnswerBlocked && !guidance.publicSummary.givesAnswer,
            referenceHintCount: max(guidance.publicSummary.stepCount - guidance.publicSummary.checklistCount, 0),
            selfCheckCount: guidance.publicSummary.checklistCount,
            guidanceStepCount: guidance.publicSummary.stepCount
        )
    }

    private func adultReviewView(
        homework: SchoolHomework,
        jointApproval: SchoolJointApprovalSnapshot?
    ) -> AIHomeworkSchoolCreditAdultReviewView {
        if let jointApproval {
            let summary = jointApproval.stageSummary
            let teacherRequired = summary.awaitingTeacherCount > 0 || jointApproval.header.status == .awaitingTeacher
            let guardianRequired = summary.awaitingGuardianCount > 0 || jointApproval.header.status == .awaitingGuardian
            let blocked = jointApproval.header.status == .blocked || summary.blockedCount > 0 || summary.returnedCount > 0
            return AIHomeworkSchoolCreditAdultReviewView(
                boardStatusLabel: jointApproval.header.status.label,
                teacherReviewRequired: teacherRequired,
                guardianConfirmationRequired: guardianRequired,
                confirmedCount: summary.confirmedCount,
                blocked: blocked,
                childVisibleMessage: childReviewCopy(
                    homeworkStatus: homework.status,
                    teacherRequired: teacherRequired,
                    guardianRequired: guardianRequired,
                    blocked: blocked
                )
            )
        }

        let teacherRequired = homework.status == .submitted
        let guardianRequired = homework.status == .verified
        let blocked = homework.status == .returned
        let confirmedCount = homework.status == .verified ? 1 : 0
        return AIHomeworkSchoolCreditAdultReviewView(
            boardStatusLabel: homework.status.label,
            teacherReviewRequired: teacherRequired,
            guardianConfirmationRequired: guardianRequired,
            confirmedCount: confirmedCount,
            blocked: blocked,
            childVisibleMessage: childReviewCopy(
                homeworkStatus: homework.status,
                teacherRequired: teacherRequired,
                guardianRequired: guardianRequired,
                blocked: blocked
            )
        )
    }

    private func childReviewCopy(
        homeworkStatus: HomeworkStatus,
        teacherRequired: Bool,
        guardianRequired: Bool,
        blocked: Bool
    ) -> String {
        if blocked { return "这条作业需要再完成一遍，先别急着领奖励。" }
        if teacherRequired { return "作业已经交上去，正在等老师看看。" }
        if guardianRequired { return "老师已经看过，正在等家长确认奖励。" }
        switch homeworkStatus {
        case .assigned, .inProgress:
            return "先把作业按步骤完成，再提交给大人确认。"
        case .submitted:
            return "作业已经交上去，正在等老师看看。"
        case .verified:
            return "作业完成情况已经对齐，等家长复核奖励。"
        case .returned:
            return "这条作业需要再完成一遍，先别急着领奖励。"
        }
    }

    private func creditView(
        homework: SchoolHomework,
        directAnswerBlocked: Bool,
        adultReview: AIHomeworkSchoolCreditAdultReviewView,
        creditReview: CreditLedgerReviewConsole?
    ) -> AIHomeworkSchoolCreditCreditView {
        if let creditReview {
            let conflict = creditReview.summary.conflictCount
            let blocked = creditReview.summary.blockedOrIgnoredCount + conflict
            let reviewRequired = creditReview.summary.reviewRequiredCount
            let frozen = creditReview.summary.frozenCount
            let state: AIHomeworkSchoolCreditCreditState
            if blocked > 0 || directAnswerBlocked || adultReview.blocked {
                state = .blocked
            } else if reviewRequired > 0 || frozen > 0 || adultReview.teacherReviewRequired || adultReview.guardianConfirmationRequired {
                state = .frozen
            } else {
                state = .reviewable
            }
            return AIHomeworkSchoolCreditCreditView(
                state: state,
                settleableCount: creditReview.summary.proposableCount,
                frozenCount: frozen,
                conflictCount: conflict,
                reviewRequiredCount: reviewRequired,
                blockedCount: blocked,
                childVisibleCopy: childCreditCopy(state)
            )
        }

        let state: AIHomeworkSchoolCreditCreditState
        let settleable: Int
        let frozen: Int
        let blocked: Int
        let reviewRequired: Int
        if directAnswerBlocked || adultReview.blocked || homework.status == .returned {
            state = .blocked
            settleable = 0
            frozen = 0
            blocked = 1
            reviewRequired = 0
        } else if homework.status == .verified {
            state = .reviewable
            settleable = 1
            frozen = 0
            blocked = 0
            reviewRequired = 0
        } else {
            state = .frozen
            settleable = 0
            frozen = 1
            blocked = 0
            reviewRequired = adultReview.teacherReviewRequired || adultReview.guardianConfirmationRequired ? 1 : 0
        }
        return AIHomeworkSchoolCreditCreditView(
            state: state,
            settleableCount: settleable,
            frozenCount: frozen,
            conflictCount: 0,
            reviewRequiredCount: reviewRequired,
            blockedCount: blocked,
            childVisibleCopy: childCreditCopy(state)
        )
    }

    private func visibleAdultReview(
        _ adult: AIHomeworkSchoolCreditAdultReviewView,
        visibility: AIHomeworkSchoolCreditHandoffVisibility
    ) -> AIHomeworkSchoolCreditAdultReviewView {
        guard !visibility.canSeeAdultReviewDetail else { return adult }
        return AIHomeworkSchoolCreditAdultReviewView(
            boardStatusLabel: adult.blocked ? "需大人处理" : "处理中",
            teacherReviewRequired: false,
            guardianConfirmationRequired: false,
            confirmedCount: 0,
            blocked: adult.blocked,
            childVisibleMessage: adult.childVisibleMessage
        )
    }

    private func visibleCredit(
        _ credit: AIHomeworkSchoolCreditCreditView,
        visibility: AIHomeworkSchoolCreditHandoffVisibility
    ) -> AIHomeworkSchoolCreditCreditView {
        guard visibility.canSeeCreditDetail else {
            return AIHomeworkSchoolCreditCreditView(
                state: credit.state,
                settleableCount: 0,
                frozenCount: 0,
                conflictCount: 0,
                reviewRequiredCount: 0,
                blockedCount: credit.state == .blocked ? 1 : 0,
                childVisibleCopy: credit.childVisibleCopy
            )
        }
        return credit
    }

    private func childCreditCopy(_ state: AIHomeworkSchoolCreditCreditState) -> String {
        switch state {
        case .reviewable: return "成长积分可以交给家长复核。"
        case .frozen: return "成长积分正在等大人确认。"
        case .blocked: return "这条作业暂时不能换成长积分。"
        }
    }

    private func handoffState(
        assignment: AIHomeworkSchoolCreditAssignmentView,
        guidance: AIHomeworkGuidanceSessionSnapshot,
        directAnswerBlocked: Bool,
        adultReview: AIHomeworkSchoolCreditAdultReviewView,
        credit: AIHomeworkSchoolCreditCreditView
    ) -> AIHomeworkSchoolCreditHandoffState {
        if assignment.subjectLabel.isEmpty { return .empty }
        if !assignment.accepted || assignment.needsRedo || directAnswerBlocked || guidance.header.status == .blocked
            || adultReview.blocked || credit.state == .blocked {
            return .blocked
        }
        if adultReview.teacherReviewRequired || adultReview.guardianConfirmationRequired {
            return .reviewRequired
        }
        if credit.state == .frozen {
            return .frozen
        }
        return .ready
    }

    private func childNextStep(
        state: AIHomeworkSchoolCreditHandoffState,
        homework: SchoolHomework,
        directAnswerBlocked: Bool,
        adultReview: AIHomeworkSchoolCreditAdultReviewView,
        credit: AIHomeworkSchoolCreditCreditView
    ) -> AIHomeworkSchoolCreditChildNextStep {
        let kind: AIHomeworkSchoolCreditChildNextStepKind
        if directAnswerBlocked {
            kind = .removeAnswerMaterial
        } else if homework.status == .assigned || homework.status == .inProgress {
            kind = .continueGuidance
        } else if homework.status == .returned || state == .blocked || adultReview.blocked || credit.state == .blocked {
            kind = .waitForAssignmentReview
        } else if adultReview.teacherReviewRequired || adultReview.guardianConfirmationRequired {
            kind = .waitForAdultReview
        } else if credit.state == .frozen {
            kind = .waitForCreditReview
        } else {
            kind = .readOnly
        }
        return AIHomeworkSchoolCreditChildNextStep(
            publicActionRef: publicRef("ai-hw-next", "\(homework.subject.rawValue):\(homework.status.rawValue):\(kind.rawValue)"),
            kind: kind,
            title: kind.title,
            actionRequired: kind.actionRequired
        )
    }

    private func careSummary(
        viewerRole: AIHomeworkSchoolCreditHandoffViewerRole,
        homework: SchoolHomework,
        guidance: AIHomeworkGuidanceSessionSnapshot,
        state: AIHomeworkSchoolCreditHandoffState,
        directAnswerBlocked: Bool,
        adultReview: AIHomeworkSchoolCreditAdultReviewView,
        credit: AIHomeworkSchoolCreditCreditView
    ) -> AIHomeworkSchoolCreditCareSummary {
        let riskLabels = guidance.careSummary?.riskLabels.map(\.label) ?? []
        let intentLabels = guidance.careSummary?.intentLabels ?? []
        return AIHomeworkSchoolCreditCareSummary(
            subjectLabel: homework.subject.label,
            stateLabel: state.label,
            intentLabels: intentLabels,
            riskLabels: riskLabels,
            headline: "\(homework.subject.label) · \(state.label)",
            recommendedAction: recommendedAction(
                viewerRole: viewerRole,
                state: state,
                directAnswerBlocked: directAnswerBlocked,
                adultReview: adultReview,
                credit: credit
            )
        )
    }

    private func recommendedAction(
        viewerRole: AIHomeworkSchoolCreditHandoffViewerRole,
        state: AIHomeworkSchoolCreditHandoffState,
        directAnswerBlocked: Bool,
        adultReview: AIHomeworkSchoolCreditAdultReviewView,
        credit: AIHomeworkSchoolCreditCreditView
    ) -> String {
        if directAnswerBlocked {
            return "本次引导出现直接索要答案意图，应先回到提示和自检流程。"
        }
        if state == .blocked {
            return "先处理作业退回、成人阻断或成长积分冲突，再进入成长积分复核。"
        }
        if adultReview.teacherReviewRequired {
            return viewerRole == .teacher ? "请老师先完成作业完成情况验证。" : "等待老师完成作业验证。"
        }
        if adultReview.guardianConfirmationRequired {
            return "请家长确认作业完成情况后，再处理成长积分。"
        }
        if credit.state == .frozen {
            return "成长积分建议保持冻结，只能由家长复核后进入后续账本流程。"
        }
        return "作业引导、学校确认与成长积分复核入口已对齐，可以进入下一步人工复核。"
    }

    // MARK: - Findings & summary

    private func findings(
        viewerRole: AIHomeworkSchoolCreditHandoffViewerRole,
        visibility: AIHomeworkSchoolCreditHandoffVisibility,
        homework: SchoolHomework,
        messages: [AIHomeworkSessionMessage],
        guidance: AIHomeworkGuidanceSessionSnapshot,
        assignment: AIHomeworkSchoolCreditAssignmentView,
        adultReview: AIHomeworkSchoolCreditAdultReviewView,
        credit: AIHomeworkSchoolCreditCreditView,
        state: AIHomeworkSchoolCreditHandoffState,
        directAnswerBlocked: Bool
    ) -> [AIHomeworkSchoolCreditHandoffFinding] {
        var result: [AIHomeworkSchoolCreditHandoffFinding] = []
        func push(_ code: AIHomeworkSchoolCreditHandoffFindingCode, _ severity: AIHomeworkSchoolCreditHandoffSeverity, _ message: String) {
            result.append(AIHomeworkSchoolCreditHandoffFinding(
                code: code,
                severity: severity,
                message: message,
                publicRef: publicRef("ai-hw-school-credit-find", "\(viewerRole.rawValue):\(code.rawValue):\(result.count)")
            ))
        }

        if messages.isEmpty {
            push(.awaitingChildInput, .info, "孩子还没有在 AI 作业引导里提出问题。")
        }
        if viewerRole == .child && (!visibility.canSeeAdultReviewDetail || !visibility.canSeeCreditDetail) {
            push(.childVisibilityRedacted, .info, "孩子端已隐藏成人审批明细与成长积分复核细节。")
        }
        if homework.status == .returned || assignment.needsRedo {
            push(.schoolAssignmentReturned, .warning, "学校作业处于退回重做状态。")
            push(.schoolAssignmentBlocked, .blocker, "退回作业不能交接到成长积分复核。")
        }
        if directAnswerBlocked {
            push(.guidanceDirectAnswerBlocked, .blocker, "AI 引导出现直接索要答案意图，已阻断成长积分交接。")
        } else if guidance.header.status == .blocked {
            push(.guidanceNotAccepted, .blocker, "AI 作业引导未通过脱敏或安全检查。")
        }
        if visibility.canSeeAdultReviewDetail && adultReview.teacherReviewRequired {
            push(.teacherReviewRequired, .info, "作业提交后仍需老师验证。")
        }
        if visibility.canSeeAdultReviewDetail && adultReview.guardianConfirmationRequired {
            push(.guardianConfirmationRequired, .info, "老师验证后仍需家长确认。")
        }
        if visibility.canSeeAdultReviewDetail && adultReview.blocked {
            push(.adultReviewBlocked, .blocker, "成人审批链路当前不可继续交接。")
        }
        if visibility.canSeeCreditDetail && credit.state == .frozen {
            push(.creditReviewFrozen, .warning, "成长积分建议保持冻结，等待成人复核。")
        }
        if visibility.canSeeCreditDetail && (credit.conflictCount > 0 || credit.blockedCount > 0) {
            push(.creditConflictBlocked, .blocker, "成长积分复核存在冲突或阻断项。")
        }
        push(.roleVisibilityApplied, .info, "已按 \(viewerRole.label) 视角裁剪作业、引导、审批与成长积分信息。")
        if state == .ready && !result.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            push(.handoffReady, .ok, "AI 作业引导、学校确认与成长积分复核入口已只读对齐。")
        }
        return result
    }

    private func publicSummary(
        viewerRole: AIHomeworkSchoolCreditHandoffViewerRole,
        visibility: AIHomeworkSchoolCreditHandoffVisibility,
        state: AIHomeworkSchoolCreditHandoffState,
        assignment: AIHomeworkSchoolCreditAssignmentView,
        guidance: AIHomeworkGuidanceSessionSnapshot,
        directAnswerBlocked: Bool,
        adultReview: AIHomeworkSchoolCreditAdultReviewView,
        credit: AIHomeworkSchoolCreditCreditView,
        nextStep: AIHomeworkSchoolCreditChildNextStep,
        findings: [AIHomeworkSchoolCreditHandoffFinding]
    ) -> AIHomeworkSchoolCreditHandoffPublicSummary {
        AIHomeworkSchoolCreditHandoffPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            state: state,
            subjectLabel: assignment.subjectLabel,
            accepted: assignment.accepted,
            noDirectAnswer: !directAnswerBlocked && !guidance.publicSummary.givesAnswer,
            referenceHintCount: max(guidance.publicSummary.stepCount - guidance.publicSummary.checklistCount, 0),
            selfCheckCount: guidance.publicSummary.checklistCount,
            teacherReviewRequired: visibility.canSeeAdultReviewDetail ? adultReview.teacherReviewRequired : false,
            guardianConfirmationRequired: visibility.canSeeAdultReviewDetail ? adultReview.guardianConfirmationRequired : false,
            creditState: credit.state,
            childNextStepKind: nextStep.kind,
            findingCodes: findings.map(\.code)
        )
    }

    // MARK: - Empty & fallback

    private func emptySnapshot(
        viewerRole: AIHomeworkSchoolCreditHandoffViewerRole,
        visibility: AIHomeworkSchoolCreditHandoffVisibility
    ) -> AIHomeworkSchoolCreditHandoffSnapshot {
        let finding = AIHomeworkSchoolCreditHandoffFinding(
            code: .handoffReady,
            severity: .ok,
            message: "当前没有可交接复核的作业，入口保持只读空态。",
            publicRef: publicRef("ai-hw-school-credit-find", "\(viewerRole.rawValue):empty")
        )
        let assignment = AIHomeworkSchoolCreditAssignmentView(subjectLabel: "", statusLabel: "", accepted: false, needsRedo: false)
        let guidance = AIHomeworkSchoolCreditGuidanceView(
            guidanceAccepted: false,
            noDirectAnswer: true,
            referenceHintCount: 0,
            selfCheckCount: 0,
            guidanceStepCount: 0
        )
        let adult = AIHomeworkSchoolCreditAdultReviewView(
            boardStatusLabel: "暂无审批",
            teacherReviewRequired: false,
            guardianConfirmationRequired: false,
            confirmedCount: 0,
            blocked: false,
            childVisibleMessage: "现在没有需要交接复核的作业。"
        )
        let credit = AIHomeworkSchoolCreditCreditView(
            state: .frozen,
            settleableCount: 0,
            frozenCount: 0,
            conflictCount: 0,
            reviewRequiredCount: 0,
            blockedCount: 0,
            childVisibleCopy: "现在没有成长积分需要复核。"
        )
        let next = AIHomeworkSchoolCreditChildNextStep(
            publicActionRef: publicRef("ai-hw-next", "\(viewerRole.rawValue):empty"),
            kind: .readOnly,
            title: AIHomeworkSchoolCreditChildNextStepKind.readOnly.title,
            actionRequired: false
        )
        return AIHomeworkSchoolCreditHandoffSnapshot(
            generatedAt: generatedAt,
            header: AIHomeworkSchoolCreditHandoffHeader(
                viewerRole: viewerRole,
                state: .empty,
                generatedAt: generatedAt,
                privacyScope: privacyScope(for: viewerRole)
            ),
            visibility: visibility,
            state: .empty,
            assignment: assignment,
            guidance: guidance,
            adultReview: adult,
            credit: credit,
            childNextStep: next,
            careSummary: nil,
            findings: [finding],
            publicSummary: AIHomeworkSchoolCreditHandoffPublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                state: .empty,
                subjectLabel: "",
                accepted: false,
                noDirectAnswer: true,
                referenceHintCount: 0,
                selfCheckCount: 0,
                teacherReviewRequired: false,
                guardianConfirmationRequired: false,
                creditState: .frozen,
                childNextStepKind: .readOnly,
                findingCodes: [finding.code]
            )
        )
    }

    private func safeFallback(
        viewerRole: AIHomeworkSchoolCreditHandoffViewerRole,
        visibility: AIHomeworkSchoolCreditHandoffVisibility,
        code: AIHomeworkSchoolCreditHandoffFindingCode
    ) -> AIHomeworkSchoolCreditHandoffSnapshot {
        let finding = AIHomeworkSchoolCreditHandoffFinding(
            code: code,
            severity: .blocker,
            message: "AI 作业学校成长积分交接复核未通过本地脱敏检查，已降级为安全阻断态。",
            publicRef: publicRef("ai-hw-school-credit-find", "\(viewerRole.rawValue):safe-fallback")
        )
        let assignment = AIHomeworkSchoolCreditAssignmentView(subjectLabel: "", statusLabel: "安全阻断", accepted: false, needsRedo: false)
        let guidance = AIHomeworkSchoolCreditGuidanceView(
            guidanceAccepted: false,
            noDirectAnswer: true,
            referenceHintCount: 0,
            selfCheckCount: 0,
            guidanceStepCount: 0
        )
        let adult = AIHomeworkSchoolCreditAdultReviewView(
            boardStatusLabel: "安全阻断",
            teacherReviewRequired: false,
            guardianConfirmationRequired: false,
            confirmedCount: 0,
            blocked: true,
            childVisibleMessage: "这条作业需要先让大人看看。"
        )
        let credit = AIHomeworkSchoolCreditCreditView(
            state: .blocked,
            settleableCount: 0,
            frozenCount: 0,
            conflictCount: 0,
            reviewRequiredCount: 0,
            blockedCount: 1,
            childVisibleCopy: "这条作业暂时不能换成长积分。"
        )
        let next = AIHomeworkSchoolCreditChildNextStep(
            publicActionRef: publicRef("ai-hw-next", "\(viewerRole.rawValue):safe-fallback"),
            kind: .readOnly,
            title: AIHomeworkSchoolCreditChildNextStepKind.readOnly.title,
            actionRequired: false
        )
        return AIHomeworkSchoolCreditHandoffSnapshot(
            generatedAt: generatedAt,
            header: AIHomeworkSchoolCreditHandoffHeader(
                viewerRole: viewerRole,
                state: .blocked,
                generatedAt: generatedAt,
                privacyScope: "private"
            ),
            visibility: visibility,
            state: .blocked,
            assignment: assignment,
            guidance: guidance,
            adultReview: adult,
            credit: credit,
            childNextStep: next,
            careSummary: nil,
            findings: [finding],
            publicSummary: AIHomeworkSchoolCreditHandoffPublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                state: .blocked,
                subjectLabel: "",
                accepted: false,
                noDirectAnswer: true,
                referenceHintCount: 0,
                selfCheckCount: 0,
                teacherReviewRequired: false,
                guardianConfirmationRequired: false,
                creditState: .blocked,
                childNextStepKind: .readOnly,
                findingCodes: [finding.code]
            )
        )
    }

    // MARK: - Safety

    private func hasUnsafeInput(
        homework: SchoolHomework?,
        messages: [AIHomeworkSessionMessage],
        jointApproval: SchoolJointApprovalSnapshot?,
        creditReview: CreditLedgerReviewConsole?
    ) -> Bool {
        if messages.contains(where: \.containsUnsafeInput) { return true }
        var values: [String] = []
        if let homework {
            values.append(contentsOf: [
                homework.subject.label,
                homework.title,
                homework.instructions,
                homework.dueLabel,
                homework.status.label
            ])
            values.append(contentsOf: homework.guidance.hints)
            values.append(contentsOf: homework.guidance.checklist)
            values.append(homework.guidance.nextStep)
        }
        if let jointApproval {
            values.append(jointApproval.header.privacyScope)
            values.append(contentsOf: jointApproval.items.flatMap { [$0.publicItemRef, $0.headline, $0.childSafeCopy, $0.guardianReason ?? ""] })
            values.append(contentsOf: jointApproval.findings.flatMap { [$0.publicRef, $0.message] })
        }
        if let creditReview {
            values.append(creditReview.headline)
            values.append(contentsOf: creditReview.sections.flatMap { group in
                group.items.flatMap { [$0.publicReviewRef, $0.childSafeStatus, $0.reason ?? "", $0.sourceLabel ?? ""] }
            })
            values.append(contentsOf: creditReview.findings.flatMap { [$0.publicRef, $0.message] })
        }
        return hasUnsafeDisplayValues(values)
    }

    private func hasUnsafeDisplayValues(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let rawPatterns = [
            "(?i)\\b(child|family|school|class|teacher|guardian|homework|submission|proof|ledger|credit|event|session|transcript|provider|model|source|ref):[a-z0-9_-]+",
            "(?i)\\b(taskId|claimId|server-secret|device-token|api[_-]?key)\\b",
            "(?i)\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b",
            "(?i)file://|/Users/|/Volumes/"
        ]
        return values.contains { value in
            rawPatterns.contains { pattern in
                value.range(of: pattern, options: .regularExpression) != nil
            }
        }
    }

    private func displayValues(_ snapshot: AIHomeworkSchoolCreditHandoffSnapshot) -> [String] {
        var values = [
            snapshot.generatedAt,
            snapshot.header.privacyScope,
            snapshot.header.viewerRole.rawValue,
            snapshot.header.state.rawValue,
            snapshot.assignment.subjectLabel,
            snapshot.assignment.statusLabel,
            snapshot.adultReview.boardStatusLabel,
            snapshot.adultReview.childVisibleMessage,
            snapshot.credit.childVisibleCopy,
            snapshot.childNextStep.publicActionRef,
            snapshot.childNextStep.title,
            snapshot.headline
        ]
        if let care = snapshot.careSummary {
            values.append(contentsOf: [
                care.subjectLabel,
                care.stateLabel,
                care.headline,
                care.recommendedAction
            ])
            values.append(contentsOf: care.intentLabels)
            values.append(contentsOf: care.riskLabels)
        }
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
