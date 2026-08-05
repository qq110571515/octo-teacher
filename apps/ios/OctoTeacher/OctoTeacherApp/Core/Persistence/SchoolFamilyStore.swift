import Foundation
import Observation

/// 学校作业与家庭成长动态的本地 store。
///
/// 这是「iOS 学校作业与家庭成长动态视图」第一版的本地数据源与状态机。所有数据均为
/// 本地 mock，符合 CLAUDE.md 安全边界：
///
/// - 不接真实学校 LMS、老师账号、网络、数据库、AI、视频、通讯录、通知、支付或云服务。
/// - 作业照片证明只保存到本机沙盒，等待老师或家长验证，不上传。
/// - AI 引导只给提示/清单/下一步，绝不给作业答案（见 `AIHomeworkGuidance`）。
/// - 家庭成长内容默认私密；亲友只读 / 评论待审核，不能批准任务、不能发成长积分、不能解锁设备。
/// - 不暴露真实孩子、家庭、学校、亲友、媒体、路径、token 或局域网地址。
@Observable
final class SchoolFamilyStore {
    // MARK: - 学校作业（孩子端）

    var homeworks: [SchoolHomework]

    // MARK: - 家庭成长动态（家庭端）

    var feed: [GrowthFeedEntry]
    var badges: [GrowthBadge]
    var starCards: [GrowthStarCard]
    var honorWall: [HonorWallItem]
    var relativeComments: [RelativeFeedComment]
    var vlogs: [GrowthVLOGPlaceholder]
    var storyline: StorylineSummary

    init() {
        self.homeworks = Self.seedHomeworks()
        self.feed = Self.seedFeed()
        self.badges = Self.seedBadges()
        self.starCards = Self.seedStarCards()
        self.honorWall = Self.seedHonorWall()
        self.relativeComments = Self.seedRelativeComments()
        self.vlogs = Self.seedVLOGs()
        self.storyline = Self.seedStoryline()
    }

    // MARK: - 学校作业：派生与提交

    /// 还需要孩子处理的作业（待开始 / 进行中 / 需重做）。
    var openHomeworks: [SchoolHomework] {
        homeworks.filter { $0.status.acceptsSubmission }
    }

    /// 已提交或已完成的作业。
    var settledHomeworks: [SchoolHomework] {
        homeworks.filter { !$0.status.acceptsSubmission }
    }

    /// 孩子提交作业证明。
    ///
    /// 安全边界：
    /// - 必须有可提交内容（文字非空、真实照片或图片占位名存在），否则不提交。
    /// - 已提交/已完成的作业不再接受新提交（幂等，避免重复刷状态）。
    /// - 仅把状态推进到 `submitted`（等待验证），**绝不**在此自动发成长积分或标记 `verified`。
    @discardableResult
    func submitHomework(_ homework: SchoolHomework, proof: ProofDraft) -> Bool {
        guard let index = homeworks.firstIndex(where: { $0.id == homework.id }) else { return false }
        guard homeworks[index].status.acceptsSubmission else { return false }
        guard proof.hasContent else { return false }

        var submitted = proof
        submitted.status = .submitted
        homeworks[index].proof = submitted
        homeworks[index].status = .submitted
        return true
    }

    /// 文字证明便捷提交。
    @discardableResult
    func submitHomework(_ homework: SchoolHomework, text: String) -> Bool {
        let proof = ProofDraft(kind: .text, text: text, photoPlaceholderName: nil, status: .submitted)
        return submitHomework(homework, proof: proof)
    }

    /// 取某条作业当前的 AI 引导（只读，引导式，不含答案）。
    func guidance(for homework: SchoolHomework) -> AIHomeworkGuidance {
        homeworks.first(where: { $0.id == homework.id })?.guidance ?? .empty
    }

    // MARK: - 家庭成长动态：受众可见性

    /// 按受众过滤动态。亲友只能看到已批准且非私密的条目。
    func visibleFeed(for audience: FamilyFeedAudience) -> [GrowthFeedEntry] {
        feed.filter { $0.isVisible(to: audience) }
    }

    /// 按受众过滤荣誉墙。
    func visibleHonorWall(for audience: FamilyFeedAudience) -> [HonorWallItem] {
        honorWall.filter { $0.isVisible(to: audience) }
    }

    /// 按受众过滤亲友评论。亲友只能看到已通过审核的评论。
    func visibleComments(for audience: FamilyFeedAudience) -> [RelativeFeedComment] {
        relativeComments.filter { $0.isVisible(to: audience) }
    }

    /// 按受众过滤球星卡。亲友看不到私密卡。
    func visibleStarCards(for audience: FamilyFeedAudience) -> [GrowthStarCard] {
        switch audience {
        case .household:
            return starCards
        case .relative:
            return starCards.filter { $0.visibility != .privateFamily }
        }
    }

    /// 按受众过滤成长视频日记条目。
    func visibleVLOGs(for audience: FamilyFeedAudience) -> [GrowthVLOGPlaceholder] {
        vlogs.filter { $0.isVisible(to: audience) }
    }

    // MARK: - 家庭成长动态：亲友评论（只读 / 待审核）

    /// 亲友留下评论。
    ///
    /// 安全边界：亲友评论默认进入 `pending`，必须由家长审核后才会对其他亲友展示。
    /// 此方法绝不发成长积分、不改任务/作业状态、不解锁设备。空消息不入库。
    @discardableResult
    func addRelativeComment(nickname: String, message: String, createdLabel: String = "刚刚") -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        relativeComments.insert(
            RelativeFeedComment(
                id: UUID(),
                relativeNickname: nickname,
                message: trimmed,
                status: .pending,
                createdLabel: createdLabel
            ),
            at: 0
        )
        return true
    }

    /// 家长审核亲友评论。仅家长可调用（亲友视图不暴露此入口）。
    func moderateComment(_ comment: RelativeFeedComment, decision: FamilyApprovalState) {
        guard let index = relativeComments.firstIndex(where: { $0.id == comment.id }) else { return }
        relativeComments[index].status = decision
    }

    /// 家长审核荣誉墙条目。批准后才上墙、才可能对亲友可见。
    func moderateHonorItem(_ item: HonorWallItem, decision: FamilyApprovalState) {
        guard let index = honorWall.firstIndex(where: { $0.id == item.id }) else { return }
        honorWall[index].approval = decision
    }

    // MARK: - 种子数据

    private static func seedHomeworks() -> [SchoolHomework] {
        [
            SchoolHomework(
                id: UUID(),
                subject: .math,
                title: "完成两位数加减法练习",
                instructions: "做完练习册第 12 页，遇到不会的题先圈出来。",
                dueLabel: "今天 20:00 前",
                status: .assigned,
                requiredProof: .photoPlaceholder,
                guidance: AIHomeworkGuidance(
                    hints: [
                        "先想一想：进位的时候个位满十要怎么办？",
                        "可以把大数拆成整十数和个位数分别算，再合起来。",
                        "卡住的题先跳过，做完回头再看，往往会更清楚。"
                    ],
                    checklist: [
                        "每道题都写了计算过程",
                        "检查了进位/退位有没有漏",
                        "把圈出来的难题准备好向老师或家长请教"
                    ],
                    nextStep: "把这一页做完后，挑一道最难的题，试着用自己的话讲一遍解题思路。"
                )
            ),
            SchoolHomework(
                id: UUID(),
                subject: .chinese,
                title: "朗读课文并抄写生词",
                instructions: "朗读今天的课文两遍，抄写本课生词各一行。",
                dueLabel: "今天睡前",
                status: .inProgress,
                requiredProof: .text,
                proof: ProofDraft(kind: .text, text: "已经朗读一遍", photoPlaceholderName: nil, status: .drafting),
                guidance: AIHomeworkGuidance(
                    hints: [
                        "朗读时注意标点停顿，读不顺的句子可以多读两遍。",
                        "抄写生词时一边写一边小声读，记得更牢。"
                    ],
                    checklist: [
                        "课文朗读了两遍",
                        "生词每个抄了一行",
                        "不认识的字查过或问过"
                    ],
                    nextStep: "抄完后，挑两个新学的生词，自己试着各说一个句子。"
                )
            ),
            SchoolHomework(
                id: UUID(),
                subject: .reading,
                title: "课外阅读二十分钟",
                instructions: "读一本喜欢的书二十分钟，用一句话写下今天读到的内容。",
                dueLabel: "今天内",
                status: .returned,
                requiredProof: .text,
                guidance: AIHomeworkGuidance(
                    hints: [
                        "可以从「今天主角遇到了什么」开始想。",
                        "一句话写不下时，先说时间、地点、发生了什么。"
                    ],
                    checklist: [
                        "读满了二十分钟",
                        "用一句完整的话写了内容"
                    ],
                    nextStep: "下次试着多写一句你的感受：你喜欢这一段吗，为什么？"
                )
            ),
            SchoolHomework(
                id: UUID(),
                subject: .science,
                title: "观察并记录一种植物",
                instructions: "观察家里或路边的一种植物，画下来并写两点发现。",
                dueLabel: "已完成",
                status: .verified,
                requiredProof: .photoPlaceholder,
                proof: ProofDraft(kind: .photoPlaceholder, text: "", photoPlaceholderName: "local-plant-note", status: .submitted),
                guidance: AIHomeworkGuidance(
                    hints: ["观察时可以从颜色、形状、大小这些角度去找不同。"],
                    checklist: ["画了观察对象", "写了两点发现"],
                    nextStep: "做得很好！可以明天再观察一次，看看有没有新的变化。"
                )
            )
        ]
    }

    private static func seedFeed() -> [GrowthFeedEntry] {
        [
            GrowthFeedEntry(
                id: UUID(),
                title: "坚持阅读第 7 天",
                summary: "今天又读完了二十分钟，连续一周没断过。",
                visibility: .family,
                approval: .approved,
                occurredLabel: "今天",
                tags: ["阅读", "坚持"]
            ),
            GrowthFeedEntry(
                id: UUID(),
                title: "数学小进步",
                summary: "两位数加减法基本都能自己做对了。",
                visibility: .family,
                approval: .pending,
                occurredLabel: "今天",
                tags: ["数学"]
            ),
            GrowthFeedEntry(
                id: UUID(),
                title: "情绪小记",
                summary: "今天有点累，但还是把作业做完了。",
                visibility: .privateFamily,
                approval: .approved,
                occurredLabel: "今天",
                tags: ["心情"]
            )
        ]
    }

    private static func seedBadges() -> [GrowthBadge] {
        [
            GrowthBadge(id: UUID(), name: "阅读小达人", systemImage: "book.fill", earnedLabel: "连续阅读 7 天"),
            GrowthBadge(id: UUID(), name: "坚持之星", systemImage: "flame.fill", earnedLabel: "本周任务全勤"),
            GrowthBadge(id: UUID(), name: "观察家", systemImage: "leaf.fill", earnedLabel: "完成科学观察")
        ]
    }

    private static func seedStarCards() -> [GrowthStarCard] {
        [
            GrowthStarCard(
                id: UUID(),
                childNickname: "小阳",
                seasonLabel: "本月",
                ratings: [
                    .knowledge: 72,
                    .habit: 81,
                    .creativity: 65,
                    .social: 70,
                    .health: 78
                ],
                visibility: .family
            )
        ]
    }

    private static func seedHonorWall() -> [HonorWallItem] {
        [
            HonorWallItem(id: UUID(), title: "阅读之星", category: "阅读", approval: .approved, visibility: .family),
            HonorWallItem(id: UUID(), title: "进步奖", category: "数学", approval: .pending, visibility: .family)
        ]
    }

    private static func seedRelativeComments() -> [RelativeFeedComment] {
        [
            RelativeFeedComment(id: UUID(), relativeNickname: "外婆", message: "小阳真棒，继续加油！", status: .approved, createdLabel: "今天"),
            RelativeFeedComment(id: UUID(), relativeNickname: "小姨", message: "看到你坚持阅读，真为你高兴。", status: .pending, createdLabel: "今天")
        ]
    }

    private static func seedVLOGs() -> [GrowthVLOGPlaceholder] {
        [
            GrowthVLOGPlaceholder(
                id: UUID(),
                title: "本周成长小回顾",
                durationLabel: "约 1 分钟",
                visibility: .family,
                placeholderNote: "待家长开启记录 · 不会自动读取或上传媒体"
            )
        ]
    }

    private static func seedStoryline() -> StorylineSummary {
        StorylineSummary(
            headline: "一点一滴，都是成长",
            milestones: [
                StorylineMilestone(id: UUID(), title: "养成阅读习惯", summary: "从偶尔读书到连续一周坚持阅读。", occurredLabel: "本周"),
                StorylineMilestone(id: UUID(), title: "敢于面对难题", summary: "遇到不会的数学题，学会先圈出来再请教。", occurredLabel: "本周"),
                StorylineMilestone(id: UUID(), title: "学会观察世界", summary: "完成第一次科学观察记录。", occurredLabel: "上周")
            ]
        )
    }
}
