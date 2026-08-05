import Foundation

/// 任务包库中的一条模板：家长勾选后成为今日任务。
/// 模板本身不含任何孩子数据；成长积分只是建议值，布置时家长可整体沿用。
struct PackTaskTemplate: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var instructions: String
    var category: TaskCategory
    var suggestedRewardMinutes: Int
    /// 预计完成时长，主要给家长自定义任务包使用；布置后会写入任务说明。
    var expectedMinutes: Int?
    var requiredProof: ProofKind
    var adultSupervisionRequired: Bool
    var reading: ReadingSpec?
    var creative: CreativeTaskSpec?

    var isCustom: Bool { id.hasPrefix("custom-") }

    init(
        id: String,
        title: String,
        instructions: String,
        category: TaskCategory,
        suggestedRewardMinutes: Int,
        expectedMinutes: Int? = nil,
        requiredProof: ProofKind,
        adultSupervisionRequired: Bool = false,
        reading: ReadingSpec? = nil,
        creative: CreativeTaskSpec? = nil
    ) {
        self.id = id
        self.title = title
        self.instructions = instructions
        self.category = category
        self.suggestedRewardMinutes = suggestedRewardMinutes
        self.expectedMinutes = expectedMinutes
        self.requiredProof = requiredProof
        self.adultSupervisionRequired = adultSupervisionRequired
        self.reading = reading
        self.creative = creative
    }
}

/// 任务包库中的一个包：一组同类模板。
struct PackTemplateGroup: Identifiable, Equatable {
    var packType: PackType
    var summary: String
    var templates: [PackTaskTemplate]

    var id: String { packType.rawValue }
    var title: String { packType.label }
}

/// 内置任务包模板库（官方种子）。
/// 金融素养包只做记录、模拟和流程教学，不出现任何真实支付/交易操作
/// （见 docs/DECISIONS.md 2026-07-04: No Real-Money Transactions In App）。
enum ParentPackTemplateLibrary {
    static let groups: [PackTemplateGroup] = [
        PackTemplateGroup(
            packType: .basicHabits,
            summary: "个人独立性的大项：点进去布置睡觉、洗漱、穿衣、衣物、书包、房间等分项。",
            templates: [
                PackTaskTemplate(
                    id: "habit-early-sleep",
                    title: "按时上床睡觉",
                    instructions: "在约定时间前上床，把屏幕放到指定位置，睡前把明天要穿的衣服放好。",
                    category: .health,
                    suggestedRewardMinutes: 10,
                    requiredProof: .text
                ),
                PackTaskTemplate(
                    id: "habit-wash-up",
                    title: "自己洗脸刷牙洗澡",
                    instructions: "早晚刷牙洗脸，洗澡后把毛巾挂好、脏衣服放到洗衣篮。",
                    category: .health,
                    suggestedRewardMinutes: 10,
                    requiredProof: .text
                ),
                PackTaskTemplate(
                    id: "habit-dress-self",
                    title: "自己穿衣服",
                    instructions: "自己挑选并穿好当天的衣服，不需要大人帮忙。",
                    category: .home,
                    suggestedRewardMinutes: 5,
                    requiredProof: .text
                ),
                PackTaskTemplate(
                    id: "habit-clothes-away",
                    title: "收拾自己的衣服",
                    instructions: "把干净衣服叠好放回抽屉，脏衣服放进洗衣篮，不把衣服丢在地上。",
                    category: .home,
                    suggestedRewardMinutes: 10,
                    requiredProof: .photo
                ),
                PackTaskTemplate(
                    id: "habit-pack-bag",
                    title: "整理书包",
                    instructions: "按课表把明天要用的书和文具放进书包，拉好拉链。",
                    category: .learning,
                    suggestedRewardMinutes: 10,
                    requiredProof: .photo
                ),
                PackTaskTemplate(
                    id: "habit-tidy-room",
                    title: "整理自己的房间",
                    instructions: "玩具、书和学习用品各回各位，地面没有明显杂物。",
                    category: .home,
                    suggestedRewardMinutes: 15,
                    requiredProof: .photo
                ),
                PackTaskTemplate(
                    id: "habit-morning-ready",
                    title: "早晨自己准备好",
                    instructions: "起床后自己完成穿衣、洗漱、拿书包，出门前再检查一次。",
                    category: .health,
                    suggestedRewardMinutes: 10,
                    requiredProof: .text
                )
            ]
        ),
        PackTemplateGroup(
            packType: .chores,
            summary: "家庭协作的大项：点进去布置餐桌、垃圾、植物、清洁、收纳等分项。",
            templates: [
                PackTaskTemplate(
                    id: "chore-tidy-room",
                    title: "协助整理公共区域",
                    instructions: "把客厅或家庭公共区的玩具、书和杂物放回原位。",
                    category: .home,
                    suggestedRewardMinutes: 15,
                    requiredProof: .photo
                ),
                PackTaskTemplate(
                    id: "chore-trash",
                    title: "倒垃圾",
                    instructions: "把家里的垃圾分类后拿到楼下垃圾点。",
                    category: .home,
                    suggestedRewardMinutes: 10,
                    requiredProof: .text
                ),
                PackTaskTemplate(
                    id: "chore-set-table",
                    title: "帮忙摆碗筷",
                    instructions: "吃饭前把碗筷和水杯摆好，吃完帮忙收回厨房。",
                    category: .home,
                    suggestedRewardMinutes: 10,
                    requiredProof: .text
                ),
                PackTaskTemplate(
                    id: "chore-clear-table",
                    title: "饭后清理餐桌",
                    instructions: "饭后把自己的餐具拿到厨房，擦干净自己座位前的桌面。",
                    category: .home,
                    suggestedRewardMinutes: 10,
                    requiredProof: .text
                ),
                PackTaskTemplate(
                    id: "chore-sort-laundry",
                    title: "分类脏衣服",
                    instructions: "把自己的脏衣服按深浅或家庭规则放进对应篮子。",
                    category: .home,
                    suggestedRewardMinutes: 10,
                    requiredProof: .photo
                ),
                PackTaskTemplate(
                    id: "chore-wipe-surface",
                    title: "擦一个小区域",
                    instructions: "选择书桌、餐桌或柜面的一小块区域擦干净，再把抹布放回去。",
                    category: .home,
                    suggestedRewardMinutes: 10,
                    requiredProof: .photo
                ),
                PackTaskTemplate(
                    id: "chore-pet-care",
                    title: "照顾小宠物或植物",
                    instructions: "给宠物添食换水，或者给植物浇水，观察它们的变化。",
                    category: .home,
                    suggestedRewardMinutes: 10,
                    requiredProof: .photo
                )
            ]
        ),
        PackTemplateGroup(
            packType: .outdoorSports,
            summary: "把手机放下，到院子、公园或安全户外活动。家长可自定义运动类型、时长和成长积分。",
            templates: [
                PackTaskTemplate(
                    id: "outdoor-park-walk",
                    title: "公园快走或散步",
                    instructions: "和大人确认路线，在安全区域快走或散步，回来讲一个路上看到的新东西。",
                    category: .health,
                    suggestedRewardMinutes: 15,
                    expectedMinutes: 20,
                    requiredProof: .text,
                    adultSupervisionRequired: true
                ),
                PackTaskTemplate(
                    id: "outdoor-jump-rope",
                    title: "跳绳挑战",
                    instructions: "找一块安全空地跳绳，记录这次最多连续跳了多少下。",
                    category: .health,
                    suggestedRewardMinutes: 15,
                    expectedMinutes: 15,
                    requiredProof: .text
                ),
                PackTaskTemplate(
                    id: "outdoor-ball-play",
                    title: "球类运动",
                    instructions: "选择篮球、足球、羽毛球或抛接球，认真活动到出汗。",
                    category: .health,
                    suggestedRewardMinutes: 20,
                    expectedMinutes: 30,
                    requiredProof: .photo,
                    adultSupervisionRequired: true
                ),
                PackTaskTemplate(
                    id: "outdoor-bike-scooter",
                    title: "骑车或滑板车",
                    instructions: "戴好头盔和护具，只在家长允许的安全区域活动。",
                    category: .health,
                    suggestedRewardMinutes: 25,
                    expectedMinutes: 30,
                    requiredProof: .photo,
                    adultSupervisionRequired: true
                ),
                PackTaskTemplate(
                    id: "outdoor-nature-search",
                    title: "自然观察任务",
                    instructions: "在院子或公园找 3 种叶子、石头或小动物痕迹，回来描述它们有什么不同。",
                    category: .health,
                    suggestedRewardMinutes: 20,
                    expectedMinutes: 25,
                    requiredProof: .photo,
                    adultSupervisionRequired: true
                ),
                PackTaskTemplate(
                    id: "outdoor-family-game",
                    title: "户外亲子游戏",
                    instructions: "和家人玩追逐、飞盘、跳格子或你们约定的户外游戏。",
                    category: .family,
                    suggestedRewardMinutes: 20,
                    expectedMinutes: 25,
                    requiredProof: .text,
                    adultSupervisionRequired: true
                )
            ]
        ),
        PackTemplateGroup(
            packType: .learning,
            summary: "阅读和学习任务。阅读任务可以填书名、最低时长和章节计划。",
            templates: [
                PackTaskTemplate(
                    id: "learn-reading-30",
                    title: "阅读 30 分钟",
                    instructions: "读完后用自己的话说说这一段讲了什么、你最喜欢哪里。",
                    category: .learning,
                    suggestedRewardMinutes: 20,
                    requiredProof: .text,
                    reading: ReadingSpec(
                        bookTitle: "（布置时填写书名）",
                        minMinutes: 30,
                        chapterPlanText: "（布置时填写本次要读的章节）",
                        deliveryMode: .physicalManual
                    )
                ),
                PackTaskTemplate(
                    id: "learn-mental-math",
                    title: "口算练习 10 道",
                    instructions: "完成 10 道口算题，把算式和答案写下来。",
                    category: .learning,
                    suggestedRewardMinutes: 10,
                    requiredProof: .photo
                ),
                PackTaskTemplate(
                    id: "learn-new-words",
                    title: "学 5 个新词语",
                    instructions: "学会 5 个新词语，每个词造一个句子说给大人听。",
                    category: .learning,
                    suggestedRewardMinutes: 15,
                    requiredProof: .text
                )
            ]
        ),
        PackTemplateGroup(
            packType: .skillExtension,
            summary: "动手的生活技能。带「需要大人在场」标记的任务必须有大人陪同。",
            templates: [
                PackTaskTemplate(
                    id: "skill-shoelace",
                    title: "学会系鞋带",
                    instructions: "跟着大人学一种系鞋带的方法，自己完整系好一次。",
                    category: .creative,
                    suggestedRewardMinutes: 15,
                    requiredProof: .photo
                ),
                PackTaskTemplate(
                    id: "skill-fix-toy",
                    title: "修理一个玩具",
                    instructions: "找一个坏了的玩具，和大人一起研究并修好它。",
                    category: .creative,
                    suggestedRewardMinutes: 30,
                    requiredProof: .photo,
                    adultSupervisionRequired: true
                ),
                PackTaskTemplate(
                    id: "skill-sew-button",
                    title: "缝一颗扣子",
                    instructions: "在大人陪同下用针线把一颗扣子缝到布上。",
                    category: .creative,
                    suggestedRewardMinutes: 20,
                    requiredProof: .photo,
                    adultSupervisionRequired: true
                ),
                PackTaskTemplate(
                    id: "skill-simple-dish",
                    title: "做一道简单料理",
                    instructions: "在大人陪同下完成一道简单的菜或点心，注意用火用刀安全。",
                    category: .home,
                    suggestedRewardMinutes: 30,
                    requiredProof: .photo,
                    adultSupervisionRequired: true
                )
            ]
        ),
        PackTemplateGroup(
            packType: .financeLiteracy,
            summary: "认识钱和规划。只做记录和模拟，真实买卖由大人在 App 外完成。",
            templates: [
                PackTaskTemplate(
                    id: "finance-allowance-log",
                    title: "记录一周零花钱",
                    instructions: "把这一周收到和花掉的零花钱记下来，分成「想要」和「需要」两类。",
                    category: .learning,
                    suggestedRewardMinutes: 15,
                    requiredProof: .photo
                ),
                PackTaskTemplate(
                    id: "finance-saving-goal",
                    title: "制定一个储蓄小目标",
                    instructions: "选一个想买的东西，算算要存多久，写出每周的存钱计划。",
                    category: .learning,
                    suggestedRewardMinutes: 15,
                    requiredProof: .text
                ),
                PackTaskTemplate(
                    id: "finance-flea-market",
                    title: "整理义卖旧玩具",
                    instructions: "挑出不玩的玩具，擦干净、定个价格、写一句推荐语。真正卖的时候由大人来操作。",
                    category: .creative,
                    suggestedRewardMinutes: 20,
                    requiredProof: .photo
                )
            ]
        ),
        PackTemplateGroup(
            packType: .creativeWorks,
            summary: "画画、手工和表达，作品可以进荣誉墙。",
            templates: [
                PackTaskTemplate(
                    id: "create-theme-drawing",
                    title: "画一幅主题画",
                    instructions: "围绕一个主题（比如我的家、春天）画一幅画，画完介绍一下。",
                    category: .creative,
                    suggestedRewardMinutes: 20,
                    requiredProof: .photo,
                    creative: CreativeTaskSpec(
                        kind: .drawing,
                        creativePrompt: CreativeTaskKind.drawing.starterPrompt,
                        materials: CreativeTaskKind.drawing.starterMaterials,
                        estimatedMinutes: 30
                    )
                ),
                PackTaskTemplate(
                    id: "create-handcraft",
                    title: "做一个小手工",
                    instructions: "用家里的材料做一个小手工，拍照留念。",
                    category: .creative,
                    suggestedRewardMinutes: 20,
                    requiredProof: .photo,
                    creative: CreativeTaskSpec(
                        kind: .handcraft,
                        creativePrompt: CreativeTaskKind.handcraft.starterPrompt,
                        materials: CreativeTaskKind.handcraft.starterMaterials,
                        estimatedMinutes: 30
                    )
                ),
                PackTaskTemplate(
                    id: "create-journal",
                    title: "写一篇小日记",
                    instructions: "写下今天最开心或最难忘的一件事，三句话以上。",
                    category: .creative,
                    suggestedRewardMinutes: 15,
                    requiredProof: .text,
                    creative: CreativeTaskSpec(
                        kind: .storytelling,
                        creativePrompt: CreativeTaskKind.storytelling.starterPrompt,
                        materials: CreativeTaskKind.storytelling.starterMaterials,
                        estimatedMinutes: 20
                    )
                )
            ]
        ),
        PackTemplateGroup(
            packType: .familyResponsibility,
            summary: "亲情陪伴和家庭责任。",
            templates: [
                PackTaskTemplate(
                    id: "family-call-grandparents",
                    title: "给爷爷奶奶打电话",
                    instructions: "打一个电话，聊聊这周学校里发生的事，问问他们的身体。",
                    category: .family,
                    suggestedRewardMinutes: 15,
                    requiredProof: .text
                ),
                PackTaskTemplate(
                    id: "family-teach-skill",
                    title: "教家人一个新东西",
                    instructions: "把你会的一个小技能（游戏、折纸、手机操作）教给家里人。",
                    category: .family,
                    suggestedRewardMinutes: 15,
                    requiredProof: .text
                ),
                PackTaskTemplate(
                    id: "family-play-sibling",
                    title: "陪弟弟妹妹玩",
                    instructions: "认真陪弟弟妹妹玩 20 分钟，让他们开心。",
                    category: .family,
                    suggestedRewardMinutes: 15,
                    requiredProof: .text
                )
            ]
        )
    ]

    static func group(for packType: PackType) -> PackTemplateGroup? {
        groups.first { $0.packType == packType }
    }
}
