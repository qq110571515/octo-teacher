import Foundation

/// iOS 端「监护人与孩子同意策略入口」只读快照。
///
/// 把 B49 `guardian-child-consent-policy-service-contract` 的语义投影到手机端：
/// 在真实同意策略服务、隐私账本、学校系统、AI provider、导出删除管线接入之前，
/// 手机端只做本地确定性投影，回答「这条用途的同意现在是放行 / 待复核 / 阻断，卡在哪个门，
/// 谁能看见什么」。
///
/// 安全边界：不接网络、云 API、数据库、队列、AI、学校系统、社交平台、通知、账本、设备，
/// 也不做真实导出 / 删除 / 授权。所有副作用恒为 false。原始同意理由、亲友权限明细、
/// 老师内部备注、内部同意状态都按角色脱敏，公开层只保留稳定脱敏 publicRef。

enum GuardianChildConsentPolicyViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case relative
    case teacher
    case publicViewer

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        case .teacher: return "老师"
        case .publicViewer: return "公开访客"
        }
    }

    var audienceNote: String {
        switch self {
        case .child:
            return "孩子看到鼓励式说明，不展示家长内部原因、亲友权限明细或老师内部备注。"
        case .guardian:
            return "家长可见全部同意状态、撤回传播、过期、审计与阻断细节。"
        case .relative:
            return "亲友只读，只看被授权范围内的脱敏摘要，不看家庭私密与权限明细。"
        case .teacher:
            return "老师只看学校相关授权，不看家庭私密内容和亲友内容。"
        case .publicViewer:
            return "公开访客只看公开脱敏摘要，不展示任何内部同意状态。"
        }
    }
}

enum GuardianChildConsentPolicyPurpose: String, CaseIterable, Equatable {
    case familyStory
    case honorWall
    case relativeVisibility
    case publicShare
    case schoolTeacherVisibility
    case aiHomeworkAssist
    case dataExportDelete

    var label: String {
        switch self {
        case .familyStory: return "家庭故事线"
        case .honorWall: return "荣誉墙"
        case .relativeVisibility: return "亲友可见"
        case .publicShare: return "公开分享"
        case .schoolTeacherVisibility: return "学校/老师可见"
        case .aiHomeworkAssist: return "AI 作业辅导"
        case .dataExportDelete: return "导出/删除"
        }
    }

    var systemImage: String {
        switch self {
        case .familyStory: return "book.closed"
        case .honorWall: return "trophy"
        case .relativeVisibility: return "person.2"
        case .publicShare: return "globe"
        case .schoolTeacherVisibility: return "studentdesk"
        case .aiHomeworkAssist: return "sparkles"
        case .dataExportDelete: return "tray.and.arrow.down"
        }
    }

    /// 公开层涉及外部传播的用途（需要脱敏审查）。
    var isPublicFacing: Bool {
        self == .publicShare
    }

    /// 学校/老师相关用途。
    var isSchoolFacing: Bool {
        self == .schoolTeacherVisibility
    }

    /// 亲友相关用途。
    var isRelativeFacing: Bool {
        self == .relativeVisibility || self == .familyStory || self == .honorWall
    }
}

enum GuardianChildConsentPolicyState: String, Equatable {
    case allowed
    case gated
    case blocked

    var label: String {
        switch self {
        case .allowed: return "同意放行"
        case .gated: return "待复核"
        case .blocked: return "已阻断"
        }
    }
}

enum GuardianChildConsentState: String, Equatable {
    case granted
    case pending
    case denied
    case revoked
    case expired

    var label: String {
        switch self {
        case .granted: return "已同意"
        case .pending: return "待同意"
        case .denied: return "已拒绝"
        case .revoked: return "已撤回"
        case .expired: return "已过期"
        }
    }

    var isUsable: Bool { self == .granted }
}

enum GuardianChildConsentAgeBand: String, CaseIterable, Equatable {
    case under13
    case age13To15 = "13_15"
    case age16To17 = "16_17"

    var label: String {
        switch self {
        case .under13: return "13 岁以下"
        case .age13To15: return "13-15 岁"
        case .age16To17: return "16-17 岁"
        }
    }

    /// 该年龄段对分享类用途是否需要孩子 assent（共同同意）。
    var requiresChildAssent: Bool {
        self != .under13
    }

    /// 是否允许公开分享（保守：仅 16-17 岁可在脱敏后公开）。
    var allowsPublicShare: Bool {
        self == .age16To17
    }
}

enum GuardianChildConsentPolicySeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

enum GuardianChildConsentPolicyFindingCode: String, Equatable {
    case policyReady = "GUARDIAN_CHILD_CONSENT_POLICY_OK"
    case childVisibilityRedacted = "CHILD_VISIBILITY_REDACTED"
    case relativeBoundaryApplied = "RELATIVE_BOUNDARY_APPLIED"
    case teacherBoundaryApplied = "TEACHER_BOUNDARY_APPLIED"
    case publicRedactionApplied = "PUBLIC_REDACTION_APPLIED"
    case revocationPropagated = "REVOCATION_PROPAGATED"
    case guardianConsentRequired = "GUARDIAN_CONSENT_REQUIRED"
    case childAssentRequired = "CHILD_ASSENT_REQUIRED"
    case purposeMismatch = "CONSENT_PURPOSE_SCOPE_MISMATCH"
    case consentExpiredOrRevoked = "GUARDIAN_CONSENT_EXPIRED_OR_REVOKED"
    case agePublicShareBlocked = "AGE_POLICY_PUBLIC_SHARE_BLOCKED"
    case relativeScopeExceeded = "RELATIVE_SCOPE_BLOCKED"
    case teacherScopeExceeded = "TEACHER_SCOPE_BLOCKED"
    case publicShareNotRedacted = "PUBLIC_REDACTION_REQUIRED"
    case exportDeleteAuditMissing = "EXPORT_DELETE_AUDIT_MISSING"
    case revocationNotPropagated = "REVOCATION_PROPAGATION_MISSING"
    case crossChildFamilyMismatch = "IDENTITY_SCOPE_MISMATCH"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
    case realSideEffectBlocked = "REAL_SIDE_EFFECT_BLOCKED"
    case sideEffectFree = "SIDE_EFFECT_FREE"

    var label: String {
        switch self {
        case .policyReady: return "同意策略就绪"
        case .childVisibilityRedacted: return "孩子端脱敏"
        case .relativeBoundaryApplied: return "亲友边界"
        case .teacherBoundaryApplied: return "老师边界"
        case .publicRedactionApplied: return "公开脱敏"
        case .revocationPropagated: return "撤回已传播"
        case .guardianConsentRequired: return "缺家长同意"
        case .childAssentRequired: return "缺孩子 assent"
        case .purposeMismatch: return "目的错配"
        case .consentExpiredOrRevoked: return "同意过期/撤回"
        case .agePublicShareBlocked: return "年龄段禁止公开"
        case .relativeScopeExceeded: return "亲友越权"
        case .teacherScopeExceeded: return "老师越权"
        case .publicShareNotRedacted: return "公开未脱敏"
        case .exportDeleteAuditMissing: return "导出删除缺审计"
        case .revocationNotPropagated: return "撤回未传播"
        case .crossChildFamilyMismatch: return "跨孩子/跨家庭错挂"
        case .unsafePayloadBlocked: return "不安全负载阻断"
        case .publicSummaryLeak: return "公开摘要泄漏"
        case .realSideEffectBlocked: return "真实副作用阻断"
        case .sideEffectFree: return "无副作用"
        }
    }
}

struct GuardianChildConsentPolicyFinding: Identifiable, Equatable {
    var code: GuardianChildConsentPolicyFindingCode
    var severity: GuardianChildConsentPolicySeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

/// 角色可见性投影：哪些内部信息对当前角色可见。
struct GuardianChildConsentPolicyVisibility: Equatable {
    var viewerRole: GuardianChildConsentPolicyViewerRole
    var canSeeInternalConsentState: Bool
    var canSeeGuardianReason: Bool
    var canSeeRelativePermissionDetail: Bool
    var canSeeTeacherInternalNote: Bool
    var canSeeAuditDetail: Bool
}

/// 可见性与权能决策（已按用途/角色脱敏）。
struct GuardianChildConsentVisibilityDecision: Equatable {
    var familyVisible: Bool
    var relativeVisible: Bool
    var schoolVisible: Bool
    var publicVisible: Bool
    var exportAllowed: Bool
    var deleteAllowed: Bool
    var childCanWithdraw: Bool
    var requiresManualReview: Bool
}

/// 撤回传播计划：本地只读投影，不执行真实删除或通知。
struct GuardianChildConsentRevocationPlan: Equatable {
    var revocationRequired: Bool
    var revocationApplied: Bool
    var deletionSuppressedVisibility: Bool
    var pendingTargetCount: Int

    let writesDeletion = false
    let sendsNotification = false
}

/// 审计摘要：导出/删除/撤回是否有完整审计链。
struct GuardianChildConsentAuditSummary: Equatable {
    var linkedEventCount: Int
    var missingEventCount: Int

    let writesExternalSystem = false
}

/// 公开脱敏摘要：可安全外发的最小字段，所有副作用恒为 false。
struct GuardianChildConsentPolicyPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: GuardianChildConsentPolicyViewerRole
    var state: GuardianChildConsentPolicyState
    var purpose: GuardianChildConsentPolicyPurpose
    var policyPublicRef: String
    var requestPublicRef: String
    var familyPublicRef: String
    var childPublicRef: String
    var guardianPublicRef: String
    var findingCodes: [GuardianChildConsentPolicyFindingCode]
    var guardianConsentGranted: Bool
    var childAssentGranted: Bool
    var relativeVisible: Bool
    var schoolVisible: Bool
    var publicVisible: Bool
    var exportAllowed: Bool
    var deleteAllowed: Bool
    var revocationApplied: Bool

    let writesDatabase = false
    let writesLedger = false
    let writesPrivacyRecord = false
    let writesPermissionGrant = false
    let writesDeletion = false
    let publishesContent = false
    let sendsNotification = false
    let callsNetwork = false
    let callsAi = false
    let callsQueue = false
    let callsSchoolSystem = false
    let callsSocialPlatform = false
    let touchesDevice = false
}

/// 全部副作用标记，恒为 false。
struct GuardianChildConsentPolicySideEffects: Equatable {
    let writesDatabase = false
    let writesLedger = false
    let writesPrivacyRecord = false
    let writesPermissionGrant = false
    let writesDeletion = false
    let publishesContent = false
    let sendsNotification = false
    let callsNetwork = false
    let callsAi = false
    let callsQueue = false
    let callsSchoolSystem = false
    let callsSocialPlatform = false
    let touchesDevice = false
}

struct GuardianChildConsentPolicySnapshot: Equatable {
    var generatedAt: String
    var state: GuardianChildConsentPolicyState
    var purpose: GuardianChildConsentPolicyPurpose
    var ageBand: GuardianChildConsentAgeBand
    var headline: String
    var childSafeCopy: String
    var audienceNote: String
    var visibility: GuardianChildConsentPolicyVisibility
    /// 已按角色脱敏后的同意状态展示文案（公开访客恒为「不可见」）。
    var guardianConsentDisplay: String
    var childAssentDisplay: String
    var decision: GuardianChildConsentVisibilityDecision
    var revocationPlan: GuardianChildConsentRevocationPlan
    var audit: GuardianChildConsentAuditSummary
    var findings: [GuardianChildConsentPolicyFinding]
    var publicSummary: GuardianChildConsentPolicyPublicSummary
    var sideEffects = GuardianChildConsentPolicySideEffects()

    var hasBlocker: Bool {
        findings.contains { $0.severity == .blocker }
    }
}

/// 输入侧风险：检测到不安全 endpoint 或负载时直接阻断，不把原始内容带入快照。
struct GuardianChildConsentPolicyInputRisk: Equatable {
    var unsafeEndpointObserved: Bool
    var unsafePayloadObserved: Bool

    static let safe = GuardianChildConsentPolicyInputRisk(
        unsafeEndpointObserved: false,
        unsafePayloadObserved: false
    )
    static let unsafeEndpointDetected = GuardianChildConsentPolicyInputRisk(
        unsafeEndpointObserved: true,
        unsafePayloadObserved: false
    )
    static let unsafePayloadDetected = GuardianChildConsentPolicyInputRisk(
        unsafeEndpointObserved: false,
        unsafePayloadObserved: true
    )

    var blocksPolicy: Bool {
        unsafeEndpointObserved || unsafePayloadObserved
    }
}
