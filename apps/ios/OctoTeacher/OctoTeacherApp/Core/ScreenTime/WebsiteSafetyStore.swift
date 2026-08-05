import Foundation
import Observation

enum BlockedWebsiteSource: String, Codable {
    case recommended
    case guardian
}

struct BlockedWebsiteEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var domain: String
    var source: BlockedWebsiteSource
    var isEnabled: Bool
    var createdAt: Date
}

struct WebsiteSafetySnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var automaticAdultContentFilterEnabled: Bool
    var entries: [BlockedWebsiteEntry]
}

protocol WebsiteSafetyPersisting {
    func load() -> WebsiteSafetySnapshot?
    func save(_ snapshot: WebsiteSafetySnapshot) throws
}

struct FileWebsiteSafetyPersistence: WebsiteSafetyPersisting {
    var fileURL: URL

    static func documents() -> FileWebsiteSafetyPersistence {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileWebsiteSafetyPersistence(
            fileURL: documents.appendingPathComponent("octoteacher-website-safety.json")
        )
    }

    func load() -> WebsiteSafetySnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WebsiteSafetySnapshot.self, from: data)
    }

    func save(_ snapshot: WebsiteSafetySnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}

enum AddBlockedWebsiteResult: Equatable {
    case added
    case duplicate
    case invalidDomain
    case capacityReached
}

/// 家长维护的网站安全策略库。这里只保存策略，不记录孩子访问过哪些网站。
@Observable
final class WebsiteSafetyStore {
    static let maximumBlockedDomains = 50

    /// 推荐列表是系统成人内容自动过滤的补充，不替代 Apple 的动态分类能力。
    static let recommendedDomains = [
        "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "redtube.com",
        "youporn.com", "tube8.com", "spankbang.com", "tnaflix.com", "beeg.com",
        "brazzers.com", "naughtyamerica.com", "realitykings.com", "bangbros.com",
        "chaturbate.com", "stripchat.com", "livejasmin.com", "cam4.com",
        "fansly.com", "onlyfans.com"
    ]

    var automaticAdultContentFilterEnabled: Bool
    private(set) var entries: [BlockedWebsiteEntry]

    @ObservationIgnored
    private let persistence: (any WebsiteSafetyPersisting)?

    init(persistence: (any WebsiteSafetyPersisting)? = nil, now: Date = Date()) {
        self.persistence = persistence
        if let snapshot = persistence?.load() {
            automaticAdultContentFilterEnabled = snapshot.automaticAdultContentFilterEnabled
            entries = snapshot.entries
        } else {
            automaticAdultContentFilterEnabled = true
            entries = []
        }
        mergeRecommendedDomains(now: now)
        persist()
    }

    var enabledDomains: [String] {
        entries.filter(\.isEnabled).map(\.domain).sorted()
    }

    var recommendedEntries: [BlockedWebsiteEntry] {
        entries.filter { $0.source == .recommended }.sorted { $0.domain < $1.domain }
    }

    var guardianEntries: [BlockedWebsiteEntry] {
        entries.filter { $0.source == .guardian }.sorted { $0.createdAt > $1.createdAt }
    }

    func setAutomaticAdultContentFilterEnabled(_ enabled: Bool) {
        automaticAdultContentFilterEnabled = enabled
        persist()
    }

    @discardableResult
    func addGuardianDomain(_ rawValue: String, now: Date = Date()) -> AddBlockedWebsiteResult {
        guard let domain = Self.normalizedDomain(rawValue) else { return .invalidDomain }
        guard !entries.contains(where: { $0.domain == domain }) else { return .duplicate }
        guard entries.count < Self.maximumBlockedDomains else { return .capacityReached }
        entries.append(
            BlockedWebsiteEntry(
                id: UUID(),
                domain: domain,
                source: .guardian,
                isEnabled: true,
                createdAt: now
            )
        )
        persist()
        return .added
    }

    func setEnabled(_ enabled: Bool, for entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].isEnabled = enabled
        persist()
    }

    func removeGuardianDomain(_ entryID: UUID) {
        entries.removeAll { $0.id == entryID && $0.source == .guardian }
        persist()
    }

    func restoreRecommendedProtection(now: Date = Date()) {
        automaticAdultContentFilterEnabled = true
        mergeRecommendedDomains(now: now)
        for index in entries.indices where entries[index].source == .recommended {
            entries[index].isEnabled = true
        }
        persist()
    }

    static func normalizedDomain(_ rawValue: String) -> String? {
        var candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !candidate.isEmpty else { return nil }
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }
        guard let components = URLComponents(string: candidate), var host = components.host else { return nil }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        guard host.count <= 253, host.contains("."), !host.contains(" ") else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 &&
                label.first != "-" && label.last != "-" &&
                label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }) else { return nil }
        return host
    }

    private func mergeRecommendedDomains(now: Date) {
        let existing = Set(entries.map(\.domain))
        for domain in Self.recommendedDomains where !existing.contains(domain) {
            entries.append(
                BlockedWebsiteEntry(
                    id: UUID(),
                    domain: domain,
                    source: .recommended,
                    isEnabled: true,
                    createdAt: now
                )
            )
        }
    }

    private func persist() {
        let snapshot = WebsiteSafetySnapshot(
            schemaVersion: WebsiteSafetySnapshot.currentSchemaVersion,
            automaticAdultContentFilterEnabled: automaticAdultContentFilterEnabled,
            entries: entries
        )
        try? persistence?.save(snapshot)
    }
}
