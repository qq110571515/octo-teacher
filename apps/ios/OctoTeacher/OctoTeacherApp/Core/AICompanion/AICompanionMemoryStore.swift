import Foundation
import Observation

struct AICompanionMemoryDigest: Identifiable, Codable, Equatable {
    var childId: UUID
    var updatedAt: Date
    var companionName: String
    var companionAvatarDescription: String
    var personalityLabel: String
    var conversationCount: Int
    var interests: [String]
    var preferences: [String]
    var learningNotes: [String]
    var emotionalNotes: [String]
    var homeworkGuidanceNotes: [String]
    var latestSummary: String

    var id: UUID { childId }
    var storesRawTranscript: Bool { false }

    static func empty(
        childId: UUID,
        companionName: String,
        companionAvatarDescription: String,
        personalityLabel: String,
        now: Date = Date()
    ) -> AICompanionMemoryDigest {
        AICompanionMemoryDigest(
            childId: childId,
            updatedAt: now,
            companionName: companionName,
            companionAvatarDescription: companionAvatarDescription,
            personalityLabel: personalityLabel,
            conversationCount: 0,
            interests: [],
            preferences: [],
            learningNotes: [],
            emotionalNotes: [],
            homeworkGuidanceNotes: [],
            latestSummary: ""
        )
    }

    var promptSummary: String {
        var lines: [String] = [
            "companion_name=\(companionName)",
            "avatar=\(companionAvatarDescription)",
            "personality=\(personalityLabel)",
            "conversation_count=\(conversationCount)"
        ]
        if !interests.isEmpty { lines.append("interests=\(interests.joined(separator: "、"))") }
        if !preferences.isEmpty { lines.append("preferences=\(preferences.joined(separator: "、"))") }
        if !learningNotes.isEmpty { lines.append("learning_notes=\(learningNotes.joined(separator: "、"))") }
        if !emotionalNotes.isEmpty { lines.append("emotional_notes=\(emotionalNotes.joined(separator: "、"))") }
        if !homeworkGuidanceNotes.isEmpty { lines.append("homework_guidance=\(homeworkGuidanceNotes.joined(separator: "、"))") }
        if !latestSummary.isEmpty { lines.append("latest_summary=\(latestSummary)") }
        return lines.joined(separator: "\n")
    }
}

struct AICompanionMemoryUpdate: Codable, Equatable {
    var interests: [String]
    var preferences: [String]
    var learningNotes: [String]
    var emotionalNotes: [String]
    var homeworkGuidanceNotes: [String]
    var summary: String

    init(
        interests: [String] = [],
        preferences: [String] = [],
        learningNotes: [String] = [],
        emotionalNotes: [String] = [],
        homeworkGuidanceNotes: [String] = [],
        summary: String = ""
    ) {
        self.interests = interests
        self.preferences = preferences
        self.learningNotes = learningNotes
        self.emotionalNotes = emotionalNotes
        self.homeworkGuidanceNotes = homeworkGuidanceNotes
        self.summary = summary
    }

    static func local(intent: AICompanionIntent, childText: String) -> AICompanionMemoryUpdate {
        let clipped = String(childText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        switch intent {
        case .homeworkStuck, .wantsDirectAnswer:
            return AICompanionMemoryUpdate(
                learningNotes: ["遇到作业卡住时需要先读题、圈条件、说出第一步"],
                homeworkGuidanceNotes: ["只给提示和检查方向，不给最终答案"],
                summary: clipped.isEmpty ? "孩子请求作业引导" : "孩子请求作业引导：\(clipped)"
            )
        case .emotionalSupport:
            return AICompanionMemoryUpdate(
                emotionalNotes: ["需要先接住情绪，再整理事实和下一步"],
                summary: clipped.isEmpty ? "孩子请求情绪陪伴" : "孩子请求情绪陪伴：\(clipped)"
            )
        case .offTopic:
            return AICompanionMemoryUpdate(
                interests: [clipped].filter { !$0.isEmpty },
                summary: clipped.isEmpty ? "孩子想自由聊天" : "孩子想聊：\(clipped)"
            )
        case .findNextStep:
            return AICompanionMemoryUpdate(summary: "孩子请求下一步建议")
        case .askTrustedAdult, .highRisk:
            return AICompanionMemoryUpdate(
                emotionalNotes: ["出现需要可信大人介入的信号"],
                summary: "本地安全规则建议可信大人介入"
            )
        case .unclear:
            return AICompanionMemoryUpdate(summary: clipped.isEmpty ? "孩子发起自由聊天" : "孩子自由聊天：\(clipped)")
        }
    }
}

protocol AICompanionMemoryPersisting {
    func load() -> [AICompanionMemoryDigest]
    func save(_ digests: [AICompanionMemoryDigest])
}

struct FileAICompanionMemoryPersistence: AICompanionMemoryPersisting {
    var fileURL: URL

    static func documents(fileName: String = "octoteacher-ai-companion-memory.json") -> FileAICompanionMemoryPersistence {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileAICompanionMemoryPersistence(fileURL: directory.appendingPathComponent(fileName))
    }

    init(directory: URL, fileName: String = "octoteacher-ai-companion-memory.json") {
        fileURL = directory.appendingPathComponent(fileName)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> [AICompanionMemoryDigest] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AICompanionMemoryDigest].self, from: data)) ?? []
    }

    func save(_ digests: [AICompanionMemoryDigest]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(digests) else { return }
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
final class AICompanionMemoryStore {
    static let maxItemsPerBucket = 8

    private(set) var digests: [AICompanionMemoryDigest]

    @ObservationIgnored
    private let persistence: (any AICompanionMemoryPersisting)?

    init(persistence: (any AICompanionMemoryPersisting)? = nil) {
        self.persistence = persistence
        self.digests = persistence?.load().sorted { $0.updatedAt > $1.updatedAt } ?? []
    }

    func digest(
        for childId: UUID,
        companionName: String,
        avatarDescription: String,
        personalityLabel: String,
        now: Date = Date()
    ) -> AICompanionMemoryDigest {
        if var existing = digests.first(where: { $0.childId == childId }) {
            existing.companionName = companionName
            existing.companionAvatarDescription = avatarDescription
            existing.personalityLabel = personalityLabel
            return existing
        }
        return .empty(
            childId: childId,
            companionName: companionName,
            companionAvatarDescription: avatarDescription,
            personalityLabel: personalityLabel,
            now: now
        )
    }

    func apply(
        _ update: AICompanionMemoryUpdate,
        childId: UUID,
        companionName: String,
        avatarDescription: String,
        personalityLabel: String,
        now: Date = Date()
    ) {
        var digest = digest(
            for: childId,
            companionName: companionName,
            avatarDescription: avatarDescription,
            personalityLabel: personalityLabel,
            now: now
        )
        digest.updatedAt = now
        digest.conversationCount += 1
        digest.interests = merged(digest.interests, update.interests)
        digest.preferences = merged(digest.preferences, update.preferences)
        digest.learningNotes = merged(digest.learningNotes, update.learningNotes)
        digest.emotionalNotes = merged(digest.emotionalNotes, update.emotionalNotes)
        digest.homeworkGuidanceNotes = merged(digest.homeworkGuidanceNotes, update.homeworkGuidanceNotes)
        let summary = update.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            digest.latestSummary = String(summary.prefix(120))
        }

        digests.removeAll { $0.childId == childId }
        digests.insert(digest, at: 0)
        digests.sort { $0.updatedAt > $1.updatedAt }
        persistence?.save(digests)
    }

    func clear(for childId: UUID) {
        digests.removeAll { $0.childId == childId }
        persistence?.save(digests)
    }

    private func merged(_ current: [String], _ incoming: [String]) -> [String] {
        var result = current
        for raw in incoming {
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty else { continue }
            if !result.contains(where: { $0.localizedCaseInsensitiveCompare(item) == .orderedSame }) {
                result.insert(String(item.prefix(40)), at: 0)
            }
        }
        return Array(result.prefix(Self.maxItemsPerBucket))
    }
}
