import Foundation

enum MobileFamilySchoolNotificationDigestViewerRole: String, CaseIterable, Equatable {
    case guardian
    case child
    case teacher
    case relative

    var label: String {
        switch self {
        case .guardian: return "家长"
        case .child: return "孩子"
        case .teacher: return "老师"
        case .relative: return "亲友"
        }
    }
}

enum MobileFamilySchoolNotificationDigestStatus: String, Equatable {
    case ready
    case reviewRequired = "review_required"
    case blocked
    case empty

    var label: String {
        switch self {
        case .ready: return "可查看"
        case .reviewRequired: return "需复核"
        case .blocked: return "已阻断"
        case .empty: return "暂无摘要"
        }
    }
}

enum MobileFamilySchoolNotificationDigestCardKind: String, Equatable, CaseIterable {
    case guardianReview = "guardian_review"
    case guardianRewardPending = "guardian_reward_pending"
    case childHomework = "child_homework"
    case teacherSchool = "teacher_school"
    case relativeFamily = "relative_family"
    case quietWindow = "quiet_window"
    case eventEvidence = "event_evidence"

    var title: String {
        switch self {
        case .guardianReview: return "家长复核摘要"
        case .guardianRewardPending: return "奖励待处理提醒"
        case .childHomework: return "孩子作业提醒"
        case .teacherSchool: return "老师学校摘要"
        case .relativeFamily: return "亲友家庭摘要"
        case .quietWindow: return "安静窗口"
        case .eventEvidence: return "事件证据"
        }
    }
}

enum MobileFamilySchoolNotificationDigestCardState: String, Equatable {
    case deliverable
    case suppressed
    case needsReview = "needs_review"

    var label: String {
        switch self {
        case .deliverable: return "可展示"
        case .suppressed: return "已抑制"
        case .needsReview: return "需复核"
        }
    }
}

enum MobileFamilySchoolNotificationDigestSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

enum MobileFamilySchoolNotificationDigestFindingCode: String, Equatable {
    case digestReady = "FAMILY_SCHOOL_DIGEST_CENTER_OK"
    case guardianConsentRequired = "GUARDIAN_CONSENT_REQUIRED"
    case childWithdrawn = "CHILD_WITHDRAWN_OR_ASSENT_INACTIVE"
    case teacherRosterExpired = "TEACHER_ROSTER_EXPIRED"
    case rolePrivateDetailHidden = "ROLE_PRIVATE_DETAIL_HIDDEN"
    case relativePrivateDetailBlocked = "RELATIVE_PRIVATE_DETAIL_BLOCKED"
    case urgentQuietOverrideBlocked = "URGENT_QUIET_OVERRIDE_BLOCKED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
    case sideEffectFree = "SIDE_EFFECT_FREE"

    var label: String {
        switch self {
        case .digestReady: return "摘要可查看"
        case .guardianConsentRequired: return "缺家长同意"
        case .childWithdrawn: return "孩子撤回/assent 失效"
        case .teacherRosterExpired: return "老师名册过期"
        case .rolePrivateDetailHidden: return "角色私密已隐藏"
        case .relativePrivateDetailBlocked: return "亲友私密阻断"
        case .urgentQuietOverrideBlocked: return "安静窗口阻断"
        case .publicSummaryLeak: return "公开摘要泄漏"
        case .unsafePayloadBlocked: return "不安全负载阻断"
        case .sideEffectFree: return "无副作用"
        }
    }
}

struct MobileFamilySchoolNotificationDigestScenario: Equatable {
    var guardianConsentGranted: Bool = true
    var childAssentActive: Bool = true
    var childWithdrawn: Bool = false
    var relativeConsentGranted: Bool = true
    var teacherRosterActive: Bool = true
    var urgentQuietOverrideAllowed: Bool = true
    var containsAnswerKey: Bool = false
    var containsRawTranscript: Bool = false
    var containsAdultInternalReason: Bool = false
    var containsGuardianConsentDetail: Bool = false
    var containsChildConsentDetail: Bool = false
    var containsCreditAmount: Bool = false
    var containsBudget: Bool = false
    var containsRawProof: Bool = false
    var containsCrossChildContent: Bool = false
    var unsafePayload: String?

    static let safe = MobileFamilySchoolNotificationDigestScenario()
}

struct MobileFamilySchoolNotificationDigestBoundary: Equatable {
    var guardianConsentGranted: Bool
    var childAssentActive: Bool
    var childWithdrawn: Bool
    var relativeConsentGranted: Bool
    var teacherRosterActive: Bool
    var urgentQuietOverrideAllowed: Bool

    let sendsNotification = false
    let writesQueue = false
}

struct MobileFamilySchoolNotificationDigestCard: Identifiable, Equatable {
    var publicCardRef: String
    var kind: MobileFamilySchoolNotificationDigestCardKind
    var title: String
    var detail: String
    var state: MobileFamilySchoolNotificationDigestCardState
    var visibleToGuardian: Bool
    var visibleToChild: Bool
    var visibleToTeacher: Bool
    var visibleToRelative: Bool

    let sendsNotification = false
    let writesQueue = false
    let writesSchoolSystem = false
    let callsLms = false
    let callsAiProvider = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let showsAnswerKey = false
    let showsRawTranscript = false
    let showsAdultInternalReason = false
    let showsGuardianConsentDetail = false
    let showsCreditAmount = false
    let showsRawProof = false
    let showsCrossChildContent = false

    var id: String { publicCardRef }
}

struct MobileFamilySchoolNotificationDigestFinding: Identifiable, Equatable {
    var code: MobileFamilySchoolNotificationDigestFindingCode
    var severity: MobileFamilySchoolNotificationDigestSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct MobileFamilySchoolNotificationDigestPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: MobileFamilySchoolNotificationDigestViewerRole
    var status: MobileFamilySchoolNotificationDigestStatus
    var visibleCardCount: Int
    var suppressedCardCount: Int
    var reviewCardCount: Int
    var findingCodes: [MobileFamilySchoolNotificationDigestFindingCode]

    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let sendsNotification = false
    let writesQueue = false
    let writesDatabase = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let storesRawTranscript = false
}

struct MobileFamilySchoolNotificationDigestSideEffects: Equatable {
    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let sendsNotification = false
    let writesQueue = false
    let writesDatabase = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let storesRawTranscript = false

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || sendsNotification || writesQueue || writesDatabase || writesLedger || grantsCredit
            || unlocksDevice || storesRawTranscript
    }
}

struct MobileFamilySchoolNotificationDigestSnapshot: Equatable {
    var generatedAt: String
    var viewerRole: MobileFamilySchoolNotificationDigestViewerRole
    var status: MobileFamilySchoolNotificationDigestStatus
    var headline: String
    var boundary: MobileFamilySchoolNotificationDigestBoundary
    var cards: [MobileFamilySchoolNotificationDigestCard]
    var findings: [MobileFamilySchoolNotificationDigestFinding]
    var publicSummary: MobileFamilySchoolNotificationDigestPublicSummary
    var sideEffects: MobileFamilySchoolNotificationDigestSideEffects
}

struct MobileFamilySchoolNotificationDigestCenterBuilder {
    var generatedAt: String = "2026-06-24T12:00:00Z"
    var redactionSalt: String = "mobile-family-school-notification-digest-ios-v1"

    private let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "relative:",
        "homework:", "session:", "review:", "transcript:", "provider:", "model:",
        "ledger:", "taskid", "claimid", "baseurl", "token", "secret", "答案键",
        "answerkey", "transcript_private", "http://", "https://", "192.168.",
        "/users/", "/volumes/", "c:\\"
    ]

    func build(
        viewerRole: MobileFamilySchoolNotificationDigestViewerRole,
        family: LocalFamilyStore = LocalFamilyStore(),
        schoolFamily: SchoolFamilyStore = SchoolFamilyStore(),
        scenario: MobileFamilySchoolNotificationDigestScenario = .safe
    ) -> MobileFamilySchoolNotificationDigestSnapshot {
        if hasUnsafePayload(scenario.unsafePayload) {
            return blockedSnapshot(viewerRole: viewerRole, code: .unsafePayloadBlocked)
        }

        let boundary = MobileFamilySchoolNotificationDigestBoundary(
            guardianConsentGranted: scenario.guardianConsentGranted,
            childAssentActive: scenario.childAssentActive,
            childWithdrawn: scenario.childWithdrawn,
            relativeConsentGranted: scenario.relativeConsentGranted,
            teacherRosterActive: scenario.teacherRosterActive,
            urgentQuietOverrideAllowed: scenario.urgentQuietOverrideAllowed
        )
        let allCards = cards(family: family, schoolFamily: schoolFamily, scenario: scenario)
        let visibleCards = allCards.filter { isVisible($0, to: viewerRole) }
        let findings = findings(viewerRole: viewerRole, scenario: scenario, cards: visibleCards)
        let status = status(cards: visibleCards, findings: findings)
        let snapshot = MobileFamilySchoolNotificationDigestSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            headline: headline(status: status, role: viewerRole, cards: visibleCards),
            boundary: boundary,
            cards: visibleCards,
            findings: findings,
            publicSummary: publicSummary(role: viewerRole, status: status, cards: visibleCards, findings: findings),
            sideEffects: MobileFamilySchoolNotificationDigestSideEffects()
        )
        return redacts(snapshot) ? snapshot : blockedSnapshot(viewerRole: viewerRole, code: .publicSummaryLeak)
    }

    func redacts(_ snapshot: MobileFamilySchoolNotificationDigestSnapshot) -> Bool {
        let text = displayValues(snapshot).joined(separator: " ").lowercased()
        return !sensitiveMarkers.contains { text.contains($0) }
    }

    private func cards(
        family: LocalFamilyStore,
        schoolFamily: SchoolFamilyStore,
        scenario: MobileFamilySchoolNotificationDigestScenario
    ) -> [MobileFamilySchoolNotificationDigestCard] {
        let submitted = family.assignments.filter { $0.status == .submitted }.count
        let openHomework = schoolFamily.openHomeworks.count
        let pendingComments = schoolFamily.relativeComments.filter { $0.status == .pending }.count
        let honor = schoolFamily.honorWall.filter { $0.approval == .approved }.count
        // 与 RewardPathwayBuilder 同口径：当前活跃孩子的待定价愿望、待兑现愿望、待确认零花钱。
        // 摘要里只放计数和去处，不带愿望标题等具体内容。
        let activeChildId = family.activeChildId
        let activeChildWishes = family.wishes.filter { $0.childId == activeChildId && $0.status != .rejected }
        let rewardPending = RewardPathwayPendingBreakdown(
            pricingWishCount: activeChildWishes.filter { $0.status == .proposed }.count,
            fulfillmentWishCount: activeChildWishes.filter { $0.status == .redeemed }.count,
            pocketMoneyConfirmCount: family.moneyLedger.filter {
                $0.childId == activeChildId && $0.status == .awaitingApproval
            }.count
        )

        return [
            card(
                .guardianReview,
                detail: "有 \(submitted + pendingComments) 条家庭或亲友事项需要家长复核。",
                state: submitted + pendingComments > 0 ? .needsReview : .deliverable,
                visible: [.guardian]
            ),
            card(
                .guardianRewardPending,
                detail: rewardPending.total > 0
                    ? "有 \(rewardPending.total) 个奖励项等家长处理：待定价 \(rewardPending.pricingWishCount) · 待兑现 \(rewardPending.fulfillmentWishCount) · 零花钱确认 \(rewardPending.pocketMoneyConfirmCount)，请到零花钱工作台处理。"
                    : "暂无奖励项等家长处理。",
                state: rewardPending.total > 0 ? .needsReview : .deliverable,
                visible: [.guardian]
            ),
            card(
                .childHomework,
                detail: scenario.containsAnswerKey || scenario.containsRawTranscript || scenario.containsAdultInternalReason
                    ? "作业提醒已改为安全提示，隐藏答案、原始对话和成人原因。"
                    : "有 \(openHomework) 份作业提醒，只展示下一步提示。",
                state: scenario.childWithdrawn || !scenario.childAssentActive ? .suppressed : .deliverable,
                visible: [.child, .guardian]
            ),
            card(
                .teacherSchool,
                detail: scenario.containsGuardianConsentDetail || scenario.containsChildConsentDetail
                    ? "老师摘要已隐藏家庭同意细节。"
                    : "老师只看学校相关摘要和待复核状态。",
                state: scenario.teacherRosterActive ? .deliverable : .suppressed,
                visible: [.teacher, .guardian]
            ),
            card(
                .relativeFamily,
                detail: scenario.containsCreditAmount || scenario.containsBudget || scenario.containsRawProof || scenario.containsCrossChildContent
                    ? "亲友摘要已隐藏成长积分、预算、原始证明和跨孩子内容。"
                    : "亲友可看 \(honor) 条家长开放的荣誉和成长摘要。",
                state: scenario.guardianConsentGranted && scenario.relativeConsentGranted ? .deliverable : .suppressed,
                visible: [.relative, .guardian]
            ),
            card(
                .quietWindow,
                detail: scenario.urgentQuietOverrideAllowed ? "紧急摘要可在允许覆盖时显示。" : "安静窗口不允许紧急覆盖，摘要保持抑制。",
                state: scenario.urgentQuietOverrideAllowed ? .deliverable : .suppressed,
                visible: [.guardian, .child, .teacher, .relative]
            ),
            card(
                .eventEvidence,
                detail: "同意、抑制、去重、送达和脱敏证据只做本地只读展示。",
                state: .deliverable,
                visible: [.guardian, .teacher]
            )
        ]
    }

    private func findings(
        viewerRole: MobileFamilySchoolNotificationDigestViewerRole,
        scenario: MobileFamilySchoolNotificationDigestScenario,
        cards: [MobileFamilySchoolNotificationDigestCard]
    ) -> [MobileFamilySchoolNotificationDigestFinding] {
        var result: [MobileFamilySchoolNotificationDigestFinding] = [
            finding(.digestReady, .ok, "\(viewerRole.label)视角通知摘要已按本地边界生成。")
        ]
        if !scenario.guardianConsentGranted || !scenario.relativeConsentGranted {
            result.append(finding(.guardianConsentRequired, .blocker, "亲友摘要缺少家长或亲友许可，已抑制。"))
        }
        if scenario.childWithdrawn || !scenario.childAssentActive {
            result.append(finding(.childWithdrawn, .blocker, "孩子撤回或 assent 失效后，孩子、老师和亲友摘要不可继续送达。"))
        }
        if !scenario.teacherRosterActive {
            result.append(finding(.teacherRosterExpired, .blocker, "老师名册或授权过期，学校摘要已阻断。"))
        }
        if scenario.containsAnswerKey || scenario.containsRawTranscript || scenario.containsAdultInternalReason
            || scenario.containsGuardianConsentDetail || scenario.containsChildConsentDetail {
            result.append(finding(.rolePrivateDetailHidden, .warning, "答案、原始对话、成人原因或同意细节已从当前摘要隐藏。"))
        }
        if scenario.containsCreditAmount || scenario.containsBudget || scenario.containsRawProof || scenario.containsCrossChildContent {
            result.append(finding(.relativePrivateDetailBlocked, .blocker, "亲友摘要不能展示成长积分、预算、原始证明或跨孩子内容。"))
        }
        if !scenario.urgentQuietOverrideAllowed {
            result.append(finding(.urgentQuietOverrideBlocked, .warning, "当前安静窗口不允许紧急覆盖，通知摘要保持抑制。"))
        }
        if cards.allSatisfy({ $0.state == .deliverable }) {
            result.append(finding(.sideEffectFree, .info, "所有摘要只读展示，不发送通知、不写队列。"))
        }
        return result
    }

    private func status(
        cards: [MobileFamilySchoolNotificationDigestCard],
        findings: [MobileFamilySchoolNotificationDigestFinding]
    ) -> MobileFamilySchoolNotificationDigestStatus {
        if cards.isEmpty { return .empty }
        if findings.contains(where: { $0.severity == .blocker }) { return .blocked }
        if cards.contains(where: { $0.state != .deliverable }) || findings.contains(where: { $0.severity == .warning }) {
            return .reviewRequired
        }
        return .ready
    }

    private func card(
        _ kind: MobileFamilySchoolNotificationDigestCardKind,
        detail: String,
        state: MobileFamilySchoolNotificationDigestCardState,
        visible: Set<MobileFamilySchoolNotificationDigestViewerRole>
    ) -> MobileFamilySchoolNotificationDigestCard {
        MobileFamilySchoolNotificationDigestCard(
            publicCardRef: publicRef("card:\(kind.rawValue)"),
            kind: kind,
            title: kind.title,
            detail: detail,
            state: state,
            visibleToGuardian: visible.contains(.guardian),
            visibleToChild: visible.contains(.child),
            visibleToTeacher: visible.contains(.teacher),
            visibleToRelative: visible.contains(.relative)
        )
    }

    private func isVisible(
        _ card: MobileFamilySchoolNotificationDigestCard,
        to role: MobileFamilySchoolNotificationDigestViewerRole
    ) -> Bool {
        switch role {
        case .guardian: return card.visibleToGuardian
        case .child: return card.visibleToChild
        case .teacher: return card.visibleToTeacher
        case .relative: return card.visibleToRelative
        }
    }

    private func publicSummary(
        role: MobileFamilySchoolNotificationDigestViewerRole,
        status: MobileFamilySchoolNotificationDigestStatus,
        cards: [MobileFamilySchoolNotificationDigestCard],
        findings: [MobileFamilySchoolNotificationDigestFinding]
    ) -> MobileFamilySchoolNotificationDigestPublicSummary {
        MobileFamilySchoolNotificationDigestPublicSummary(
            generatedAt: generatedAt,
            viewerRole: role,
            status: status,
            visibleCardCount: cards.count,
            suppressedCardCount: cards.filter { $0.state == .suppressed }.count,
            reviewCardCount: cards.filter { $0.state == .needsReview }.count,
            findingCodes: findings.map(\.code)
        )
    }

    private func headline(
        status: MobileFamilySchoolNotificationDigestStatus,
        role: MobileFamilySchoolNotificationDigestViewerRole,
        cards: [MobileFamilySchoolNotificationDigestCard]
    ) -> String {
        switch status {
        case .ready:
            return "\(role.label)可查看 \(cards.count) 条安全摘要"
        case .reviewRequired:
            return "\(role.label)摘要有抑制或复核项"
        case .blocked:
            return "\(role.label)摘要被安全边界阻断"
        case .empty:
            return "暂无可见通知摘要"
        }
    }

    private func blockedSnapshot(
        viewerRole: MobileFamilySchoolNotificationDigestViewerRole,
        code: MobileFamilySchoolNotificationDigestFindingCode
    ) -> MobileFamilySchoolNotificationDigestSnapshot {
        let finding = finding(code, .blocker, "通知摘要输入包含不安全内容，已进入本地安全壳。")
        return MobileFamilySchoolNotificationDigestSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: .blocked,
            headline: "\(viewerRole.label)摘要已阻断",
            boundary: MobileFamilySchoolNotificationDigestBoundary(
                guardianConsentGranted: false,
                childAssentActive: false,
                childWithdrawn: true,
                relativeConsentGranted: false,
                teacherRosterActive: false,
                urgentQuietOverrideAllowed: false
            ),
            cards: [],
            findings: [finding],
            publicSummary: MobileFamilySchoolNotificationDigestPublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: .blocked,
                visibleCardCount: 0,
                suppressedCardCount: 0,
                reviewCardCount: 0,
                findingCodes: [code]
            ),
            sideEffects: MobileFamilySchoolNotificationDigestSideEffects()
        )
    }

    private func finding(
        _ code: MobileFamilySchoolNotificationDigestFindingCode,
        _ severity: MobileFamilySchoolNotificationDigestSeverity,
        _ message: String
    ) -> MobileFamilySchoolNotificationDigestFinding {
        MobileFamilySchoolNotificationDigestFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("finding:\(code.rawValue):\(message)")
        )
    }

    private func displayValues(_ snapshot: MobileFamilySchoolNotificationDigestSnapshot) -> [String] {
        [
            snapshot.generatedAt,
            snapshot.viewerRole.rawValue,
            snapshot.status.rawValue,
            snapshot.headline
        ]
        + snapshot.cards.flatMap { [$0.publicCardRef, $0.kind.rawValue, $0.title, $0.detail, $0.state.rawValue] }
        + snapshot.findings.flatMap { [$0.code.rawValue, $0.message, $0.publicRef] }
        + snapshot.publicSummary.findingCodes.map(\.rawValue)
    }

    private func hasUnsafePayload(_ value: String?) -> Bool {
        guard let value else { return false }
        let lowered = value.lowercased()
        return sensitiveMarkers.contains { lowered.contains($0) }
    }

    private func publicRef(_ seed: String) -> String {
        "fsd-\(Self.stableHash("\(redactionSalt):\(seed)"))"
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
