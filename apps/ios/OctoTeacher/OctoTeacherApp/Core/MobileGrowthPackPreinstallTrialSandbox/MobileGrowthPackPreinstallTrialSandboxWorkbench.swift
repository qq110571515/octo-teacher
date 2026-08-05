import Foundation

/// iOS 成长包安装前试运行配置沙盒的纯本地只读投影。
///
/// 该层组合成长包安装权益、模块配置草稿和 Manifest 预览语义，帮助家长在正式购买、
/// 安装或分配给孩子前先看任务节奏、证明、学校优先级、权限和成长积分建议边界。
/// 它不购买、不退款、不安装、不创建任务、不写 entitlement/ledger、不发成长积分、不解锁设备。
enum MobileGrowthPackPreinstallTrialRole: String, CaseIterable, Equatable {
    case child
    case guardian
    case creator

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        case .creator: return "创作者"
        }
    }

    var audienceNote: String {
        switch self {
        case .child:
            return "这里只看适龄学习预览、可能的任务节奏和证明下一步。"
        case .guardian:
            return "只读试运行安装、配置、证明、学校优先级和成长积分建议边界。"
        case .creator:
            return "只看脱敏试运行反馈，不展示家庭、孩子或交易授权细节。"
        }
    }
}

enum MobileGrowthPackPreinstallTrialState: String, Equatable {
    case canTrial
    case needsGuardianReview
    case frozen
    case blocked
    case hidden

    var label: String {
        switch self {
        case .canTrial: return "可试运行"
        case .needsGuardianReview: return "待家长复核"
        case .frozen: return "已冻结"
        case .blocked: return "已阻断"
        case .hidden: return "不可见"
        }
    }
}

enum MobileGrowthPackPreinstallTrialFindingCode: String, Equatable {
    case readOnlyReady = "READ_ONLY_READY"
    case guardianReviewRequired = "GUARDIAN_REVIEW_REQUIRED"
    case agePolicyBlocked = "AGE_POLICY_BLOCKED"
    case permissionPolicyBlocked = "PERMISSION_POLICY_BLOCKED"
    case listingOrEntitlementBlocked = "LISTING_OR_AUTHORIZATION_BLOCKED"
    case schoolPriorityConflict = "SCHOOL_PRIORITY_CONFLICT"
    case creditBoundaryReview = "CREDIT_BOUNDARY_REVIEW"
    case creatorFeedbackRedacted = "CREATOR_FEEDBACK_REDACTED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

struct MobileGrowthPackPreinstallTrialRow: Identifiable, Equatable {
    var publicTrialRef: String
    var title: String
    var category: String
    var learningPreview: String
    var installBoundaryLabel: String
    var agePermissionLabel: String
    var scheduleLabel: String
    var proofLabel: String
    var creditBoundaryLabel: String
    var nextStep: String
    var safetyNote: String
    var state: MobileGrowthPackPreinstallTrialState
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToCreator: Bool
    var ageAllowed: Bool
    var permissionsAllowed: Bool
    var listingOrEntitlementBlocked: Bool
    var schoolPriorityConflict: Bool
    var creditNeedsGuardianReview: Bool

    let purchasesPack = false
    let refundsPayment = false
    let installsPack = false
    let createsAssignment = false
    let writesEntitlement = false
    let writesOrder = false
    let writesLedger = false
    let grantsCredit = false
    let grantsBadge = false
    let mutatesAbilityCard = false
    let unlocksDevice = false
    let sendsNotification = false
    let callsNetwork = false
    let opensWebView = false
    let callsAI = false
    let writesSchoolSystem = false

    var id: String { publicTrialRef }

    var displayValues: [String] {
        [
            title,
            category,
            learningPreview,
            installBoundaryLabel,
            agePermissionLabel,
            scheduleLabel,
            proofLabel,
            creditBoundaryLabel,
            nextStep,
            safetyNote,
            state.rawValue,
            state.label
        ]
    }
}

struct MobileGrowthPackPreinstallTrialFinding: Identifiable, Equatable {
    var code: MobileGrowthPackPreinstallTrialFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToCreator: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileGrowthPackPreinstallTrialPublicSummary: Equatable {
    var role: MobileGrowthPackPreinstallTrialRole
    var packCount: Int
    var visiblePackCount: Int
    var blockedCount: Int
    var guardianReviewCount: Int
    var schoolPriorityConflictCount: Int
    var creditBoundaryReviewCount: Int
    var findingCodes: [MobileGrowthPackPreinstallTrialFindingCode]

    let purchasesPack = false
    let refundsPayment = false
    let installsPack = false
    let createsAssignment = false
    let writesEntitlement = false
    let writesOrder = false
    let writesLedger = false
    let grantsCredit = false
    let grantsBadge = false
    let mutatesAbilityCard = false
    let unlocksDevice = false
    let sendsNotification = false
    let callsNetwork = false
    let opensWebView = false
    let callsAI = false
    let writesSchoolSystem = false

    var hasTriggeredSideEffect: Bool {
        purchasesPack || refundsPayment || installsPack || createsAssignment || writesEntitlement
            || writesOrder || writesLedger || grantsCredit || grantsBadge || mutatesAbilityCard
            || unlocksDevice || sendsNotification || callsNetwork || opensWebView || callsAI
            || writesSchoolSystem
    }
}

struct MobileGrowthPackPreinstallTrialSandboxWorkbench: Equatable {
    var role: MobileGrowthPackPreinstallTrialRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var rows: [MobileGrowthPackPreinstallTrialRow]
    var findings: [MobileGrowthPackPreinstallTrialFinding]
    var publicSummary: MobileGrowthPackPreinstallTrialPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + rows.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileGrowthPackPreinstallTrialSandboxBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileGrowthPackPreinstallTrialSandboxBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "guardian:", "creator:", "pack:", "order:",
        "entitlement:", "assignment:", "task:", "proof:", "ledger:", "device:",
        "school:", "teacher:", "price:", "revenue:", "publicref",
        "成长积分金额", "设备命令", "订单", "权益 id", "创作者收益",
        "http://", "https://", "file://", "/users/", "/volumes/", "192.168."
    ]
    private static let sensitivePatterns = [
        "(?i)\\b(?:access|device|session|api|bearer)[ _-]?token\\b",
        "(?i)\\b(?:api|server|client)[ _-]?secret\\b",
        "(?i)\\bapi[_-]?key\\b",
        "(?i)\\bcredit[ _-]?amount\\b",
        "(?i)\\border[ _-]?id\\b",
        "(?i)\\bentitlement[ _-]?id\\b"
    ]

    func build(
        role: MobileGrowthPackPreinstallTrialRole,
        installInput: GrowthPackInstallCatalogInput = .mock,
        configuration: MobileModuleConfigurationDraftSnapshot? = nil,
        unsafePayload: [String] = []
    ) -> MobileGrowthPackPreinstallTrialSandboxWorkbench {
        if Self.hasUnsafeInput(installInput: installInput, configuration: configuration, unsafePayload: unsafePayload) {
            return safeFallback(role: role, hiddenCount: installInput.packs.count)
        }

        let configurationSnapshot = configuration ?? MobileModuleConfigurationDraftBuilder().build(viewerRole: .guardian)
        if configurationSnapshot.status == .blocked || Self.hasUnsafeDisplayPayload(configurationSnapshot.displayValues) {
            return safeFallback(role: role, hiddenCount: installInput.packs.count)
        }

        let rows = installInput.packs.map {
            row(role: role, pack: $0, installInput: installInput, configuration: configurationSnapshot)
        }
        let visibleRows = rows.filter { isVisible($0, to: role) }
        let findings = findingRows(role: role, rows: rows, configuration: configurationSnapshot)
        let summary = MobileGrowthPackPreinstallTrialPublicSummary(
            role: role,
            packCount: rows.count,
            visiblePackCount: visibleRows.count,
            blockedCount: rows.filter { $0.state == .blocked || $0.state == .frozen }.count,
            guardianReviewCount: rows.filter { $0.state == .needsGuardianReview }.count,
            schoolPriorityConflictCount: rows.filter(\.schoolPriorityConflict).count,
            creditBoundaryReviewCount: rows.filter(\.creditNeedsGuardianReview).count,
            findingCodes: findings.map(\.code)
        )
        let workbench = MobileGrowthPackPreinstallTrialSandboxWorkbench(
            role: role,
            title: "安装前试运行沙盒",
            subtitle: "\(installInput.packs.count) 个成长包 · 本地只读",
            audienceNote: role.audienceNote,
            rows: visibleRows,
            findings: findings.filter { finding in
                switch role {
                case .child: return finding.visibleToChild
                case .guardian: return finding.visibleToGuardian
                case .creator: return finding.visibleToCreator
                }
            },
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? safeFallback(role: role, hiddenCount: installInput.packs.count) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        if sensitiveMarkers.contains(where: { joined.contains($0) }) { return true }
        return sensitivePatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func hasUnsafeInput(
        installInput: GrowthPackInstallCatalogInput,
        configuration: MobileModuleConfigurationDraftSnapshot?,
        unsafePayload: [String]
    ) -> Bool {
        var values = unsafePayload + [installInput.generatedAt, installInput.familySeed, installInput.childSeed]
        values.append(contentsOf: installInput.packs.flatMap { pack in
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
        })
        if let configuration {
            values.append(contentsOf: configuration.displayValues)
        }
        return hasUnsafeDisplayPayload(values)
    }

    private func row(
        role: MobileGrowthPackPreinstallTrialRole,
        pack: GrowthPackInstallPackInput,
        installInput: GrowthPackInstallCatalogInput,
        configuration: MobileModuleConfigurationDraftSnapshot
    ) -> MobileGrowthPackPreinstallTrialRow {
        let ageAllowed = installInput.childAge >= pack.minAge && installInput.childAge <= pack.maxAge
        let permissionsAllowed = pack.permissionsGranted
        let listingOrEntitlementBlocked = pack.listingState == .delisted
            || pack.entitlementState == .refunded
            || pack.entitlementState == .revoked
            || pack.entitlementState == .expired
        let schoolPriorityConflict = configuration.findings.contains { $0.code == .schoolPriority }
            || configuration.items.contains { $0.moduleKey == .schoolHomework && $0.warning != nil }
        let creditNeedsGuardianReview = configuration.publicSummary.creditPreviewTotal != nil
            || pack.entitlementState == .none
            || pack.entitlementState == .pendingGuardianApproval

        let state: MobileGrowthPackPreinstallTrialState
        if listingOrEntitlementBlocked {
            state = pack.entitlementState == .refunded || pack.entitlementState == .revoked || pack.entitlementState == .expired
                ? .frozen
                : .blocked
        } else if !ageAllowed || !permissionsAllowed {
            state = .blocked
        } else if pack.entitlementState == .pendingGuardianApproval || schoolPriorityConflict || creditNeedsGuardianReview {
            state = .needsGuardianReview
        } else {
            state = .canTrial
        }

        return MobileGrowthPackPreinstallTrialRow(
            publicTrialRef: publicRef("mgts", pack.packSeed),
            title: titleCopy(role: role, pack: pack),
            category: pack.category,
            learningPreview: learningPreview(role: role, pack: pack, state: state),
            installBoundaryLabel: installBoundaryLabel(role: role, pack: pack, state: state),
            agePermissionLabel: agePermissionLabel(pack: pack, ageAllowed: ageAllowed, permissionsAllowed: permissionsAllowed),
            scheduleLabel: scheduleLabel(role: role, configuration: configuration, schoolPriorityConflict: schoolPriorityConflict),
            proofLabel: proofLabel(role: role, pack: pack),
            creditBoundaryLabel: creditBoundaryLabel(role: role, needsReview: creditNeedsGuardianReview),
            nextStep: nextStep(role: role, state: state),
            safetyNote: safetyNote(role: role),
            state: state,
            visibleToChild: state == .canTrial || state == .needsGuardianReview,
            visibleToGuardian: role == .guardian,
            visibleToCreator: role == .creator,
            ageAllowed: ageAllowed,
            permissionsAllowed: permissionsAllowed,
            listingOrEntitlementBlocked: listingOrEntitlementBlocked,
            schoolPriorityConflict: schoolPriorityConflict,
            creditNeedsGuardianReview: creditNeedsGuardianReview
        )
    }

    private func isVisible(
        _ row: MobileGrowthPackPreinstallTrialRow,
        to role: MobileGrowthPackPreinstallTrialRole
    ) -> Bool {
        switch role {
        case .child: return row.visibleToChild
        case .guardian: return row.visibleToGuardian
        case .creator: return row.visibleToCreator
        }
    }

    private func findingRows(
        role: MobileGrowthPackPreinstallTrialRole,
        rows: [MobileGrowthPackPreinstallTrialRow],
        configuration: MobileModuleConfigurationDraftSnapshot
    ) -> [MobileGrowthPackPreinstallTrialFinding] {
        var findings: [MobileGrowthPackPreinstallTrialFinding] = []
        if rows.contains(where: { $0.state == .needsGuardianReview }) {
            findings.append(finding(.guardianReviewRequired, "试运行结果需要家长复核后才能进入正式流程。", true, child: true, guardian: true, creator: false))
        }
        if rows.contains(where: { !$0.ageAllowed }) {
            findings.append(finding(.agePolicyBlocked, "年龄不匹配的成长包不能分配给孩子。", true, child: false, guardian: true, creator: true))
        }
        if rows.contains(where: { !$0.permissionsAllowed }) {
            findings.append(finding(.permissionPolicyBlocked, "缺少权限的成长包不能进入试运行分配。", true, child: false, guardian: true, creator: true))
        }
        if rows.contains(where: \.listingOrEntitlementBlocked) {
            findings.append(finding(.listingOrEntitlementBlocked, "下架、退款、撤权或过期会冻结安装前试运行。", true, child: false, guardian: true, creator: true))
        }
        if configuration.findings.contains(where: { $0.code == .schoolPriority }) || rows.contains(where: \.schoolPriorityConflict) {
            findings.append(finding(.schoolPriorityConflict, "存在学校作业优先级，娱乐奖励和成长包运行需要后置。", true, child: false, guardian: true, creator: false))
        }
        if rows.contains(where: \.creditNeedsGuardianReview) {
            findings.append(finding(.creditBoundaryReview, "成长积分建议只能进入家长复核，不能由试运行直接发放。", true, child: false, guardian: true, creator: false))
        }
        if role == .creator {
            findings.append(finding(.creatorFeedbackRedacted, "创作者只看到脱敏试运行反馈，不含家庭、孩子或交易授权细节。", false, child: false, guardian: false, creator: true))
        }
        if findings.isEmpty {
            findings.append(finding(.readOnlyReady, "安装前试运行沙盒只读就绪。", false, child: true, guardian: true, creator: true))
        }
        return findings
    }

    private func finding(
        _ code: MobileGrowthPackPreinstallTrialFindingCode,
        _ message: String,
        _ actionRequired: Bool,
        child: Bool,
        guardian: Bool,
        creator: Bool
    ) -> MobileGrowthPackPreinstallTrialFinding {
        MobileGrowthPackPreinstallTrialFinding(
            code: code,
            message: message,
            actionRequired: actionRequired,
            visibleToChild: child,
            visibleToGuardian: guardian,
            visibleToCreator: creator
        )
    }

    private func titleCopy(
        role: MobileGrowthPackPreinstallTrialRole,
        pack: GrowthPackInstallPackInput
    ) -> String {
        role == .creator ? "\(pack.category)试运行反馈" : pack.title
    }

    private func learningPreview(
        role: MobileGrowthPackPreinstallTrialRole,
        pack: GrowthPackInstallPackInput,
        state: MobileGrowthPackPreinstallTrialState
    ) -> String {
        switch role {
        case .child:
            return state == .canTrial || state == .needsGuardianReview
                ? "安排好后，可以按节奏完成这个成长挑战。"
                : "这个成长包暂时不可用。"
        case .guardian:
            return "\(pack.summary) 试运行只生成预览，不创建真实任务。"
        case .creator:
            return "脱敏反馈：\(pack.category)成长包需要通过家庭安装前边界检查。"
        }
    }

    private func installBoundaryLabel(
        role: MobileGrowthPackPreinstallTrialRole,
        pack: GrowthPackInstallPackInput,
        state: MobileGrowthPackPreinstallTrialState
    ) -> String {
        if role == .child { return "等待家庭安排是否加入任务" }
        switch state {
        case .frozen: return "权益状态冻结，不能试运行"
        case .blocked: return "安装前边界已阻断"
        case .needsGuardianReview: return "需要家长复核后才能进入正式安装"
        case .canTrial: return pack.entitlementState == .active ? "已有授权，可试运行配置" : "可试运行，正式安装另行确认"
        case .hidden: return "不可见"
        }
    }

    private func agePermissionLabel(
        pack: GrowthPackInstallPackInput,
        ageAllowed: Bool,
        permissionsAllowed: Bool
    ) -> String {
        if !ageAllowed { return "年龄不适配：\(pack.minAge)-\(pack.maxAge) 岁" }
        if !permissionsAllowed { return "缺少权限，需家长检查" }
        return "\(pack.minAge)-\(pack.maxAge) 岁适配，权限可检查"
    }

    private func scheduleLabel(
        role: MobileGrowthPackPreinstallTrialRole,
        configuration: MobileModuleConfigurationDraftSnapshot,
        schoolPriorityConflict: Bool
    ) -> String {
        if role == .child { return "按家长安排的时间完成" }
        if schoolPriorityConflict { return "学校作业优先，成长包试运行需后置" }
        return "预计 \(configuration.publicSummary.estimatedMinutesTotal) 分钟本地草稿"
    }

    private func proofLabel(
        role: MobileGrowthPackPreinstallTrialRole,
        pack: GrowthPackInstallPackInput
    ) -> String {
        if role == .child { return "完成后提交证明给家长" }
        return pack.requiredPermissions.isEmpty ? "暂无证明/权限要求" : "证明与权限：\(pack.requiredPermissions.joined(separator: " / "))"
    }

    private func creditBoundaryLabel(
        role: MobileGrowthPackPreinstallTrialRole,
        needsReview: Bool
    ) -> String {
        if role == .child { return "完成后等待确认" }
        return needsReview ? "成长积分建议需家长复核，不写账本" : "无即时成长积分写入"
    }

    private func nextStep(
        role: MobileGrowthPackPreinstallTrialRole,
        state: MobileGrowthPackPreinstallTrialState
    ) -> String {
        switch (role, state) {
        case (.child, .canTrial), (.child, .needsGuardianReview):
            return "先完成今天的安排，再等待确认。"
        case (.guardian, .canTrial):
            return "可继续进入正式安装/分配流程。"
        case (.guardian, .needsGuardianReview):
            return "先处理权限、学校优先级和成长积分边界。"
        case (.creator, .canTrial), (.creator, .needsGuardianReview):
            return "根据脱敏反馈补充发布说明。"
        default:
            return "该成长包暂不进入试运行。"
        }
    }

    private func safetyNote(role: MobileGrowthPackPreinstallTrialRole) -> String {
        switch role {
        case .child:
            return "本页不显示支付细节、成人处理细节、奖励数值或设备操作。"
        case .guardian:
            return "本页不购买、不安装、不创建任务、不发成长积分、不解锁设备。"
        case .creator:
            return "本页不显示家庭、孩子、支付、权益或设备细节。"
        }
    }

    private func safeFallback(
        role: MobileGrowthPackPreinstallTrialRole,
        hiddenCount: Int
    ) -> MobileGrowthPackPreinstallTrialSandboxWorkbench {
        MobileGrowthPackPreinstallTrialSandboxWorkbench(
            role: role,
            title: "安装前试运行已被安全保护",
            subtitle: "本地安全壳",
            audienceNote: role.audienceNote,
            rows: [],
            findings: [
                finding(
                    .unsafePayloadBlocked,
                    "检测到链接、路径、密钥、局域网地址、内部标识或支付/权益/设备敏感语义，本地壳不回显原文。",
                    role != .child,
                    child: false,
                    guardian: true,
                    creator: true
                )
            ],
            publicSummary: MobileGrowthPackPreinstallTrialPublicSummary(
                role: role,
                packCount: hiddenCount,
                visiblePackCount: 0,
                blockedCount: hiddenCount,
                guardianReviewCount: 0,
                schoolPriorityConflictCount: 0,
                creditBoundaryReviewCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        var hash: UInt32 = 5381
        for scalar in "mobile-growth-pack-preinstall-trial:\(source)".unicodeScalars {
            hash = (hash &* 33) ^ (scalar.value & 0xFFFF)
        }
        return "\(prefix)-\(String(hash, radix: 36))"
    }
}
