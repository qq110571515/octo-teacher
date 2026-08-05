import Foundation
import Observation

enum EmergencyUnlockStatus: String, Codable {
    case requested
    case approved
    case active
    case denied
    case expiredUnused
    case completed
}

struct EmergencyUnlockRequest: Identifiable, Codable, Equatable {
    var id: UUID
    var childId: UUID
    var reason: String
    var minutes: Int
    var status: EmergencyUnlockStatus
    var requestedAt: Date
    var decidedAt: Date?
    var decidedByGuardianId: UUID?
    var approvalExpiresAt: Date?
    var consumedAt: Date?
    var selectedApplicationTokenData: Data?
    var sessionEndsAt: Date?
}

struct EmergencyUnlockSnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var requests: [EmergencyUnlockRequest]
}

protocol EmergencyUnlockPersisting {
    func load() -> EmergencyUnlockSnapshot?
    func save(_ snapshot: EmergencyUnlockSnapshot) throws
}

struct FileEmergencyUnlockPersistence: EmergencyUnlockPersisting {
    var fileURL: URL

    static func documents() -> FileEmergencyUnlockPersistence {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileEmergencyUnlockPersistence(
            fileURL: documents.appendingPathComponent("octoteacher-emergency-unlocks.json")
        )
    }

    func load() -> EmergencyUnlockSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(EmergencyUnlockSnapshot.self, from: data)
    }

    func save(_ snapshot: EmergencyUnlockSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}

/// 紧急解锁是独立审批，不扣成长积分；批准后由孩子一次性选择一个被锁 App。
@Observable
final class EmergencyUnlockStore {
    static let grantedMinutes = 30
    static let approvalLifetime: TimeInterval = 12 * 60 * 60

    private(set) var requests: [EmergencyUnlockRequest]

    @ObservationIgnored
    private let persistence: (any EmergencyUnlockPersisting)?

    init(persistence: (any EmergencyUnlockPersisting)? = nil) {
        self.persistence = persistence
        requests = persistence?.load()?.requests ?? []
        refresh()
    }

    var pendingRequests: [EmergencyUnlockRequest] {
        requests.filter { $0.status == .requested }.sorted { $0.requestedAt < $1.requestedAt }
    }

    @discardableResult
    func submit(childId: UUID, reason: String, now: Date = Date()) -> EmergencyUnlockRequest {
        refresh(now: now)
        if let existing = requests.first(where: {
            $0.childId == childId && [.requested, .approved, .active].contains($0.status)
        }) {
            return existing
        }
        let request = EmergencyUnlockRequest(
            id: UUID(),
            childId: childId,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            minutes: Self.grantedMinutes,
            status: .requested,
            requestedAt: now
        )
        requests.insert(request, at: 0)
        persist()
        return request
    }

    @discardableResult
    func approve(_ requestID: UUID, guardianId: UUID?, now: Date = Date()) -> Bool {
        guard let index = requests.firstIndex(where: { $0.id == requestID && $0.status == .requested }) else {
            return false
        }
        requests[index].status = .approved
        requests[index].decidedAt = now
        requests[index].decidedByGuardianId = guardianId
        requests[index].approvalExpiresAt = now.addingTimeInterval(Self.approvalLifetime)
        persist()
        return true
    }

    @discardableResult
    func deny(_ requestID: UUID, guardianId: UUID?, now: Date = Date()) -> Bool {
        guard let index = requests.firstIndex(where: { $0.id == requestID && $0.status == .requested }) else {
            return false
        }
        requests[index].status = .denied
        requests[index].decidedAt = now
        requests[index].decidedByGuardianId = guardianId
        persist()
        return true
    }

    func latestRequest(for childId: UUID, now: Date = Date()) -> EmergencyUnlockRequest? {
        refresh(now: now)
        return requests.filter { $0.childId == childId }.max { $0.requestedAt < $1.requestedAt }
    }

    func approvedRequest(for childId: UUID, now: Date = Date()) -> EmergencyUnlockRequest? {
        refresh(now: now)
        return requests.first { $0.childId == childId && $0.status == .approved }
    }

    @discardableResult
    func activate(
        _ requestID: UUID,
        applicationTokenData: Data,
        endsAt: Date,
        now: Date = Date()
    ) -> Bool {
        refresh(now: now)
        guard let index = requests.firstIndex(where: { $0.id == requestID && $0.status == .approved }) else {
            return false
        }
        requests[index].status = .active
        requests[index].consumedAt = now
        requests[index].selectedApplicationTokenData = applicationTokenData
        requests[index].sessionEndsAt = endsAt
        persist()
        return true
    }

    func refresh(now: Date = Date()) {
        var changed = false
        for index in requests.indices {
            if requests[index].status == .approved,
               let expiresAt = requests[index].approvalExpiresAt,
               now >= expiresAt {
                requests[index].status = .expiredUnused
                changed = true
            } else if requests[index].status == .active,
                      let endsAt = requests[index].sessionEndsAt,
                      now >= endsAt {
                requests[index].status = .completed
                changed = true
            }
        }
        if changed { persist() }
    }

    private func persist() {
        try? persistence?.save(
            EmergencyUnlockSnapshot(
                schemaVersion: EmergencyUnlockSnapshot.currentSchemaVersion,
                requests: requests
            )
        )
    }
}
