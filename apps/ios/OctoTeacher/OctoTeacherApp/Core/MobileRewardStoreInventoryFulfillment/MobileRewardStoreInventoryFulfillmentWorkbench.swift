import Foundation

/// iOS 奖励商店库存与履约的本地只读安全壳。
///
/// 该层只把 RewardRedemptionView、RewardStatusView、MobileChildCreditWallet、
/// MobileCreditSettlement、MobileOfflineOutbox/Replay 和 reward-store-inventory-fulfillment-audit
/// 的语义组合成孩子/家长视角，不接真实兑换、库存、账本、订单、物流、通知或设备控制。
/// 页面不真实兑换、不扣成长积分、不发货、不写账本、不通知、不解锁设备。
enum MobileRewardStoreFulfillmentRole: String, CaseIterable, Equatable {
    case child
    case guardian

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        }
    }

    var audienceNote: String {
        switch self {
        case .child:
            return "这里只看可以换什么、还剩多少、需不需要等家长帮忙，以及下一步怎么做。"
        case .guardian:
            return "只读复核库存售罄/超卖、兑换预留、重复扣成长积分、履约失败、退款取消回滚建议、实物地址确认、设备时长上限和离线回放。"
        }
    }
}

/// 奖励种类：数字、实物、设备时长。
enum MobileRewardStoreItemKind: String, Equatable {
    case digital
    case physical
    case deviceTime

    var childLabel: String {
        switch self {
        case .digital: return "线上奖励"
        case .physical: return "实物奖励"
        case .deviceTime: return "娱乐时间"
        }
    }

    var guardianLabel: String {
        switch self {
        case .digital: return "数字奖励"
        case .physical: return "实物奖励"
        case .deviceTime: return "设备时长奖励"
        }
    }
}

/// 库存状态。oversold 表示出现超卖需对账。
enum MobileRewardStoreInventoryState: String, Equatable {
    case inStock
    case lowStock
    case reserved
    case soldOut
    case oversold

    var guardianLabel: String {
        switch self {
        case .inStock: return "有库存"
        case .lowStock: return "库存偏低"
        case .reserved: return "已预留待履约"
        case .soldOut: return "已售罄"
        case .oversold: return "超卖需对账"
        }
    }
}

/// 履约状态。仅本地语义，不代表真实订单或物流。
enum MobileRewardStoreFulfillmentState: String, Equatable {
    case none
    case pending
    case awaitingAddress
    case failed
    case cancelled
    case refunded
    case completed

    var guardianLabel: String {
        switch self {
        case .none: return "未发起履约"
        case .pending: return "履约处理中"
        case .awaitingAddress: return "等待地址确认"
        case .failed: return "履约失败"
        case .cancelled: return "已取消"
        case .refunded: return "已退款"
        case .completed: return "履约完成"
        }
    }
}

/// 行级综合展示状态，用于孩子端脱敏。
enum MobileRewardStoreFulfillmentDisplayState: String, Equatable {
    case redeemable
    case reserved
    case needsParent
    case unavailable

    var label: String {
        switch self {
        case .redeemable: return "可兑换"
        case .reserved: return "处理中"
        case .needsParent: return "待家长处理"
        case .unavailable: return "暂不可兑换"
        }
    }
}

enum MobileRewardStoreFulfillmentFindingCode: String, Equatable {
    case readOnlyReady = "READ_ONLY_READY"
    case inventorySoldOutOrOversold = "INVENTORY_SOLD_OUT_OR_OVERSOLD"
    case redemptionReserved = "REDEMPTION_RESERVED"
    case duplicateCreditDeduction = "DUPLICATE_CREDIT_DEDUCTION"
    case fulfillmentFailed = "FULFILLMENT_FAILED"
    case refundCancelRollbackReview = "REFUND_CANCEL_ROLLBACK_REVIEW"
    case physicalAddressConfirmation = "PHYSICAL_ADDRESS_CONFIRMATION"
    case deviceTimeCapReview = "DEVICE_TIME_CAP_REVIEW"
    case offlineReplayPending = "OFFLINE_REPLAY_PENDING"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

struct MobileRewardStoreItemInput: Equatable {
    var itemSeed: String
    var orderSeed: String?
    var redemptionSeed: String?
    var title: String
    var category: String
    var kind: MobileRewardStoreItemKind
    var inventory: MobileRewardStoreInventoryState
    var fulfillment: MobileRewardStoreFulfillmentState
    var duplicateCreditDeduction: Bool
    var addressConfirmed: Bool
    var deviceMinutesRequested: Int
    var deviceDailyCapMinutes: Int
    var offlineReplayPending: Bool
    var expired: Bool

    init(
        itemSeed: String,
        orderSeed: String? = nil,
        redemptionSeed: String? = nil,
        title: String,
        category: String,
        kind: MobileRewardStoreItemKind,
        inventory: MobileRewardStoreInventoryState,
        fulfillment: MobileRewardStoreFulfillmentState = .none,
        duplicateCreditDeduction: Bool = false,
        addressConfirmed: Bool = true,
        deviceMinutesRequested: Int = 0,
        deviceDailyCapMinutes: Int = 0,
        offlineReplayPending: Bool = false,
        expired: Bool = false
    ) {
        self.itemSeed = itemSeed
        self.orderSeed = orderSeed
        self.redemptionSeed = redemptionSeed
        self.title = title
        self.category = category
        self.kind = kind
        self.inventory = inventory
        self.fulfillment = fulfillment
        self.duplicateCreditDeduction = duplicateCreditDeduction
        self.addressConfirmed = addressConfirmed
        self.deviceMinutesRequested = deviceMinutesRequested
        self.deviceDailyCapMinutes = deviceDailyCapMinutes
        self.offlineReplayPending = offlineReplayPending
        self.expired = expired
    }
}

struct MobileRewardStoreFulfillmentInput: Equatable {
    var generatedAt: String
    var familySeed: String
    var childSeed: String
    var items: [MobileRewardStoreItemInput]
    var unsafePayload: [String]
}

struct MobileRewardStoreFulfillmentRow: Identifiable, Equatable {
    var publicReviewRef: String
    var title: String
    var category: String
    var kindLabel: String
    var state: MobileRewardStoreFulfillmentDisplayState
    var availabilityLabel: String
    var fulfillmentLabel: String
    var creditBoundaryLabel: String
    var deviceCapLabel: String
    var nextStep: String
    var safetyNote: String
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var soldOutOrOversold: Bool
    var reserved: Bool
    var duplicateCreditDeduction: Bool
    var fulfillmentFailed: Bool
    var refundOrCancelRollback: Bool
    var addressConfirmationNeeded: Bool
    var deviceCapExceeded: Bool
    var offlineReplayPending: Bool

    let redeemsReward = false
    let deductsCredit = false
    let shipsGoods = false
    let writesOrder = false
    let writesInventory = false
    let writesRedemption = false
    let writesLedger = false
    let refundsPayment = false
    let rollsBack = false
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
            kindLabel,
            state.rawValue,
            state.label,
            availabilityLabel,
            fulfillmentLabel,
            creditBoundaryLabel,
            deviceCapLabel,
            nextStep,
            safetyNote
        ]
    }

    var hasTriggeredSideEffect: Bool {
        redeemsReward || deductsCredit || shipsGoods || writesOrder || writesInventory
            || writesRedemption || writesLedger || refundsPayment || rollsBack || grantsBadge
            || mutatesAbilityCard || unlocksDevice || sendsNotification || callsNetwork
            || opensStoreKit || callsAI || writesSchoolSystem
    }
}

struct MobileRewardStoreFulfillmentFinding: Identifiable, Equatable {
    var code: MobileRewardStoreFulfillmentFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool
    var visibleToGuardian: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileRewardStoreFulfillmentPublicSummary: Equatable {
    var role: MobileRewardStoreFulfillmentRole
    var itemCount: Int
    var visibleItemCount: Int
    var redeemableCount: Int
    var needsParentCount: Int
    var unavailableCount: Int
    var reservedCount: Int
    var fulfillmentRiskCount: Int
    var findingCodes: [MobileRewardStoreFulfillmentFindingCode]

    let redeemsReward = false
    let deductsCredit = false
    let shipsGoods = false
    let writesOrder = false
    let writesInventory = false
    let writesRedemption = false
    let writesLedger = false
    let refundsPayment = false
    let rollsBack = false
    let grantsBadge = false
    let mutatesAbilityCard = false
    let unlocksDevice = false
    let sendsNotification = false
    let callsNetwork = false
    let opensStoreKit = false
    let callsAI = false
    let writesSchoolSystem = false

    var hasTriggeredSideEffect: Bool {
        redeemsReward || deductsCredit || shipsGoods || writesOrder || writesInventory
            || writesRedemption || writesLedger || refundsPayment || rollsBack || grantsBadge
            || mutatesAbilityCard || unlocksDevice || sendsNotification || callsNetwork
            || opensStoreKit || callsAI || writesSchoolSystem
    }
}

struct MobileRewardStoreInventoryFulfillmentWorkbench: Equatable {
    var role: MobileRewardStoreFulfillmentRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var rows: [MobileRewardStoreFulfillmentRow]
    var findings: [MobileRewardStoreFulfillmentFinding]
    var publicSummary: MobileRewardStoreFulfillmentPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + rows.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileRewardStoreInventoryFulfillmentBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileRewardStoreInventoryFulfillmentBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "guardian:", "reward:", "item:", "inventory:",
        "redemption:", "gift:", "order:", "ledger:", "device:", "address:",
        "claim:", "task:", "ref:", "退款金额", "退款原因", "成长积分金额", "账本",
        "订单号", "库存 id", "履约地址", "收货地址", "设备命令", "成人责任原因",
        "家长预算", "publicref", "http://", "https://", "file://",
        "/users/", "/volumes/", "192.168."
    ]
    private static let sensitivePatterns = [
        "(?i)\\b(?:access|device|session|api|bearer)[ _-]?token\\b",
        "(?i)\\b(?:api|server|client)[ _-]?secret\\b",
        "(?i)\\bapi[_-]?key\\b",
        "(?i)\\bcredit[ _-]?amount\\b",
        "(?i)\\b(?:order|inventory|redemption|gift|ledger|device)[ _-]?id\\b",
        "(?i)\\brefund[ _-]?(?:id|amount|reason)\\b"
    ]

    func build(
        role: MobileRewardStoreFulfillmentRole,
        input: MobileRewardStoreFulfillmentInput = .mock
    ) -> MobileRewardStoreInventoryFulfillmentWorkbench {
        if Self.hasUnsafeInput(input) {
            return safeFallback(role: role, hiddenCount: input.items.count)
        }

        let rows = input.items.map { row(role: role, item: $0) }
        let findings = findingRows(role: role, rows: rows)
        let visibleFindings = findings.filter { finding in
            role == .child ? finding.visibleToChild : finding.visibleToGuardian
        }
        let summary = MobileRewardStoreFulfillmentPublicSummary(
            role: role,
            itemCount: rows.count,
            visibleItemCount: rows.count,
            redeemableCount: rows.filter { $0.state == .redeemable }.count,
            needsParentCount: rows.filter { $0.state == .needsParent }.count,
            unavailableCount: rows.filter { $0.state == .unavailable }.count,
            reservedCount: rows.filter { $0.state == .reserved }.count,
            fulfillmentRiskCount: rows.filter { $0.fulfillmentFailed || $0.refundOrCancelRollback }.count,
            findingCodes: visibleFindings.map(\.code)
        )
        let workbench = MobileRewardStoreInventoryFulfillmentWorkbench(
            role: role,
            title: title(for: role),
            subtitle: "\(input.items.count) 个奖励 · 本地只读",
            audienceNote: role.audienceNote,
            rows: rows,
            findings: visibleFindings,
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? safeFallback(role: role, hiddenCount: input.items.count) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        if sensitiveMarkers.contains(where: { joined.contains($0) }) { return true }
        return sensitivePatterns.contains { pattern in
            joined.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func hasUnsafeInput(_ input: MobileRewardStoreFulfillmentInput) -> Bool {
        let itemValues = input.items.flatMap {
            [$0.title, $0.category, $0.itemSeed, $0.orderSeed ?? "", $0.redemptionSeed ?? ""]
        }
        return hasUnsafeDisplayPayload(
            [input.generatedAt, input.familySeed, input.childSeed] + itemValues + input.unsafePayload
        )
    }

    private func row(
        role: MobileRewardStoreFulfillmentRole,
        item: MobileRewardStoreItemInput
    ) -> MobileRewardStoreFulfillmentRow {
        let soldOutOrOversold = [.soldOut, .oversold].contains(item.inventory)
        let fulfillmentFailed = item.fulfillment == .failed
        let refundOrCancel = [.cancelled, .refunded].contains(item.fulfillment)
        let addressNeeded = item.kind == .physical
            && !item.addressConfirmed
            && ![.none, .cancelled, .refunded].contains(item.fulfillment)
        let deviceCapExceeded = item.kind == .deviceTime
            && item.deviceDailyCapMinutes > 0
            && item.deviceMinutesRequested > item.deviceDailyCapMinutes
        let reserved = item.inventory == .reserved || item.fulfillment == .pending

        let state: MobileRewardStoreFulfillmentDisplayState
        if soldOutOrOversold || item.expired || fulfillmentFailed {
            state = .unavailable
        } else if item.duplicateCreditDeduction || refundOrCancel || addressNeeded || deviceCapExceeded {
            state = .needsParent
        } else if reserved || item.offlineReplayPending {
            state = .reserved
        } else {
            state = .redeemable
        }

        let publicRef = Self.publicRef(prefix: "rsif", seed: "\(item.itemSeed):\(role.rawValue)")
        return MobileRewardStoreFulfillmentRow(
            publicReviewRef: publicRef,
            title: item.title,
            category: item.category,
            kindLabel: role == .child ? item.kind.childLabel : item.kind.guardianLabel,
            state: state,
            availabilityLabel: availabilityLabel(role: role, item: item, state: state),
            fulfillmentLabel: fulfillmentLabel(role: role, item: item),
            creditBoundaryLabel: creditBoundaryLabel(role: role, item: item),
            deviceCapLabel: deviceCapLabel(role: role, item: item, exceeded: deviceCapExceeded),
            nextStep: nextStep(role: role, state: state),
            safetyNote: safetyNote(role: role, state: state),
            visibleToChild: role == .child,
            visibleToGuardian: role == .guardian,
            soldOutOrOversold: soldOutOrOversold,
            reserved: reserved,
            duplicateCreditDeduction: item.duplicateCreditDeduction,
            fulfillmentFailed: fulfillmentFailed,
            refundOrCancelRollback: refundOrCancel,
            addressConfirmationNeeded: addressNeeded,
            deviceCapExceeded: deviceCapExceeded,
            offlineReplayPending: item.offlineReplayPending
        )
    }

    private func findingRows(
        role: MobileRewardStoreFulfillmentRole,
        rows: [MobileRewardStoreFulfillmentRow]
    ) -> [MobileRewardStoreFulfillmentFinding] {
        var findings: [MobileRewardStoreFulfillmentFinding] = [
            finding(.readOnlyReady, readOnlyMessage(for: role), false, child: true, guardian: true)
        ]
        if rows.contains(where: \.soldOutOrOversold) {
            findings.append(finding(.inventorySoldOutOrOversold, "存在售罄或超卖奖励，需要家长在真实库存系统外对账，不能继续兑换。", true, child: false, guardian: true))
        }
        if rows.contains(where: \.reserved) {
            findings.append(finding(.redemptionReserved, "存在兑换预留或处理中履约，预留只读展示，不锁定真实库存或成长积分。", false, child: false, guardian: true))
        }
        if rows.contains(where: \.duplicateCreditDeduction) {
            findings.append(finding(.duplicateCreditDeduction, "检测到疑似重复扣成长积分，需要家长复核，不在本页冲正或退成长积分。", true, child: false, guardian: true))
        }
        if rows.contains(where: \.fulfillmentFailed) {
            findings.append(finding(.fulfillmentFailed, "存在履约失败奖励，需要家长在正式流程外确认，本页不重试发货。", true, child: false, guardian: true))
        }
        if rows.contains(where: \.refundOrCancelRollback) {
            findings.append(finding(.refundCancelRollbackReview, "退款或取消后的库存与成长积分回滚只进入只读建议，不改正式记录。", true, child: false, guardian: true))
        }
        if rows.contains(where: \.addressConfirmationNeeded) {
            findings.append(finding(.physicalAddressConfirmation, "实物奖励需家长确认收货信息后才能进入履约，本页不展示也不写入地址。", true, child: false, guardian: true))
        }
        if rows.contains(where: \.deviceCapExceeded) {
            findings.append(finding(.deviceTimeCapReview, "设备时长奖励超过每日上限，需要家长复核，本页不解锁设备。", true, child: false, guardian: true))
        }
        if rows.contains(where: \.offlineReplayPending) {
            findings.append(finding(.offlineReplayPending, "存在离线回放待确认，联网回放前不代表真实兑换或履约状态。", false, child: false, guardian: true))
        }
        return findings
    }

    private func readOnlyMessage(for role: MobileRewardStoreFulfillmentRole) -> String {
        switch role {
        case .child:
            return "这个页面只看奖励，不会真的兑换、不会扣成长积分、也不会改变娱乐时间。"
        case .guardian:
            return "复核壳只读，不真实兑换、不扣成长积分、不发货、不写正式记录/订单/库存、不退款、不通知、不解锁设备。"
        }
    }

    private func availabilityLabel(
        role: MobileRewardStoreFulfillmentRole,
        item: MobileRewardStoreItemInput,
        state: MobileRewardStoreFulfillmentDisplayState
    ) -> String {
        if role == .child {
            switch state {
            case .redeemable: return "现在可以换"
            case .reserved: return "正在处理"
            case .needsParent: return "需要家长帮忙"
            case .unavailable: return item.expired ? "已过期" : "暂时换完了"
            }
        }
        if item.expired { return "已过期 · \(item.inventory.guardianLabel)" }
        return item.inventory.guardianLabel
    }

    private func fulfillmentLabel(
        role: MobileRewardStoreFulfillmentRole,
        item: MobileRewardStoreItemInput
    ) -> String {
        if role == .child {
            return "家长会处理领取流程"
        }
        if item.offlineReplayPending {
            return "\(item.fulfillment.guardianLabel) · 离线回放待确认"
        }
        return item.fulfillment.guardianLabel
    }

    private func creditBoundaryLabel(
        role: MobileRewardStoreFulfillmentRole,
        item: MobileRewardStoreItemInput
    ) -> String {
        if role == .child { return "不会直接扣成长积分" }
        if item.duplicateCreditDeduction { return "疑似重复扣成长积分，待家长复核" }
        if [.cancelled, .refunded].contains(item.fulfillment) { return "回滚建议只读，不改正式成长积分记录" }
        if item.fulfillment == .failed { return "履约失败，成长积分按建议保留待复核" }
        return "无成长积分变动"
    }

    private func deviceCapLabel(
        role: MobileRewardStoreFulfillmentRole,
        item: MobileRewardStoreItemInput,
        exceeded: Bool
    ) -> String {
        guard item.kind == .deviceTime else {
            return role == .child ? "不涉及娱乐时间" : "非设备时长奖励"
        }
        if role == .child {
            return exceeded ? "需要家长确认娱乐时间" : "娱乐时间按家庭安排"
        }
        if item.deviceDailyCapMinutes <= 0 { return "未设置每日上限" }
        return exceeded ? "请求超过每日上限，需复核" : "在每日上限内"
    }

    private func nextStep(
        role: MobileRewardStoreFulfillmentRole,
        state: MobileRewardStoreFulfillmentDisplayState
    ) -> String {
        switch role {
        case .child:
            switch state {
            case .redeemable: return "可以告诉家长你想换这个。"
            case .reserved: return "正在处理，先等一等。"
            case .needsParent: return "请家长帮忙看看。"
            case .unavailable: return "换个别的奖励看看吧。"
            }
        case .guardian:
            switch state {
            case .redeemable: return "库存与履约正常，可继续观察。"
            case .reserved: return "确认预留与离线回放后再决定是否履约。"
            case .needsParent: return "进入人工复核，确认库存、成长积分、地址或设备上限。"
            case .unavailable: return "在正式库存系统外对账售罄/超卖或履约失败。"
            }
        }
    }

    private func safetyNote(
        role: MobileRewardStoreFulfillmentRole,
        state: MobileRewardStoreFulfillmentDisplayState
    ) -> String {
        if role == .child {
            return "本页不会真的兑换，也不会改变成长积分或娱乐时间。"
        }
        return "这里只读展示库存与履约建议，不真实兑换、不扣成长积分、不发货、不写正式记录、不退款、不通知、不解锁设备。"
    }

    private func title(for role: MobileRewardStoreFulfillmentRole) -> String {
        switch role {
        case .child: return "奖励商店"
        case .guardian: return "奖励库存履约复核"
        }
    }

    private func finding(
        _ code: MobileRewardStoreFulfillmentFindingCode,
        _ message: String,
        _ actionRequired: Bool,
        child: Bool,
        guardian: Bool
    ) -> MobileRewardStoreFulfillmentFinding {
        MobileRewardStoreFulfillmentFinding(
            code: code,
            message: message,
            actionRequired: actionRequired,
            visibleToChild: child,
            visibleToGuardian: guardian
        )
    }

    private func safeFallback(
        role: MobileRewardStoreFulfillmentRole,
        hiddenCount: Int
    ) -> MobileRewardStoreInventoryFulfillmentWorkbench {
        let finding = MobileRewardStoreFulfillmentFinding(
            code: .unsafePayloadBlocked,
            message: "输入包含不安全展示内容，已进入只读阻断壳。",
            actionRequired: true,
            visibleToChild: role == .child,
            visibleToGuardian: role == .guardian
        )
        return MobileRewardStoreInventoryFulfillmentWorkbench(
            role: role,
            title: title(for: role),
            subtitle: "\(hiddenCount) 个奖励 · 已阻断",
            audienceNote: role.audienceNote,
            rows: [],
            findings: [finding],
            publicSummary: MobileRewardStoreFulfillmentPublicSummary(
                role: role,
                itemCount: hiddenCount,
                visibleItemCount: 0,
                redeemableCount: 0,
                needsParentCount: 0,
                unavailableCount: hiddenCount,
                reservedCount: 0,
                fulfillmentRiskCount: 0,
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

extension MobileRewardStoreFulfillmentInput {
    static let mock = MobileRewardStoreFulfillmentInput(
        generatedAt: "2026-06-24T23:30:00Z",
        familySeed: "family-seed",
        childSeed: "child-seed",
        items: [
            MobileRewardStoreItemInput(
                itemSeed: "sticker-pack",
                title: "贴纸礼包",
                category: "线上奖励",
                kind: .digital,
                inventory: .inStock
            ),
            MobileRewardStoreItemInput(
                itemSeed: "weekend-movie",
                orderSeed: "order-movie",
                redemptionSeed: "redemption-movie",
                title: "周末电影 30 分钟",
                category: "娱乐时间",
                kind: .deviceTime,
                inventory: .reserved,
                fulfillment: .pending,
                deviceMinutesRequested: 30,
                deviceDailyCapMinutes: 60
            ),
            MobileRewardStoreItemInput(
                itemSeed: "long-game",
                orderSeed: "order-game",
                redemptionSeed: "redemption-game",
                title: "额外游戏时间",
                category: "娱乐时间",
                kind: .deviceTime,
                inventory: .lowStock,
                fulfillment: .none,
                deviceMinutesRequested: 120,
                deviceDailyCapMinutes: 60
            ),
            MobileRewardStoreItemInput(
                itemSeed: "story-book",
                orderSeed: "order-book",
                redemptionSeed: "redemption-book",
                title: "故事书",
                category: "实物奖励",
                kind: .physical,
                inventory: .inStock,
                fulfillment: .awaitingAddress,
                addressConfirmed: false
            ),
            MobileRewardStoreItemInput(
                itemSeed: "robot-kit",
                orderSeed: "order-robot",
                redemptionSeed: "redemption-robot",
                title: "拼装机器人",
                category: "实物奖励",
                kind: .physical,
                inventory: .oversold,
                fulfillment: .failed
            ),
            MobileRewardStoreItemInput(
                itemSeed: "art-set",
                orderSeed: "order-art",
                redemptionSeed: "redemption-art",
                title: "绘画套装",
                category: "实物奖励",
                kind: .physical,
                inventory: .inStock,
                fulfillment: .refunded,
                duplicateCreditDeduction: true,
                offlineReplayPending: true
            )
        ],
        unsafePayload: []
    )
}
