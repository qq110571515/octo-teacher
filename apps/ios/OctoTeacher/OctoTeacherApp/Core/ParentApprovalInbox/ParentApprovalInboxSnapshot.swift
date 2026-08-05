import Foundation

/// iOS 端「家长审批收件箱」只读快照。
///
/// 对齐控制台 B35 parent-approval-inbox-mobile-contract：聚合成长包证明、学校作业、
/// 亲友待审核、证据申诉、成长积分建议和离线冲突，形成家长端审批队列。它只读展示，
/// 不批准、不驳回、不写账本、不改作业、不通知、不解锁设备。
enum ParentApprovalInboxViewerRole: String, Equatable, CaseIterable {
    case guardian
    case child
    case relative
    case teacher

    var label: String {
        switch self {
        case .guardian: return "家长"
        case .child: return "孩子"
        case .relative: return "亲友"
        case .teacher: return "老师"
        }
    }
}

enum ParentApprovalInboxStatus: String, Equatable {
    case ready
    case empty
    case reviewRequired = "review_required"
    case offlineConflict = "offline_conflict"
    case blocked

    var label: String {
        switch self {
        case .ready: return "可查看"
        case .empty: return "暂无待审"
        case .reviewRequired: return "需要复核"
        case .offlineConflict: return "离线冲突"
        case .blocked: return "已阻断"
        }
    }
}

enum ParentApprovalInboxItemKind: String, Equatable, CaseIterable {
    case growthProof = "growth_proof"
    case schoolHomework = "school_homework"
    case relativeComment = "relative_comment"
    case evidenceAppeal = "evidence_appeal"
    case creditSuggestion = "credit_suggestion"
    case offlineConflict = "offline_conflict"

    var label: String {
        switch self {
        case .growthProof: return "成长证明"
        case .schoolHomework: return "学校作业"
        case .relativeComment: return "亲友鼓励"
        case .evidenceAppeal: return "证据申诉"
        case .creditSuggestion: return "成长积分建议"
        case .offlineConflict: return "离线冲突"
        }
    }
}

enum ParentApprovalInboxPriority: String, Equatable, CaseIterable {
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

enum ParentApprovalInboxFindingCode: String, Equatable {
    case inboxOK = "PARENT_APPROVAL_INBOX_OK"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case nonGuardianQueueHidden = "NON_GUARDIAN_QUEUE_HIDDEN"
    case offlineConflictActive = "OFFLINE_CONFLICT_ACTIVE"
    case appealOrFreezeActive = "APPEAL_OR_FREEZE_ACTIVE"
    case creditReviewRequired = "CREDIT_REVIEW_REQUIRED"
    case upstreamBlocked = "UPSTREAM_BLOCKED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

enum ParentApprovalInboxSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

enum ParentApprovalInboxSourceRole: String, Equatable {
    case child
    case guardian
    case teacher
    case relative
    case system

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .teacher: return "老师"
        case .relative: return "亲友"
        case .system: return "系统"
        }
    }
}

enum ParentApprovalInboxSourceKind: String, Equatable {
    case growthPack = "growth_pack"
    case schoolHomework = "school_homework"
    case familyAchievement = "family_achievement"
    case creditReward = "credit_reward"
    case offlineSync = "offline_sync"

    var label: String {
        switch self {
        case .growthPack: return "成长包"
        case .schoolHomework: return "学校作业"
        case .familyAchievement: return "家庭成就"
        case .creditReward: return "成长积分"
        case .offlineSync: return "离线同步"
        }
    }
}

struct ParentApprovalInboxSourceBoundary: Equatable {
    var sourceRole: ParentApprovalInboxSourceRole
    var sourceKind: ParentApprovalInboxSourceKind
    var childCanSeeCopy: Bool
    let relativeCanSeeInternalPriority = false
    let teacherCanSeeGuardianQueue = false
}

struct ParentApprovalInboxFinding: Identifiable, Equatable {
    var code: ParentApprovalInboxFindingCode
    var severity: ParentApprovalInboxSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct ParentApprovalInboxItem: Identifiable, Equatable {
    var publicApprovalRef: String
    var kind: ParentApprovalInboxItemKind
    var priority: ParentApprovalInboxPriority
    var title: String
    var childVisibleCopy: String
    var actionRequired: Bool
    var frozenOrBlockedReason: String?
    var sourceBoundary: ParentApprovalInboxSourceBoundary
    var idempotencyPublicRef: String

    let writesLedger = false
    let modifiesHomework = false
    let sendsNotification = false

    var id: String { publicApprovalRef }
}

struct ParentApprovalInboxNextAction: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case reviewItem = "review_item"
        case resolveAppeal = "resolve_appeal"
        case resolveOfflineConflict = "resolve_offline_conflict"
        case readOnly = "read_only"
    }

    var publicActionRef: String
    var kind: Kind
    var priority: ParentApprovalInboxPriority
    var title: String
    var actionRequired: Bool

    var id: String { publicActionRef }
}

struct ParentApprovalInboxVisibility: Equatable {
    var viewerRole: ParentApprovalInboxViewerRole
    var canSeeQueue: Bool
    var canSeeInternalPriority: Bool
    var canSeePrivateProof: Bool
    var canSeeRelativePendingComment: Bool
    var canSeeTeacherSource: Bool
    var canSeeCreditSuggestion: Bool
}

struct ParentApprovalInboxBatchSummary: Equatable {
    var totalCount: Int
    var urgentCount: Int
    var highCount: Int
    var mediumCount: Int
    var lowCount: Int
    var frozenCount: Int
    var blockedCount: Int

    let readOnly = true
    let approvesItems = false
    let rejectsItems = false
    let writesLedger = false
    let modifiesHomework = false
    let sendsNotification = false
}

struct ParentApprovalInboxPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: ParentApprovalInboxViewerRole
    var status: ParentApprovalInboxStatus
    var visibleItemCount: Int
    var growthProofCount: Int
    var schoolHomeworkCount: Int
    var relativeCommentCount: Int
    var evidenceAppealCount: Int
    var creditSuggestionCount: Int
    var offlineConflictCount: Int
    var findingCodes: [ParentApprovalInboxFindingCode]

    let approvesItems = false
    let rejectsItems = false
    let writesLedger = false
    let modifiesHomework = false
    let writesSchoolHomework = false
    let sendsNotification = false
    let notifiesRelatives = false
    let unlocksDevice = false
    let uploadsMedia = false
    let callsSchoolSystem = false
    let usesAiToAnswer = false
}

struct ParentApprovalInboxSnapshot: Equatable {
    var generatedAt: String
    var header: ParentApprovalInboxHeader
    var visibility: ParentApprovalInboxVisibility
    var items: [ParentApprovalInboxItem]
    var nextActions: [ParentApprovalInboxNextAction]
    var batchSummary: ParentApprovalInboxBatchSummary
    var findings: [ParentApprovalInboxFinding]
    var publicSummary: ParentApprovalInboxPublicSummary
}

struct ParentApprovalInboxHeader: Equatable {
    var viewerRole: ParentApprovalInboxViewerRole
    var status: ParentApprovalInboxStatus
    var generatedAt: String
}

struct ParentApprovalInboxSnapshotBuilder {
    var generatedAt: String = "2026-06-24T09:00:00Z"
    var redactionSalt: String = "parent-approval-inbox-ios-v1"

    func build(
        viewerRole: ParentApprovalInboxViewerRole,
        growthPack: GrowthPackMobileDetailSnapshot,
        schoolCredit: SchoolGrowthCreditSnapshot,
        familyAchievement: FamilyAchievementSnapshotDashboard,
        creditSettlement: MobileCreditSettlementReport,
        offlineStatus: MobileOfflinePublicStatus = .clean,
        offlineReport: MobileOfflineReplayReport = .empty
    ) -> ParentApprovalInboxSnapshot {
        let visibility = visibility(for: viewerRole)
        if hasUnsafeInput(
            growthPack: growthPack,
            schoolCredit: schoolCredit,
            familyAchievement: familyAchievement,
            creditSettlement: creditSettlement
        ) {
            return safeFallback(viewerRole: viewerRole, visibility: visibility)
        }

        let items = collectItems(
            viewerRole: viewerRole,
            growthPack: growthPack,
            schoolCredit: schoolCredit,
            familyAchievement: familyAchievement,
            creditSettlement: creditSettlement,
            offlineStatus: offlineStatus,
            offlineReport: offlineReport
        )
        let inboxFindings = findings(
            viewerRole: viewerRole,
            items: items,
            growthPack: growthPack,
            schoolCredit: schoolCredit,
            familyAchievement: familyAchievement
        )
        let status = statusFor(items: items, findings: inboxFindings)
        let header = ParentApprovalInboxHeader(
            viewerRole: viewerRole,
            status: status,
            generatedAt: generatedAt
        )
        let batch = batchSummary(items)
        let base = ParentApprovalInboxSnapshot(
            generatedAt: generatedAt,
            header: header,
            visibility: visibility,
            items: items,
            nextActions: nextActions(items),
            batchSummary: batch,
            findings: inboxFindings,
            publicSummary: publicSummary(
                viewerRole: viewerRole,
                status: status,
                items: items,
                findings: inboxFindings
            )
        )
        return redacts(base) ? base : safeFallback(viewerRole: viewerRole, visibility: visibility)
    }

    func redacts(_ snapshot: ParentApprovalInboxSnapshot) -> Bool {
        let values = displayValues(snapshot)
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ").lowercased()
        let blocked = ["child:", "family:", "school:", "teacher:", "relative:", "approval:", "homework:", "proof:", "ledger:", "event:", "task:", "claim:"]
        return !blocked.contains { joined.contains($0) }
    }

    // MARK: - Visibility

    private func visibility(for role: ParentApprovalInboxViewerRole) -> ParentApprovalInboxVisibility {
        let guardian = role == .guardian
        return ParentApprovalInboxVisibility(
            viewerRole: role,
            canSeeQueue: guardian,
            canSeeInternalPriority: guardian,
            canSeePrivateProof: guardian,
            canSeeRelativePendingComment: guardian,
            canSeeTeacherSource: guardian,
            canSeeCreditSuggestion: guardian
        )
    }

    // MARK: - Items

    private func collectItems(
        viewerRole: ParentApprovalInboxViewerRole,
        growthPack: GrowthPackMobileDetailSnapshot,
        schoolCredit: SchoolGrowthCreditSnapshot,
        familyAchievement: FamilyAchievementSnapshotDashboard,
        creditSettlement: MobileCreditSettlementReport,
        offlineStatus: MobileOfflinePublicStatus,
        offlineReport: MobileOfflineReplayReport
    ) -> [ParentApprovalInboxItem] {
        guard viewerRole == .guardian else { return [] }
        return growthItems(growthPack)
            + schoolItems(schoolCredit)
            + relativeItems(familyAchievement)
            + appealItems(growthPack: growthPack, schoolCredit: schoolCredit)
            + creditItems(creditSettlement)
            + offlineItems(status: offlineStatus, report: offlineReport)
    }

    private func growthItems(_ snapshot: GrowthPackMobileDetailSnapshot) -> [ParentApprovalInboxItem] {
        snapshot.nextActions
            .filter { $0.actionRequired && $0.kind == .guardianReview }
            .map { action in
                item(
                    kind: .growthProof,
                    priority: action.severity == .urgent ? .urgent : .medium,
                    title: "复核成长包证明",
                    childVisibleCopy: "证明正在等待家长复核。",
                    boundary: boundary(.child, .growthPack, childCanSeeCopy: action.visibleToChild),
                    seed: action.publicActionRef
                )
            }
    }

    private func schoolItems(_ snapshot: SchoolGrowthCreditSnapshot) -> [ParentApprovalInboxItem] {
        snapshot.nextActions
            .filter { $0.actionRequired && ($0.kind == .guardianConfirm || $0.kind == .teacherVerify || $0.kind == .resolveAppeal) }
            .map { action in
                let teacher = action.kind == .teacherVerify
                return item(
                    kind: action.kind == .resolveAppeal ? .evidenceAppeal : .schoolHomework,
                    priority: action.kind == .resolveAppeal ? .urgent : (teacher ? .high : .medium),
                    title: teacher ? "等待老师验证作业" : (action.kind == .resolveAppeal ? "处理学校作业申诉" : "确认学校作业结果"),
                    childVisibleCopy: teacher ? "作业还在等老师验证。" : "作业结果正在等待家长复核。",
                    boundary: boundary(teacher ? .teacher : .guardian, .schoolHomework, childCanSeeCopy: action.visibleToChild),
                    seed: action.publicActionRef,
                    frozenOrBlockedReason: action.kind == .resolveAppeal ? "appeal_or_credit_freeze_active" : nil
                )
            }
    }

    private func relativeItems(_ dashboard: FamilyAchievementSnapshotDashboard) -> [ParentApprovalInboxItem] {
        guard dashboard.relativeParticipation.pendingCommentCount > 0 else { return [] }
        return (0..<dashboard.relativeParticipation.pendingCommentCount).map { index in
            item(
                kind: .relativeComment,
                priority: .medium,
                title: "复核亲友鼓励",
                childVisibleCopy: "一条家庭鼓励正在等待家长审核。",
                boundary: boundary(.relative, .familyAchievement, childCanSeeCopy: false),
                seed: "relative-\(index)"
            )
        }
    }

    private func appealItems(
        growthPack: GrowthPackMobileDetailSnapshot,
        schoolCredit: SchoolGrowthCreditSnapshot
    ) -> [ParentApprovalInboxItem] {
        let count = max(0, growthPack.publicSummary.appealCount + schoolCredit.publicSummary.appealCount)
        return (0..<count).map { index in
            item(
                kind: .evidenceAppeal,
                priority: .urgent,
                title: "处理证据申诉",
                childVisibleCopy: "证据正在复核中。",
                boundary: boundary(.system, .growthPack, childCanSeeCopy: false),
                seed: "appeal-\(index)",
                frozenOrBlockedReason: "appeal_or_credit_freeze_active"
            )
        }
    }

    private func creditItems(_ report: MobileCreditSettlementReport) -> [ParentApprovalInboxItem] {
        report.proposals
            .filter { $0.status == .reviewRequired || $0.status == .proposed || $0.status == .conflict }
            .map { proposal in
                item(
                    kind: .creditSuggestion,
                    priority: proposal.status == .conflict ? .urgent : (proposal.status == .reviewRequired ? .high : .low),
                    title: "复核成长积分建议",
                    childVisibleCopy: "一条成长积分建议正在等待家长复核。",
                    boundary: boundary(.system, .creditReward, childCanSeeCopy: false),
                    seed: proposal.publicProposalRef,
                    frozenOrBlockedReason: proposal.status == .conflict ? "teacher_guardian_conflict" : nil
                )
            }
    }

    private func offlineItems(
        status: MobileOfflinePublicStatus,
        report: MobileOfflineReplayReport
    ) -> [ParentApprovalInboxItem] {
        let conflictCount = max(status.conflictCount, report.conflictCount)
        let rollbackCount = max(status.rolledBackCount, report.rolledBackCount)
        guard conflictCount + rollbackCount > 0 else { return [] }
        return [
            item(
                kind: .offlineConflict,
                priority: .urgent,
                title: "处理离线冲突",
                childVisibleCopy: "离线更改需要家长复核后才会应用。",
                boundary: boundary(.system, .offlineSync, childCanSeeCopy: false),
                seed: "offline-\(conflictCount)-\(rollbackCount)",
                frozenOrBlockedReason: "offline_conflict"
            )
        ]
    }

    // MARK: - Summaries

    private func batchSummary(_ items: [ParentApprovalInboxItem]) -> ParentApprovalInboxBatchSummary {
        ParentApprovalInboxBatchSummary(
            totalCount: items.count,
            urgentCount: items.filter { $0.priority == .urgent }.count,
            highCount: items.filter { $0.priority == .high }.count,
            mediumCount: items.filter { $0.priority == .medium }.count,
            lowCount: items.filter { $0.priority == .low }.count,
            frozenCount: items.filter { ($0.frozenOrBlockedReason ?? "").contains("freeze") || ($0.frozenOrBlockedReason ?? "").contains("appeal") }.count,
            blockedCount: items.filter { ($0.frozenOrBlockedReason ?? "").contains("blocked") || ($0.frozenOrBlockedReason ?? "").contains("conflict") }.count
        )
    }

    private func findings(
        viewerRole: ParentApprovalInboxViewerRole,
        items: [ParentApprovalInboxItem],
        growthPack: GrowthPackMobileDetailSnapshot,
        schoolCredit: SchoolGrowthCreditSnapshot,
        familyAchievement: FamilyAchievementSnapshotDashboard
    ) -> [ParentApprovalInboxFinding] {
        var result: [ParentApprovalInboxFinding] = []
        if viewerRole != .guardian {
            result.append(finding(.nonGuardianQueueHidden, .info, "家长审批队列已对非家长视角隐藏。", viewerRole.rawValue))
        }
        if items.contains(where: { $0.kind == .offlineConflict }) {
            result.append(finding(.offlineConflictActive, .warning, "审批收件箱存在离线冲突或回滚。", "offline"))
        }
        if items.contains(where: { $0.kind == .evidenceAppeal }) {
            result.append(finding(.appealOrFreezeActive, .warning, "证据申诉或成长积分冻结需要家长复核。", "appeal"))
        }
        if items.contains(where: { $0.kind == .creditSuggestion && $0.priority != .low }) {
            result.append(finding(.creditReviewRequired, .warning, "成长积分结算建议需要家长复核。", "credit"))
        }
        if viewerRole == .guardian &&
            (growthPack.header.status == .blocked || schoolCredit.header.status == .blocked || familyAchievement.status == .blocked) {
            result.append(finding(.upstreamBlocked, .blocker, "上游移动投影存在阻断状态。", "upstream"))
        }
        result.append(finding(.roleVisibilityApplied, .info, "已按 \(viewerRole.label) 视角裁剪审批收件箱。", viewerRole.rawValue))
        if !result.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            result.append(finding(.inboxOK, .ok, "家长审批收件箱只读、脱敏且无副作用。", "ok"))
        }
        return result
    }

    private func statusFor(
        items: [ParentApprovalInboxItem],
        findings: [ParentApprovalInboxFinding]
    ) -> ParentApprovalInboxStatus {
        if findings.contains(where: { $0.severity == .blocker }) { return .blocked }
        if items.contains(where: { $0.kind == .offlineConflict }) { return .offlineConflict }
        if items.contains(where: { $0.priority == .urgent || $0.priority == .high || $0.priority == .medium }) {
            return .reviewRequired
        }
        if items.isEmpty { return .empty }
        return .ready
    }

    private func nextActions(_ items: [ParentApprovalInboxItem]) -> [ParentApprovalInboxNextAction] {
        if items.isEmpty {
            return [
                ParentApprovalInboxNextAction(
                    publicActionRef: publicRef("pai-action", "read-only"),
                    kind: .readOnly,
                    priority: .low,
                    title: "当前视角只读查看审批收件箱。",
                    actionRequired: false
                )
            ]
        }
        return items.map { item in
            ParentApprovalInboxNextAction(
                publicActionRef: publicRef("pai-action", item.publicApprovalRef),
                kind: item.kind == .evidenceAppeal ? .resolveAppeal : (item.kind == .offlineConflict ? .resolveOfflineConflict : .reviewItem),
                priority: item.priority,
                title: item.title,
                actionRequired: true
            )
        }
    }

    private func publicSummary(
        viewerRole: ParentApprovalInboxViewerRole,
        status: ParentApprovalInboxStatus,
        items: [ParentApprovalInboxItem],
        findings: [ParentApprovalInboxFinding]
    ) -> ParentApprovalInboxPublicSummary {
        ParentApprovalInboxPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            visibleItemCount: items.count,
            growthProofCount: items.filter { $0.kind == .growthProof }.count,
            schoolHomeworkCount: items.filter { $0.kind == .schoolHomework }.count,
            relativeCommentCount: items.filter { $0.kind == .relativeComment }.count,
            evidenceAppealCount: items.filter { $0.kind == .evidenceAppeal }.count,
            creditSuggestionCount: items.filter { $0.kind == .creditSuggestion }.count,
            offlineConflictCount: items.filter { $0.kind == .offlineConflict }.count,
            findingCodes: findings.map(\.code)
        )
    }

    // MARK: - Safety

    private func hasUnsafeInput(
        growthPack: GrowthPackMobileDetailSnapshot,
        schoolCredit: SchoolGrowthCreditSnapshot,
        familyAchievement: FamilyAchievementSnapshotDashboard,
        creditSettlement: MobileCreditSettlementReport
    ) -> Bool {
        var values: [String] = []
        values.append(contentsOf: growthPack.tasks.map(\.title))
        values.append(contentsOf: growthPack.steps.flatMap { [$0.title, $0.reason, $0.nextStep] })
        values.append(contentsOf: schoolCredit.assignments.map(\.title))
        values.append(contentsOf: familyAchievement.riskFlags.map(\.title))
        values.append(contentsOf: creditSettlement.proposals.flatMap { [$0.reason, $0.scopeLabel] })
        return MobileSyncPayloadGuard.isUnsafe(values)
    }

    private func displayValues(_ snapshot: ParentApprovalInboxSnapshot) -> [String] {
        var values: [String] = [snapshot.generatedAt, snapshot.header.generatedAt]
        values.append(contentsOf: snapshot.items.flatMap { item in
            [
                item.publicApprovalRef,
                item.idempotencyPublicRef,
                item.title,
                item.childVisibleCopy,
                item.frozenOrBlockedReason ?? "",
                item.sourceBoundary.sourceKind.rawValue,
                item.sourceBoundary.sourceRole.rawValue
            ]
        })
        values.append(contentsOf: snapshot.nextActions.flatMap { [$0.publicActionRef, $0.title] })
        values.append(contentsOf: snapshot.findings.flatMap { [$0.publicRef, $0.message] })
        return values
    }

    private func safeFallback(
        viewerRole: ParentApprovalInboxViewerRole,
        visibility: ParentApprovalInboxVisibility
    ) -> ParentApprovalInboxSnapshot {
        let fallback = finding(
            .publicSummaryLeak,
            .blocker,
            "家长审批收件箱未通过公开脱敏检查，已进入安全降级模式。",
            "fallback"
        )
        let header = ParentApprovalInboxHeader(
            viewerRole: viewerRole,
            status: .blocked,
            generatedAt: generatedAt
        )
        let emptyItems: [ParentApprovalInboxItem] = []
        let emptyFindings = [fallback]
        return ParentApprovalInboxSnapshot(
            generatedAt: generatedAt,
            header: header,
            visibility: visibility,
            items: emptyItems,
            nextActions: [],
            batchSummary: batchSummary(emptyItems),
            findings: emptyFindings,
            publicSummary: publicSummary(viewerRole: viewerRole, status: .blocked, items: emptyItems, findings: emptyFindings)
        )
    }

    // MARK: - Helpers

    private func boundary(
        _ sourceRole: ParentApprovalInboxSourceRole,
        _ sourceKind: ParentApprovalInboxSourceKind,
        childCanSeeCopy: Bool
    ) -> ParentApprovalInboxSourceBoundary {
        ParentApprovalInboxSourceBoundary(
            sourceRole: sourceRole,
            sourceKind: sourceKind,
            childCanSeeCopy: childCanSeeCopy
        )
    }

    private func item(
        kind: ParentApprovalInboxItemKind,
        priority: ParentApprovalInboxPriority,
        title: String,
        childVisibleCopy: String,
        boundary: ParentApprovalInboxSourceBoundary,
        seed: String,
        frozenOrBlockedReason: String? = nil
    ) -> ParentApprovalInboxItem {
        ParentApprovalInboxItem(
            publicApprovalRef: publicRef("pai-inbox", "\(kind.rawValue)-\(seed)"),
            kind: kind,
            priority: priority,
            title: title,
            childVisibleCopy: childVisibleCopy,
            actionRequired: true,
            frozenOrBlockedReason: frozenOrBlockedReason,
            sourceBoundary: boundary,
            idempotencyPublicRef: publicRef("pai-idem", "\(kind.rawValue)-\(seed)")
        )
    }

    private func finding(
        _ code: ParentApprovalInboxFindingCode,
        _ severity: ParentApprovalInboxSeverity,
        _ message: String,
        _ seed: String
    ) -> ParentApprovalInboxFinding {
        ParentApprovalInboxFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("pai-finding", "\(code.rawValue)-\(seed)")
        )
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        Self.stablePublicRef(prefix: prefix, source: source, salt: redactionSalt)
    }

    static func stablePublicRef(prefix: String, source: String, salt: String = "parent-approval-inbox-ios-v1") -> String {
        var hash: UInt32 = 5381
        for scalar in "\(salt):\(source)".unicodeScalars {
            hash = (hash &* 33) ^ UInt32(scalar.value)
        }
        let body = String(hash, radix: 36)
        let padded = body.count >= 7 ? body : String(repeating: "0", count: 7 - body.count) + body
        return "\(prefix)-\(padded)"
    }
}
