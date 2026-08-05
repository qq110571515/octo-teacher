import Foundation

/// 按任务内容匹配具体图标：孩子端优先使用稳定的 SF Symbol，旧界面继续拿表情兜底。
/// 关键词优先，类别兜底。纯函数便于测试。
enum TaskIconProvider {
    struct Icon: Equatable {
        let emoji: String
        let assetName: String?
        let systemImageName: String?

        init(emoji: String, assetName: String? = nil, systemImageName: String? = nil) {
            self.emoji = emoji
            self.assetName = assetName
            self.systemImageName = systemImageName
        }
    }

    /// (关键词, 图标) —— 先匹配到先用。
    static let keywordIcons: [(keywords: [String], icon: Icon)] = [
        (["睡觉", "上床", "早睡", "sleep", "bedtime", "go to bed"], Icon(emoji: "😴", systemImageName: "moon.zzz.fill")),
        (["起床", "早起", "wake up", "get up"], Icon(emoji: "🌅", systemImageName: "sunrise.fill")),
        (["刷牙", "brush teeth", "toothbrush"], Icon(emoji: "🪥", systemImageName: "sparkles")),
        (["洗脸", "洗手", "洗澡", "wash", "bath", "shower"], Icon(emoji: "🧼", systemImageName: "drop.fill")),
        (["穿衣", "衣服", "get dressed", "clothes"], Icon(emoji: "👕", systemImageName: "tshirt.fill")),
        (["书包", "backpack", "school bag"], Icon(emoji: "🎒", systemImageName: "backpack.fill")),
        (["读", "阅读", "book", "read"], Icon(emoji: "📖", systemImageName: "book.closed.fill")),
        (["视频", "看片", "video"], Icon(emoji: "📺", systemImageName: "play.rectangle.fill")),
        (["作业", "写字", "练字", "homework", "writing", "handwriting"], Icon(emoji: "✏️", systemImageName: "pencil.line")),
        (["口算", "数学", "算术", "math", "arithmetic", "counting"], Icon(emoji: "🔢", systemImageName: "plus.forwardslash.minus")),
        (["单词", "英语", "english"], Icon(emoji: "🔤", systemImageName: "character.book.closed.fill")),
        (["画", "美术", "涂色", "draw", "paint", "coloring"], Icon(emoji: "🖍️", systemImageName: "paintbrush.pointed.fill")),
        (["手工", "折纸", "做一个", "craft", "origami", "make a"], Icon(emoji: "✂️", systemImageName: "scissors")),
        (["琴", "音乐", "唱歌", "乐器", "music", "sing", "instrument"], Icon(emoji: "🎹", systemImageName: "music.note")),
        (["舞", "跳舞", "dance"], Icon(emoji: "💃", systemImageName: "figure.dance")),
        (["跑", "运动", "锻炼", "跳绳", "球", "run", "exercise", "sport", "jump rope"], Icon(emoji: "⚽", systemImageName: "figure.run")),
        (["垃圾", "trash", "garbage"], Icon(emoji: "🗑️", systemImageName: "trash.fill")),
        (["碗", "筷", "餐桌", "吃饭", "dishes", "table", "meal"], Icon(emoji: "🍽️", systemImageName: "fork.knife")),
        (["房间", "整理", "收拾", "书桌", "tidy", "clean", "organize", "desk", "room"], Icon(emoji: "🧹", systemImageName: "sparkles")),
        (["宠物", "小狗", "小猫", "喂", "浇水", "植物", "pet", "dog", "cat", "feed", "water the plant"], Icon(emoji: "🐶", systemImageName: "pawprint.fill")),
        (["电话", "爷爷", "奶奶", "外公", "外婆"], Icon(emoji: "📞", systemImageName: "phone.fill")),
        (["弟弟", "妹妹", "陪"], Icon(emoji: "🧸", systemImageName: "teddybear.fill")),
        (["钱", "零花", "储蓄", "记账", "义卖"], Icon(emoji: "🪙", systemImageName: "banknote.fill")),
        (["修理", "灯泡", "工具"], Icon(emoji: "🔧", systemImageName: "wrench.and.screwdriver.fill")),
        (["做饭", "料理", "厨"], Icon(emoji: "🍳", systemImageName: "fork.knife")),
        (["缝", "扣子"], Icon(emoji: "🧵", systemImageName: "scissors")),
        (["鞋带"], Icon(emoji: "👟", systemImageName: "figure.walk")),
        (["实验", "科学"], Icon(emoji: "🔬", systemImageName: "testtube.2")),
        (["恐龙"], Icon(emoji: "🦕", systemImageName: "pawprint.fill")),
        (["太空", "星球", "宇宙"], Icon(emoji: "🚀", systemImageName: "rocket.fill")),
        (["日记"], Icon(emoji: "📔", systemImageName: "book.pages.fill")),
        (["考试", "测验"], Icon(emoji: "🧠", systemImageName: "brain.head.profile")),
    ]

    static let keywordEmoji: [(keywords: [String], emoji: String)] = keywordIcons.map {
        ($0.keywords, $0.icon.emoji)
    }

    /// 类别兜底表情。
    static func categoryEmoji(_ category: TaskCategory) -> String {
        categoryIcon(category).emoji
    }

    static func categoryIcon(_ category: TaskCategory) -> Icon {
        switch category {
        case .home: return Icon(emoji: "🏠", systemImageName: "house.fill")
        case .learning: return Icon(emoji: "📚", systemImageName: "book.closed.fill")
        case .health: return Icon(emoji: "🏃", systemImageName: "figure.run")
        case .creative: return Icon(emoji: "🎨", systemImageName: "paintpalette.fill")
        case .family: return Icon(emoji: "❤️", systemImageName: "heart.fill")
        case .school: return Icon(emoji: "🏫", systemImageName: "building.columns.fill")
        }
    }

    /// 孩子端图标：先按当前界面的显示标题与原文匹配，说明只作兜底，再按任务类型与类别兜底。
    /// `displayTitle` 让云端任务或翻译后的标题仍能拿到与孩子实际看到内容一致的图标。
    static func icon(for task: TaskTemplate, displayTitle: String? = nil) -> Icon {
        if task.reading != nil { return Icon(emoji: "📖", systemImageName: "book.closed.fill") }
        if task.video != nil {
            let symbol = isYouTubeVideo(task) ? "play.rectangle.fill" : "play.square.fill"
            return Icon(emoji: "▶", systemImageName: symbol)
        }
        let titleHaystack = [displayTitle, task.title]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if let match = keywordIcons.first(where: { entry in
            entry.keywords.contains(where: { titleHaystack.contains($0.lowercased()) })
        }) {
            return match.icon
        }

        let instructions = task.instructions.lowercased()
        if let match = keywordIcons.first(where: { entry in
            entry.keywords.contains(where: { instructions.contains($0.lowercased()) })
        }) {
            return match.icon
        }
        return categoryIcon(task.category)
    }

    /// 旧调用保持表情语义，避免影响普通孩子端、钱包等既有界面。
    static func emoji(for task: TaskTemplate) -> String {
        icon(for: task).emoji
    }

    static func isYouTubeVideo(_ task: TaskTemplate) -> Bool {
        guard let video = task.video else { return false }
        let source = "\(video.platformLabel) \(video.urlString)".lowercased()
        return source.contains("youtube") || source.contains("youtu.be")
    }
}
