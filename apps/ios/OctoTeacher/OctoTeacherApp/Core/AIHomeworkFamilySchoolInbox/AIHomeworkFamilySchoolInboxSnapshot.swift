import Foundation

/// iOS 端「AI 作业家校收件箱」只读投影。
///
/// 组合本地学校作业、AI 引导安全状态、AI/LMS 边界、作业成长积分交接和家长审批摘要，
/// 只回答“谁现在应该看什么、下一步做什么”。它不调用真实 AI、LMS、学校系统、
/// 通知、账本、云端、数据库或设备控制。
enum AIHomeworkFamilySchoolInboxViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case teacher
    case operations

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .teacher: return "老师"
        case .operations: return "运营"
        }
    }
}

enum AIHomeworkFamilySchoolInboxStatus: String, Equatable {
    case ready
    case empty
    case reviewRequired = "review_required"
    case blocked

    var label: String {
        switch self {
        case .ready: return "可查看"
        case .empty: return "暂无事项"
        case .reviewRequired: return "需要复核"
        case .blocked: return "已阻断"
        }
    }
}

enum AIHomeworkFamilySchoolInboxItemKind: String, Equatable, CaseIterable {
    case guidance = "ai_guidance"
    case homeworkStatus = "homework_status"
    case teacherReview = "teacher_review"
    case guardianReview = "guardian_review"
    case lmsBoundary = "lms_boundary"
    case creditReview = "credit_review"
    case parentInbox = "parent_inbox"
    case operationsSummary = "operations_summary"

    var title: String {
        switch self {
        case .guidance: return "AI 引导"
        case .homeworkStatus: return "作业状态"
        case .teacherReview: return "老师复核"
        case .guardianReview: return "家长复核"
        case .lmsBoundary: return "LMS 边界"
        case .creditReview: return "成长积分复核"
        case .parentInbox: return "家长收件箱"
        case .operationsSummary: return "脱敏运营摘要"
        }
    }
}

enum AIHomeworkFamilySchoolInboxSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

enum AIHomeworkFamilySchoolInboxFindingCode: String, Equatable {
    case inboxOK = "AI_HOMEWORK_FAMILY_SCHOOL_INBOX_OK"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case childSensitiveFieldsHidden = "CHILD_SENSITIVE_FIELDS_HIDDEN"
    case nonGuardianQueueHidden = "NON_GUARDIAN_QUEUE_HIDDEN"
    case directAnswerBlocked = "DIRECT_ANSWER_BLOCKED"
    case manualReviewRequired = "MANUAL_REVIEW_REQUIRED"
    case lmsBoundaryBlocked = "LMS_BOUNDARY_BLOCKED"
    case returnedHomeworkBlocked = "RETURNED_HOMEWORK_BLOCKED"
    case creditReviewFrozen = "CREDIT_REVIEW_FROZEN"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

struct AIHomeworkFamilySchoolInboxVisibility: Equatable {
    var viewerRole: AIHomeworkFamilySchoolInboxViewerRole
    var canSeeChildNextStep: Bool
    var canSeeGuardianQueue: Bool
    var canSeeTeacherReview: Bool
    var canSeeCreditReview: Bool
    var canSeeOperationsSummary: Bool

    var hidesSensitiveFields: Bool {
        viewerRole == .child || viewerRole == .teacher || viewerRole == .operations
    }
}

struct AIHomeworkFamilySchoolInboxItem: Identifiable, Equatable {
    var publicItemRef: String
    var kind: AIHomeworkFamilySchoolInboxItemKind
    var title: String
    var detail: String
    var badge: String
    var actionRequired: Bool
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToTeacher: Bool
    var visibleToOperations: Bool

    let showsAnswerKey = false
    let showsProviderOrModel = false
    let showsRawTranscript = false
    let showsTeacherPrivateNote = false
    let showsGuardianConsentDetail = false
    let showsCreditAmount = false
    let showsCrossChildContent = false
    let writesHomework = false
    let writesLedger = false
    let sendsNotification = false
    let callsLms = false
    let callsAiProvider = false

    var id: String { publicItemRef }
}

struct AIHomeworkFamilySchoolInboxNextAction: Identifiable, Equatable {
    var publicActionRef: String
    var title: String
    var actionRequired: Bool
    var visibleToViewer: Bool

    let writesSystem = false
    let sendsNotification = false

    var id: String { publicActionRef }
}

struct AIHomeworkFamilySchoolInboxFinding: Identifiable, Equatable {
    var code: AIHomeworkFamilySchoolInboxFindingCode
    var severity: AIHomeworkFamilySchoolInboxSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct AIHomeworkFamilySchoolInboxPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: AIHomeworkFamilySchoolInboxViewerRole
    var status: AIHomeworkFamilySchoolInboxStatus
    var visibleItemCount: Int
    var actionRequiredCount: Int
    var homeworkCount: Int
    var teacherReviewCount: Int
    var guardianReviewCount: Int
    var lmsBlockedCount: Int
    var findingCodes: [AIHomeworkFamilySchoolInboxFindingCode]

    let callsAiProvider = false
    let callsNetwork = false
    let writesDatabase = false
    let callsLms = false
    let writesSchoolSystem = false
    let sendsNotification = false
    let writesLedger = false
    let issuesCredit = false
    let unlocksDevice = false
    let storesRawTranscript = false
    let revealsProviderOrModel = false
    let showsCreditAmount = false
}

struct AIHomeworkFamilySchoolInboxSideEffects: Equatable {
    let callsAiProvider = false
    let callsNetwork = false
    let writesDatabase = false
    let callsLms = false
    let writesSchoolSystem = false
    let sendsNotification = false
    let writesLedger = false
    let issuesCredit = false
    let unlocksDevice = false

    var hasTriggeredSideEffect: Bool {
        callsAiProvider || callsNetwork || writesDatabase || callsLms || writesSchoolSystem
            || sendsNotification || writesLedger || issuesCredit || unlocksDevice
    }
}

struct AIHomeworkFamilySchoolInboxSnapshot: Equatable {
    var generatedAt: String
    var viewerRole: AIHomeworkFamilySchoolInboxViewerRole
    var status: AIHomeworkFamilySchoolInboxStatus
    var visibility: AIHomeworkFamilySchoolInboxVisibility
    var headline: String
    var items: [AIHomeworkFamilySchoolInboxItem]
    var nextActions: [AIHomeworkFamilySchoolInboxNextAction]
    var findings: [AIHomeworkFamilySchoolInboxFinding]
    var publicSummary: AIHomeworkFamilySchoolInboxPublicSummary
    var sideEffects: AIHomeworkFamilySchoolInboxSideEffects
}

struct AIHomeworkFamilySchoolInboxBuilder {
    var generatedAt: String = "2026-06-24T11:00:00Z"
    var redactionSalt: String = "ai-homework-family-school-inbox-ios-v1"

    private let handoffBuilder = AIHomeworkSchoolCreditHandoffBuilder()
    private let lmsBuilder = AIHomeworkSchoolLmsBoundaryBuilder()

    func build(
        viewerRole: AIHomeworkFamilySchoolInboxViewerRole,
        homeworks: [SchoolHomework],
        messagesByHomeworkID: [UUID: [AIHomeworkSessionMessage]] = [:],
        parentInbox: ParentApprovalInboxSnapshot? = nil
    ) -> AIHomeworkFamilySchoolInboxSnapshot {
        let visibility = visibility(for: viewerRole)
        if hasUnsafeInput(homeworks: homeworks) {
            return safeFallback(viewerRole: viewerRole, visibility: visibility)
        }

        let source = sourceRows(
            role: viewerRole,
            homeworks: homeworks,
            messagesByHomeworkID: messagesByHomeworkID
        )
        let items = visibleItems(
            role: viewerRole,
            rows: source,
            parentInbox: parentInbox,
            visibility: visibility
        )
        let findings = findings(
            role: viewerRole,
            rows: source,
            parentInbox: parentInbox,
            visibility: visibility
        )
        let status = statusFor(items: items, findings: findings, homeworks: homeworks)
        let snapshot = AIHomeworkFamilySchoolInboxSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            visibility: visibility,
            headline: headline(status: status, items: items, role: viewerRole),
            items: items,
            nextActions: nextActions(from: items, role: viewerRole),
            findings: findings,
            publicSummary: publicSummary(
                role: viewerRole,
                status: status,
                homeworks: homeworks,
                items: items,
                findings: findings
            ),
            sideEffects: AIHomeworkFamilySchoolInboxSideEffects()
        )
        return redacts(snapshot) ? snapshot : safeFallback(viewerRole: viewerRole, visibility: visibility)
    }

    func redacts(_ snapshot: AIHomeworkFamilySchoolInboxSnapshot) -> Bool {
        let values = displayValues(snapshot)
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ").lowercased()
        let blockedMarkers = [
            "child:", "family:", "school:", "teacher:", "guardian:", "homework:",
            "provider:", "model:", "transcript:", "ledger:", "credit:", "taskid",
            "claimid", "http://", "https://", "file://", "/users/", "/volumes/", "192.168."
        ]
        return !blockedMarkers.contains { joined.contains($0) }
    }

    private func visibility(for role: AIHomeworkFamilySchoolInboxViewerRole) -> AIHomeworkFamilySchoolInboxVisibility {
        switch role {
        case .child:
            return AIHomeworkFamilySchoolInboxVisibility(
                viewerRole: role,
                canSeeChildNextStep: true,
                canSeeGuardianQueue: false,
                canSeeTeacherReview: false,
                canSeeCreditReview: false,
                canSeeOperationsSummary: false
            )
        case .guardian:
            return AIHomeworkFamilySchoolInboxVisibility(
                viewerRole: role,
                canSeeChildNextStep: true,
                canSeeGuardianQueue: true,
                canSeeTeacherReview: true,
                canSeeCreditReview: true,
                canSeeOperationsSummary: false
            )
        case .teacher:
            return AIHomeworkFamilySchoolInboxVisibility(
                viewerRole: role,
                canSeeChildNextStep: false,
                canSeeGuardianQueue: false,
                canSeeTeacherReview: true,
                canSeeCreditReview: false,
                canSeeOperationsSummary: false
            )
        case .operations:
            return AIHomeworkFamilySchoolInboxVisibility(
                viewerRole: role,
                canSeeChildNextStep: false,
                canSeeGuardianQueue: false,
                canSeeTeacherReview: false,
                canSeeCreditReview: false,
                canSeeOperationsSummary: true
            )
        }
    }

    private struct SourceRow {
        var index: Int
        var homework: SchoolHomework
        var messages: [AIHomeworkSessionMessage]
        var handoff: AIHomeworkSchoolCreditHandoffSnapshot
        var lms: AIHomeworkSchoolLmsBoundarySnapshot
        var directAnswerBlocked: Bool
    }

    private func sourceRows(
        role: AIHomeworkFamilySchoolInboxViewerRole,
        homeworks: [SchoolHomework],
        messagesByHomeworkID: [UUID: [AIHomeworkSessionMessage]]
    ) -> [SourceRow] {
        homeworks.enumerated().map { index, homework in
            let messages = messagesByHomeworkID[homework.id] ?? sampleMessages(for: homework)
            let directAnswer = messages.contains { $0.intent == .wantsDirectAnswer || $0.containsUnsafeInput }
            let handoff = handoffBuilder.build(
                viewerRole: handoffRole(for: role),
                homework: homework,
                messages: messages
            )
            let lms = lmsBuilder.build(
                viewerRole: lmsRole(for: role),
                homework: homework,
                messages: messages,
                inputRisk: directAnswer ? .unsafePayloadDetected : .safe
            )
            return SourceRow(
                index: index,
                homework: homework,
                messages: messages,
                handoff: handoff,
                lms: lms,
                directAnswerBlocked: directAnswer
            )
        }
    }

    private func visibleItems(
        role: AIHomeworkFamilySchoolInboxViewerRole,
        rows: [SourceRow],
        parentInbox: ParentApprovalInboxSnapshot?,
        visibility: AIHomeworkFamilySchoolInboxVisibility
    ) -> [AIHomeworkFamilySchoolInboxItem] {
        switch role {
        case .child:
            return rows.flatMap { row in
                [
                    item(
                        row: row,
                        kind: .homeworkStatus,
                        title: row.homework.subject.label,
                        detail: row.handoff.childNextStep.title,
                        badge: row.handoff.state.label,
                        actionRequired: row.handoff.childNextStep.actionRequired,
                        role: role
                    ),
                    item(
                        row: row,
                        kind: .guidance,
                        title: "AI 只给提示",
                        detail: row.directAnswerBlocked ? "已拦截直接答案，改用提示和自检。" : "继续按提示和自检完成作业。",
                        badge: row.directAnswerBlocked ? "已拦截" : "安全",
                        actionRequired: row.directAnswerBlocked,
                        role: role
                    )
                ]
            }
        case .guardian:
            var items = rows.flatMap { row in
                [
                    item(
                        row: row,
                        kind: .guardianReview,
                        title: row.homework.subject.label,
                        detail: row.handoff.headline,
                        badge: row.handoff.state.label,
                        actionRequired: row.handoff.state != .ready && row.handoff.state != .empty,
                        role: role
                    ),
                    item(
                        row: row,
                        kind: .creditReview,
                        title: "成长积分复核",
                        detail: row.handoff.credit.childVisibleCopy,
                        badge: row.handoff.credit.state.label,
                        actionRequired: row.handoff.credit.state != .reviewable,
                        role: role
                    )
                ]
            }
            if let parentInbox, parentInbox.publicSummary.visibleItemCount > 0 {
                items.append(
                    standaloneItem(
                        kind: .parentInbox,
                        title: "家长收件箱",
                        detail: "\(parentInbox.publicSummary.visibleItemCount) 个家校/成长事项待复核。",
                        badge: parentInbox.header.status.label,
                        actionRequired: parentInbox.publicSummary.visibleItemCount > 0,
                        seed: "parent-\(parentInbox.publicSummary.visibleItemCount)",
                        role: role
                    )
                )
            }
            return items
        case .teacher:
            return rows.map { row in
                item(
                    row: row,
                    kind: .teacherReview,
                    title: row.homework.subject.label,
                    detail: row.lms.publicSummary.state == .blocked ? "学校边界已阻断，请走老师复核流程。" : "只显示学校作业和老师复核上下文。",
                    badge: row.lms.publicSummary.state.label,
                    actionRequired: row.lms.publicSummary.state != .ready,
                    role: role
                )
            }
        case .operations:
            return [
                standaloneItem(
                    kind: .operationsSummary,
                    title: "脱敏家校队列",
                    detail: "作业 \(rows.count) · 阻断 \(rows.filter { $0.handoff.state == .blocked || $0.lms.publicSummary.state == .blocked }.count) · 待复核 \(rows.filter { $0.handoff.state == .reviewRequired || $0.handoff.state == .frozen }.count)",
                    badge: rows.contains { $0.handoff.state == .blocked || $0.lms.publicSummary.state == .blocked } ? "需复核" : "正常",
                    actionRequired: rows.contains { $0.handoff.state == .blocked || $0.lms.publicSummary.state == .blocked },
                    seed: "operations-\(rows.count)",
                    role: role
                )
            ]
        }
    }

    private func findings(
        role: AIHomeworkFamilySchoolInboxViewerRole,
        rows: [SourceRow],
        parentInbox: ParentApprovalInboxSnapshot?,
        visibility: AIHomeworkFamilySchoolInboxVisibility
    ) -> [AIHomeworkFamilySchoolInboxFinding] {
        var result: [AIHomeworkFamilySchoolInboxFinding] = [
            finding(.roleVisibilityApplied, .info, "已按 \(role.label) 视角裁剪家校收件箱。", role.rawValue)
        ]
        if role == .child {
            result.append(finding(.childSensitiveFieldsHidden, .info, "孩子视角已隐藏成人复核、模型和成长积分等敏感内容。", "child"))
        }
        if role != .guardian && (parentInbox?.publicSummary.visibleItemCount ?? 0) > 0 {
            result.append(finding(.nonGuardianQueueHidden, .info, "家长审批队列已对当前视角隐藏。", role.rawValue))
        }
        if rows.contains(where: \.directAnswerBlocked) {
            result.append(finding(.directAnswerBlocked, .blocker, "直接答案请求已被拦截。", "direct-answer"))
        }
        if rows.contains(where: { $0.handoff.state == .reviewRequired }) {
            result.append(finding(.manualReviewRequired, .warning, "作业需要老师或家长复核。", "manual-review"))
        }
        if rows.contains(where: { $0.lms.publicSummary.state == .blocked }) {
            result.append(finding(.lmsBoundaryBlocked, .blocker, "AI/LMS 边界已阻断不安全输入或写回。", "lms"))
        }
        if rows.contains(where: { $0.homework.status == .returned }) {
            result.append(finding(.returnedHomeworkBlocked, .warning, "退回作业需要先重做。", "returned"))
        }
        if rows.contains(where: { $0.handoff.credit.state == .frozen }) {
            result.append(finding(.creditReviewFrozen, .warning, "成长积分建议正在等待成人复核。", "frozen"))
        }
        if !result.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            result.append(finding(.inboxOK, .ok, "家校收件箱只读、脱敏且无副作用。", "ok"))
        }
        return result
    }

    private func statusFor(
        items: [AIHomeworkFamilySchoolInboxItem],
        findings: [AIHomeworkFamilySchoolInboxFinding],
        homeworks: [SchoolHomework]
    ) -> AIHomeworkFamilySchoolInboxStatus {
        if findings.contains(where: { $0.severity == .blocker }) { return .blocked }
        if items.contains(where: \.actionRequired) || findings.contains(where: { $0.severity == .warning }) { return .reviewRequired }
        if homeworks.isEmpty || items.isEmpty { return .empty }
        return .ready
    }

    private func headline(
        status: AIHomeworkFamilySchoolInboxStatus,
        items: [AIHomeworkFamilySchoolInboxItem],
        role: AIHomeworkFamilySchoolInboxViewerRole
    ) -> String {
        if status == .empty { return "暂无家校作业事项" }
        if role == .child { return "这里会告诉你作业下一步，不会直接给答案。" }
        if role == .teacher { return "只查看学校作业和老师复核上下文。" }
        if role == .operations { return "只显示脱敏计数和阻断状态。" }
        let required = items.filter(\.actionRequired).count
        return required == 0 ? "家校作业收件箱正常" : "有 \(required) 个家校作业事项待复核"
    }

    private func nextActions(
        from items: [AIHomeworkFamilySchoolInboxItem],
        role: AIHomeworkFamilySchoolInboxViewerRole
    ) -> [AIHomeworkFamilySchoolInboxNextAction] {
        let actionable = items.filter(\.actionRequired)
        if actionable.isEmpty {
            return [
                AIHomeworkFamilySchoolInboxNextAction(
                    publicActionRef: publicRef("afs-action", "\(role.rawValue)-read-only"),
                    title: "保持只读查看，不触发通知、账本或设备动作。",
                    actionRequired: false,
                    visibleToViewer: true
                )
            ]
        }
        return actionable.map { item in
            AIHomeworkFamilySchoolInboxNextAction(
                publicActionRef: publicRef("afs-action", item.publicItemRef),
                title: item.kind == .guidance ? "回到提示和自检，不要直接要答案。" : item.title,
                actionRequired: true,
                visibleToViewer: true
            )
        }
    }

    private func publicSummary(
        role: AIHomeworkFamilySchoolInboxViewerRole,
        status: AIHomeworkFamilySchoolInboxStatus,
        homeworks: [SchoolHomework],
        items: [AIHomeworkFamilySchoolInboxItem],
        findings: [AIHomeworkFamilySchoolInboxFinding]
    ) -> AIHomeworkFamilySchoolInboxPublicSummary {
        AIHomeworkFamilySchoolInboxPublicSummary(
            generatedAt: generatedAt,
            viewerRole: role,
            status: status,
            visibleItemCount: items.count,
            actionRequiredCount: items.filter(\.actionRequired).count,
            homeworkCount: homeworks.count,
            teacherReviewCount: items.filter { $0.kind == .teacherReview }.count,
            guardianReviewCount: items.filter { $0.kind == .guardianReview || $0.kind == .parentInbox }.count,
            lmsBlockedCount: findings.filter { $0.code == .lmsBoundaryBlocked }.count,
            findingCodes: findings.map(\.code)
        )
    }

    private func handoffRole(
        for role: AIHomeworkFamilySchoolInboxViewerRole
    ) -> AIHomeworkSchoolCreditHandoffViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .operations: return .guardian
        case .teacher: return .teacher
        }
    }

    private func lmsRole(
        for role: AIHomeworkFamilySchoolInboxViewerRole
    ) -> AIHomeworkSchoolLmsBoundaryViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .operations: return .guardian
        case .teacher: return .teacher
        }
    }

    private func sampleMessages(for homework: SchoolHomework) -> [AIHomeworkSessionMessage] {
        switch homework.status {
        case .assigned: return []
        case .inProgress: return [.init(preset: .whereToStart)]
        case .submitted, .verified: return [.init(preset: .howToCheck)]
        case .returned: return [.init(preset: .stuckOnStep)]
        }
    }

    private func item(
        row: SourceRow,
        kind: AIHomeworkFamilySchoolInboxItemKind,
        title: String,
        detail: String,
        badge: String,
        actionRequired: Bool,
        role: AIHomeworkFamilySchoolInboxViewerRole
    ) -> AIHomeworkFamilySchoolInboxItem {
        standaloneItem(
            kind: kind,
            title: title,
            detail: detail,
            badge: badge,
            actionRequired: actionRequired,
            seed: "\(row.index)-\(kind.rawValue)-\(row.homework.subject.rawValue)-\(row.homework.status.rawValue)",
            role: role
        )
    }

    private func standaloneItem(
        kind: AIHomeworkFamilySchoolInboxItemKind,
        title: String,
        detail: String,
        badge: String,
        actionRequired: Bool,
        seed: String,
        role: AIHomeworkFamilySchoolInboxViewerRole
    ) -> AIHomeworkFamilySchoolInboxItem {
        AIHomeworkFamilySchoolInboxItem(
            publicItemRef: publicRef("afs-item", seed),
            kind: kind,
            title: sanitize(title, fallback: kind.title),
            detail: sanitize(detail, fallback: "请在对应流程中查看下一步。"),
            badge: sanitize(badge, fallback: "只读"),
            actionRequired: actionRequired,
            visibleToChild: role == .child,
            visibleToGuardian: role == .guardian,
            visibleToTeacher: role == .teacher,
            visibleToOperations: role == .operations
        )
    }

    private func finding(
        _ code: AIHomeworkFamilySchoolInboxFindingCode,
        _ severity: AIHomeworkFamilySchoolInboxSeverity,
        _ message: String,
        _ seed: String
    ) -> AIHomeworkFamilySchoolInboxFinding {
        AIHomeworkFamilySchoolInboxFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("afs-finding", "\(code.rawValue)-\(seed)")
        )
    }

    private func hasUnsafeInput(homeworks: [SchoolHomework]) -> Bool {
        MobileSyncPayloadGuard.isUnsafe(homeworks.flatMap { [$0.title, $0.instructions, $0.dueLabel] })
    }

    private func displayValues(_ snapshot: AIHomeworkFamilySchoolInboxSnapshot) -> [String] {
        [snapshot.generatedAt, snapshot.headline]
            + snapshot.items.flatMap { [$0.publicItemRef, $0.kind.rawValue, $0.title, $0.detail, $0.badge] }
            + snapshot.nextActions.flatMap { [$0.publicActionRef, $0.title] }
            + snapshot.findings.flatMap { [$0.publicRef, $0.message] }
    }

    private func sanitize(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if MobileSyncPayloadGuard.isUnsafe(trimmed) { return fallback }
        let lowercased = trimmed.lowercased()
        let blockedMarkers = [
            "child:", "family:", "school:", "teacher:", "guardian:", "homework:",
            "provider:", "model:", "transcript:", "ledger:", "credit:", "taskid",
            "claimid", "http://", "https://", "file://", "/users/", "/volumes/", "192.168."
        ]
        if blockedMarkers.contains(where: { lowercased.contains($0) }) { return fallback }
        return trimmed
    }

    private func safeFallback(
        viewerRole: AIHomeworkFamilySchoolInboxViewerRole,
        visibility: AIHomeworkFamilySchoolInboxVisibility
    ) -> AIHomeworkFamilySchoolInboxSnapshot {
        let finding = finding(.publicSummaryLeak, .blocker, "家校收件箱未通过公开脱敏检查，已进入安全保护模式。", "fallback")
        return AIHomeworkFamilySchoolInboxSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: .blocked,
            visibility: visibility,
            headline: "家校收件箱已进入安全保护模式",
            items: [],
            nextActions: [],
            findings: [finding],
            publicSummary: AIHomeworkFamilySchoolInboxPublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: .blocked,
                visibleItemCount: 0,
                actionRequiredCount: 0,
                homeworkCount: 0,
                teacherReviewCount: 0,
                guardianReviewCount: 0,
                lmsBlockedCount: 0,
                findingCodes: [.publicSummaryLeak]
            ),
            sideEffects: AIHomeworkFamilySchoolInboxSideEffects()
        )
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
}
