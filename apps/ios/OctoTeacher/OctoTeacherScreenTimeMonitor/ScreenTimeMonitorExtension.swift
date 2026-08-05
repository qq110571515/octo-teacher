import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class OctoTeacherScreenTimeMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity.rawValue.hasPrefix(ScreenTimeSharedContract.rewardActivityPrefix) ||
            activity.rawValue == ScreenTimeSharedContract.rewardActivityName {
            reconcileRewardWindows(activityName: activity.rawValue, phase: .intervalStarted)
        } else if activity.rawValue.hasPrefix(ScreenTimeSharedContract.schoolActivityPrefix) {
            applySchoolSelectionIfNeeded(activityName: activity.rawValue)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity.rawValue == ScreenTimeSharedContract.rewardActivityName ||
            activity.rawValue.hasPrefix(ScreenTimeSharedContract.rewardActivityPrefix) {
            reconcileRewardWindows(activityName: activity.rawValue, phase: .intervalEnded)
        } else if activity.rawValue.hasPrefix(ScreenTimeSharedContract.schoolActivityPrefix) {
            clearSchoolSelectionIfNeeded(activityName: activity.rawValue)
        }
    }

    private func applySchoolSelectionIfNeeded(activityName: String) {
        _ = ScreenTimeRewardWindowLock.withLock {
            applySchoolSelectionWhileLocked(activityName: activityName)
        }
    }

    private func applySchoolSelectionWhileLocked(activityName: String) {
        guard let defaults = UserDefaults(suiteName: ScreenTimeSharedContract.appGroupIdentifier),
              let runtimeData = defaults.data(forKey: ScreenTimeSharedContract.schoolRuntimeKey),
              let runtime = try? JSONDecoder().decode(PersistedSchoolModeRuntime.self, from: runtimeData),
              runtime.shouldApplyShield(at: Date(), activityName: activityName)
        else { return }

        let referenceDate = Date()
        let emergency = defaults.data(forKey: ScreenTimeSharedContract.activeEmergencyWindowKey).flatMap {
            try? JSONDecoder().decode(PersistedScreenTimeEmergencyWindow.self, from: $0)
        }
        if ScreenTimeSharedContract.emergencyDefersShieldRestoration(emergency, at: referenceDate) {
            defaults.set(true, forKey: ScreenTimeSharedContract.schoolModeActiveKey)
            return
        }

        let store = ManagedSettingsStore(named: ManagedSettingsStore.Name(ScreenTimeSharedContract.schoolStoreName))
        store.shield.applications = nil
        store.shield.applicationCategories = .all()
        store.shield.webDomains = nil
        guard store.shield.applications == nil,
              store.shield.applicationCategories != nil,
              store.shield.webDomains == nil else { return }
        defaults.set(true, forKey: ScreenTimeSharedContract.schoolModeActiveKey)
    }

    private func clearSchoolSelectionIfNeeded(activityName: String) {
        _ = ScreenTimeRewardWindowLock.withLock {
            clearSchoolSelectionWhileLocked(activityName: activityName)
        }
    }

    private func clearSchoolSelectionWhileLocked(activityName: String) {
        guard let defaults = UserDefaults(suiteName: ScreenTimeSharedContract.appGroupIdentifier),
              let runtimeData = defaults.data(forKey: ScreenTimeSharedContract.schoolRuntimeKey),
              let runtime = try? JSONDecoder().decode(PersistedSchoolModeRuntime.self, from: runtimeData),
              runtime.shouldClearShield(at: Date(), activityName: activityName) else { return }
        let store = ManagedSettingsStore(named: ManagedSettingsStore.Name(ScreenTimeSharedContract.schoolStoreName))
        store.clearAllSettings()
        guard store.shield.applications == nil,
              store.shield.applicationCategories == nil,
              store.shield.webDomains == nil else { return }
        defaults.set(false, forKey: ScreenTimeSharedContract.schoolModeActiveKey)
    }

    private func reconcileRewardWindows(
        activityName: String,
        phase: ScreenTimeRewardActivityCallbackPhase,
        referenceDate: Date = Date()
    ) {
        let didAcquireLock: Bool? = ScreenTimeRewardWindowLock.withLock {
            reconcileRewardWindowsWhileLocked(
                activityName: activityName,
                phase: phase,
                referenceDate: referenceDate
            )
            return true
        }
        if didAcquireLock == nil {
            writeRewardRelockDiagnostic(
                activityName: activityName,
                phase: phase,
                outcome: .lockUnavailable,
                storedWindowCount: 0,
                activeWindowCount: 0,
                updatedAt: referenceDate
            )
        }
    }

    private func reconcileRewardWindowsWhileLocked(
        activityName: String,
        phase: ScreenTimeRewardActivityCallbackPhase,
        referenceDate: Date
    ) {
        guard let defaults = UserDefaults(suiteName: ScreenTimeSharedContract.appGroupIdentifier) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyData = defaults.data(forKey: ScreenTimeSharedContract.activeRewardWindowKey)
        let windowsData = defaults.data(forKey: ScreenTimeSharedContract.activeRewardWindowsKey)
        let usesLegacyStorage = windowsData == nil && legacyData != nil
        let storedWindows: [PersistedScreenTimeRewardWindow]
        if let windowsData,
           let decoded = try? decoder.decode([PersistedScreenTimeRewardWindow].self, from: windowsData) {
            storedWindows = decoded
        } else if let legacyData,
                  let legacy = try? decoder.decode(PersistedScreenTimeRewardWindow.self, from: legacyData) {
            storedWindows = [legacy]
        } else {
            storedWindows = []
        }

        let emergencyData = defaults.data(forKey: ScreenTimeSharedContract.activeEmergencyWindowKey)
        let emergency = emergencyData.flatMap {
            try? JSONDecoder().decode(PersistedScreenTimeEmergencyWindow.self, from: $0)
        }
        guard !ScreenTimeSharedContract.emergencyDefersShieldRestoration(
            emergency,
            at: referenceDate
        ) else {
            writeRewardRelockDiagnostic(
                activityName: activityName,
                phase: phase,
                outcome: .deferredByEmergencyAccess,
                storedWindowCount: storedWindows.count,
                activeWindowCount: storedWindows.count,
                updatedAt: referenceDate
            )
            return
        }
        let selectionGeneration = ScreenTimeSharedContract.currentSelectionGeneration(
            defaults: defaults
        )
        let selectionScopedWindows = storedWindows.filter {
            $0.belongsToSelectionGeneration(selectionGeneration)
        }
        let hasStaleSelectionWindows = selectionScopedWindows.count != storedWindows.count
        let clearsEmergency: Bool
        if activityName == ScreenTimeSharedContract.rewardActivityName {
            if let emergency {
                guard emergency.endsAt <= referenceDate else { return }
                clearsEmergency = true
            } else {
                // The legacy activity is now reserved for all-app emergency access. If its
                // marker is missing or unreadable, fail closed: reconcile the guardian shield
                // instead of leaving the device open after the main process exits.
                clearsEmergency = true
            }
        } else {
            clearsEmergency = false
        }

        let callbackWindows = ScreenTimeRewardWindowLedger.activeWindowsForCallback(
            activityName: activityName,
            phase: phase,
            storedWindows: selectionScopedWindows,
            at: referenceDate,
            acceptsLegacyActivity: clearsEmergency || usesLegacyStorage,
            systemUptime: ProcessInfo.processInfo.systemUptime
        )

        let compensationData = defaults.data(
            forKey: ScreenTimeSharedContract.pendingRewardCompensationsKey
        )
        let decodedCompensations = compensationData.flatMap {
            try? JSONDecoder().decode([PersistedScreenTimeRewardCompensation].self, from: $0)
        }
        let pendingCompensations = compensationData != nil && decodedCompensations == nil
            ? storedWindows.map { .init(id: $0.resolvedID, requestedAt: referenceDate) }
            : decodedCompensations ?? []
        guard callbackWindows != nil ||
                !pendingCompensations.isEmpty ||
                hasStaleSelectionWindows else {
            writeRewardRelockDiagnostic(
                activityName: activityName,
                phase: phase,
                outcome: .ignoredStaleCallback,
                storedWindowCount: storedWindows.count,
                activeWindowCount: storedWindows.count,
                updatedAt: referenceDate
            )
            return
        }
        let callbackBaseWindows = callbackWindows ?? selectionScopedWindows
        let uncompensated = ScreenTimeRewardCompensationLedger.applying(
            pendingCompensations,
            to: callbackBaseWindows
        ).remaining

        let selection = defaults.data(forKey: ScreenTimeSharedContract.selectionKey).flatMap {
            try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: $0)
        }
        let activeWindows = selection == nil
            ? []
            : ScreenTimeRewardWindowLedger.active(
                uncompensated,
                at: referenceDate,
                systemUptime: ProcessInfo.processInfo.systemUptime
            )
        let activeIDs = Set(activeWindows.map(\.resolvedID))
        let removedIDs = Set(storedWindows.map(\.resolvedID)).subtracting(activeIDs)
        let durableCompensations = removedIDs.reduce(pendingCompensations) { result, id in
            ScreenTimeRewardCompensationLedger.adding(id: id, at: referenceDate, to: result)
        }
        guard persistCompensations(durableCompensations, defaults: defaults) else {
            writeRewardRelockDiagnostic(
                activityName: activityName,
                phase: phase,
                outcome: .persistenceFailed,
                storedWindowCount: storedWindows.count,
                activeWindowCount: activeWindows.count,
                updatedAt: referenceDate
            )
            return
        }
        guard persistRewardState(
            activeWindows,
            clearsEmergency: clearsEmergency,
            defaults: defaults
        ) else {
            writeRewardRelockDiagnostic(
                activityName: activityName,
                phase: phase,
                outcome: .persistenceFailed,
                storedWindowCount: storedWindows.count,
                activeWindowCount: activeWindows.count,
                updatedAt: referenceDate
            )
            return
        }
        guard let selection else {
            clearGuardianApplicationStores(defaults: defaults)
            guard guardianApplicationStoresAreClear() else {
                writeRewardRelockDiagnostic(
                    activityName: activityName,
                    phase: phase,
                    outcome: .shieldVerificationFailed,
                    storedWindowCount: storedWindows.count,
                    activeWindowCount: activeWindows.count,
                    updatedAt: referenceDate
                )
                return
            }
            _ = clearCompensations(ids: Set(durableCompensations.map(\.id)), defaults: defaults)
            writeRewardRelockDiagnostic(
                activityName: activityName,
                phase: phase,
                outcome: .reconciled,
                storedWindowCount: storedWindows.count,
                activeWindowCount: activeWindows.count,
                updatedAt: referenceDate
            )
            return
        }

        let activeTokens: Set<ApplicationToken> = Set(activeWindows.compactMap {
            guard $0.resolvedTargetKind == .application else { return nil }
            return try? PropertyListDecoder().decode(
                ApplicationToken.self,
                from: $0.applicationTokenData
            )
        })
        let activeCategoryTokens: Set<ActivityCategoryToken> = Set(activeWindows.compactMap {
            guard $0.resolvedTargetKind == .category else { return nil }
            return try? PropertyListDecoder().decode(
                ActivityCategoryToken.self,
                from: $0.applicationTokenData
            )
        })
        let shieldStrategy = ScreenTimeSharedContract.applicationShieldStrategy(
            applicationCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count
        )
        guard shieldStrategy.isSupported,
              ScreenTimeSharedContract.activeRewardApplicationsAreValid(
                  activeTokens,
                  guardianApplications: selection.applicationTokens,
                  hasGuardianCategories: !selection.categoryTokens.isEmpty
              ), activeCategoryTokens.isSubset(of: selection.categoryTokens)
        else {
            writeRewardRelockDiagnostic(
                activityName: activityName,
                phase: phase,
                outcome: .shieldVerificationFailed,
                storedWindowCount: storedWindows.count,
                activeWindowCount: activeWindows.count,
                updatedAt: referenceDate
            )
            return
        }

        let expectedApplications = ScreenTimeSharedContract.expectedShieldApplications(
            guardianApplications: selection.applicationTokens,
            activeRewardApplications: activeTokens
        )
        let expectedCategories = ScreenTimeSharedContract.expectedShieldCategories(
            guardianCategories: selection.categoryTokens,
            activeRewardCategories: activeCategoryTokens
        )
        let categoryExceptions = ScreenTimeSharedContract.categoryShieldExceptions(
            guardianApplications: selection.applicationTokens,
            activeRewardApplications: activeTokens
        )
        guard let applicationShards = ScreenTimeSharedContract.applicationShieldShards(
            expectedApplications
        ) else {
            writeRewardRelockDiagnostic(
                activityName: activityName,
                phase: phase,
                outcome: .shieldVerificationFailed,
                storedWindowCount: storedWindows.count,
                activeWindowCount: activeWindows.count,
                updatedAt: referenceDate
            )
            return
        }

        clearGuardianApplicationStores(defaults: defaults)
        for (index, shard) in applicationShards.enumerated() {
            let shardStore = guardianApplicationStore(at: index)
            if #available(iOS 26.5, *) {
                shardStore.isActive = true
            }
            shardStore.shield.applications = shard
        }

        let store = guardianApplicationStore(at: 0)
        if #available(iOS 26.5, *),
           applicationShards.isEmpty,
           (!expectedCategories.isEmpty || !selection.webDomainTokens.isEmpty) {
            store.isActive = true
        }
        switch shieldStrategy {
        case .preciseApplications:
            store.shield.applicationCategories = nil
        case .applicationsAndCategories:
            store.shield.applicationCategories = expectedCategories.isEmpty
                ? nil
                : .specific(expectedCategories, except: categoryExceptions)
        case .categories:
            store.shield.applicationCategories = expectedCategories.isEmpty
                ? nil
                : .specific(expectedCategories, except: categoryExceptions)
        case .none, .unsupportedTooManyApplications:
            return
        }
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        defaults.set(
            applicationShards.count,
            forKey: ScreenTimeSharedContract.applicationShieldShardCountKey
        )
        if defaults.bool(forKey: ScreenTimeSharedContract.schoolModeActiveKey) {
            let schoolStore = ManagedSettingsStore(
                named: ManagedSettingsStore.Name(ScreenTimeSharedContract.schoolStoreName)
            )
            schoolStore.shield.applications = nil
            schoolStore.shield.applicationCategories = .all()
            schoolStore.shield.webDomains = nil
        }
        guard rewardShieldMatches(
            activeRewardApplications: activeTokens,
            activeRewardCategories: activeCategoryTokens,
            selection: selection
        ) else {
            writeRewardRelockDiagnostic(
                activityName: activityName,
                phase: phase,
                outcome: .shieldVerificationFailed,
                storedWindowCount: storedWindows.count,
                activeWindowCount: activeWindows.count,
                updatedAt: referenceDate
            )
            return
        }
        _ = clearCompensations(ids: Set(durableCompensations.map(\.id)), defaults: defaults)
        writeRewardRelockDiagnostic(
            activityName: activityName,
            phase: phase,
            outcome: .reconciled,
            storedWindowCount: storedWindows.count,
            activeWindowCount: activeWindows.count,
            updatedAt: referenceDate
        )
    }

    private func writeRewardRelockDiagnostic(
        activityName: String,
        phase: ScreenTimeRewardActivityCallbackPhase,
        outcome: PersistedScreenTimeRewardRelockOutcome,
        storedWindowCount: Int,
        activeWindowCount: Int,
        updatedAt: Date
    ) {
        guard let defaults = UserDefaults(suiteName: ScreenTimeSharedContract.appGroupIdentifier) else { return }
        let diagnostic = PersistedScreenTimeRewardRelockDiagnostic(
            activityName: activityName,
            phase: phase,
            outcome: outcome,
            targetWindowID: ScreenTimeSharedContract.rewardWindowID(forActivityName: activityName),
            storedWindowCount: storedWindowCount,
            activeWindowCount: activeWindowCount,
            updatedAt: updatedAt
        )
        guard let data = try? JSONEncoder().encode(diagnostic) else { return }
        defaults.set(data, forKey: ScreenTimeSharedContract.rewardRelockDiagnosticKey)
    }

    private func persistCompensations(
        _ compensations: [PersistedScreenTimeRewardCompensation],
        defaults: UserDefaults
    ) -> Bool {
        let key = ScreenTimeSharedContract.pendingRewardCompensationsKey
        guard !compensations.isEmpty else { return true }
        guard let data = try? JSONEncoder().encode(compensations) else { return false }
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }

    private func clearCompensations(ids: Set<UUID>, defaults: UserDefaults) -> Bool {
        guard !ids.isEmpty else { return true }
        let key = ScreenTimeSharedContract.pendingRewardCompensationsKey
        let current = defaults.data(forKey: key).flatMap {
            try? JSONDecoder().decode([PersistedScreenTimeRewardCompensation].self, from: $0)
        } ?? []
        let remaining = ScreenTimeRewardCompensationLedger.removing(ids: ids, from: current)
        if remaining.isEmpty {
            defaults.removeObject(forKey: key)
            return defaults.object(forKey: key) == nil
        }
        guard let data = try? JSONEncoder().encode(remaining) else { return false }
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }

    private func persistRewardState(
        _ windows: [PersistedScreenTimeRewardWindow],
        clearsEmergency: Bool,
        defaults: UserDefaults
    ) -> Bool {
        let windowsKey = ScreenTimeSharedContract.activeRewardWindowsKey
        let legacyKey = ScreenTimeSharedContract.activeRewardWindowKey
        let emergencyKey = ScreenTimeSharedContract.activeEmergencyWindowKey
        let previousWindows = defaults.object(forKey: windowsKey)
        let previousLegacy = defaults.object(forKey: legacyKey)
        let previousEmergency = defaults.object(forKey: emergencyKey)

        let encoded: Data?
        if windows.isEmpty {
            encoded = nil
        } else {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(windows.map { $0.normalized() }) else { return false }
            encoded = data
        }

        set(encoded, forKey: windowsKey, defaults: defaults)
        defaults.removeObject(forKey: legacyKey)
        if clearsEmergency {
            defaults.removeObject(forKey: emergencyKey)
        }

        let committed = defaults.data(forKey: windowsKey) == encoded &&
            defaults.object(forKey: legacyKey) == nil &&
            (!clearsEmergency || defaults.object(forKey: emergencyKey) == nil)
        guard !committed else { return true }

        set(previousWindows, forKey: windowsKey, defaults: defaults)
        set(previousLegacy, forKey: legacyKey, defaults: defaults)
        set(previousEmergency, forKey: emergencyKey, defaults: defaults)
        return false
    }

    private func set(_ value: Any?, forKey key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func guardianApplicationStore(at index: Int) -> ManagedSettingsStore {
        ManagedSettingsStore(
            named: ManagedSettingsStore.Name(
                ScreenTimeSharedContract.applicationShieldStoreName(at: index)
            )
        )
    }

    private var appliedGuardianApplicationTokens: Set<ApplicationToken> {
        (0..<ScreenTimeSharedContract.maximumApplicationShieldStoreCount)
            .reduce(into: Set<ApplicationToken>()) { result, index in
                result.formUnion(
                    guardianApplicationStore(at: index).shield.applications ?? []
                )
            }
    }

    private func rewardShieldMatches(
        activeRewardApplications: Set<ApplicationToken>,
        activeRewardCategories: Set<ActivityCategoryToken>,
        selection: FamilyActivitySelection
    ) -> Bool {
        let store = guardianApplicationStore(at: 0)
        let appliedApplications = appliedGuardianApplicationTokens
        let strategy = ScreenTimeSharedContract.applicationShieldStrategy(
            applicationCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count
        )
        guard strategy.isSupported,
              ScreenTimeSharedContract.activeRewardApplicationsAreValid(
                  activeRewardApplications,
                  guardianApplications: selection.applicationTokens,
                  hasGuardianCategories: !selection.categoryTokens.isEmpty
              ), activeRewardCategories.isSubset(of: selection.categoryTokens)
        else { return false }

        let expectedCategories = ScreenTimeSharedContract.expectedShieldCategories(
            guardianCategories: selection.categoryTokens,
            activeRewardCategories: activeRewardCategories
        )
        let categoryExceptions = ScreenTimeSharedContract.categoryShieldExceptions(
            guardianApplications: selection.applicationTokens,
            activeRewardApplications: activeRewardApplications
        )
        let expectedCategoryPolicy: ShieldSettings.ActivityCategoryPolicy<Application>? =
            expectedCategories.isEmpty
                ? nil
                : .specific(expectedCategories, except: categoryExceptions)

        let enforcementMatches: Bool
        switch strategy {
        case .preciseApplications:
            enforcementMatches = ScreenTimeSharedContract.rewardShieldApplicationsMatch(
                guardianApplications: selection.applicationTokens,
                activeRewardApplications: activeRewardApplications,
                appliedApplications: appliedApplications
            ) && store.shield.applicationCategories == nil
        case .applicationsAndCategories:
            enforcementMatches = appliedApplications ==
                ScreenTimeSharedContract.expectedShieldApplications(
                    guardianApplications: selection.applicationTokens,
                    activeRewardApplications: activeRewardApplications
                ) && store.shield.applicationCategories == expectedCategoryPolicy
        case .categories:
            enforcementMatches = appliedApplications.isEmpty &&
                store.shield.applicationCategories == expectedCategoryPolicy
        case .none, .unsupportedTooManyApplications:
            enforcementMatches = false
        }
        return enforcementMatches &&
            (store.shield.webDomains ?? []) == selection.webDomainTokens
    }

    private func clearGuardianApplicationStores(defaults: UserDefaults) {
        for index in 0..<ScreenTimeSharedContract.maximumApplicationShieldStoreCount {
            guardianApplicationStore(at: index).clearAllSettings()
        }
        defaults.removeObject(forKey: ScreenTimeSharedContract.applicationShieldShardCountKey)
    }

    private func guardianApplicationStoresAreClear() -> Bool {
        return (0..<ScreenTimeSharedContract.maximumApplicationShieldStoreCount).allSatisfy { index in
            let store = guardianApplicationStore(at: index)
            return store.shield.applications == nil &&
                store.shield.applicationCategories == nil &&
                store.shield.webDomains == nil
        }
    }
}
