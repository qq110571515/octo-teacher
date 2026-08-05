import Foundation
import Observation

struct ParentAICompanionCoachEntry: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case parent
        case coach
    }

    enum Origin: String, Codable {
        case parentText = "parent_text"
        case coachCloud = "coach_cloud"
        case coachLocal = "coach_local"
        case coachFallback = "coach_fallback"
    }

    var id: UUID
    var role: Role
    var text: String
    var timestamp: Date
    var origin: Origin

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        timestamp: Date = Date(),
        origin: Origin
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.origin = origin
    }
}

struct ParentAICompanionCoachMemoryDigest: Codable, Equatable {
    var childId: UUID
    var updatedAt: Date
    var conversationCount: Int
    var parentGoals: [String]
    var usefulStrategies: [String]
    var boundaryNotes: [String]
    var latestSummary: String

    static func empty(childId: UUID, now: Date = Date()) -> ParentAICompanionCoachMemoryDigest {
        ParentAICompanionCoachMemoryDigest(
            childId: childId,
            updatedAt: now,
            conversationCount: 0,
            parentGoals: [],
            usefulStrategies: [],
            boundaryNotes: [],
            latestSummary: ""
        )
    }

    var promptSummary: String {
        var lines = ["parent_coach_conversation_count=\(conversationCount)"]
        if !parentGoals.isEmpty { lines.append("parent_goals=\(parentGoals.joined(separator: "、"))") }
        if !usefulStrategies.isEmpty { lines.append("useful_strategies=\(usefulStrategies.joined(separator: "、"))") }
        if !boundaryNotes.isEmpty { lines.append("boundary_notes=\(boundaryNotes.joined(separator: "、"))") }
        if !latestSummary.isEmpty { lines.append("latest_summary=\(latestSummary)") }
        return lines.joined(separator: "\n")
    }
}

struct ParentAICompanionCoachMemoryUpdate: Codable, Equatable {
    var parentGoals: [String]
    var usefulStrategies: [String]
    var boundaryNotes: [String]
    var summary: String

    init(
        parentGoals: [String] = [],
        usefulStrategies: [String] = [],
        boundaryNotes: [String] = [],
        summary: String = ""
    ) {
        self.parentGoals = parentGoals
        self.usefulStrategies = usefulStrategies
        self.boundaryNotes = boundaryNotes
        self.summary = summary
    }

    static func local(parentText: String) -> ParentAICompanionCoachMemoryUpdate {
        let clipped = String(parentText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(44))
        var goals: [String] = []
        if containsAny(parentText, ["睡觉", "晚睡", "睡前"]) {
            goals.append("改善睡前节奏")
        }
        if containsAny(parentText, ["手机", "游戏", "短视频", "屏幕"]) {
            goals.append("减少无效屏幕时间")
        }
        if containsAny(parentText, ["阅读", "书", "识字"]) {
            goals.append("建立阅读习惯")
        }
        if containsAny(parentText, ["家务", "收拾", "整理", "独立"]) {
            goals.append("提升个人独立性和家务参与")
        }
        return ParentAICompanionCoachMemoryUpdate(
            parentGoals: goals,
            usefulStrategies: ["先共情，再给一个可执行小步骤，最后约定复盘时间"],
            boundaryNotes: ["不替孩子完成任务，不用羞辱或威胁推动执行"],
            summary: clipped.isEmpty ? "家长请求育儿策略建议" : "家长请求育儿策略：\(clipped)"
        )
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }
}

struct ParentAICompanionCoachThread: Codable, Equatable {
    var childId: UUID
    var entries: [ParentAICompanionCoachEntry]
    var memory: ParentAICompanionCoachMemoryDigest
}

protocol ParentAICompanionCoachPersisting {
    func load() -> [ParentAICompanionCoachThread]
    func save(_ threads: [ParentAICompanionCoachThread])
}

struct FileParentAICompanionCoachPersistence: ParentAICompanionCoachPersisting {
    static let currentVersion = 1

    private struct CoachFile: Codable {
        var version: Int
        var threads: [ParentAICompanionCoachThread]
    }

    var fileURL: URL

    static func documents(fileName: String = "octoteacher-parent-ai-companion-coach.json") -> FileParentAICompanionCoachPersistence {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileParentAICompanionCoachPersistence(fileURL: directory.appendingPathComponent(fileName))
    }

    init(directory: URL, fileName: String = "octoteacher-parent-ai-companion-coach.json") {
        fileURL = directory.appendingPathComponent(fileName)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> [ParentAICompanionCoachThread] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(CoachFile.self, from: data),
              file.version <= Self.currentVersion else {
            return []
        }
        return file.threads
    }

    func save(_ threads: [ParentAICompanionCoachThread]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(CoachFile(version: Self.currentVersion, threads: threads)) else { return }
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
final class ParentAICompanionCoachStore {
    static let maxEntriesPerChild = 400
    static let defaultRestoreLimit = 100
    static let maxItemsPerBucket = 8
    static let maxCloudContextLines = 4
    static let maxCloudContextCharacters = 80

    private(set) var threads: [ParentAICompanionCoachThread]

    @ObservationIgnored
    private let persistence: (any ParentAICompanionCoachPersisting)?

    init(persistence: (any ParentAICompanionCoachPersisting)? = nil) {
        self.persistence = persistence
        self.threads = persistence?.load() ?? []
    }

    func append(_ entry: ParentAICompanionCoachEntry, childId: UUID) {
        var thread = thread(for: childId)
        thread.entries.append(entry)
        thread.entries = Array(thread.entries.suffix(Self.maxEntriesPerChild))
        upsert(thread)
    }

    func recentEntries(
        for childId: UUID,
        limit: Int = ParentAICompanionCoachStore.defaultRestoreLimit
    ) -> [ParentAICompanionCoachEntry] {
        Array(thread(for: childId).entries.suffix(limit))
    }

    func recentCloudContextLines(
        for childId: UUID,
        limit: Int = ParentAICompanionCoachStore.maxCloudContextLines
    ) -> [String] {
        recentEntries(for: childId, limit: limit * 2)
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

    func memory(for childId: UUID, now: Date = Date()) -> ParentAICompanionCoachMemoryDigest {
        thread(for: childId, now: now).memory
    }

    func apply(_ update: ParentAICompanionCoachMemoryUpdate, childId: UUID, now: Date = Date()) {
        var thread = thread(for: childId, now: now)
        var memory = thread.memory
        memory.updatedAt = now
        memory.conversationCount += 1
        memory.parentGoals = merged(memory.parentGoals, update.parentGoals)
        memory.usefulStrategies = merged(memory.usefulStrategies, update.usefulStrategies)
        memory.boundaryNotes = merged(memory.boundaryNotes, update.boundaryNotes)
        let summary = update.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            memory.latestSummary = String(summary.prefix(140))
        }
        thread.memory = memory
        upsert(thread)
    }

    func clear(for childId: UUID) {
        threads.removeAll { $0.childId == childId }
        persistence?.save(threads)
    }

    private func thread(for childId: UUID, now: Date = Date()) -> ParentAICompanionCoachThread {
        if let existing = threads.first(where: { $0.childId == childId }) {
            return existing
        }
        return ParentAICompanionCoachThread(
            childId: childId,
            entries: [],
            memory: .empty(childId: childId, now: now)
        )
    }

    private func upsert(_ thread: ParentAICompanionCoachThread) {
        threads.removeAll { $0.childId == thread.childId }
        threads.append(thread)
        persistence?.save(threads)
    }

    private func merged(_ current: [String], _ incoming: [String]) -> [String] {
        var result = current
        for raw in incoming {
            let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty, !MobileSyncPayloadGuard.isUnsafe(item) else { continue }
            if !result.contains(where: { $0.localizedCaseInsensitiveCompare(item) == .orderedSame }) {
                result.insert(String(item.prefix(52)), at: 0)
            }
        }
        return Array(result.prefix(Self.maxItemsPerBucket))
    }
}

struct ParentAICompanionCoachRequest: Equatable {
    var childName: String
    var childAge: Int
    var latestText: String
    var childMemory: AICompanionMemoryDigest
    var growthProfileSummary: String
    var childRecentContextLines: [String]
    var parentMemory: ParentAICompanionCoachMemoryDigest
    var parentRecentContextLines: [String]
    var activeTasksSummary: String
    var rewardSummary: String
    var attachmentSummaries: [String] = []
    var language: AppInterfaceLanguage = .chinese

    var isProviderRequestAllowed: Bool {
        let trimmed = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !MobileSyncPayloadGuard.isUnsafe(
            [trimmed, growthProfileSummary, activeTasksSummary, rewardSummary]
                + attachmentSummaries
                + childRecentContextLines
                + parentRecentContextLines
        )
    }
}

struct ParentAICompanionCoachTurn: Equatable {
    var reply: String
    var memoryUpdate: ParentAICompanionCoachMemoryUpdate
    var providerUsed: Bool
}

enum ParentAICompanionCoachError: Error, Equatable {
    case blockedBySafetyGate
    case badResponse
    case unsafeResponse
}

struct ParentAICompanionCoachService {
    func systemPrompt(_ request: ParentAICompanionCoachRequest) -> String {
        let responseLanguage = request.language == .english
            ? "natural parent-facing English"
            : "natural, practical, parent-facing zh-CN"
        return """
        You are OctoTeacher's parent AI coach. Reply in \(responseLanguage). Do not output JSON, Markdown tables, raw key=value fields, or internal memory digests.
        You advise a guardian raising \(request.childName), age \(request.childAge).
        Use the child's local memory digest and growth profile to give practical, kind, specific parenting strategy.
        Treat child_ai_memory, child_growth_profile, active_tasks, and reward_context as background only. Never paste those raw fields back to the parent.
        Do not expose or reconstruct the child's private raw transcript. Do not shame, threaten, manipulate, or recommend surveillance.
        Help the parent design routines, task packages, reading/video learning, outdoor play, sleep rhythm, screen-time exchange, pocket money, and wish-list incentives.
        If the topic is homework, coach the parent to guide with questions and hints; do not give the child a final answer.
        If there is self-harm, abuse, violence, bullying, or immediate danger, advise the parent to intervene immediately and seek qualified local help.
        Keep answers operational: what to say, what to set in OctoTeacher, what to observe, and how to review tomorrow.
        Memory rule: do not include parent_memory_updates in the visible reply. OctoTeacher will summarize useful strategy locally later.
        """
    }

    func userPrompt(_ request: ParentAICompanionCoachRequest) -> String {
        let childContext = request.childRecentContextLines.isEmpty
            ? "none"
            : request.childRecentContextLines.joined(separator: "\n")
        let parentContext = request.parentRecentContextLines.isEmpty
            ? "none"
            : request.parentRecentContextLines.joined(separator: "\n")
        let growth = request.growthProfileSummary.isEmpty ? "none" : request.growthProfileSummary
        let attachments = request.attachmentSummaries.isEmpty
            ? "none"
            : request.attachmentSummaries.joined(separator: "\n")
        return """
        child_name=\(request.childName)
        child_age=\(request.childAge)

        child_ai_memory:
        \(request.childMemory.promptSummary)

        child_growth_profile:
        \(growth)

        clipped_child_recent_context:
        \(childContext)

        parent_coach_memory:
        \(request.parentMemory.promptSummary)

        parent_recent_context:
        \(parentContext)

        active_tasks:
        \(request.activeTasksSummary)

        reward_context:
        \(request.rewardSummary)

        parent_shared_images:
        \(attachments)

        parent_question:
        \(request.latestText)
        """
    }

    func parseTurn(_ response: String) throws -> ParentAICompanionCoachTurn {
        let normalized = normalizedJSONText(response)
        guard let data = normalized.data(using: .utf8) else {
            throw ParentAICompanionCoachError.badResponse
        }
        struct Envelope: Decodable {
            struct Updates: Decodable {
                var parentGoals: [String]?
                var usefulStrategies: [String]?
                var boundaryNotes: [String]?
                var summary: String?

                enum CodingKeys: String, CodingKey {
                    case parentGoals = "parent_goals"
                    case usefulStrategies = "useful_strategies"
                    case boundaryNotes = "boundary_notes"
                    case summary
                }
            }

            var reply: String
            var parentMemoryUpdates: Updates?

            enum CodingKeys: String, CodingKey {
                case reply
                case parentMemoryUpdates = "parent_memory_updates"
            }
        }

        let decoded: Envelope
        do {
            decoded = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            return try parsePlainTurn(response)
        }

        let reply = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw ParentAICompanionCoachError.badResponse }
        guard !MobileSyncPayloadGuard.isUnsafe(reply),
              !looksLikeInternalPromptLeak(reply) else {
            throw ParentAICompanionCoachError.unsafeResponse
        }
        let updates = decoded.parentMemoryUpdates
        return ParentAICompanionCoachTurn(
            reply: reply,
            memoryUpdate: ParentAICompanionCoachMemoryUpdate(
                parentGoals: capped(updates?.parentGoals),
                usefulStrategies: capped(updates?.usefulStrategies),
                boundaryNotes: capped(updates?.boundaryNotes),
                summary: updates?.summary ?? ""
            ),
            providerUsed: true
        )
    }

    func localTurn(
        request: ParentAICompanionCoachRequest,
        shouldRecordStrategy: Bool = true
    ) -> ParentAICompanionCoachTurn {
        let intent = localIntent(for: request.latestText)
        if request.language == .english {
            let reply: String
            switch intent {
            case .capabilities:
                reply = "I can summarize recent growth signals, turn a family goal into a small task and reward draft, suggest words you can use tonight, and help review what worked. When the cloud is unavailable, I use only on-device summaries, never the child's full private transcript."
            case .childStatus:
                reply = "Start with one calm question: ‘What felt hardest to begin today?’ Listen first, then reduce the next action to something that takes less than five minutes. Review the result without blame."
            case .rewardOrTask:
                reply = "Use one main task and one optional bonus task. Award Growth Points after a parent review, then let the family rules decide whether points can exchange for screen time, allowance, or a wish-list item."
            case .strategy:
                reply = "Start by naming the child's feeling, then offer one small step. Try: ‘I'm not here to blame you. Let's choose the easiest thing to begin, and we'll record the effort when it is done.’ Review what was easy and what should be smaller tomorrow."
            }
            let update = shouldRecordStrategy
                ? ParentAICompanionCoachMemoryUpdate.local(parentText: request.latestText)
                : ParentAICompanionCoachMemoryUpdate(summary: "Cloud failed; temporary on-device guidance was shown and not saved as a long-term strategy.")
            return ParentAICompanionCoachTurn(reply: reply, memoryUpdate: update, providerUsed: false)
        }
        let reply: String
        switch intent {
        case .capabilities:
            reply = """
            我可以做四件事：1. 结合 \(request.childName) 的小伙伴记忆和成长记录，总结最近兴趣、卡点和情绪线索；2. 帮你把目标拆成任务包、成长积分、屏幕时间兑换和愿望清单；3. 设计今晚能说出口的一句话和一个最小动作；4. 复盘哪些方法有效、哪些会让孩子更抵触。云端没接上时我只用本机摘要，不会读取原始聊天全文。
            """
        case .childStatus:
            let memory = childMemorySummary(request.childMemory)
            let growth = humanSummary(from: request.growthProfileSummary, empty: "暂无新的成长记录摘要。")
            let tasks = request.activeTasksSummary.isEmpty ? "当前没有待开始任务。" : request.activeTasksSummary
            reply = """
            先给你本机摘要：\(request.childName) 最近的线索是：\(clipped(memory, limit: 140)) 成长记录：\(clipped(growth, limit: 120)) 任务状态：\(clipped(tasks, limit: 100))。建议你下一步只问一个温和问题：「今天哪件事最难开始？」再把它改成 5 分钟以内的小任务。
            """
        case .rewardOrTask:
            let tasks = request.activeTasksSummary.isEmpty ? "先新增一个 5-15 分钟任务，例如睡前阅读、整理书包或刷牙洗脸。" : request.activeTasksSummary
            let rewards = request.rewardSummary.isEmpty ? "奖励可以先用成长积分，暂不直接给屏幕时间。" : request.rewardSummary
            reply = """
            任务和奖励建议：\(clipped(tasks, limit: 120)) 奖励出口：\(clipped(rewards, limit: 120))。今晚只设一个主任务、一个可选加分任务；完成后给成长积分，再由家长审核是否兑换屏幕时间、零花钱或愿望清单。
            """
        case .strategy:
            let taskHint = request.activeTasksSummary.isEmpty
                ? "先在家长端布置一个 5-15 分钟的小任务。"
                : "先从正在进行的任务里挑一个最小动作。"
            reply = """
            我先用本机规则给你一个稳妥策略：先接住孩子当下的感受，再把要求缩成一个可完成的小步骤。\(taskHint)
            今天可以这样说：「我不是来骂你的，我们先一起选一件最容易开始的事，做完就记录成长积分。」完成后只复盘事实：哪里顺、哪里卡、明天要不要调小一点。
            """
        }
        let update = shouldRecordStrategy
            ? ParentAICompanionCoachMemoryUpdate.local(parentText: request.latestText)
            : ParentAICompanionCoachMemoryUpdate(
                summary: "云端失败后提供了一次本机\(intent.memoryLabel)兜底，未写入长期策略。"
            )
        return ParentAICompanionCoachTurn(reply: reply, memoryUpdate: update, providerUsed: false)
    }

    private func parsePlainTurn(_ response: String) throws -> ParentAICompanionCoachTurn {
        let reply = normalizedPlainText(response)
        guard !reply.isEmpty else { throw ParentAICompanionCoachError.badResponse }
        guard !MobileSyncPayloadGuard.isUnsafe(reply),
              !looksLikeInternalPromptLeak(reply) else {
            throw ParentAICompanionCoachError.unsafeResponse
        }
        return ParentAICompanionCoachTurn(
            reply: reply,
            memoryUpdate: ParentAICompanionCoachMemoryUpdate(),
            providerUsed: true
        )
    }

    private func childMemorySummary(_ memory: AICompanionMemoryDigest) -> String {
        var parts: [String] = []
        if !memory.latestSummary.isEmpty { parts.append(memory.latestSummary) }
        if !memory.interests.isEmpty { parts.append("兴趣：\(memory.interests.prefix(3).joined(separator: "、"))") }
        if !memory.learningNotes.isEmpty { parts.append("学习线索：\(memory.learningNotes.prefix(2).joined(separator: "、"))") }
        if !memory.emotionalNotes.isEmpty { parts.append("情绪线索：\(memory.emotionalNotes.prefix(2).joined(separator: "、"))") }
        if !memory.preferences.isEmpty { parts.append("偏好：\(memory.preferences.prefix(2).joined(separator: "、"))") }
        return parts.isEmpty ? "暂无可用的小伙伴记忆摘要。" : parts.joined(separator: "；")
    }

    private func humanSummary(from raw: String, empty: String) -> String {
        let lines = raw
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.contains("=") }
            .filter { !$0.contains("_count") && !$0.contains("_summary") }
        return lines.isEmpty ? empty : lines.joined(separator: "；")
    }

    private enum LocalIntent {
        case capabilities
        case childStatus
        case rewardOrTask
        case strategy

        var memoryLabel: String {
            switch self {
            case .capabilities: return "能力说明"
            case .childStatus: return "孩子现况"
            case .rewardOrTask: return "任务奖励"
            case .strategy: return "育儿策略"
            }
        }
    }

    private func localIntent(for text: String) -> LocalIntent {
        if containsAny(text, ["能做什么", "你会什么", "有什么功能", "怎么用", "可以做什么"]) {
            return .capabilities
        }
        if containsAny(text, ["现况", "情况", "状态", "最近", "表现", "报告", "总结"]) {
            return .childStatus
        }
        if containsAny(text, ["任务", "奖励", "积分", "屏幕时间", "零花钱", "愿望", "兑换"]) {
            return .rewardOrTask
        }
        return .strategy
    }

    private func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func clipped(_ text: String, limit: Int) -> String {
        String(
            text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(limit)
        )
    }

    private func capped(_ values: [String]?) -> [String] {
        Array((values ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !MobileSyncPayloadGuard.isUnsafe($0) }
            .prefix(4))
    }

    private func normalizedJSONText(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.firstIndex(of: "{"),
           let last = trimmed.lastIndex(of: "}"),
           first < last {
            return String(trimmed[first...last]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else { return trimmed }
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 3 else { return trimmed }
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveContains("json") == true else {
            return trimmed
        }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedPlainText(_ response: String) -> String {
        var trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```"), trimmed.hasSuffix("```") {
            var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.count >= 3 {
                lines.removeFirst()
                lines.removeLast()
                trimmed = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            guard let looseReply = extractLooseReply(from: trimmed) else { return "" }
            trimmed = looseReply
        }
        return String(trimmed.prefix(1000))
    }

    private func extractLooseReply(from text: String) -> String? {
        let markers = ["\"reply\"", "reply", "回复", "回答"]
        for marker in markers {
            guard let markerRange = text.range(of: marker, options: [.caseInsensitive]) else { continue }
            let tail = text[markerRange.upperBound...]
            guard let colon = tail.firstIndex(of: ":") else { continue }
            var value = String(tail[tail.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\"") { value.removeFirst() }
            let stopMarkers = [
                "\",\"parent_memory_updates", "\", \"parent_memory_updates",
                "\", parent_memory_updates", ", parent_memory_updates",
                "\",\"memory_updates", "\", \"memory_updates",
                "\", memory_updates", ", memory_updates",
                "\n}", "\n]", "}"
            ]
            for stop in stopMarkers {
                if let range = value.range(of: stop) {
                    value = String(value[..<range.lowerBound])
                }
            }
            value = value
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" ,}\n\t"))
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\"", with: "\"")
            guard !value.isEmpty, !looksLikeInternalPromptLeak(value) else { continue }
            return String(value.prefix(1000))
        }
        return nil
    }

    private func looksLikeInternalPromptLeak(_ text: String) -> Bool {
        let markers = [
            "companion_name=", "conversation_count=", "latest_summary=", "growth_event_count=",
            "ai_chat_summary=", "growth_recent:", "child_ai_memory:", "child_growth_profile:",
            "parent_coach_memory:", "parent_memory_updates", "memory_updates", "guardian_signal",
            "active_tasks:", "reward_context:", "parent_recent_context:", "clipped_child_recent_context:"
        ]
        return containsAny(text, markers)
    }
}
