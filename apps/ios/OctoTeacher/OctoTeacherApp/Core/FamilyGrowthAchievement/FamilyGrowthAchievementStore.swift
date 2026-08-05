import Foundation
import Observation

/// 家庭成长荣誉卡片视图的本地 store。
///
/// 纯本地 mock 数据源 + 可见性裁决，符合任务安全边界：不接真实社交/学校/云端，不发布、
/// 不通知亲友、不发成长积分、不授徽章、不上传媒体。所有 fixture 文本均已脱敏，绝不含真实
/// child/family/relative/badge/honor/journal/vlog/proof/event ID、token、路径或局域网地址。
@Observable
final class FamilyGrowthAchievementStore {
    /// 全部卡片（家庭内部全量；按角色裁决后才对外）。
    private(set) var cards: [FamilyGrowthCard]

    /// 家庭脱敏引用 seed（不展示原文）。
    private let familySeed: String
    /// 孩子脱敏引用 seed（不展示原文）。
    private let childSeed: String

    init(
        cards: [FamilyGrowthCard]? = nil,
        familySeed: String = "family-self",
        childSeed: String = "child-self"
    ) {
        self.cards = cards ?? Self.seedCards()
        self.familySeed = familySeed
        self.childSeed = childSeed
    }

    /// 计算某个角色看到的荣誉卡片汇总。
    func summary(for role: FamilyGrowthViewerRole) -> FamilyGrowthViewerSummary {
        let visible = cards
            .filter { $0.isVisible(to: role) }
            .sorted(by: Self.ordering)

        var kindCounts: [FamilyGrowthCardKind: Int] = [:]
        var visibilityCounts: [FamilyGrowthCardVisibility: Int] = [:]
        for card in visible {
            kindCounts[card.kind, default: 0] += 1
            visibilityCounts[card.visibility, default: 0] += 1
        }

        return FamilyGrowthViewerSummary(
            role: role,
            familyPublicRef: FamilyGrowthRedaction.publicRef(prefix: "family", source: familySeed),
            childPublicRef: FamilyGrowthRedaction.publicRef(prefix: "child", source: childSeed),
            cards: visible,
            kindCounts: kindCounts,
            visibilityCounts: visibilityCounts
        )
    }

    /// 当前角色可见、且属于某来源种类的卡片。
    func cards(of kind: FamilyGrowthCardKind, for role: FamilyGrowthViewerRole) -> [FamilyGrowthCard] {
        summary(for: role).cards.filter { $0.kind == kind }
    }

    /// 排序：先按来源种类固定顺序，正式荣誉在前，再按标题稳定排序（无时钟/无随机）。
    private static func ordering(_ lhs: FamilyGrowthCard, _ rhs: FamilyGrowthCard) -> Bool {
        let li = kindOrder(lhs.kind)
        let ri = kindOrder(rhs.kind)
        if li != ri { return li < ri }
        if lhs.isFormalHonor != rhs.isFormalHonor { return lhs.isFormalHonor && !rhs.isFormalHonor }
        return lhs.title < rhs.title
    }

    private static func kindOrder(_ kind: FamilyGrowthCardKind) -> Int {
        switch kind {
        case .storyline: return 0
        case .honorWall: return 1
        case .badge: return 2
        case .growthCard: return 3
        case .journal: return 4
        case .relativeComment: return 5
        case .vlogPlaceholder: return 6
        }
    }

    // MARK: - 本地脱敏 fixture

    /// 覆盖每种来源、每种可见范围、每种生命周期状态的本地示例卡片。
    static func seedCards() -> [FamilyGrowthCard] {
        [
            // 故事线摘要（家庭可见，鼓励式）。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "storyline-month",
                kind: .storyline,
                title: "这个月的成长故事线",
                summary: "从坚持晨读到主动整理书桌，一点点把好习惯串成了线。",
                occurredLabel: "本月",
                visibility: .family,
                lifecycle: .published,
                supportiveCopy: "每一个小坚持都算数，你正在长成更喜欢的自己。",
                nextStep: "可以和家长一起挑一个下个月想继续保持的小目标。",
                tags: ["坚持", "习惯"],
                allowsRelative: false,
                reactionCount: 3,
                approvedCommentCount: 1,
                ratings: nil
            ),
            // 荣誉墙：已通过、对亲友开放。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "honor-reading-star",
                kind: .honorWall,
                title: "阅读之星",
                summary: "连续两周完成每日阅读打卡，被家长点亮上墙。",
                occurredLabel: "上周",
                visibility: .relatives,
                lifecycle: .published,
                supportiveCopy: "你愿意每天翻开一本书，这份专注很珍贵。",
                nextStep: "下周可以试着把读到的一个小故事讲给家人听。",
                tags: ["阅读"],
                allowsRelative: true,
                reactionCount: 5,
                approvedCommentCount: 2,
                ratings: nil
            ),
            // 荣誉墙：待审核（家庭可见，亲友看不到，不作正式荣誉）。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "honor-helper-pending",
                kind: .honorWall,
                title: "家务小帮手",
                summary: "主动帮忙摆碗筷、收拾桌子，等家长确认后上墙。",
                occurredLabel: "今天",
                visibility: .family,
                lifecycle: .pending,
                supportiveCopy: "愿意为家里出一份力，本身就很了不起。",
                nextStep: "等家长确认后，这份荣誉就会正式上墙。",
                tags: ["家务", "责任"],
                allowsRelative: false,
                reactionCount: 0,
                approvedCommentCount: 0,
                ratings: nil
            ),
            // 徽章：已通过、家庭可见。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "badge-early-bird",
                kind: .badge,
                title: "早起鸟徽章",
                summary: "一周里有五天按时起床完成晨间清单。",
                occurredLabel: "本周",
                visibility: .family,
                lifecycle: .published,
                supportiveCopy: "早起不容易，你坚持下来了，给自己点个赞。",
                nextStep: "可以把早起后第一件想做的小事写进成长日记。",
                tags: ["作息"],
                allowsRelative: false,
                reactionCount: 4,
                approvedCommentCount: 0,
                ratings: nil
            ),
            // 成长球星卡：已通过、家庭可见，带能力维度评分。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "card-season",
                kind: .growthCard,
                title: "本月成长球星卡",
                summary: "把任务、习惯和阅读沉淀成本月的能力快照（仅供鼓励，不作排名）。",
                occurredLabel: "本月",
                visibility: .family,
                lifecycle: .published,
                supportiveCopy: "这是你自己的成长曲线，和别人无关，慢慢来就好。",
                nextStep: "挑一个你最想提升的维度，和家长聊聊小计划。",
                tags: ["能力", "成长"],
                allowsRelative: false,
                reactionCount: 2,
                approvedCommentCount: 0,
                ratings: [
                    .knowledge: 72,
                    .habit: 80,
                    .creativity: 65,
                    .social: 70,
                    .health: 78
                ]
            ),
            // 成长日记：私密（仅孩子+家长），已通过。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "journal-private",
                kind: .journal,
                title: "今天的小心情",
                summary: "记录了今天有点紧张但还是举手发言的瞬间。",
                occurredLabel: "今天",
                visibility: .privateOnly,
                lifecycle: .published,
                supportiveCopy: "把心情写下来很勇敢，紧张也没关系，你做到了。",
                nextStep: "想分享的话，可以让家长决定要不要放进家庭圈。",
                tags: ["心情", "勇气"],
                allowsRelative: false,
                reactionCount: 0,
                approvedCommentCount: 0,
                ratings: nil
            ),
            // 成长日记：已撤回（仅家庭内部看到状态）。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "journal-withdrawn",
                kind: .journal,
                title: "一篇被收起的日记",
                summary: "家长和孩子商量后把这篇日记收了起来。",
                occurredLabel: "前几天",
                visibility: .privateOnly,
                lifecycle: .withdrawn,
                supportiveCopy: "收起来也没关系，你的感受一直都被认真对待。",
                nextStep: "随时可以重新写一篇，想留下的回忆都值得记录。",
                tags: ["心情"],
                allowsRelative: false,
                reactionCount: 0,
                approvedCommentCount: 0,
                ratings: nil
            ),
            // 亲友鼓励：已通过、对亲友开放。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "relative-comment-approved",
                kind: .relativeComment,
                title: "来自家人的鼓励",
                summary: "「看到你坚持阅读，真为你高兴！」",
                occurredLabel: "上周",
                visibility: .relatives,
                lifecycle: .published,
                supportiveCopy: "家人的支持会一直陪着你，被惦记是件温暖的事。",
                nextStep: "可以请家长帮你回一句谢谢。",
                tags: ["鼓励"],
                allowsRelative: true,
                reactionCount: 1,
                approvedCommentCount: 1,
                ratings: nil
            ),
            // 亲友鼓励：待审核（家庭可见，亲友看不到）。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "relative-comment-pending",
                kind: .relativeComment,
                title: "一条待审核的鼓励",
                summary: "亲友留了一句鼓励，等家长审核后才会展示给其他亲友。",
                occurredLabel: "今天",
                visibility: .family,
                lifecycle: .pending,
                supportiveCopy: "有人想为你加油，这份心意已经收到了。",
                nextStep: "家长审核通过后，这条鼓励就会出现在亲友视角。",
                tags: ["鼓励"],
                allowsRelative: false,
                reactionCount: 0,
                approvedCommentCount: 0,
                ratings: nil
            ),
            // 视频日记草稿：私密、已通过（不持有真实媒体）。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "vlog-placeholder",
                kind: .vlogPlaceholder,
                title: "成长视频日记草稿",
                summary: "约 1 分钟 · 待家长开启记录；不会自动读取或上传媒体。",
                occurredLabel: "本周",
                visibility: .privateOnly,
                lifecycle: .published,
                supportiveCopy: "等你愿意了，再和家长一起决定要不要记录这段成长。",
                nextStep: "是否拍摄、是否分享，都由家长确认。",
                tags: ["视频日记", "草稿"],
                allowsRelative: false,
                reactionCount: 0,
                approvedCommentCount: 0,
                ratings: nil
            ),
            // 公开分享：已通过且家长批准公开（脱敏摘要）。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "honor-public-share",
                kind: .honorWall,
                title: "公益小达人（已脱敏公开）",
                summary: "参加了社区图书整理活动，家长批准以脱敏摘要形式公开。",
                occurredLabel: "本月",
                visibility: .publicShare,
                lifecycle: .published,
                supportiveCopy: "把善意带给更多人，你让这个世界更暖了一点。",
                nextStep: "公开内容只保留脱敏摘要，具体细节仍只在家庭内可见。",
                tags: ["公益"],
                allowsRelative: false,
                reactionCount: 6,
                approvedCommentCount: 1,
                ratings: nil
            ),
            // 已阻断：审核命中风险，仅家庭内部看到脱敏说明。
            FamilyGrowthCard(
                id: UUID(),
                internalSeed: "journal-blocked",
                kind: .journal,
                title: "一条被阻断的内容",
                summary: "（原文已被审核阻断，这里不应出现任何原文）",
                occurredLabel: "今天",
                visibility: .privateOnly,
                lifecycle: .blocked,
                supportiveCopy: "我们会先帮你把可能不安全的内容挡在外面，你是安全的。",
                nextStep: "家长可以和你一起看看发生了什么，再决定怎么处理。",
                tags: ["安全"],
                allowsRelative: false,
                reactionCount: 0,
                approvedCommentCount: 0,
                ratings: nil
            )
        ]
    }
}
