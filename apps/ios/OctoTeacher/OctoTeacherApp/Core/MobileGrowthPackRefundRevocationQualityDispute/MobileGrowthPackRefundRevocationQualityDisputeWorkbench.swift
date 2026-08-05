import Foundation

/// iOS 成长包退款、撤权、下架与质量争议的本地只读复核壳。
///
/// 该层只组合现有安装权益、云同步和安装前试运行 mock 语义，不接 StoreKit、App Store、
/// 云端、账本、通知、AI、学校系统或设备控制。
enum MobileGrowthPackRefundDisputeRole: String, CaseIterable, Equatable {
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
            return "这里只看安全下一步：能继续的内容、暂时暂停的内容和等待家长处理。"
        case .guardian:
            return "只读复核退款窗口、撤权下架、质量反馈、进度保留和成长积分冻结边界。"
        case .creator:
            return "只看脱敏质量反馈和版本提示。"
        }
    }
}

enum MobileGrowthPackRefundDisputeState: String, Equatable {
    case active
    case reviewRequired
    case frozen
    case blocked
    case hidden

    var label: String {
        switch self {
        case .active: return "可继续"
        case .reviewRequired: return "待复核"
        case .frozen: return "已冻结"
        case .blocked: return "已阻断"
        case .hidden: return "不可见"
        }
    }
}

enum MobileGrowthPackQualityDisputeStatus: String, Equatable {
    case none
    case opened
    case underReview
    case upheld
    case rejected
    case resolved
}

enum MobileGrowthPackQualityDisputeReason: String, Equatable {
    case contentQuality
    case ageMismatch
    case proofMismatch
    case safetyConcern
}

enum MobileGrowthPackRefundDisputeFindingCode: String, Equatable {
    case readOnlyReady = "READ_ONLY_READY"
    case refundWindowReview = "REFUND_WINDOW_REVIEW"
    case revocationOrDelistBlocked = "REVOCATION_OR_DELIST_BLOCKED"
    case qualityDisputeFrozen = "QUALITY_DISPUTE_FROZEN"
    case progressRetentionReview = "PROGRESS_RETENTION_REVIEW"
    case creditRollbackReview = "CREDIT_ROLLBACK_REVIEW"
    case creatorFeedbackRedacted = "CREATOR_FEEDBACK_REDACTED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

struct MobileGrowthPackQualityDisputeInput: Equatable {
    var packSeed: String
    var status: MobileGrowthPackQualityDisputeStatus
    var reason: MobileGrowthPackQualityDisputeReason
    var creatorVisibleSummary: String
}

struct MobileGrowthPackRefundDisputeInput: Equatable {
    var generatedAt: String
    var installInput: GrowthPackInstallCatalogInput
    var cloudStateByPackSeed: [String: GrowthPackCloudSyncMobileBridgeCloudState]
    var qualityDisputes: [MobileGrowthPackQualityDisputeInput]
    var completedProgressByPackSeed: [String: Int]
    var incompleteTasksByPackSeed: [String: Int]
    var creditFrozenByPackSeed: [String: Bool]
    var unsafePayload: [String]
}

struct MobileGrowthPackRefundDisputeRow: Identifiable, Equatable {
    var publicReviewRef: String
    var title: String
    var category: String
    var state: MobileGrowthPackRefundDisputeState
    var statusLabel: String
    var lifecycleLabel: String
    var progressLabel: String
    var creditBoundaryLabel: String
    var nextStep: String
    var safetyNote: String
    var creatorFeedback: String?
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToCreator: Bool
    var refundWindowOpen: Bool
    var revokedOrDelisted: Bool
    var qualityDisputeOpen: Bool
    var preservesCompletedProgress: Bool
    var freezesIncompleteTasks: Bool
    var creditRollbackReviewNeeded: Bool

    let chargesPayment = false
    let refundsPayment = false
    let restoresEntitlement = false
    let writesEntitlement = false
    let writesOrder = false
    let writesLedger = false
    let grantsCredit = false
    let deductsCredit = false
    let grantsBadge = false
    let mutatesAbilityCard = false
    let unlocksDevice = false
    let sendsNotification = false
    let callsNetwork = false
    let opensStoreKit = false
    let callsAI = false
    let writesSchoolSystem = false

    var id: String { publicReviewRef }

    var displayValues: [String] {
        [
            title,
            category,
            state.rawValue,
            state.label,
            statusLabel,
            lifecycleLabel,
            progressLabel,
            creditBoundaryLabel,
            nextStep,
            safetyNote,
            creatorFeedback ?? ""
        ]
    }

    var hasTriggeredSideEffect: Bool {
        chargesPayment || refundsPayment || restoresEntitlement || writesEntitlement
            || writesOrder || writesLedger || grantsCredit || deductsCredit || grantsBadge
            || mutatesAbilityCard || unlocksDevice || sendsNotification || callsNetwork
            || opensStoreKit || callsAI || writesSchoolSystem
    }
}

struct MobileGrowthPackRefundDisputeFinding: Identifiable, Equatable {
    var code: MobileGrowthPackRefundDisputeFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var visibleToCreator: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileGrowthPackRefundDisputePublicSummary: Equatable {
    var role: MobileGrowthPackRefundDisputeRole
    var packCount: Int
    var visiblePackCount: Int
    var reviewRequiredCount: Int
    var frozenCount: Int
    var blockedCount: Int
    var completedProgressPreservedCount: Int
    var creditRollbackReviewCount: Int
    var findingCodes: [MobileGrowthPackRefundDisputeFindingCode]

    let chargesPayment = false
    let refundsPayment = false
    let restoresEntitlement = false
    let writesEntitlement = false
    let writesOrder = false
    let writesLedger = false
    let grantsCredit = false
    let deductsCredit = false
    let grantsBadge = false
    let mutatesAbilityCard = false
    let unlocksDevice = false
    let sendsNotification = false
    let callsNetwork = false
    let opensStoreKit = false
    let callsAI = false
    let writesSchoolSystem = false

    var hasTriggeredSideEffect: Bool {
        chargesPayment || refundsPayment || restoresEntitlement || writesEntitlement
            || writesOrder || writesLedger || grantsCredit || deductsCredit || grantsBadge
            || mutatesAbilityCard || unlocksDevice || sendsNotification || callsNetwork
            || opensStoreKit || callsAI || writesSchoolSystem
    }
}

struct MobileGrowthPackRefundDisputeWorkbench: Equatable {
    var role: MobileGrowthPackRefundDisputeRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var rows: [MobileGrowthPackRefundDisputeRow]
    var findings: [MobileGrowthPackRefundDisputeFinding]
    var publicSummary: MobileGrowthPackRefundDisputePublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + rows.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileGrowthPackRefundRevocationQualityDisputeBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileGrowthPackRefundRevocationQualityDisputeBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "guardian:", "creator:", "pack:", "order:",
        "entitlement:", "refund:", "dispute:", "assignment:", "task:",
        "proof:", "ledger:", "device:", "school:", "teacher:", "price:",
        "revenue:", "publicref", "退款金额", "价格", "订单", "权益 id",
        "创作者收益", "家长预算", "质量争议细节", "成人责任原因",
        "成长积分金额", "账本", "设备命令", "http://", "https://",
        "file://", "/users/", "/volumes/", "192.168."
    ]
    private static let sensitivePatterns = [
        "(?i)\\b(?:access|device|session|api|bearer)[ _-]?token\\b",
        "(?i)\\b(?:api|server|client)[ _-]?secret\\b",
        "(?i)\\bapi[_-]?key\\b",
        "(?i)\\bcredit[ _-]?amount\\b",
        "(?i)\\border[ _-]?id\\b",
        "(?i)\\bentitlement[ _-]?id\\b",
        "(?i)\\brefund[ _-]?(?:id|amount|reason)\\b",
        "(?i)\\bdispute[ _-]?id\\b"
    ]
    private static let creatorFeedbackPrivateMarkers = [
        "家庭", "孩子", "家长", "亲友", "老师", "学校", "订单", "权益",
        "退款", "预算", "设备", "成长积分金额", "family", "child", "guardian",
        "relative", "teacher", "school", "order", "entitlement", "refund",
        "budget", "device", "credit amount"
    ]

    func build(
        role: MobileGrowthPackRefundDisputeRole,
        input: MobileGrowthPackRefundDisputeInput = .mock
    ) -> MobileGrowthPackRefundDisputeWorkbench {
        if Self.hasUnsafeInput(input) {
            return safeFallback(role: role, hiddenCount: input.installInput.packs.count)
        }

        let installSnapshot = GrowthPackInstallEntitlementBuilder().build(viewerRole: .guardian, input: input.installInput)
        let trialSnapshot = MobileGrowthPackPreinstallTrialSandboxBuilder().build(role: .guardian, installInput: input.installInput)
        let cloudSnapshot = GrowthPackCloudSyncMobileBridgeBuilder().build(viewerRole: .guardian)
        if GrowthPackInstallEntitlementBuilder.reportLeaks(installSnapshot)
            || trialSnapshot.hasUnsafeDisplayPayload
            || cloudSnapshot.sideEffects.hasTriggeredSideEffect {
            return safeFallback(role: role, hiddenCount: input.installInput.packs.count)
        }

        let disputesByPack = Dictionary(uniqueKeysWithValues: input.qualityDisputes.map { ($0.packSeed, $0) })
        let rows = input.installInput.packs.map { pack in
            row(role: role, pack: pack, input: input, dispute: disputesByPack[pack.packSeed])
        }
        let visibleRows = rows.filter { isVisible($0, to: role) }
        let findings = findingRows(role: role, rows: rows)
        let visibleFindings = findings.filter { finding in
            switch role {
            case .child: return finding.visibleToChild
            case .guardian: return finding.visibleToGuardian
            case .creator: return finding.visibleToCreator
            }
        }
        let summary = MobileGrowthPackRefundDisputePublicSummary(
            role: role,
            packCount: rows.count,
            visiblePackCount: visibleRows.count,
            reviewRequiredCount: rows.filter { $0.state == .reviewRequired }.count,
            frozenCount: rows.filter { $0.state == .frozen }.count,
            blockedCount: rows.filter { $0.state == .blocked }.count,
            completedProgressPreservedCount: rows.filter(\.preservesCompletedProgress).count,
            creditRollbackReviewCount: rows.filter(\.creditRollbackReviewNeeded).count,
            findingCodes: visibleFindings.map(\.code)
        )
        let workbench = MobileGrowthPackRefundDisputeWorkbench(
            role: role,
            title: title(for: role),
            subtitle: "\(input.installInput.packs.count) 个成长包 · 本地只读",
            audienceNote: role.audienceNote,
            rows: visibleRows,
            findings: visibleFindings,
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? safeFallback(role: role, hiddenCount: input.installInput.packs.count) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        if sensitiveMarkers.contains(where: { joined.contains($0) }) { return true }
        return sensitivePatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func hasUnsafeInput(_ input: MobileGrowthPackRefundDisputeInput) -> Bool {
        let packValues = input.installInput.packs.flatMap {
            [
                $0.packSeed,
                $0.creatorSeed,
                $0.orderSeed ?? "",
                $0.entitlementSeed ?? "",
                $0.title,
                $0.summary,
                $0.category,
                $0.creatorDisplayName,
                $0.priceLabel
            ]
        }
        let disputeValues = input.qualityDisputes.flatMap {
            [$0.packSeed, $0.status.rawValue, $0.reason.rawValue, $0.creatorVisibleSummary]
        }
        return hasUnsafeDisplayPayload([
            input.generatedAt,
            input.installInput.familySeed,
            input.installInput.childSeed
        ] + packValues + disputeValues + input.unsafePayload)
    }

    private func row(
        role: MobileGrowthPackRefundDisputeRole,
        pack: GrowthPackInstallPackInput,
        input: MobileGrowthPackRefundDisputeInput,
        dispute: MobileGrowthPackQualityDisputeInput?
    ) -> MobileGrowthPackRefundDisputeRow {
        let cloudState = input.cloudStateByPackSeed[pack.packSeed] ?? .fresh
        let completed = input.completedProgressByPackSeed[pack.packSeed] ?? 0
        let incomplete = input.incompleteTasksByPackSeed[pack.packSeed] ?? 0
        let creditFrozen = input.creditFrozenByPackSeed[pack.packSeed] ?? false
        let revokedOrDelisted = pack.listingState == .delisted
            || [.refunded, .revoked, .expired].contains(pack.entitlementState)
            || [.refunded, .revoked, .delisted].contains(cloudState)
        let qualityOpen = dispute.map { ![.none, .resolved].contains($0.status) } ?? false
        let review = pack.refundWindowOpen || pack.canMigrateVersion || cloudState == .stale
        let state: MobileGrowthPackRefundDisputeState
        if revokedOrDelisted {
            state = .blocked
        } else if qualityOpen || creditFrozen {
            state = .frozen
        } else if review {
            state = .reviewRequired
        } else {
            state = .active
        }

        let preservesCompleted = completed > 0 && (revokedOrDelisted || qualityOpen || creditFrozen)
        let freezesIncomplete = incomplete > 0 && (revokedOrDelisted || qualityOpen || creditFrozen)
        let rollbackReview = creditFrozen || revokedOrDelisted || qualityOpen
        let publicRef = Self.publicRef(prefix: "gprq", seed: "\(pack.packSeed):\(role.rawValue)")
        return MobileGrowthPackRefundDisputeRow(
            publicReviewRef: publicRef,
            title: safeTitle(pack.title, role: role),
            category: pack.category,
            state: role == .child && state == .blocked ? .frozen : state,
            statusLabel: statusLabel(role: role, state: state, pack: pack, cloudState: cloudState, dispute: dispute),
            lifecycleLabel: lifecycleLabel(role: role, pack: pack, cloudState: cloudState),
            progressLabel: progressLabel(role: role, completed: completed, incomplete: incomplete, preservesCompleted: preservesCompleted, freezesIncomplete: freezesIncomplete),
            creditBoundaryLabel: creditBoundaryLabel(role: role, rollbackReview: rollbackReview, creditFrozen: creditFrozen),
            nextStep: nextStep(role: role, state: state),
            safetyNote: safetyNote(role: role, state: state),
            creatorFeedback: creatorFeedback(role: role, dispute: dispute),
            visibleToChild: role == .child,
            visibleToGuardian: role == .guardian,
            visibleToCreator: role == .creator,
            refundWindowOpen: pack.refundWindowOpen,
            revokedOrDelisted: revokedOrDelisted,
            qualityDisputeOpen: qualityOpen,
            preservesCompletedProgress: preservesCompleted,
            freezesIncompleteTasks: freezesIncomplete,
            creditRollbackReviewNeeded: rollbackReview
        )
    }

    private func findingRows(
        role: MobileGrowthPackRefundDisputeRole,
        rows: [MobileGrowthPackRefundDisputeRow]
    ) -> [MobileGrowthPackRefundDisputeFinding] {
        var findings: [MobileGrowthPackRefundDisputeFinding] = [
            finding(.readOnlyReady, readOnlyMessage(for: role), false, child: true, guardian: true, creator: true)
        ]
        if rows.contains(where: \.refundWindowOpen) {
            findings.append(finding(.refundWindowReview, "存在退款窗口或售后时限，需要家长在真实支付系统外确认。", true, child: false, guardian: true, creator: false))
        }
        if rows.contains(where: \.revokedOrDelisted) {
            findings.append(finding(.revocationOrDelistBlocked, "已退款、撤权、过期或下架的成长包不能继续产生新任务。", true, child: false, guardian: true, creator: false))
        }
        if rows.contains(where: \.qualityDisputeOpen) {
            findings.append(finding(.qualityDisputeFrozen, "质量反馈处理中，未完成任务和成长积分建议保持冻结。", true, child: false, guardian: true, creator: true))
        }
        if rows.contains(where: \.preservesCompletedProgress) {
            findings.append(finding(.progressRetentionReview, "已完成学习记录保留为只读历史，不因售后复核自动删除。", false, child: false, guardian: true, creator: false))
        }
        if rows.contains(where: \.creditRollbackReviewNeeded) {
            findings.append(finding(.creditRollbackReview, "成长积分冻结或回滚建议只进入复核，不改正式成长积分记录。", true, child: false, guardian: true, creator: false))
        }
        if role == .creator {
            findings.append(finding(.creatorFeedbackRedacted, "已应用创作者脱敏反馈视角。", false, child: false, guardian: false, creator: true))
        }
        return findings
    }

    private func readOnlyMessage(for role: MobileGrowthPackRefundDisputeRole) -> String {
        switch role {
        case .child:
            return "复核壳只读，不改变任务、成长积分或娱乐时间。"
        case .guardian:
            return "复核壳只读，不触发真实售后、授权、正式记录、通知或设备动作。"
        case .creator:
            return "复核壳只读，只展示脱敏反馈和版本改进提示。"
        }
    }

    private func isVisible(_ row: MobileGrowthPackRefundDisputeRow, to role: MobileGrowthPackRefundDisputeRole) -> Bool {
        switch role {
        case .child: return row.visibleToChild
        case .guardian: return row.visibleToGuardian
        case .creator: return row.visibleToCreator
        }
    }

    private func statusLabel(
        role: MobileGrowthPackRefundDisputeRole,
        state: MobileGrowthPackRefundDisputeState,
        pack: GrowthPackInstallPackInput,
        cloudState: GrowthPackCloudSyncMobileBridgeCloudState,
        dispute: MobileGrowthPackQualityDisputeInput?
    ) -> String {
        if role == .child {
            switch state {
            case .active: return "可以继续"
            case .reviewRequired, .frozen, .blocked: return "暂时暂停，等待家庭安排"
            case .hidden: return "不可见"
            }
        }
        if role == .creator {
            if let dispute, dispute.status != .none { return "收到脱敏质量反馈" }
            return "公开生命周期正常"
        }
        if pack.refundWindowOpen { return "售后窗口需复核" }
        if pack.entitlementState == .refunded { return "已退款，停止新任务" }
        if pack.entitlementState == .revoked { return "已撤权，停止新任务" }
        if pack.listingState == .delisted || cloudState == .delisted { return "已下架，停止新任务" }
        if dispute.map({ ![.none, .resolved].contains($0.status) }) == true { return "质量争议处理中" }
        if cloudState == .stale { return "云镜像过期，需对账" }
        return "可继续观察"
    }

    private func lifecycleLabel(
        role: MobileGrowthPackRefundDisputeRole,
        pack: GrowthPackInstallPackInput,
        cloudState: GrowthPackCloudSyncMobileBridgeCloudState
    ) -> String {
        if role == .child { return "家长会处理可用内容" }
        if role == .creator { return "只显示脱敏版本和生命周期提示" }
        return "\(pack.listingState.label) · \(pack.entitlementState.label) · \(cloudState.label)"
    }

    private func progressLabel(
        role: MobileGrowthPackRefundDisputeRole,
        completed: Int,
        incomplete: Int,
        preservesCompleted: Bool,
        freezesIncomplete: Bool
    ) -> String {
        if role == .child {
            return preservesCompleted ? "已完成记录会保留" : "继续完成可用安排"
        }
        if role == .creator {
            return "只看汇总反馈，不看个体进度"
        }
        let completedText = preservesCompleted ? "\(completed) 项已完成记录保留" : "\(completed) 项已完成"
        let incompleteText = freezesIncomplete ? "\(incomplete) 项未完成任务冻结" : "\(incomplete) 项可继续复核"
        return "\(completedText) · \(incompleteText)"
    }

    private func creditBoundaryLabel(
        role: MobileGrowthPackRefundDisputeRole,
        rollbackReview: Bool,
        creditFrozen: Bool
    ) -> String {
        if role == .child { return "不会直接改变成长积分" }
        if role == .creator { return "只保留版本改进提示" }
        if creditFrozen { return "成长积分建议冻结，等待家长复核" }
        return rollbackReview ? "回滚建议只读，不改正式成长积分记录" : "无成长积分回滚动作"
    }

    private func nextStep(
        role: MobileGrowthPackRefundDisputeRole,
        state: MobileGrowthPackRefundDisputeState
    ) -> String {
        switch role {
        case .child:
            return state == .active ? "继续今天可用的学习安排。" : "先做可用安排，等待家长处理。"
        case .guardian:
            return state == .active ? "可继续观察，无需立即处理。" : "进入人工复核，确认进度、成长积分和权益边界。"
        case .creator:
            return "查看脱敏反馈，准备版本或内容改进。"
        }
    }

    private func safetyNote(
        role: MobileGrowthPackRefundDisputeRole,
        state: MobileGrowthPackRefundDisputeState
    ) -> String {
        if role == .child {
            return state == .active ? "本页不会改变任务或成长积分。" : "暂停项不会自动改变成长积分或娱乐时间。"
        }
        if role == .creator { return "只展示脱敏质量反馈和版本提示。" }
        return "这里只读展示复核建议，不执行售后、不恢复授权、不改正式记录、不通知、不解锁设备。"
    }

    private func creatorFeedback(
        role: MobileGrowthPackRefundDisputeRole,
        dispute: MobileGrowthPackQualityDisputeInput?
    ) -> String? {
        guard role == .creator else { return nil }
        guard let dispute, dispute.status != .none else { return "暂无质量反馈。" }
        if Self.hasUnsafeCreatorFeedback(dispute.creatorVisibleSummary) {
            return "已收到脱敏质量反馈。"
        }
        return dispute.creatorVisibleSummary
    }

    private static func hasUnsafeCreatorFeedback(_ value: String) -> Bool {
        if hasUnsafeDisplayPayload([value]) { return true }
        let lowered = value.lowercased()
        return creatorFeedbackPrivateMarkers.contains { lowered.contains($0.lowercased()) }
    }

    private func safeTitle(_ title: String, role: MobileGrowthPackRefundDisputeRole) -> String {
        role == .creator ? "成长包质量反馈" : title
    }

    private func title(for role: MobileGrowthPackRefundDisputeRole) -> String {
        switch role {
        case .child:
            return "成长包安全处理"
        case .guardian:
            return "退款撤权质量争议复核"
        case .creator:
            return "成长包质量反馈复核"
        }
    }

    private func finding(
        _ code: MobileGrowthPackRefundDisputeFindingCode,
        _ message: String,
        _ actionRequired: Bool,
        child: Bool,
        guardian: Bool,
        creator: Bool
    ) -> MobileGrowthPackRefundDisputeFinding {
        MobileGrowthPackRefundDisputeFinding(
            code: code,
            message: message,
            actionRequired: actionRequired,
            visibleToChild: child,
            visibleToGuardian: guardian,
            visibleToCreator: creator
        )
    }

    private func safeFallback(
        role: MobileGrowthPackRefundDisputeRole,
        hiddenCount: Int
    ) -> MobileGrowthPackRefundDisputeWorkbench {
        let finding = MobileGrowthPackRefundDisputeFinding(
            code: .unsafePayloadBlocked,
            message: "输入包含不安全展示内容，已进入只读阻断壳。",
            actionRequired: true,
            visibleToChild: role == .child,
            visibleToGuardian: role == .guardian,
            visibleToCreator: role == .creator
        )
        return MobileGrowthPackRefundDisputeWorkbench(
            role: role,
            title: title(for: role),
            subtitle: "\(hiddenCount) 个成长包 · 已阻断",
            audienceNote: role.audienceNote,
            rows: [],
            findings: [finding],
            publicSummary: MobileGrowthPackRefundDisputePublicSummary(
                role: role,
                packCount: hiddenCount,
                visiblePackCount: 0,
                reviewRequiredCount: 0,
                frozenCount: 0,
                blockedCount: hiddenCount,
                completedProgressPreservedCount: 0,
                creditRollbackReviewCount: 0,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private static func publicRef(prefix: String, seed: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in Array(seed.utf8) {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return "\(prefix)-\(String(hash, radix: 36))"
    }
}

extension MobileGrowthPackRefundDisputeInput {
    static let mock = MobileGrowthPackRefundDisputeInput(
        generatedAt: "2026-06-24T22:50:00Z",
        installInput: .mock,
        cloudStateByPackSeed: [
            "electric-basics-v1": .fresh,
            "morning-routine-v2": .stale,
            "creator-art-vlog": .fresh,
            "old-game-proof": .delisted
        ],
        qualityDisputes: [
            MobileGrowthPackQualityDisputeInput(
                packSeed: "creator-art-vlog",
                status: .underReview,
                reason: .contentQuality,
                creatorVisibleSummary: "有脱敏反馈提示内容讲解节奏需要更清楚。"
            ),
            MobileGrowthPackQualityDisputeInput(
                packSeed: "old-game-proof",
                status: .opened,
                reason: .safetyConcern,
                creatorVisibleSummary: "有脱敏反馈提示需补充安全说明。"
            )
        ],
        completedProgressByPackSeed: [
            "electric-basics-v1": 4,
            "morning-routine-v2": 2,
            "creator-art-vlog": 5,
            "old-game-proof": 1
        ],
        incompleteTasksByPackSeed: [
            "electric-basics-v1": 1,
            "morning-routine-v2": 3,
            "creator-art-vlog": 2,
            "old-game-proof": 4
        ],
        creditFrozenByPackSeed: [
            "creator-art-vlog": true,
            "old-game-proof": true
        ],
        unsafePayload: []
    )
}
