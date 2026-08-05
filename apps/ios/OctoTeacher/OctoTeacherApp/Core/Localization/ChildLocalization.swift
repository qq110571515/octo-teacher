import Foundation
import SwiftUI

/// 家长设备查看「孩子」页时使用的本机预览语言。
///
/// 这个偏好只存在当前设备的 UserDefaults，不进入家庭快照，也不会覆盖孩子手机
/// 自己的界面语言。孩子设备始终使用云端按孩子保存的实际语言。
enum GuardianChildPreviewLanguage: String, CaseIterable, Identifiable {
    case followChild
    case chinese
    case english

    var id: String { rawValue }

    func resolvedLanguage(childLanguage: AppInterfaceLanguage) -> AppInterfaceLanguage {
        switch self {
        case .followChild: return childLanguage
        case .chinese: return .chinese
        case .english: return .english
        }
    }

    func label(for parentLanguage: AppInterfaceLanguage) -> String {
        switch self {
        case .followChild: return parentLanguage.pick("跟随孩子手机", "Follow child's device")
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

enum GuardianChildPreviewLanguagePreference {
    static let key = "octoteacher.guardian.childPreviewLanguage"

    static func resolve(_ rawValue: String?) -> GuardianChildPreviewLanguage {
        rawValue.flatMap(GuardianChildPreviewLanguage.init(rawValue:)) ?? .followChild
    }
}

private struct ChildSurfaceLanguageKey: EnvironmentKey {
    static let defaultValue: AppInterfaceLanguage = .chinese
}

extension EnvironmentValues {
    /// 当前屏幕上孩子直接看到的语言。家长设备可用本机预览值；孩子设备使用真实孩子配置。
    var childSurfaceLanguage: AppInterfaceLanguage {
        get { self[ChildSurfaceLanguageKey.self] }
        set { self[ChildSurfaceLanguageKey.self] = newValue }
    }
}

/// App 内确定性双语文案的统一入口。
///
/// 背景：工程 developmentRegion=en 且只有 en.lproj，`Text("中文字面量")` 会被系统
/// 语言驱动的 bundle 查找强行翻成英文，与 App 内的语言设置脱节。因此所有
/// 「必须跟随家长语言 / 孩子语言」的界面文案，都应该走这里的显式 String API
/// （String 变量初始化的 Text 不做 .strings 查找），而不是依赖字面量 key。
extension AppInterfaceLanguage {
    /// 按界面语言取中/英文案。所有孩子端与设置页动态文案的最小公共 API。
    func pick(_ chinese: String, _ english: String) -> String {
        self == .english ? english : chinese
    }
}

/// 当前孩子的界面语言上下文：View 里一次解析，避免每处散落判断。
struct ChildLocalizationContext {
    var language: AppInterfaceLanguage

    var isEnglish: Bool { language == .english }

    /// 双语选择：中文孩子看中文，英文孩子看英文。
    func pick(_ chinese: String, _ english: String) -> String {
        language.pick(chinese, english)
    }
}

extension LocalFamilyStore {
    /// 当前活跃孩子的界面语言上下文（孩子端 View 统一从这里取文案语言）。
    var activeChildLocalization: ChildLocalizationContext {
        ChildLocalizationContext(language: activeChildInterfaceLanguage)
    }

    /// 种子数据里的“孩子”是产品占位名，不是用户起的昵称；英文界面应显示 Child。
    /// 家长真正填写的中文姓名属于家庭数据，必须原样保留，不能擅自翻译。
    func childDisplayName(_ child: ChildProfile, for language: AppInterfaceLanguage) -> String {
        let trimmed = child.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "孩子" {
            return language.pick("孩子", "Child")
        }
        return trimmed
    }
}

/// 自定义任务缺少目标语言翻译缓存时的显式回退。
///
/// 英文孩子不能静默看到中文任务，中文孩子也不能静默看到纯英文任务：
/// 回退文案只给出孩子看得懂的提示（等待翻译 / 找大人帮忙），不把另一种
/// 语言的原文带进孩子界面。家长端继续直接读 title/instructions 原字段，不受影响。
enum TaskLanguageFallback {
    /// 含中日韩统一表意文字（含扩展 A）即视为中文内容。
    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
                || (0x3400...0x4DBF).contains(Int(scalar.value))
        }
    }

    /// 目标界面语言读不懂原文时，需要显式的「等待翻译」提示。
    /// 纯数字/表情等无文字内容不算需要翻译。
    static func needsTranslationNotice(_ text: String, for language: AppInterfaceLanguage) -> Bool {
        switch language {
        case .english:
            return containsCJK(text)
        case .chinese:
            return !containsCJK(text) && text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        }
    }

    static func title(_ original: String, for language: AppInterfaceLanguage) -> String {
        guard needsTranslationNotice(original, for: language) else { return original }
        return language.pick("任务翻译准备中", "Task translation pending")
    }

    static func instructions(_ original: String, for language: AppInterfaceLanguage) -> String {
        guard needsTranslationNotice(original, for: language) else { return original }
        return language.pick(
            "请让大人完成翻译后再开始这个任务。",
            "Ask a grown-up to finish the translation before starting this task."
        )
    }
}

/// 内置中文任务/成长包文案的确定性英文映射。
///
/// 家长自定义任务继续走 TaskLocalizedContent（AI 翻译缓存）；这里只覆盖
/// 随 App 内置的种子任务、首日晚间节律包和任务包库模板，保证英文孩子
/// 不会因为「内置文案没有翻译」而看到中文。映射按完整原文精确匹配，
/// 不做模糊翻译；查不到时返回 nil，由调用方决定回退行为。
enum BuiltInTaskLocalization {
    static func englishTitle(for chinese: String) -> String? {
        titleMap[chinese.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    static func englishInstructions(for chinese: String) -> String? {
        instructionsMap[chinese.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    /// 成长包标题/摘要等非任务内置文案。
    static func englishPhrase(for chinese: String) -> String? {
        phraseMap[chinese.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    // MARK: - 任务标题（种子任务 + 晚间节律包 + 任务包库）

    private static let titleMap: [String: String] = [
        // 种子任务
        "阅读 15 分钟": "Read for 15 minutes",
        "整理书桌": "Tidy your desk",
        "运动 20 分钟": "Exercise for 20 minutes",
        // 首日晚间节律包
        "把玩具送回家": "Put toys back home",
        "睡前读小书": "Bedtime reading",
        "出门玩一会儿": "Go outside and play",
        "手机去睡觉": "Put the phone to bed",
        // 个人独立性
        "按时上床睡觉": "Go to bed on time",
        "自己洗脸刷牙洗澡": "Wash up by yourself",
        "自己穿衣服": "Get dressed by yourself",
        "收拾自己的衣服": "Put away your clothes",
        "整理书包": "Pack your school bag",
        "整理自己的房间": "Tidy your room",
        "早晨自己准备好": "Get ready in the morning",
        // 家务
        "协助整理公共区域": "Help tidy shared spaces",
        "倒垃圾": "Take out the trash",
        "帮忙摆碗筷": "Set the table",
        "饭后清理餐桌": "Clear the table after meals",
        "分类脏衣服": "Sort the laundry",
        "擦一个小区域": "Wipe one small area",
        "照顾小宠物或植物": "Care for a pet or plant",
        // 户外运动
        "公园快走或散步": "Brisk walk in the park",
        "跳绳挑战": "Jump rope challenge",
        "球类运动": "Ball games",
        "骑车或滑板车": "Bike or scooter ride",
        "自然观察任务": "Nature observation",
        "户外亲子游戏": "Outdoor family game",
        // 学习
        "阅读 30 分钟": "Read for 30 minutes",
        "口算练习 10 道": "10 mental math problems",
        "学 5 个新词语": "Learn 5 new words",
        // 技能扩展
        "学会系鞋带": "Learn to tie shoelaces",
        "修理一个玩具": "Fix a toy",
        "缝一颗扣子": "Sew on a button",
        "做一道简单料理": "Cook a simple dish",
        // 金融素养
        "记录一周零花钱": "Track a week of pocket money",
        "制定一个储蓄小目标": "Set a small savings goal",
        "整理义卖旧玩具": "Prepare old toys for a sale",
        // 创造作品
        "画一幅主题画": "Paint a themed picture",
        "做一个小手工": "Make a small craft",
        "写一篇小日记": "Write a short diary entry",
        // 家庭责任
        "给爷爷奶奶打电话": "Call your grandparents",
        "教家人一个新东西": "Teach your family something new",
        "陪弟弟妹妹玩": "Play with your younger sibling"
    ]

    // MARK: - 任务说明

    private static let instructionsMap: [String: String] = [
        // 种子任务
        "读一本书或一篇文章，然后写下一句今天学到的内容。":
            "Read a book or an article, then write one sentence about what you learned today.",
        "把书桌整理到可以写作业或阅读的状态，拍一张照片给爸爸妈妈看。":
            "Tidy your desk until it is ready for homework or reading, then take a photo for Mom or Dad.",
        "散步、拉伸、户外活动或做一组简单运动，并写一句完成记录。":
            "Take a walk, stretch, play outside, or do a simple workout, then write one sentence about it.",
        // 首日晚间节律包
        "睡觉前，把地上的玩具和书送回它们自己的家，拍张照片给爸爸妈妈看。":
            "Before bed, put the toys and books on the floor back where they live, then take a photo for Mom or Dad.",
        "选一本你喜欢的书，自己读，或者请大人读给你听，再说一说你最喜欢哪里。":
            "Pick a book you like, read it yourself or ask a grown-up to read it to you, then share your favorite part.",
        "和大人一起下楼或者去公园，跑一跑跳一跳，玩一会儿再回家。":
            "Go downstairs or to the park with a grown-up, run and jump for a while, then head home.",
        "睡觉前，把手机放到和爸爸妈妈说好的充电的地方，跟它说晚安。":
            "Before bed, put the phone in its agreed charging spot and say good night to it.",
        // 个人独立性
        "在约定时间前上床，把屏幕放到指定位置，睡前把明天要穿的衣服放好。":
            "Get in bed before the agreed time, put screens in their spot, and lay out tomorrow's clothes.",
        "早晚刷牙洗脸，洗澡后把毛巾挂好、脏衣服放到洗衣篮。":
            "Brush your teeth and wash your face morning and night; after your bath, hang the towel and put dirty clothes in the basket.",
        "自己挑选并穿好当天的衣服，不需要大人帮忙。":
            "Pick out and put on today's clothes all by yourself.",
        "把干净衣服叠好放回抽屉，脏衣服放进洗衣篮，不把衣服丢在地上。":
            "Fold clean clothes into the drawer and put dirty ones in the basket — no clothes on the floor.",
        "按课表把明天要用的书和文具放进书包，拉好拉链。":
            "Pack tomorrow's books and supplies by the class schedule, then zip up the bag.",
        "玩具、书和学习用品各回各位，地面没有明显杂物。":
            "Put toys, books, and school supplies back in their places, with a clear floor.",
        "起床后自己完成穿衣、洗漱、拿书包，出门前再检查一次。":
            "After waking up, get dressed, wash up, and grab your bag by yourself; double-check before leaving.",
        // 家务
        "把客厅或家庭公共区的玩具、书和杂物放回原位。":
            "Return the toys, books, and clutter in the living room or shared areas to their places.",
        "把家里的垃圾分类后拿到楼下垃圾点。":
            "Sort the household trash and take it to the collection point downstairs.",
        "吃饭前把碗筷和水杯摆好，吃完帮忙收回厨房。":
            "Set out bowls, chopsticks, and cups before the meal, and help carry them back to the kitchen after.",
        "饭后把自己的餐具拿到厨房，擦干净自己座位前的桌面。":
            "After eating, take your dishes to the kitchen and wipe the table in front of your seat.",
        "把自己的脏衣服按深浅或家庭规则放进对应篮子。":
            "Sort your dirty clothes into the right baskets by color or family rules.",
        "选择书桌、餐桌或柜面的一小块区域擦干净，再把抹布放回去。":
            "Pick one small area — desk, table, or shelf — wipe it clean, then put the cloth back.",
        "给宠物添食换水，或者给植物浇水，观察它们的变化。":
            "Feed the pet and change its water, or water the plants, and notice how they change.",
        // 户外运动
        "和大人确认路线，在安全区域快走或散步，回来讲一个路上看到的新东西。":
            "Agree on a route with a grown-up, walk briskly in a safe area, and share one new thing you saw.",
        "找一块安全空地跳绳，记录这次最多连续跳了多少下。":
            "Find a safe open spot to jump rope and record your best streak.",
        "选择篮球、足球、羽毛球或抛接球，认真活动到出汗。":
            "Choose basketball, soccer, badminton, or catch, and play until you break a sweat.",
        "戴好头盔和护具，只在家长允许的安全区域活动。":
            "Wear your helmet and pads, and ride only in areas your parents allow.",
        "在院子或公园找 3 种叶子、石头或小动物痕迹，回来描述它们有什么不同。":
            "Find 3 kinds of leaves, rocks, or animal traces in the yard or park, and describe how they differ.",
        "和家人玩追逐、飞盘、跳格子或你们约定的户外游戏。":
            "Play tag, frisbee, hopscotch, or your family's favorite outdoor game together.",
        // 学习
        "读完后用自己的话说说这一段讲了什么、你最喜欢哪里。":
            "After reading, retell the passage in your own words and share your favorite part.",
        "完成 10 道口算题，把算式和答案写下来。":
            "Solve 10 mental math problems and write down each problem and answer.",
        "学会 5 个新词语，每个词造一个句子说给大人听。":
            "Learn 5 new words and say a sentence with each one to a grown-up.",
        // 技能扩展
        "跟着大人学一种系鞋带的方法，自己完整系好一次。":
            "Learn one way to tie shoelaces from a grown-up, then tie them fully by yourself once.",
        "找一个坏了的玩具，和大人一起研究并修好它。":
            "Find a broken toy and figure out how to fix it together with a grown-up.",
        "在大人陪同下用针线把一颗扣子缝到布上。":
            "With a grown-up beside you, sew a button onto fabric with needle and thread.",
        "在大人陪同下完成一道简单的菜或点心，注意用火用刀安全。":
            "With a grown-up beside you, make a simple dish or snack, staying safe with heat and knives.",
        // 金融素养
        "把这一周收到和花掉的零花钱记下来，分成「想要」和「需要」两类。":
            "Write down the pocket money you received and spent this week, sorted into wants and needs.",
        "选一个想买的东西，算算要存多久，写出每周的存钱计划。":
            "Pick something you want to buy, work out how long to save, and write a weekly savings plan.",
        "挑出不玩的玩具，擦干净、定个价格、写一句推荐语。真正卖的时候由大人来操作。":
            "Pick toys you no longer play with, clean them, set a price, and write a one-line pitch. A grown-up handles the actual sale.",
        // 创造作品
        "围绕一个主题（比如我的家、春天）画一幅画，画完介绍一下。":
            "Paint a picture around a theme (like my home or spring), then tell everyone about it.",
        "用家里的材料做一个小手工，拍照留念。":
            "Make a small craft with materials from home and take a photo of it.",
        "写下今天最开心或最难忘的一件事，三句话以上。":
            "Write about today's happiest or most memorable moment, in at least three sentences.",
        // 家庭责任
        "打一个电话，聊聊这周学校里发生的事，问问他们的身体。":
            "Make a call, chat about what happened at school this week, and ask how they are feeling.",
        "把你会的一个小技能（游戏、折纸、手机操作）教给家里人。":
            "Teach your family one small skill you know (a game, origami, or using the phone).",
        "认真陪弟弟妹妹玩 20 分钟，让他们开心。":
            "Play attentively with your younger sibling for 20 minutes and make them happy."
    ]

    // MARK: - 其他内置短语（成长包标题/摘要等）

    private static let phraseMap: [String: String] = [
        "今日成长计划": "Today's Growth Plan",
        "把今天的学习、生活和运动安排成清楚的小计划，完成后获得成长积分。":
            "Turn today's learning, life, and exercise into one clear little plan; finish it to earn Growth Points.",
        "今日任务包": "Today's Task Pack",
        "阅读任务": "Reading task"
    ]
}
