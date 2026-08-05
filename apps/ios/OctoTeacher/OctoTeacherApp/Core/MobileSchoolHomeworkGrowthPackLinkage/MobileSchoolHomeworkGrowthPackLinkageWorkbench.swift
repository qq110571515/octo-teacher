import Foundation

/// 学校作业与成长包任务联动工作台的纯本地只读投影。
///
/// 它把 `SchoolFamilyStore`、`GrowthPackRuntimeStore` 和 `SchoolGrowthCreditSnapshot`
/// 组合成手机端可看的联动视图：孩子看下一步，家长看老师/家长验证与成长积分建议边界，
/// 老师只看教学验证状态。它不提交作业、不验证老师/家长、不写学校系统、不发成长积分、
/// 不解锁设备、不调用 AI 或网络。
enum MobileSchoolHomeworkGrowthPackLinkageViewerRole: String, CaseIterable, Equatable {
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

    var audienceNote: String {
        switch self {
        case .child:
            return "只看作业目标、成长包关联和下一步；不会显示分值、成人原因或最终解析。"
        case .guardian:
            return "只读查看老师验证、家长确认、退回申诉和成长积分建议边界；真正确认仍在正式流程完成。"
        case .teacher:
            return "只看教学验证状态和作业进度；不会展示家庭奖励预算、设备控制或家长内部原因。"
        }
    }

    var schoolCreditRole: SchoolGrowthCreditViewerRole {
        switch self {
        case .child: return .child
        case .guardian: return .guardian
        case .teacher: return .teacher
        }
    }
}

enum MobileSchoolHomeworkGrowthPackLinkageStatus: String, Equatable {
    case waitingChild = "waiting_child"
    case waitingTeacher = "waiting_teacher"
    case waitingGuardian = "waiting_guardian"
    case suggestedBoundary = "suggested_boundary"
    case returned
    case blocked

    var label: String {
        switch self {
        case .waitingChild: return "等孩子完成"
        case .waitingTeacher: return "等老师验证"
        case .waitingGuardian: return "等家长确认"
        case .suggestedBoundary: return "可进入建议边界"
        case .returned: return "已退回"
        case .blocked: return "已阻断"
        }
    }

    var systemImage: String {
        switch self {
        case .waitingChild: return "pencil.and.outline"
        case .waitingTeacher: return "graduationcap"
        case .waitingGuardian: return "person.badge.shield.checkmark"
        case .suggestedBoundary: return "checkmark.seal"
        case .returned: return "arrow.uturn.backward"
        case .blocked: return "lock.shield"
        }
    }
}

enum MobileSchoolHomeworkGrowthPackFindingCode: String, Equatable {
    case readOnlyReady = "READ_ONLY_READY"
    case returnedBlocksCredit = "RETURNED_BLOCKS_CREDIT"
    case teacherCreditHidden = "TEACHER_CREDIT_HIDDEN"
    case childAdultReasonHidden = "CHILD_ADULT_REASON_HIDDEN"
    case guardianConfirmationRequired = "GUARDIAN_CONFIRMATION_REQUIRED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

struct MobileSchoolHomeworkGrowthPackLinkageItem: Identifiable, Equatable {
    var publicLinkRef: String
    var title: String
    var subjectLabel: String
    var dueLabel: String
    var homeworkStatusLabel: String
    var growthPackStatusLabel: String
    var verificationLabel: String
    var creditBoundaryLabel: String
    var proofLabel: String
    var nextStep: String
    var status: MobileSchoolHomeworkGrowthPackLinkageStatus
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToTeacher: Bool
    var canSuggestCreditToGuardian: Bool
    var teacherVerificationRequired: Bool
    var guardianConfirmationRequired: Bool
    var returnedOrBlocked: Bool

    let submitsHomework = false
    let verifiesTeacher = false
    let confirmsGuardian = false
    let writesSchoolSystem = false
    let callsLms = false
    let callsAIProvider = false
    let callsNetwork = false
    let uploadsAttachment = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false

    var id: String { publicLinkRef }

    var displayValues: [String] {
        [
            publicLinkRef,
            title,
            subjectLabel,
            dueLabel,
            homeworkStatusLabel,
            growthPackStatusLabel,
            verificationLabel,
            creditBoundaryLabel,
            proofLabel,
            nextStep,
            status.rawValue,
            status.label
        ]
    }
}

struct MobileSchoolHomeworkGrowthPackFinding: Identifiable, Equatable {
    var code: MobileSchoolHomeworkGrowthPackFindingCode
    var message: String
    var visibleToChild: Bool

    var id: String { code.rawValue }
}

struct MobileSchoolHomeworkGrowthPackPublicSummary: Equatable {
    var role: MobileSchoolHomeworkGrowthPackLinkageViewerRole
    var linkedHomeworkCount: Int
    var waitingTeacherCount: Int
    var waitingGuardianCount: Int
    var returnedOrBlockedCount: Int
    var guardianCreditSuggestionCount: Int
    var teacherVisibleCreditDetailCount: Int
    var childVisibleAdultReasonCount: Int
    var findingCodes: [MobileSchoolHomeworkGrowthPackFindingCode]

    let submitsHomework = false
    let verifiesTeacher = false
    let confirmsGuardian = false
    let writesSchoolSystem = false
    let callsLms = false
    let callsAIProvider = false
    let callsNetwork = false
    let uploadsAttachment = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false

    var hasTriggeredSideEffect: Bool {
        submitsHomework || verifiesTeacher || confirmsGuardian || writesSchoolSystem
            || callsLms || callsAIProvider || callsNetwork || uploadsAttachment
            || writesLedger || grantsCredit || unlocksDevice || sendsNotification
    }
}

struct MobileSchoolHomeworkGrowthPackLinkageWorkbench: Equatable {
    var role: MobileSchoolHomeworkGrowthPackLinkageViewerRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var items: [MobileSchoolHomeworkGrowthPackLinkageItem]
    var findings: [MobileSchoolHomeworkGrowthPackFinding]
    var publicSummary: MobileSchoolHomeworkGrowthPackPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + items.flatMap(\.displayValues)
            + findings.flatMap { [$0.code.rawValue, $0.message] }
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileSchoolHomeworkGrowthPackLinkageBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileSchoolHomeworkGrowthPackLinkageBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "homework:",
        "task:", "pack:", "proof:", "ledger:", "device:", "session:",
        "provider:", "model:", "transcript", "answerkey", "answer key",
        "baseurl", "api_key", "apikey", "token", "secret", "qwen", "openai",
        "http://", "https://", "file://", "/users/", "/volumes/", "192.168."
    ]

    func build(
        role: MobileSchoolHomeworkGrowthPackLinkageViewerRole,
        homeworks: [SchoolHomework],
        runtimeReport: GrowthRuntimeSettlementReport = .empty,
        schoolCredit: SchoolGrowthCreditSnapshot? = nil
    ) -> MobileSchoolHomeworkGrowthPackLinkageWorkbench {
        if Self.hasUnsafeInput(homeworks: homeworks, runtimeReport: runtimeReport) {
            return safeFallback(role: role)
        }

        let credit = schoolCredit ?? SchoolGrowthCreditSnapshotBuilder().build(
            viewerRole: role.schoolCreditRole,
            homeworks: homeworks,
            runtimeReport: runtimeReport
        )
        let schoolSteps = runtimeReport.steps.filter { $0.kind == .schoolHomework }
        let previewByHomeworkIndex = previewMap(homeworks: homeworks, previews: credit.creditPreviews)
        let items = homeworks.enumerated().map { index, homework in
            item(
                role: role,
                homework: homework,
                order: index,
                assignment: credit.assignments[safe: index],
                preview: role == .guardian ? previewByHomeworkIndex[index] : nil,
                growthStep: schoolSteps[safe: index]
            )
        }
        let findings = findings(role: role, items: items)
        let summary = MobileSchoolHomeworkGrowthPackPublicSummary(
            role: role,
            linkedHomeworkCount: items.count,
            waitingTeacherCount: items.filter { $0.teacherVerificationRequired }.count,
            waitingGuardianCount: items.filter { $0.guardianConfirmationRequired }.count,
            returnedOrBlockedCount: items.filter { $0.returnedOrBlocked }.count,
            guardianCreditSuggestionCount: role == .guardian
                ? items.filter { $0.canSuggestCreditToGuardian }.count
                : 0,
            teacherVisibleCreditDetailCount: role == .teacher
                ? items.filter { $0.canSuggestCreditToGuardian }.count
                : 0,
            childVisibleAdultReasonCount: role == .child
                ? items.filter { $0.verificationLabel.localizedCaseInsensitiveContains("原因") }.count
                : 0,
            findingCodes: findings.map { $0.code }
        )
        let workbench = MobileSchoolHomeworkGrowthPackLinkageWorkbench(
            role: role,
            title: "学校作业成长包联动",
            subtitle: "\(items.count) 份作业 · \(runtimeReport.isEmpty ? "成长包待同步" : runtimeReport.packTitle)",
            audienceNote: role.audienceNote,
            items: items.filter { isVisible($0, to: role) },
            findings: findings.filter { role != .child || $0.visibleToChild },
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? safeFallback(role: role) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private static func hasUnsafeInput(
        homeworks: [SchoolHomework],
        runtimeReport: GrowthRuntimeSettlementReport
    ) -> Bool {
        let values = homeworks.flatMap {
            [
                $0.title,
                $0.instructions,
                $0.dueLabel,
                $0.proof.text,
                $0.proof.photoPlaceholderName ?? "",
                $0.guidance.nextStep
            ] + $0.guidance.hints + $0.guidance.checklist
        } + [
            runtimeReport.packTitle,
            runtimeReport.packSummary
        ] + runtimeReport.steps.flatMap {
            [$0.title, $0.reason, $0.nextStep, $0.proofRequirementLabel, $0.settlement.scopeLabel]
        }
        return hasUnsafeDisplayPayload(values)
    }

    private func previewMap(
        homeworks: [SchoolHomework],
        previews: [SchoolGrowthCreditPreview]
    ) -> [Int: SchoolGrowthCreditPreview] {
        var cursor = 0
        var result: [Int: SchoolGrowthCreditPreview] = [:]
        for (index, homework) in homeworks.enumerated() {
            guard homework.status != .assigned && homework.status != .inProgress else { continue }
            if let preview = previews[safe: cursor] {
                result[index] = preview
            }
            cursor += 1
        }
        return result
    }

    private func item(
        role: MobileSchoolHomeworkGrowthPackLinkageViewerRole,
        homework: SchoolHomework,
        order: Int,
        assignment: SchoolGrowthCreditAssignmentSnapshot?,
        preview: SchoolGrowthCreditPreview?,
        growthStep: GrowthRuntimeStepProjection?
    ) -> MobileSchoolHomeworkGrowthPackLinkageItem {
        let status = linkageStatus(homework: homework, preview: preview, growthStep: growthStep)
        return MobileSchoolHomeworkGrowthPackLinkageItem(
            publicLinkRef: publicRef("shgp", "\(homework.id.uuidString):\(order)"),
            title: homework.title,
            subjectLabel: homework.subject.label,
            dueLabel: homework.dueLabel,
            homeworkStatusLabel: homework.status.label,
            growthPackStatusLabel: growthPackLabel(for: growthStep),
            verificationLabel: verificationLabel(for: homework, role: role, assignment: assignment),
            creditBoundaryLabel: creditBoundaryLabel(for: role, homework: homework, preview: preview),
            proofLabel: proofLabel(for: homework),
            nextStep: nextStep(for: role, homework: homework, status: status),
            status: status,
            visibleToChild: true,
            visibleToGuardian: true,
            visibleToTeacher: true,
            canSuggestCreditToGuardian: role == .guardian && preview?.state == .availablePreview,
            teacherVerificationRequired: homework.status == .submitted,
            guardianConfirmationRequired: role == .guardian && homework.status == .verified,
            returnedOrBlocked: homework.status == .returned || preview?.state == .blocked || growthStep?.status == .blocked
        )
    }

    private func linkageStatus(
        homework: SchoolHomework,
        preview: SchoolGrowthCreditPreview?,
        growthStep: GrowthRuntimeStepProjection?
    ) -> MobileSchoolHomeworkGrowthPackLinkageStatus {
        if homework.status == .returned || preview?.state == .blocked || growthStep?.status == .blocked {
            return .returned
        }
        switch homework.status {
        case .assigned, .inProgress:
            return .waitingChild
        case .submitted:
            return .waitingTeacher
        case .verified:
            if preview?.state == .availablePreview { return .suggestedBoundary }
            return .waitingGuardian
        case .returned:
            return .returned
        }
    }

    private func growthPackLabel(for step: GrowthRuntimeStepProjection?) -> String {
        guard let step else { return "待挂入成长包计划" }
        return "\(step.kind.label) · \(step.status.label)"
    }

    private func verificationLabel(
        for homework: SchoolHomework,
        role: MobileSchoolHomeworkGrowthPackLinkageViewerRole,
        assignment: SchoolGrowthCreditAssignmentSnapshot?
    ) -> String {
        switch role {
        case .child:
            switch homework.status {
            case .assigned, .inProgress: return "先完成作业，再等待老师或家长确认。"
            case .submitted: return "已经提交，等待老师或家长确认。"
            case .verified: return "已经被确认，等待家长完成后续流程。"
            case .returned: return "需要重新完成后再提交。"
            }
        case .guardian:
            return assignment?.status.label ?? "等待家长查看联动状态"
        case .teacher:
            switch homework.status {
            case .assigned, .inProgress: return "学生尚未提交，老师只读等待。"
            case .submitted: return "等待教学验证，本页不执行通过或退回。"
            case .verified: return "教学验证已完成，家庭后续不可见。"
            case .returned: return "作业已退回，等待学生重新提交。"
            }
        }
    }

    private func creditBoundaryLabel(
        for role: MobileSchoolHomeworkGrowthPackLinkageViewerRole,
        homework: SchoolHomework,
        preview: SchoolGrowthCreditPreview?
    ) -> String {
        switch role {
        case .child:
            return "完成后只进入等待确认，不显示分值。"
        case .teacher:
            return "老师视角不展示家庭奖励细节。"
        case .guardian:
            guard homework.status != .returned else {
                return "退回作业不能进入成长积分建议。"
            }
            guard let preview else {
                return "没有可展示的成长积分建议，本页仍然只读。"
            }
            switch preview.state {
            case .availablePreview:
                return "可作为家长确认后的成长积分建议，不写账本。"
            case .reviewRequired:
                return "仍需老师/家长复核，不能展示为可用。"
            case .frozen:
                return "申诉或冻结期间不能展示为可用。"
            case .blocked:
                return "安全边界阻断，不能进入建议。"
            case .duplicate:
                return "重复建议已忽略，不重复结算。"
            case .alreadyCredited:
                return "过去已结算，不重复建议。"
            case .voided:
                return "结算投影已作废。"
            }
        }
    }

    private func proofLabel(for homework: SchoolHomework) -> String {
        switch homework.requiredProof {
        case .text:
            return homework.proof.hasContent ? "文字证明已记录" : "需要文字证明"
        case .photoPlaceholder, .photo:
            return homework.proof.hasContent ? "照片证明已记录" : "需要照片证明"
        }
    }

    private func nextStep(
        for role: MobileSchoolHomeworkGrowthPackLinkageViewerRole,
        homework: SchoolHomework,
        status: MobileSchoolHomeworkGrowthPackLinkageStatus
    ) -> String {
        switch role {
        case .child:
            switch status {
            case .waitingChild:
                return homework.guidance.nextStep.isEmpty ? "完成作业后提交脱敏证明。" : homework.guidance.nextStep
            case .waitingTeacher, .waitingGuardian:
                return "已经交上去啦，接下来等老师或家长确认。"
            case .suggestedBoundary:
                return "作业已确认，继续完成下一个成长包步骤。"
            case .returned, .blocked:
                return "按提示重新完成，再请老师或家长确认。"
            }
        case .guardian:
            switch status {
            case .waitingChild: return "提醒孩子完成作业；本页不催发通知。"
            case .waitingTeacher: return "等待老师验证后再考虑家长确认。"
            case .waitingGuardian, .suggestedBoundary: return "可进入联合审批台复核；本页不执行确认。"
            case .returned, .blocked: return "退回或阻断状态下不进入成长积分建议。"
            }
        case .teacher:
            switch status {
            case .waitingChild: return "等待学生提交。"
            case .waitingTeacher: return "在学校流程里完成验证，本页只读。"
            case .waitingGuardian, .suggestedBoundary: return "教学验证已结束，家庭后续由家长处理。"
            case .returned, .blocked: return "等待学生重新提交后再验证。"
            }
        }
    }

    private func findings(
        role: MobileSchoolHomeworkGrowthPackLinkageViewerRole,
        items: [MobileSchoolHomeworkGrowthPackLinkageItem]
    ) -> [MobileSchoolHomeworkGrowthPackFinding] {
        var result: [MobileSchoolHomeworkGrowthPackFinding] = []
        if items.contains(where: \.returnedOrBlocked) {
            result.append(.init(
                code: .returnedBlocksCredit,
                message: role == .child ? "退回的作业需要重新完成。" : "退回或阻断的作业不能进入成长积分建议。",
                visibleToChild: true
            ))
        }
        if role == .teacher {
            result.append(.init(
                code: .teacherCreditHidden,
                message: "老师视角已隐藏家庭奖励与设备控制信息。",
                visibleToChild: false
            ))
        }
        if role == .child {
            result.append(.init(
                code: .childAdultReasonHidden,
                message: "孩子视角已隐藏成人内部原因和分值细节。",
                visibleToChild: true
            ))
        }
        if role == .guardian && items.contains(where: \.guardianConfirmationRequired) {
            result.append(.init(
                code: .guardianConfirmationRequired,
                message: "已验证作业仍需家长在正式流程中确认。",
                visibleToChild: false
            ))
        }
        result.append(.init(
            code: .readOnlyReady,
            message: "联动工作台只读、脱敏且无外部副作用。",
            visibleToChild: true
        ))
        return result
    }

    private func isVisible(
        _ item: MobileSchoolHomeworkGrowthPackLinkageItem,
        to role: MobileSchoolHomeworkGrowthPackLinkageViewerRole
    ) -> Bool {
        switch role {
        case .child: return item.visibleToChild
        case .guardian: return item.visibleToGuardian
        case .teacher: return item.visibleToTeacher
        }
    }

    private func safeFallback(
        role: MobileSchoolHomeworkGrowthPackLinkageViewerRole
    ) -> MobileSchoolHomeworkGrowthPackLinkageWorkbench {
        let finding = MobileSchoolHomeworkGrowthPackFinding(
            code: .unsafePayloadBlocked,
            message: "联动数据命中安全保护，已隐藏原文。",
            visibleToChild: role == .child
        )
        return MobileSchoolHomeworkGrowthPackLinkageWorkbench(
            role: role,
            title: "学校作业成长包联动已保护",
            subtitle: "本地安全壳",
            audienceNote: role.audienceNote,
            items: [],
            findings: [finding],
            publicSummary: MobileSchoolHomeworkGrowthPackPublicSummary(
                role: role,
                linkedHomeworkCount: 0,
                waitingTeacherCount: 0,
                waitingGuardianCount: 0,
                returnedOrBlockedCount: 0,
                guardianCreditSuggestionCount: 0,
                teacherVisibleCreditDetailCount: 0,
                childVisibleAdultReasonCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func publicRef(_ prefix: String, _ seed: String) -> String {
        "\(prefix)-\(Self.stableHash("school-homework-growth-pack-linkage:\(seed)"))"
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
