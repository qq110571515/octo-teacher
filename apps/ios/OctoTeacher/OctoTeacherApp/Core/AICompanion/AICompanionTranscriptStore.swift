import Foundation
import Observation

/// 孩子端 AI 小伙伴聊天窗口的本机持久化记录。
///
/// 边界：
/// - 只落本机文件，不进入家长摘要、不进入云端请求。
/// - 不保存原图，只保存小尺寸缩略图数据；语音只保存转写后的文字。
/// - 按 childId 分档，滚动上限 500 条 / 90 天，UI 恢复最近 100 条。
struct AICompanionTranscriptEntry: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case child
        case companion
    }

    enum Origin: String, Codable {
        case childText = "child_text"
        case childVoice = "child_voice"
        case companionLocal = "companion_local"
        case companionCloud = "companion_cloud"
        case companionFallback = "companion_fallback"
    }

    var id: UUID
    var role: Role
    var text: String
    var timestamp: Date
    var imageThumbnailData: [Data]
    var origin: Origin
    var fallbackReason: String?

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        timestamp: Date = Date(),
        imageThumbnailData: [Data] = [],
        origin: Origin,
        fallbackReason: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.imageThumbnailData = imageThumbnailData
        self.origin = origin
        self.fallbackReason = fallbackReason
    }
}

struct AICompanionChildTranscript: Codable, Equatable {
    var childId: UUID
    var entries: [AICompanionTranscriptEntry]
}

protocol AICompanionTranscriptPersisting {
    func load() -> [AICompanionChildTranscript]
    func save(_ transcripts: [AICompanionChildTranscript])
}

struct FileAICompanionTranscriptPersistence: AICompanionTranscriptPersisting {
    /// 文件格式版本；未来结构变化时用于迁移。
    static let currentVersion = 1

    private struct TranscriptFile: Codable {
        var version: Int
        var transcripts: [AICompanionChildTranscript]
    }

    var fileURL: URL

    static func documents(fileName: String = "octoteacher-ai-companion-transcript.json") -> FileAICompanionTranscriptPersistence {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileAICompanionTranscriptPersistence(fileURL: directory.appendingPathComponent(fileName))
    }

    init(directory: URL, fileName: String = "octoteacher-ai-companion-transcript.json") {
        fileURL = directory.appendingPathComponent(fileName)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> [AICompanionChildTranscript] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(TranscriptFile.self, from: data),
              file.version <= Self.currentVersion else {
            return []
        }
        return file.transcripts
    }

    func save(_ transcripts: [AICompanionChildTranscript]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(
            TranscriptFile(version: Self.currentVersion, transcripts: transcripts)
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
final class AICompanionTranscriptStore {
    static let maxEntriesPerChild = 500
    static let maxEntryAge: TimeInterval = 90 * 24 * 60 * 60
    static let defaultRestoreLimit = 100
    static let maxCloudContextLines = 4
    static let maxCloudContextCharacters = 60

    private(set) var transcripts: [AICompanionChildTranscript]

    @ObservationIgnored
    private let persistence: (any AICompanionTranscriptPersisting)?

    init(persistence: (any AICompanionTranscriptPersisting)? = nil) {
        self.persistence = persistence
        self.transcripts = persistence?.load() ?? []
    }

    func append(_ entry: AICompanionTranscriptEntry, childId: UUID, now: Date = Date()) {
        var transcript = transcripts.first { $0.childId == childId }
            ?? AICompanionChildTranscript(childId: childId, entries: [])
        transcript.entries.append(entry)
        transcript.entries = pruned(transcript.entries, now: now)
        transcripts.removeAll { $0.childId == childId }
        transcripts.append(transcript)
        persistence?.save(transcripts)
    }

    func recentEntries(
        for childId: UUID,
        limit: Int = AICompanionTranscriptStore.defaultRestoreLimit,
        now: Date = Date()
    ) -> [AICompanionTranscriptEntry] {
        let entries = pruned(
            transcripts.first { $0.childId == childId }?.entries ?? [],
            now: now
        )
        return Array(entries.suffix(limit))
    }

    /// 给云端请求用的最近上下文：只取最近几条、剪裁长度、过滤不安全内容。
    /// 绝不返回完整 transcript，也不包含图片数据。
    func recentCloudContextLines(
        for childId: UUID,
        limit: Int = AICompanionTranscriptStore.maxCloudContextLines,
        now: Date = Date()
    ) -> [String] {
        recentEntries(for: childId, limit: limit * 2, now: now)
            .compactMap { entry -> String? in
                let clipped = String(
                    entry.text
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .prefix(Self.maxCloudContextCharacters)
                )
                guard !clipped.isEmpty, !MobileSyncPayloadGuard.isUnsafe(clipped) else { return nil }
                return "\(entry.role.rawValue): \(clipped)"
            }
            .suffix(limit)
            .map { $0 }
    }

    func clear(for childId: UUID) {
        transcripts.removeAll { $0.childId == childId }
        persistence?.save(transcripts)
    }

    private func pruned(_ entries: [AICompanionTranscriptEntry], now: Date) -> [AICompanionTranscriptEntry] {
        let cutoff = now.addingTimeInterval(-Self.maxEntryAge)
        let fresh = entries.filter { $0.timestamp >= cutoff }
        return Array(fresh.suffix(Self.maxEntriesPerChild))
    }
}
