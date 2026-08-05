import Foundation

struct ChildProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var age: Int
    var dailyLimitMinutes: Int
    var rewardBalanceMinutes: Int
    /// 兴趣标签（恐龙/乐高/画画……），供 AI 生成个性化任务。旧数据缺省为空。
    var interests: [String]?
    /// 家长备注（"怕黑""刚学拼音"），只进家长自己的 AI 通道。旧数据缺省为空。
    var parentNotes: String?
    /// 幼儿模式：TA 还不认字。开启后孩子端换成大图标卡片界面，并显示手动点读的小喇叭。
    var preReaderMode: Bool?
    /// TA 的学习内容语言（任务/阅读/考题）；nil = 跟随家庭设置。
    /// 支持"家长中文、孩子学英文"，兄妹也可以不同。
    var contentLanguage: FamilyLanguage?
    /// TA 的界面语言（按钮/导航/状态短语）；与学习内容语言分开。
    /// nil = 跟随家庭级孩子界面语言，再跟随家庭语言；兄妹可以不同。
    var interfaceLanguage: AppInterfaceLanguage?
    /// 孩子给 AI 小伙伴起的名字；nil 时使用默认名字。
    var aiCompanionName: String?
    /// 孩子选择的小伙伴声音风格；nil 时使用温柔陪伴音。
    var aiCompanionVoice: AICompanionVoiceStyle?
    /// 孩子偏好的小伙伴互动人格；nil 时使用耐心引导型。
    var aiCompanionPersonality: AICompanionPersonalityStyle?
    /// 孩子给小伙伴定义的外貌/虚拟形象；nil 时使用默认星光伙伴形象。
    var aiCompanionAvatarDescription: String?

    init(
        id: UUID,
        name: String,
        age: Int,
        dailyLimitMinutes: Int,
        rewardBalanceMinutes: Int,
        interests: [String]? = nil,
        parentNotes: String? = nil,
        preReaderMode: Bool? = nil,
        contentLanguage: FamilyLanguage? = nil,
        interfaceLanguage: AppInterfaceLanguage? = nil,
        aiCompanionName: String? = nil,
        aiCompanionVoice: AICompanionVoiceStyle? = nil,
        aiCompanionPersonality: AICompanionPersonalityStyle? = nil,
        aiCompanionAvatarDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.dailyLimitMinutes = dailyLimitMinutes
        self.rewardBalanceMinutes = rewardBalanceMinutes
        self.interests = interests
        self.parentNotes = parentNotes
        self.preReaderMode = preReaderMode
        self.contentLanguage = contentLanguage
        self.interfaceLanguage = interfaceLanguage
        self.aiCompanionName = aiCompanionName
        self.aiCompanionVoice = aiCompanionVoice
        self.aiCompanionPersonality = aiCompanionPersonality
        self.aiCompanionAvatarDescription = aiCompanionAvatarDescription
    }

    var resolvedInterests: [String] { interests ?? [] }
    /// 未由家长明确设置时，7 岁及以下默认使用大图标幼儿界面。
    /// `false` 表示家长明确关闭，不能再被年龄规则重新开启。
    var isPreReader: Bool { preReaderMode ?? (age <= 7) }
    var companionDisplayName: String { companionDisplayName(for: .chinese) }
    var companionVoiceStyle: AICompanionVoiceStyle { aiCompanionVoice ?? .warm }
    var companionPersonalityStyle: AICompanionPersonalityStyle { aiCompanionPersonality ?? .gentleGuide }
    var companionAvatarDescription: String { companionAvatarDescription(for: .chinese) }

    /// 未自定义名字时使用产品化 AI 老师名称；孩子仍可在伙伴设置中自定义名字。
    func companionDisplayName(for language: AppInterfaceLanguage) -> String {
        let trimmed = (aiCompanionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyDefaultNames = ["星星伙伴", "Star Buddy"]
        return trimmed.isEmpty || legacyDefaultNames.contains(trimmed)
            ? language.pick("AI 章鱼老师", "AI Octo Teacher")
            : trimmed
    }

    /// 未自定义形象时按孩子界面语言给默认样子描述。
    func companionAvatarDescription(for language: AppInterfaceLanguage) -> String {
        let trimmed = (aiCompanionAvatarDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        return language.pick(
            "一位戴眼镜、爱读书的橙色章鱼 AI 老师，会陪在孩子的任务和阅读旁边",
            "A friendly orange octopus AI teacher with glasses and a book, ready to help with tasks and reading"
        )
    }

    static let sample = ChildProfile(
        id: UUID(),
        name: "孩子",
        age: 10,
        dailyLimitMinutes: 60,
        rewardBalanceMinutes: 0
    )
}

/// AI 小伙伴的本机声音偏好。这里只保存孩子的选择；真正 TTS 仍由 SpeechReader 决定。
enum AICompanionVoiceStyle: String, Codable, CaseIterable, Equatable {
    case warm
    case bright
    case calm

    var label: String {
        switch self {
        case .warm: return "温柔陪伴音"
        case .bright: return "活力鼓励音"
        case .calm: return "安静讲解音"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .warm: return "Warm companion voice"
        case .bright: return "Bright cheer voice"
        case .calm: return "Calm storyteller voice"
        }
    }

    var sampleText: String {
        switch self {
        case .warm: return "我会慢慢陪你，一步一步来。"
        case .bright: return "准备好了吗？我们先做一个小小的开始！"
        case .calm: return "别急，我们先观察，再想下一步。"
        }
    }

    func sampleText(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return sampleText }
        switch self {
        case .warm: return "I'll go slowly with you, one step at a time."
        case .bright: return "Ready? Let's make a tiny start together!"
        case .calm: return "No rush — let's look first, then think about the next step."
        }
    }

    var localSpeechRate: Float {
        switch self {
        case .warm: return 0.46
        case .bright: return 0.51
        case .calm: return 0.43
        }
    }

    var localPitchMultiplier: Float {
        switch self {
        case .warm: return 1.0
        case .bright: return 1.12
        case .calm: return 0.92
        }
    }

    var openAISpeechVoice: String {
        switch self {
        case .warm: return "nova"
        case .bright: return "shimmer"
        case .calm: return "onyx"
        }
    }
}

/// AI 小伙伴的人格偏好。第一版只影响界面和提示语，不改变安全边界。
enum AICompanionPersonalityStyle: String, Codable, CaseIterable, Equatable {
    case gentleGuide
    case playfulCoach
    case quietBuddy

    var label: String {
        switch self {
        case .gentleGuide: return "耐心引导型"
        case .playfulCoach: return "活泼教练型"
        case .quietBuddy: return "安静陪伴型"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .gentleGuide: return "Patient guide"
        case .playfulCoach: return "Playful coach"
        case .quietBuddy: return "Quiet companion"
        }
    }

    var childHint: String {
        switch self {
        case .gentleGuide: return "会多问一步，帮你自己想出来。"
        case .playfulCoach: return "会用鼓励和小游戏把事情拆小。"
        case .quietBuddy: return "会先听你说，再轻轻提醒下一步。"
        }
    }

    func childHint(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return childHint }
        switch self {
        case .gentleGuide: return "Asks one more question to help you figure it out yourself."
        case .playfulCoach: return "Uses cheers and little games to break things into small pieces."
        case .quietBuddy: return "Listens to you first, then gently reminds you of the next step."
        }
    }
}

/// 家庭级设置：AI 生成内容的语言等。旧数据缺省为中文。
enum FamilyLanguage: String, Codable, CaseIterable {
    case chinese
    case english
    case bilingual

    var label: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        case .bilingual: return "中英双语"
        }
    }

    func label(for interfaceLanguage: AppInterfaceLanguage) -> String {
        guard interfaceLanguage == .english else { return label }
        switch self {
        case .chinese: return "Chinese"
        case .english: return "English"
        case .bilingual: return "Chinese + English"
        }
    }

    /// 注入 AI prompt 的语言指令。
    var promptInstruction: String {
        switch self {
        case .chinese: return "所有任务内容用简体中文。"
        case .english: return "Write all task content in English."
        case .bilingual: return "任务内容用简体中文，并附英文对照。"
        }
    }
}

/// App 界面语言。界面语言与学习内容语言分开：家长可以用中文管理，孩子用英文操作。
enum AppInterfaceLanguage: String, Codable, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .chinese: return "zh-Hans"
        case .english: return "en"
        }
    }

    var taskLanguage: FamilyLanguage {
        switch self {
        case .chinese: return .chinese
        case .english: return .english
        }
    }
}

/// 电子书章节结构：EPUB 加载后会按 OPF spine 抽取章节文本范围。
struct BookChapter: Identifiable, Codable, Equatable {
    let id: UUID
    var order: Int
    var title: String
    var startCharacter: Int
    var endCharacter: Int

    init(
        id: UUID = UUID(),
        order: Int,
        title: String,
        startCharacter: Int,
        endCharacter: Int
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.startCharacter = startCharacter
        self.endCharacter = endCharacter
    }
}

/// 导入到 App 书库的电子书（PDF/TXT/HTML/EPUB，无 DRM）。文件只存本机沙盒 Documents/books/。
struct FamilyBook: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var fileName: String
    /// pdf | txt | html | htm | epub
    var format: String
    var pageCount: Int
    var charCount: Int
    /// EPUB/HTML/TXT 的章节范围；PDF 可为空。
    var chapters: [BookChapter]
    var importedAt: Date
    /// 仅用于家长端内容中心展示，不参与联网或鉴权。
    var sourceName: String?
    var sourceURLString: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case fileName
        case format
        case pageCount
        case charCount
        case chapters
        case importedAt
        case sourceName
        case sourceURLString
    }

    init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        format: String,
        pageCount: Int,
        charCount: Int,
        chapters: [BookChapter] = [],
        importedAt: Date = Date(),
        sourceName: String? = nil,
        sourceURLString: String? = nil
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.format = format
        self.pageCount = pageCount
        self.charCount = charCount
        self.chapters = chapters
        self.importedAt = importedAt
        self.sourceName = sourceName
        self.sourceURLString = sourceURLString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        fileName = try container.decode(String.self, forKey: .fileName)
        format = try container.decode(String.self, forKey: .format)
        pageCount = try container.decode(Int.self, forKey: .pageCount)
        charCount = try container.decode(Int.self, forKey: .charCount)
        chapters = try container.decodeIfPresent([BookChapter].self, forKey: .chapters) ?? []
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        sourceURLString = try container.decodeIfPresent(String.self, forKey: .sourceURLString)
    }
}

/// 孩子在 App 内阅读一本书的本地进度。只存在家庭本机数据里，不上传。
struct BookReadingProgress: Identifiable, Codable, Equatable {
    let id: UUID
    var childId: UUID
    var bookId: UUID
    var assignmentId: UUID?
    var lastPage: Int?
    var lastCharacterOffset: Int?
    var fontSize: Double
    var speechRate: Double
    var totalSeconds: Int
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        childId: UUID,
        bookId: UUID,
        assignmentId: UUID? = nil,
        lastPage: Int? = nil,
        lastCharacterOffset: Int? = nil,
        fontSize: Double = 18,
        speechRate: Double = 1.0,
        totalSeconds: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.childId = childId
        self.bookId = bookId
        self.assignmentId = assignmentId
        self.lastPage = lastPage
        self.lastCharacterOffset = lastCharacterOffset
        self.fontSize = fontSize
        self.speechRate = speechRate
        self.totalSeconds = totalSeconds
        self.updatedAt = updatedAt
    }
}

/// 家庭所在地区：决定购书/内容渠道与平台默认。
enum FamilyRegion: String, Codable, CaseIterable {
    case china
    case usa
    case other

    var label: String {
        switch self {
        case .china: return "中国"
        case .usa: return "美国"
        case .other: return "其他地区"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .china: return "China"
        case .usa: return "United States"
        case .other: return "Other"
        }
    }
}

enum SchoolIntegrationStatus: String, Codable, Equatable {
    case notConnected
    case pending
    case connected
    case suspended
}

/// 学校后台的家庭侧接入契约。第一阶段只保存状态与授权范围，不保存学校密钥或伪造联网。
struct SchoolIntegrationSettings: Codable, Equatable {
    var status: SchoolIntegrationStatus
    var schoolDisplayName: String?
    var allowsTeacherAssignments: Bool
    var sharesHomeworkCompletion: Bool
    var lastSyncAt: Date?

    static let disconnected = SchoolIntegrationSettings(
        status: .notConnected,
        schoolDisplayName: nil,
        allowsTeacherAssignments: false,
        sharesHomeworkCompletion: false,
        lastSyncAt: nil
    )
}

struct FamilySettings: Codable, Equatable {
    /// 家长语言：AI 给家长看的内容（书籍简介/计划说明/初评摘要）用它；
    /// 同时是孩子内容语言的家庭默认值。
    var language: FamilyLanguage
    /// 语音朗读（儿童无障碍）：开启后孩子端文字旁出现小喇叭。旧数据缺省关闭。
    var readAloudEnabled: Bool?
    /// 家庭所在地区；旧数据缺省中国。
    var region: FamilyRegion?
    /// 云端真人语音（用家长的 AI 账号做 TTS，音质接近真人）；旧数据缺省开启，
    /// 仅在 AI 就绪时实际生效，失败自动回落本机语音。
    var cloudVoiceEnabled: Bool?
    /// 家长与孩子的 UI 语言分别保存；旧数据按家庭内容语言推导。
    var parentInterfaceLanguage: AppInterfaceLanguage? = nil
    var childInterfaceLanguage: AppInterfaceLanguage? = nil
    /// 未来学校后台接入的家庭侧授权与状态；不含任何密钥。
    var schoolIntegration: SchoolIntegrationSettings? = nil

    var resolvedReadAloud: Bool { readAloudEnabled ?? false }
    var resolvedRegion: FamilyRegion { region ?? .china }
    var resolvedCloudVoice: Bool { cloudVoiceEnabled ?? true }
    var resolvedParentInterfaceLanguage: AppInterfaceLanguage {
        parentInterfaceLanguage ?? (language == .english ? .english : .chinese)
    }
    var resolvedChildInterfaceLanguage: AppInterfaceLanguage {
        childInterfaceLanguage ?? (language == .english ? .english : .chinese)
    }
    var resolvedSchoolIntegration: SchoolIntegrationSettings {
        schoolIntegration ?? .disconnected
    }

    static let `default` = FamilySettings(language: .chinese, readAloudEnabled: false)
}

enum TaskCategory: String, Codable, CaseIterable {
    case home
    case learning
    case health
    case creative
    case family
    case school

    var label: String {
        switch self {
        case .home: return "家务"
        case .learning: return "学习"
        case .health: return "体育锻炼"
        case .creative: return "创造"
        case .family: return "家庭"
        case .school: return "学校任务"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .home: return "Chores"
        case .learning: return "Learning"
        case .health: return "Exercise"
        case .creative: return "Creative"
        case .family: return "Family"
        case .school: return "School"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .learning: return "book.fill"
        case .health: return "figure.run"
        case .creative: return "paintpalette.fill"
        case .family: return "heart.fill"
        case .school: return "backpack.fill"
        }
    }

    /// 孩子端分组展示顺序。
    static let childDisplayOrder: [TaskCategory] = [.learning, .school, .home, .health, .creative, .family]
}

/// 创作任务的真实类型。创作广场、家长布置表单和 AI 点评共用这一份定义，
/// 避免画画、手工、乐高等能力散落成互不相认的页面。
enum CreativeTaskKind: String, Codable, CaseIterable, Identifiable {
    case drawing
    case music
    case handcraft
    case buildingBlocks
    case lego
    case toyDesign
    case storytelling
    case photography
    case claySculpture
    case danceDrama
    case cooking
    case natureArt
    case scienceMaking
    case digitalCreation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .drawing: return "绘画"
        case .music: return "音乐"
        case .handcraft: return "手工"
        case .buildingBlocks: return "积木"
        case .lego: return "乐高"
        case .toyDesign: return "玩具创作"
        case .storytelling: return "故事创作"
        case .photography: return "摄影"
        case .claySculpture: return "黏土塑形"
        case .danceDrama: return "舞蹈与表演"
        case .cooking: return "创意料理"
        case .natureArt: return "自然创作"
        case .scienceMaking: return "科学制作"
        case .digitalCreation: return "数字创作"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .drawing: return "Drawing"
        case .music: return "Music"
        case .handcraft: return "Crafts"
        case .buildingBlocks: return "Blocks"
        case .lego: return "LEGO"
        case .toyDesign: return "Toy Design"
        case .storytelling: return "Storytelling"
        case .photography: return "Photography"
        case .claySculpture: return "Clay Sculpting"
        case .danceDrama: return "Dance & Drama"
        case .cooking: return "Creative Cooking"
        case .natureArt: return "Nature Art"
        case .scienceMaking: return "Science Making"
        case .digitalCreation: return "Digital Creation"
        }
    }

    var systemImage: String {
        switch self {
        case .drawing: return "paintbrush.pointed.fill"
        case .music: return "music.note"
        case .handcraft: return "scissors"
        case .buildingBlocks: return "square.3.layers.3d"
        case .lego: return "shippingbox.fill"
        case .toyDesign: return "teddybear.fill"
        case .storytelling: return "text.book.closed.fill"
        case .photography: return "camera.fill"
        case .claySculpture: return "hand.raised.fill"
        case .danceDrama: return "theatermasks.fill"
        case .cooking: return "fork.knife"
        case .natureArt: return "leaf.fill"
        case .scienceMaking: return "flask.fill"
        case .digitalCreation: return "ipad.and.iphone"
        }
    }

    var starterTitle: String {
        switch self {
        case .drawing: return "画一幅有故事的画"
        case .music: return "创作一段自己的节奏"
        case .handcraft: return "用家里的材料做一件作品"
        case .buildingBlocks: return "搭一座能站稳的建筑"
        case .lego: return "用乐高完成一个主题作品"
        case .toyDesign: return "给玩具设计一个新玩法"
        case .storytelling: return "讲一个自己编的小故事"
        case .photography: return "拍一组有主题的照片"
        case .claySculpture: return "捏一个想象中的角色"
        case .danceDrama: return "编一段动作或小表演"
        case .cooking: return "和大人一起做创意点心"
        case .natureArt: return "用落叶和石头做自然作品"
        case .scienceMaking: return "做一个能演示原理的小装置"
        case .digitalCreation: return "做一张数字海报或小动画"
        }
    }

    func starterTitle(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return starterTitle }
        switch self {
        case .drawing: return "Draw a picture that tells a story"
        case .music: return "Create your own rhythm"
        case .handcraft: return "Make something from household materials"
        case .buildingBlocks: return "Build a structure that stands"
        case .lego: return "Build a themed LEGO creation"
        case .toyDesign: return "Invent a new way to play"
        case .storytelling: return "Tell an original short story"
        case .photography: return "Take a themed photo series"
        case .claySculpture: return "Sculpt an imaginary character"
        case .danceDrama: return "Create a movement or mini performance"
        case .cooking: return "Make a creative snack with a grown-up"
        case .natureArt: return "Create with leaves and stones"
        case .scienceMaking: return "Build a device that shows how something works"
        case .digitalCreation: return "Make a digital poster or animation"
        }
    }

    var starterPrompt: String {
        switch self {
        case .drawing: return "选一个你喜欢的主题，用颜色画出最重要的部分，完成后说说画里的故事。"
        case .music: return "用拍手、哼唱或乐器做一段 20 秒以上的节奏，完成后录音或说说灵感。"
        case .handcraft: return "先想好要做什么，再选安全的材料；需要剪刀、热胶或电器时请大人帮忙。"
        case .buildingBlocks: return "先画或说出计划，再搭出作品，试试看它能不能稳定站住。"
        case .lego: return "围绕一个主题自由搭建，至少加入一个你自己发明的细节。"
        case .toyDesign: return "挑一个玩具，为它设计新角色、新规则或新场景，并演示给大人看。"
        case .storytelling: return "故事要有角色、发生的事情和结尾；不会写字可以直接录语音。"
        case .photography: return "围绕同一个主题拍 3 张照片，再选出最满意的一张并说明原因。"
        case .claySculpture: return "先捏出大形状，再补细节和表情，完成后给角色起一个名字。"
        case .danceDrama: return "设计开头、中间和结尾三个动作，需要奔跑或跳跃时先清理周围。"
        case .cooking: return "和大人一起完成准备、制作和收拾，刀、火和电器必须由大人负责。"
        case .natureArt: return "只捡地上的自然材料，不折活的花草；完成后说说每种材料从哪里来。"
        case .scienceMaking: return "先说出你的猜想，再制作和试验，记录成功或需要改进的地方。"
        case .digitalCreation: return "用家长允许的工具创作，不上传个人信息；完成后展示最满意的画面。"
        }
    }

    var starterMaterials: [String] {
        switch self {
        case .drawing: return ["画纸", "彩笔或颜料"]
        case .music: return ["可以发出声音的安全物品或乐器"]
        case .handcraft: return ["纸盒或纸杯", "胶带", "彩笔"]
        case .buildingBlocks: return ["积木"]
        case .lego: return ["乐高零件"]
        case .toyDesign: return ["一个玩具", "可选的场景材料"]
        case .storytelling: return ["录音或画故事的纸笔"]
        case .photography: return ["相机或手机"]
        case .claySculpture: return ["安全黏土", "垫板"]
        case .danceDrama: return ["安全的活动空间"]
        case .cooking: return ["家长确认的食材", "围裙"]
        case .natureArt: return ["地上捡到的落叶、树枝或石头"]
        case .scienceMaking: return ["家长确认的实验材料"]
        case .digitalCreation: return ["家长允许的平板或电脑"]
        }
    }

    var needsAdultByDefault: Bool {
        self == .handcraft || self == .cooking || self == .scienceMaking
    }
}

/// 一次创作任务的结构化说明。照片和语音作品仍由 ProofDraft 留在本机沙盒。
struct CreativeTaskSpec: Codable, Equatable {
    var kind: CreativeTaskKind
    var creativePrompt: String
    var materials: [String]
    var estimatedMinutes: Int

    init(kind: CreativeTaskKind, creativePrompt: String, materials: [String], estimatedMinutes: Int) {
        self.kind = kind
        self.creativePrompt = creativePrompt
        self.materials = materials
        self.estimatedMinutes = max(5, estimatedMinutes)
    }
}

/// 任务重复属性：一次性 / 每天 / 每周某天（家长布置时选择）。
enum TaskRecurrence: String, Codable, CaseIterable {
    case once
    case daily
    case weekly

    var label: String {
        switch self {
        case .once: return "一次性"
        case .daily: return "每天"
        case .weekly: return "每周"
        }
    }
}

/// 重复任务规则：按规则每天/每周自动生成当日任务实例（幂等）。
struct RecurringTaskRule: Identifiable, Codable, Equatable {
    let id: UUID
    var childId: UUID
    var template: TaskTemplate
    var recurrence: TaskRecurrence
    /// weekly 时的星期几（1=周日 … 7=周六，跟随 Calendar.weekday）。
    var weekday: Int?
    /// 最近一次生成的日期键（"2026-07-04"），防重复生成。
    var lastGeneratedDayKey: String?
}

/// 家长/监护角色称谓。敏感称谓一律用友好说法（继母/继父可用阿姨/叔叔或自定义昵称，
/// 保姆用家庭老师），尊重使用者感受。
enum GuardianRole: String, Codable, CaseIterable {
    case dad
    case mom
    case grandpaP      // 爷爷
    case grandmaP      // 奶奶
    case grandpaM      // 外公
    case grandmaM      // 外婆
    case uncle
    case aunt
    case familyTeacher // 家庭老师（照护者的友好称谓）
    case guardian      // 监护人（通用）

    var label: String {
        switch self {
        case .dad: return "爸爸"
        case .mom: return "妈妈"
        case .grandpaP: return "爷爷"
        case .grandmaP: return "奶奶"
        case .grandpaM: return "外公"
        case .grandmaM: return "外婆"
        case .uncle: return "叔叔"
        case .aunt: return "阿姨"
        case .familyTeacher: return "家庭老师"
        case .guardian: return "监护人"
        }
    }
}

/// 家庭里的大人：谁在布置任务、谁批准。displayName 可自定义（如"张老师""大伯"）。
struct GuardianProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var role: GuardianRole
}

enum TaskDifficulty: String, Codable, CaseIterable {
    case easy
    case medium
    case hard

    var label: String {
        switch self {
        case .easy: return "轻松"
        case .medium: return "适中"
        case .hard: return "挑战"
        }
    }
}

/// 证明类型。照片仅保存在本机 App 沙盒，绝不上传网络或对亲友公开。
enum ProofKind: String, Codable, CaseIterable {
    case text
    /// 早期兼容字段，用来记录未迁移照片证明的本地标记。
    case photoPlaceholder
    /// 真实照片证明：孩子从相册选一张照片，仅存本机，家长审核时可见。
    case photo

    var label: String {
        switch self {
        case .text: return "写一句话"
        // 旧数据按照片证明展示，与孩子端体验一致。
        case .photoPlaceholder, .photo: return "拍照片"
        }
    }
}

/// 任务包类型：与成长包平台化 v2 规范（docs/modules/GROWTH_PACK_PLATFORM_UPGRADE.md）对齐。
enum PackType: String, Codable, CaseIterable {
    case basicHabits = "basic_habits"
    case chores
    case outdoorSports = "outdoor_sports"
    case learning
    case skillExtension = "skill_extension"
    case financeLiteracy = "finance_literacy"
    case creativeWorks = "creative_works"
    case familyResponsibility = "family_responsibility"

    var label: String {
        switch self {
        case .basicHabits: return "个人独立性任务包"
        case .chores: return "家务包"
        case .outdoorSports: return "户外运动包"
        case .learning: return "学习成长包"
        case .skillExtension: return "技能扩展包"
        case .financeLiteracy: return "金融素养包"
        case .creativeWorks: return "创造作品包"
        case .familyResponsibility: return "家庭责任包"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .basicHabits: return "Independence Pack"
        case .chores: return "Chores Pack"
        case .outdoorSports: return "Outdoor Sports Pack"
        case .learning: return "Learning Pack"
        case .skillExtension: return "Skill Builder Pack"
        case .financeLiteracy: return "Money Skills Pack"
        case .creativeWorks: return "Creative Works Pack"
        case .familyResponsibility: return "Family Care Pack"
        }
    }

    var systemImage: String {
        switch self {
        case .basicHabits: return "sunrise"
        case .chores: return "house"
        case .outdoorSports: return "figure.outdoor.cycle"
        case .learning: return "book"
        case .skillExtension: return "wrench.and.screwdriver"
        case .financeLiteracy: return "banknote"
        case .creativeWorks: return "paintpalette"
        case .familyResponsibility: return "heart"
        }
    }

    var supportsCustomTemplates: Bool {
        switch self {
        case .basicHabits, .chores, .outdoorSports, .creativeWorks:
            return true
        case .learning, .skillExtension, .financeLiteracy, .familyResponsibility:
            return false
        }
    }

    var defaultCustomCategory: TaskCategory {
        switch self {
        case .outdoorSports:
            return .health
        case .basicHabits, .chores:
            return .home
        case .learning:
            return .learning
        case .skillExtension, .creativeWorks:
            return .creative
        case .financeLiteracy:
            return .learning
        case .familyResponsibility:
            return .family
        }
    }

    var customTemplatePrompt: String {
        switch self {
        case .basicHabits:
            return "例如：自己剪指甲前准备、洗完澡收浴巾、出门前检查水壶。"
        case .chores:
            return "例如：擦餐桌、收快递、整理鞋柜、给植物浇水。"
        case .outdoorSports:
            return "例如：跳绳 15 分钟、骑车 30 分钟、公园观察 20 分钟。"
        case .creativeWorks:
            return "例如：画一幅有故事的画、搭一座桥、编一个小故事、拍一组自然照片。"
        default:
            return "添加一个家庭自定义任务。"
        }
    }
}

/// 学习验收方式：家长确认后，孩子端按它展示小测或语音复述要求。
enum TaskVerificationMode: String, Codable, CaseIterable {
    case choiceQuiz = "choice_quiz"
    case voiceRetell = "voice_retell"
    case learningDrill = "learning_drill"

    var label: String {
        switch self {
        case .choiceQuiz: return "选择题小测"
        case .voiceRetell: return "语音复述"
        case .learningDrill: return "学习题练习"
        }
    }
}

/// 验收内容类型：故事/知识内容与字母数学等练习内容分开，避免用故事题验收识字数学。
enum TaskVerificationContentKind: String, Codable, CaseIterable {
    case story
    case knowledge
    case literacy
    case math

    var label: String {
        switch self {
        case .story: return "故事理解"
        case .knowledge: return "知识理解"
        case .literacy: return "识字/字母"
        case .math: return "数学练习"
        }
    }
}

/// 任务验收规格：统一承载阅读、视频学习和识字数学任务的 AI 验收入口。
/// AI 只做初评；是否通过、是否发成长积分仍由家长终审。
struct TaskVerificationSpec: Codable, Equatable {
    var mode: TaskVerificationMode
    var contentKind: TaskVerificationContentKind
    /// 选择题/学习题题数，家长可在 5-10 之间选择。
    var questionCount: Int?
    /// 语音复述建议秒数，默认 180 秒。
    var minimumRetellSeconds: Int?
    /// 视频等外部内容的家长确认摘要；孩子验收和 AI 初评只基于确认后的摘要。
    var parentApprovedSummary: String?

    var resolvedQuestionCount: Int {
        min(10, max(5, questionCount ?? 5))
    }

    var resolvedMinimumRetellSeconds: Int {
        max(30, minimumRetellSeconds ?? 180)
    }

    var usesChoiceQuestions: Bool {
        mode == .choiceQuiz || mode == .learningDrill
    }

    static func reading(questionCount: Int = 5, contentKind: TaskVerificationContentKind = .story) -> TaskVerificationSpec {
        TaskVerificationSpec(
            mode: contentKind == .literacy || contentKind == .math ? .learningDrill : .choiceQuiz,
            contentKind: contentKind,
            questionCount: questionCount,
            minimumRetellSeconds: nil,
            parentApprovedSummary: nil
        )
    }

    static func retell(summary: String? = nil, seconds: Int = 180, contentKind: TaskVerificationContentKind = .knowledge) -> TaskVerificationSpec {
        TaskVerificationSpec(
            mode: .voiceRetell,
            contentKind: contentKind,
            questionCount: nil,
            minimumRetellSeconds: seconds,
            parentApprovedSummary: summary
        )
    }
}

enum ReadingDeliveryMode: String, Codable, Equatable {
    /// 家长明确布置的实体书/外部纸质材料，不要求 App 内电子书。
    case physicalManual = "physical_manual"
    /// 电子书已经进入家庭书库，孩子设备必须先同步到内容才能看到任务。
    case digitalLoaded = "digital_loaded"
    /// AI/成长包只提出了书名，但电子书还没有加载；不能投递到孩子设备。
    case digitalRequired = "digital_required"
}

/// 阅读任务规格：书目、最低阅读分钟和章节计划。
/// 第一版章节计划由家长手写；后续版本可由 AI 起草、家长批准后锁定。
struct ReadingSpec: Codable, Equatable {
    var bookTitle: String
    var minMinutes: Int
    /// 本次要读的章节/页码范围，例如"第 1-2 章"。
    var chapterPlanText: String
    /// App 内阅读内容（AI 按书名+章节+年龄生成的适龄改写文本）。
    /// 孩子第一次点「开始阅读」时懒生成并缓存；nil 表示读实体书/外部平台。
    var inAppContent: String?
    /// 家长是否允许「没有这本书时用 AI 生成改写版在 App 里读」。
    /// 默认关闭——主推真实书籍购买/下载渠道，规避版权争议。
    var allowAIContent: Bool?
    /// 关联的导入电子书（FamilyBook.id）；孩子在 App 内直接翻到本次页码阅读。
    var importedBookId: UUID?
    /// 本次阅读的起止页（PDF）或起止字符段（TXT）。
    var pageStart: Int?
    var pageEnd: Int?
    /// 旧版本没有该字段。缺省时只有带 importedBookId 的任务可视为已加载电子书；
    /// 其余旧任务不得静默冒充实体书任务。
    var deliveryMode: ReadingDeliveryMode?

    var aiContentAllowed: Bool { allowAIContent ?? false }
    var resolvedDeliveryMode: ReadingDeliveryMode {
        deliveryMode ?? (importedBookId == nil ? .digitalRequired : .digitalLoaded)
    }

    init(
        bookTitle: String,
        minMinutes: Int,
        chapterPlanText: String,
        inAppContent: String? = nil,
        allowAIContent: Bool? = nil,
        importedBookId: UUID? = nil,
        pageStart: Int? = nil,
        pageEnd: Int? = nil,
        deliveryMode: ReadingDeliveryMode? = nil
    ) {
        self.bookTitle = bookTitle
        self.minMinutes = minMinutes
        self.chapterPlanText = chapterPlanText
        self.inAppContent = inAppContent
        self.allowAIContent = allowAIContent
        self.importedBookId = importedBookId
        self.pageStart = pageStart
        self.pageEnd = pageEnd
        self.deliveryMode = deliveryMode
    }
}

/// 视频学习任务规格：家长批准的视频链接与最低观看时长。
/// 链接由家长亲自粘贴或从 AI 建议里挑选后确认，孩子端点开在浏览器观看。
struct VideoSpec: Codable, Equatable {
    var urlString: String
    /// 展示用平台名（如 YouTube / Bilibili）。
    var platformLabel: String
    var minWatchMinutes: Int
    /// 该视频计入哪个学科徽章（LearningSubject.rawValue）；旧数据缺省按科学。
    var subjectRaw: String?
    /// 家长确认过的学习摘要。AI 可起草，但必须由家长确认后才作为验收依据。
    var contentSummary: String?

    init(
        urlString: String,
        platformLabel: String,
        minWatchMinutes: Int,
        subjectRaw: String? = nil,
        contentSummary: String? = nil
    ) {
        self.urlString = urlString
        self.platformLabel = platformLabel
        self.minWatchMinutes = minWatchMinutes
        self.subjectRaw = subjectRaw
        self.contentSummary = contentSummary
    }
}

struct TaskLocalizedContent: Codable, Equatable {
    var language: AppInterfaceLanguage
    var title: String
    var instructions: String
}

struct TaskTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var category: TaskCategory
    var difficulty: TaskDifficulty
    var rewardMinutes: Int
    var instructions: String
    var requiredProof: ProofKind
    /// 需要大人在场的动手任务（用电、用刀、炉灶等）。旧数据缺省视为不需要。
    var adultSupervisionRequired: Bool?
    /// 阅读任务的书目与章节计划；非阅读任务为 nil。旧数据缺省为 nil。
    var reading: ReadingSpec?
    /// 视频学习任务的链接与观看要求；非视频任务为 nil。旧数据缺省为 nil。
    var video: VideoSpec?
    /// 学习验收规格；nil 表示沿用旧证明/审批流程。
    var verification: TaskVerificationSpec?
    /// 创作任务的类型、创作提示和材料；非创作任务为 nil。
    var creative: CreativeTaskSpec?
    /// 任务来自哪个包（包工作台的「本包已布置」列表用）。旧数据缺省为 nil。
    var packType: PackType?
    /// 家长自定义任务的翻译缓存。原文始终保留在 title/instructions，不被翻译覆盖。
    var localizedContent: [TaskLocalizedContent]?

    init(
        id: UUID,
        title: String,
        category: TaskCategory,
        difficulty: TaskDifficulty,
        rewardMinutes: Int,
        instructions: String,
        requiredProof: ProofKind,
        adultSupervisionRequired: Bool? = nil,
        reading: ReadingSpec? = nil,
        video: VideoSpec? = nil,
        verification: TaskVerificationSpec? = nil,
        creative: CreativeTaskSpec? = nil,
        packType: PackType? = nil,
        localizedContent: [TaskLocalizedContent]? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.difficulty = difficulty
        self.rewardMinutes = rewardMinutes
        self.instructions = instructions
        self.requiredProof = requiredProof
        self.adultSupervisionRequired = adultSupervisionRequired
        self.reading = reading
        self.video = video
        self.verification = verification
        self.creative = creative
        self.packType = packType
        self.localizedContent = localizedContent
    }

    var needsAdultSupervision: Bool { adultSupervisionRequired ?? false }

    /// 孩子端展示标题：家长翻译缓存优先，其次内置任务的确定性英文映射；
    /// 都没有且原文是目标语言读不懂的文字时，给出显式「等待翻译」提示，
    /// 不静默展示另一种语言（原文仍保留在家长端字段里）。
    func displayTitle(for language: AppInterfaceLanguage) -> String {
        if let localized = localizedContent?.first(where: { $0.language == language })?.title,
           !localized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localized
        }
        // 视频标题是资源名称。保留真实主题比统一替换成「翻译准备中」
        // 更有意义，也让旧云端任务无需重新布置即可恢复可辨识标题。
        if video != nil {
            return displayVideoTitle(for: language)
        }
        if language == .english, let builtIn = BuiltInTaskLocalization.englishTitle(for: title) {
            return builtIn
        }
        return TaskLanguageFallback.title(title, for: language)
    }

    private func displayVideoTitle(for language: AppInterfaceLanguage) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        let genericTitles: Set<String> = [
            "",
            "任务翻译准备中",
            "task translation pending",
            "看视频学习",
            "watch & learn",
            "watch and learn",
            "学习视频",
            "learning video"
        ]

        guard !genericTitles.contains(normalized),
              !normalized.hasPrefix("http://"),
              !normalized.hasPrefix("https://") else {
            return language.pick("学习视频", "Learning Video")
        }
        return trimmed
    }

    func displayInstructions(for language: AppInterfaceLanguage) -> String {
        if let localized = localizedContent?.first(where: { $0.language == language })?.instructions {
            return localized
        }
        if language == .english, let builtIn = BuiltInTaskLocalization.englishInstructions(for: instructions) {
            return builtIn
        }
        return TaskLanguageFallback.instructions(instructions, for: language)
    }
}

enum TaskAssignmentStatus: String, Codable {
    case open
    case submitted
    case approved
    case rejected
    case cancelled
}

/// 任务撤销的发起方。只用于本机状态迁移与审计文案，不进入云端。
enum TaskCancellationActor {
    case child
    case guardian
}

/// 家长驳回任务时选择的原因，便于孩子知道如何重做。仅本地枚举，不含自由敏感文本。
enum RejectionReason: String, Codable, CaseIterable {
    case proofUnclear
    case incomplete
    case needRedo
    case other

    var label: String {
        switch self {
        case .proofUnclear: return "证明看不清楚"
        case .incomplete: return "任务还没完成"
        case .needRedo: return "需要重做一次"
        case .other: return "其他原因"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .proofUnclear: return "The proof is hard to see"
        case .incomplete: return "The task is not finished yet"
        case .needRedo: return "It needs another try"
        case .other: return "Another reason"
        }
    }
}

/// 证明草稿状态。提交后等待家长批准，批准/驳回由 store 决定。
enum ProofDraftStatus: String, Codable {
    case empty
    case drafting
    case submitted
}

/// 孩子端记录的证明草稿。
/// `photoFileName` 指向 App 沙盒 proof-photos 目录里的本机照片文件，不上传网络。
struct ProofDraft: Codable, Equatable {
    var kind: ProofKind
    var text: String
    var photoPlaceholderName: String?
    /// 真实照片证明的本机文件名；新照片任务与早期兼容任务都可使用。
    var photoFileName: String?
    /// 孩子的语音说明文件名（沙盒 proof-audio/，家长本机回放，不上传）。
    /// 任何证明类型都可以附带；不认字的幼儿可以只用语音当证明。
    var audioFileName: String?
    var status: ProofDraftStatus

    init(
        kind: ProofKind,
        text: String,
        photoPlaceholderName: String?,
        photoFileName: String? = nil,
        audioFileName: String? = nil,
        status: ProofDraftStatus
    ) {
        self.kind = kind
        self.text = text
        self.photoPlaceholderName = photoPlaceholderName
        self.photoFileName = photoFileName
        self.audioFileName = audioFileName
        self.status = status
    }

    static let empty = ProofDraft(kind: .text, text: "", photoPlaceholderName: nil, status: .empty)

    /// 该证明是否已具备可提交内容。文字任务里语音说明等价于文字。
    var hasContent: Bool {
        switch kind {
        case .text:
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || audioFileName != nil
        case .photoPlaceholder:
            return photoFileName != nil || photoPlaceholderName != nil
        case .photo:
            return photoFileName != nil
        }
    }
}

/// AI 对一次提交的初评（只是建议，永不终审）。持久化在 assignment 上供家长查看。
struct AIReviewSummary: Codable, Equatable {
    var confidence: Double
    var summary: String
    /// suggest_approve | needs_parent_judgment
    var recommendation: String
    /// 初评来源：local_rule（本地确定性规则）| cloud（真实 AI provider）。旧数据缺省视为 cloud。
    var source: String?
    /// 可以直接展示给孩子的具体、鼓励式点评。旧数据缺省为 nil。
    var childFeedback: String?

    init(
        confidence: Double,
        summary: String,
        recommendation: String,
        source: String? = nil,
        childFeedback: String? = nil
    ) {
        self.confidence = confidence
        self.summary = summary
        self.recommendation = recommendation
        self.source = source
        self.childFeedback = childFeedback
    }

    var isLocalRuleReview: Bool { source == "local_rule" }
}

struct TaskAssignment: Identifiable, Codable, Equatable {
    let id: UUID
    var childId: UUID
    var task: TaskTemplate
    var date: Date
    var status: TaskAssignmentStatus
    var proof: ProofDraft
    /// 最近一次被家长驳回的原因；批准或重新提交后清空。
    var rejectionReason: RejectionReason?
    /// AI 初评（提交后异步生成）；旧数据缺省为 nil。
    var aiReview: AIReviewSummary?
    /// 在 App 内阅读页累计的阅读秒数（进度跟进）；旧数据缺省为 nil。
    var readingSecondsSpent: Int?

    init(
        id: UUID,
        childId: UUID,
        task: TaskTemplate,
        date: Date,
        status: TaskAssignmentStatus,
        proof: ProofDraft,
        rejectionReason: RejectionReason? = nil,
        aiReview: AIReviewSummary? = nil,
        readingSecondsSpent: Int? = nil
    ) {
        self.id = id
        self.childId = childId
        self.task = task
        self.date = date
        self.status = status
        self.proof = proof
        self.rejectionReason = rejectionReason
        self.aiReview = aiReview
        self.readingSecondsSpent = readingSecondsSpent
    }
}

struct RewardGrant: Identifiable, Codable, Equatable {
    let id: UUID
    var childId: UUID
    var minutes: Int
    var reason: String
    var grantedAt: Date
    var expiresAt: Date?
    /// Stable origin for task rewards. Older persisted grants decode as nil.
    var sourceAssignmentId: UUID? = nil
}

/// 成长积分余额快照：可用、待批准、累计获得，供孩子端展示。
struct CreditBalance: Codable, Equatable {
    var availableMinutes: Int
    var pendingMinutes: Int
    var lifetimeEarnedMinutes: Int

    static let zero = CreditBalance(availableMinutes: 0, pendingMinutes: 0, lifetimeEarnedMinutes: 0)

    var hasSpendable: Bool { availableMinutes > 0 }
}

/// 成长包中单个步骤的运行态进度，由 store 根据任务状态推导。
enum GrowthStepProgress: String, Codable {
    case locked
    case active
    case submitted
    case approved
}

/// 成长包步骤：通过 assignmentId 关联到一条今日任务。
struct GrowthPackStep: Identifiable, Codable, Equatable {
    let id: UUID
    var order: Int
    var title: String
    var detail: String
    var assignmentId: UUID
    var rewardMinutes: Int
}

/// 任务解锁模式。
/// - free：默认，全部任务任意选择、互不阻塞（2026-07-04 用户拍板）。
/// - sequential：按顺序逐步解锁，留给未来的「闯关型」成长包。
enum PackSequencing: String, Codable {
    case free
    case sequential
}

/// 成长包：一组步骤。默认自由模式（全部可选），可按包开启顺序解锁。
struct GrowthPack: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var summary: String
    var steps: [GrowthPackStep]
    /// 旧数据缺省视为 free。
    var sequencing: PackSequencing?

    var resolvedSequencing: PackSequencing { sequencing ?? .free }

    init(id: UUID, title: String, summary: String, steps: [GrowthPackStep], sequencing: PackSequencing? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.steps = steps
        self.sequencing = sequencing
    }
}

/// 孩子端今日任务的展示模型，由 assignment 派生。
struct TodayTask: Identifiable, Equatable {
    let id: UUID
    var title: String
    var category: TaskCategory
    var rewardMinutes: Int
    var status: TaskAssignmentStatus
    var requiredProof: ProofKind
    var proofStatus: ProofDraftStatus
}

enum ShieldState: String, Codable {
    case locked
    case unlocked
}

struct ScreenTimeRule: Codable, Equatable {
    var childId: UUID
    var selectedAppsLocalOnly: [String]
    var shieldState: ShieldState
}

/// 奖励兑换屏幕时间会话的运行态。
/// - locked: 没有进行中的会话，娱乐 App 被遮挡（mock）。
/// - active: 解锁会话进行中，倒计时未结束。
/// - expired: 上一个会话因到期被自动重锁；与家长手动锁定区分，便于 UI 提示。
/// 注意：active 之外的任何状态对真实/模拟设备都表现为「锁定」，过期窗口绝不保持解锁。
enum RewardSessionStatus: String, Codable {
    case locked
    case active
    case expired
}

/// 会话结束原因，写入会话收据用于对账与展示。
enum SessionEndReason: String, Codable {
    /// 倒计时到期自动重锁。
    case expired
    /// 家长在倒计时内提前结束。
    case parentEnded
}

/// 会话收据：每次解锁会话结束（到期或家长提前结束）时生成的一条本地凭证。
/// 仅记录分钟数与时间戳，绝不包含真实设备标识、App bundle id 或孩子隐私字段。
struct RewardSessionReceipt: Identifiable, Codable, Equatable {
    let id: UUID
    /// Stable ID shared with the real Screen Time exception for idempotent cloud reporting.
    var sessionID: UUID? = nil
    /// Privacy-safe alias such as `app:<hash>`; never stores Apple's opaque app token.
    var appUsageRef: String? = nil
    /// 本次会话发放（解锁）的分钟数。
    var grantedMinutes: Int
    var startedAt: Date
    /// 计划到期时间（startedAt + grantedMinutes 分钟）。
    var plannedEndsAt: Date
    /// 实际结束时间。
    var endedAt: Date
    var endReason: SessionEndReason
    /// 实际消耗分钟（向上取整，封顶 grantedMinutes），用于与未来真实 DeviceActivity 用量回执对账。
    var consumedMinutes: Int
    /// 家长提前结束时未使用的分钟（grantedMinutes - consumedMinutes）。仅用于展示，本壳不自动退回成长积分。
    var unusedMinutes: Int
    /// Optional so receipts written before authority tracking remain decodable.
    var authority: ScreenTimeGrantAuthority? = nil

    var resolvedAuthority: ScreenTimeGrantAuthority { authority ?? .growthPoints }
}
