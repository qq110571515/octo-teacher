import Foundation
import Observation
import CryptoKit
import Security
import UIKit

protocol FamilyCloudSecretStoring {
    func save(_ value: String, account: String) -> Bool
    func load(account: String) -> String?
    func delete(account: String)
}

final class KeychainFamilyCloudSecretStore: FamilyCloudSecretStoring {
    private let service = "com.octoteacher.family.cloud"
    private static let backgroundAccessibleAccounts = Set([
        "child_device_session",
    ])

    func save(_ value: String, account: String) -> Bool {
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return false }
        delete(account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.accessibility(for: account),
            kSecAttrSynchronizable as String: false
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let attributes = result as? [String: Any],
              let data = attributes[kSecValueData as String] as? Data else { return nil }
        migrateAccessibilityIfNeeded(attributes: attributes, account: account)
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ] as CFDictionary)
    }

    static func accessibility(for account: String) -> CFString {
        backgroundAccessibleAccounts.contains(account)
            ? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }

    private func migrateAccessibilityIfNeeded(
        attributes: [String: Any],
        account: String
    ) {
        let desired = Self.accessibility(for: account)
        guard attributes[kSecAttrAccessible as String] as? String != desired as String else {
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        SecItemUpdate(
            query as CFDictionary,
            [kSecAttrAccessible as String: desired] as CFDictionary
        )
    }
}

final class InMemoryFamilyCloudSecretStore: FamilyCloudSecretStoring {
    private var values: [String: String] = [:]
    func save(_ value: String, account: String) -> Bool { values[account] = value; return true }
    func load(account: String) -> String? { values[account] }
    func delete(account: String) { values[account] = nil }
}

@MainActor
@Observable
final class FamilyCloudSessionStore {
    static let consentVersion = "2026-07-family-sync-v1"
    private static let snapshotRefreshInterval: TimeInterval = 5 * 60

    private enum Account {
        static let guardian = "guardian_session"
        static let child = "child_device_session"
        static let childRebind = "child_device_rebind_required"
        static let deviceRef = "device_public_ref"
    }

    private let client: FamilyCloudClient
    private let secrets: FamilyCloudSecretStoring
    private let syncStateStore: FamilyCloudSyncStateStoring
    private var syncState: FamilyCloudSyncState
    private var lastPersistedSyncState: FamilyCloudSyncState
    private var messageEnglish: String?
    private var isRestoringPersistedState = true
    #if DEBUG
    private var uiTestEmergency: FamilyScreenTimeEmergency?
    private var uiTestEmergencyChildID: UUID?
    #endif

    private(set) var guardian: GuardianSummary?
    private(set) var family: FamilyCloudSnapshot? {
        didSet {
            guard !isRestoringPersistedState, family != oldValue else { return }
            syncState.cachedFamily = family
            syncState.familySnapshotGeneration = (syncState.familySnapshotGeneration ?? 0) + 1
            _ = persistSyncState()
        }
    }
    private(set) var childDeviceName: String?
    private(set) var childDeviceProfile: ChildDeviceProfileResponse?
    private(set) var childAICapabilities: FamilyAICapabilities = .unavailable
    private(set) var cloudTasks: [FamilyCloudTask] = []
    private(set) var childSurface: FamilyChildSurface?
    private(set) var guardianActivitySummary: FamilyCloudActivitySummary?
    private(set) var guardianTodayActivitySummary: FamilyCloudActivitySummary?
    private(set) var guardianActivityLocalChildID: UUID?
    private(set) var downloadingBookIDs: Set<UUID> = []
    private(set) var failedBookDownloadIDs: Set<UUID> = []
    private(set) var isWorking = false
    private(set) var lastSyncAt: Date?
    private(set) var lastSyncError: String?
    private(set) var childDeviceRebindRequired = false
    private var isChildRefreshInFlight = false
    private var isGuardianRefreshInFlight = false
    private var isFlushingPointMutations = false
    private var isFlushingActivityEvents = false
    private var childForceRefreshRequested = false
    private var guardianForceRefreshRequested = false
    var message: String? {
        didSet {
            if message != oldValue { messageEnglish = nil }
        }
    }
    var pendingChildSubmissionCount: Int { syncState.pendingChildSubmissions.count }
    var pendingChildWithdrawalCount: Int { syncState.pendingChildWithdrawals?.count ?? 0 }
    var pendingPointMutationCount: Int { syncState.pendingPointMutations?.count ?? 0 }
    var pendingActivityEventCount: Int { syncState.pendingActivityEvents?.count ?? 0 }
    var pendingGuardianProfileCount: Int {
        var refs = Set(syncState.pendingGuardianProfileClientRefs ?? [])
        refs.formUnion(syncState.pendingGuardianProfileFields?.keys.map { $0 } ?? [])
        return refs.count
    }
    var pendingGuardianDecisionCount: Int { syncState.pendingGuardianDecisions?.count ?? 0 }
    var pendingGuardianTaskUpsertCount: Int { syncState.pendingGuardianTaskUpserts?.count ?? 0 }

    init(
        client: FamilyCloudClient = FamilyCloudClient(),
        secrets: FamilyCloudSecretStoring = KeychainFamilyCloudSecretStore(),
        syncStateStore: FamilyCloudSyncStateStoring = FileFamilyCloudSyncStateStore.documents()
    ) {
        self.client = client
        self.secrets = secrets
        self.syncStateStore = syncStateStore
        let restoredState = syncStateStore.load()
        self.syncState = restoredState
        self.lastPersistedSyncState = restoredState
        self.cloudTasks = restoredState.cachedTasks ?? []
        self.family = restoredState.cachedFamily
        self.childDeviceRebindRequired = secrets.load(account: Account.childRebind) == "1"
        self.isRestoringPersistedState = false
    }

    func localizedMessage(for language: AppInterfaceLanguage) -> String? {
        guard let message else { return nil }
        return language.pick(message, messageEnglish ?? message)
    }

    private func setMessage(_ chinese: String, _ english: String) {
        message = chinese
        messageEnglish = english
    }

    var guardianToken: String? { secrets.load(account: Account.guardian) }
    var childDeviceToken: String? { secrets.load(account: Account.child) }
    var isGuardianSignedIn: Bool { guardianToken != nil }
    var isChildDevice: Bool {
        childDeviceToken != nil || childDeviceRebindRequired || usesSchoolEmergencyUITestFixture
    }
    var isChildAIRelayReady: Bool {
        isChildDevice && childAICapabilities.configured && childAICapabilities.guidanceEnabled
    }
    var isChildAIImageRelayReady: Bool {
        isChildAIRelayReady && childAICapabilities.imageUploadEnabled
    }
    var isChildAIVoiceRelayReady: Bool {
        isChildAIRelayReady && childAICapabilities.voiceEnabled
    }
    var devicePublicRef: String {
        if let value = secrets.load(account: Account.deviceRef) { return value }
        let value = "ios_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        _ = secrets.save(value, account: Account.deviceRef)
        return value
    }

    /// 家长明确修改孩子档案后登记一个持久化同步意图。周期同步只发送这些档案，
    /// 避免其他家长设备用旧的本机副本反复覆盖云端新设置。
    @discardableResult
    func queueGuardianProfileSync(
        for childId: UUID,
        fields: Set<FamilyCloudGuardianProfileField> = Set(FamilyCloudGuardianProfileField.allCases)
    ) -> Bool {
        guard !fields.isEmpty else { return true }
        let clientRef = childId.uuidString.lowercased()
        var pending = Set(syncState.pendingGuardianProfileClientRefs ?? [])
        pending.insert(clientRef)
        syncState.pendingGuardianProfileClientRefs = pending.sorted()
        var pendingFields = syncState.pendingGuardianProfileFields ?? [:]
        let merged = Set(pendingFields[clientRef] ?? []).union(fields)
        pendingFields[clientRef] = merged.sorted { $0.rawValue < $1.rawValue }
        syncState.pendingGuardianProfileFields = pendingFields
        var generations = syncState.pendingGuardianProfileGenerations ?? [:]
        generations[clientRef, default: 0] += 1
        syncState.pendingGuardianProfileGenerations = generations
        return persistSyncState()
    }

    @discardableResult
    func queueGuardianTaskDecision(assignmentId: UUID, status: TaskAssignmentStatus) -> Bool {
        guard isGuardianSignedIn else {
            lastSyncError = "guardian_decision_session_unavailable"
            return false
        }
        guard let expectedVersion = cloudTasks.first(where: {
            $0.clientRef.lowercased() == assignmentId.uuidString.lowercased()
        })?.version else {
            lastSyncError = "guardian_decision_cloud_version_unavailable"
            return false
        }
        let cloudStatus: String
        switch status {
        case .approved: cloudStatus = "approved"
        case .rejected: cloudStatus = "rejected"
        case .cancelled: cloudStatus = "cancelled"
        case .open, .submitted: return false
        }
        var pending = syncState.pendingGuardianDecisions ?? []
        pending.removeAll { $0.assignmentId == assignmentId }
        pending.append(PendingFamilyCloudGuardianDecision(
            assignmentId: assignmentId,
            status: cloudStatus,
            expectedVersion: expectedVersion,
            queuedAt: Date()
        ))
        syncState.pendingGuardianDecisions = pending
        guard persistSyncState() else { return false }
        lastSyncError = nil
        return true
    }

    /// Call this after a guardian intentionally creates or edits a task. The upload is
    /// snapshotted immediately, so a restart cannot turn an arbitrary local cache row into
    /// cloud intent. Existing cross-feature editors still need to adopt this hook explicitly.
    @discardableResult
    func queueGuardianTaskUpsert(assignmentId: UUID, local: LocalFamilyStore) -> Bool {
        queueGuardianTaskUpserts(assignmentIds: [assignmentId], local: local)
    }

    /// Persist a batch of explicit guardian writes in one operation. Task-package and reading
    /// flows create several assignments at once, so the complete batch must be durable before
    /// the automatic cloud pull is allowed to treat the server snapshot as authoritative.
    @discardableResult
    func queueGuardianTaskUpserts(assignmentIds: [UUID], local: LocalFamilyStore) -> Bool {
        let uniqueIDs = Array(Set(assignmentIds))
        guard !uniqueIDs.isEmpty, isGuardianSignedIn else {
            lastSyncError = "guardian_task_upsert_unavailable"
            return false
        }
        let uploads = uniqueIDs.compactMap { assignmentId -> FamilyCloudTaskUpload? in
            guard let assignment = local.assignments.first(where: { $0.id == assignmentId }) else {
                return nil
            }
            return guardianTaskUpload(for: assignment, local: local, statusOverride: nil)
        }
        guard uploads.count == uniqueIDs.count else {
            lastSyncError = "guardian_task_upsert_unavailable"
            return false
        }
        var pending = syncState.pendingGuardianTaskUpserts ?? []
        let uploadRefs = Set(uploads.map { $0.clientRef.lowercased() })
        pending.removeAll { uploadRefs.contains($0.upload.clientRef.lowercased()) }
        let queuedAt = Date()
        pending.append(contentsOf: uploads.map {
            PendingFamilyCloudGuardianTaskUpsert(
                mutationRef: guardianMutationRef([$0]),
                upload: $0,
                queuedAt: queuedAt
            )
        })
        syncState.pendingGuardianTaskUpserts = pending
        guard persistSyncState() else { return false }
        lastSyncError = nil
        return true
    }

    func hasCloudTask(for assignmentId: UUID) -> Bool {
        cloudTasks.contains { $0.clientRef.lowercased() == assignmentId.uuidString.lowercased() }
    }

    func reserveScreenTimeRedemption(
        _ receipt: FamilyScreenTimeRedemptionReceipt
    ) async throws -> FamilyScreenTimeRedemptionReservation {
        guard isChildDevice, let token = childDeviceToken else {
            throw FamilyCloudClientError.server("child_device_session_required")
        }
        return try await client.reserveScreenTimeRedemption(token: token, receipt: receipt)
    }

    func commitScreenTimeRedemption(
        reservationID: String,
        receipt: FamilyScreenTimeRedemptionReceipt,
        local: LocalFamilyStore
    ) async throws -> FamilyScreenTimeRedemptionReservation {
        guard isChildDevice, let token = childDeviceToken else {
            throw FamilyCloudClientError.server("child_device_session_required")
        }
        let result = try await client.commitScreenTimeRedemption(
            token: token,
            reservationID: reservationID,
            receipt: receipt
        )
        local.applyCloudGrowthPointBalance(result.balance, pendingDelta: pendingPointDelta)
        return result
    }

    func cancelScreenTimeRedemption(
        reservationID: String,
        local: LocalFamilyStore
    ) async throws -> FamilyScreenTimeRedemptionReservation {
        guard isChildDevice, let token = childDeviceToken else {
            throw FamilyCloudClientError.server("child_device_session_required")
        }
        let result = try await client.cancelScreenTimeRedemption(
            token: token,
            reservationID: reservationID
        )
        local.applyCloudGrowthPointBalance(result.balance, pendingDelta: pendingPointDelta)
        return result
    }

    /// 设备解锁成功后登记积分消费。mutationRef/sourceRef 来自该次真实解锁会话，
    /// 云端唯一约束保证重试不会重复扣分。
    @discardableResult
    func queuePointMutation(
        mutationRef: String,
        kind: FamilyCloudPointMutationKind,
        delta: Int,
        sourceRef: String,
        local: LocalFamilyStore
    ) -> Bool {
        guard isChildDevice, delta != 0 else { return false }
        var pending = syncState.pendingPointMutations ?? []
        let alreadyKnown =
            pending.contains(where: { $0.mutationRef == mutationRef }) ||
            (syncState.acknowledgedPointMutationRefs ?? []).contains(mutationRef) ||
            (syncState.failedPointMutations ?? []).contains(where: { $0.mutationRef == mutationRef })
        if alreadyKnown {
            guard let token = childDeviceToken else { return true }
            Task {
                await flushPendingPointMutations(token: token, into: local)
                await flushPendingActivityEvents(token: token)
            }
            return true
        }
        pending.append(PendingFamilyCloudPointMutation(
            mutationRef: mutationRef,
            kind: kind,
            delta: delta,
            sourceRef: sourceRef,
            queuedAt: Date()
        ))
        syncState.pendingPointMutations = pending
        guard persistSyncState() else { return false }
        guard let token = childDeviceToken else { return true }
        Task {
            await flushPendingPointMutations(token: token, into: local)
            await flushPendingActivityEvents(token: token)
        }
        return true
    }

    /// Records elapsed authorized time after a Screen Time window actually ends.
    /// Apple does not expose exact foreground seconds for arbitrary selected apps, so this is
    /// explicitly the elapsed authorization window, not claimed foreground usage.
    @discardableResult
    func queueScreenTimeAuthorizationReceipt(
        _ receipt: RewardSessionReceipt
    ) -> Bool {
        guard receipt.consumedMinutes > 0 else { return true }
        let sessionRef = (
            receipt.sessionID?.uuidString ??
                receipt.id.uuidString
        ).lowercased()
        return queueActivityEvent(
            clientRef: "screen-time-complete:\(sessionRef)",
            kind: .screenTime,
            title: "App Authorized Time",
            durationSeconds: receipt.consumedMinutes * 60,
            resourceRef: Self.screenTimeResourceRef(
                authority: receipt.resolvedAuthority,
                appUsageRef: receipt.appUsageRef
            )
        )
    }

    static func screenTimeResourceRef(
        authority: ScreenTimeGrantAuthority,
        appUsageRef: String?
    ) -> String {
        let prefix = "authority:\(authority.rawValue)"
        guard let appUsageRef,
              appUsageRef.range(
                  of: "^app:[a-f0-9]{32}$",
                  options: .regularExpression
              ) != nil else {
            return prefix
        }
        return "\(prefix):\(appUsageRef)"
    }

    @discardableResult
    func queueActivityEvent(
        clientRef: String = "activity:\(UUID().uuidString.lowercased())",
        kind: FamilyCloudActivityKind,
        title: String,
        durationSeconds: Int,
        progressPercent: Double? = nil,
        resourceRef: String? = nil
    ) -> Bool {
        guard isChildDevice else { return false }
        appendActivityEvent(
            clientRef: clientRef,
            kind: kind,
            title: title,
            durationSeconds: durationSeconds,
            progressPercent: progressPercent,
            resourceRef: resourceRef
        )
        guard persistSyncState() else { return false }
        guard let token = childDeviceToken else { return true }
        Task { await flushPendingActivityEvents(token: token) }
        return true
    }

    private func appendActivityEvent(
        clientRef: String,
        kind: FamilyCloudActivityKind,
        title: String,
        durationSeconds: Int,
        progressPercent: Double?,
        resourceRef: String?
    ) {
        var pending = syncState.pendingActivityEvents ?? []
        guard !pending.contains(where: { $0.clientRef == clientRef }),
              !(syncState.acknowledgedActivityEventRefs ?? []).contains(clientRef) else {
            return
        }
        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        pending.append(PendingFamilyCloudActivityEvent(
            clientRef: clientRef,
            kind: kind,
            displayName: String((safeTitle.isEmpty ? "Octo Teacher activity" : safeTitle).prefix(120)),
            durationSeconds: min(12 * 60 * 60, max(0, durationSeconds)),
            progressPercent: progressPercent.map { Int(min(100, max(0, $0)).rounded()) },
            resourceRef: resourceRef,
            occurredAt: ISO8601DateFormatter().string(from: Date())
        ))
        syncState.pendingActivityEvents = pending
    }
    var deviceName: String { UIDevice.current.name.isEmpty ? "iPhone" : UIDevice.current.name }

    private var usesSchoolEmergencyUITestFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-OctoTeacherUITestSchoolEmergencyFlow")
        #else
        false
        #endif
    }

    func bootstrap() async {
        if usesSchoolEmergencyUITestFixture {
            recordSyncSuccess()
            return
        }
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if let token = guardianToken {
                let status = try await client.loadGuardianSession(token: token)
                guardian = status.guardian
                family = status.family
                if let snapshot = status.family {
                    _ = try await refreshGuardianSnapshotIfNeeded(
                        token: token,
                        familyId: snapshot.family.id,
                        force: cloudTasks.isEmpty
                    )
                    _ = try await pullGuardianChanges(
                        token: token,
                        familyId: snapshot.family.id,
                        from: syncState.guardianCursors[snapshot.family.id] ?? 0
                    )
                }
            } else if let token = childDeviceToken {
                childDeviceProfile = try await client.loadChildProfile(token: token)
                childDeviceName = childDeviceProfile?.displayName
                childAICapabilities = (try? await client.loadChildAICapabilities(token: token)) ?? .unavailable
                _ = try await refreshChildSnapshotIfNeeded(token: token, force: cloudTasks.isEmpty)
                _ = try await pullChildChanges(token: token, from: syncState.childCursor)
                await flushPendingChildWithdrawals(token: token)
                await flushPendingChildSubmissions(token: token)
                await flushPendingActivityEvents(token: token)
            }
            message = nil
            recordSyncSuccess()
        } catch FamilyCloudClientError.server(let code)
            where childDeviceToken != nil &&
                (code == "child_device_rebind_required" || code == "child_device_session_required") {
            requireChildDeviceRebind()
        } catch {
            message = error.localizedDescription
            lastSyncError = error.localizedDescription
        }
    }

    func startEmailSignIn() async throws -> EmailDeviceLoginStart {
        isWorking = true
        defer { isWorking = false }
        let request = try await client.startEmailDeviceSession(
            deviceRef: devicePublicRef,
            deviceName: deviceName
        )
        setMessage(
            "请在网页中登录邮箱并批准这台手机。",
            "Sign in with your email on the website and approve this phone."
        )
        return request
    }

    @discardableResult
    func completeEmailSignIn(requestToken: String) async throws -> Bool {
        isWorking = true
        defer { isWorking = false }
        let response = try await client.exchangeEmailDeviceSession(
            requestToken: requestToken,
            deviceRef: devicePublicRef
        )
        guard response.status == "complete" else {
            setMessage(
                "网页还没有批准这台手机。批准后再点一次“完成连接”。",
                "This phone has not been approved on the website yet. Approve it, then tap Finish Connecting again."
            )
            return false
        }
        guard let token = response.sessionToken, let signedInGuardian = response.guardian,
              secrets.save(token, account: Account.guardian) else {
            throw FamilyCloudClientError.server("session_keychain_save_failed")
        }
        guardian = signedInGuardian
        family = response.family
        setMessage("邮箱账号已连接。", "Email account connected.")
        return true
    }

    func createFamily(from local: LocalFamilyStore) async throws {
        guard let token = guardianToken else { throw FamilyCloudClientError.server("unauthorized") }
        isWorking = true
        defer { isWorking = false }
        family = try await client.createFamily(
            token: token,
            displayName: local.familyNetwork.familyName,
            deviceName: deviceName,
            children: local.children.map {
                FamilyCreateChild(
                    clientRef: $0.id.uuidString.lowercased(),
                    displayName: $0.name,
                    birthYear: Calendar(identifier: .gregorian).component(.year, from: Date()) - $0.age,
                    preReaderMode: $0.isPreReader,
                    interfaceLanguage: local.childInterfaceLanguage(for: $0.id),
                    contentLanguage: local.effectiveContentLanguage(for: $0.id),
                    dailyLimitMinutes: $0.dailyLimitMinutes,
                    exchangePolicy: local.policy(for: $0.id)
                )
            }
        )
        // This install created an empty cloud task set, so subsequent local tasks are
        // unambiguously new guardian intent rather than migration cache.
        syncState.guardianTaskBaselineEstablished = true
        syncState.pendingGuardianTaskUpserts = []
        syncState.cachedTasks = []
        cloudTasks = []
        guard persistSyncState() else {
            throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
        }
        setMessage("家庭云同步已启用。", "Family Cloud Sync is enabled.")
    }

    func issueInvite(kind: String, childId: String? = nil) async throws -> FamilyCloudInvite {
        guard let token = guardianToken, let family else { throw FamilyCloudClientError.server("unauthorized") }
        isWorking = true
        defer { isWorking = false }
        return try await client.issueInvite(token: token, familyId: family.family.id, kind: kind, childId: childId)
    }

    /// Explicitly creates a child in Family Cloud, then reconciles the local guardian cache.
    /// Local-only seed profiles are never treated as create intent.
    func addGuardianChild(name: String, age: Int, local: LocalFamilyStore) async throws {
        guard let token = guardianToken, let currentFamily = family else {
            throw FamilyCloudClientError.server("unauthorized")
        }
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { throw FamilyCloudClientError.server("invalid_child_name") }
        guard !currentFamily.children.contains(where: {
            $0.displayName.caseInsensitiveCompare(displayName) == .orderedSame
        }) else { throw FamilyCloudClientError.server("duplicate_child_name") }

        isWorking = true
        defer { isWorking = false }
        let childID = UUID()
        let request = FamilyCreateChild(
            clientRef: childID.uuidString.lowercased(),
            displayName: displayName,
            birthYear: Calendar(identifier: .gregorian).component(.year, from: Date()) - max(3, min(18, age)),
            preReaderMode: age <= 7,
            interfaceLanguage: local.settings.resolvedChildInterfaceLanguage,
            contentLanguage: local.settings.language,
            dailyLimitMinutes: 60,
            exchangePolicy: .default
        )
        let refreshed = try await client.createChild(
            token: token,
            familyId: currentFamily.family.id,
            child: request
        )
        family = refreshed
        local.applyCloudFamilyIdentity(refreshed)
        local.applyCloudGuardianProfiles(
            refreshed,
            preservingClientRefs: Set(syncState.pendingGuardianProfileClientRefs ?? [])
        )
        local.setActiveChild(childID)
        recordSyncSuccess()
        setMessage("已添加孩子档案。", "Child profile added.")
    }

    /// Soft-archives a child profile. Approved history and the point ledger remain auditable;
    /// active devices and unfinished work are revoked by the server transaction.
    func archiveGuardianChild(childID: UUID, local: LocalFamilyStore) async throws {
        guard let token = guardianToken, let currentFamily = family else {
            throw FamilyCloudClientError.server("unauthorized")
        }
        guard currentFamily.children.count > 1 else {
            throw FamilyCloudClientError.server("family_must_keep_one_child")
        }
        guard let cloudChild = currentFamily.children.first(where: {
            $0.clientRef?.lowercased() == childID.uuidString.lowercased()
        }) else { throw FamilyCloudClientError.server("child_profile_not_found") }

        isWorking = true
        defer { isWorking = false }
        _ = try await client.archiveChild(
            token: token,
            familyId: currentFamily.family.id,
            childId: cloudChild.id
        )
        guard let refreshed = try await client.loadGuardianSession(token: token).family else {
            throw FamilyCloudClientError.server("family_not_found")
        }
        family = refreshed
        local.applyCloudFamilyIdentity(refreshed)
        local.applyCloudGuardianProfiles(
            refreshed,
            preservingClientRefs: Set(syncState.pendingGuardianProfileClientRefs ?? [])
        )
        recordSyncSuccess()
        setMessage("孩子档案已归档。", "Child profile archived.")
    }

    func claim(_ invite: FamilyCloudJoinPayload) async throws {
        isWorking = true
        defer { isWorking = false }
        let response = try await client.claimInvite(
            invite,
            guardianToken: guardianToken,
            deviceRef: devicePublicRef,
            deviceName: deviceName
        )
        if response.kind == "child_device", let token = response.deviceSessionToken {
            secrets.delete(account: Account.guardian)
            guardian = nil
            family = nil
            guard secrets.save(token, account: Account.child) else {
                throw FamilyCloudClientError.server("session_keychain_save_failed")
            }
            secrets.delete(account: Account.childRebind)
            childDeviceRebindRequired = false
            childDeviceName = response.child?.displayName
            childAICapabilities = (try? await client.loadChildAICapabilities(token: token)) ?? .unavailable
            syncState.childCursor = 0
            syncState.pendingChildSubmissions = []
            syncState.pendingPointMutations = []
            syncState.pendingActivityEvents = []
            syncState.pendingGuardianDecisions = []
            syncState.pendingGuardianTaskUpserts = []
            syncState.guardianTaskBaselineEstablished = false
            syncState.cachedTasks = []
            syncState.childSnapshotDate = nil
            cloudTasks = []
            guard persistSyncState() else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            _ = try await refreshChildSnapshotIfNeeded(token: token, force: true)
        } else if let snapshot = response.family {
            family = snapshot
        } else if let token = guardianToken {
            family = try await client.loadGuardianSession(token: token).family
        }
        setMessage("这台手机已经加入家庭。", "This phone has joined the family.")
    }

    private func requireChildDeviceRebind() {
        secrets.delete(account: Account.child)
        _ = secrets.save("1", account: Account.childRebind)
        childDeviceRebindRequired = true
        childAICapabilities = .unavailable
        childSurface = nil
        lastSyncError = FamilyCloudClientError.server("child_device_rebind_required").localizedDescription
        setMessage(
            "孩子端接口已经升级，请让家长生成新的孩子设备二维码并重新绑定。",
            "The child-device protocol changed. Ask a guardian for a new child-device QR code and rebind."
        )
    }

    func syncGuardianTasks(
        from local: LocalFamilyStore,
        forceFullSnapshot: Bool = false
    ) async throws {
        guard let token = guardianToken, var family else { throw FamilyCloudClientError.server("unauthorized") }
        guard !isGuardianRefreshInFlight else {
            if forceFullSnapshot { guardianForceRefreshRequested = true }
            return
        }
        isGuardianRefreshInFlight = true
        let localAssignmentsBeforePull = local.assignments
        let hadTaskBaseline = syncState.guardianTaskBaselineEstablished == true
        var requiresGuardianReReview = false
        isWorking = true
        defer {
            let shouldForceRefresh = guardianForceRefreshRequested
            guardianForceRefreshRequested = false
            isWorking = false
            isGuardianRefreshInFlight = false
            if shouldForceRefresh {
                Task { [weak self] in
                    try? await self?.syncGuardianTasks(from: local, forceFullSnapshot: true)
                }
            }
        }
        do {
            guard applyPendingRemovedTasks(into: local) else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            // Family name, members, devices and balances are full cloud snapshots. Refresh
            // them before task deltas so stale local household metadata can never be pushed.
            if let refreshed = try await client.loadGuardianSession(token: token).family {
                family = refreshed
                self.family = refreshed
                local.applyCloudFamilyIdentity(refreshed)
            }
            let snapshotTasks = try await refreshGuardianSnapshotIfNeeded(
                token: token,
                familyId: family.family.id,
                force: forceFullSnapshot || cloudTasks.isEmpty,
                authoritative: forceFullSnapshot
            )
            let startingCursor = syncState.guardianCursors[family.family.id] ?? 0
            let remoteChanges = try await pullGuardianChanges(
                token: token,
                familyId: family.family.id,
                from: startingCursor
            )
            guard applyPendingRemovedTasks(into: local) else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            var decisionReconciliation = try reconcilePendingGuardianDecisions()
            var decisionsRequiringReview = decisionReconciliation.requiresReview
            requiresGuardianReReview = !decisionsRequiringReview.isEmpty
            local.applyCloudFamilyTasks(
                snapshotTasks + remoteChanges + cloudTasks,
                familySnapshot: family,
                childName: nil,
                preservingLocalStatusesFor: Set(decisionReconciliation.active.map(\.assignmentId))
            )

            // Before the first authoritative baseline, every pre-existing local task is cache
            // or migration residue unless the cloud snapshot contains it. Removing those rows
            // prevents an old guardian phone from republishing work that was already revoked.
            if !hadTaskBaseline {
                let authoritativeRefs = Set(cloudTasks.map { $0.clientRef.lowercased() })
                let protectedPendingRefs = Set((syncState.pendingGuardianTaskUpserts ?? []).map {
                    $0.upload.clientRef.lowercased()
                })
                let staleLocalRefs = Set(localAssignmentsBeforePull.compactMap { assignment -> String? in
                    let ref = assignment.id.uuidString.lowercased()
                    return authoritativeRefs.contains(ref) || protectedPendingRefs.contains(ref) ? nil : ref
                })
                local.removeCloudFamilyTasks(clientRefs: staleLocalRefs)
            }

            // Pull profile changes made by another guardian first, but preserve explicit local
            // edits until they have reached the cloud.
            var profileSyncFailed = false
            var pendingProfileFields = syncState.pendingGuardianProfileFields ?? [:]
            var pendingProfileRefs = Set(syncState.pendingGuardianProfileClientRefs ?? [])
                .union(pendingProfileFields.keys)
            var pendingProfileGenerations = syncState.pendingGuardianProfileGenerations ?? [:]
            local.applyCloudGuardianProfiles(family, preservingClientRefs: pendingProfileRefs)
            for child in local.children {
                let clientRef = child.id.uuidString.lowercased()
                let uploadingGeneration = pendingProfileGenerations[clientRef] ?? 0
                do {
                    if let cloudChild = family.children.first(where: {
                        $0.clientRef?.lowercased() == clientRef
                    }) {
                        guard pendingProfileRefs.contains(clientRef) else { continue }
                        let changedFields = Set(
                            pendingProfileFields[clientRef]
                                ?? Array(FamilyCloudGuardianProfileField.legacySafeFields)
                        )
                        family = try await updateChildProfileWithConflictRetry(
                            token: token,
                            family: family,
                            cloudChild: cloudChild,
                            localChild: child,
                            local: local,
                            changedFields: changedFields
                        )
                    } else {
                        // Cloud profiles are authoritative. A local cache row may create a cloud
                        // child only when the parent explicitly queued that profile. Without this
                        // gate, old seed children are silently uploaded and resurrected forever.
                        guard pendingProfileRefs.contains(clientRef) else { continue }
                        let request = makeGuardianProfileRequest(
                            localChild: child,
                            local: local,
                            cloudChild: nil,
                            changedFields: Set(FamilyCloudGuardianProfileField.allCases)
                        )
                        family = try await client.createChild(
                            token: token,
                            familyId: family.family.id,
                            child: request
                        )
                    }
                    // Only acknowledge the intent generation that produced this request.
                    // A save queued during an await has a newer generation and must remain
                    // pending for the next pass, even when it edits the same field again.
                    let currentGeneration = syncState.pendingGuardianProfileGenerations?[clientRef] ?? 0
                    if currentGeneration == uploadingGeneration {
                        var currentRefs = Set(syncState.pendingGuardianProfileClientRefs ?? [])
                        currentRefs.remove(clientRef)
                        var currentFields = syncState.pendingGuardianProfileFields ?? [:]
                        currentFields[clientRef] = nil
                        var currentGenerations = syncState.pendingGuardianProfileGenerations ?? [:]
                        currentGenerations[clientRef] = nil
                        syncState.pendingGuardianProfileClientRefs = currentRefs.sorted()
                        syncState.pendingGuardianProfileFields = currentFields
                        syncState.pendingGuardianProfileGenerations = currentGenerations
                    }
                    guard persistSyncState() else {
                        throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
                    }
                    pendingProfileFields = syncState.pendingGuardianProfileFields ?? [:]
                    pendingProfileRefs = Set(syncState.pendingGuardianProfileClientRefs ?? [])
                        .union(pendingProfileFields.keys)
                    pendingProfileGenerations = syncState.pendingGuardianProfileGenerations ?? [:]
                } catch let FamilyCloudClientError.server(code) where code == "child_profile_archived" {
                    var currentRefs = Set(syncState.pendingGuardianProfileClientRefs ?? [])
                    currentRefs.remove(clientRef)
                    var currentFields = syncState.pendingGuardianProfileFields ?? [:]
                    currentFields[clientRef] = nil
                    var currentGenerations = syncState.pendingGuardianProfileGenerations ?? [:]
                    currentGenerations[clientRef] = nil
                    syncState.pendingGuardianProfileClientRefs = currentRefs.sorted()
                    syncState.pendingGuardianProfileFields = currentFields
                    syncState.pendingGuardianProfileGenerations = currentGenerations
                    if !persistSyncState() {
                        profileSyncFailed = true
                    }
                    pendingProfileFields = syncState.pendingGuardianProfileFields ?? [:]
                    pendingProfileRefs = Set(syncState.pendingGuardianProfileClientRefs ?? [])
                        .union(pendingProfileFields.keys)
                    pendingProfileGenerations = syncState.pendingGuardianProfileGenerations ?? [:]
                } catch {
                    profileSyncFailed = true
                }
            }
            self.family = family
            local.applyCloudFamilyIdentity(family)
            local.applyCloudGuardianProfiles(family, preservingClientRefs: pendingProfileRefs)

            let decisionsByAssignment = Dictionary(uniqueKeysWithValues: decisionReconciliation.active.map {
                ($0.assignmentId, $0)
            })
            var queuedUploads = syncState.pendingGuardianTaskUpserts ?? []
            for pending in decisionReconciliation.active {
                guard let current = cloudTasks.first(where: {
                    $0.clientRef.lowercased() == pending.assignmentId.uuidString.lowercased()
                }) else { continue }
                let upload = guardianDecisionUpload(cloud: current, decision: pending, family: family)
                queuedUploads.append(PendingFamilyCloudGuardianTaskUpsert(
                    mutationRef: guardianMutationRef([upload]),
                    upload: upload,
                    queuedAt: pending.queuedAt
                ))
            }
            var cursor = syncState.guardianCursors[family.family.id] ?? 0
            for pending in queuedUploads {
                let page: FamilyCloudTaskPage
                do {
                    page = try await client.syncTasks(
                        token: token,
                        familyId: family.family.id,
                        mutationRef: pending.mutationRef,
                        cursor: cursor,
                        tasks: [pending.upload]
                    )
                } catch FamilyCloudClientError.server(let code) where code == "stale_task_version" {
                    _ = try await refreshGuardianSnapshotIfNeeded(
                        token: token,
                        familyId: family.family.id,
                        force: true
                    )
                    decisionReconciliation = try reconcilePendingGuardianDecisions()
                    decisionsRequiringReview.formUnion(decisionReconciliation.requiresReview)
                    requiresGuardianReReview = !decisionsRequiringReview.isEmpty
                    local.applyCloudFamilyTasks(
                        cloudTasks,
                        familySnapshot: family,
                        childName: nil,
                        authoritativeCloudBalance: family.children.contains { $0.growthPointBalance != nil },
                        preservingLocalStatusesFor: Set(decisionReconciliation.active.map(\.assignmentId))
                    )
                    // The cloud changed after this intent was queued. Fail closed: discard the
                    // stale body after the authoritative refresh instead of retrying forever or
                    // rebasing an old title/status/point value over newer family data.
                    syncState.pendingGuardianTaskUpserts?.removeAll {
                        $0.mutationRef == pending.mutationRef
                    }
                    guard persistSyncState() else {
                        throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
                    }
                    throw FamilyCloudClientError.server(code)
                }
                guard mergeCloudTasks(page.tasks) else {
                    throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
                }
                syncState.pendingGuardianTaskUpserts?.removeAll { $0.mutationRef == pending.mutationRef }
                cursor = max(cursor, page.cursor)
                syncState.guardianCursors[family.family.id] = cursor
                guard persistSyncState() else {
                    throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
                }
                if page.hasMore {
                    _ = try await pullGuardianChanges(token: token, familyId: family.family.id, from: cursor)
                    cursor = syncState.guardianCursors[family.family.id] ?? cursor
                }
            }
            syncState.guardianTaskBaselineEstablished = true
            guard persistSyncState() else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            decisionReconciliation = try reconcilePendingGuardianDecisions()
            decisionsRequiringReview.formUnion(decisionReconciliation.requiresReview)
            requiresGuardianReReview = !decisionsRequiringReview.isEmpty
            if decisionsByAssignment.values.contains(where: { $0.status == "approved" }),
               let refreshedSession = try? await client.loadGuardianSession(token: token),
               let refreshed = refreshedSession.family {
                family = refreshed
                self.family = refreshed
                local.applyCloudGuardianProfiles(
                    refreshed,
                    preservingClientRefs: Set(syncState.pendingGuardianProfileClientRefs ?? [])
                )
            }
            // Keep the just-made guardian decision authoritative for the entire sync pass.
            // A lagging task page must not turn an approved task back into "submitted" and
            // send the guardian through the approval flow again.
            local.applyCloudFamilyTasks(
                cloudTasks,
                familySnapshot: family,
                childName: nil,
                authoritativeCloudBalance: family.children.contains { $0.growthPointBalance != nil },
                preservingLocalStatusesFor: Set(
                    decisionReconciliation.active.map(\.assignmentId)
                )
            )
            try? await refreshGuardianActivitySummaries(for: local)
            recordSyncSuccess()
            if requiresGuardianReReview {
                setMessage(
                    "任务证明已更新，请基于最新证明重新审核。",
                    "Task evidence changed. Please review the latest evidence again."
                )
            } else if profileSyncFailed {
                setMessage(
                    "任务已同步；部分孩子设置会自动重试。",
                    "Tasks synced. Some child settings will retry automatically."
                )
            } else {
                setMessage(
                    "已同步 \(cloudTasks.count) 项任务。",
                    "Synced \(cloudTasks.count) tasks."
                )
            }
        } catch {
            recordSyncFailure(error)
            if requiresGuardianReReview {
                setMessage(
                    "任务证明已更新，请基于最新证明重新审核。",
                    "Task evidence changed. Please review the latest evidence again."
                )
            }
            throw error
        }
    }

    func refreshGuardianActivitySummaries(for local: LocalFamilyStore) async throws {
        guard let token = guardianToken, let family else {
            throw FamilyCloudClientError.server("unauthorized")
        }
        let requestedChildID = local.activeChildId
        let timeZone = TimeZone.current
        let localDate = Self.activityDateIdentifier(for: Date(), timeZone: timeZone)
        async let historyActivity = loadGuardianActivitySummary(
            token: token,
            family: family,
            localChildID: requestedChildID,
            days: 90,
            localDate: nil,
            timeZone: timeZone.identifier
        )
        async let todayActivity = loadGuardianActivitySummary(
            token: token,
            family: family,
            localChildID: requestedChildID,
            days: 1,
            localDate: localDate,
            timeZone: timeZone.identifier
        )
        let (history, today) = try await (historyActivity, todayActivity)

        // A guardian can switch children while either request is in flight.
        // Never let an older child's response overwrite the active child's view.
        guard local.activeChildId == requestedChildID else { return }
        guardianActivitySummary = history
        guardianTodayActivitySummary = today
        guardianActivityLocalChildID = requestedChildID
    }

    private func loadGuardianActivitySummary(
        token: String,
        family: FamilyCloudSnapshot,
        localChildID: UUID,
        days: Int,
        localDate: String?,
        timeZone: String
    ) async throws -> FamilyCloudActivitySummary? {
        let clientRef = localChildID.uuidString.lowercased()
        guard let cloudChild = family.children.first(where: {
            $0.clientRef?.lowercased() == clientRef
        }) else { return nil }
        return try await client.loadGuardianActivitySummary(
            token: token,
            familyId: family.family.id,
            childId: cloudChild.id,
            days: days,
            localDate: localDate,
            timeZone: timeZone
        )
    }

    private static func activityDateIdentifier(
        for date: Date,
        timeZone: TimeZone
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    /// 把家长明确允许的 BYOK 能力加密托管到家庭云中继。
    /// 原始密钥不会出现在家庭快照、任务、孩子设备或日志中。
    func syncGuardianAI(from provider: ParentAIProviderStore) async throws {
        guard let token = guardianToken, let family else { return }
        guard let provisioning = provider.familyAIProviderProvisioning else { return }
        _ = try await client.configureFamilyAI(
            token: token,
            familyId: family.family.id,
            provisioning: provisioning
        )
    }

    func chatChildAICompanion(
        request: AICompanionChatRequest,
        using service: AICompanionChatService = AICompanionChatService()
    ) async throws -> AICompanionChatTurn {
        guard let token = childDeviceToken, isChildAIRelayReady else {
            throw AICompanionChatServiceError.notConfigured
        }
        if request.containsImages && !isChildAIImageRelayReady {
            throw AICompanionChatServiceError.imageUploadNotAllowed
        }
        let relayRequest = try service.familyRelayRequest(for: request)
        let response = try await client.completeChildAIChat(token: token, request: relayRequest)
        return try service.parseFamilyRelayResponse(response, request: request)
    }

    func transcribeChildAIAudio(at audioFileURL: URL) async throws -> String {
        guard let token = childDeviceToken, isChildAIVoiceRelayReady else {
            throw AudioTranscriptionError.notConfigured
        }
        guard let data = try? Data(contentsOf: audioFileURL), !data.isEmpty else {
            throw AudioTranscriptionError.audioUnreadable
        }
        guard data.count <= 3_000_000 else {
            throw AudioTranscriptionError.audioUnreadable
        }
        defer { try? FileManager.default.removeItem(at: audioFileURL) }
        do {
            return try await client.transcribeChildAIAudio(
                token: token,
                request: FamilyAITranscriptionRelayRequest(
                    mimeType: "audio/m4a",
                    base64Data: data.base64EncodedString()
                )
            )
        } catch {
            throw AudioTranscriptionError.requestFailed(statusCode: nil)
        }
    }

    func refreshChildTasks(
        into local: LocalFamilyStore,
        forceFullSnapshot: Bool = false
    ) async throws {
        guard let token = childDeviceToken else { throw FamilyCloudClientError.server("unauthorized") }
        guard !isChildRefreshInFlight else {
            if forceFullSnapshot { childForceRefreshRequested = true }
            return
        }
        isChildRefreshInFlight = true
        isWorking = true
        defer {
            let shouldForceRefresh = childForceRefreshRequested
            childForceRefreshRequested = false
            isWorking = false
            isChildRefreshInFlight = false
            if shouldForceRefresh {
                Task { [weak self] in
                    try? await self?.refreshChildTasks(into: local, forceFullSnapshot: true)
                }
            }
        }
        do {
            guard applyPendingRemovedTasks(into: local) else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            childDeviceProfile = try await client.loadChildProfile(token: token)
            childDeviceName = childDeviceProfile?.displayName
            childAICapabilities = (try? await client.loadChildAICapabilities(token: token)) ?? .unavailable
            if let childDeviceProfile {
                local.applyCloudFamilyIdentity(childDeviceProfile)
                local.applyCloudChildProfile(
                    childDeviceProfile,
                    pendingPointDelta: pendingPointDelta
                )
            }
            let snapshotTasks = try await refreshChildSnapshotIfNeeded(
                token: token,
                force: forceFullSnapshot || cloudTasks.isEmpty,
                authoritative: forceFullSnapshot
            )
            let changes = try await pullChildChanges(token: token, from: syncState.childCursor)
            guard applyPendingRemovedTasks(into: local) else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            await flushPendingChildWithdrawals(token: token)
            guard recoverLocallySubmittedTasks(in: local) else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            await flushPendingChildSubmissions(token: token)
            await flushPendingPointMutations(token: token, into: local)
            await flushPendingActivityEvents(token: token)
            let pendingChildSubmissionIDs = Set(syncState.pendingChildSubmissions.map(\.localAssignmentId))
            let allTasks = mergedTaskValues(snapshotTasks + changes + cloudTasks)
            await materializeCloudBooks(from: allTasks, into: local)
            let unavailable = allTasks.filter { !isTaskExecutableOnDevice($0, local: local) }
            local.quarantineUnavailableCloudTasks(unavailable)
            local.applyCloudFamilyTasks(
                allTasks.filter { isTaskExecutableOnDevice($0, local: local) },
                familySnapshot: nil,
                childName: childDeviceName,
                authoritativeCloudBalance: childDeviceProfile?.growthPointBalance != nil,
                preservingLocalStatusesFor: pendingChildSubmissionIDs
            )
            recordSyncSuccess()
            setMessage("孩子任务已更新。", "Child tasks are up to date.")
        } catch {
            recordSyncFailure(error)
            throw error
        }
    }

    /// Refreshes the child surface from the same cloud authority on both device roles.
    /// A manual refresh requests an authoritative snapshot so a guardian preview and the
    /// child's own phone cannot keep rendering different historical task caches.
    func refreshChildSurface(
        into local: LocalFamilyStore,
        forceFullSnapshot: Bool = false
    ) async throws {
        if isChildDevice {
            guard let token = childDeviceToken else {
                throw FamilyCloudClientError.server("child_device_session_unavailable")
            }
            guard !isChildRefreshInFlight else {
                if forceFullSnapshot { childForceRefreshRequested = true }
                return
            }
            isChildRefreshInFlight = true
            isWorking = true
            defer {
                let shouldForceRefresh = childForceRefreshRequested
                childForceRefreshRequested = false
                isWorking = false
                isChildRefreshInFlight = false
                if shouldForceRefresh {
                    Task { [weak self] in
                        try? await self?.refreshChildSurface(into: local, forceFullSnapshot: true)
                    }
                }
            }
            do {
                try await flushPendingChildWrites(token: token, into: local)
                childAICapabilities = (try? await client.loadChildAICapabilities(token: token)) ?? .unavailable
                let surface = try await client.loadChildSurface(token: token)
                await applyChildSurface(surface, into: local, familySnapshot: nil)
            } catch {
                recordSyncFailure(error)
                throw error
            }
        } else {
            guard let token = guardianToken, var family else {
                throw FamilyCloudClientError.server("guardian_session_unavailable")
            }
            let requestedLocalChildID = local.activeChildId
            guard !isGuardianRefreshInFlight else {
                if forceFullSnapshot { guardianForceRefreshRequested = true }
                return
            }
            isGuardianRefreshInFlight = true
            isWorking = true
            defer {
                let shouldForceRefresh = guardianForceRefreshRequested
                guardianForceRefreshRequested = false
                isWorking = false
                isGuardianRefreshInFlight = false
                if shouldForceRefresh {
                    Task { [weak self] in
                        try? await self?.refreshChildSurface(into: local, forceFullSnapshot: true)
                    }
                }
            }
            do {
                if let refreshed = try await client.loadGuardianSession(token: token).family {
                    family = refreshed
                    self.family = refreshed
                    local.applyCloudFamilyIdentity(refreshed)
                    local.applyCloudGuardianProfiles(
                        refreshed,
                        preservingClientRefs: Set(syncState.pendingGuardianProfileClientRefs ?? [])
                    )
                }
                guard let child = cloudChild(for: requestedLocalChildID) else {
                    throw FamilyCloudClientError.server("child_profile_not_found")
                }
                let surface = try await client.loadGuardianChildSurface(
                    token: token,
                    familyId: family.family.id,
                    childId: child.id
                )
                await applyChildSurface(
                    surface,
                    into: local,
                    familySnapshot: family,
                    activateProfile: local.activeChildId == requestedLocalChildID
                )
            } catch {
                recordSyncFailure(error)
                throw error
            }
        }
    }

    /// Sends the child's durable outbox before reading the shared child surface. This method
    /// never materializes a second task projection into the UI; ChildSurface remains the only
    /// read model used by both the guardian preview and the child's own phone.
    private func flushPendingChildWrites(
        token: String,
        into local: LocalFamilyStore
    ) async throws {
        guard applyPendingRemovedTasks(into: local) else {
            throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
        }
        await flushPendingChildWithdrawals(token: token)
        guard recoverLocallySubmittedTasks(in: local) else {
            throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
        }
        await flushPendingChildSubmissions(token: token)
        await flushPendingPointMutations(token: token, into: local)
        await flushPendingActivityEvents(token: token)
    }

    /// Applies one server-authored child projection to both the guardian preview and child phone.
    /// Guardian refresh is deliberately read-only: only the task editor's explicit sync path may
    /// upload task mutations.
    private func applyChildSurface(
        _ surface: FamilyChildSurface,
        into local: LocalFamilyStore,
        familySnapshot: FamilyCloudSnapshot?,
        activateProfile: Bool = true
    ) async {
        childSurface = surface
        let incoming = surface.tasks.map(\.task)
        let targetServerChildID = surface.child.id
        let previousTargetRefs = Set(cloudTasks.compactMap { task in
            task.childProfileId == targetServerChildID ? task.clientRef.lowercased() : nil
        })
        let incomingRefs = Set(incoming.map { $0.clientRef.lowercased() })
        let targetLocalChildID = familySnapshot?.children.first(where: { $0.id == targetServerChildID })
            .flatMap(\.clientRef)
            .flatMap(UUID.init(uuidString:))
            ?? local.activeChildId
        let protectedLocalIDs = Set(syncState.pendingChildSubmissions.map(\.localAssignmentId))
            .union((syncState.pendingChildWithdrawals ?? []).map(\.localAssignmentId))
        let protectedGuardianRefs = Set((syncState.pendingGuardianTaskUpserts ?? []).map {
            $0.upload.clientRef.lowercased()
        })
        let staleLocalRefs = Set(local.assignments.compactMap { assignment -> String? in
            guard assignment.childId == targetLocalChildID else { return nil }
            let ref = assignment.id.uuidString.lowercased()
            guard !incomingRefs.contains(ref),
                  !protectedLocalIDs.contains(assignment.id),
                  !protectedGuardianRefs.contains(ref) else { return nil }
            return ref
        })
        let removedRefs = previousTargetRefs.subtracting(incomingRefs)
            .union(staleLocalRefs)
            .union(surface.sync.removedRefs.tasks.map { $0.lowercased() })
        local.removeCloudFamilyTasks(clientRefs: removedRefs)

        if familySnapshot == nil {
            cloudTasks = mergedTaskValues(incoming)
            syncState.childCursor = max(syncState.childCursor, surface.sync.taskCursor)
            syncState.childSnapshotDate = Date()
            childDeviceName = surface.child.displayName
        } else {
            let otherChildren = cloudTasks.filter { $0.childProfileId != targetServerChildID }
            cloudTasks = mergedTaskValues(otherChildren + incoming)
            if let familyId = familySnapshot?.family.id {
                var snapshotDates = syncState.guardianSnapshotDates ?? [:]
                snapshotDates[familyId] = Date()
                syncState.guardianSnapshotDates = snapshotDates
            }
        }
        syncState.cachedTasks = cloudTasks
        _ = persistSyncState()

        local.applyCloudChildSurfaceProfile(
            surface.child,
            pendingPointDelta: isChildDevice ? pendingPointDelta : 0,
            makeActive: activateProfile
        )
        await materializeCloudBooks(from: incoming, into: local)
        let unavailable = incoming.filter { !isTaskExecutableOnDevice($0, local: local) }
        local.quarantineUnavailableCloudTasks(unavailable)
        let preserved: Set<UUID> = isChildDevice
            ? Set(syncState.pendingChildSubmissions.map(\.localAssignmentId))
            : []
        local.applyCloudFamilyTasks(
            incoming.filter { isTaskExecutableOnDevice($0, local: local) },
            familySnapshot: familySnapshot,
            childName: familySnapshot == nil ? surface.child.displayName : nil,
            authoritativeCloudBalance: true,
            preservingLocalStatusesFor: preserved
        )
        recordSyncSuccess()
        setMessage(
            "孩子首页已与家庭云同步。",
            "The child home is synced with the family cloud."
        )
    }

    /// 孩子真机可以修改自己的界面语言；云端档案仍是所有设备的权威值。
    /// 家长设备的本机预览语言不走这里，避免预览偏好覆盖孩子手机设置。
    func updateChildInterfaceLanguage(
        _ language: AppInterfaceLanguage,
        in local: LocalFamilyStore
    ) async throws {
        guard let token = childDeviceToken else {
            throw FamilyCloudClientError.server("child_device_session_unavailable")
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let profile = try await client.updateChildInterfaceLanguage(
                token: token,
                language: language
            )
            childDeviceProfile = profile
            childDeviceName = profile.displayName
            local.applyCloudFamilyIdentity(profile)
            local.applyCloudChildProfile(profile, pendingPointDelta: pendingPointDelta)
            recordSyncSuccess()
        } catch {
            recordSyncFailure(error)
            throw error
        }
    }

    func revokeDevice(_ device: FamilyCloudSnapshot.Device) async throws {
        guard let token = guardianToken, let family else { throw FamilyCloudClientError.server("unauthorized") }
        isWorking = true
        defer { isWorking = false }
        self.family = try await client.revokeDevice(token: token, familyId: family.family.id, deviceId: device.id)
    }

    func screenTimePolicy(for localChildID: UUID) -> FamilyScreenTimePolicy? {
        cloudChild(for: localChildID)?.screenTimePolicy
    }

    func screenTimeCatalog(for localChildID: UUID) -> FamilyScreenTimeCatalog? {
        guard let family,
              let child = cloudChild(for: localChildID),
              let catalog = child.screenTimeCatalog,
              family.devices.contains(where: { device in
                  device.role == "child" &&
                      device.status == "active" &&
                      device.requiresRebind != true &&
                      device.childProfileId == child.id &&
                      device.publicRef == catalog.sourceDevicePublicRef
              })
        else { return nil }
        return catalog
    }

    func screenTimeStatus(for localChildID: UUID) -> FamilyScreenTimeDeviceStatus? {
        cloudChild(for: localChildID)?.screenTimeStatus
    }

    func screenTimeEmergency(for localChildID: UUID) -> FamilyScreenTimeEmergency? {
        #if DEBUG
        if usesSchoolEmergencyUITestFixture, uiTestEmergencyChildID == localChildID {
            return uiTestEmergency
        }
        #endif
        if let profile = childDeviceProfile,
           profile.clientRef?.lowercased() == localChildID.uuidString.lowercased() {
            return profile.screenTimeEmergency
        }
        return cloudChild(for: localChildID)?.screenTimeEmergency
    }

    var pendingScreenTimeEmergencyChildIDs: [UUID] {
        #if DEBUG
        if usesSchoolEmergencyUITestFixture,
           uiTestEmergency?.isPendingGuardianDecision == true,
           let uiTestEmergencyChildID {
            return [uiTestEmergencyChildID]
        }
        #endif
        guard let family else { return [] }
        return family.children.compactMap { child in
            guard child.screenTimeEmergency?.isPendingGuardianDecision == true,
                  let clientRef = child.clientRef,
                  let localID = UUID(uuidString: clientRef) else { return nil }
            return localID
        }
    }

    func activeChildDevices(for localChildID: UUID) -> [FamilyCloudSnapshot.Device] {
        guard let family, let child = cloudChild(for: localChildID) else { return [] }
        return family.devices.filter { device in
            device.role == "child" &&
                device.status == "active" &&
                device.requiresRebind != true &&
                device.childProfileId == child.id
        }
    }

    func syncGuardianScreenTimePolicy(
        _ policy: FamilyScreenTimePolicy?,
        for localChildID: UUID
    ) async throws {
        guard let token = guardianToken, let family, let child = cloudChild(for: localChildID) else {
            throw FamilyCloudClientError.server("unauthorized")
        }
        self.family = try await client.updateScreenTimePolicy(
            token: token,
            familyId: family.family.id,
            childProfileId: child.id,
            policy: policy
        )
        recordSyncSuccess()
    }

    func syncChildScreenTimeStatus(_ status: FamilyScreenTimeDeviceStatus) async throws {
        guard let token = childDeviceToken else { throw FamilyCloudClientError.server("unauthorized") }
        childDeviceProfile = try await client.updateChildScreenTimeStatus(token: token, status: status)
        recordSyncSuccess()
    }

    @discardableResult
    func syncChildScreenTimeCatalog(
        _ catalog: FamilyScreenTimeCatalogUpload
    ) async throws -> FamilyScreenTimeCatalog? {
        guard let token = childDeviceToken else { throw FamilyCloudClientError.server("unauthorized") }
        childDeviceProfile = try await client.updateChildScreenTimeCatalog(
            token: token,
            catalog: catalog
        )
        recordSyncSuccess()
        return childDeviceProfile?.screenTimeCatalog
    }

    func registerChildPush(_ registration: FamilyRemotePushRegistration) async throws {
        guard let token = childDeviceToken else { throw FamilyCloudClientError.server("unauthorized") }
        childDeviceProfile = try await client.registerChildPush(
            token: token,
            registration: registration
        )
        recordSyncSuccess()
    }

    func sendGuardianScreenTimeControl(
        action: String,
        minutes: Int? = nil,
        for localChildID: UUID
    ) async throws {
        guard let token = guardianToken, let family, let child = cloudChild(for: localChildID) else {
            throw FamilyCloudClientError.server("unauthorized")
        }
        self.family = try await client.updateGuardianScreenTimeControl(
            token: token,
            familyId: family.family.id,
            childProfileId: child.id,
            action: action,
            minutes: minutes
        )
        recordSyncSuccess()
    }

    @discardableResult
    func submitChildScreenTimeEmergency(
        reason: String,
        minutes: Int = 30,
        requestId: String = "school:\(UUID().uuidString.lowercased())",
        localChildID: UUID? = nil
    ) async throws -> FamilyScreenTimeEmergency {
        #if DEBUG
        if usesSchoolEmergencyUITestFixture {
            let emergency = makeUITestEmergency(
                status: .requested,
                requestId: requestId,
                reason: reason,
                minutes: minutes
            )
            uiTestEmergencyChildID = localChildID
            uiTestEmergency = emergency
            recordSyncSuccess()
            return emergency
        }
        #endif
        guard let token = childDeviceToken else { throw FamilyCloudClientError.server("unauthorized") }
        childDeviceProfile = try await client.updateChildScreenTimeEmergency(
            token: token,
            action: "request",
            requestId: requestId,
            reason: String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280)),
            minutes: min(60, max(1, minutes))
        )
        recordSyncSuccess()
        guard let emergency = childDeviceProfile?.screenTimeEmergency else {
            throw FamilyCloudClientError.invalidResponse
        }
        return emergency
    }

    @discardableResult
    func updateChildScreenTimeEmergency(
        action: String,
        requestId: String,
        sessionEndsAt: Date? = nil
    ) async throws -> FamilyScreenTimeEmergency {
        #if DEBUG
        if usesSchoolEmergencyUITestFixture,
           let current = uiTestEmergency,
           current.requestId == requestId {
            let status: FamilyScreenTimeEmergencyStatus = switch action {
            case "activate": .active
            case "complete": .completed
            case "expire": .expired
            default: current.status
            }
            let emergency = makeUITestEmergency(
                status: status,
                requestId: requestId,
                reason: current.reason,
                minutes: current.minutes ?? 30,
                sessionEndsAt: sessionEndsAt.map { ISO8601DateFormatter().string(from: $0) }
            )
            uiTestEmergency = emergency
            recordSyncSuccess()
            return emergency
        }
        #endif
        guard let token = childDeviceToken else { throw FamilyCloudClientError.server("unauthorized") }
        childDeviceProfile = try await client.updateChildScreenTimeEmergency(
            token: token,
            action: action,
            requestId: requestId,
            sessionEndsAt: sessionEndsAt.map { ISO8601DateFormatter().string(from: $0) }
        )
        recordSyncSuccess()
        guard let emergency = childDeviceProfile?.screenTimeEmergency else {
            throw FamilyCloudClientError.invalidResponse
        }
        return emergency
    }

    @discardableResult
    func decideGuardianScreenTimeEmergency(
        for localChildID: UUID,
        requestId: String,
        approve: Bool,
        minutes: Int = 30
    ) async throws -> FamilyScreenTimeEmergency {
        #if DEBUG
        if usesSchoolEmergencyUITestFixture,
           uiTestEmergencyChildID == localChildID,
           let current = uiTestEmergency,
           current.requestId == requestId {
            let emergency = makeUITestEmergency(
                status: approve ? .approved : .denied,
                requestId: requestId,
                reason: current.reason,
                minutes: minutes
            )
            uiTestEmergency = emergency
            recordSyncSuccess()
            return emergency
        }
        #endif
        guard let token = guardianToken, let family, let child = cloudChild(for: localChildID) else {
            throw FamilyCloudClientError.server("unauthorized")
        }
        self.family = try await client.updateGuardianScreenTimeEmergency(
            token: token,
            familyId: family.family.id,
            childProfileId: child.id,
            action: approve ? "approve" : "deny",
            requestId: requestId,
            minutes: approve ? min(60, max(1, minutes)) : nil
        )
        recordSyncSuccess()
        guard let emergency = screenTimeEmergency(for: localChildID) else {
            throw FamilyCloudClientError.invalidResponse
        }
        return emergency
    }

    #if DEBUG
    private func makeUITestEmergency(
        status: FamilyScreenTimeEmergencyStatus,
        requestId: String,
        reason: String?,
        minutes: Int,
        sessionEndsAt: String? = nil
    ) -> FamilyScreenTimeEmergency {
        let now = ISO8601DateFormatter().string(from: Date())
        return FamilyScreenTimeEmergency(
            schemaVersion: 1,
            status: status,
            requestId: requestId,
            reason: String((reason ?? "").prefix(280)),
            minutes: min(60, max(1, minutes)),
            requestedAt: now,
            decidedAt: status == .approved || status == .denied ? now : nil,
            approvalExpiresAt: status == .approved
                ? ISO8601DateFormatter().string(from: Date().addingTimeInterval(10 * 60))
                : nil,
            activatedAt: status == .active ? now : nil,
            sessionEndsAt: sessionEndsAt,
            completedAt: status == .completed ? now : nil,
            expiredAt: status == .expired ? now : nil,
            expirationReason: status == .expired ? "ui_test" : nil,
            updatedAt: now
        )
    }
    #endif

    func submitChildTask(localAssignmentId: UUID, evidenceSummary: String?) async {
        guard let token = childDeviceToken else {
            setMessage(
                "这台设备还没有连接家庭，提交会保存在本机。",
                "This device is not connected to a family. The submission stays on this device."
            )
            return
        }
        let cloudTask = cloudTasks.first(where: {
            $0.clientRef.lowercased() == localAssignmentId.uuidString.lowercased()
        })
        if !syncState.pendingChildSubmissions.contains(where: { $0.localAssignmentId == localAssignmentId }) {
            syncState.pendingChildSubmissions.append(PendingFamilyCloudSubmission(
                mutationRef: "child:\(UUID().uuidString.lowercased())",
                localAssignmentId: localAssignmentId,
                cloudTaskId: cloudTask?.id,
                expectedVersion: cloudTask?.version ?? 1,
                evidenceSummary: evidenceSummary.map { String($0.prefix(500)) },
                queuedAt: Date()
            ))
            guard persistSyncState() else {
                setMessage(
                    "提交未能保存，请释放存储空间后重试。",
                    "The submission could not be saved. Free storage space and try again."
                )
                return
            }
        }
        await flushPendingChildSubmissions(token: token)
        if !syncState.pendingChildSubmissions.contains(where: { $0.localAssignmentId == localAssignmentId }),
           let task = cloudTask {
            queueActivityEvent(
                clientRef: "activity:task:\(localAssignmentId.uuidString.lowercased())",
                kind: .task,
                title: task.title,
                durationSeconds: 0,
                progressPercent: 100
            )
        }
        if syncState.pendingChildSubmissions.contains(where: { $0.localAssignmentId == localAssignmentId }) {
            setMessage(
                "任务已保存在本机，云同步会自动重试。",
                "The task is saved on this device and cloud sync will retry automatically."
            )
        } else {
            message = nil
        }
    }

    @discardableResult
    func withdrawChildTask(localAssignmentId: UUID) async -> Bool {
        // A withdrawal supersedes a submission that has not reached the server yet.
        syncState.pendingChildSubmissions.removeAll { $0.localAssignmentId == localAssignmentId }
        let current = cloudTasks.first(where: {
            $0.clientRef.lowercased() == localAssignmentId.uuidString.lowercased()
        })
        if !(syncState.pendingChildWithdrawals ?? []).contains(where: {
               $0.localAssignmentId == localAssignmentId
           }) {
            var withdrawals = syncState.pendingChildWithdrawals ?? []
            withdrawals.append(PendingFamilyCloudWithdrawal(
                mutationRef: "child-withdraw:\(UUID().uuidString.lowercased())",
                localAssignmentId: localAssignmentId,
                cloudTaskId: current?.id,
                expectedVersion: current?.version ?? 1,
                queuedAt: Date()
            ))
            syncState.pendingChildWithdrawals = withdrawals
        }
        guard persistSyncState() else {
            setMessage(
                "撤回未能保存，请释放存储空间后重试。",
                "The withdrawal could not be saved. Free storage space and try again."
            )
            return false
        }
        guard let token = childDeviceToken else {
            setMessage(
                "撤回已保存在本机，连接家庭后会自动同步。",
                "The withdrawal is saved on this device and will sync after the family reconnects."
            )
            return true
        }
        await flushPendingChildWithdrawals(token: token)
        if (syncState.pendingChildWithdrawals ?? []).contains(where: {
            $0.localAssignmentId == localAssignmentId
        }) {
            setMessage(
                "撤回已保存在本机，云同步会自动重试。",
                "The withdrawal is saved on this device and cloud sync will retry automatically."
            )
        } else {
            message = nil
        }
        return true
    }

    func exportCloudFamily() async throws -> FamilyCloudExport {
        guard let token = guardianToken, let family else { throw FamilyCloudClientError.server("unauthorized") }
        isWorking = true
        defer { isWorking = false }
        return try await client.exportFamily(token: token, familyId: family.family.id)
    }

    func createPortalLink() async throws -> FamilyCloudPortalLink {
        guard let token = guardianToken, let family else {
            throw FamilyCloudClientError.server("unauthorized")
        }
        isWorking = true
        defer { isWorking = false }
        return try await client.createPortalLink(token: token, familyId: family.family.id)
    }

    func disconnectGuardian() async throws {
        guard let token = guardianToken else {
            clearGuardianState()
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await client.revokeGuardianSession(token: token)
        } catch FamilyCloudClientError.server(let code) where code == "guardian_session_required" || code == "unauthorized" {
            // The server has already invalidated this session, so clearing the device is correct.
        }
        clearGuardianState()
    }

    func deleteCloudFamily() async throws -> FamilyCloudDeletionReceipt {
        guard let token = guardianToken, let family else { throw FamilyCloudClientError.server("unauthorized") }
        isWorking = true
        defer { isWorking = false }
        let receipt = try await client.deleteFamily(
            token: token,
            familyId: family.family.id,
            publicRef: family.family.publicRef
        )
        clearGuardianState()
        return receipt
    }

    private func recordSyncSuccess() {
        lastSyncAt = Date()
        lastSyncError = nil
    }

    private func recordSyncFailure(_ error: Error) {
        lastSyncError = error.localizedDescription
        setMessage("同步暂时失败，请稍后重试。", "Sync failed for now. Please try again later.")
    }

    @discardableResult
    private func mergeCloudTasks(_ tasks: [FamilyCloudTask]) -> Bool {
        for task in tasks {
            if let index = cloudTasks.firstIndex(where: { $0.id == task.id }) {
                if task.version >= cloudTasks[index].version { cloudTasks[index] = task }
            } else {
                cloudTasks.append(task)
            }
        }
        syncState.cachedTasks = cloudTasks
        return persistSyncState()
    }

    private func reconcilePendingGuardianDecisions() throws -> (
        active: [PendingFamilyCloudGuardianDecision],
        requiresReview: Set<UUID>
    ) {
        let queued = syncState.pendingGuardianDecisions ?? []
        guard !queued.isEmpty else { return ([], []) }
        let cloudByRef = Dictionary(uniqueKeysWithValues: cloudTasks.map {
            ($0.clientRef.lowercased(), $0)
        })
        let terminalStatuses = Set(["approved", "rejected", "cancelled"])
        var active: [PendingFamilyCloudGuardianDecision] = []
        var requiresReview: Set<UUID> = []
        for pending in queued {
            guard let current = cloudByRef[pending.assignmentId.uuidString.lowercased()] else {
                requiresReview.insert(pending.assignmentId)
                continue
            }
            if current.status == pending.status {
                continue
            }
            guard pending.expectedVersion > 0,
                  current.version == pending.expectedVersion,
                  !terminalStatuses.contains(current.status) else {
                requiresReview.insert(pending.assignmentId)
                continue
            }
            active.append(pending)
        }
        if active != queued {
            syncState.pendingGuardianDecisions = active
            guard persistSyncState() else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
        }
        return (active, requiresReview)
    }

    @discardableResult
    private func refreshGuardianSnapshotIfNeeded(
        token: String,
        familyId: String,
        force: Bool,
        authoritative: Bool = false
    ) async throws -> [FamilyCloudTask] {
        let lastSnapshot = syncState.guardianSnapshotDates?[familyId]
        guard force || lastSnapshot == nil || Date().timeIntervalSince(lastSnapshot!) >= Self.snapshotRefreshInterval else {
            return []
        }
        let previousCursor = syncState.guardianCursors[familyId] ?? 0
        let page = try await client.loadGuardianTaskSnapshot(token: token, familyId: familyId)
        // A full snapshot is a current cloud view, not a deletion log. A task can be absent
        // while its guardian outbox write is still in flight, so only an explicit incremental
        // tombstone may delete local or queued work.
        let pendingRefs = Set((syncState.pendingGuardianTaskUpserts ?? []).map {
            $0.upload.clientRef.lowercased()
        })
        let pendingCachedTasks = cloudTasks.filter {
            pendingRefs.contains($0.clientRef.lowercased())
        }
        cloudTasks = mergedTaskValues(page.tasks + pendingCachedTasks)
        syncState.cachedTasks = cloudTasks
        guard persistSyncState() else {
            throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
        }
        if authoritative {
            syncState.guardianCursors[familyId] = page.cursor
            var dates = syncState.guardianSnapshotDates ?? [:]
            dates[familyId] = Date()
            syncState.guardianSnapshotDates = dates
            guard persistSyncState() else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            return page.tasks
        }
        _ = try await pullGuardianChanges(token: token, familyId: familyId, from: previousCursor)
        syncState.guardianCursors[familyId] = max(
            syncState.guardianCursors[familyId] ?? previousCursor,
            page.cursor
        )
        var dates = syncState.guardianSnapshotDates ?? [:]
        dates[familyId] = Date()
        syncState.guardianSnapshotDates = dates
        guard persistSyncState() else {
            throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
        }
        return page.tasks
    }

    @discardableResult
    private func refreshChildSnapshotIfNeeded(
        token: String,
        force: Bool,
        authoritative: Bool = false
    ) async throws -> [FamilyCloudTask] {
        let lastSnapshot = syncState.childSnapshotDate
        guard force || lastSnapshot == nil || Date().timeIntervalSince(lastSnapshot!) >= Self.snapshotRefreshInterval else {
            return []
        }
        let previousCursor = syncState.childCursor
        let previousRefs = Set(cloudTasks.map { $0.clientRef.lowercased() })
        let page = try await client.loadChildTaskSnapshot(token: token)
        let currentRefs = Set(page.tasks.map { $0.clientRef.lowercased() })
        let removedRefs = previousRefs.subtracting(currentRefs)
        var pendingRemoved = Set(syncState.pendingRemovedTaskClientRefs ?? [])
        pendingRemoved.formUnion(removedRefs)
        syncState.pendingRemovedTaskClientRefs = pendingRemoved.sorted()
        cloudTasks = page.tasks
        syncState.cachedTasks = cloudTasks
        guard persistSyncState() else {
            throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
        }
        if authoritative {
            syncState.childCursor = page.cursor
            syncState.childSnapshotDate = Date()
            guard persistSyncState() else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            return page.tasks
        }
        _ = try await pullChildChanges(token: token, from: previousCursor)
        syncState.childCursor = max(syncState.childCursor, page.cursor)
        syncState.childSnapshotDate = Date()
        guard persistSyncState() else {
            throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
        }
        return page.tasks
    }

    @discardableResult
    private func pullGuardianChanges(
        token: String,
        familyId: String,
        from initialCursor: Int64
    ) async throws -> [FamilyCloudTask] {
        var cursor = initialCursor
        var collected: [FamilyCloudTask] = []
        repeat {
            let page = try await client.loadGuardianTasks(token: token, familyId: familyId, cursor: cursor)
            guard removeCloudTasks(clientRefs: page.removedClientRefs),
                  mergeCloudTasks(page.tasks) else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            collected.append(contentsOf: page.tasks)
            cursor = page.cursor
            syncState.guardianCursors[familyId] = cursor
            guard persistSyncState() else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            if !page.hasMore { break }
        } while true
        return collected
    }

    @discardableResult
    private func pullChildChanges(token: String, from initialCursor: Int64) async throws -> [FamilyCloudTask] {
        var cursor = initialCursor
        var collected: [FamilyCloudTask] = []
        repeat {
            let page = try await client.loadChildTasks(token: token, cursor: cursor)
            guard removeCloudTasks(clientRefs: page.removedClientRefs),
                  mergeCloudTasks(page.tasks) else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            collected.append(contentsOf: page.tasks)
            cursor = page.cursor
            syncState.childCursor = cursor
            guard persistSyncState() else {
                throw FamilyCloudClientError.server("family_cloud_local_persistence_failed")
            }
            if !page.hasMore { break }
        } while true
        return collected
    }

    @discardableResult
    private func removeCloudTasks(clientRefs: [String]) -> Bool {
        let removed = Set(clientRefs.map { $0.lowercased() })
        guard !removed.isEmpty else { return true }
        var pendingRemoved = Set(syncState.pendingRemovedTaskClientRefs ?? [])
        pendingRemoved.formUnion(removed)
        syncState.pendingRemovedTaskClientRefs = pendingRemoved.sorted()
        cloudTasks.removeAll { removed.contains($0.clientRef.lowercased()) }
        syncState.pendingGuardianTaskUpserts?.removeAll {
            removed.contains($0.upload.clientRef.lowercased())
        }
        syncState.pendingGuardianDecisions?.removeAll {
            removed.contains($0.assignmentId.uuidString.lowercased())
        }
        syncState.cachedTasks = cloudTasks
        return persistSyncState()
    }

    /// Applies durable server tombstones before any cursor can hide them. Clearing
    /// the outbox is itself durable; on failure the tombstones remain replayable.
    @discardableResult
    private func applyPendingRemovedTasks(into local: LocalFamilyStore) -> Bool {
        let pendingRemoved = Set(syncState.pendingRemovedTaskClientRefs ?? [])
        guard !pendingRemoved.isEmpty else { return true }
        local.removeCloudFamilyTasks(clientRefs: pendingRemoved)
        syncState.pendingRemovedTaskClientRefs = []
        return persistSyncState()
    }

    private func flushPendingChildSubmissions(token: String) async {
        for queued in syncState.pendingChildSubmissions {
            var pending = queued
            do {
                var current = cloudTasks.first(where: {
                    $0.clientRef.lowercased() == pending.localAssignmentId.uuidString.lowercased()
                })
                if current == nil {
                    _ = try await refreshChildSnapshotIfNeeded(token: token, force: true)
                    current = cloudTasks.first(where: {
                        $0.clientRef.lowercased() == pending.localAssignmentId.uuidString.lowercased()
                    })
                }
                guard let current else {
                    lastSyncError = "task_cloud_mapping_unavailable"
                    continue
                }
                if current.status == "submitted" || current.status == "approved" {
                    syncState.pendingChildSubmissions.removeAll { $0.mutationRef == pending.mutationRef }
                    guard persistSyncState() else { return }
                    continue
                }
                if current.status == "cancelled" {
                    syncState.pendingChildSubmissions.removeAll { $0.mutationRef == pending.mutationRef }
                    lastSyncError = "task_cancelled_before_submission"
                    guard persistSyncState() else { return }
                    continue
                }
                pending.cloudTaskId = current.id
                pending.expectedVersion = current.version
                if let index = syncState.pendingChildSubmissions.firstIndex(where: {
                    $0.mutationRef == pending.mutationRef
                }) {
                    syncState.pendingChildSubmissions[index] = pending
                    guard persistSyncState() else { return }
                }
                let updated = try await client.submitChildTask(
                    token: token,
                    taskId: current.id,
                    mutationRef: pending.mutationRef,
                    expectedVersion: current.version,
                    evidenceSummary: pending.evidenceSummary
                )
                guard mergeCloudTasks([updated]) else { return }
                syncState.pendingChildSubmissions.removeAll { $0.mutationRef == pending.mutationRef }
                guard persistSyncState() else { return }
            } catch FamilyCloudClientError.server(let code) where code == "stale_task_version" {
                do {
                    _ = try await refreshChildSnapshotIfNeeded(token: token, force: true)
                    guard let current = cloudTasks.first(where: {
                        $0.clientRef.lowercased() == pending.localAssignmentId.uuidString.lowercased()
                    }) else { continue }
                    if current.status == "submitted" || current.status == "approved" {
                        syncState.pendingChildSubmissions.removeAll { $0.mutationRef == pending.mutationRef }
                        guard persistSyncState() else { return }
                        continue
                    }
                    guard let index = syncState.pendingChildSubmissions.firstIndex(where: {
                        $0.mutationRef == pending.mutationRef
                    }) else { continue }
                    syncState.pendingChildSubmissions[index].expectedVersion = current.version
                    guard persistSyncState() else { return }
                    let updated = try await client.submitChildTask(
                        token: token,
                        taskId: current.id,
                        mutationRef: pending.mutationRef,
                        expectedVersion: current.version,
                        evidenceSummary: pending.evidenceSummary
                    )
                    guard mergeCloudTasks([updated]) else { return }
                    syncState.pendingChildSubmissions.removeAll { $0.mutationRef == pending.mutationRef }
                    guard persistSyncState() else { return }
                } catch {
                    lastSyncError = error.localizedDescription
                }
            } catch {
                lastSyncError = error.localizedDescription
            }
        }
    }

    private func flushPendingChildWithdrawals(token: String) async {
        for queued in syncState.pendingChildWithdrawals ?? [] {
            var pending = queued
            do {
                var current = cloudTasks.first(where: {
                    $0.clientRef.lowercased() == pending.localAssignmentId.uuidString.lowercased()
                })
                if current == nil {
                    _ = try await refreshChildSnapshotIfNeeded(token: token, force: true)
                    current = cloudTasks.first(where: {
                        $0.clientRef.lowercased() == pending.localAssignmentId.uuidString.lowercased()
                    })
                }
                guard let current else {
                    lastSyncError = "task_cloud_mapping_unavailable"
                    continue
                }
                if current.status == "assigned" || current.status == "started" || current.status == "rejected" {
                    syncState.pendingChildWithdrawals?.removeAll { $0.mutationRef == pending.mutationRef }
                    guard persistSyncState() else { return }
                    continue
                }
                if current.status == "approved" || current.status == "cancelled" {
                    syncState.pendingChildWithdrawals?.removeAll { $0.mutationRef == pending.mutationRef }
                    lastSyncError = "task_withdrawal_too_late"
                    guard persistSyncState() else { return }
                    continue
                }
                pending.cloudTaskId = current.id
                pending.expectedVersion = current.version
                if let index = syncState.pendingChildWithdrawals?.firstIndex(where: {
                    $0.mutationRef == pending.mutationRef
                }) {
                    syncState.pendingChildWithdrawals?[index] = pending
                    guard persistSyncState() else { return }
                }
                let updated = try await client.withdrawChildTask(
                    token: token,
                    taskId: current.id,
                    mutationRef: pending.mutationRef,
                    expectedVersion: current.version
                )
                guard mergeCloudTasks([updated]) else { return }
                syncState.pendingChildWithdrawals?.removeAll { $0.mutationRef == pending.mutationRef }
                guard persistSyncState() else { return }
            } catch FamilyCloudClientError.server(let code) where code == "stale_task_version" {
                do {
                    _ = try await refreshChildSnapshotIfNeeded(token: token, force: true)
                    guard let current = cloudTasks.first(where: {
                        $0.clientRef.lowercased() == pending.localAssignmentId.uuidString.lowercased()
                    }) else { continue }
                    if current.status != "submitted" {
                        syncState.pendingChildWithdrawals?.removeAll { $0.mutationRef == pending.mutationRef }
                        guard persistSyncState() else { return }
                        continue
                    }
                    let updated = try await client.withdrawChildTask(
                        token: token,
                        taskId: current.id,
                        mutationRef: pending.mutationRef,
                        expectedVersion: current.version
                    )
                    guard mergeCloudTasks([updated]) else { return }
                    syncState.pendingChildWithdrawals?.removeAll { $0.mutationRef == pending.mutationRef }
                    guard persistSyncState() else { return }
                } catch {
                    lastSyncError = error.localizedDescription
                }
            } catch {
                lastSyncError = error.localizedDescription
            }
        }
    }

    /// Repairs submissions made by older clients that updated the local task but silently lost
    /// the cloud mutation after an app restart. The cloud task map is child-scoped, so UUID
    /// matching cannot leak another child's local assignment into this device's outbox.
    @discardableResult
    private func recoverLocallySubmittedTasks(in local: LocalFamilyStore) -> Bool {
        var didRecover = false
        for assignment in local.assignments where assignment.status == .submitted {
            guard let cloudTask = cloudTasks.first(where: {
                $0.clientRef.lowercased() == assignment.id.uuidString.lowercased()
            }), cloudTask.status == "assigned" || cloudTask.status == "rejected" else { continue }
            guard !syncState.pendingChildSubmissions.contains(where: {
                $0.localAssignmentId == assignment.id
            }) else { continue }
            guard !(syncState.pendingChildWithdrawals ?? []).contains(where: {
                $0.localAssignmentId == assignment.id
            }) else { continue }
            let evidence = assignment.proof.text.trimmingCharacters(in: .whitespacesAndNewlines)
            syncState.pendingChildSubmissions.append(PendingFamilyCloudSubmission(
                mutationRef: "child:\(UUID().uuidString.lowercased())",
                localAssignmentId: assignment.id,
                cloudTaskId: cloudTask.id,
                expectedVersion: cloudTask.version,
                evidenceSummary: evidence.isEmpty ? nil : String(evidence.prefix(500)),
                queuedAt: Date()
            ))
            didRecover = true
        }
        return !didRecover || persistSyncState()
    }

    private func guardianMutationRef(_ uploads: [FamilyCloudTaskUpload]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(uploads.sorted { $0.clientRef < $1.clientRef })) ?? Data()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "guardian:\(digest)"
    }

    private func guardianTaskUpload(
        for assignment: TaskAssignment,
        local: LocalFamilyStore,
        statusOverride: String?
    ) -> FamilyCloudTaskUpload? {
        guard local.children.contains(where: { $0.id == assignment.childId }) else { return nil }
        let clientRef = assignment.id.uuidString.lowercased()
        let current = cloudTasks.first { $0.clientRef.lowercased() == clientRef }
        let localStatus: String
        switch assignment.status {
        case .open: localStatus = "assigned"
        case .submitted: localStatus = "submitted"
        case .approved: localStatus = "approved"
        case .rejected: localStatus = "rejected"
        case .cancelled: localStatus = "cancelled"
        }
        let payload = cloudPayload(for: assignment, local: local)
        let requestedStatus = statusOverride ?? current?.status ?? localStatus
        let deliveryStatus = payload.isCloudExecutable ? requestedStatus : "cancelled"
        return FamilyCloudTaskUpload(
            childClientRef: assignment.childId.uuidString.lowercased(),
            clientRef: clientRef,
            title: assignment.task.title,
            titleEnglish: assignment.task.localizedContent?.first(where: { $0.language == .english })?.title,
            status: deliveryStatus,
            growthPoints: assignment.task.rewardMinutes,
            requiresEvidence: assignment.task.requiredProof != .text || !assignment.task.instructions.isEmpty,
            plannedFor: FamilyCloudTaskDateCodec.encode(assignment.date),
            version: current?.version ?? 1,
            baseVersion: current?.version,
            taskPayload: payload
        )
    }

    /// Decisions carry the last cloud-authored task body, not the local cache body. This keeps
    /// approval/rejection from accidentally reverting a title, payload, schedule or point value
    /// written by another guardian or the child submission flow.
    private func guardianDecisionUpload(
        cloud: FamilyCloudTask,
        decision: PendingFamilyCloudGuardianDecision,
        family: FamilyCloudSnapshot
    ) -> FamilyCloudTaskUpload {
        let childClientRef = family.children.first(where: { $0.id == cloud.childProfileId })?.clientRef
            ?? cloud.childProfileId
        return FamilyCloudTaskUpload(
            childClientRef: childClientRef.lowercased(),
            clientRef: cloud.clientRef.lowercased(),
            title: cloud.title,
            titleEnglish: cloud.titleEnglish,
            status: decision.status,
            growthPoints: cloud.growthPoints,
            requiresEvidence: cloud.requiresEvidence,
            plannedFor: cloud.plannedFor,
            version: cloud.version,
            baseVersion: decision.expectedVersion,
            taskPayload: cloud.taskPayload
        )
    }

    private func cloudPayload(for assignment: TaskAssignment, local: LocalFamilyStore) -> FamilyCloudTaskPayload {
        var task = assignment.task
        task.reading?.inAppContent = nil
        let resource = local.book(for: task.reading).flatMap { book -> FamilyCloudBookResource? in
            guard let source = book.sourceURLString,
                  let url = URL(string: source),
                  url.scheme?.lowercased() == "https" else { return nil }
            return FamilyCloudBookResource(
                id: book.id,
                title: book.title,
                format: book.format,
                sourceName: book.sourceName,
                sourceURLString: source
            )
        }
        let readingMode = task.reading?.resolvedDeliveryMode
        let readiness: FamilyCloudContentReadiness?
        switch readingMode {
        case .physicalManual:
            readiness = .notRequired
        case .digitalLoaded:
            readiness = resource == nil ? .missing : .ready
        case .digitalRequired:
            readiness = .missing
        case .none:
            readiness = .notRequired
        }
        return FamilyCloudTaskPayload(
            task: task,
            bookResource: resource,
            readingMode: readingMode,
            contentReadiness: readiness
        )
    }

    private var pendingPointDelta: Int {
        (syncState.pendingPointMutations ?? []).reduce(0) { $0 + $1.delta }
    }

    private func mergedTaskValues(_ values: [FamilyCloudTask]) -> [FamilyCloudTask] {
        var byID: [String: FamilyCloudTask] = [:]
        for value in values {
            let key = value.clientRef.lowercased()
            guard let current = byID[key] else {
                byID[key] = value
                continue
            }
            if value.version > current.version ||
                (value.version == current.version && value.updatedAt > current.updatedAt) {
                byID[key] = value
            }
        }
        return Array(byID.values)
    }

    private func isTaskExecutableOnDevice(_ cloud: FamilyCloudTask, local: LocalFamilyStore) -> Bool {
        // Cancelled rows are delivery tombstones. They must reach the local merge so stale
        // assignments disappear, even though they are not runnable work.
        if cloud.status == "cancelled" { return true }
        guard let payload = cloud.taskPayload, payload.isCloudExecutable else { return false }
        guard payload.task.reading != nil else { return true }
        if payload.readingMode == .physicalManual { return true }
        guard let resource = payload.bookResource else { return false }
        return local.book(id: resource.id) != nil
    }

    private func flushPendingPointMutations(token: String, into local: LocalFamilyStore) async {
        guard !isFlushingPointMutations else { return }
        isFlushingPointMutations = true
        defer { isFlushingPointMutations = false }

        while let mutation = syncState.pendingPointMutations?.first {
            do {
                let response = try await client.applyChildPointMutation(token: token, mutation: mutation)
                rememberAcknowledgedPointMutationRef(mutation.mutationRef)
                syncState.pendingPointMutations?.removeAll { $0.mutationRef == mutation.mutationRef }
                guard persistSyncState() else { return }
                local.applyCloudGrowthPointBalance(response.balance, pendingDelta: pendingPointDelta)
            } catch FamilyCloudClientError.server(let code)
                where familyCloudPointMutationFailureDisposition(serverCode: code) == .deadLetter {
                guard deadLetterPointMutation(mutation, errorCode: code) else { return }
                lastSyncError = code
                continue
            } catch FamilyCloudClientError.server(let code)
                where familyCloudPointMutationFailureDisposition(serverCode: code) == .refreshAndRetry {
                do {
                    let profile = try await client.loadChildProfile(token: token)
                    childDeviceProfile = profile
                    local.applyCloudChildProfile(profile, pendingPointDelta: pendingPointDelta)
                    let response = try await client.applyChildPointMutation(token: token, mutation: mutation)
                    rememberAcknowledgedPointMutationRef(mutation.mutationRef)
                    syncState.pendingPointMutations?.removeAll { $0.mutationRef == mutation.mutationRef }
                    guard persistSyncState() else { return }
                    local.applyCloudGrowthPointBalance(response.balance, pendingDelta: pendingPointDelta)
                } catch FamilyCloudClientError.server(let replayCode)
                    where familyCloudPointMutationFailureDisposition(serverCode: replayCode) == .deadLetter {
                    guard deadLetterPointMutation(mutation, errorCode: replayCode) else { return }
                    lastSyncError = replayCode
                    continue
                } catch {
                    // The recoverable mutation remains in the durable outbox. Stop here so
                    // later entries cannot overtake a spend/refund dependency in the ledger.
                    lastSyncError = error.localizedDescription
                    return
                }
            } catch {
                lastSyncError = error.localizedDescription
                return
            }
        }
    }

    @discardableResult
    private func deadLetterPointMutation(
        _ mutation: PendingFamilyCloudPointMutation,
        errorCode: String
    ) -> Bool {
        syncState.pendingPointMutations?.removeAll { $0.mutationRef == mutation.mutationRef }
        var failures = syncState.failedPointMutations ?? []
        failures.removeAll { $0.mutationRef == mutation.mutationRef }
        failures.append(FailedFamilyCloudPointMutation(
            mutationRef: mutation.mutationRef,
            kind: mutation.kind,
            delta: mutation.delta,
            sourceRef: mutation.sourceRef,
            errorCode: errorCode,
            failedAt: Date()
        ))
        syncState.failedPointMutations = Array(failures.suffix(50))
        return persistSyncState()
    }

    private func flushPendingActivityEvents(token: String) async {
        guard !isFlushingActivityEvents else { return }
        isFlushingActivityEvents = true
        defer { isFlushingActivityEvents = false }

        while let batch = syncState.pendingActivityEvents?.prefix(25), !batch.isEmpty {
            do {
                let events = Array(batch)
                _ = try await client.uploadChildActivityEvents(token: token, events: events)
                let uploaded = Set(events.map(\.clientRef))
                rememberAcknowledgedActivityEventRefs(Array(uploaded))
                syncState.pendingActivityEvents?.removeAll { uploaded.contains($0.clientRef) }
                guard persistSyncState() else { return }
            } catch {
                lastSyncError = error.localizedDescription
                return
            }
        }
    }

    private func rememberAcknowledgedPointMutationRef(_ mutationRef: String) {
        var refs = syncState.acknowledgedPointMutationRefs ?? []
        refs.removeAll { $0 == mutationRef }
        refs.append(mutationRef)
        syncState.acknowledgedPointMutationRefs = Array(refs.suffix(256))
    }

    private func rememberAcknowledgedActivityEventRefs(_ clientRefs: [String]) {
        var refs = syncState.acknowledgedActivityEventRefs ?? []
        for clientRef in clientRefs {
            refs.removeAll { $0 == clientRef }
            refs.append(clientRef)
        }
        syncState.acknowledgedActivityEventRefs = Array(refs.suffix(256))
    }

    private func cloudChild(for localChildID: UUID) -> FamilyCloudSnapshot.Child? {
        family?.children.first { child in
            child.clientRef?.lowercased() == localChildID.uuidString.lowercased()
        }
    }

    private func materializeCloudBooks(from tasks: [FamilyCloudTask], into local: LocalFamilyStore) async {
        var resourcesByID: [UUID: FamilyCloudBookResource] = [:]
        for task in tasks {
            guard task.status != "cancelled" else { continue }
            guard let resource = task.taskPayload?.bookResource else { continue }
            resourcesByID[resource.id] = resource
        }
        let resources = resourcesByID.values
        for resource in resources where local.book(id: resource.id) == nil {
            await materializeCloudBook(resource, into: local)
        }
    }

    private func materializeCloudBook(
        _ resource: FamilyCloudBookResource,
        into local: LocalFamilyStore
    ) async {
        downloadingBookIDs.insert(resource.id)
        failedBookDownloadIDs.remove(resource.id)
        defer { downloadingBookIDs.remove(resource.id) }

        guard let url = URL(string: resource.sourceURLString), url.scheme?.lowercased() == "https" else {
            failedBookDownloadIDs.insert(resource.id)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("OctoTeacher/0.17 family-book-sync", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count <= 100 * 1_024 * 1_024 else {
            failedBookDownloadIDs.insert(resource.id)
            return
        }
        let ext = resource.format.lowercased()
        guard let fileName = BookFileStore.shared.importBook(data: data, ext: ext),
              let analysis = BookFileStore.shared.analyzeDetailed(fileName: fileName) else {
            failedBookDownloadIDs.insert(resource.id)
            return
        }
        local.addCloudBook(
            resource,
            fileName: fileName,
            pageCount: analysis.pageCount,
            charCount: analysis.charCount,
            chapters: analysis.chapters
        )
    }

    @discardableResult
    private func persistSyncState() -> Bool {
        syncState.cachedTasks = cloudTasks
        guard syncStateStore.save(syncState) else {
            syncState = lastPersistedSyncState
            cloudTasks = lastPersistedSyncState.cachedTasks ?? []
            lastSyncError = "family_cloud_local_persistence_failed"
            return false
        }
        lastPersistedSyncState = syncState
        return true
    }

    private func updateChildProfileWithConflictRetry(
        token: String,
        family: FamilyCloudSnapshot,
        cloudChild: FamilyCloudSnapshot.Child,
        localChild: ChildProfile,
        local: LocalFamilyStore,
        changedFields: Set<FamilyCloudGuardianProfileField>
    ) async throws -> FamilyCloudSnapshot {
        let request = makeGuardianProfileRequest(
            localChild: localChild,
            local: local,
            cloudChild: cloudChild,
            changedFields: changedFields
        )
        do {
            return try await client.updateChild(
                token: token,
                familyId: family.family.id,
                childId: cloudChild.id,
                baseVersion: cloudChild.profileVersion ?? 1,
                child: request
            )
        } catch FamilyCloudClientError.server(let code) where code == "stale_child_profile_version" {
            guard let refreshed = try await client.loadGuardianSession(token: token).family,
                  let current = refreshed.children.first(where: {
                      $0.clientRef?.lowercased() == localChild.id.uuidString.lowercased()
                  }) else {
                throw FamilyCloudClientError.server("child_profile_not_found")
            }
            let rebasedRequest = makeGuardianProfileRequest(
                localChild: localChild,
                local: local,
                cloudChild: current,
                changedFields: changedFields
            )
            return try await client.updateChild(
                token: token,
                familyId: refreshed.family.id,
                childId: current.id,
                baseVersion: current.profileVersion ?? 1,
                child: rebasedRequest
            )
        }
    }

    func makeGuardianProfileRequest(
        localChild: ChildProfile,
        local: LocalFamilyStore,
        cloudChild: FamilyCloudSnapshot.Child?,
        changedFields: Set<FamilyCloudGuardianProfileField>
    ) -> FamilyCreateChild {
        let currentYear = Calendar.current.component(.year, from: Date())
        let localBirthYear = currentYear - localChild.age
        let hasCloudProfile = cloudChild != nil

        return FamilyCreateChild(
            clientRef: localChild.id.uuidString.lowercased(),
            displayName: changedFields.contains(.displayName)
                ? localChild.name
                : cloudChild?.displayName ?? localChild.name,
            birthYear: changedFields.contains(.birthYear)
                ? localBirthYear
                : (hasCloudProfile ? cloudChild?.birthYear : localBirthYear),
            preReaderMode: changedFields.contains(.preReaderMode)
                ? localChild.isPreReader
                : cloudChild?.preReaderMode ?? localChild.isPreReader,
            interfaceLanguage: changedFields.contains(.interfaceLanguage)
                ? local.childInterfaceLanguage(for: localChild.id)
                : cloudChild?.interfaceLanguage ?? local.childInterfaceLanguage(for: localChild.id),
            contentLanguage: changedFields.contains(.contentLanguage)
                ? local.effectiveContentLanguage(for: localChild.id)
                : cloudChild?.contentLanguage ?? local.effectiveContentLanguage(for: localChild.id),
            dailyLimitMinutes: changedFields.contains(.dailyLimitMinutes)
                ? localChild.dailyLimitMinutes
                : cloudChild?.dailyLimitMinutes ?? localChild.dailyLimitMinutes,
            exchangePolicy: changedFields.contains(.exchangePolicy)
                ? local.policy(for: localChild.id)
                : cloudChild?.exchangePolicy ?? local.policy(for: localChild.id)
        )
    }

    private func clearGuardianState() {
        secrets.delete(account: Account.guardian)
        guardian = nil
        family = nil
        cloudTasks = []
        guardianActivitySummary = nil
        guardianTodayActivitySummary = nil
        guardianActivityLocalChildID = nil
        syncState.cachedTasks = []
        syncState.guardianCursors = [:]
        syncState.guardianSnapshotDates = [:]
        syncState.pendingGuardianProfileClientRefs = []
        syncState.pendingGuardianProfileFields = [:]
        syncState.pendingGuardianProfileGenerations = [:]
        syncState.pendingGuardianDecisions = []
        syncState.pendingGuardianTaskUpserts = []
        syncState.guardianTaskBaselineEstablished = false
        syncState.cachedFamily = nil
        persistSyncState()
        message = nil
    }
}

extension LocalFamilyStore {
    /// Cloud household metadata is authoritative. The local family network remains an offline
    /// cache; member identifiers are intentionally not rewritten because server ids are opaque.
    func applyCloudFamilyIdentity(_ snapshot: FamilyCloudSnapshot) {
        guard familyNetwork.familyName != snapshot.family.displayName else { return }
        familyNetwork.familyName = snapshot.family.displayName
        persist()
    }

    func applyCloudFamilyIdentity(_ profile: ChildDeviceProfileResponse) {
        guard familyNetwork.familyName != profile.family.displayName else { return }
        familyNetwork.familyName = profile.family.displayName
        persist()
    }

    /// Remove cloud-owned tasks that were revoked, reassigned to another child, or quarantined.
    /// This is a server tombstone application, so it must not enqueue a new guardian mutation.
    func removeCloudFamilyTasks(clientRefs: Set<String>) {
        let ids = Set(clientRefs.compactMap(UUID.init(uuidString:)))
        guard !ids.isEmpty else { return }
        for assignment in assignments where ids.contains(assignment.id) {
            if let photo = assignment.proof.photoFileName { ProofPhotoStore.shared.delete(fileName: photo) }
            if let audio = assignment.proof.audioFileName { ProofVoiceStore.shared.delete(fileName: audio) }
        }
        assignments.removeAll { ids.contains($0.id) }
        growthPack.steps.removeAll { step in
            ids.contains(step.assignmentId)
        }
        for index in growthPack.steps.indices { growthPack.steps[index].order = index + 1 }
        persist()
    }

    /// 只导入云合同允许的最小任务字段。照片、聊天、成长记忆等敏感本机数据不参与同步。
    func applyCloudFamilyTasks(
        _ tasks: [FamilyCloudTask],
        familySnapshot: FamilyCloudSnapshot? = nil,
        childName: String?,
        authoritativeCloudBalance: Bool = false,
        preservingLocalStatusesFor assignmentIDs: Set<UUID> = []
    ) {
        if let childName, !childName.isEmpty, let index = children.firstIndex(where: { $0.id == activeChildId }) {
            children[index].name = childName
        }
        for cloud in tasks {
            guard let id = UUID(uuidString: cloud.clientRef) else { continue }
            let targetChildId: UUID
            if let familySnapshot {
                guard let cloudChild = familySnapshot.children.first(where: { $0.id == cloud.childProfileId }),
                      let clientRef = cloudChild.clientRef,
                      let localId = UUID(uuidString: clientRef),
                      children.contains(where: { $0.id == localId }) else {
                    continue
                }
                targetChildId = localId
            } else {
                // A child-device token is already scoped to one child server-side.
                targetChildId = activeChildId
            }
            let status: TaskAssignmentStatus
            switch cloud.status {
            case "submitted": status = .submitted
            case "approved": status = .approved
            case "rejected": status = .rejected
            case "cancelled": status = .cancelled
            default: status = .open
            }
            if let index = assignments.firstIndex(where: { $0.id == id }) {
                assignments[index].childId = targetChildId
                if cloud.taskPayload?.isCloudExecutable == true,
                   let syncedTask = cloud.taskPayload?.task {
                    assignments[index].task = syncedTask
                }
                assignments[index].task.title = cloud.title
                assignments[index].task.rewardMinutes = max(1, cloud.growthPoints)
                if let english = cloud.titleEnglish {
                    var localized = assignments[index].task.localizedContent ?? []
                    localized.removeAll { $0.language == .english }
                    localized.append(TaskLocalizedContent(language: .english, title: english, instructions: ""))
                    assignments[index].task.localizedContent = localized
                }
                if let plannedFor = cloud.plannedFor,
                   let date = FamilyCloudTaskDateCodec.decode(plannedFor) {
                    assignments[index].date = date
                }
                let mergedStatus = mergedTaskStatus(
                    local: assignments[index].status,
                    cloud: status,
                    preserveLocal: assignmentIDs.contains(id)
                )
                if mergedStatus == .approved,
                   assignments[index].status != .approved,
                   !authoritativeCloudBalance {
                    _ = approve(assignments[index])
                } else {
                    assignments[index].status = mergedStatus
                }
                if status == .submitted, let evidenceSummary = cloud.evidenceSummary {
                    assignments[index].proof.text = evidenceSummary
                    assignments[index].proof.status = .submitted
                }
                ensureCloudGrowthStep(for: assignments[index])
                continue
            }
            let localized = cloud.titleEnglish.map {
                [TaskLocalizedContent(language: .english, title: $0, instructions: "")]
            }
            var template = cloud.taskPayload?.isCloudExecutable == true
                ? cloud.taskPayload?.task
                : nil
            if template == nil {
                template = TaskTemplate(
                    id: UUID(),
                    title: cloud.title,
                    category: .family,
                    difficulty: .easy,
                    rewardMinutes: max(1, cloud.growthPoints),
                    instructions: "",
                    requiredProof: .text,
                    localizedContent: localized
                )
            }
            template?.title = cloud.title
            template?.rewardMinutes = max(1, cloud.growthPoints)
            if template?.localizedContent == nil { template?.localizedContent = localized }
            assignments.append(TaskAssignment(
                id: id,
                childId: targetChildId,
                task: template!,
                date: cloud.plannedFor.flatMap(FamilyCloudTaskDateCodec.decode) ?? Date(),
                status: status == .approved ? .open : status,
                proof: status == .submitted
                    ? ProofDraft(
                        kind: .text,
                        text: cloud.evidenceSummary ?? "",
                        photoPlaceholderName: nil,
                        status: .submitted
                    )
                    : .empty
            ))
            if let inserted = assignments.first(where: { $0.id == id }) {
                ensureCloudGrowthStep(for: inserted)
            }
            if status == .approved,
               !authoritativeCloudBalance,
               let assignment = assignments.first(where: { $0.id == id }) {
                _ = approve(assignment)
            } else if status == .approved,
                      authoritativeCloudBalance,
                      let index = assignments.firstIndex(where: { $0.id == id }) {
                assignments[index].status = .approved
            }
        }
        persist()
    }

    private func mergedTaskStatus(
        local: TaskAssignmentStatus,
        cloud: TaskAssignmentStatus,
        preserveLocal: Bool
    ) -> TaskAssignmentStatus {
        guard preserveLocal else { return cloud }
        switch local {
        case .submitted, .approved, .rejected, .cancelled:
            return local
        case .open:
            return cloud
        }
    }

    private func ensureCloudGrowthStep(for assignment: TaskAssignment) {
        if let index = growthPack.steps.firstIndex(where: { $0.assignmentId == assignment.id }) {
            growthPack.steps[index].title = assignment.task.title
            growthPack.steps[index].detail = assignment.task.instructions
            growthPack.steps[index].rewardMinutes = assignment.task.rewardMinutes
            return
        }
        growthPack.steps.append(GrowthPackStep(
            id: UUID(),
            order: (growthPack.steps.map(\.order).max() ?? 0) + 1,
            title: assignment.task.title,
            detail: assignment.task.instructions,
            assignmentId: assignment.id,
            rewardMinutes: assignment.task.rewardMinutes
        ))
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
