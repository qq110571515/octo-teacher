import Foundation
import Observation

/// 跨模块“孩子本地成长大脑”的基础事件模型。
///
/// 边界：
/// - 事件只落本机文件，带版本号、原子写入，不参与云同步。
/// - 事件摘要在写入时剪裁，不保存原始长聊天、原图、语音或隐私路径。
/// - 云端只允许拿 `digest(for:)` 生成的脱敏摘要，不允许拿事件全量。
enum GrowthMemoryEventKind: String, Codable, CaseIterable {
    case aiChatSummary = "ai_chat_summary"
    case readingProgress = "reading_progress"
    case videoLearning = "video_learning"
    case quizResult = "quiz_result"
    case literacySignal = "literacy_signal"
    case taskCompletion = "task_completion"
    case rewardPreference = "reward_preference"
    case wishPreference = "wish_preference"
    case companionProfile = "companion_profile"
    case schoolDynamic = "school_dynamic"

    var label: String {
        switch self {
        case .aiChatSummary: return "AI 聊天摘要"
        case .readingProgress: return "阅读进展"
        case .videoLearning: return "视频学习"
        case .quizResult: return "测验结果"
        case .literacySignal: return "识字信号"
        case .taskCompletion: return "任务完成"
        case .rewardPreference: return "奖励偏好"
        case .wishPreference: return "愿望偏好"
        case .companionProfile: return "小伙伴人格"
        case .schoolDynamic: return "学校动态"
        }
    }
}

struct GrowthMemoryEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var childId: UUID
    var kind: GrowthMemoryEventKind
    var summary: String
    var tags: [String]
    /// 可选的归一化分数（如测验正确率 0...1）。
    var score: Double?
    var occurredAt: Date

    init(
        id: UUID = UUID(),
        childId: UUID,
        kind: GrowthMemoryEventKind,
        summary: String,
        tags: [String] = [],
        score: Double? = nil,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.childId = childId
        self.kind = kind
        self.summary = summary
        self.tags = tags
        self.score = score
        self.occurredAt = occurredAt
    }
}

/// 把各模块已有模型翻译成成长事件的工具；先覆盖低风险的纯数据入口。
enum GrowthMemoryEventFactory {
    static func aiChatSummary(childId: UUID, summary: String, occurredAt: Date = Date()) -> GrowthMemoryEvent {
        GrowthMemoryEvent(childId: childId, kind: .aiChatSummary, summary: summary, occurredAt: occurredAt)
    }

    static func companionProfile(
        childId: UUID,
        companionName: String,
        personalityLabel: String,
        occurredAt: Date = Date()
    ) -> GrowthMemoryEvent {
        GrowthMemoryEvent(
            childId: childId,
            kind: .companionProfile,
            summary: "小伙伴现在叫\(companionName)，风格：\(personalityLabel)",
            tags: [personalityLabel],
            occurredAt: occurredAt
        )
    }

    static func readingProgress(
        childId: UUID,
        bookTitle: String,
        minutes: Int,
        occurredAt: Date = Date()
    ) -> GrowthMemoryEvent {
        GrowthMemoryEvent(
            childId: childId,
            kind: .readingProgress,
            summary: "读了《\(bookTitle)》约 \(max(minutes, 0)) 分钟",
            occurredAt: occurredAt
        )
    }

    static func videoLearning(
        childId: UUID,
        title: String,
        minutes: Int,
        occurredAt: Date = Date()
    ) -> GrowthMemoryEvent {
        GrowthMemoryEvent(
            childId: childId,
            kind: .videoLearning,
            summary: "看学习视频「\(title)」约 \(max(minutes, 0)) 分钟",
            occurredAt: occurredAt
        )
    }

    static func quizResult(
        childId: UUID,
        subjectLabel: String,
        correctCount: Int,
        totalCount: Int,
        occurredAt: Date = Date()
    ) -> GrowthMemoryEvent {
        let safeTotal = max(totalCount, 1)
        return GrowthMemoryEvent(
            childId: childId,
            kind: .quizResult,
            summary: "\(subjectLabel)测验答对 \(correctCount)/\(safeTotal)",
            tags: [subjectLabel],
            score: Double(min(max(correctCount, 0), safeTotal)) / Double(safeTotal),
            occurredAt: occurredAt
        )
    }

    static func literacySignal(childId: UUID, note: String, occurredAt: Date = Date()) -> GrowthMemoryEvent {
        GrowthMemoryEvent(childId: childId, kind: .literacySignal, summary: note, occurredAt: occurredAt)
    }

    static func taskCompletion(childId: UUID, taskTitle: String, occurredAt: Date = Date()) -> GrowthMemoryEvent {
        GrowthMemoryEvent(
            childId: childId,
            kind: .taskCompletion,
            summary: "完成任务「\(taskTitle)」",
            occurredAt: occurredAt
        )
    }

    static func schoolDynamic(
        childId: UUID,
        category: SchoolDynamicCategory,
        title: String,
        schoolName: String?,
        occurredAt: Date = Date()
    ) -> GrowthMemoryEvent {
        let school = schoolName.map { "\($0)：" } ?? ""
        return GrowthMemoryEvent(
            childId: childId,
            kind: .schoolDynamic,
            summary: "\(school)\(title)",
            tags: [category.rawValue],
            occurredAt: occurredAt
        )
    }

    static func rewardPreference(childId: UUID, preference: String, occurredAt: Date = Date()) -> GrowthMemoryEvent {
        GrowthMemoryEvent(childId: childId, kind: .rewardPreference, summary: preference, occurredAt: occurredAt)
    }

    static func wishPreference(childId: UUID, wish: String, occurredAt: Date = Date()) -> GrowthMemoryEvent {
        GrowthMemoryEvent(childId: childId, kind: .wishPreference, summary: wish, occurredAt: occurredAt)
    }
}

/// 云端可见的脱敏成长画像摘要：只有计数、兴趣提示和剪裁后的近况，不含原始记录。
struct GrowthMemoryDigest: Codable, Equatable {
    var childId: UUID
    var generatedAt: Date
    var totalEventCount: Int
    var kindCounts: [String: Int]
    var recentHighlights: [String]
    var interestHints: [String]

    static func empty(childId: UUID, now: Date = Date()) -> GrowthMemoryDigest {
        GrowthMemoryDigest(
            childId: childId,
            generatedAt: now,
            totalEventCount: 0,
            kindCounts: [:],
            recentHighlights: [],
            interestHints: []
        )
    }

    var promptSummary: String {
        guard totalEventCount > 0 else { return "" }
        var lines: [String] = ["growth_event_count=\(totalEventCount)"]
        let counts = kindCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        if !counts.isEmpty { lines.append("growth_kinds: \(counts)") }
        if !interestHints.isEmpty { lines.append("growth_interests=\(interestHints.joined(separator: "、"))") }
        if !recentHighlights.isEmpty {
            lines.append("growth_recent:")
            lines.append(contentsOf: recentHighlights.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }
}

protocol GrowthMemoryPersisting {
    func load() -> [GrowthMemoryEvent]
    func save(_ events: [GrowthMemoryEvent])
}

struct FileGrowthMemoryPersistence: GrowthMemoryPersisting {
    static let currentVersion = 1

    private struct MemoryFile: Codable {
        var version: Int
        var events: [GrowthMemoryEvent]
    }

    var fileURL: URL

    static func documents(fileName: String = "octoteacher-growth-memory.json") -> FileGrowthMemoryPersistence {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileGrowthMemoryPersistence(fileURL: directory.appendingPathComponent(fileName))
    }

    init(directory: URL, fileName: String = "octoteacher-growth-memory.json") {
        fileURL = directory.appendingPathComponent(fileName)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> [GrowthMemoryEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(MemoryFile.self, from: data),
              file.version <= Self.currentVersion else {
            return []
        }
        return file.events
    }

    func save(_ events: [GrowthMemoryEvent]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(
            MemoryFile(version: Self.currentVersion, events: events)
        ) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        #if os(iOS)
        let options: Data.WritingOptions = [.atomic, .completeFileProtection]
        #else
        let options: Data.WritingOptions = [.atomic]
        #endif
        try? data.write(to: fileURL, options: options)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = fileURL
        try? protectedURL.setResourceValues(values)
    }
}

@Observable
final class GrowthMemoryStore {
    static let maxEventsPerChild = 400
    static let maxSummaryLength = 80
    static let maxTagLength = 20
    static let maxDigestHighlights = 8
    static let maxHighlightLength = 60
    static let maxInterestHints = 6

    private(set) var events: [GrowthMemoryEvent]

    @ObservationIgnored
    private let persistence: (any GrowthMemoryPersisting)?

    init(persistence: (any GrowthMemoryPersisting)? = nil) {
        self.persistence = persistence
        self.events = persistence?.load() ?? []
    }

    func record(_ event: GrowthMemoryEvent) {
        var sanitized = event
        sanitized.summary = String(
            event.summary
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Self.maxSummaryLength)
        )
        guard !sanitized.summary.isEmpty else { return }
        sanitized.tags = event.tags
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxTagLength)) }
            .filter { !$0.isEmpty && !MobileSyncPayloadGuard.isUnsafe($0) }

        events.append(sanitized)
        let childEvents = events.filter { $0.childId == event.childId }
        if childEvents.count > Self.maxEventsPerChild {
            let overflow = childEvents.count - Self.maxEventsPerChild
            let dropIds = Set(
                childEvents
                    .sorted { $0.occurredAt < $1.occurredAt }
                    .prefix(overflow)
                    .map(\.id)
            )
            events.removeAll { dropIds.contains($0.id) }
        }
        persistence?.save(events)
    }

    func events(for childId: UUID) -> [GrowthMemoryEvent] {
        events
            .filter { $0.childId == childId }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    func clear(for childId: UUID) {
        events.removeAll { $0.childId == childId }
        persistence?.save(events)
    }

    /// 生成脱敏画像摘要：只保留计数、兴趣提示和剪裁后的近况。
    /// 命中安全守卫（密钥、路径、局域网地址等）的事件不会进入摘要。
    func digest(for childId: UUID, now: Date = Date()) -> GrowthMemoryDigest {
        let childEvents = events(for: childId)
            .filter { !MobileSyncPayloadGuard.isUnsafe($0.summary) }
        guard !childEvents.isEmpty else {
            return .empty(childId: childId, now: now)
        }

        var kindCounts: [String: Int] = [:]
        for event in childEvents {
            kindCounts[event.kind.rawValue, default: 0] += 1
        }

        let highlights = childEvents
            .suffix(Self.maxDigestHighlights)
            .map { event in
                "\(event.kind.label)：\(String(event.summary.prefix(Self.maxHighlightLength)))"
            }

        var interestHints: [String] = []
        for event in childEvents.reversed()
        where event.kind == .rewardPreference || event.kind == .wishPreference || !event.tags.isEmpty {
            let candidates = event.tags.isEmpty ? [event.summary] : event.tags
            for candidate in candidates {
                let hint = String(candidate.prefix(Self.maxTagLength))
                if !hint.isEmpty && !interestHints.contains(hint) {
                    interestHints.append(hint)
                }
            }
            if interestHints.count >= Self.maxInterestHints { break }
        }

        return GrowthMemoryDigest(
            childId: childId,
            generatedAt: now,
            totalEventCount: childEvents.count,
            kindCounts: kindCounts,
            recentHighlights: highlights,
            interestHints: Array(interestHints.prefix(Self.maxInterestHints))
        )
    }
}
