import Foundation

/// 成长积分 → 屏幕时间的兑换汇率（家长设定）。
enum ScreenExchangeRate: String, Codable, CaseIterable {
    /// 1 成长积分 = 1 分钟（默认）。
    case onePointPerMinute = "one_point_per_minute"
    /// 2 成长积分 = 1 分钟（更严格）。
    case twoPointsPerMinute = "two_points_per_minute"
    /// 1 成长积分 = 2 分钟（更宽松）。
    case onePointPerTwoMinutes = "one_point_per_two_minutes"

    var label: String {
        switch self {
        case .onePointPerMinute: return "1 成长积分 = 1 分钟屏幕时间"
        case .twoPointsPerMinute: return "2 成长积分 = 1 分钟屏幕时间"
        case .onePointPerTwoMinutes: return "1 成长积分 = 2 分钟屏幕时间"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .onePointPerMinute: return "1 Growth Point = 1 minute"
        case .twoPointsPerMinute: return "2 Growth Points = 1 minute"
        case .onePointPerTwoMinutes: return "1 Growth Point = 2 minutes"
        }
    }

    /// 解锁 minutes 分钟需要的成长积分（向上取整，不让孩子占整数便宜）。
    func pointsRequired(forMinutes minutes: Int) -> Int {
        switch self {
        case .onePointPerMinute: return minutes
        case .twoPointsPerMinute: return minutes * 2
        case .onePointPerTwoMinutes: return (minutes + 1) / 2
        }
    }
}

/// 基础零花钱发放周期。
enum AllowanceCycle: String, Codable, CaseIterable {
    case monthly
    case weekly
    case daily

    var label: String {
        switch self {
        case .monthly: return "每月"
        case .weekly: return "每周"
        case .daily: return "每天"
        }
    }
}

/// 家长为每个孩子设定的兑换机制。
struct FamilyExchangePolicy: Codable, Equatable {
    /// 基础零花钱周期（旧数据缺省为每月）。
    var allowanceCycle: AllowanceCycle?
    /// 每周期基础零花钱（货币单位整数，0 = 不发底薪）。
    var baseMonthlyAllowance: Int
    /// 每月几号入账（1-28，避免月末不存在的日期）。
    var allowanceDayOfMonth: Int
    /// 屏幕时间汇率。
    var screenRate: ScreenExchangeRate
    /// 家长自定义每 15 分钟所需成长积分；旧数据为 nil 时继续使用预设汇率。
    var customScreenPointsPer15Minutes: Int? = nil
    /// 自定义兑换的一份时长；旧数据缺省为 15 分钟。
    var customScreenExchangeMinutes: Int? = nil
    /// 多少成长积分兑换 1 个货币单位（如 10 积分 = ¥1）。
    var pointsPerCurrencyUnit: Int
    /// 零花钱兑换是否需要家长批准（默认需要——钱最终是家长掏的）。
    var pocketMoneyRequiresApproval: Bool
    /// 每月零花钱兑换上限（货币单位）；nil = 不限。
    var monthlyPocketMoneyCap: Int?
    /// 货币符号。
    var currencySymbol: String

    var resolvedCycle: AllowanceCycle { allowanceCycle ?? .monthly }

    var resolvedScreenPointsPer15Minutes: Int {
        max(1, customScreenPointsPer15Minutes ?? screenRate.pointsRequired(forMinutes: 15))
    }

    var resolvedScreenExchangeMinutes: Int {
        min(720, max(1, customScreenExchangeMinutes ?? 15))
    }

    func screenPointsRequired(forMinutes minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        if customScreenPointsPer15Minutes != nil {
            return Int(ceil(Double(minutes * resolvedScreenPointsPer15Minutes) / Double(resolvedScreenExchangeMinutes)))
        }
        return screenRate.pointsRequired(forMinutes: minutes)
    }

    var screenRateLabel: String {
        if customScreenPointsPer15Minutes != nil {
            return "每 \(resolvedScreenExchangeMinutes) 分钟需要 \(resolvedScreenPointsPer15Minutes) 成长积分"
        }
        return screenRate.label
    }

    func screenRateLabel(for language: AppInterfaceLanguage) -> String {
        if customScreenPointsPer15Minutes != nil {
            return language.pick(
                "每 \(resolvedScreenExchangeMinutes) 分钟需要 \(resolvedScreenPointsPer15Minutes) 成长积分",
                "\(resolvedScreenPointsPer15Minutes) Growth Points per \(resolvedScreenExchangeMinutes) minutes"
            )
        }
        return screenRate.label(for: language)
    }

    static let `default` = FamilyExchangePolicy(
        allowanceCycle: .monthly,
        baseMonthlyAllowance: 0,
        allowanceDayOfMonth: 1,
        screenRate: .onePointPerMinute,
        customScreenPointsPer15Minutes: nil,
        pointsPerCurrencyUnit: 10,
        pocketMoneyRequiresApproval: true,
        monthlyPocketMoneyCap: nil,
        currencySymbol: "¥"
    )
}

/// 零花钱账本条目类型。
enum MoneyLedgerEntryKind: String, Codable {
    /// 每月基础零花钱（自动入账）。
    case baseAllowance = "base_allowance"
    /// 成长积分兑换所得。
    case creditExchange = "credit_exchange"
    /// 家长手动调整（可为负）。
    case parentAdjustment = "parent_adjustment"

    var label: String {
        switch self {
        case .baseAllowance: return "每月零花钱"
        case .creditExchange: return "成长积分兑换"
        case .parentAdjustment: return "家长调整"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .baseAllowance: return "Monthly allowance"
        case .creditExchange: return "Growth Points exchange"
        case .parentAdjustment: return "Parent adjustment"
        }
    }
}

/// 零花钱条目状态。App 只记账，真实现金由家长线下给（不接任何支付）。
enum MoneyLedgerEntryStatus: String, Codable {
    /// 等家长批准（成长积分已先扣作押金，驳回时退回）。
    case awaitingApproval = "awaiting_approval"
    /// 已批准/已入账，等家长线下把钱给孩子。
    case pendingPayout = "pending_payout"
    /// 家长已把钱给了孩子并划账。
    case paid
    /// 家长驳回（成长积分已退回）。
    case rejected

    var label: String {
        switch self {
        case .awaitingApproval: return "等大人确认"
        case .pendingPayout: return "待发放"
        case .paid: return "已发放"
        case .rejected: return "已驳回"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .awaitingApproval: return "Waiting for a grown-up"
        case .pendingPayout: return "On its way"
        case .paid: return "Paid"
        case .rejected: return "Not approved"
        }
    }
}

/// 孩子的愿望清单条目。
/// 流程：孩子提愿望 → 家长定成长积分价格（或驳回）→ 孩子积分够了兑换（扣分）→
/// 家长兑现后划账。愿望可以是实物、活动或特权，由家长线下兑现。
enum WishStatus: String, Codable {
    /// 孩子刚提出，等家长定价。
    case proposed
    /// 家长已定价，孩子攒够分可兑换。
    case priced
    /// 孩子已用成长积分兑换，等家长兑现。
    case redeemed
    /// 家长已兑现。
    case fulfilled
    /// 家长驳回。
    case rejected

    var label: String {
        switch self {
        case .proposed: return "等大人定价"
        case .priced: return "可以兑换"
        case .redeemed: return "等大人兑现"
        case .fulfilled: return "已实现"
        case .rejected: return "没通过"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .proposed: return "Waiting for a price"
        case .priced: return "Ready to redeem"
        case .redeemed: return "Waiting for a grown-up"
        case .fulfilled: return "Came true"
        case .rejected: return "Not approved"
        }
    }
}

struct WishListItem: Identifiable, Codable, Equatable {
    let id: UUID
    var childId: UUID
    var title: String
    var note: String
    var status: WishStatus
    /// 家长定的成长积分价格；proposed/rejected 时为 nil。
    var pricePoints: Int?
    var createdAt: Date
}

/// 零花钱账本条目（纯记账）。
struct MoneyLedgerEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var childId: UUID
    var kind: MoneyLedgerEntryKind
    /// 货币单位整数金额；parentAdjustment 可为负。
    var amount: Int
    /// creditExchange 时扣掉的成长积分（驳回时按此退回）。
    var pointsSpent: Int?
    var status: MoneyLedgerEntryStatus
    var note: String
    var createdAt: Date
}
