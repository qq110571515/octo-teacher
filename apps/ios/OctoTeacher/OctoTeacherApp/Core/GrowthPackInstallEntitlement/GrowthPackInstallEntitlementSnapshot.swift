import Foundation

/// iOS 端「成长包安装权益 / 市场入口」只读快照。
///
/// 把成长包市场、购买意图、entitlement、退款/撤权、版本迁移和年龄/权限门禁投影到手机端。
/// 这里不做真实购买、不接真实支付/市场/云端/CDN/通知/账本/设备/AI/学校系统；所有输出都只是
/// 本地确定性 mock，供家长端选择和孩子端加载前的安全边界验证。
enum GrowthPackInstallViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case relative
    case creator

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .relative: return "亲友"
        case .creator: return "创作者"
        }
    }

    var note: String {
        switch self {
        case .child:
            return "孩子只看到可运行摘要和下一步，不展示价格、订单、权益 ID 或创作者内部收益。"
        case .guardian:
            return "家长可见购买、权益、退款、权限与阻断原因，但仍不能在本地直接购买或发成长积分。"
        case .relative:
            return "亲友只读，只看家庭允许公开的成长包摘要，不看购买和权益细节。"
        case .creator:
            return "创作者只看上架/版本/审核状态，不看单个家庭、孩子、订单或权益。"
        }
    }
}

enum GrowthPackMarketListingState: String, Equatable {
    case listed
    case underReview = "under_review"
    case delisted

    var label: String {
        switch self {
        case .listed: return "已上架"
        case .underReview: return "审核中"
        case .delisted: return "已下架"
        }
    }
}

enum GrowthPackEntitlementState: String, Equatable {
    case none
    case pendingGuardianApproval = "pending_guardian_approval"
    case active
    case refunded
    case revoked
    case expired

    var label: String {
        switch self {
        case .none: return "未授权"
        case .pendingGuardianApproval: return "待家长确认"
        case .active: return "已授权"
        case .refunded: return "已退款"
        case .revoked: return "已撤权"
        case .expired: return "已过期"
        }
    }
}

enum GrowthPackInstallDecisionState: String, Equatable {
    case installable
    case installed
    case pendingGuardianConfirmation = "pending_guardian_confirmation"
    case frozen
    case blocked
    case hidden

    var label: String {
        switch self {
        case .installable: return "可安装"
        case .installed: return "已安装"
        case .pendingGuardianConfirmation: return "待家长确认"
        case .frozen: return "已冻结"
        case .blocked: return "已阻断"
        case .hidden: return "不可见"
        }
    }
}

enum GrowthPackInstallFindingCode: String, Equatable {
    case installProjectionReady = "GROWTH_PACK_INSTALL_ENTITLEMENT_OK"
    case childVisibilityRedacted = "CHILD_INSTALL_VISIBILITY_REDACTED"
    case relativeVisibilityRedacted = "RELATIVE_INSTALL_VISIBILITY_REDACTED"
    case creatorVisibilityRedacted = "CREATOR_INSTALL_VISIBILITY_REDACTED"
    case guardianReviewRequired = "GUARDIAN_REVIEW_REQUIRED"
    case listingDelisted = "MARKET_LISTING_DELISTED"
    case entitlementRefundedOrRevoked = "ENTITLEMENT_REFUNDED_OR_REVOKED"
    case entitlementExpired = "ENTITLEMENT_EXPIRED"
    case agePolicyBlocked = "AGE_POLICY_BLOCKED"
    case permissionPolicyBlocked = "PERMISSION_POLICY_BLOCKED"
    case versionMigrationAvailable = "VERSION_MIGRATION_AVAILABLE"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
    case publicSummaryLeak = "PUBLIC_SUMMARY_LEAK"
    case sideEffectFree = "SIDE_EFFECT_FREE"
}

enum GrowthPackInstallSeverity: String, Equatable {
    case ok
    case info
    case warning
    case blocker
}

struct GrowthPackInstallCatalogInput: Equatable {
    var generatedAt: String
    var familySeed: String
    var childSeed: String
    var childAge: Int
    var packs: [GrowthPackInstallPackInput]
}

struct GrowthPackInstallPackInput: Equatable {
    var packSeed: String
    var creatorSeed: String
    var orderSeed: String?
    var entitlementSeed: String?
    var title: String
    var summary: String
    var category: String
    var creatorDisplayName: String
    var version: String
    var latestVersion: String
    var minAge: Int
    var maxAge: Int
    var requiredPermissions: [String]
    var permissionsGranted: Bool
    var listingState: GrowthPackMarketListingState
    var entitlementState: GrowthPackEntitlementState
    var priceLabel: String
    var refundWindowOpen: Bool
    var canMigrateVersion: Bool
}

struct GrowthPackInstallVisibility: Equatable {
    var viewerRole: GrowthPackInstallViewerRole
    var canSeeCatalog: Bool
    var canSeePrice: Bool
    var canSeeOrderAndEntitlement: Bool
    var canSeeGuardianReason: Bool
    var canSeeCreatorListingState: Bool
}

struct GrowthPackInstallDecision: Identifiable, Equatable {
    var packPublicRef: String
    var creatorPublicRef: String
    var state: GrowthPackInstallDecisionState
    var title: String
    var summary: String
    var category: String
    var creatorDisplayName: String
    var versionLabel: String
    var ageLabel: String
    var requiredPermissionLabels: [String]
    var listingLabel: String?
    var entitlementLabel: String?
    var priceLabel: String?
    var orderPublicRef: String?
    var entitlementPublicRef: String?
    var reason: String
    var nextAction: String
    var migrationNotice: String?
    var refundWindowOpen: Bool

    let chargesPayment = false
    let writesMarketplace = false
    let writesEntitlement = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let callsCloud = false

    var id: String { packPublicRef }
}

struct GrowthPackInstallFinding: Identifiable, Equatable {
    var code: GrowthPackInstallFindingCode
    var severity: GrowthPackInstallSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

struct GrowthPackInstallPublicSummary: Equatable {
    var generatedAt: String
    var viewerRole: GrowthPackInstallViewerRole
    var catalogPublicRef: String
    var familyPublicRef: String
    var childPublicRef: String
    var visiblePackCount: Int
    var installableCount: Int
    var installedCount: Int
    var gatedCount: Int
    var blockedCount: Int
    var findingCodes: [GrowthPackInstallFindingCode]

    let chargesPayment = false
    let createsOrder = false
    let writesMarketplace = false
    let writesEntitlement = false
    let writesBilling = false
    let callsCloud = false
    let fetchesCdn = false
    let sendsNotification = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let callsAi = false
    let writesSchoolSystem = false
}

struct GrowthPackInstallSnapshot: CustomStringConvertible, Equatable {
    var generatedAt: String
    var viewerRole: GrowthPackInstallViewerRole
    var headline: String
    var audienceNote: String
    var visibility: GrowthPackInstallVisibility
    var decisions: [GrowthPackInstallDecision]
    var findings: [GrowthPackInstallFinding]
    var publicSummary: GrowthPackInstallPublicSummary

    var description: String {
        let decisionText = decisions.map { decision in
            [
                decision.packPublicRef,
                decision.creatorPublicRef,
                decision.state.rawValue,
                decision.title,
                decision.summary,
                decision.category,
                decision.creatorDisplayName,
                decision.versionLabel,
                decision.ageLabel,
                decision.listingLabel ?? "",
                decision.entitlementLabel ?? "",
                decision.priceLabel ?? "",
                decision.orderPublicRef ?? "",
                decision.entitlementPublicRef ?? "",
                decision.reason,
                decision.nextAction,
                decision.migrationNotice ?? ""
            ].joined(separator: " ")
        }
        let findingText = findings.map { "\($0.code.rawValue) \($0.severity.rawValue) \($0.message) \($0.publicRef)" }
        let summaryText = [
            publicSummary.catalogPublicRef,
            publicSummary.familyPublicRef,
            publicSummary.childPublicRef,
            "\(publicSummary.visiblePackCount)",
            "\(publicSummary.installableCount)",
            "\(publicSummary.installedCount)",
            "\(publicSummary.gatedCount)",
            "\(publicSummary.blockedCount)"
        ]
        return ([generatedAt, viewerRole.rawValue, headline, audienceNote] + decisionText + findingText + summaryText)
            .joined(separator: " | ")
    }
}

struct GrowthPackInstallEntitlementBuilder {
    var redactionSalt = "growth-pack-install-entitlement-ios-v1"

    func build(
        viewerRole: GrowthPackInstallViewerRole,
        input: GrowthPackInstallCatalogInput = .mock
    ) -> GrowthPackInstallSnapshot {
        let visibility = visibility(for: viewerRole)
        if hasUnsafeInput(input) {
            return blockedSnapshot(viewerRole: viewerRole, visibility: visibility, input: input, code: .unsafePayloadBlocked)
        }

        let rawDecisions = input.packs.map { decision(for: $0, input: input, visibility: visibility) }
        let decisions = visibility.canSeeCatalog ? rawDecisions : []
        var findings = collectFindings(from: input, decisions: rawDecisions, viewerRole: viewerRole)

        switch viewerRole {
        case .child:
            findings.append(finding(.childVisibilityRedacted, .info, "孩子端已隐藏价格、订单、权益和创作者内部信息。", "visibility-child"))
        case .relative:
            findings.append(finding(.relativeVisibilityRedacted, .info, "亲友端只读，购买与权益细节已隐藏。", "visibility-relative"))
        case .creator:
            findings.append(finding(.creatorVisibilityRedacted, .info, "创作者端不展示家庭、孩子、订单或权益明细。", "visibility-creator"))
        case .guardian:
            break
        }
        findings.append(finding(.sideEffectFree, .ok, "本地只读投影：不购买、不写权益、不发成长积分、不解锁设备。", "side-effect"))
        if !findings.contains(where: { $0.severity == .blocker }) {
            findings.insert(finding(.installProjectionReady, .ok, "成长包安装权益投影就绪。", "ready"), at: 0)
        }
        findings = unique(findings)

        let snapshot = GrowthPackInstallSnapshot(
            generatedAt: input.generatedAt,
            viewerRole: viewerRole,
            headline: headline(for: viewerRole, decisions: decisions),
            audienceNote: viewerRole.note,
            visibility: visibility,
            decisions: decisions,
            findings: visibleFindings(findings, visibility: visibility),
            publicSummary: publicSummary(
                input: input,
                viewerRole: viewerRole,
                decisions: decisions,
                findings: findings
            )
        )
        return Self.reportLeaks(snapshot) ? blockedSnapshot(viewerRole: viewerRole, visibility: visibility, input: input, code: .publicSummaryLeak) : snapshot
    }

    static func reportLeaks(_ snapshot: GrowthPackInstallSnapshot) -> Bool {
        let values = displayValues(snapshot)
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        let blocked = [
            "child:", "family:", "order:", "entitlement:", "creator:", "pack:",
            "http://", "https://", "192.168.", "/users/", "/volumes/", "file://",
            "baseurl", "apikey", "token"
        ]
        return blocked.contains { joined.contains($0) }
    }

    private func visibility(for role: GrowthPackInstallViewerRole) -> GrowthPackInstallVisibility {
        switch role {
        case .guardian:
            return GrowthPackInstallVisibility(
                viewerRole: role,
                canSeeCatalog: true,
                canSeePrice: true,
                canSeeOrderAndEntitlement: true,
                canSeeGuardianReason: true,
                canSeeCreatorListingState: true
            )
        case .child:
            return GrowthPackInstallVisibility(
                viewerRole: role,
                canSeeCatalog: true,
                canSeePrice: false,
                canSeeOrderAndEntitlement: false,
                canSeeGuardianReason: false,
                canSeeCreatorListingState: false
            )
        case .relative:
            return GrowthPackInstallVisibility(
                viewerRole: role,
                canSeeCatalog: true,
                canSeePrice: false,
                canSeeOrderAndEntitlement: false,
                canSeeGuardianReason: false,
                canSeeCreatorListingState: false
            )
        case .creator:
            return GrowthPackInstallVisibility(
                viewerRole: role,
                canSeeCatalog: true,
                canSeePrice: false,
                canSeeOrderAndEntitlement: false,
                canSeeGuardianReason: false,
                canSeeCreatorListingState: true
            )
        }
    }

    private func decision(
        for pack: GrowthPackInstallPackInput,
        input: GrowthPackInstallCatalogInput,
        visibility: GrowthPackInstallVisibility
    ) -> GrowthPackInstallDecision {
        let ageAllowed = input.childAge >= pack.minAge && input.childAge <= pack.maxAge
        let permissionsAllowed = pack.permissionsGranted
        let delisted = pack.listingState == .delisted
        let refundedOrRevoked = pack.entitlementState == .refunded || pack.entitlementState == .revoked
        let expired = pack.entitlementState == .expired

        let state: GrowthPackInstallDecisionState
        let reason: String
        let nextAction: String

        if refundedOrRevoked {
            state = .frozen
            reason = visibility.canSeeGuardianReason ? "购买权益已退款或撤权，孩子端运行被冻结。" : "这个成长包已暂停。"
            nextAction = "由家长处理退款/撤权后的安排。"
        } else if expired {
            state = .frozen
            reason = visibility.canSeeGuardianReason ? "权益已过期，需要重新确认。" : "这个成长包需要家长重新确认。"
            nextAction = "等待家长确认是否续用。"
        } else if !ageAllowed {
            state = .blocked
            reason = visibility.canSeeGuardianReason ? "孩子年龄不在 \(pack.minAge)-\(pack.maxAge) 岁范围内。" : "这个成长包暂时不适合你。"
            nextAction = "请家长选择适龄成长包。"
        } else if !permissionsAllowed {
            state = .blocked
            reason = visibility.canSeeGuardianReason ? "缺少运行所需权限：\(pack.requiredPermissions.joined(separator: "、"))。" : "需要家长先确认权限。"
            nextAction = "等待家长检查权限。"
        } else if delisted && pack.entitlementState != .active {
            state = .blocked
            reason = visibility.canSeeGuardianReason || visibility.canSeeCreatorListingState ? "成长包已下架，不能新购或安装。" : "这个成长包暂时不可用。"
            nextAction = "选择其它成长包。"
        } else if pack.entitlementState == .pendingGuardianApproval {
            state = .pendingGuardianConfirmation
            reason = "安装前需要家长确认。"
            nextAction = "等待家长批准安装。"
        } else if pack.entitlementState == .active {
            state = .installed
            reason = "成长包已授权，可在孩子端运行。"
            nextAction = pack.canMigrateVersion ? "可由家长查看版本迁移。" : "继续完成成长任务。"
        } else {
            state = .installable
            reason = "成长包可供家长选择安装。"
            nextAction = "家长确认后进入本地任务计划。"
        }

        return GrowthPackInstallDecision(
            packPublicRef: publicRef("gpi-pack", pack.packSeed),
            creatorPublicRef: publicRef("gpi-creator", pack.creatorSeed),
            state: visibility.canSeeCatalog ? state : .hidden,
            title: pack.title,
            summary: visibility.viewerRole == .child ? childSummary(for: state, pack: pack) : pack.summary,
            category: pack.category,
            creatorDisplayName: visibility.viewerRole == .child ? "已认证创作者" : pack.creatorDisplayName,
            versionLabel: pack.canMigrateVersion ? "\(pack.version) -> \(pack.latestVersion)" : pack.version,
            ageLabel: "\(pack.minAge)-\(pack.maxAge) 岁",
            requiredPermissionLabels: visibility.viewerRole == .child ? [] : pack.requiredPermissions,
            listingLabel: visibility.canSeeCreatorListingState ? pack.listingState.label : nil,
            entitlementLabel: visibility.canSeeOrderAndEntitlement ? pack.entitlementState.label : nil,
            priceLabel: visibility.canSeePrice ? pack.priceLabel : nil,
            orderPublicRef: visibility.canSeeOrderAndEntitlement ? pack.orderSeed.map { publicRef("gpi-order", $0) } : nil,
            entitlementPublicRef: visibility.canSeeOrderAndEntitlement ? pack.entitlementSeed.map { publicRef("gpi-ent", $0) } : nil,
            reason: reason,
            nextAction: nextAction,
            migrationNotice: pack.canMigrateVersion ? "存在可迁移版本，迁移前不丢失已完成进度。" : nil,
            refundWindowOpen: visibility.canSeeOrderAndEntitlement && pack.refundWindowOpen
        )
    }

    private func childSummary(for state: GrowthPackInstallDecisionState, pack: GrowthPackInstallPackInput) -> String {
        switch state {
        case .installable, .pendingGuardianConfirmation:
            return "等家长确认后，这个成长包会出现在你的任务里。"
        case .installed:
            return "这个成长包已经可以继续挑战。"
        case .frozen:
            return "这个成长包暂停了，先去完成其它任务。"
        case .blocked, .hidden:
            return "这个成长包暂时不开放。"
        }
    }

    private func collectFindings(
        from input: GrowthPackInstallCatalogInput,
        decisions: [GrowthPackInstallDecision],
        viewerRole: GrowthPackInstallViewerRole
    ) -> [GrowthPackInstallFinding] {
        var result: [GrowthPackInstallFinding] = []
        for (index, pack) in input.packs.enumerated() {
            let decision = decisions[index]
            if pack.entitlementState == .pendingGuardianApproval {
                result.append(finding(.guardianReviewRequired, .warning, "成长包安装需要家长确认。", pack.packSeed))
            }
            if pack.listingState == .delisted {
                result.append(finding(.listingDelisted, .blocker, "下架成长包不能新购或新装。", pack.packSeed))
            }
            if pack.entitlementState == .refunded || pack.entitlementState == .revoked {
                result.append(finding(.entitlementRefundedOrRevoked, .blocker, "退款或撤权后必须冻结孩子端运行。", pack.packSeed))
            }
            if pack.entitlementState == .expired {
                result.append(finding(.entitlementExpired, .warning, "过期权益需要家长重新确认。", pack.packSeed))
            }
            if input.childAge < pack.minAge || input.childAge > pack.maxAge {
                result.append(finding(.agePolicyBlocked, .blocker, "年龄分级不匹配，已阻断安装。", pack.packSeed))
            }
            if !pack.permissionsGranted {
                result.append(finding(.permissionPolicyBlocked, .blocker, "缺少成长包运行所需权限，已阻断安装。", pack.packSeed))
            }
            if pack.canMigrateVersion {
                result.append(finding(.versionMigrationAvailable, .info, "成长包有可迁移版本，迁移前保留进度。", pack.packSeed))
            }
            if decision.state == .pendingGuardianConfirmation && viewerRole == .child {
                result.append(finding(.childVisibilityRedacted, .info, "孩子端只显示等待家长确认。", "\(pack.packSeed)-child"))
            }
        }
        return result
    }

    private func visibleFindings(
        _ findings: [GrowthPackInstallFinding],
        visibility: GrowthPackInstallVisibility
    ) -> [GrowthPackInstallFinding] {
        if visibility.viewerRole == .guardian { return findings }
        return findings.filter { finding in
            switch finding.code {
            case .installProjectionReady, .childVisibilityRedacted, .relativeVisibilityRedacted, .creatorVisibilityRedacted, .sideEffectFree, .versionMigrationAvailable:
                return true
            case .listingDelisted:
                return visibility.canSeeCreatorListingState
            default:
                return false
            }
        }
    }

    private func publicSummary(
        input: GrowthPackInstallCatalogInput,
        viewerRole: GrowthPackInstallViewerRole,
        decisions: [GrowthPackInstallDecision],
        findings: [GrowthPackInstallFinding]
    ) -> GrowthPackInstallPublicSummary {
        GrowthPackInstallPublicSummary(
            generatedAt: input.generatedAt,
            viewerRole: viewerRole,
            catalogPublicRef: publicRef("gpi-catalog", "catalog"),
            familyPublicRef: publicRef("gpi-family", input.familySeed),
            childPublicRef: publicRef("gpi-child", input.childSeed),
            visiblePackCount: decisions.count,
            installableCount: decisions.filter { $0.state == .installable }.count,
            installedCount: decisions.filter { $0.state == .installed }.count,
            gatedCount: decisions.filter { $0.state == .pendingGuardianConfirmation || $0.state == .frozen }.count,
            blockedCount: decisions.filter { $0.state == .blocked }.count,
            findingCodes: findings.map(\.code)
        )
    }

    private func headline(for role: GrowthPackInstallViewerRole, decisions: [GrowthPackInstallDecision]) -> String {
        switch role {
        case .child:
            return decisions.contains(where: { $0.state == .installed }) ? "已有成长包可以继续挑战" : "等待家长选择成长包"
        case .guardian:
            return "成长包安装权益待家长确认"
        case .relative:
            return "亲友可查看孩子的公开成长包摘要"
        case .creator:
            return "创作者可查看上架与版本状态"
        }
    }

    private func blockedSnapshot(
        viewerRole: GrowthPackInstallViewerRole,
        visibility: GrowthPackInstallVisibility,
        input: GrowthPackInstallCatalogInput,
        code: GrowthPackInstallFindingCode
    ) -> GrowthPackInstallSnapshot {
        let finding = self.finding(code, .blocker, "成长包安装权益投影命中安全阻断。", "blocked")
        return GrowthPackInstallSnapshot(
            generatedAt: input.generatedAt,
            viewerRole: viewerRole,
            headline: "成长包安装权益已阻断",
            audienceNote: viewerRole.note,
            visibility: visibility,
            decisions: [],
            findings: [finding, self.finding(.sideEffectFree, .ok, "阻断只发生在本地投影层，没有任何真实副作用。", "side-effect")],
            publicSummary: GrowthPackInstallPublicSummary(
                generatedAt: input.generatedAt,
                viewerRole: viewerRole,
                catalogPublicRef: publicRef("gpi-catalog", "blocked"),
                familyPublicRef: publicRef("gpi-family", "blocked-family"),
                childPublicRef: publicRef("gpi-child", "blocked-child"),
                visiblePackCount: 0,
                installableCount: 0,
                installedCount: 0,
                gatedCount: 0,
                blockedCount: 1,
                findingCodes: [code, .sideEffectFree]
            )
        )
    }

    private func hasUnsafeInput(_ input: GrowthPackInstallCatalogInput) -> Bool {
        let values =
            [input.familySeed, input.childSeed, input.generatedAt]
            + input.packs.flatMap { pack in
                [
                    pack.packSeed,
                    pack.creatorSeed,
                    pack.orderSeed ?? "",
                    pack.entitlementSeed ?? "",
                    pack.title,
                    pack.summary,
                    pack.category,
                    pack.creatorDisplayName,
                    pack.version,
                    pack.latestVersion,
                    pack.priceLabel
                ] + pack.requiredPermissions
            }
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        let blocked = ["child:", "family:", "order:", "entitlement:", "creator:", "pack:", "http://", "https://", "192.168.", "/users/", "/volumes/", "file://"]
        return blocked.contains { joined.contains($0) }
    }

    private func finding(
        _ code: GrowthPackInstallFindingCode,
        _ severity: GrowthPackInstallSeverity,
        _ message: String,
        _ seed: String
    ) -> GrowthPackInstallFinding {
        GrowthPackInstallFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("gpi-find", "\(code.rawValue):\(seed)")
        )
    }

    private func unique(_ findings: [GrowthPackInstallFinding]) -> [GrowthPackInstallFinding] {
        var seen = Set<String>()
        return findings.filter { finding in
            let key = finding.code.rawValue + finding.publicRef
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func publicRef(_ prefix: String, _ seed: String) -> String {
        "\(prefix)_\(stableHash("\(redactionSalt):\(seed)"))"
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 36)
    }

    private static func displayValues(_ snapshot: GrowthPackInstallSnapshot) -> [String] {
        var values: [String] = [
            snapshot.generatedAt,
            snapshot.headline,
            snapshot.audienceNote,
            snapshot.publicSummary.catalogPublicRef,
            snapshot.publicSummary.familyPublicRef,
            snapshot.publicSummary.childPublicRef
        ]
        values += snapshot.decisions.flatMap { decision in
            [
                decision.packPublicRef,
                decision.creatorPublicRef,
                decision.title,
                decision.summary,
                decision.category,
                decision.creatorDisplayName,
                decision.versionLabel,
                decision.ageLabel,
                decision.listingLabel ?? "",
                decision.entitlementLabel ?? "",
                decision.priceLabel ?? "",
                decision.orderPublicRef ?? "",
                decision.entitlementPublicRef ?? "",
                decision.reason,
                decision.nextAction,
                decision.migrationNotice ?? ""
            ] + decision.requiredPermissionLabels
        }
        values += snapshot.findings.flatMap { [$0.code.rawValue, $0.message, $0.publicRef] }
        return values
    }
}

extension GrowthPackInstallCatalogInput {
    static let mock = GrowthPackInstallCatalogInput(
        generatedAt: "2026-06-24T13:00:00Z",
        familySeed: "family-self",
        childSeed: "child-self",
        childAge: 11,
        packs: [
            GrowthPackInstallPackInput(
                packSeed: "electric-basics-v1",
                creatorSeed: "official-maker",
                orderSeed: nil,
                entitlementSeed: nil,
                title: "电工基础入门",
                summary: "用图文、动画和小测验学习安全用电、简单电路和工具识别。",
                category: "知识 / 手作",
                creatorDisplayName: "章鱼老师 官方",
                version: "1.0.0",
                latestVersion: "1.0.0",
                minAge: 9,
                maxAge: 14,
                requiredPermissions: ["家长确认", "测验证明"],
                permissionsGranted: true,
                listingState: .listed,
                entitlementState: .none,
                priceLabel: "$4.99",
                refundWindowOpen: false,
                canMigrateVersion: false
            ),
            GrowthPackInstallPackInput(
                packSeed: "morning-routine-v2",
                creatorSeed: "habit-lab",
                orderSeed: "order-morning",
                entitlementSeed: "ent-morning",
                title: "早睡早起基础包",
                summary: "把睡眠、洗漱、晨间准备拆成可完成的小任务。",
                category: "基础习惯",
                creatorDisplayName: "Habit Lab",
                version: "2.0.0",
                latestVersion: "2.1.0",
                minAge: 6,
                maxAge: 13,
                requiredPermissions: ["基础任务", "家长复核"],
                permissionsGranted: true,
                listingState: .listed,
                entitlementState: .active,
                priceLabel: "已购买",
                refundWindowOpen: false,
                canMigrateVersion: true
            ),
            GrowthPackInstallPackInput(
                packSeed: "creator-art-vlog",
                creatorSeed: "creator-art",
                orderSeed: "order-art",
                entitlementSeed: "ent-art",
                title: "创作展示成长包",
                summary: "完成画作、上传展示并等待家长审核后获得成长记录。",
                category: "创作",
                creatorDisplayName: "小小创作社",
                version: "1.2.0",
                latestVersion: "1.2.0",
                minAge: 8,
                maxAge: 16,
                requiredPermissions: ["媒体上传", "家长审核"],
                permissionsGranted: false,
                listingState: .listed,
                entitlementState: .pendingGuardianApproval,
                priceLabel: "$2.99",
                refundWindowOpen: false,
                canMigrateVersion: false
            ),
            GrowthPackInstallPackInput(
                packSeed: "old-game-proof",
                creatorSeed: "game-school",
                orderSeed: "order-game",
                entitlementSeed: "ent-game",
                title: "旧版通关截图包",
                summary: "旧版游戏截图证明成长包。",
                category: "游戏证明",
                creatorDisplayName: "Game School",
                version: "0.9.0",
                latestVersion: "1.0.0",
                minAge: 12,
                maxAge: 17,
                requiredPermissions: ["截图证明"],
                permissionsGranted: true,
                listingState: .delisted,
                entitlementState: .refunded,
                priceLabel: "已退款",
                refundWindowOpen: false,
                canMigrateVersion: false
            )
        ]
    )
}
