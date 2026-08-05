import Foundation
import Observation

struct AICompanionSessionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var childId: UUID
    var createdAt: Date
    var mode: AICompanionMode
    var status: AICompanionStatus
    var latestIntent: AICompanionIntent
    var intentLabels: [String]
    var riskLabels: [AICompanionRiskLabel]
    var needsGuardianAction: Bool
    var suggestedGuardianAction: String
    var findingCodes: [AICompanionFindingCode]

    var storesRawTranscript: Bool { false }
    var callsNetwork: Bool { false }
    var givesFinalAnswer: Bool { false }

    static func make(
        childId: UUID,
        createdAt: Date = Date(),
        mode: AICompanionMode,
        latestMessage: AICompanionMessage,
        guardianSnapshot: AICompanionSnapshot
    ) -> AICompanionSessionRecord {
        let summary = guardianSnapshot.careSummary
        return AICompanionSessionRecord(
            id: UUID(),
            childId: childId,
            createdAt: createdAt,
            mode: mode,
            status: guardianSnapshot.status,
            latestIntent: latestMessage.intent,
            intentLabels: summary?.intentLabels ?? [latestMessage.intent.label],
            riskLabels: summary?.riskLabels ?? [],
            needsGuardianAction: summary?.needsGuardianAction ?? false,
            suggestedGuardianAction: summary?.suggestedGuardianAction ?? "当前无需介入，孩子可以继续按小步骤推进。",
            findingCodes: guardianSnapshot.findings
        )
    }
}

protocol AICompanionSessionPersisting {
    func load() -> [AICompanionSessionRecord]
    func save(_ records: [AICompanionSessionRecord])
}

struct FileAICompanionSessionPersistence: AICompanionSessionPersisting {
    var fileURL: URL

    static func documents(fileName: String = "octoteacher-ai-companion-sessions.json") -> FileAICompanionSessionPersistence {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileAICompanionSessionPersistence(fileURL: directory.appendingPathComponent(fileName))
    }

    init(directory: URL, fileName: String = "octoteacher-ai-companion-sessions.json") {
        fileURL = directory.appendingPathComponent(fileName)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> [AICompanionSessionRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AICompanionSessionRecord].self, from: data)) ?? []
    }

    func save(_ records: [AICompanionSessionRecord]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
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
final class AICompanionSessionStore {
    static let maxRecordsPerChild = 50

    private(set) var records: [AICompanionSessionRecord]

    @ObservationIgnored
    private let persistence: (any AICompanionSessionPersisting)?

    init(persistence: (any AICompanionSessionPersisting)? = nil) {
        self.persistence = persistence
        self.records = persistence?.load().sorted { $0.createdAt > $1.createdAt } ?? []
    }

    func append(
        childId: UUID,
        mode: AICompanionMode,
        latestMessage: AICompanionMessage,
        guardianSnapshot: AICompanionSnapshot,
        createdAt: Date = Date()
    ) {
        let record = AICompanionSessionRecord.make(
            childId: childId,
            createdAt: createdAt,
            mode: mode,
            latestMessage: latestMessage,
            guardianSnapshot: guardianSnapshot
        )
        records.insert(record, at: 0)
        records.sort { $0.createdAt > $1.createdAt }
        records = capped(records)
        persistence?.save(records)
    }

    func records(for childId: UUID) -> [AICompanionSessionRecord] {
        records.filter { $0.childId == childId }.sorted { $0.createdAt > $1.createdAt }
    }

    func latestRecord(for childId: UUID) -> AICompanionSessionRecord? {
        records(for: childId).first
    }

    func clear(for childId: UUID) {
        records.removeAll { $0.childId == childId }
        persistence?.save(records)
    }

    private func capped(_ records: [AICompanionSessionRecord]) -> [AICompanionSessionRecord] {
        var counts: [UUID: Int] = [:]
        return records.filter { record in
            let current = counts[record.childId, default: 0]
            guard current < Self.maxRecordsPerChild else { return false }
            counts[record.childId] = current + 1
            return true
        }
    }
}
