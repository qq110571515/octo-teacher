import Foundation

/// iOS 亲友创作评论/鼓励安全壳的纯本地只读投影。
///
/// 该层只组织创作展示下的亲友鼓励、评论草稿、奖励承诺与撤回/申诉边界：
/// 不发布评论，不审核评论，不通知孩子或亲友，不上传媒体，不写账本，不发成长积分，不解锁设备。
enum MobileRelativeCreativeCommentViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case relative

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        }
    }

    var audienceNote: String {
        switch self {
        case .child:
            return "这里只看家长确认过的温和鼓励和安全下一步。"
        case .guardian:
            return "只读查看关系授权、评论审核、情绪安全、奖励压力、撤回/申诉和成长积分边界。"
        case .relative:
            return "这里只显示支持性表达指引和待审核状态；互动和奖励都由家长流程处理。"
        }
    }
}

enum MobileRelativeCreativeCommentState: String, Equatable {
    case approvedEncouragement
    case waitingGuardianReview
    case hiddenFromChild
    case blocked

    var label: String {
        switch self {
        case .approvedEncouragement: return "可鼓励"
        case .waitingGuardianReview: return "待家长审核"
        case .hiddenFromChild: return "孩子不可见"
        case .blocked: return "已阻断"
        }
    }
}

enum MobileRelativeCreativeCommentFindingCode: String, Equatable {
    case readOnlyReady = "READ_ONLY_READY"
    case approvalRequired = "APPROVAL_REQUIRED"
    case privacyVisibilityBlocked = "PRIVACY_VISIBILITY_BLOCKED"
    case rewardPressureBlocked = "REWARD_PRESSURE_BLOCKED"
    case roleBoundaryBlocked = "ROLE_BOUNDARY_BLOCKED"
    case removalAppealBlocked = "REMOVAL_APPEAL_BLOCKED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

enum MobileRelativeCreativeCommentAuthorRole: String, Equatable {
    case relative
    case expert
    case unknown

    var label: String {
        switch self {
        case .relative: return "亲友"
        case .expert: return "专家"
        case .unknown: return "未知"
        }
    }
}

struct MobileRelativeCreativeCommentDraft: Equatable {
    var commentId: String
    var showcaseId: String
    var authorRole: MobileRelativeCreativeCommentAuthorRole
    var supportiveSummary: String
    var relationshipAuthorized: Bool
    var guardianApproved: Bool
    var moderationPassed: Bool
    var childAssentActive: Bool
    var showcasePrivate: Bool
    var showcaseWithdrawn: Bool
    var deletionRequested: Bool
    var appealOpen: Bool
    var rewardPromise: Bool
    var deviceUnlockLanguage: Bool
    var schoolDetailMentioned: Bool
}

struct MobileRelativeCreativeCommentRow: Identifiable, Equatable {
    var publicCommentRef: String
    var title: String
    var summary: String
    var authorLabel: String
    var reviewLabel: String
    var privacyLabel: String
    var emotionalSafetyLabel: String
    var rewardBoundaryLabel: String
    var nextStep: String
    var safetyNote: String
    var state: MobileRelativeCreativeCommentState
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToRelative: Bool
    var relationshipAuthorized: Bool
    var guardianApproved: Bool
    var moderationPassed: Bool
    var rewardPressureBlocked: Bool
    var roleBoundaryBlocked: Bool
    var removalOrAppealBlocked: Bool

    let publishesComment = false
    let approvesComment = false
    let sendsNotification = false
    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let uploadsMedia = false
    let callsNetwork = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let writesSocialPlatform = false

    var id: String { publicCommentRef }

    var displayValues: [String] {
        [
            title,
            summary,
            authorLabel,
            reviewLabel,
            privacyLabel,
            emotionalSafetyLabel,
            rewardBoundaryLabel,
            nextStep,
            safetyNote,
            state.rawValue,
            state.label
        ]
    }
}

struct MobileRelativeCreativeCommentFinding: Identifiable, Equatable {
    var code: MobileRelativeCreativeCommentFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool
    var visibleToRelative: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileRelativeCreativeCommentPublicSummary: Equatable {
    var role: MobileRelativeCreativeCommentViewerRole
    var commentCount: Int
    var visibleCommentCount: Int
    var waitingReviewCount: Int
    var hiddenFromChildCount: Int
    var blockedCount: Int
    var rewardPressureBlockedCount: Int
    var findingCodes: [MobileRelativeCreativeCommentFindingCode]

    let publishesComment = false
    let approvesComment = false
    let sendsNotification = false
    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let uploadsMedia = false
    let callsNetwork = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let writesSocialPlatform = false

    var hasTriggeredSideEffect: Bool {
        publishesComment || approvesComment || sendsNotification || opensCamera || opensPhotoLibrary
            || opensFilePicker || uploadsMedia || callsNetwork || writesLedger || grantsCredit
            || unlocksDevice || writesSocialPlatform
    }
}

struct MobileRelativeCreativeCommentSafetyWorkbench: Equatable {
    var role: MobileRelativeCreativeCommentViewerRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var comments: [MobileRelativeCreativeCommentRow]
    var findings: [MobileRelativeCreativeCommentFinding]
    var publicSummary: MobileRelativeCreativeCommentPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + comments.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileRelativeCreativeCommentSafetyBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileRelativeCreativeCommentSafetyBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "guardian:", "relative:", "comment:", "media:",
        "showcase:", "proof:", "creator:", "pack:", "session:", "device:",
        "ledger:", "credit:", "reward amount", "设备命令", "原文：",
        "http://", "https://", "file://", "/users/", "/volumes/"
    ]
    private static let sensitivePatterns = [
        "(?i)\\b(?:access|device|session|api|bearer)[ _-]?token\\b",
        "(?i)\\b(?:api|server|client)[ _-]?secret\\b",
        "(?i)\\bapi[_-]?key\\b",
        "(?i)\\bcredit[ _-]?amount\\b",
        "成长积分金额[:：]"
    ]

    func build(
        role: MobileRelativeCreativeCommentViewerRole,
        drafts: [MobileRelativeCreativeCommentDraft] = .mobileRelativeCreativeCommentMock
    ) -> MobileRelativeCreativeCommentSafetyWorkbench {
        if Self.hasUnsafeDraftPayload(drafts) {
            return safeFallback(role: role, hiddenCount: drafts.count)
        }

        let rows = drafts.map { row(from: $0, role: role) }
        let visibleRows = rows.filter { isVisible($0, to: role) }
        let findings = findingRows(role: role, rows: rows)
        let summary = MobileRelativeCreativeCommentPublicSummary(
            role: role,
            commentCount: rows.count,
            visibleCommentCount: visibleRows.count,
            waitingReviewCount: rows.filter { $0.state == .waitingGuardianReview }.count,
            hiddenFromChildCount: rows.filter { !$0.visibleToChild }.count,
            blockedCount: rows.filter { $0.state == .blocked }.count,
            rewardPressureBlockedCount: rows.filter(\.rewardPressureBlocked).count,
            findingCodes: findings.map(\.code)
        )
        let workbench = MobileRelativeCreativeCommentSafetyWorkbench(
            role: role,
            title: "亲友评论鼓励安全壳",
            subtitle: "创作展示互动 · 本地只读",
            audienceNote: role.audienceNote,
            comments: visibleRows,
            findings: findings.filter { finding in
                switch role {
                case .child: return finding.visibleToChild
                case .relative: return finding.visibleToRelative
                case .guardian: return true
                }
            },
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? safeFallback(role: role, hiddenCount: drafts.count) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        if sensitiveMarkers.contains(where: { joined.contains($0) }) { return true }
        return sensitivePatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func hasUnsafeDraftPayload(_ drafts: [MobileRelativeCreativeCommentDraft]) -> Bool {
        hasUnsafeDisplayPayload(drafts.flatMap { [$0.supportiveSummary, $0.commentId, $0.showcaseId] })
    }

    private func row(
        from draft: MobileRelativeCreativeCommentDraft,
        role: MobileRelativeCreativeCommentViewerRole
    ) -> MobileRelativeCreativeCommentRow {
        let roleBoundaryBlocked = draft.authorRole != .relative || !draft.relationshipAuthorized
        let rewardPressureBlocked = draft.rewardPromise || draft.deviceUnlockLanguage
        let privacyBlocked = !draft.childAssentActive || draft.showcasePrivate || draft.showcaseWithdrawn
        let removalOrAppealBlocked = draft.deletionRequested || draft.appealOpen
        let contentBlocked = !draft.moderationPassed || draft.schoolDetailMentioned
        let blocked = roleBoundaryBlocked || rewardPressureBlocked || privacyBlocked || removalOrAppealBlocked || contentBlocked
        let waiting = !draft.guardianApproved
        let visibleToChild = !blocked && !waiting && draft.guardianApproved
        let visibleToRelative = !blocked

        let state: MobileRelativeCreativeCommentState
        if blocked {
            state = .blocked
        } else if waiting {
            state = .waitingGuardianReview
        } else if role == .child && !visibleToChild {
            state = .hiddenFromChild
        } else {
            state = .approvedEncouragement
        }

        return MobileRelativeCreativeCommentRow(
            publicCommentRef: publicRef("mrc", draft.commentId),
            title: titleCopy(role: role),
            summary: summaryCopy(role: role, draft: draft, state: state),
            authorLabel: role == .guardian ? draft.authorRole.label : "亲友",
            reviewLabel: draft.guardianApproved && draft.moderationPassed ? "家长审核已通过" : "仍需家长审核",
            privacyLabel: privacyBlocked ? "私密或撤回内容不展示" : "作品可见范围已确认",
            emotionalSafetyLabel: draft.moderationPassed && !draft.schoolDetailMentioned ? "鼓励语气安全" : "评论内容需复核",
            rewardBoundaryLabel: rewardPressureBlocked ? "奖励承诺已阻断" : "不触发成长积分或设备",
            nextStep: nextStep(role: role, state: state),
            safetyNote: safetyNote(role: role),
            state: state,
            visibleToChild: visibleToChild,
            visibleToGuardian: role == .guardian,
            visibleToRelative: visibleToRelative,
            relationshipAuthorized: draft.relationshipAuthorized,
            guardianApproved: draft.guardianApproved,
            moderationPassed: draft.moderationPassed,
            rewardPressureBlocked: rewardPressureBlocked,
            roleBoundaryBlocked: roleBoundaryBlocked,
            removalOrAppealBlocked: removalOrAppealBlocked
        )
    }

    private func isVisible(
        _ row: MobileRelativeCreativeCommentRow,
        to role: MobileRelativeCreativeCommentViewerRole
    ) -> Bool {
        switch role {
        case .child: return row.visibleToChild && row.state == .approvedEncouragement
        case .guardian: return row.visibleToGuardian
        case .relative: return row.visibleToRelative && row.state != .blocked
        }
    }

    private func findingRows(
        role: MobileRelativeCreativeCommentViewerRole,
        rows: [MobileRelativeCreativeCommentRow]
    ) -> [MobileRelativeCreativeCommentFinding] {
        var findings: [MobileRelativeCreativeCommentFinding] = []
        if rows.contains(where: { $0.state == .waitingGuardianReview }) {
            findings.append(finding(.approvalRequired, "亲友评论需要先经过家长审核，不能直接进入孩子视角。", true, child: true, relative: true))
        }
        if rows.contains(where: { !$0.visibleToChild }) {
            findings.append(finding(.privacyVisibilityBlocked, "私密、撤回、待审核或内容复核中的评论不会展示给孩子。", true, child: false, relative: false))
        }
        if rows.contains(where: \.rewardPressureBlocked) {
            findings.append(finding(.rewardPressureBlocked, "奖励承诺、解锁暗示或设备语义会阻断评论。", true, child: false, relative: false))
        }
        if rows.contains(where: \.roleBoundaryBlocked) {
            findings.append(finding(.roleBoundaryBlocked, "非授权亲友或专家身份不能伪装成家庭鼓励评论。", true, child: false, relative: false))
        }
        if rows.contains(where: \.removalOrAppealBlocked) {
            findings.append(finding(.removalAppealBlocked, "删除、撤回或申诉中的评论不会进入展示。", true, child: false, relative: false))
        }
        if findings.isEmpty {
            findings.append(finding(
                .readOnlyReady,
                role == .relative ? "当前只显示支持性表达指引，真实互动等待家长流程。" : "亲友评论鼓励安全壳只读就绪。",
                false,
                child: true,
                relative: true
            ))
        }
        return findings
    }

    private func finding(
        _ code: MobileRelativeCreativeCommentFindingCode,
        _ message: String,
        _ actionRequired: Bool,
        child: Bool,
        relative: Bool
    ) -> MobileRelativeCreativeCommentFinding {
        MobileRelativeCreativeCommentFinding(
            code: code,
            message: message,
            actionRequired: actionRequired,
            visibleToChild: child,
            visibleToRelative: relative
        )
    }

    private func titleCopy(role: MobileRelativeCreativeCommentViewerRole) -> String {
        switch role {
        case .child: return "家人鼓励"
        case .guardian: return "亲友评论审核"
        case .relative: return "支持性表达指引"
        }
    }

    private func summaryCopy(
        role: MobileRelativeCreativeCommentViewerRole,
        draft: MobileRelativeCreativeCommentDraft,
        state: MobileRelativeCreativeCommentState
    ) -> String {
        switch role {
        case .child:
            return state == .approvedEncouragement ? "家人看到了你的努力，给了温和鼓励。" : "这条互动还在家长保护中。"
        case .guardian:
            return draft.supportiveSummary
        case .relative:
            return "可以表达支持，但不要承诺奖励、询问作业细节或要求孩子兑换。"
        }
    }

    private func nextStep(
        role: MobileRelativeCreativeCommentViewerRole,
        state: MobileRelativeCreativeCommentState
    ) -> String {
        switch (role, state) {
        case (.child, .approvedEncouragement):
            return "看见鼓励后继续完成自己的创作。"
        case (.guardian, .approvedEncouragement):
            return "确认可见范围后，再交给正式互动流程。"
        case (.guardian, .waitingGuardianReview):
            return "先检查关系授权、情绪安全和奖励压力。"
        case (.relative, .approvedEncouragement), (.relative, .waitingGuardianReview):
            return "提交支持性表达后等待家长审核。"
        default:
            return "该互动暂不展示，请先修正安全边界。"
        }
    }

    private func safetyNote(role: MobileRelativeCreativeCommentViewerRole) -> String {
        switch role {
        case .child:
            return "孩子视角只显示温和鼓励，不展示成人处理细节。"
        case .guardian:
            return "本页不发布评论、不通知亲友、不写账本、不处理设备。"
        case .relative:
            return "亲友侧只读展示指引，不发布评论、不通知孩子。"
        }
    }

    private func safeFallback(
        role: MobileRelativeCreativeCommentViewerRole,
        hiddenCount: Int
    ) -> MobileRelativeCreativeCommentSafetyWorkbench {
        MobileRelativeCreativeCommentSafetyWorkbench(
            role: role,
            title: "亲友互动已被安全保护",
            subtitle: "本地安全壳",
            audienceNote: role.audienceNote,
            comments: [],
            findings: [
                finding(
                    .unsafePayloadBlocked,
                    "检测到链接、路径、密钥、局域网地址、内部标识或评论/成长积分/设备敏感语义，本地壳不回显原文。",
                    role == .guardian,
                    child: false,
                    relative: false
                )
            ],
            publicSummary: MobileRelativeCreativeCommentPublicSummary(
                role: role,
                commentCount: hiddenCount,
                visibleCommentCount: 0,
                waitingReviewCount: 0,
                hiddenFromChildCount: hiddenCount,
                blockedCount: hiddenCount,
                rewardPressureBlockedCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        var hash: UInt32 = 5381
        for scalar in "mobile-relative-creative-comment:\(source)".unicodeScalars {
            hash = (hash &* 33) ^ (scalar.value & 0xFFFF)
        }
        return "\(prefix)-\(String(hash, radix: 36))"
    }
}

extension Array where Element == MobileRelativeCreativeCommentDraft {
    static var mobileRelativeCreativeCommentMock: [MobileRelativeCreativeCommentDraft] {
        [
            MobileRelativeCreativeCommentDraft(
                commentId: "comment-encourage-a",
                showcaseId: "showcase-art-a",
                authorRole: .relative,
                supportiveSummary: "亲友给出温和鼓励，肯定孩子坚持完成创作。",
                relationshipAuthorized: true,
                guardianApproved: true,
                moderationPassed: true,
                childAssentActive: true,
                showcasePrivate: false,
                showcaseWithdrawn: false,
                deletionRequested: false,
                appealOpen: false,
                rewardPromise: false,
                deviceUnlockLanguage: false,
                schoolDetailMentioned: false
            )
        ]
    }
}
