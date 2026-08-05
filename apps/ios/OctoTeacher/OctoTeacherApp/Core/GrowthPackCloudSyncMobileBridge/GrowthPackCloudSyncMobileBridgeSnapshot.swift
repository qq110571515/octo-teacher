import Foundation

/// iOS 端「成长包云同步移动端只读桥接」本地投影。
///
/// 这是未来真实云同步/StoreKit/权限闸门接入前的手机端 read model：只组合本地 mock
/// 安装权益、移动权限闸门、离线队列/重放、同意撤回与成长积分冻结信号；不调用真实云端、
/// 市场、支付、账本、通知、AI、LMS、学校系统或设备控制。
enum GrowthPackCloudSyncMobileBridgeViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case relative
    case creator
    case operations

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        case .creator: return "创作者"
        case .operations: return "运营"
        }
    }
}

enum GrowthPackCloudSyncMobileBridgeCloudState: String, Equatable {
    case fresh
    case stale
    case localDraftPending = "local_draft_pending"
    case refunded
    case revoked
    case delisted

    var label: String {
        switch self {
        case .fresh: return "云镜像正常"
        case .stale: return "云镜像过期"
        case .localDraftPending: return "本地草稿待同步"
        case .refunded: return "退款复核"
        case .revoked: return "权益撤回"
        case .delisted: return "成长包下架"
        }
    }
}

enum GrowthPackCloudSyncMobileBridgeState: String, Equatable {
    case ready
    case reviewRequired = "review_required"
    case conflict
    case frozen
    case revoked
    case blocked

    var label: String {
        switch self {
        case .ready: return "可查看"
        case .reviewRequired: return "需要复核"
        case .conflict: return "同步冲突"
        case .frozen: return "已冻结"
        case .revoked: return "已撤权"
        case .blocked: return "已阻断"
        }
    }
}

enum GrowthPackCloudSyncMobileBridgeSurface: String, Equatable {
    case homeCard = "home_card"
    case detail
    case offlinePrompt = "offline_prompt"
    case permissionGate = "permission_gate"
    case operationsSummary = "operations_summary"

    var title: String {
        switch self {
        case .homeCard: return "首页卡片"
        case .detail: return "成长包详情"
        case .offlinePrompt: return "离线提示"
        case .permissionGate: return "权限闸门"
        case .operationsSummary: return "运营摘要"
        }
    }
}

enum GrowthPackCloudSyncMobileBridgeFindingCode: String, Equatable {
    case bridgeOK = "GROWTH_PACK_CLOUD_SYNC_MOBILE_BRIDGE_OK"
    case roleVisibilityApplied = "ROLE_VISIBILITY_APPLIED"
    case childSensitiveFieldsHidden = "CHILD_SENSITIVE_FIELDS_HIDDEN"
    case nonGuardianSensitiveFieldsHidden = "NON_GUARDIAN_SENSITIVE_FIELDS_HIDDEN"
    case localDraftPending = "LOCAL_DRAFT_PENDING"
    case cloudMirrorStale = "CLOUD_MIRROR_STALE"
    case refundOrRevocationBlocked = "REFUND_OR_REVOCATION_BLOCKED"
    case packDelisted = "PACK_DELISTED"
    case offlineConflict = "OFFLINE_CONFLICT"
    case consentRevoked = "CONSENT_REVOKED"
    case creditFrozen = "CREDIT_FROZEN"
    case permissionGateBlocked = "PERMISSION_GATE_BLOCKED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
}

enum GrowthPackCloudSyncMobileBridgeSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

struct GrowthPackCloudSyncMobileBridgeInput: Equatable {
    var generatedAt: String
    var installSnapshot: GrowthPackInstallSnapshot
    var permissionReport: MobilePlatformPermissionGatewayReadModelReport
    var offlineStatus: MobileOfflinePublicStatus
    var offlineReport: MobileOfflineReplayReport
    var cloudState: GrowthPackCloudSyncMobileBridgeCloudState
    var consentRevoked: Bool
    var creditFrozen: Bool
    var unsafePayload: [String]
}

struct GrowthPackCloudSyncMobileBridgeVisibility: Equatable {
    var viewerRole: GrowthPackCloudSyncMobileBridgeViewerRole
    var canSeeHome: Bool
    var canSeeDetail: Bool
    var canSeeOfflinePrompt: Bool
    var canSeeGuardianReview: Bool
    var canSeeOperationsSummary: Bool

    var hidesSensitiveFields: Bool {
        viewerRole != .guardian
    }
}

struct GrowthPackCloudSyncMobileBridgeCard: Identifiable, Equatable {
    var publicCardRef: String
    var surface: GrowthPackCloudSyncMobileBridgeSurface
    var title: String
    var detail: String
    var badge: String
    var state: GrowthPackCloudSyncMobileBridgeState
    var actionRequired: Bool

    let showsPrice = false
    let showsOrderOrEntitlement = false
    let showsRefundInternalReason = false
    let showsGuardianConsentDetail = false
    let showsCreditAmount = false
    let showsCloudInternalState = false
    let showsCrossChildContent = false
    let writesCloud = false
    let writesEntitlement = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false

    var id: String { publicCardRef }
}

struct GrowthPackCloudSyncMobileBridgeDetailItem: Identifiable, Equatable {
    var publicItemRef: String
    var surface: GrowthPackCloudSyncMobileBridgeSurface
    var title: String
    var detail: String
    var visibleToViewer: Bool
    var actionRequired: Bool

    let showsPrice = false
    let showsOrderOrEntitlement = false
    let showsRefundInternalReason = false
    let showsGuardianConsentDetail = false
    let showsCreditAmount = false
    let showsCloudInternalState = false
    let showsCrossChildContent = false
    let writesSystem = false

    var id: String { publicItemRef }
}

struct GrowthPackCloudSyncMobileBridgeFinding: Identifiable, Equatable {
    var code: GrowthPackCloudSyncMobileBridgeFindingCode
    var severity: GrowthPackCloudSyncMobileBridgeSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct GrowthPackCloudSyncMobileBridgePublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: GrowthPackCloudSyncMobileBridgeViewerRole
    var state: GrowthPackCloudSyncMobileBridgeState
    var bridgePublicRef: String
    var visibleCardCount: Int
    var visibleDetailCount: Int
    var actionRequiredCount: Int
    var offlineAttentionCount: Int
    var findingCodes: [GrowthPackCloudSyncMobileBridgeFindingCode]

    let callsCloud = false
    let writesCloud = false
    let chargesPayment = false
    let createsOrder = false
    let writesMarketplace = false
    let writesEntitlement = false
    let downloadsAssets = false
    let sendsNotification = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let callsAi = false
    let callsLms = false
    let writesSchoolSystem = false
}

struct GrowthPackCloudSyncMobileBridgeSideEffects: Equatable {
    let callsCloud = false
    let writesCloud = false
    let chargesPayment = false
    let createsOrder = false
    let writesMarketplace = false
    let writesEntitlement = false
    let downloadsAssets = false
    let sendsNotification = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let callsAi = false
    let callsLms = false
    let writesSchoolSystem = false

    var hasTriggeredSideEffect: Bool {
        callsCloud || writesCloud || chargesPayment || createsOrder || writesMarketplace
            || writesEntitlement || downloadsAssets || sendsNotification || writesLedger
            || grantsCredit || unlocksDevice || callsAi || callsLms || writesSchoolSystem
    }
}

struct GrowthPackCloudSyncMobileBridgeSnapshot: Equatable {
    var generatedAt: String
    var viewerRole: GrowthPackCloudSyncMobileBridgeViewerRole
    var state: GrowthPackCloudSyncMobileBridgeState
    var headline: String
    var visibility: GrowthPackCloudSyncMobileBridgeVisibility
    var homeCards: [GrowthPackCloudSyncMobileBridgeCard]
    var detailItems: [GrowthPackCloudSyncMobileBridgeDetailItem]
    var offlinePrompt: GrowthPackCloudSyncMobileBridgeDetailItem?
    var findings: [GrowthPackCloudSyncMobileBridgeFinding]
    var publicSummary: GrowthPackCloudSyncMobileBridgePublicSummary
    var sideEffects: GrowthPackCloudSyncMobileBridgeSideEffects
}

struct GrowthPackCloudSyncMobileBridgeBuilder {
    var redactionSalt = "growth-pack-cloud-sync-mobile-bridge-ios-v1"

    func build(
        viewerRole: GrowthPackCloudSyncMobileBridgeViewerRole,
        input: GrowthPackCloudSyncMobileBridgeInput? = nil
    ) -> GrowthPackCloudSyncMobileBridgeSnapshot {
        let resolvedInput = input ?? defaultInput(for: viewerRole)
        let visibility = visibility(for: viewerRole)
        if hasUnsafeInput(resolvedInput) {
            return safeFallback(viewerRole: viewerRole, visibility: visibility, generatedAt: resolvedInput.generatedAt)
        }

        var findings = findings(for: resolvedInput, role: viewerRole)
        let state = state(for: resolvedInput, findings: findings)
        if !findings.contains(where: { $0.severity == .blocker || $0.severity == .warning }) {
            findings.insert(finding(.bridgeOK, .ok, "成长包云同步移动端桥接只读投影就绪。", "ok"), at: 0)
        }
        findings.insert(finding(.roleVisibilityApplied, .info, "已按 \(viewerRole.label) 视角裁剪云同步桥接信息。", viewerRole.rawValue), at: 0)
        if visibility.hidesSensitiveFields {
            findings.append(finding(.nonGuardianSensitiveFieldsHidden, .info, "当前视角已隐藏订单、权益、退款、同意、成长积分和云端内部细节。", "visibility"))
        }
        if viewerRole == .child {
            findings.append(finding(.childSensitiveFieldsHidden, .info, "孩子端只看下一步，不展示价格、订单、权益、成长积分金额或云端内部状态。", "child"))
        }
        findings = unique(findings)

        let cards = homeCards(input: resolvedInput, state: state, role: viewerRole, visibility: visibility)
        let details = detailItems(input: resolvedInput, state: state, role: viewerRole, visibility: visibility)
        let offline = offlinePrompt(input: resolvedInput, state: state, role: viewerRole, visibility: visibility)
        let snapshot = GrowthPackCloudSyncMobileBridgeSnapshot(
            generatedAt: resolvedInput.generatedAt,
            viewerRole: viewerRole,
            state: state,
            headline: headline(state: state, role: viewerRole),
            visibility: visibility,
            homeCards: cards,
            detailItems: details,
            offlinePrompt: offline,
            findings: visibleFindings(findings, role: viewerRole),
            publicSummary: publicSummary(
                input: resolvedInput,
                role: viewerRole,
                state: state,
                cards: cards,
                details: details,
                offline: offline,
                findings: findings
            ),
            sideEffects: GrowthPackCloudSyncMobileBridgeSideEffects()
        )
        return redacts(snapshot) ? snapshot : safeFallback(viewerRole: viewerRole, visibility: visibility, generatedAt: resolvedInput.generatedAt)
    }

    func defaultInput(for role: GrowthPackCloudSyncMobileBridgeViewerRole) -> GrowthPackCloudSyncMobileBridgeInput {
        let installSnapshot = GrowthPackInstallEntitlementBuilder().build(viewerRole: installRole(for: role))
        let permissionReport = MobilePlatformPermissionGatewayAdapter().buildReadModel(viewerRole: permissionRole(for: role))
        return GrowthPackCloudSyncMobileBridgeInput(
            generatedAt: "2026-06-24T14:30:00Z",
            installSnapshot: installSnapshot,
            permissionReport: permissionReport,
            offlineStatus: MobileOfflinePublicStatus(pendingCount: 2, conflictCount: role == .guardian ? 1 : 0, rolledBackCount: 0),
            offlineReport: .empty,
            cloudState: role == .guardian ? .localDraftPending : .fresh,
            consentRevoked: false,
            creditFrozen: role == .guardian,
            unsafePayload: []
        )
    }

    func redacts(_ snapshot: GrowthPackCloudSyncMobileBridgeSnapshot) -> Bool {
        let values = displayValues(snapshot)
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ").lowercased()
        let blockedMarkers = [
            "child:", "family:", "school:", "teacher:", "relative:", "guardian:", "pack:",
            "creator:", "order:", "entitlement:", "refund:", "ledger:", "credit:", "cloud:",
            "taskid", "claimid", "provider:", "model:", "token", "secret", "baseurl",
            "http://", "https://", "file://", "/users/", "/volumes/", "192.168."
        ]
        if blockedMarkers.contains(where: { joined.contains($0) }) { return false }
        let blockedPatterns = [
            #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#,
            #"(?i)\b[0-9a-f]{24,}\b"#,
            #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#
        ]
        return !blockedPatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func visibility(for role: GrowthPackCloudSyncMobileBridgeViewerRole) -> GrowthPackCloudSyncMobileBridgeVisibility {
        switch role {
        case .child:
            return GrowthPackCloudSyncMobileBridgeVisibility(viewerRole: role, canSeeHome: true, canSeeDetail: true, canSeeOfflinePrompt: true, canSeeGuardianReview: false, canSeeOperationsSummary: false)
        case .guardian:
            return GrowthPackCloudSyncMobileBridgeVisibility(viewerRole: role, canSeeHome: true, canSeeDetail: true, canSeeOfflinePrompt: true, canSeeGuardianReview: true, canSeeOperationsSummary: false)
        case .relative:
            return GrowthPackCloudSyncMobileBridgeVisibility(viewerRole: role, canSeeHome: true, canSeeDetail: false, canSeeOfflinePrompt: false, canSeeGuardianReview: false, canSeeOperationsSummary: false)
        case .creator:
            return GrowthPackCloudSyncMobileBridgeVisibility(viewerRole: role, canSeeHome: true, canSeeDetail: true, canSeeOfflinePrompt: false, canSeeGuardianReview: false, canSeeOperationsSummary: false)
        case .operations:
            return GrowthPackCloudSyncMobileBridgeVisibility(viewerRole: role, canSeeHome: false, canSeeDetail: false, canSeeOfflinePrompt: false, canSeeGuardianReview: false, canSeeOperationsSummary: true)
        }
    }

    private func state(
        for input: GrowthPackCloudSyncMobileBridgeInput,
        findings: [GrowthPackCloudSyncMobileBridgeFinding]
    ) -> GrowthPackCloudSyncMobileBridgeState {
        if findings.contains(where: { $0.severity == .blocker }) { return .blocked }
        if input.cloudState == .revoked { return .revoked }
        if input.cloudState == .refunded || input.creditFrozen || input.consentRevoked { return .frozen }
        if input.offlineStatus.hasAttention || input.offlineReport.conflictCount > 0 || input.offlineReport.rolledBackCount > 0 { return .conflict }
        if findings.contains(where: { $0.severity == .warning }) { return .reviewRequired }
        return .ready
    }

    private func findings(
        for input: GrowthPackCloudSyncMobileBridgeInput,
        role: GrowthPackCloudSyncMobileBridgeViewerRole
    ) -> [GrowthPackCloudSyncMobileBridgeFinding] {
        var result: [GrowthPackCloudSyncMobileBridgeFinding] = []
        if input.cloudState == .localDraftPending {
            result.append(finding(.localDraftPending, .warning, "本地安装草稿等待云镜像确认。", "draft"))
        }
        if input.cloudState == .stale {
            result.append(finding(.cloudMirrorStale, .warning, "云镜像已过期，需要刷新后再判断。", "stale"))
        }
        if input.cloudState == .refunded || input.cloudState == .revoked {
            result.append(finding(.refundOrRevocationBlocked, .blocker, "退款或撤权后本地运行必须冻结。", "revoked"))
        }
        if input.cloudState == .delisted {
            result.append(finding(.packDelisted, .blocker, "成长包下架后不能新装或继续同步安装草稿。", "delisted"))
        }
        if input.offlineStatus.hasAttention || input.offlineReport.conflictCount > 0 || input.offlineReport.rolledBackCount > 0 {
            result.append(finding(.offlineConflict, .warning, "离线回放存在冲突或回滚，需要家长复核。", "offline"))
        }
        if input.consentRevoked {
            result.append(finding(.consentRevoked, .blocker, "家庭同意撤回后不得继续同步或建议解锁。", "consent"))
        }
        if input.creditFrozen {
            result.append(finding(.creditFrozen, .warning, "成长积分建议冻结中，不能兑换设备时间。", "credit-frozen"))
        }
        if !input.permissionReport.accepted || input.permissionReport.state == .blocked {
            result.append(finding(.permissionGateBlocked, .blocker, "移动权限闸门阻断成长包云同步展示。", "permission"))
        }
        return result
    }

    private func homeCards(
        input: GrowthPackCloudSyncMobileBridgeInput,
        state: GrowthPackCloudSyncMobileBridgeState,
        role: GrowthPackCloudSyncMobileBridgeViewerRole,
        visibility: GrowthPackCloudSyncMobileBridgeVisibility
    ) -> [GrowthPackCloudSyncMobileBridgeCard] {
        if visibility.canSeeOperationsSummary {
            return [
                card(.operationsSummary, title: "脱敏同步摘要", detail: "可见 \(input.installSnapshot.publicSummary.visiblePackCount) · 待关注 \(input.installSnapshot.publicSummary.gatedCount + input.installSnapshot.publicSummary.blockedCount) · 离线 \(input.offlineStatus.conflictCount + input.offlineStatus.rolledBackCount)", badge: state.label, state: state, actionRequired: state != .ready)
            ]
        }
        guard visibility.canSeeHome else { return [] }
        return [
            card(.homeCard, title: "成长包云同步", detail: homeDetail(input: input, role: role), badge: state.label, state: state, actionRequired: state != .ready),
            card(.permissionGate, title: "权限闸门", detail: input.permissionReport.state == .blocked ? "权限闸门阻断，等待家长处理。" : "权限闸门保持只读通过。", badge: input.permissionReport.state.rawValue, state: input.permissionReport.state == .blocked ? .blocked : .ready, actionRequired: input.permissionReport.state != .ready)
        ]
    }

    private func detailItems(
        input: GrowthPackCloudSyncMobileBridgeInput,
        state: GrowthPackCloudSyncMobileBridgeState,
        role: GrowthPackCloudSyncMobileBridgeViewerRole,
        visibility: GrowthPackCloudSyncMobileBridgeVisibility
    ) -> [GrowthPackCloudSyncMobileBridgeDetailItem] {
        guard visibility.canSeeDetail || visibility.canSeeOperationsSummary else { return [] }
        if visibility.canSeeOperationsSummary {
            return [
                detail(.operationsSummary, title: "只读计数", detail: "可见包 \(input.installSnapshot.publicSummary.visiblePackCount)，离线关注 \(input.offlineStatus.conflictCount + input.offlineStatus.rolledBackCount)。", visible: true, actionRequired: state != .ready)
            ]
        }
        var items = [
            detail(.detail, title: "详情状态", detail: detailCopy(input: input, role: role), visible: true, actionRequired: state != .ready),
            detail(.permissionGate, title: "共享权限模块", detail: "可见模块 \(input.permissionReport.modules.filter { $0.visibility != .hidden }.count)，所有模块只读。", visible: true, actionRequired: input.permissionReport.state != .ready)
        ]
        if visibility.canSeeGuardianReview {
            items.append(detail(.detail, title: "家长复核", detail: "退款、撤权、同意撤回和成长积分冻结只生成复核提示，不自动修复。", visible: true, actionRequired: state != .ready))
        }
        return items
    }

    private func offlinePrompt(
        input: GrowthPackCloudSyncMobileBridgeInput,
        state: GrowthPackCloudSyncMobileBridgeState,
        role: GrowthPackCloudSyncMobileBridgeViewerRole,
        visibility: GrowthPackCloudSyncMobileBridgeVisibility
    ) -> GrowthPackCloudSyncMobileBridgeDetailItem? {
        guard visibility.canSeeOfflinePrompt else { return nil }
        let attention = input.offlineStatus.conflictCount + input.offlineStatus.rolledBackCount + input.offlineReport.conflictCount + input.offlineReport.rolledBackCount
        let text = attention > 0
            ? "有 \(attention) 个离线同步问题，先由家长复核。"
            : input.offlineStatus.pendingCount > 0 ? "有 \(input.offlineStatus.pendingCount) 个本地草稿等待同步。" : "离线同步没有阻断。"
        return detail(.offlinePrompt, title: "离线同步", detail: text, visible: true, actionRequired: attention > 0 || input.offlineStatus.pendingCount > 0)
    }

    private func publicSummary(
        input: GrowthPackCloudSyncMobileBridgeInput,
        role: GrowthPackCloudSyncMobileBridgeViewerRole,
        state: GrowthPackCloudSyncMobileBridgeState,
        cards: [GrowthPackCloudSyncMobileBridgeCard],
        details: [GrowthPackCloudSyncMobileBridgeDetailItem],
        offline: GrowthPackCloudSyncMobileBridgeDetailItem?,
        findings: [GrowthPackCloudSyncMobileBridgeFinding]
    ) -> GrowthPackCloudSyncMobileBridgePublicSummary {
        GrowthPackCloudSyncMobileBridgePublicSummary(
            generatedAt: input.generatedAt,
            viewerRole: role,
            state: state,
            bridgePublicRef: publicRef("gpcm-bridge", "\(role.rawValue)-\(input.generatedAt)"),
            visibleCardCount: cards.count,
            visibleDetailCount: details.count + (offline == nil ? 0 : 1),
            actionRequiredCount: cards.filter(\.actionRequired).count + details.filter(\.actionRequired).count + ((offline?.actionRequired ?? false) ? 1 : 0),
            offlineAttentionCount: input.offlineStatus.conflictCount + input.offlineStatus.rolledBackCount + input.offlineReport.conflictCount + input.offlineReport.rolledBackCount,
            findingCodes: findings.map(\.code)
        )
    }

    private func visibleFindings(
        _ findings: [GrowthPackCloudSyncMobileBridgeFinding],
        role: GrowthPackCloudSyncMobileBridgeViewerRole
    ) -> [GrowthPackCloudSyncMobileBridgeFinding] {
        if role == .child {
            return findings.map { finding in
                if finding.code == .refundOrRevocationBlocked || finding.code == .consentRevoked || finding.code == .creditFrozen {
                    return self.finding(finding.code, finding.severity, "需要家长复核后才能继续。", finding.publicRef)
                }
                return finding
            }
        }
        return findings
    }

    private func headline(state: GrowthPackCloudSyncMobileBridgeState, role: GrowthPackCloudSyncMobileBridgeViewerRole) -> String {
        if role == .operations { return "成长包云同步脱敏摘要" }
        switch state {
        case .ready: return "成长包同步状态正常"
        case .reviewRequired: return "成长包同步需要复核"
        case .conflict: return "成长包离线同步有冲突"
        case .frozen: return "成长包权益或成长积分已冻结"
        case .revoked: return "成长包权益已撤回"
        case .blocked: return "成长包云同步已阻断"
        }
    }

    private func homeDetail(input: GrowthPackCloudSyncMobileBridgeInput, role: GrowthPackCloudSyncMobileBridgeViewerRole) -> String {
        if role == .child {
            if input.cloudState == .fresh { return "可以继续看已开放的成长包下一步。" }
            return "等待家长确认同步状态后再继续。"
        }
        if role == .creator {
            return "只显示版本和上架相关的同步状态，不显示家庭权益。"
        }
        if role == .relative {
            return "只读查看家长开放的成长包摘要。"
        }
        return "\(input.cloudState.label) · \(input.offlineStatus.headline)"
    }

    private func detailCopy(input: GrowthPackCloudSyncMobileBridgeInput, role: GrowthPackCloudSyncMobileBridgeViewerRole) -> String {
        if role == .child {
            return "这里只告诉你能不能继续，不展示订单、权益或成长积分金额。"
        }
        if role == .creator {
            return "创作者只看公开生命周期，不看家庭、孩子或权益明细。"
        }
        return "云镜像、离线草稿、同意撤回和成长积分冻结都只生成只读提示。"
    }

    private func card(
        _ surface: GrowthPackCloudSyncMobileBridgeSurface,
        title: String,
        detail: String,
        badge: String,
        state: GrowthPackCloudSyncMobileBridgeState,
        actionRequired: Bool
    ) -> GrowthPackCloudSyncMobileBridgeCard {
        GrowthPackCloudSyncMobileBridgeCard(
            publicCardRef: publicRef("gpcm-card", "\(surface.rawValue)-\(title)-\(badge)"),
            surface: surface,
            title: sanitize(title, fallback: surface.title),
            detail: sanitize(detail, fallback: "请查看对应只读状态。"),
            badge: sanitize(badge, fallback: state.label),
            state: state,
            actionRequired: actionRequired
        )
    }

    private func detail(
        _ surface: GrowthPackCloudSyncMobileBridgeSurface,
        title: String,
        detail: String,
        visible: Bool,
        actionRequired: Bool
    ) -> GrowthPackCloudSyncMobileBridgeDetailItem {
        GrowthPackCloudSyncMobileBridgeDetailItem(
            publicItemRef: publicRef("gpcm-item", "\(surface.rawValue)-\(title)-\(detail)"),
            surface: surface,
            title: sanitize(title, fallback: surface.title),
            detail: sanitize(detail, fallback: "请查看对应只读状态。"),
            visibleToViewer: visible,
            actionRequired: actionRequired
        )
    }

    private func finding(
        _ code: GrowthPackCloudSyncMobileBridgeFindingCode,
        _ severity: GrowthPackCloudSyncMobileBridgeSeverity,
        _ message: String,
        _ seed: String
    ) -> GrowthPackCloudSyncMobileBridgeFinding {
        GrowthPackCloudSyncMobileBridgeFinding(
            code: code,
            severity: severity,
            message: sanitize(message, fallback: "已进入只读安全提示。"),
            publicRef: seed.hasPrefix("gpcm-finding-") ? seed : publicRef("gpcm-finding", "\(code.rawValue)-\(seed)")
        )
    }

    private func unique(_ findings: [GrowthPackCloudSyncMobileBridgeFinding]) -> [GrowthPackCloudSyncMobileBridgeFinding] {
        var seen: Set<GrowthPackCloudSyncMobileBridgeFindingCode> = []
        return findings.filter { seen.insert($0.code).inserted }
    }

    private func hasUnsafeInput(_ input: GrowthPackCloudSyncMobileBridgeInput) -> Bool {
        MobileSyncPayloadGuard.isUnsafe(input.unsafePayload)
    }

    private func sanitize(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if MobileSyncPayloadGuard.isUnsafe(trimmed) { return fallback }
        let lowercased = trimmed.lowercased()
        let blockedMarkers = [
            "child:", "family:", "school:", "teacher:", "relative:", "guardian:", "pack:",
            "creator:", "order:", "entitlement:", "refund:", "ledger:", "credit:", "cloud:",
            "taskid", "claimid", "provider:", "model:", "token", "secret",
            "http://", "https://", "file://", "/users/", "/volumes/", "192.168."
        ]
        if blockedMarkers.contains(where: { lowercased.contains($0) }) { return fallback }
        return trimmed
    }

    private func displayValues(_ snapshot: GrowthPackCloudSyncMobileBridgeSnapshot) -> [String] {
        var values = [snapshot.generatedAt, snapshot.viewerRole.rawValue, snapshot.state.rawValue, snapshot.headline]
        for card in snapshot.homeCards {
            values.append(contentsOf: [card.publicCardRef, card.surface.rawValue, card.title, card.detail, card.badge, card.state.rawValue])
        }
        for item in snapshot.detailItems {
            values.append(contentsOf: [item.publicItemRef, item.surface.rawValue, item.title, item.detail])
        }
        if let offlinePrompt = snapshot.offlinePrompt {
            values.append(contentsOf: [offlinePrompt.publicItemRef, offlinePrompt.surface.rawValue, offlinePrompt.title, offlinePrompt.detail])
        }
        for finding in snapshot.findings {
            values.append(contentsOf: [finding.code.rawValue, finding.severity.rawValue, finding.message, finding.publicRef])
        }
        values.append(contentsOf: [
            snapshot.publicSummary.bridgePublicRef,
            "\(snapshot.publicSummary.visibleCardCount)",
            "\(snapshot.publicSummary.visibleDetailCount)",
            "\(snapshot.publicSummary.actionRequiredCount)",
            "\(snapshot.publicSummary.offlineAttentionCount)"
        ])
        return values
    }

    private func installRole(for role: GrowthPackCloudSyncMobileBridgeViewerRole) -> GrowthPackInstallViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .operations: return .guardian
        case .relative: return .relative
        case .creator: return .creator
        }
    }

    private func permissionRole(for role: GrowthPackCloudSyncMobileBridgeViewerRole) -> MobilePlatformPermissionGatewayViewerRole {
        switch role {
        case .child: return .child
        case .guardian, .creator, .operations: return .guardian
        case .relative: return .relative
        }
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

    private func safeFallback(
        viewerRole: GrowthPackCloudSyncMobileBridgeViewerRole,
        visibility: GrowthPackCloudSyncMobileBridgeVisibility,
        generatedAt: String
    ) -> GrowthPackCloudSyncMobileBridgeSnapshot {
        let fallbackFinding = finding(.publicSummaryLeak, .blocker, "成长包云同步桥接未通过公开脱敏检查，已进入安全保护模式。", "fallback")
        return GrowthPackCloudSyncMobileBridgeSnapshot(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            state: .blocked,
            headline: "成长包云同步已进入安全保护模式",
            visibility: visibility,
            homeCards: [],
            detailItems: [],
            offlinePrompt: nil,
            findings: [fallbackFinding],
            publicSummary: GrowthPackCloudSyncMobileBridgePublicSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                state: .blocked,
                bridgePublicRef: publicRef("gpcm-bridge", "fallback-\(viewerRole.rawValue)"),
                visibleCardCount: 0,
                visibleDetailCount: 0,
                actionRequiredCount: 0,
                offlineAttentionCount: 0,
                findingCodes: [.publicSummaryLeak]
            ),
            sideEffects: GrowthPackCloudSyncMobileBridgeSideEffects()
        )
    }
}
