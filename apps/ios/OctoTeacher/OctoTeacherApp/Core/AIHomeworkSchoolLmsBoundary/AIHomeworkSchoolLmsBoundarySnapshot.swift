import Foundation

/// iOS 端「AI 作业学校 LMS/provider 边界」只读快照。
///
/// 对齐 B50 的服务边界：真实 AI provider、局域网 QWEN、学校 LMS 和云端 API 接入之前，
/// 手机端只展示本地确定性投影。它回答「现在是否允许进入未来 provider/LMS 接入链路、卡在哪个门」，
/// 但绝不调用模型、网络、学校系统、LMS、数据库、队列、通知、账本或设备，也不保存原始 transcript、
/// 不展示 answer key、provider/model、baseUrl、token 或成长积分金额。

enum AIHomeworkSchoolLmsBoundaryViewerRole: String, Equatable, CaseIterable {
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

    var isCareTeam: Bool { self != .child }
}

enum AIHomeworkSchoolLmsBoundaryState: String, Equatable {
    case ready
    case gated
    case blocked
    case empty

    var label: String {
        switch self {
        case .ready: return "边界就绪"
        case .gated: return "等待复核"
        case .blocked: return "已阻断"
        case .empty: return "暂无作业"
        }
    }
}

enum AIHomeworkSchoolLmsProviderMode: String, Equatable {
    case disabledLocalProjection = "disabled_local_projection"
    case dryRunRedacted = "dry_run_redacted"
    case liveProvider = "live_provider"

    var label: String {
        switch self {
        case .disabledLocalProjection: return "本地只读投影"
        case .dryRunRedacted: return "脱敏预演"
        case .liveProvider: return "真实 provider"
        }
    }
}

enum AIHomeworkSchoolLmsMode: String, Equatable {
    case readOnlySnapshot = "read_only_snapshot"
    case liveRead = "live_read"
    case writeBack = "write_back"

    var label: String {
        switch self {
        case .readOnlySnapshot: return "只读快照"
        case .liveRead: return "实时读取"
        case .writeBack: return "写回模式"
        }
    }
}

enum AIHomeworkSchoolLmsAgeBand: String, Equatable, CaseIterable {
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

    var maxDryRunTokens: Int {
        switch self {
        case .under13: return 800
        case .age13To15: return 1600
        case .age16To17: return 2000
        }
    }
}

enum AIHomeworkSchoolLmsBoundarySeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

enum AIHomeworkSchoolLmsBoundaryFindingCode: String, Equatable {
    case boundaryReady = "BOUNDARY_READY"
    case childVisibilityRedacted = "CHILD_VISIBILITY_REDACTED"
    case providerDisabled = "PROVIDER_DISABLED"
    case providerRequestBlocked = "PROVIDER_REQUEST_BLOCKED"
    case providerSecretOrEndpointBlocked = "PROVIDER_SECRET_OR_ENDPOINT_BLOCKED"
    case directAnswerBlocked = "DIRECT_ANSWER_BOUNDARY_BLOCKED"
    case lmsReadOnly = "LMS_READ_ONLY"
    case lmsWriteBlocked = "LMS_WRITE_BOUNDARY_BLOCKED"
    case consentRequired = "CONSENT_REQUIRED"
    case ageOrRateLimitBlocked = "AGE_OR_RATE_LIMIT_BLOCKED"
    case manualEscalationRequired = "MANUAL_ESCALATION_REQUIRED"
    case rawTranscriptBlocked = "RAW_TRANSCRIPT_BOUNDARY_BLOCKED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

struct AIHomeworkSchoolLmsBoundaryFinding: Identifiable, Equatable {
    var code: AIHomeworkSchoolLmsBoundaryFindingCode
    var severity: AIHomeworkSchoolLmsBoundarySeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct AIHomeworkSchoolLmsBoundaryVisibility: Equatable {
    var viewerRole: AIHomeworkSchoolLmsBoundaryViewerRole
    var canSeeProviderInternals: Bool
    var canSeeConsentDetail: Bool
    var canSeeTeacherDetail: Bool
    var canSeeTranscriptSummary: Bool
}

struct AIHomeworkSchoolLmsProviderBoundary: Equatable {
    var providerPublicRef: String
    var requestMode: AIHomeworkSchoolLmsProviderMode
    var requestAllowed: Bool
    var maxTokens: Int
    var tokenCeiling: Int
    var noDirectAnswer: Bool
    var socraticFirst: Bool
    var childSeesProviderDetails: Bool

    let callsAiProvider = false
    let callsLocalModel = false
    let callsNetwork = false
    let sendsRawPrompt = false
    let sendsRawTranscript = false
    let sendsAnswerKey = false
}

struct AIHomeworkSchoolLmsReadOnlyBoundary: Equatable {
    var schoolPublicRef: String
    var homeworkPublicRef: String
    var mode: AIHomeworkSchoolLmsMode
    var lmsReadOnly: Bool

    let callsLms = false
    let writesGrade = false
    let writesSubmission = false
    let uploadsAttachment = false
    let mutatesAssignment = false
    let syncsRoster = false
}

struct AIHomeworkSchoolLmsConsentBoundary: Equatable {
    var guardianConsentGranted: Bool
    var childAssentGranted: Bool
    var teacherAuthorized: Bool
    var consentPublicRef: String
    var guardianConsentHidden = false
    var childAssentHidden = false
    var teacherAuthorizationHidden = false
}

struct AIHomeworkSchoolLmsTranscriptBoundary: Equatable {
    var retentionMode: String
    var parentSummaryRedacted: Bool
    var teacherSummaryRedacted: Bool

    let storesRawTranscript = false
    let rawChildInputVisibleToTeacher = false
    let rawChildInputVisibleToGuardian = false
    let revealsAnswerKey = false
}

struct AIHomeworkSchoolLmsAuditSummary: Equatable {
    var linkedEventCount: Int
    var missingEventCount: Int

    let writesExternalSystem = false
}

struct AIHomeworkSchoolLmsBoundaryPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: AIHomeworkSchoolLmsBoundaryViewerRole
    var state: AIHomeworkSchoolLmsBoundaryState
    var homeworkPublicRef: String
    var boundaryPublicRef: String
    var findingCodes: [AIHomeworkSchoolLmsBoundaryFindingCode]
    var providerRequestAllowed: Bool
    var lmsReadOnly: Bool
    var manualReviewRequired: Bool

    let callsAiProvider = false
    let callsLocalModel = false
    let callsNetwork = false
    let callsLms = false
    let writesSchoolSystem = false
    let writesDatabase = false
    let writesLedger = false
    let sendsNotification = false
    let storesRawTranscript = false
    let createsScore = false
    let showsAnswerKey = false
    let revealsModelOrProvider = false
    let unlocksDevice = false
}

struct AIHomeworkSchoolLmsBoundarySnapshot: Equatable {
    var generatedAt: String
    var state: AIHomeworkSchoolLmsBoundaryState
    var headline: String
    var childSafeCopy: String
    var visibility: AIHomeworkSchoolLmsBoundaryVisibility
    var subjectLabel: String
    var statusLabel: String
    var provider: AIHomeworkSchoolLmsProviderBoundary
    var lms: AIHomeworkSchoolLmsReadOnlyBoundary
    var consent: AIHomeworkSchoolLmsConsentBoundary
    var transcript: AIHomeworkSchoolLmsTranscriptBoundary
    var audit: AIHomeworkSchoolLmsAuditSummary
    var findings: [AIHomeworkSchoolLmsBoundaryFinding]
    var publicSummary: AIHomeworkSchoolLmsBoundaryPublicSummary
}

struct AIHomeworkSchoolLmsBoundaryInputRisk: Equatable {
    var unsafeEndpointObserved: Bool
    var unsafePayloadObserved: Bool

    static let safe = AIHomeworkSchoolLmsBoundaryInputRisk(
        unsafeEndpointObserved: false,
        unsafePayloadObserved: false
    )
    static let unsafeEndpointDetected = AIHomeworkSchoolLmsBoundaryInputRisk(
        unsafeEndpointObserved: true,
        unsafePayloadObserved: false
    )
    static let unsafePayloadDetected = AIHomeworkSchoolLmsBoundaryInputRisk(
        unsafeEndpointObserved: false,
        unsafePayloadObserved: true
    )

    var blocksProviderBoundary: Bool {
        unsafeEndpointObserved || unsafePayloadObserved
    }
}

struct AIHomeworkSchoolLmsBoundaryBuilder {
    var generatedAt = "2026-06-24T12:00:00Z"
    var redactionSalt = "ai-homework-school-lms-boundary-ios-v1"

    func build(
        viewerRole: AIHomeworkSchoolLmsBoundaryViewerRole,
        homework: SchoolHomework?,
        messages: [AIHomeworkSessionMessage] = [],
        providerMode: AIHomeworkSchoolLmsProviderMode = .disabledLocalProjection,
        inputRisk: AIHomeworkSchoolLmsBoundaryInputRisk = .safe,
        lmsMode: AIHomeworkSchoolLmsMode = .readOnlySnapshot,
        ageBand: AIHomeworkSchoolLmsAgeBand = .age13To15,
        maxTokens: Int = 1200,
        requestsInLastHour: Int = 2,
        maxRequestsPerHour: Int = 8,
        guardianConsentGranted: Bool = true,
        childAssentGranted: Bool = true,
        teacherAuthorized: Bool = true,
        manualReviewRequired: Bool = false,
        manualReviewRouted: Bool = true
    ) -> AIHomeworkSchoolLmsBoundarySnapshot {
        let visibility = visibility(for: viewerRole)
        guard let homework else {
            return emptySnapshot(viewerRole: viewerRole, visibility: visibility)
        }

        if inputRisk.blocksProviderBoundary {
            return blockedSnapshot(
                viewerRole: viewerRole,
                visibility: visibility,
                homework: homework,
                code: .providerSecretOrEndpointBlocked
            )
        }

        let directAnswerBlocked = messages.contains { $0.intent == .wantsDirectAnswer || $0.containsUnsafeInput }
        let providerBlocked = providerMode == .liveProvider
        let lmsWriteBlocked = lmsMode == .writeBack
        let consentBlocked = !guardianConsentGranted || !childAssentGranted || !teacherAuthorized
        let ageRateBlocked = requestsInLastHour > maxRequestsPerHour || maxTokens > ageBand.maxDryRunTokens
        let manualBlocked = manualReviewRequired && !manualReviewRouted
        let returnedBlocked = homework.status == .returned
        let blocker = providerBlocked || lmsWriteBlocked || consentBlocked || directAnswerBlocked || manualBlocked || returnedBlocked
            || (ageRateBlocked && ageBand == .under13)
        let gated = ageRateBlocked || manualReviewRequired || homework.status == .submitted || homework.status == .verified
        let state: AIHomeworkSchoolLmsBoundaryState = blocker ? .blocked : (gated ? .gated : .ready)

        var findings = findings(
            viewerRole: viewerRole,
            state: state,
            providerBlocked: providerBlocked,
            lmsWriteBlocked: lmsWriteBlocked,
            consentBlocked: consentBlocked,
            directAnswerBlocked: directAnswerBlocked,
            ageRateBlocked: ageRateBlocked,
            manualBlocked: manualBlocked,
            returnedBlocked: returnedBlocked
        )
        if !providerBlocked {
            findings.append(finding(.providerDisabled, .ok, "Provider 仍保持本地只读或脱敏预演。", "provider"))
        }
        if !lmsWriteBlocked {
            findings.append(finding(.lmsReadOnly, .ok, "LMS 仍保持只读快照。", "lms"))
        }
        if state == .ready {
            findings.insert(finding(.boundaryReady, .ok, "AI/LMS 边界只读就绪。", "boundary"), at: 0)
        }

        let providerBoundary = AIHomeworkSchoolLmsProviderBoundary(
            providerPublicRef: stableRef("prov", "provider-disabled"),
            requestMode: providerMode,
            requestAllowed: state == .ready && providerMode != .liveProvider,
            maxTokens: maxTokens,
            tokenCeiling: ageBand.maxDryRunTokens,
            noDirectAnswer: !directAnswerBlocked,
            socraticFirst: true,
            childSeesProviderDetails: false
        )
        let provider = visibleProvider(providerBoundary, visibility: visibility)
        let lms = AIHomeworkSchoolLmsReadOnlyBoundary(
            schoolPublicRef: stableRef("sch", "school-local"),
            homeworkPublicRef: stableRef("hw", homework.id.uuidString),
            mode: lmsMode,
            lmsReadOnly: state != .blocked && lmsMode == .readOnlySnapshot
        )
        let consent = AIHomeworkSchoolLmsConsentBoundary(
            guardianConsentGranted: guardianConsentGranted,
            childAssentGranted: childAssentGranted,
            teacherAuthorized: teacherAuthorized,
            consentPublicRef: stableRef("cons", "\(homework.id.uuidString):consent")
        )
        let transcript = AIHomeworkSchoolLmsTranscriptBoundary(
            retentionMode: "redacted_summary",
            parentSummaryRedacted: true,
            teacherSummaryRedacted: true
        )
        let audit = AIHomeworkSchoolLmsAuditSummary(
            linkedEventCount: state == .blocked ? 5 : 6,
            missingEventCount: state == .blocked ? 1 : 0
        )
        let summary = AIHomeworkSchoolLmsBoundaryPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            state: state,
            homeworkPublicRef: lms.homeworkPublicRef,
            boundaryPublicRef: stableRef("bnd", "\(homework.id.uuidString):boundary"),
            findingCodes: findings.map(\.code),
            providerRequestAllowed: provider.requestAllowed,
            lmsReadOnly: lms.lmsReadOnly,
            manualReviewRequired: manualReviewRequired || ageRateBlocked
        )
        let snapshot = AIHomeworkSchoolLmsBoundarySnapshot(
            generatedAt: generatedAt,
            state: state,
            headline: headline(state: state, homework: homework, viewerRole: viewerRole),
            childSafeCopy: childCopy(state: state, directAnswerBlocked: directAnswerBlocked),
            visibility: visibility,
            subjectLabel: homework.subject.label,
            statusLabel: homework.status.label,
            provider: provider,
            lms: lms,
            consent: visibleConsent(consent, visibility: visibility),
            transcript: transcript,
            audit: audit,
            findings: findings,
            publicSummary: summary
        )
        return redacts(snapshot)
            ? snapshot
            : blockedSnapshot(viewerRole: viewerRole, visibility: visibility, homework: homework, code: .publicSummaryLeak)
    }

    func redacts(_ snapshot: AIHomeworkSchoolLmsBoundarySnapshot) -> Bool {
        !hasUnsafeDisplayValues(displayValues(snapshot))
    }

    private func emptySnapshot(
        viewerRole: AIHomeworkSchoolLmsBoundaryViewerRole,
        visibility: AIHomeworkSchoolLmsBoundaryVisibility
    ) -> AIHomeworkSchoolLmsBoundarySnapshot {
        let provider = AIHomeworkSchoolLmsProviderBoundary(
            providerPublicRef: stableRef("prov", "empty"),
            requestMode: .disabledLocalProjection,
            requestAllowed: false,
            maxTokens: 0,
            tokenCeiling: AIHomeworkSchoolLmsAgeBand.age13To15.maxDryRunTokens,
            noDirectAnswer: true,
            socraticFirst: true,
            childSeesProviderDetails: false
        )
        let lms = AIHomeworkSchoolLmsReadOnlyBoundary(
            schoolPublicRef: stableRef("sch", "empty"),
            homeworkPublicRef: stableRef("hw", "empty"),
            mode: .readOnlySnapshot,
            lmsReadOnly: true
        )
        let consent = AIHomeworkSchoolLmsConsentBoundary(
            guardianConsentGranted: false,
            childAssentGranted: false,
            teacherAuthorized: false,
            consentPublicRef: stableRef("cons", "empty")
        )
        let summary = AIHomeworkSchoolLmsBoundaryPublicSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            state: .empty,
            homeworkPublicRef: lms.homeworkPublicRef,
            boundaryPublicRef: stableRef("bnd", "empty"),
            findingCodes: [],
            providerRequestAllowed: false,
            lmsReadOnly: true,
            manualReviewRequired: false
        )
        return AIHomeworkSchoolLmsBoundarySnapshot(
            generatedAt: generatedAt,
            state: .empty,
            headline: "暂无 AI/LMS 边界复核作业",
            childSafeCopy: "现在还没有需要复核的作业。",
            visibility: visibility,
            subjectLabel: "暂无",
            statusLabel: "暂无作业",
            provider: provider,
            lms: lms,
            consent: visibleConsent(consent, visibility: visibility),
            transcript: AIHomeworkSchoolLmsTranscriptBoundary(
                retentionMode: "none",
                parentSummaryRedacted: true,
                teacherSummaryRedacted: true
            ),
            audit: AIHomeworkSchoolLmsAuditSummary(linkedEventCount: 0, missingEventCount: 0),
            findings: [],
            publicSummary: summary
        )
    }

    private func blockedSnapshot(
        viewerRole: AIHomeworkSchoolLmsBoundaryViewerRole,
        visibility: AIHomeworkSchoolLmsBoundaryVisibility,
        homework: SchoolHomework,
        code: AIHomeworkSchoolLmsBoundaryFindingCode
    ) -> AIHomeworkSchoolLmsBoundarySnapshot {
        build(
            viewerRole: viewerRole,
            homework: homework,
            providerMode: .liveProvider,
            ageBand: .age13To15,
            maxTokens: 1200,
            guardianConsentGranted: true,
            childAssentGranted: true,
            teacherAuthorized: true
        ).replacingFindings([finding(code, .blocker, "边界输入已被安全阻断。", "boundary")])
    }

    private func visibility(for role: AIHomeworkSchoolLmsBoundaryViewerRole) -> AIHomeworkSchoolLmsBoundaryVisibility {
        switch role {
        case .child:
            return AIHomeworkSchoolLmsBoundaryVisibility(
                viewerRole: role,
                canSeeProviderInternals: false,
                canSeeConsentDetail: false,
                canSeeTeacherDetail: false,
                canSeeTranscriptSummary: false
            )
        case .guardian:
            return AIHomeworkSchoolLmsBoundaryVisibility(
                viewerRole: role,
                canSeeProviderInternals: false,
                canSeeConsentDetail: true,
                canSeeTeacherDetail: true,
                canSeeTranscriptSummary: true
            )
        case .teacher:
            return AIHomeworkSchoolLmsBoundaryVisibility(
                viewerRole: role,
                canSeeProviderInternals: false,
                canSeeConsentDetail: false,
                canSeeTeacherDetail: true,
                canSeeTranscriptSummary: true
            )
        }
    }

    private func visibleConsent(
        _ consent: AIHomeworkSchoolLmsConsentBoundary,
        visibility: AIHomeworkSchoolLmsBoundaryVisibility
    ) -> AIHomeworkSchoolLmsConsentBoundary {
        guard visibility.canSeeConsentDetail else {
            return AIHomeworkSchoolLmsConsentBoundary(
                guardianConsentGranted: false,
                childAssentGranted: false,
                teacherAuthorized: visibility.canSeeTeacherDetail ? consent.teacherAuthorized : false,
                consentPublicRef: consent.consentPublicRef,
                guardianConsentHidden: true,
                childAssentHidden: true,
                teacherAuthorizationHidden: !visibility.canSeeTeacherDetail
            )
        }
        return consent
    }

    private func visibleProvider(
        _ provider: AIHomeworkSchoolLmsProviderBoundary,
        visibility: AIHomeworkSchoolLmsBoundaryVisibility
    ) -> AIHomeworkSchoolLmsProviderBoundary {
        guard visibility.viewerRole != .child else {
            return AIHomeworkSchoolLmsProviderBoundary(
                providerPublicRef: provider.providerPublicRef,
                requestMode: .disabledLocalProjection,
                requestAllowed: false,
                maxTokens: 0,
                tokenCeiling: 0,
                noDirectAnswer: provider.noDirectAnswer,
                socraticFirst: true,
                childSeesProviderDetails: false
            )
        }
        return provider
    }

    private func findings(
        viewerRole: AIHomeworkSchoolLmsBoundaryViewerRole,
        state: AIHomeworkSchoolLmsBoundaryState,
        providerBlocked: Bool,
        lmsWriteBlocked: Bool,
        consentBlocked: Bool,
        directAnswerBlocked: Bool,
        ageRateBlocked: Bool,
        manualBlocked: Bool,
        returnedBlocked: Bool
    ) -> [AIHomeworkSchoolLmsBoundaryFinding] {
        var result: [AIHomeworkSchoolLmsBoundaryFinding] = []
        if viewerRole == .child {
            result.append(finding(.childVisibilityRedacted, .info, "孩子端已隐藏 provider、LMS、成人同意和 transcript 细节。", "visibility"))
        }
        if providerBlocked {
            result.append(finding(.providerRequestBlocked, .blocker, "真实 provider 请求被阻断。", "provider.mode"))
        }
        if lmsWriteBlocked || returnedBlocked {
            result.append(finding(.lmsWriteBlocked, .blocker, "LMS 写回、改作业或退回态被阻断。", "lms"))
        }
        if consentBlocked {
            result.append(finding(.consentRequired, .blocker, "需要家长同意、孩子 assent 和老师授权。", "consent"))
        }
        if directAnswerBlocked {
            result.append(finding(.directAnswerBlocked, .blocker, "直接答案或不安全 transcript 已被阻断。", "guidance"))
            result.append(finding(.rawTranscriptBlocked, .blocker, "原始 transcript 不会保存或发送。", "transcript"))
        }
        if ageRateBlocked {
            result.append(finding(.ageOrRateLimitBlocked, state == .blocked ? .blocker : .warning, "年龄或速率上限需要复核。", "ageRate"))
        }
        if manualBlocked {
            result.append(finding(.manualEscalationRequired, .blocker, "人工复核要求尚未路由。", "manualReview"))
        }
        return result
    }

    private func finding(
        _ code: AIHomeworkSchoolLmsBoundaryFindingCode,
        _ severity: AIHomeworkSchoolLmsBoundarySeverity,
        _ message: String,
        _ seed: String
    ) -> AIHomeworkSchoolLmsBoundaryFinding {
        AIHomeworkSchoolLmsBoundaryFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: stableRef("find", "\(code.rawValue):\(seed)")
        )
    }

    private func headline(
        state: AIHomeworkSchoolLmsBoundaryState,
        homework: SchoolHomework,
        viewerRole: AIHomeworkSchoolLmsBoundaryViewerRole
    ) -> String {
        if viewerRole == .child { return childCopy(state: state, directAnswerBlocked: false) }
        return "\(homework.subject.label) · \(state.label) · 真实 AI/LMS 仍关闭"
    }

    private func childCopy(state: AIHomeworkSchoolLmsBoundaryState, directAnswerBlocked: Bool) -> String {
        if directAnswerBlocked { return "这次只用提示和自检，不直接看答案。" }
        switch state {
        case .ready: return "可以继续按提示做，系统还不会真的连接 AI 或学校。"
        case .gated: return "这一步要等家长或老师再确认一下。"
        case .blocked: return "这条作业暂时不能继续，等大人看看。"
        case .empty: return "现在还没有要处理的作业。"
        }
    }

    private func stableRef(_ prefix: String, _ source: String) -> String {
        let input = "\(redactionSalt):\(prefix):\(source)"
        let seeds: [UInt64] = [0xcbf29ce484222325, 0x84222325cbf29ce4]
        let parts = seeds.map { seed -> String in
            var hash = seed
            for scalar in input.unicodeScalars {
                hash ^= UInt64(scalar.value)
                hash = hash &* 0x100000001b3
            }
            return String(String(hash, radix: 36).suffixPadded(to: 13))
        }
        return "\(prefix):\(parts.joined())"
    }

    private func hasUnsafeDisplayValues(_ values: [String]) -> Bool {
        // MobileSyncPayloadGuard is a pure regex guard; this path performs no I/O or external calls.
        let text = values.joined(separator: " ")
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let markers = [
            "child:", "family:", "school:", "teacher:", "guardian:", "homework:", "session:",
            "transcript:", "provider:", "model:", "source:", "prompt:", "answer key", "taskId",
            "claimId", "baseUrl", "endpoint=", "Bearer ", "api_key", "sk-", "192.168.",
            "local-model-host", ".local", "file://", "/Users/", "/Volumes/"
        ]
        return markers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func displayValues(_ snapshot: AIHomeworkSchoolLmsBoundarySnapshot) -> [String] {
        var values = [
            snapshot.headline,
            snapshot.childSafeCopy,
            snapshot.subjectLabel,
            snapshot.statusLabel,
            snapshot.provider.providerPublicRef,
            snapshot.lms.schoolPublicRef,
            snapshot.lms.homeworkPublicRef,
            snapshot.consent.consentPublicRef,
            snapshot.publicSummary.homeworkPublicRef,
            snapshot.publicSummary.boundaryPublicRef
        ]
        values.append(contentsOf: snapshot.findings.flatMap { [$0.publicRef, $0.message] })
        return values
    }
}

private extension String {
    func suffixPadded(to length: Int) -> String {
        if count >= length { return String(suffix(length)) }
        return String(repeating: "0", count: length - count) + self
    }
}

private extension AIHomeworkSchoolLmsBoundarySnapshot {
    func replacingFindings(_ findings: [AIHomeworkSchoolLmsBoundaryFinding]) -> AIHomeworkSchoolLmsBoundarySnapshot {
        var copy = self
        copy.findings = findings
        copy.state = .blocked
        copy.publicSummary = AIHomeworkSchoolLmsBoundaryPublicSummary(
            generatedAt: publicSummary.generatedAt,
            viewerRole: publicSummary.viewerRole,
            state: .blocked,
            homeworkPublicRef: publicSummary.homeworkPublicRef,
            boundaryPublicRef: publicSummary.boundaryPublicRef,
            findingCodes: findings.map(\.code),
            providerRequestAllowed: false,
            lmsReadOnly: false,
            manualReviewRequired: true
        )
        return copy
    }
}
