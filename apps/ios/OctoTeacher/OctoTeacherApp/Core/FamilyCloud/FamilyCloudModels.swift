import Foundation

enum FamilyCloudTaskDateCodec {
    static func encode(_ date: Date) -> String {
        formatter().string(from: date)
    }

    static func decode(_ value: String) -> Date? {
        formatter().date(from: value)
    }

    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

struct FamilyCloudSnapshot: Codable, Equatable {
    struct Family: Codable, Equatable {
        var id: String
        var publicRef: String
        var displayName: String
        var isCreator: Bool
    }

    struct Guardian: Codable, Equatable, Identifiable {
        var id: String
        var displayName: String
        var isCreator: Bool
        var joinedAt: String?
    }

    struct Child: Codable, Equatable, Identifiable {
        var id: String
        var publicRef: String
        var clientRef: String?
        var displayName: String
        var birthYear: Int?
        var preReaderMode: Bool? = nil
        var interfaceLanguage: AppInterfaceLanguage? = nil
        var contentLanguage: FamilyLanguage? = nil
        var dailyLimitMinutes: Int? = nil
        var exchangePolicy: FamilyExchangePolicy? = nil
        var screenTimeCatalog: FamilyScreenTimeCatalog? = nil
        var screenTimePolicy: FamilyScreenTimePolicy? = nil
        var screenTimeStatus: FamilyScreenTimeDeviceStatus? = nil
        var screenTimeEmergency: FamilyScreenTimeEmergency? = nil
        var profileVersion: Int? = nil
        var growthPointBalance: Int? = nil
    }

    struct Device: Codable, Equatable, Identifiable {
        var id: String
        var publicRef: String
        var displayName: String
        var role: String
        var childProfileId: String?
        var status: String
        var boundAt: String
        var protocolGeneration: Int?
        var requiresRebind: Bool?
    }

    var family: Family
    var guardians: [Guardian]
    var children: [Child]
    var devices: [Device]
}

struct FamilyCloudInvite: Codable, Equatable, Identifiable {
    var payload: String
    var publicRef: String
    var expiresAt: String
    var kind: String
    var id: String { publicRef }
}

struct FamilyCloudJoinPayload: Codable, Equatable, Identifiable {
    static let currentVersion = 2
    static let schemePrefix = "octoteacher://family/cloud-join/"

    var version: Int
    var publicRef: String
    var secret: String
    var kind: String
    var expiresAt: String
    var id: String { publicRef }

    var isGuardian: Bool { kind == "guardian" }
    var isChildDevice: Bool { kind == "child_device" }

    static func decode(_ rawValue: String) -> Self? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix(schemePrefix) else { return nil }
        var encoded = String(value.dropFirst(schemePrefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if encoded.count % 4 != 0 {
            encoded += String(repeating: "=", count: 4 - encoded.count % 4)
        }
        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONDecoder().decode(Self.self, from: data),
              payload.version == currentVersion,
              payload.isGuardian || payload.isChildDevice else { return nil }
        return payload
    }
}

struct FamilyCloudTask: Codable, Equatable, Identifiable {
    var id: String
    var childProfileId: String
    var clientRef: String
    var title: String
    var titleEnglish: String?
    var status: String
    var growthPoints: Int
    var requiresEvidence: Bool
    var plannedFor: String?
    var evidenceSummary: String?
    var taskPayload: FamilyCloudTaskPayload? = nil
    var version: Int
    var updatedAt: String
}

enum FamilyChildSurfaceModuleKey: String, Codable, Equatable {
    case today
    case reading
    case video
    case creation
    case completed
}

struct FamilyChildSurface: Codable, Equatable {
    struct Child: Codable, Equatable {
        var id: String
        var publicRef: String
        var clientRef: String?
        var displayName: String
        var birthYear: Int?
        var preReaderMode: Bool
        var interfaceLanguage: AppInterfaceLanguage
        var contentLanguage: FamilyLanguage
        var growthPointBalance: Int
    }

    struct Module: Codable, Equatable, Identifiable {
        var id: String
        var key: FamilyChildSurfaceModuleKey
        var title: String
        var titleEnglish: String
        var sortOrder: Int
    }

    struct TaskItem: Codable, Equatable, Identifiable {
        var itemId: String
        var moduleId: String
        var sortOrder: Int
        var task: FamilyCloudTask
        var id: String { itemId }
    }

    struct ContentItem: Codable, Equatable, Identifiable {
        struct Assignment: Codable, Equatable {
            var status: String
            var progressPercent: Int
            var durationSeconds: Int
            var version: Int
            var updatedAt: String
        }

        var id: String
        var publicRef: String
        var clientRef: String
        var kind: String
        var title: String
        var titleEnglish: String?
        var sourceKind: String
        var sourceRef: String?
        var availability: String
        var assignment: Assignment
        var version: Int
        var updatedAt: String
    }

    struct Library: Codable, Equatable {
        var books: [ContentItem]
        var videos: [ContentItem]
        var creations: [ContentItem]
    }

    struct Sync: Codable, Equatable {
        struct RemovedRefs: Codable, Equatable {
            var tasks: [String]
            var content: [String]
        }

        var taskCursor: Int64
        var removedRefs: RemovedRefs
    }

    var schemaVersion: Int
    var generatedAt: String
    var cursor: String
    var surfaceVersion: String
    var child: Child
    var modules: [Module]
    var tasks: [TaskItem]
    var library: Library
    var sync: Sync
}

struct FamilyCloudTaskUpload: Codable, Equatable {
    var childClientRef: String
    var clientRef: String
    var title: String
    var titleEnglish: String?
    var status: String
    var growthPoints: Int
    var requiresEvidence: Bool
    var plannedFor: String?
    var version: Int
    var baseVersion: Int?
    var taskPayload: FamilyCloudTaskPayload?
}

/// 可跨孩子设备同步的任务合同。只包含任务执行所需字段和可公开重新下载的书源元数据；
/// 证明文件、聊天、成长记忆、邮件、家长备注和 provider 凭证永不进入这里。
struct FamilyCloudTaskPayload: Codable, Equatable {
    static let currentVersion = 2

    var version: Int = currentVersion
    var task: TaskTemplate
    var bookResource: FamilyCloudBookResource?
    var readingMode: ReadingDeliveryMode? = nil
    var contentReadiness: FamilyCloudContentReadiness? = nil

    /// 云端投递合同只回答“孩子现在能否真正执行”。下载失败等设备状态由本机再收紧。
    var isCloudExecutable: Bool {
        guard task.reading != nil else {
            return readingMode == nil && (contentReadiness == nil || contentReadiness == .notRequired)
        }
        if version < Self.currentVersion {
            // 旧版只有确实携带可重新下载资源时才允许迁移；仅有书名的历史任务必须隔离。
            return bookResource?.hasUsableRemoteSource == true
        }
        switch readingMode {
        case .physicalManual:
            return contentReadiness == .notRequired && bookResource == nil
        case .digitalLoaded:
            return contentReadiness == .ready && bookResource?.hasUsableRemoteSource == true
        case .digitalRequired, .none:
            return false
        }
    }
}

enum FamilyCloudContentReadiness: String, Codable, Equatable {
    case ready
    case missing
    case notRequired = "not_required"
}

struct FamilyCloudBookResource: Codable, Equatable {
    var id: UUID
    var title: String
    var format: String
    var sourceName: String?
    var sourceURLString: String

    var hasUsableRemoteSource: Bool {
        guard let url = URL(string: sourceURLString) else { return false }
        return url.scheme?.lowercased() == "https" && url.host != nil
    }
}

struct ChildDeviceProfileResponse: Codable, Equatable {
    struct Family: Codable, Equatable {
        var id: String
        var publicRef: String
        var displayName: String
    }

    var id: String
    var publicRef: String
    var clientRef: String?
    var displayName: String
    var birthYear: Int?
    var preReaderMode: Bool?
    var interfaceLanguage: AppInterfaceLanguage?
    var contentLanguage: FamilyLanguage?
    var dailyLimitMinutes: Int? = nil
    var exchangePolicy: FamilyExchangePolicy? = nil
    var screenTimeCatalog: FamilyScreenTimeCatalog? = nil
    var screenTimePolicy: FamilyScreenTimePolicy? = nil
    var screenTimeStatus: FamilyScreenTimeDeviceStatus? = nil
    var screenTimeEmergency: FamilyScreenTimeEmergency? = nil
    var profileVersion: Int?
    var growthPointBalance: Int? = nil
    var family: Family
}

enum FamilyScreenTimeEmergencyStatus: String, Codable, Equatable {
    case idle
    case requested
    case approved
    case denied
    case active
    case completed
    case expired
}

/// Cross-device school emergency contract. The server owns all transitions and timestamps;
/// clients only request an action and render the returned state.
struct FamilyScreenTimeEmergency: Codable, Equatable {
    var schemaVersion: Int
    var status: FamilyScreenTimeEmergencyStatus
    var requestId: String?
    var reason: String?
    var minutes: Int?
    var requestedAt: String?
    var decidedAt: String?
    var approvalExpiresAt: String?
    var activatedAt: String?
    var sessionEndsAt: String?
    var completedAt: String?
    var expiredAt: String?
    var expirationReason: String?
    var updatedAt: String

    var isPendingGuardianDecision: Bool { status == .requested }
    var mayBeActivatedByChild: Bool { status == .approved }

    func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    var sessionEndDate: Date? { date(from: sessionEndsAt) }
    var approvalExpirationDate: Date? { date(from: approvalExpiresAt) }
}

struct FamilyAIProviderProvisioning: Codable, Equatable {
    var providerKind: String
    var modelName: String
    var apiKey: String
    var guidanceEnabled: Bool
    var imageUploadEnabled: Bool
    var voiceEnabled: Bool
}

struct FamilyAICapabilities: Codable, Equatable {
    var configured: Bool
    var guidanceEnabled: Bool
    var imageUploadEnabled: Bool
    var voiceEnabled: Bool
    var providerKind: String?
    var modelName: String?

    static let unavailable = FamilyAICapabilities(
        configured: false,
        guidanceEnabled: false,
        imageUploadEnabled: false,
        voiceEnabled: false,
        providerKind: nil,
        modelName: nil
    )
}

struct FamilyAIChatRelayRequest: Codable, Equatable {
    struct Image: Codable, Equatable {
        var mimeType: String
        var base64Data: String
    }

    var system: String
    var user: String
    var images: [Image]
    var homeworkSensitive: Bool
}

struct FamilyAITranscriptionRelayRequest: Codable, Equatable {
    var mimeType: String
    var base64Data: String
}

struct FamilyCloudTaskPage: Codable, Equatable {
    var tasks: [FamilyCloudTask]
    var removedClientRefs: [String]
    var cursor: Int64
    var hasMore: Bool

    init(tasks: [FamilyCloudTask], removedClientRefs: [String] = [], cursor: Int64, hasMore: Bool) {
        self.tasks = tasks
        self.removedClientRefs = removedClientRefs
        self.cursor = cursor
        self.hasMore = hasMore
    }

    private enum CodingKeys: String, CodingKey { case tasks, removedClientRefs, cursor, hasMore }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decode([FamilyCloudTask].self, forKey: .tasks)
        removedClientRefs = try container.decodeIfPresent([String].self, forKey: .removedClientRefs) ?? []
        cursor = try container.decodeIfPresent(Int64.self, forKey: .cursor) ?? 0
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

struct PendingFamilyCloudGuardianDecision: Codable, Equatable, Identifiable {
    var id: UUID { assignmentId }
    var assignmentId: UUID
    var status: String
    var expectedVersion: Int
    var queuedAt: Date

    init(assignmentId: UUID, status: String, expectedVersion: Int, queuedAt: Date) {
        self.assignmentId = assignmentId
        self.status = status
        self.expectedVersion = expectedVersion
        self.queuedAt = queuedAt
    }

    private enum CodingKeys: String, CodingKey {
        case assignmentId, status, expectedVersion, queuedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assignmentId = try container.decode(UUID.self, forKey: .assignmentId)
        status = try container.decode(String.self, forKey: .status)
        // A pre-versioned decision is unsafe to replay. Zero makes it fail closed
        // and forces a fresh review after the next cloud pull.
        expectedVersion = try container.decodeIfPresent(Int.self, forKey: .expectedVersion) ?? 0
        queuedAt = try container.decode(Date.self, forKey: .queuedAt)
    }
}

/// A guardian-authored task mutation that was explicitly queued before network I/O.
/// Keeping the complete upload contract makes retries idempotent and prevents a later
/// local cache snapshot from being mistaken for fresh guardian intent.
struct PendingFamilyCloudGuardianTaskUpsert: Codable, Equatable, Identifiable {
    var id: String { mutationRef }
    var mutationRef: String
    var upload: FamilyCloudTaskUpload
    var queuedAt: Date
}

struct PendingFamilyCloudSubmission: Codable, Equatable, Identifiable {
    var id: String { mutationRef }
    var mutationRef: String
    var localAssignmentId: UUID
    /// Older local tasks can still be submitted before the in-memory cloud map is restored.
    /// Keep the action durable and resolve the server task id from `localAssignmentId` later.
    var cloudTaskId: String?
    var expectedVersion: Int
    var evidenceSummary: String?
    var queuedAt: Date
}

struct PendingFamilyCloudWithdrawal: Codable, Equatable, Identifiable {
    var id: String { mutationRef }
    var mutationRef: String
    var localAssignmentId: UUID
    var cloudTaskId: String?
    var expectedVersion: Int
    var queuedAt: Date
}

enum FamilyCloudPointMutationKind: String, Codable, Equatable {
    case screenTimeSpend = "screen_time_spend"
    case screenTimeRefund = "screen_time_refund"
}

struct PendingFamilyCloudPointMutation: Codable, Equatable, Identifiable {
    var id: String { mutationRef }
    var mutationRef: String
    var kind: FamilyCloudPointMutationKind
    var delta: Int
    var sourceRef: String
    var queuedAt: Date
}

struct FailedFamilyCloudPointMutation: Codable, Equatable, Identifiable {
    var id: String { mutationRef }
    var mutationRef: String
    var kind: FamilyCloudPointMutationKind
    var delta: Int
    var sourceRef: String
    var errorCode: String
    var failedAt: Date
}

enum FamilyCloudPointMutationFailureDisposition: Equatable {
    case deadLetter
    case refreshAndRetry
    case retryLater
}

func familyCloudPointMutationFailureDisposition(
    serverCode: String
) -> FamilyCloudPointMutationFailureDisposition {
    if serverCode == "points_refund_invalid" ||
        serverCode == "insufficient_growth_points" {
        return .refreshAndRetry
    }
    if serverCode.hasPrefix("invalid_") || serverCode.hasSuffix("_conflict") {
        return .deadLetter
    }
    return .retryLater
}

struct FamilyCloudPointMutationResponse: Codable, Equatable {
    var balance: Int
    var applied: Bool
}

struct FamilyCloudPortalLink: Codable, Equatable {
    var code: String
    var expiresAt: String
}

enum FamilyCloudActivityKind: String, Codable, Equatable {
    case task = "task"
    case reading = "reading"
    case video = "video"
    case screenTime = "screen_time"
    case creation = "creation"
}

struct FamilyCloudActivitySummary: Codable, Equatable {
    struct SummaryRow: Codable, Equatable {
        var childProfileId: String
        var kind: FamilyCloudActivityKind
        var eventCount: Int
        var durationSeconds: Int
        var maxProgressPercent: Int?
        var lastOccurredAt: String?
    }

    struct RecentEvent: Codable, Equatable {
        var eventId: String
        var kind: FamilyCloudActivityKind
        var occurredAt: String
        var durationSeconds: Int?
        var progressPercent: Int?
        var displayName: String
        var resourceRef: String?
    }

    struct ScreenTimeDailyRow: Codable, Equatable {
        var date: String
        var durationSeconds: Int
        var eventCount: Int
    }

    struct ScreenTimeAppDailyRow: Codable, Equatable {
        var date: String
        var appRef: String
        var authority: String
        var durationSeconds: Int
        var eventCount: Int
    }

    var windowDays: Int
    var summary: [SummaryRow]
    var recent: [RecentEvent]
    var screenTimeDaily: [ScreenTimeDailyRow]
    var screenTimeAppDaily: [ScreenTimeAppDailyRow]

    init(
        windowDays: Int,
        summary: [SummaryRow],
        recent: [RecentEvent],
        screenTimeDaily: [ScreenTimeDailyRow] = [],
        screenTimeAppDaily: [ScreenTimeAppDailyRow] = []
    ) {
        self.windowDays = windowDays
        self.summary = summary
        self.recent = recent
        self.screenTimeDaily = screenTimeDaily
        self.screenTimeAppDaily = screenTimeAppDaily
    }

    private enum CodingKeys: String, CodingKey {
        case windowDays
        case summary
        case recent
        case screenTimeDaily
        case screenTimeAppDaily
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowDays = try container.decode(Int.self, forKey: .windowDays)
        summary = try container.decode([SummaryRow].self, forKey: .summary)
        recent = try container.decodeIfPresent([RecentEvent].self, forKey: .recent) ?? []
        screenTimeDaily = try container.decodeIfPresent(
            [ScreenTimeDailyRow].self,
            forKey: .screenTimeDaily
        ) ?? []
        screenTimeAppDaily = try container.decodeIfPresent(
            [ScreenTimeAppDailyRow].self,
            forKey: .screenTimeAppDaily
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windowDays, forKey: .windowDays)
        try container.encode(summary, forKey: .summary)
        try container.encode(recent, forKey: .recent)
        try container.encode(screenTimeDaily, forKey: .screenTimeDaily)
        try container.encode(screenTimeAppDaily, forKey: .screenTimeAppDaily)
    }

    var screenTimeAuthorizedSeconds: Int {
        summary
            .filter { $0.kind == .screenTime }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    var screenTimeAuthorizationCount: Int {
        summary
            .filter { $0.kind == .screenTime }
            .reduce(0) { $0 + $1.eventCount }
    }
}

/// A deliberately small, privacy-safe summary for the family console. Raw chat,
/// evidence, media, URLs, book text, provider credentials and Screen Time tokens
/// never enter this outbox.
struct PendingFamilyCloudActivityEvent: Codable, Equatable, Identifiable {
    var id: String { clientRef }
    var clientRef: String
    var kind: FamilyCloudActivityKind
    var displayName: String
    var durationSeconds: Int
    var progressPercent: Int?
    var resourceRef: String?
    var occurredAt: String
}

struct FamilyCloudActivityUploadResponse: Codable, Equatable {
    struct Event: Codable, Equatable {
        var clientRef: String
        var status: String
        var eventId: String
    }

    var acceptedCount: Int
    var duplicateCount: Int
    var events: [Event]
}

enum FamilyCloudGuardianProfileField: String, Codable, CaseIterable, Hashable {
    case displayName
    case birthYear
    case preReaderMode
    case interfaceLanguage
    case contentLanguage
    case dailyLimitMinutes
    case exchangePolicy

    /// Older builds only persisted a child reference, not the edited fields. Keep
    /// those intents, but never let them overwrite a language chosen on the child
    /// device without an explicit guardian language edit.
    static var legacySafeFields: Set<Self> {
        Set(allCases).subtracting([.interfaceLanguage])
    }
}

struct FamilyCloudSyncState: Codable, Equatable {
    var guardianCursors: [String: Int64] = [:]
    var childCursor: Int64 = 0
    var pendingChildSubmissions: [PendingFamilyCloudSubmission] = []
    /// Child withdrawals must survive app restarts just like submissions. Optional
    /// keeps state files produced by older builds decodable.
    var pendingChildWithdrawals: [PendingFamilyCloudWithdrawal]? = nil
    var pendingPointMutations: [PendingFamilyCloudPointMutation]? = nil
    var failedPointMutations: [FailedFamilyCloudPointMutation]? = nil
    var pendingActivityEvents: [PendingFamilyCloudActivityEvent]? = nil
    /// Bounded durable receipts prevent system callback/restart replays from
    /// recreating an acknowledged mutation with a different timestamp.
    var acknowledgedPointMutationRefs: [String]? = nil
    var acknowledgedActivityEventRefs: [String]? = nil
    /// Explicit guardian edits that still need to reach the cloud. Optional keeps
    /// sync-state files written by older builds backwards compatible.
    var pendingGuardianProfileClientRefs: [String]? = nil
    /// Field-level intent prevents an unrelated guardian edit from replaying an
    /// old full profile over a newer child-device language selection.
    var pendingGuardianProfileFields: [String: [FamilyCloudGuardianProfileField]]? = nil
    /// Monotonic per-child intent generation. A profile save that happens while an
    /// earlier request is in flight must not be cleared by that older response.
    var pendingGuardianProfileGenerations: [String: Int]? = nil
    /// Only explicit guardian decisions are protected from an incoming cloud status.
    /// Historical approved/rejected rows must never be inferred as fresh offline intent.
    var pendingGuardianDecisions: [PendingFamilyCloudGuardianDecision]? = nil
    /// New or explicitly edited guardian tasks waiting for cloud acknowledgement.
    var pendingGuardianTaskUpserts: [PendingFamilyCloudGuardianTaskUpsert]? = nil
    /// False/nil means this install has not yet established which tasks belong to cloud.
    /// During that first pull, existing local rows are cache only and are never uploaded.
    var guardianTaskBaselineEstablished: Bool? = nil
    /// Server tombstones that have advanced the child cursor but have not yet been
    /// applied to the local task store. Keeping them beside the cursor makes a
    /// crash between those two operations replayable after launch.
    var pendingRemovedTaskClientRefs: [String]? = nil
    var cachedTasks: [FamilyCloudTask]? = nil
    /// Last acknowledged cloud household snapshot for offline display only.
    var cachedFamily: FamilyCloudSnapshot? = nil
    var familySnapshotGeneration: Int64? = nil
    var guardianSnapshotDates: [String: Date]? = nil
    var childSnapshotDate: Date? = nil
}

protocol FamilyCloudSyncStateStoring {
    func load() -> FamilyCloudSyncState
    /// Returns only after the complete state is durably written.
    @discardableResult
    func save(_ state: FamilyCloudSyncState) -> Bool
}

final class FileFamilyCloudSyncStateStore: FamilyCloudSyncStateStoring {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func documents() -> FileFamilyCloudSyncStateStore {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileFamilyCloudSyncStateStore(
            fileURL: directory.appendingPathComponent("octoteacher-family-cloud-sync.json")
        )
    }

    func load() -> FamilyCloudSyncState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(FamilyCloudSyncState.self, from: data) else {
            return FamilyCloudSyncState()
        }
        return state
    }

    @discardableResult
    func save(_ state: FamilyCloudSyncState) -> Bool {
        do {
            let data = try JSONEncoder().encode(state)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }
}

final class InMemoryFamilyCloudSyncStateStore: FamilyCloudSyncStateStoring {
    private var state = FamilyCloudSyncState()
    func load() -> FamilyCloudSyncState { state }
    @discardableResult
    func save(_ state: FamilyCloudSyncState) -> Bool {
        self.state = state
        return true
    }
}

struct FamilyCloudExport: Codable, Equatable {
    struct AuditEntry: Codable, Equatable {
        var action: String
        var actorKind: String
        var targetPublicRef: String?
        var createdAt: String
    }

    var exportVersion: String
    var exportedAt: String
    var scope: String
    var scopeNote: String
    var family: FamilyCloudSnapshot
    var tasks: [FamilyCloudTask]
    var audit: [AuditEntry]
}

struct FamilyCloudDeletionReceipt: Codable, Equatable {
    var deleted: Bool
    var receiptId: String
    var deletedAt: String
}
