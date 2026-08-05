import Foundation

/// 家长首页「今天先看这里」的愿望待办提醒。
///
/// 孩子提出愿望（proposed）后必须由家长定价，孩子端才能显示“还差多少成长积分”；
/// 孩子兑换愿望（redeemed）后必须由家长线下兑现。这两步都发生在零花钱工作台里，
/// 如果首页不提醒，真实家庭测试中家长很容易漏掉，愿望闭环就会卡死。
/// 这里只做只读统计和文案，不携带任何可执行操作。
struct ParentWishActionReminder: Equatable {
    /// 孩子刚提出、等家长定价的愿望数。
    var pricingCount: Int
    /// 孩子已兑换、等家长线下兑现的愿望数。
    var fulfillmentCount: Int

    var total: Int { pricingCount + fulfillmentCount }

    /// 首页入口一行文案；用于 Label 与 VoiceOver。
    var headline: String {
        var parts: [String] = []
        if pricingCount > 0 {
            parts.append("\(pricingCount) 个愿望等你定成长积分价格")
        }
        if fulfillmentCount > 0 {
            parts.append("\(fulfillmentCount) 个愿望等你线下兑现")
        }
        return parts.joined(separator: "，")
    }

    /// 提醒家长为什么要现在处理（定价前孩子看不到差多少分）。
    var detail: String {
        if pricingCount > 0 {
            return "定好价格后，孩子端才会显示还差多少成长积分。"
        }
        return "孩子已经用成长积分兑换，记得线下兑现后点「已兑现」。"
    }

    /// 全家范围统计需要家长动手的愿望；没有待办时返回 nil，首页不显示入口。
    static func build(wishes: [WishListItem]) -> ParentWishActionReminder? {
        let reminder = ParentWishActionReminder(
            pricingCount: wishes.filter { $0.status == .proposed }.count,
            fulfillmentCount: wishes.filter { $0.status == .redeemed }.count
        )
        return reminder.total > 0 ? reminder : nil
    }
}
