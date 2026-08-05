import XCTest
import Darwin
import UIKit
@testable import OctoTeacher

final class ScreenTimeSafetyTests: XCTestCase {
    func testInterruptedSystemCallRetriesUntilSuccess() {
        let results: [Int32] = [-1, -1, 0]
        let errors: [Int32] = [EINTR, EINTR, 0]
        var callCount = 0

        let result = ScreenTimeRewardWindowLock.retryInterruptedSystemCall({
            defer { callCount += 1 }
            return results[callCount]
        }, errorCode: {
            errors[callCount - 1]
        })

        XCTAssertEqual(result, 0)
        XCTAssertEqual(callCount, 3)
    }

    func testInterruptedSystemCallStopsOnNonInterruptedFailure() {
        var callCount = 0

        let result = ScreenTimeRewardWindowLock.retryInterruptedSystemCall({
            callCount += 1
            return -1
        }, errorCode: {
            EACCES
        })

        XCTAssertEqual(result, -1)
        XCTAssertEqual(callCount, 1)
    }

    func testInterruptedSystemCallDoesNotRepeatSuccess() {
        var callCount = 0

        let result = ScreenTimeRewardWindowLock.retryInterruptedSystemCall({
            callCount += 1
            return 42
        }, errorCode: {
            EINTR
        })

        XCTAssertEqual(result, 42)
        XCTAssertEqual(callCount, 1)
    }

    func testApplicationShieldStrategyUsesPreciseAppsAtAppleLimit() {
        XCTAssertEqual(
            ScreenTimeSharedContract.applicationShieldStrategy(applicationCount: 50, categoryCount: 0),
            .preciseApplications
        )
    }

    func testApplicationShieldStrategySupportsDirectAppsAcrossMultipleStores() {
        XCTAssertEqual(
            ScreenTimeSharedContract.applicationShieldStrategy(applicationCount: 51, categoryCount: 2),
            .applicationsAndCategories
        )
    }

    func testApplicationShieldStrategyCombinesCategoriesWithExplicitApps() {
        XCTAssertEqual(
            ScreenTimeSharedContract.applicationShieldStrategy(applicationCount: 2, categoryCount: 2),
            .applicationsAndCategories
        )
    }

    func testApplicationShieldStrategyRejectsOnlyAboveAggregateCapacity() {
        let strategy = ScreenTimeSharedContract.applicationShieldStrategy(
            applicationCount: ScreenTimeSharedContract.maximumApplicationTokenCapacity + 1,
            categoryCount: 0
        )

        XCTAssertEqual(strategy, .unsupportedTooManyApplications)
        XCTAssertFalse(strategy.isSupported)
    }

    func testApplicationShieldShardsRespectManagedSettingsPerStoreLimit() throws {
        let applications = Set(0..<120)
        let shards = try XCTUnwrap(
            ScreenTimeSharedContract.applicationShieldShards(applications)
        )

        XCTAssertEqual(shards.map(\.count), [50, 50, 20])
        XCTAssertTrue(
            shards.allSatisfy {
                $0.count <= ScreenTimeSharedContract.maximumApplicationTokensPerShieldStore
            }
        )
        XCTAssertEqual(shards.reduce(into: Set<Int>()) { $0.formUnion($1) }, applications)
    }

    func testApplicationShieldShardBoundaries() {
        XCTAssertEqual(
            ScreenTimeSharedContract.applicationShieldShardCount(applicationCount: 0),
            0
        )
        XCTAssertEqual(
            ScreenTimeSharedContract.applicationShieldShardCount(applicationCount: 50),
            1
        )
        XCTAssertEqual(
            ScreenTimeSharedContract.applicationShieldShardCount(applicationCount: 51),
            2
        )
        XCTAssertEqual(
            ScreenTimeSharedContract.applicationShieldShardCount(
                applicationCount: ScreenTimeSharedContract.maximumApplicationTokenCapacity
            ),
            ScreenTimeSharedContract.maximumApplicationShieldStoreCount
        )
        XCTAssertNil(
            ScreenTimeSharedContract.applicationShieldShardCount(
                applicationCount: ScreenTimeSharedContract.maximumApplicationTokenCapacity + 1
            )
        )
    }

    func testApplicationShieldStrategySupportsCategoryOnlySelection() {
        XCTAssertEqual(
            ScreenTimeSharedContract.applicationShieldStrategy(applicationCount: 0, categoryCount: 1),
            .categories
        )
        XCTAssertEqual(
            ScreenTimeSharedContract.applicationShieldStrategy(applicationCount: 0, categoryCount: 0),
            .none
        )
    }

    func testRewardShieldSubtractsEveryActiveApplicationFromGuardianSelection() {
        let guardianApplications = Set([1, 2, 3, 4])

        let applied = ScreenTimeSharedContract.expectedShieldApplications(
            guardianApplications: guardianApplications,
            activeRewardApplications: Set([2, 4, 99])
        )

        XCTAssertEqual(applied, Set([1, 3]))
        XCTAssertTrue(
            ScreenTimeSharedContract.rewardShieldApplicationsMatch(
                guardianApplications: guardianApplications,
                activeRewardApplications: Set([2, 4]),
                appliedApplications: Set([1, 3])
            )
        )
        XCTAssertFalse(
            ScreenTimeSharedContract.rewardShieldApplicationsMatch(
                guardianApplications: guardianApplications,
                activeRewardApplications: Set([2, 99]),
                appliedApplications: Set([1, 3, 4])
            ),
            "An app outside the guardian selection must never be reported as unlocked"
        )
    }

    func testCategoryShieldExcludesExplicitAndActiveApplications() {
        let exceptions = ScreenTimeSharedContract.categoryShieldExceptions(
            guardianApplications: Set([1, 2]),
            activeRewardApplications: Set([2, 3])
        )

        XCTAssertEqual(exceptions, Set([1, 2, 3]))
    }

    func testCategoryRewardWindowRemovesOnlyTheActiveCategory() {
        XCTAssertEqual(
            ScreenTimeSharedContract.expectedShieldCategories(
                guardianCategories: Set([1, 2, 3]),
                activeRewardCategories: Set([2])
            ),
            Set([1, 3])
        )
    }

    func testCategoryPolicyAcceptsVerifiedTappedAppOutsideExplicitSelection() {
        XCTAssertTrue(
            ScreenTimeSharedContract.activeRewardApplicationsAreValid(
                Set([99]),
                guardianApplications: Set([1, 2]),
                hasGuardianCategories: true
            )
        )
        XCTAssertFalse(
            ScreenTimeSharedContract.activeRewardApplicationsAreValid(
                Set([99]),
                guardianApplications: Set([1, 2]),
                hasGuardianCategories: false
            )
        )
    }

    func testSingleAppUnlockRequiresAnExplicitApplicationSelection() {
        XCTAssertFalse(
            ScreenTimeSharedContract.singleApplicationUnlockSelectionIsReady(applicationCount: 0)
        )
        XCTAssertTrue(
            ScreenTimeSharedContract.singleApplicationUnlockSelectionIsReady(applicationCount: 1)
        )
        XCTAssertTrue(
            ScreenTimeSharedContract.singleApplicationUnlockSelectionIsReady(applicationCount: 50)
        )
        XCTAssertTrue(
            ScreenTimeSharedContract.singleApplicationUnlockSelectionIsReady(applicationCount: 51)
        )
        XCTAssertTrue(
            ScreenTimeSharedContract.singleApplicationUnlockSelectionIsReady(
                applicationCount: ScreenTimeSharedContract.maximumApplicationTokenCapacity
            )
        )
        XCTAssertFalse(
            ScreenTimeSharedContract.singleApplicationUnlockSelectionIsReady(
                applicationCount: ScreenTimeSharedContract.maximumApplicationTokenCapacity + 1
            )
        )
    }

    func testImplicitSingleAppUnlockRejectsAmbiguousSelections() {
        XCTAssertFalse(
            ScreenTimeSharedContract.implicitSingleApplicationUnlockSelectionIsUnambiguous(
                applicationCount: 0
            )
        )
        XCTAssertTrue(
            ScreenTimeSharedContract.implicitSingleApplicationUnlockSelectionIsUnambiguous(
                applicationCount: 1
            )
        )
        XCTAssertFalse(
            ScreenTimeSharedContract.implicitSingleApplicationUnlockSelectionIsUnambiguous(
                applicationCount: 2
            )
        )
        XCTAssertFalse(
            ScreenTimeSharedContract.implicitSingleApplicationUnlockSelectionIsUnambiguous(
                applicationCount: 50
            )
        )
    }

    func testOnlyApplicationShieldRequestIdentifiesAnExactApp() {
        let createdAt = Date()
        let applicationRequest = PersistedShieldActionRequest(
            id: UUID(),
            intent: .redeemGrowthPoints,
            targetKind: .application,
            tokenData: Data([1]),
            createdAt: createdAt
        )
        let categoryRequest = PersistedShieldActionRequest(
            id: UUID(),
            intent: .redeemGrowthPoints,
            targetKind: .category,
            tokenData: Data([1]),
            createdAt: createdAt
        )

        XCTAssertTrue(applicationRequest.identifiesExactApplication(at: createdAt))
        XCTAssertFalse(categoryRequest.identifiesExactApplication(at: createdAt))
    }

    func testApplicationShieldRequestAuthorizesOnlyMatchingFreshReceipt() {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let requestID = UUID()
        let tokenData = Data([1, 2, 3])
        let request = PersistedShieldActionRequest(
            id: requestID,
            intent: .redeemGrowthPoints,
            targetKind: .application,
            tokenData: tokenData,
            createdAt: createdAt
        )

        XCTAssertTrue(
            request.authorizesApplication(
                requestID: requestID,
                tokenData: tokenData,
                at: createdAt.addingTimeInterval(299)
            )
        )
        XCTAssertFalse(
            request.authorizesApplication(
                requestID: UUID(),
                tokenData: tokenData,
                at: createdAt.addingTimeInterval(1)
            )
        )
        XCTAssertFalse(
            request.authorizesApplication(
                requestID: requestID,
                tokenData: Data([9, 9, 9]),
                at: createdAt.addingTimeInterval(1)
            )
        )
        XCTAssertFalse(
            request.authorizesApplication(
                requestID: requestID,
                tokenData: tokenData,
                at: createdAt.addingTimeInterval(300)
            )
        )

        let categoryRequest = PersistedShieldActionRequest(
            id: requestID,
            intent: .redeemGrowthPoints,
            targetKind: .category,
            tokenData: tokenData,
            createdAt: createdAt
        )
        XCTAssertFalse(
            categoryRequest.authorizesApplication(
                requestID: requestID,
                tokenData: tokenData,
                at: createdAt.addingTimeInterval(1)
            )
        )
        XCTAssertTrue(
            categoryRequest.authorizesCategory(
                requestID: requestID,
                tokenData: tokenData,
                at: createdAt.addingTimeInterval(1)
            )
        )
        XCTAssertFalse(
            categoryRequest.authorizesCategory(
                requestID: requestID,
                tokenData: Data([8, 8, 8]),
                at: createdAt.addingTimeInterval(1)
            )
        )
    }

    func testRewardLedgerKeepsApplicationAndCategoryTargetsDistinct() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let tokenData = Data([1, 2, 3])
        let application = PersistedScreenTimeRewardWindow(
            applicationTokenData: tokenData,
            targetKind: .application,
            startedAt: now,
            endsAt: now.addingTimeInterval(900),
            sourceLabel: "application"
        )
        let category = PersistedScreenTimeRewardWindow(
            applicationTokenData: tokenData,
            targetKind: .category,
            startedAt: now,
            endsAt: now.addingTimeInterval(900),
            sourceLabel: "category"
        )

        let windows = try ScreenTimeRewardWindowLedger.adding(
            category,
            to: [application],
            at: now
        )
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(Set(windows.map(\.resolvedTargetKind)), Set([.application, .category]))
    }

    func testShieldActionRequestRequiresCurrentSelectionGenerationWhenProvided() {
        let now = Date()
        let request = PersistedShieldActionRequest(
            id: UUID(),
            intent: .redeemGrowthPoints,
            targetKind: .application,
            tokenData: Data([0x01, 0x02]),
            createdAt: now,
            selectionGeneration: 4
        )

        XCTAssertTrue(
            request.identifiesExactApplication(
                at: now,
                selectionGeneration: 4
            )
        )
        XCTAssertFalse(
            request.identifiesExactApplication(
                at: now,
                selectionGeneration: 3
            )
        )
        XCTAssertTrue(request.belongsToSelectionGeneration(4))
        XCTAssertFalse(request.belongsToSelectionGeneration(3))
        XCTAssertTrue(
            request.authorizesApplication(
                requestID: request.id,
                tokenData: request.tokenData,
                at: now,
                selectionGeneration: 4
            )
        )
        XCTAssertFalse(
            request.authorizesApplication(
                requestID: request.id,
                tokenData: request.tokenData,
                at: now,
                selectionGeneration: 5
            )
        )

        let legacyRequest = PersistedShieldActionRequest(
            id: UUID(),
            intent: .redeemGrowthPoints,
            targetKind: .application,
            tokenData: Data([0x03]),
            createdAt: now
        )
        XCTAssertFalse(
            legacyRequest.identifiesExactApplication(
                at: now,
                selectionGeneration: 4
            )
        )
        XCTAssertFalse(legacyRequest.belongsToSelectionGeneration(4))
        XCTAssertTrue(legacyRequest.belongsToSelectionGeneration(nil))
    }

    func testSelectionGenerationAdvancesAndWraps() {
        let suiteName = "ScreenTimeSafetyTests.selectionGeneration.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            ScreenTimeSharedContract.currentSelectionGeneration(defaults: defaults),
            0
        )
        XCTAssertEqual(
            ScreenTimeSharedContract.advanceSelectionGeneration(defaults: defaults),
            1
        )
        XCTAssertEqual(
            ScreenTimeSharedContract.advanceSelectionGeneration(defaults: defaults),
            2
        )
        defaults.set(Int.max, forKey: ScreenTimeSharedContract.selectionGenerationKey)
        XCTAssertEqual(
            ScreenTimeSharedContract.advanceSelectionGeneration(defaults: defaults),
            1
        )
    }

    func testRewardWindowRequiresCurrentSelectionGeneration() {
        let now = Date()
        let window = PersistedScreenTimeRewardWindow(
            applicationTokenData: Data([0x04]),
            startedAt: now,
            endsAt: now.addingTimeInterval(60),
            sourceLabel: "test",
            selectionGeneration: 7
        )

        XCTAssertTrue(window.belongsToSelectionGeneration(7))
        XCTAssertFalse(window.belongsToSelectionGeneration(8))
        XCTAssertEqual(window.normalized().selectionGeneration, 7)

        let legacyWindow = PersistedScreenTimeRewardWindow(
            applicationTokenData: Data([0x05]),
            startedAt: now,
            endsAt: now.addingTimeInterval(60),
            sourceLabel: "legacy"
        )
        XCTAssertFalse(legacyWindow.belongsToSelectionGeneration(7))
    }

    func testDeviceActivityWindowUsesExactEndAndRejectsSubFifteenMinutePromises() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let exactEnd = start.addingTimeInterval(15 * 60)

        let interval = try ScreenTimeUsageWindowSchedule.validatedInterval(
            startedAt: start,
            endsAt: exactEnd
        )

        XCTAssertEqual(interval.start, start)
        XCTAssertEqual(interval.end, exactEnd)
        XCTAssertThrowsError(
            try ScreenTimeUsageWindowSchedule.validatedInterval(
                startedAt: start,
                endsAt: exactEnd.addingTimeInterval(-0.001)
            )
        ) { error in
            XCTAssertEqual(error as? ScreenTimeUsageWindowSchedule.Error, .intervalTooShort)
        }
        XCTAssertFalse(ScreenTimeUsageWindowSchedule.supports(minutes: 14))
        XCTAssertTrue(ScreenTimeUsageWindowSchedule.supports(minutes: 15))
    }

    func testActiveEmergencyDefersUUIDRewardAndDelayedSchoolShieldRestoration() {
        let start = Date(timeIntervalSince1970: 2_000)
        let emergency = PersistedScreenTimeEmergencyWindow(
            startedAt: start,
            endsAt: start.addingTimeInterval(30 * 60),
            sourceLabel: "test emergency"
        )
        let reward = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(15 * 60),
            sourceLabel: "test reward"
        )
        let callbackDate = reward.endsAt
        var persistedLedger = [reward]

        let isDeferred = ScreenTimeSharedContract.emergencyDefersShieldRestoration(
            emergency,
            at: callbackDate
        )
        if !isDeferred {
            persistedLedger = ScreenTimeRewardWindowLedger.active(persistedLedger, at: callbackDate)
        }

        XCTAssertTrue(
            isDeferred,
            "UUID reward callbacks and delayed school starts must leave enforcement untouched"
        )
        XCTAssertEqual(persistedLedger, [reward], "The reward ledger must survive until emergency convergence")
        XCTAssertFalse(
            ScreenTimeSharedContract.emergencyDefersShieldRestoration(
                emergency,
                at: emergency.endsAt
            ),
            "The emergency end callback is the convergence boundary"
        )
    }

    func testSchoolModeFailureClearsRuntimeSoNextSyncRegistersAgain() throws {
        enum Failure: Error { case shieldVerification }
        let runtime = PersistedSchoolModeRuntime(
            childID: UUID(),
            isEnabled: true,
            defaultStartMinutes: 8 * 60,
            defaultEndMinutes: 15 * 60,
            rules: [.init(weekday: 2, startMinutes: 8 * 60, endMinutes: 15 * 60)],
            exceptions: [],
            activityNames: ["octoteacher.school-mode.weekly.2"]
        )
        var persistedRuntime: PersistedSchoolModeRuntime?
        var registrations = 0
        var cancellations = 0
        var shouldFailShield = true

        func synchronize() throws {
            try SchoolModeSynchronizationTransaction.commit(
                previous: persistedRuntime,
                desired: runtime,
                replaceSchedules: { registrations += 1 },
                persistRuntime: { persistedRuntime = runtime },
                applyCurrentState: {
                    if shouldFailShield { throw Failure.shieldVerification }
                },
                rollback: {
                    cancellations += 1
                    persistedRuntime = nil
                }
            )
        }

        XCTAssertThrowsError(try synchronize())
        XCTAssertNil(persistedRuntime)
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(cancellations, 1)

        shouldFailShield = false
        XCTAssertNoThrow(try synchronize())
        XCTAssertEqual(registrations, 2, "A failed shield must make the next sync register schedules again")
        XCTAssertEqual(persistedRuntime, runtime)
    }

    func testEmergencyWindowRefusesPrivateFallbackStorage() {
        let store = ScreenTimeEmergencyWindowStore(defaults: nil, usesSharedAppGroup: false)
        let window = PersistedScreenTimeEmergencyWindow(
            startedAt: Date(timeIntervalSince1970: 2_000),
            endsAt: Date(timeIntervalSince1970: 3_800),
            sourceLabel: "test emergency"
        )

        XCTAssertFalse(store.usesSharedAppGroup)
        XCTAssertThrowsError(try store.save(window)) { error in
            guard case ScreenTimeRewardWindowPersistenceError.sharedAppGroupUnavailable = error else {
                return XCTFail("Expected sharedAppGroupUnavailable, got \(error)")
            }
        }
        XCTAssertNil(store.load())
    }

    func testEmergencyMarkerReadbackSurvivesStoreRecreation() throws {
        let suiteName = "ScreenTimeSafetyTests.Emergency.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let window = PersistedScreenTimeEmergencyWindow(
            startedAt: Date(timeIntervalSince1970: 2_000),
            endsAt: Date(timeIntervalSince1970: 3_800),
            sourceLabel: "test emergency"
        )

        let writer = ScreenTimeEmergencyWindowStore(defaults: defaults, usesSharedAppGroup: true)
        try writer.save(window)
        let relaunchedReader = ScreenTimeEmergencyWindowStore(defaults: defaults, usesSharedAppGroup: true)

        XCTAssertEqual(relaunchedReader.load(), window)
    }

    func testMissingEmergencyMarkerLegacyCallbackConvergesToSafeRelock() {
        let start = Date(timeIntervalSince1970: 4_000)
        let window = PersistedScreenTimeRewardWindow(
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(15 * 60),
            sourceLabel: "existing app window"
        )

        let remaining = ScreenTimeRewardWindowLedger.activeWindowsForCallback(
            activityName: ScreenTimeSharedContract.rewardActivityName,
            storedWindows: [window],
            at: window.endsAt,
            acceptsLegacyActivity: true
        )

        XCTAssertEqual(remaining, [], "A legacy emergency callback without a marker must fail closed")
    }

    func testLegacyNamedStoreCleanupRegistryIsExplicit() {
        XCTAssertEqual(
            Set(ScreenTimeSharedContract.legacyManagedSettingsStoreNames),
            Set(["rewardUnlock", "webSafety", "schoolMode"])
        )
    }

    func testMigrationMarkerRequiresReadableClearDefaultStoreEvidence() {
        XCTAssertTrue(
            ScreenTimeSharedContract.managedSettingsCleanupWasVerified(
                namedStoresAreClear: true,
                defaultStoreIsClear: true
            )
        )
        XCTAssertFalse(
            ScreenTimeSharedContract.managedSettingsCleanupWasVerified(
                namedStoresAreClear: true,
                defaultStoreIsClear: false
            )
        )
        XCTAssertFalse(
            ScreenTimeSharedContract.managedSettingsCleanupWasVerified(
                namedStoresAreClear: true,
                defaultStoreIsClear: nil
            ),
            "Unavailable unnamed-store readback must keep migration retryable"
        )
    }

    func testStaleEnforcementResetMarkerSurvivesHostAppReinstall() {
        XCTAssertEqual(
            ScreenTimeSharedContract.staleEnforcementResetAction(
                sharedMarkerIsSet: true,
                standardMarkerIsSet: false
            ),
            .skip,
            "The App Group marker must prevent a reset after host-app preferences are reinstalled"
        )
        XCTAssertEqual(
            ScreenTimeSharedContract.staleEnforcementResetAction(
                sharedMarkerIsSet: false,
                standardMarkerIsSet: true
            ),
            .adoptStandardMarker,
            "Existing installations should copy their standard marker without clearing selection again"
        )
        XCTAssertEqual(
            ScreenTimeSharedContract.staleEnforcementResetAction(
                sharedMarkerIsSet: false,
                standardMarkerIsSet: false
            ),
            .clearExecutionStatePreservingSelection
        )
    }

    func testAuthorizationPurposeStorePersistsItsDeviceRole() {
        let suiteName = "ScreenTimeAuthorizationPurposeStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ScreenTimeAuthorizationPurposeStore(defaults: defaults)

        store.save(.childFamily)

        XCTAssertEqual(ScreenTimeAuthorizationPurposeStore(defaults: defaults).purpose, .childFamily)
        store.clear()
        XCTAssertNil(ScreenTimeAuthorizationPurposeStore(defaults: defaults).purpose)
    }

    func testManagedSettingsExecutionIsChildDeviceOnlyOutsideUITests() {
        XCTAssertFalse(ScreenTimeSharedContract.mayExecuteDeviceControl(isChildDevice: false))
        XCTAssertTrue(ScreenTimeSharedContract.mayExecuteDeviceControl(isChildDevice: true))
        XCTAssertTrue(
            ScreenTimeSharedContract.mayExecuteDeviceControl(
                isChildDevice: false,
                isUITestMode: true
            )
        )
    }

    func testGuardianScreenTimePolicyIsStoredPerChild() throws {
        let suiteName = "ScreenTimeSafetyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = GuardianScreenTimePolicyStore(defaults: defaults)
        let childA = UUID()
        let childB = UUID()
        let policy = FamilyScreenTimePolicy(
            revision: 4,
            selectionData: Data("opaque-selection".utf8).base64EncodedString(),
            applicationCount: 2,
            categoryCount: 1,
            webDomainCount: 0,
            updatedAt: "2026-07-12T00:00:00Z"
        )

        try store.save(policy, for: childA)

        XCTAssertEqual(store.policy(for: childA), policy)
        XCTAssertNil(store.policy(for: childB))
        store.clear(for: childA)
        XCTAssertNil(store.policy(for: childA))
    }

    func testCurrentScreenTimePolicySchemaInvalidatesDeviceLocalSelections() {
        let legacyPolicy = FamilyScreenTimePolicy(
            schemaVersion: 2,
            revision: 2,
            selectionData: Data("build-56-selection".utf8).base64EncodedString(),
            applicationCount: 0,
            categoryCount: 2,
            webDomainCount: 0,
            updatedAt: "2026-07-14T20:23:17Z"
        )

        XCTAssertEqual(FamilyScreenTimePolicy.currentSchemaVersion, 3)
        XCTAssertNotEqual(legacyPolicy.schemaVersion, FamilyScreenTimePolicy.currentSchemaVersion)
        XCTAssertFalse(legacyPolicy.hasValidSelectionHash)
    }

    func testCurrentScreenTimePolicyBindsOpaqueSelectionToHash() {
        let selectionData = Data("guardian-selection".utf8).base64EncodedString()
        let policy = FamilyScreenTimePolicy(
            revision: 8,
            selectionData: selectionData,
            selectionHash: FamilyScreenTimePolicy.hash(selectionData: selectionData),
            applicationCount: 3,
            categoryCount: 1,
            webDomainCount: 0,
            updatedAt: "2026-07-29T20:00:00Z"
        )

        XCTAssertTrue(policy.hasValidSelectionHash)
        XCTAssertEqual(policy.selectionHash?.count, 64)
    }

    func testChildCatalogBindingRoundTripsWithoutReplacingGuardianAuthority() throws {
        let catalogSelectionData = Data("child-catalog".utf8).base64EncodedString()
        let catalog = FamilyScreenTimeCatalog(
            schemaVersion: 1,
            revision: 3,
            selectionData: catalogSelectionData,
            selectionHash: FamilyScreenTimePolicy.hash(selectionData: catalogSelectionData),
            applicationCount: 9,
            categoryCount: 2,
            webDomainCount: 0,
            capturedAt: "2026-08-01T17:00:00Z",
            sourceDevicePublicRef: "device_child"
        )
        let policySelectionData = Data("guardian-subset".utf8).base64EncodedString()
        let policy = FamilyScreenTimePolicy(
            revision: 7,
            selectionData: policySelectionData,
            selectionHash: FamilyScreenTimePolicy.hash(selectionData: policySelectionData),
            applicationCount: 4,
            categoryCount: 0,
            webDomainCount: 0,
            catalogBinding: catalog.binding,
            updatedAt: "2026-08-01T17:05:00Z"
        )

        let decoded = try JSONDecoder().decode(
            FamilyScreenTimePolicy.self,
            from: JSONEncoder().encode(policy)
        )

        XCTAssertTrue(catalog.hasValidSelectionHash)
        XCTAssertEqual(decoded.catalogBinding, catalog.binding)
        XCTAssertNotEqual(decoded.selectionHash, catalog.selectionHash)
    }

    @MainActor
    func testCatalogCaptureDoesNotMutateTheEnforcedSelection() throws {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let manager = ScreenTimePOCManager()
        let enforcedSelection = manager.selection
        let upload = try manager.makeChildCatalogUpload(
            from: ScreenTimeSelectionStore.emptyExpandedSelection(),
            capturedAt: "2026-08-01T17:00:00Z"
        )

        XCTAssertEqual(manager.selection, enforcedSelection)
        XCTAssertTrue(upload.hasValidSelectionHash)
        XCTAssertFalse(upload.hasSelection)
        #endif
    }

    func testGuardianControlCommandRoundTripsWithServerExpiry() throws {
        let selectionData = Data("guardian-selection".utf8).base64EncodedString()
        let control = FamilyScreenTimeControl(
            schemaVersion: 1,
            commandId: "control:unlock-1234",
            mode: .unlocked,
            issuedAt: "2026-07-29T20:00:00.000Z",
            unlockUntil: "2026-07-29T20:30:00.000Z"
        )
        let policy = FamilyScreenTimePolicy(
            revision: 9,
            selectionData: selectionData,
            selectionHash: FamilyScreenTimePolicy.hash(selectionData: selectionData),
            applicationCount: 3,
            categoryCount: 1,
            webDomainCount: 0,
            control: control,
            updatedAt: "2026-07-29T20:00:00.000Z"
        )

        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(FamilyScreenTimePolicy.self, from: data)

        XCTAssertEqual(decoded, policy)
        XCTAssertEqual(decoded.control?.mode, .unlocked)
        XCTAssertEqual(
            decoded.control?.unlockEndDate,
            Date(timeIntervalSince1970: 1_785_357_000)
        )
    }

    func testGuardianControlDecisionLocksAndRejectsInvalidCommands() {
        let now = Date(timeIntervalSince1970: 1_785_355_200)
        let locked = FamilyScreenTimeControl(
            schemaVersion: 1,
            commandId: "control:lock",
            mode: .locked,
            issuedAt: "2026-07-29T20:00:00.000Z",
            unlockUntil: nil
        )
        let invalid = FamilyScreenTimeControl(
            schemaVersion: 9,
            commandId: "",
            mode: .unlocked,
            issuedAt: "",
            unlockUntil: nil
        )

        XCTAssertEqual(
            locked.decision(activeUnlockEnd: nil, referenceDate: now, minimumStartDuration: 15 * 60),
            .lock
        )
        XCTAssertEqual(
            invalid.decision(activeUnlockEnd: nil, referenceDate: now, minimumStartDuration: 15 * 60),
            .reject(errorCode: "invalid_control_command")
        )
    }

    func testGuardianControlDecisionStartsKeepsAndExpiresUnlock() {
        let now = Date(timeIntervalSince1970: 1_785_355_200)
        let end = now.addingTimeInterval(30 * 60)
        let control = FamilyScreenTimeControl(
            schemaVersion: 1,
            commandId: "control:unlock",
            mode: .unlocked,
            issuedAt: ISO8601DateFormatter().string(from: now),
            unlockUntil: ISO8601DateFormatter().string(from: end)
        )

        XCTAssertEqual(
            control.decision(activeUnlockEnd: nil, referenceDate: now, minimumStartDuration: 15 * 60),
            .startUnlock(until: end)
        )
        XCTAssertEqual(
            control.decision(activeUnlockEnd: end, referenceDate: now, minimumStartDuration: 15 * 60),
            .keepUnlock(until: end)
        )
        XCTAssertEqual(
            control.decision(activeUnlockEnd: end, referenceDate: end, minimumStartDuration: 15 * 60),
            .lock
        )
        XCTAssertEqual(
            control.decision(
                activeUnlockEnd: nil,
                referenceDate: end.addingTimeInterval(-10 * 60),
                minimumStartDuration: 15 * 60
            ),
            .reject(errorCode: "remote_unlock_too_close_to_expiry")
        )
    }

    func testGuardianControlReceiptReportsTheEffectiveStateAfterExpiry() {
        let now = Date(timeIntervalSince1970: 1_785_355_200)
        let end = now.addingTimeInterval(30 * 60)
        let control = FamilyScreenTimeControl(
            schemaVersion: 1,
            commandId: "control:unlock:effective-receipt",
            mode: .unlocked,
            issuedAt: ISO8601DateFormatter().string(from: now),
            unlockUntil: ISO8601DateFormatter().string(from: end)
        )

        XCTAssertEqual(
            control.effectiveReceipt(referenceDate: now),
            FamilyScreenTimeControlReceipt(
                mode: .unlocked,
                unlockUntil: control.unlockUntil
            )
        )
        XCTAssertEqual(
            control.effectiveReceipt(referenceDate: end),
            FamilyScreenTimeControlReceipt(mode: .locked, unlockUntil: nil)
        )
        XCTAssertEqual(control.accountingSessionID, control.accountingSessionID)
        XCTAssertNotEqual(
            control.accountingSessionID,
            FamilyScreenTimeControl(
                schemaVersion: 1,
                commandId: "control:unlock:different",
                mode: .unlocked,
                issuedAt: control.issuedAt,
                unlockUntil: control.unlockUntil
            ).accountingSessionID
        )
    }

    func testOnlyAnActiveAcknowledgedUnlockNeedsOngoingReconciliation() {
        let unlocked = FamilyScreenTimeControl(
            schemaVersion: 1,
            commandId: "control:unlock",
            mode: .unlocked,
            issuedAt: "2026-07-29T20:00:00.000Z",
            unlockUntil: "2026-07-29T20:30:00.000Z"
        )
        let locked = FamilyScreenTimeControl(
            schemaVersion: 1,
            commandId: "control:lock",
            mode: .locked,
            issuedAt: "2026-07-29T20:00:00.000Z",
            unlockUntil: nil
        )

        XCTAssertTrue(
            ScreenTimePOCManager.shouldReconcileAcknowledgedControl(
                unlocked,
                appliedMode: .unlocked
            )
        )
        XCTAssertFalse(
            ScreenTimePOCManager.shouldReconcileAcknowledgedControl(
                unlocked,
                appliedMode: .locked
            )
        )
        XCTAssertFalse(
            ScreenTimePOCManager.shouldReconcileAcknowledgedControl(
                locked,
                appliedMode: .locked
            )
        )
    }

    func testAcknowledgedGuardianLockDoesNotCancelALaterGrowthPointsWindow() throws {
        let now = Date(timeIntervalSince1970: 1_785_355_200)
        let controller = MockScreenTimeController()
        let control = FamilyScreenTimeControl(
            schemaVersion: 1,
            commandId: "control:lock:once",
            mode: .locked,
            issuedAt: ISO8601DateFormatter().string(from: now),
            unlockUntil: nil
        )

        _ = try controller.startSession(minutes: 30, now: now)
        XCTAssertTrue(controller.reconcileGuardianControl(control, now: now.addingTimeInterval(60)))
        XCTAssertEqual(controller.sessionStatus, .locked)

        _ = try controller.startSession(minutes: 15, now: now.addingTimeInterval(120))
        XCTAssertFalse(controller.reconcileGuardianControl(control, now: now.addingTimeInterval(180)))
        XCTAssertEqual(controller.sessionStatus, .active)
        XCTAssertEqual(controller.activeGrants.count, 1)
    }

    func testAcknowledgedGuardianCommandRemainsIdempotentAfterAppRestart() throws {
        let suiteName = "ScreenTimeSafetyTests.guardian-control.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let persistenceKey = "screen-time-session"
        let now = Date(timeIntervalSince1970: 1_785_355_200)
        let control = FamilyScreenTimeControl(
            schemaVersion: 1,
            commandId: "control:lock:persisted",
            mode: .locked,
            issuedAt: ISO8601DateFormatter().string(from: now),
            unlockUntil: nil
        )

        let first = MockScreenTimeController(
            persistenceKey: persistenceKey,
            defaults: defaults
        )
        XCTAssertTrue(first.reconcileGuardianControl(control, now: now))

        let restarted = MockScreenTimeController(
            persistenceKey: persistenceKey,
            defaults: defaults
        )
        _ = try restarted.startSession(minutes: 15, now: now.addingTimeInterval(60))

        XCTAssertFalse(
            restarted.reconcileGuardianControl(
                control,
                now: now.addingTimeInterval(120)
            )
        )
        XCTAssertEqual(restarted.sessionStatus, .active)
        XCTAssertEqual(restarted.appliedGuardianControlCommandID, control.commandId)
    }

    func testGuardianRemoteUnlockIsIdempotentAndProducesAuthorizationReceipt() {
        let now = Date(timeIntervalSince1970: 1_785_355_200)
        let end = now.addingTimeInterval(30 * 60)
        let controller = MockScreenTimeController()
        let control = FamilyScreenTimeControl(
            schemaVersion: 1,
            commandId: "control:unlock:receipt",
            mode: .unlocked,
            issuedAt: ISO8601DateFormatter().string(from: now),
            unlockUntil: ISO8601DateFormatter().string(from: end)
        )

        XCTAssertTrue(controller.reconcileGuardianControl(control, now: now))
        XCTAssertFalse(controller.reconcileGuardianControl(control, now: now.addingTimeInterval(10)))
        XCTAssertEqual(controller.activeGrants.count, 1)
        XCTAssertEqual(controller.activeGrants.first?.id, control.accountingSessionID)
        XCTAssertEqual(controller.activeGrants.first?.resolvedAuthority, .guardianRemote)

        _ = controller.tick(now: end)

        XCTAssertEqual(controller.sessionStatus, .expired)
        XCTAssertEqual(controller.latestReceipt?.resolvedAuthority, .guardianRemote)
        XCTAssertEqual(controller.latestReceipt?.consumedMinutes, 30)
    }

    func testFreshPickerKeepsCategoriesSeparateFromExplicitApplications() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let selection = ScreenTimeSelectionStore.emptyExpandedSelection()

        XCTAssertFalse(selection.includeEntireCategory)
        XCTAssertTrue(selection.applicationTokens.isEmpty)
        XCTAssertTrue(selection.categoryTokens.isEmpty)
        #endif
    }

    func testCategoryRepairPickerExpandsThenNormalizesForEnforcement() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let pickerSelection = ScreenTimeSelectionStore.categoryExpandingPickerSelection(
            from: ScreenTimeSelectionStore.emptyExpandedSelection()
        )
        let normalized = ScreenTimeSelectionStore.normalizedForExplicitCategorySelection(
            pickerSelection
        )

        XCTAssertTrue(pickerSelection.includeEntireCategory)
        XCTAssertTrue(normalized.changed)
        XCTAssertFalse(normalized.selection.includeEntireCategory)
        XCTAssertFalse(normalized.droppedExpandedApplications)
        #endif
    }

    func testSingleAppUnlockDurationDependsOnAuthority() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        XCTAssertEqual(ScreenTimeSingleAppUnlockAuthority.growthPoints.maximumMinutes, 60)
        XCTAssertEqual(ScreenTimeSingleAppUnlockAuthority.parentPIN.maximumMinutes, 24 * 60)
        #endif
    }

    func testChildExchangeOptionsKeepFixedChoicesAndMergeValidCustomMinutes() {
        XCTAssertEqual(RewardScreenTimeUI.fixedExchangeMinutes, [15, 30, 45, 60])
        XCTAssertEqual(
            RewardScreenTimeUI.exchangeMinutes(customMinutes: 20),
            [15, 20, 30, 45, 60]
        )
        XCTAssertEqual(
            RewardScreenTimeUI.exchangeMinutes(customMinutes: 45),
            [15, 30, 45, 60],
            "A custom duration matching a fixed choice must be deduplicated"
        )
        XCTAssertEqual(RewardScreenTimeUI.exchangeMinutes(customMinutes: 0), [15, 30, 45, 60])
        XCTAssertEqual(RewardScreenTimeUI.exchangeMinutes(customMinutes: 14), [15, 30, 45, 60])
        XCTAssertEqual(RewardScreenTimeUI.exchangeMinutes(customMinutes: 61), [15, 30, 45, 60])
        XCTAssertEqual(LocalFamilyStore.dailyLimitRange.upperBound, 720)
    }

    func testRewardScreenTimeFlowRequiresAnExactApplicationBeforeOfferingExchange() {
        XCTAssertEqual(
            RewardScreenTimeFlow.resolve(
                isSchoolMode: false,
                hasPendingShieldAction: true,
                hasDirectShieldApplication: false,
                hasDirectShieldCategory: false,
                selectedAppIsAuthorizedForUnlock: false,
                isUITestMode: false
            ),
            .impreciseTarget,
            "A web-domain callback must never expose a paid app or category unlock"
        )
        XCTAssertEqual(
            RewardScreenTimeFlow.resolve(
                isSchoolMode: false,
                hasPendingShieldAction: true,
                hasDirectShieldApplication: false,
                hasDirectShieldCategory: true,
                selectedAppIsAuthorizedForUnlock: false,
                isUITestMode: false
            ),
            .exactCategory
        )
        XCTAssertEqual(
            RewardScreenTimeFlow.resolve(
                isSchoolMode: false,
                hasPendingShieldAction: true,
                hasDirectShieldApplication: true,
                hasDirectShieldCategory: false,
                selectedAppIsAuthorizedForUnlock: false,
                isUITestMode: false
            ),
            .exactApplication
        )
        XCTAssertEqual(
            RewardScreenTimeFlow.resolve(
                isSchoolMode: false,
                hasPendingShieldAction: false,
                hasDirectShieldApplication: false,
                hasDirectShieldCategory: false,
                selectedAppIsAuthorizedForUnlock: true,
                isUITestMode: false
            ),
            .exactApplication
        )
    }

    func testRewardScreenTimeFlowGivesSchoolModePrecedenceAndOtherwiseRequiresSetup() {
        XCTAssertEqual(
            RewardScreenTimeFlow.resolve(
                isSchoolMode: true,
                hasPendingShieldAction: true,
                hasDirectShieldApplication: true,
                hasDirectShieldCategory: true,
                selectedAppIsAuthorizedForUnlock: true,
                isUITestMode: false
            ),
            .schoolEmergency,
            "School Mode must not expose the ordinary Growth Points exchange"
        )
        XCTAssertEqual(
            RewardScreenTimeFlow.resolve(
                isSchoolMode: false,
                hasPendingShieldAction: false,
                hasDirectShieldApplication: false,
                hasDirectShieldCategory: false,
                selectedAppIsAuthorizedForUnlock: false,
                isUITestMode: false
            ),
            .setup
        )
    }

    func testExchangeTransactionStateRejectsASecondBeginUntilCompletion() {
        let started = RewardExchangeTransactionState.idle.beginning

        XCTAssertEqual(started, .inFlight)
        XCTAssertNil(started?.beginning)
        XCTAssertEqual(started?.completing, .idle)
    }

    func testSuccessfulExchangeSelectsTheNextInactiveOptionOrClearsTheSelection() {
        XCTAssertEqual(
            RewardScreenTimeUI.nextInactiveSelection(
                from: [1, 2, 3],
                excluding: 1,
                isActive: { [1, 2].contains($0) }
            ),
            3
        )
        XCTAssertEqual(
            RewardScreenTimeUI.nextInactiveSelection(
                from: [1, 2],
                excluding: 1,
                isActive: { _ in true }
            ),
            nil
        )
        XCTAssertEqual(
            RewardScreenTimeUI.nextInactiveSelection(
                from: [2, 3],
                excluding: 1,
                isActive: { $0 == 2 }
            ),
            3,
            "After consuming an exact Shield request, selection must come from the guardian-configured app set"
        )
    }

    func testSubFifteenMinuteCustomOptionNeverEntersThePaidExchangeChoices() {
        XCTAssertEqual(
            RewardScreenTimeUI.exchangeMinutes(customMinutes: 10),
            [15, 30, 45, 60]
        )
        XCTAssertFalse(ScreenTimeUsageWindowSchedule.supports(minutes: 10))
        XCTAssertEqual(
            RewardScreenTimeUI.availability(
                dailyRequiredMinutes: 15,
                cost: 5,
                availablePoints: 50,
                dailyRemainingMinutes: 10,
                isSchoolMode: false,
                isAuthorized: true,
                selectedAppIsActive: false
            ),
            .dailyLimit(remainingMinutes: 10)
        )
    }

    func testConsumedShieldActionStopsPinningTheTappedApp() {
        let request = PersistedShieldActionRequest(
            id: UUID(),
            intent: .redeemGrowthPoints,
            targetKind: .application,
            tokenData: Data([1]),
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(
            RewardScreenTimeUI.activeShieldAction(request, consumedActionID: nil),
            request
        )
        XCTAssertNil(
            RewardScreenTimeUI.activeShieldAction(request, consumedActionID: request.id)
        )
        XCTAssertEqual(
            RewardScreenTimeUI.activeShieldAction(request, consumedActionID: UUID()),
            request
        )
    }

    func testChildExchangeAvailabilityDistinguishesEveryBlockingReason() {
        let available = RewardScreenTimeUI.availability(
            dailyRequiredMinutes: 30,
            cost: 20,
            availablePoints: 50,
            dailyRemainingMinutes: 60,
            isSchoolMode: false,
            isAuthorized: true,
            selectedAppIsActive: false
        )
        XCTAssertEqual(available, .available)

        XCTAssertEqual(
            RewardScreenTimeUI.availability(
                dailyRequiredMinutes: 15,
                cost: 10,
                availablePoints: 50,
                dailyRemainingMinutes: 60,
                isSchoolMode: false,
                isAuthorized: true,
                selectedAppIsActive: false,
                transactionState: .inFlight
            ),
            .transactionInFlight,
            "Every duration must be disabled while one exchange transaction is running"
        )

        XCTAssertEqual(
            RewardScreenTimeUI.availability(
                dailyRequiredMinutes: 30,
                cost: 20,
                availablePoints: 10,
                dailyRemainingMinutes: 60,
                isSchoolMode: false,
                isAuthorized: true,
                selectedAppIsActive: false
            ),
            .insufficientPoints(required: 20, available: 10)
        )
        XCTAssertEqual(
            RewardScreenTimeUI.availability(
                dailyRequiredMinutes: 45,
                cost: 20,
                availablePoints: 50,
                dailyRemainingMinutes: 30,
                isSchoolMode: false,
                isAuthorized: true,
                selectedAppIsActive: false
            ),
            .dailyLimit(remainingMinutes: 30)
        )
        XCTAssertEqual(
            RewardScreenTimeUI.availability(
                dailyRequiredMinutes: 15,
                cost: 10,
                availablePoints: 50,
                dailyRemainingMinutes: 60,
                isSchoolMode: true,
                isAuthorized: false,
                selectedAppIsActive: false
            ),
            .schoolMode,
            "School Mode must be explained before authorization or balance blockers"
        )
        XCTAssertEqual(
            RewardScreenTimeUI.availability(
                dailyRequiredMinutes: 15,
                cost: 10,
                availablePoints: 50,
                dailyRemainingMinutes: 60,
                isSchoolMode: false,
                isAuthorized: false,
                selectedAppIsActive: false
            ),
            .unauthorized
        )
        XCTAssertEqual(
            RewardScreenTimeUI.availability(
                dailyRequiredMinutes: 15,
                cost: 10,
                availablePoints: 50,
                dailyRemainingMinutes: 60,
                isSchoolMode: false,
                isAuthorized: true,
                selectedAppIsActive: true
            ),
            .appAlreadyActive
        )
    }

    func testChildExchangeCopyIsBilingualAndPreReaderCopyIsShorter() {
        let blockers: [RewardExchangeAvailability] = [
            .available,
            .transactionInFlight,
            .insufficientPoints(required: 20, available: 5),
            .dailyLimit(remainingMinutes: 10),
            .schoolMode,
            .unauthorized,
            .appAlreadyActive
        ]

        for blocker in blockers {
            let chinese = RewardScreenTimeUI.detail(
                for: blocker,
                language: .chinese,
                isPreReader: false
            )
            let english = RewardScreenTimeUI.detail(
                for: blocker,
                language: .english,
                isPreReader: false
            )
            let chinesePreReader = RewardScreenTimeUI.detail(
                for: blocker,
                language: .chinese,
                isPreReader: true
            )
            let englishPreReader = RewardScreenTimeUI.detail(
                for: blocker,
                language: .english,
                isPreReader: true
            )

            XCTAssertTrue(TaskLanguageFallback.containsCJK(chinese))
            XCTAssertFalse(TaskLanguageFallback.containsCJK(english))
            XCTAssertLessThanOrEqual(chinesePreReader.count, chinese.count)
            XCTAssertLessThanOrEqual(englishPreReader.count, english.count)
            XCTAssertEqual(SpeechReader.voiceLanguageCode(language: .chinese, text: chinesePreReader), "zh-CN")
            XCTAssertEqual(SpeechReader.voiceLanguageCode(language: .english, text: englishPreReader), "en-US")
        }
    }

    func testLocalChildSelectionNeverSurvivesWithoutAGuardianPolicy() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        XCTAssertFalse(
            ScreenTimePOCManager.shouldPreserveLocalChildSelection(
                localSelectionCompleted: true,
                localCounts: ScreenTimeSelectionCounts(applications: 2, categories: 1, webDomains: 0)
            )
        )
        XCTAssertFalse(
            ScreenTimePOCManager.shouldPreserveLocalChildSelection(
                localSelectionCompleted: false,
                localCounts: ScreenTimeSelectionCounts(applications: 2, categories: 1, webDomains: 0)
            )
        )
        XCTAssertFalse(
            ScreenTimePOCManager.shouldPreserveLocalChildSelection(
                localSelectionCompleted: true,
                localCounts: .empty
            )
        )
        #endif
    }

    func testScreenTimeStatusRoundTripsMinimalNonSensitiveReceipt() throws {
        let status = FamilyScreenTimeDeviceStatus(
            authorization: .approved,
            enforcement: .applied,
            appliedPolicyRevision: 9,
            appliedSelectionHash: String(repeating: "a", count: 64),
            appliedControlCommandId: "control:unlock-1234",
            controlMode: .unlocked,
            unlockedUntil: "2026-07-29T20:30:00.000Z",
            lastErrorCode: nil,
            applicationCount: 3,
            categoryCount: 1,
            webDomainCount: 0,
            updatedAt: "2026-07-12T00:00:00Z"
        )

        let data = try JSONEncoder().encode(status)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(try JSONDecoder().decode(FamilyScreenTimeDeviceStatus.self, from: data), status)
        XCTAssertTrue(status.hasSelection)
        XCTAssertFalse(json.contains("bundle"))
        XCTAssertFalse(json.contains("applicationToken"))
        XCTAssertFalse(json.contains("applicationName"))
        XCTAssertTrue(json.contains("control:unlock-1234"))
    }

    func testRewardSpendRequiresExactCurrentLockedPolicyReceipt() {
        let selectionData = Data("guardian-policy".utf8).base64EncodedString()
        let selectionHash = FamilyScreenTimePolicy.hash(selectionData: selectionData)
        let policy = FamilyScreenTimePolicy(
            revision: 12,
            selectionData: selectionData,
            selectionHash: selectionHash,
            applicationCount: 0,
            categoryCount: 1,
            webDomainCount: 0,
            control: FamilyScreenTimeControl(
                schemaVersion: 1,
                commandId: "control:locked:12",
                mode: .locked,
                issuedAt: "2026-08-01T18:00:00.000Z",
                unlockUntil: nil
            ),
            updatedAt: "2026-08-01T18:00:00.000Z"
        )
        let current = FamilyScreenTimeDeviceStatus(
            authorization: .approved,
            enforcement: .applied,
            appliedPolicyRevision: 12,
            appliedSelectionHash: selectionHash,
            appliedControlCommandId: "control:locked:12",
            controlMode: .locked,
            lastErrorCode: nil,
            applicationCount: 0,
            categoryCount: 1,
            webDomainCount: 0,
            updatedAt: "2026-08-01T18:00:01.000Z"
        )

        XCTAssertTrue(current.acknowledgesCurrentLockedPolicy(policy))
        var stale = current
        stale.appliedPolicyRevision = 2
        stale.appliedControlCommandId = "policy:2:old"
        XCTAssertFalse(stale.acknowledgesCurrentLockedPolicy(policy))

        var expiredUnlock = policy
        expiredUnlock.control = FamilyScreenTimeControl(
            schemaVersion: 1,
            commandId: "control:locked:12",
            mode: .unlocked,
            issuedAt: "2026-08-01T17:00:00.000Z",
            unlockUntil: "2026-08-01T17:30:00.000Z"
        )
        XCTAssertTrue(
            current.acknowledgesCurrentLockedPolicy(
                expiredUnlock,
                referenceDate: Date(timeIntervalSince1970: 1_785_607_200)
            )
        )
    }

    func testScreenTimeRedemptionReceiptContainsOnlyOpaqueHashesAndPolicyIdentity() throws {
        let receipt = FamilyScreenTimeRedemptionReceipt(
            redemptionRef: UUID().uuidString.lowercased(),
            points: 15,
            minutes: 15,
            policyRevision: 12,
            selectionHash: String(repeating: "a", count: 64),
            controlCommandId: "control:locked:12",
            targetTokenHash: String(repeating: "b", count: 64),
            unlockUntil: "2026-08-01T18:15:00.000Z"
        )
        let data = try JSONEncoder().encode(receipt)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(try JSONDecoder().decode(FamilyScreenTimeRedemptionReceipt.self, from: data), receipt)
        XCTAssertFalse(json.localizedCaseInsensitiveContains("bundle"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("applicationName"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("tokenData"))
    }

    func testShieldActionReceiptExpiresWithoutPersistingAppMetadata() throws {
        let createdAt = Date(timeIntervalSince1970: 10_000)
        let request = PersistedShieldActionRequest(
            id: UUID(),
            intent: .redeemGrowthPoints,
            targetKind: .application,
            tokenData: Data([1, 2, 3, 4]),
            createdAt: createdAt
        )

        XCTAssertTrue(request.isValid(at: createdAt.addingTimeInterval(299)))
        XCTAssertFalse(request.isValid(at: createdAt.addingTimeInterval(300)))

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(request), encoding: .utf8))
        XCTAssertFalse(json.contains("bundle"))
        XCTAssertFalse(json.contains("applicationName"))
    }

    func testScreenTimeOperationAuditIsBoundedAndContainsNoAppIdentity() throws {
        let suiteName = "ScreenTimeSafetyTests.audit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let requestID = UUID()

        for index in 0..<(ScreenTimeOperationAuditLedger.maximumEntryCount + 5) {
            ScreenTimeOperationAuditLedger.append(
                PersistedScreenTimeOperationAuditEntry(
                    id: UUID(),
                    requestID: index == 36 ? requestID : UUID(),
                    stage: "single_app_unlock",
                    outcome: index == 36 ? .rejected : .started,
                    authorityRawValue: "growth_points",
                    targetKind: .application,
                    interfaceLanguageRawValue: "english",
                    durationMinutes: 15,
                    errorCode: index == 36 ? "request_expired" : nil,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index))
                ),
                defaults: defaults
            )
        }

        let entries = ScreenTimeOperationAuditLedger.load(defaults: defaults)
        XCTAssertEqual(entries.count, ScreenTimeOperationAuditLedger.maximumEntryCount)
        XCTAssertEqual(
            ScreenTimeOperationAuditLedger.latest(requestID: requestID, defaults: defaults)?.errorCode,
            "request_expired"
        )
        let json = try XCTUnwrap(
            String(
                data: try XCTUnwrap(defaults.data(forKey: ScreenTimeSharedContract.operationAuditKey)),
                encoding: .utf8
            )
        )
        XCTAssertFalse(json.localizedCaseInsensitiveContains("bundle"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("applicationName"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("tokenData"))
    }

    func testCrossDeviceEmergencyStateRoundTrips() throws {
        let emergency = FamilyScreenTimeEmergency(
            schemaVersion: 1,
            status: .approved,
            requestId: "screen-time-request-1234",
            reason: "Need to call home",
            minutes: 30,
            requestedAt: "2026-07-14T19:00:00.000Z",
            decidedAt: "2026-07-14T19:01:00.000Z",
            approvalExpiresAt: "2026-07-14T19:11:00.000Z",
            activatedAt: nil,
            sessionEndsAt: nil,
            completedAt: nil,
            expiredAt: nil,
            expirationReason: nil,
            updatedAt: "2026-07-14T19:01:00.000Z"
        )

        let data = try JSONEncoder().encode(emergency)
        XCTAssertEqual(try JSONDecoder().decode(FamilyScreenTimeEmergency.self, from: data), emergency)
        XCTAssertTrue(emergency.mayBeActivatedByChild)
        XCTAssertNotNil(emergency.approvalExpirationDate)
    }

    func testScreenTimeAuthorizationPurposePersistsOnlyChildFamilyMode() {
        let suiteName = "ScreenTimeSafetyTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ScreenTimeAuthorizationPurposeStore(defaults: defaults)

        XCTAssertNil(store.purpose)
        store.save(.childFamily)
        XCTAssertEqual(store.purpose, .childFamily)
        store.clear()
        XCTAssertNil(store.purpose)
    }

    @MainActor
    func testLegacyIndividualAuthorizationCannotControlAppsOrWebsites() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let suiteName = "ScreenTimeSafetyTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let purposeStore = ScreenTimeAuthorizationPurposeStore(defaults: defaults)
        let manager = ScreenTimePOCManager(
            usageWindowScheduler: NoopScreenTimeUsageWindowScheduler(),
            authorizationPurposeStore: purposeStore
        )

        manager.authorizationState = .approved
        XCTAssertFalse(manager.isChildFamilyAuthorizationReady)
        XCTAssertFalse(manager.canControlSelectedApps)

        manager.applyWebsiteSafety(enabledDomains: ["example.com"], automaticAdultContentFilter: true)
        XCTAssertFalse(manager.websiteSafetyIsApplied)
        #endif
    }

    @MainActor
    func testActiveSchoolModeBlocksRewardWindowBeforePointsCanBeCharged() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let manager = ScreenTimePOCManager(
            usageWindowScheduler: NoopScreenTimeUsageWindowScheduler()
        )
        manager.schoolModeIsActive = true

        XCTAssertFalse(manager.canStartRewardWindow)
        XCTAssertFalse(manager.canStartSingleAppRewardWindow)
        XCTAssertTrue(manager.rewardWindowReadinessLabel.contains("学校时段"))
        #endif
    }

    @MainActor
    func testCategoryShieldReceiptNeverPretendsToBeAnApplication() {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let manager = ScreenTimePOCManager(
            usageWindowScheduler: NoopScreenTimeUsageWindowScheduler()
        )
        let request = PersistedShieldActionRequest(
            id: UUID(),
            intent: .redeemGrowthPoints,
            targetKind: .category,
            tokenData: Data([1, 2, 3, 4]),
            createdAt: Date()
        )

        XCTAssertNil(manager.applicationToken(from: request))
        #endif
    }

    func testWebsiteSafetySeedsTwentyUniqueRecommendedDomains() {
        let persistence = MemoryWebsiteSafetyPersistence()
        let store = WebsiteSafetyStore(persistence: persistence, now: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(store.recommendedEntries.count, 20)
        XCTAssertEqual(Set(store.recommendedEntries.map(\.domain)).count, 20)
        XCTAssertEqual(store.enabledDomains.count, 20)
        XCTAssertTrue(store.automaticAdultContentFilterEnabled)
        XCTAssertEqual(persistence.snapshot?.entries.count, 20)
    }

    func testWebsiteSafetyNormalizesAndDeduplicatesGuardianDomains() {
        let store = WebsiteSafetyStore(persistence: nil)

        XCTAssertEqual(store.addGuardianDomain(" HTTPS://WWW.Example.COM/path?q=1 "), .added)
        XCTAssertEqual(store.guardianEntries.first?.domain, "example.com")
        XCTAssertEqual(store.addGuardianDomain("example.com"), .duplicate)
        XCTAssertEqual(store.addGuardianDomain("not a domain"), .invalidDomain)
    }

    func testWebsiteSafetyRoundTripsCustomEntryAndToggle() {
        let persistence = MemoryWebsiteSafetyPersistence()
        let original = WebsiteSafetyStore(persistence: persistence)
        XCTAssertEqual(original.addGuardianDomain("blocked.example"), .added)
        let id = try! XCTUnwrap(original.guardianEntries.first?.id)
        original.setEnabled(false, for: id)

        let restored = WebsiteSafetyStore(persistence: persistence)
        XCTAssertEqual(restored.guardianEntries.first?.domain, "blocked.example")
        XCTAssertEqual(restored.guardianEntries.first?.isEnabled, false)
        XCTAssertFalse(restored.enabledDomains.contains("blocked.example"))
    }

    func testEmergencyUnlockApprovalIsSingleChildAndSingleUse() {
        let store = EmergencyUnlockStore(persistence: nil)
        let childA = UUID()
        let childB = UUID()
        let guardian = UUID()
        let start = Date(timeIntervalSince1970: 10_000)
        let request = store.submit(childId: childA, reason: "Need access", now: start)

        XCTAssertEqual(store.submit(childId: childA, reason: "Again", now: start).id, request.id)
        XCTAssertTrue(store.approve(request.id, guardianId: guardian, now: start))
        XCTAssertNil(store.approvedRequest(for: childB, now: start))
        XCTAssertNotNil(store.approvedRequest(for: childA, now: start))

        let endsAt = start.addingTimeInterval(1_800)
        XCTAssertTrue(store.activate(request.id, applicationTokenData: Data([1, 2, 3]), endsAt: endsAt, now: start))
        XCTAssertFalse(store.activate(request.id, applicationTokenData: Data([4]), endsAt: endsAt, now: start))
        XCTAssertEqual(store.latestRequest(for: childA, now: start)?.status, .active)

        store.refresh(now: endsAt)
        XCTAssertEqual(store.latestRequest(for: childA, now: endsAt)?.status, .completed)
    }

    func testEmergencyApprovalExpiresWithoutUnlocking() {
        let store = EmergencyUnlockStore(persistence: nil)
        let child = UUID()
        let start = Date(timeIntervalSince1970: 20_000)
        let request = store.submit(childId: child, reason: "Need access", now: start)
        XCTAssertTrue(store.approve(request.id, guardianId: nil, now: start))

        let expired = start.addingTimeInterval(EmergencyUnlockStore.approvalLifetime + 1)
        XCTAssertNil(store.approvedRequest(for: child, now: expired))
        XCTAssertEqual(store.latestRequest(for: child, now: expired)?.status, .expiredUnused)
    }

    func testRewardFailureRefundsOriginatingChildAfterActiveChildChanges() {
        let family = LocalFamilyStore()
        let firstChildID = family.activeChildId
        family.child.rewardBalanceMinutes = 100
        let second = try! XCTUnwrap(family.addChild(name: "Second", age: 8))
        let controller = MockScreenTimeController()

        let result = StartRewardSessionUseCase(store: family, screenTimeController: controller)(
            minutes: 15,
            externalDeviceStart: { _, _ in
                family.setActiveChild(second.id)
                throw UnlockError.deviceCommandFailed
            }
        )

        XCTAssertEqual(result, .deviceFailureRolledBack)
        XCTAssertEqual(family.children.first(where: { $0.id == firstChildID })?.rewardBalanceMinutes, 100)
        XCTAssertEqual(family.children.first(where: { $0.id == second.id })?.rewardBalanceMinutes, 0)
    }

    func testRewardWindowLedgerAllowsDifferentAppsButRejectsTheSameAppTwice() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let first = PersistedScreenTimeRewardWindow(
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "first app"
        )
        let second = PersistedScreenTimeRewardWindow(
            applicationTokenData: Data([2]),
            startedAt: start,
            endsAt: start.addingTimeInterval(1_800),
            sourceLabel: "second app"
        )

        let withFirst = try ScreenTimeRewardWindowLedger.adding(first, to: [], at: start)
        let withBoth = try ScreenTimeRewardWindowLedger.adding(second, to: withFirst, at: start)

        XCTAssertEqual(withBoth.count, 2)
        XCTAssertThrowsError(try ScreenTimeRewardWindowLedger.adding(first, to: withBoth, at: start)) { error in
            XCTAssertEqual(error as? ScreenTimeRewardWindowLedger.Error, .alreadyActive)
        }
    }

    func testOpaqueTokenRefreshMigratesRewardWindowsAndApplicationShieldRequest() throws {
        let requestID = UUID()
        let windowID = UUID()
        let start = Date(timeIntervalSince1970: 35_000)
        let window = PersistedScreenTimeRewardWindow(
            id: windowID,
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "reward",
            selectionGeneration: 7,
            startedAtSystemUptime: 100
        )
        let request = PersistedShieldActionRequest(
            id: requestID,
            intent: .redeemGrowthPoints,
            targetKind: .application,
            tokenData: Data([2]),
            createdAt: start,
            interfaceLanguageRawValue: "english",
            selectionGeneration: 7
        )
        let tokenMap = try ScreenTimeOpaqueTokenRefreshMigration.makeTokenMap(
            oldTokenData: [Data([1]), Data([2])],
            refreshedTokenData: [Data([11]), Data([22])]
        )

        let result = try ScreenTimeOpaqueTokenRefreshMigration.migrate(
            tokenMap: tokenMap,
            rewardWindows: [window],
            shieldActionRequest: request
        )

        XCTAssertEqual(result.rewardWindows.first?.applicationTokenData, Data([11]))
        XCTAssertEqual(result.rewardWindows.first?.resolvedID, windowID)
        XCTAssertEqual(result.rewardWindows.first?.selectionGeneration, 7)
        XCTAssertEqual(result.rewardWindows.first?.startedAtSystemUptime, 100)
        XCTAssertEqual(result.shieldActionRequest?.id, requestID)
        XCTAssertEqual(result.shieldActionRequest?.tokenData, Data([22]))
        XCTAssertEqual(result.shieldActionRequest?.intent, .redeemGrowthPoints)
        XCTAssertEqual(result.shieldActionRequest?.validatedInterfaceLanguageRawValue, "english")
        XCTAssertEqual(result.shieldActionRequest?.selectionGeneration, 7)
    }

    func testOpaqueTokenRefreshLeavesCategoryShieldRequestUnchanged() throws {
        let request = PersistedShieldActionRequest(
            id: UUID(),
            intent: .parentPIN,
            targetKind: .category,
            tokenData: Data([9]),
            createdAt: Date(timeIntervalSince1970: 36_000),
            interfaceLanguageRawValue: "chinese",
            selectionGeneration: 3
        )

        let result = try ScreenTimeOpaqueTokenRefreshMigration.migrate(
            tokenMap: [:],
            rewardWindows: [],
            shieldActionRequest: request
        )

        XCTAssertEqual(result.shieldActionRequest, request)
    }

    func testOpaqueTokenRefreshRejectsInvalidMapsAndMissingRuntimeToken() throws {
        XCTAssertThrowsError(
            try ScreenTimeOpaqueTokenRefreshMigration.makeTokenMap(
                oldTokenData: [Data([1])],
                refreshedTokenData: []
            )
        ) { error in
            XCTAssertEqual(
                error as? ScreenTimeOpaqueTokenRefreshMigration.Error,
                .mismatchedTokenCount
            )
        }
        XCTAssertThrowsError(
            try ScreenTimeOpaqueTokenRefreshMigration.makeTokenMap(
                oldTokenData: [Data([1]), Data([1])],
                refreshedTokenData: [Data([2]), Data([3])]
            )
        ) { error in
            XCTAssertEqual(
                error as? ScreenTimeOpaqueTokenRefreshMigration.Error,
                .duplicateSourceToken
            )
        }
        XCTAssertThrowsError(
            try ScreenTimeOpaqueTokenRefreshMigration.makeTokenMap(
                oldTokenData: [Data([1]), Data([2])],
                refreshedTokenData: [Data([3]), Data([3])]
            )
        ) { error in
            XCTAssertEqual(
                error as? ScreenTimeOpaqueTokenRefreshMigration.Error,
                .duplicateRefreshedToken
            )
        }

        let window = PersistedScreenTimeRewardWindow(
            applicationTokenData: Data([4]),
            startedAt: Date(timeIntervalSince1970: 37_000),
            endsAt: Date(timeIntervalSince1970: 37_900),
            sourceLabel: "missing"
        )
        XCTAssertThrowsError(
            try ScreenTimeOpaqueTokenRefreshMigration.migrate(
                tokenMap: [Data([1]): Data([2])],
                rewardWindows: [window],
                shieldActionRequest: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? ScreenTimeOpaqueTokenRefreshMigration.Error,
                .missingTokenMapping
            )
        }
    }

    func testRewardWindowLedgerExpiresOneAppWithoutEndingAnother() throws {
        let start = Date(timeIntervalSince1970: 40_000)
        let first = PersistedScreenTimeRewardWindow(
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "first app"
        )
        let second = PersistedScreenTimeRewardWindow(
            applicationTokenData: Data([2]),
            startedAt: start,
            endsAt: start.addingTimeInterval(1_800),
            sourceLabel: "second app"
        )
        let windows = try ScreenTimeRewardWindowLedger.adding(
            second,
            to: ScreenTimeRewardWindowLedger.adding(first, to: [], at: start),
            at: start
        )

        let active = ScreenTimeRewardWindowLedger.active(
            windows,
            at: start.addingTimeInterval(901)
        )

        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.applicationTokenData, Data([2]))
    }

    func testRewardActivityCallbackExpiresOnlyItsAppAndLeavesAnotherWindowActive() throws {
        let start = Date(timeIntervalSince1970: 45_000)
        let first = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "first app"
        )
        let second = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([2]),
            startedAt: start,
            endsAt: start.addingTimeInterval(1_800),
            sourceLabel: "second app"
        )

        let reconciled = ScreenTimeRewardWindowLedger.activeWindowsForCallback(
            activityName: ScreenTimeSharedContract.rewardActivityName(for: first.resolvedID),
            storedWindows: [first, second],
            at: start.addingTimeInterval(901)
        )

        XCTAssertEqual(reconciled?.map(\.resolvedID), [second.resolvedID])
    }

    func testSchoolPINSessionReferencesAreUniqueAndOpaque() throws {
        let fixedID = try XCTUnwrap(
            UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")
        )

        XCTAssertEqual(
            ScreenTimeSharedContract.schoolPINSessionRef(id: fixedID),
            "school-pin:00112233-4455-6677-8899-aabbccddeeff"
        )
        XCTAssertNotEqual(
            ScreenTimeSharedContract.schoolPINSessionRef(),
            ScreenTimeSharedContract.schoolPINSessionRef()
        )
    }

    func testRewardIntervalEndIsAuthoritativeWhenWallClockMovesBackward() {
        let start = Date(timeIntervalSince1970: 46_000)
        let first = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "first app"
        )
        let second = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([2]),
            startedAt: start,
            endsAt: start.addingTimeInterval(1_800),
            sourceLabel: "second app"
        )

        let reconciled = ScreenTimeRewardWindowLedger.activeWindowsForCallback(
            activityName: ScreenTimeSharedContract.rewardActivityName(for: first.resolvedID),
            phase: .intervalEnded,
            storedWindows: [first, second],
            at: start.addingTimeInterval(300)
        )

        XCTAssertEqual(reconciled?.map(\.resolvedID), [second.resolvedID])
    }

    func testRewardIntervalStartDoesNotPrematurelyRelockItsApp() {
        let start = Date(timeIntervalSince1970: 46_500)
        let window = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "app"
        )

        let reconciled = ScreenTimeRewardWindowLedger.activeWindowsForCallback(
            activityName: ScreenTimeSharedContract.rewardActivityName(for: window.resolvedID),
            phase: .intervalStarted,
            storedWindows: [window],
            at: start
        )

        XCTAssertEqual(reconciled?.map(\.resolvedID), [window.resolvedID])
    }

    func testRewardWindowUsesMonotonicDeadlineWhenWallClockMovesBackward() {
        let start = Date(timeIntervalSince1970: 46_800)
        let window = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "app",
            startedAtSystemUptime: 10_000
        )

        XCTAssertEqual(
            ScreenTimeRewardWindowLedger.active(
                [window],
                at: start.addingTimeInterval(60),
                systemUptime: 10_899
            ).count,
            1
        )
        XCTAssertTrue(
            ScreenTimeRewardWindowLedger.active(
                [window],
                at: start.addingTimeInterval(60),
                systemUptime: 10_900
            ).isEmpty
        )
    }

    func testRewardWindowFailsClosedAfterDeviceRestart() {
        let start = Date(timeIntervalSince1970: 46_900)
        let window = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(3_600),
            sourceLabel: "app",
            startedAtSystemUptime: 100_000
        )

        XCTAssertTrue(
            ScreenTimeRewardWindowLedger.active(
                [window],
                at: start.addingTimeInterval(60),
                systemUptime: 20
            ).isEmpty
        )
    }

    func testHistoricalRewardActivityCannotMutateReplacementOrClearedLedger() {
        let start = Date(timeIntervalSince1970: 47_000)
        let historicalID = UUID()
        let replacement = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(1_800),
            sourceLabel: "replacement"
        )
        let historicalActivity = ScreenTimeSharedContract.rewardActivityName(for: historicalID)

        XCTAssertNil(
            ScreenTimeRewardWindowLedger.activeWindowsForCallback(
                activityName: historicalActivity,
                storedWindows: [replacement],
                at: start.addingTimeInterval(900)
            )
        )
        XCTAssertNil(
            ScreenTimeRewardWindowLedger.activeWindowsForCallback(
                activityName: historicalActivity,
                storedWindows: [],
                at: start.addingTimeInterval(900)
            )
        )
        XCTAssertNil(
            ScreenTimeRewardWindowLedger.activeWindowsForCallback(
                activityName: ScreenTimeSharedContract.rewardActivityName,
                storedWindows: [replacement],
                at: start.addingTimeInterval(900)
            )
        )
    }

    func testOutOfOrderRewardCallbacksRemainIdempotentAcrossMultipleApps() throws {
        let start = Date(timeIntervalSince1970: 47_500)
        let first = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "first app"
        )
        let second = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([2]),
            startedAt: start,
            endsAt: start.addingTimeInterval(1_800),
            sourceLabel: "second app"
        )
        let firstActivity = ScreenTimeSharedContract.rewardActivityName(for: first.resolvedID)
        let secondActivity = ScreenTimeSharedContract.rewardActivityName(for: second.resolvedID)

        let afterFirstEnd = try XCTUnwrap(
            ScreenTimeRewardWindowLedger.activeWindowsForCallback(
                activityName: firstActivity,
                phase: .intervalEnded,
                storedWindows: [first, second],
                at: start.addingTimeInterval(900)
            )
        )
        XCTAssertEqual(afterFirstEnd.map(\.resolvedID), [second.resolvedID])

        XCTAssertNil(
            ScreenTimeRewardWindowLedger.activeWindowsForCallback(
                activityName: firstActivity,
                phase: .intervalEnded,
                storedWindows: afterFirstEnd,
                at: start.addingTimeInterval(901)
            )
        )

        let afterSecondStart = try XCTUnwrap(
            ScreenTimeRewardWindowLedger.activeWindowsForCallback(
                activityName: secondActivity,
                phase: .intervalStarted,
                storedWindows: afterFirstEnd,
                at: start.addingTimeInterval(901)
            )
        )
        XCTAssertEqual(afterSecondStart.map(\.resolvedID), [second.resolvedID])

        let afterSecondEnd = try XCTUnwrap(
            ScreenTimeRewardWindowLedger.activeWindowsForCallback(
                activityName: secondActivity,
                phase: .intervalEnded,
                storedWindows: afterSecondStart,
                at: start.addingTimeInterval(1_800)
            )
        )
        XCTAssertTrue(afterSecondEnd.isEmpty)
    }

    func testLegacyRewardWindowGetsStableMigrationID() {
        let start = Date(timeIntervalSince1970: 48_000)
        var legacy = PersistedScreenTimeRewardWindow(
            applicationTokenData: Data([4, 8, 15, 16, 23, 42]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "legacy"
        )
        legacy.id = nil

        XCTAssertEqual(legacy.resolvedID, legacy.resolvedID)
        XCTAssertEqual(legacy.normalized().id, legacy.resolvedID)
    }

    func testLegacyRewardStoreDoesNotRemoveLegacyKeyUntilV2SaveCommits() throws {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let suiteName = "ScreenTimeSafetyTests.LegacyReward.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let start = Date(timeIntervalSince1970: 48_500)
        var legacy = PersistedScreenTimeRewardWindow(
            applicationTokenData: Data([1, 2, 3]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "legacy"
        )
        legacy.id = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(
            try encoder.encode(legacy),
            forKey: ScreenTimeSharedContract.activeRewardWindowKey
        )
        let store = ScreenTimeRewardWindowStore(defaults: defaults)

        XCTAssertTrue(store.containsLegacyWindow)
        let loaded = store.loadAll()
        XCTAssertEqual(loaded.first?.id, legacy.resolvedID)
        XCTAssertNotNil(defaults.data(forKey: ScreenTimeSharedContract.activeRewardWindowKey))

        try store.saveAll(loaded)
        XCTAssertFalse(store.containsLegacyWindow)
        XCTAssertNil(defaults.object(forKey: ScreenTimeSharedContract.activeRewardWindowKey))
        XCTAssertNotNil(defaults.data(forKey: ScreenTimeSharedContract.activeRewardWindowsKey))
        #endif
    }

    func testLegacyRewardMigrationRegistersUUIDActivitiesBeforeV2AndLegacyCancellation() throws {
        let activityNames = ["uuid-one", "uuid-two"]
        var events: [String] = []

        try ScreenTimeRewardWindowTransaction.commitLegacyMigration(
            activityNames: activityNames,
            register: { events.append("register:\($0)") },
            persistV2: { events.append("persist-v2") },
            cancelRegistered: { events.append("cancel-new:\($0.joined(separator: ","))") },
            cancelLegacy: { events.append("cancel-legacy") }
        )

        XCTAssertEqual(
            events,
            ["register:uuid-one", "register:uuid-two", "persist-v2", "cancel-legacy"]
        )
    }

    func testLegacyRewardMigrationKeepsLegacyStateWhenUUIDRegistrationFails() {
        enum Failure: Error { case expected }
        var events: [String] = []

        XCTAssertThrowsError(
            try ScreenTimeRewardWindowTransaction.commitLegacyMigration(
                activityNames: ["uuid-one", "uuid-two"],
                register: { name in
                    events.append("register:\(name)")
                    if name == "uuid-two" { throw Failure.expected }
                },
                persistV2: { events.append("persist-v2") },
                cancelRegistered: { events.append("cancel-new:\($0.joined(separator: ","))") },
                cancelLegacy: { events.append("cancel-legacy") }
            )
        )
        XCTAssertEqual(
            events,
            ["register:uuid-one", "register:uuid-two", "cancel-new:uuid-one"]
        )
    }

    func testPendingCompensationRemovesOnlyItsRewardWindowAndDeduplicates() {
        let start = Date(timeIntervalSince1970: 49_000)
        let first = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([1]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "first"
        )
        let second = PersistedScreenTimeRewardWindow(
            id: UUID(),
            applicationTokenData: Data([2]),
            startedAt: start,
            endsAt: start.addingTimeInterval(900),
            sourceLabel: "second"
        )
        let pending = ScreenTimeRewardCompensationLedger.adding(
            id: first.resolvedID,
            at: start,
            to: ScreenTimeRewardCompensationLedger.adding(
                id: first.resolvedID,
                at: start,
                to: []
            )
        )

        let result = ScreenTimeRewardCompensationLedger.applying(pending, to: [first, second])

        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(result.removed.map(\.resolvedID), [first.resolvedID])
        XCTAssertEqual(result.remaining.map(\.resolvedID), [second.resolvedID])
    }

    func testPendingCompensationPersistsUntilExplicitlyCleared() throws {
        #if canImport(FamilyControls) && canImport(ManagedSettings)
        let suiteName = "ScreenTimeSafetyTests.Compensation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ScreenTimeRewardCompensationStore(defaults: defaults)
        let id = UUID()
        let now = Date(timeIntervalSince1970: 49_500)

        try store.add(id: id, requestedAt: now)
        XCTAssertEqual(ScreenTimeRewardCompensationStore(defaults: defaults).load(), [
            PersistedScreenTimeRewardCompensation(id: id, requestedAt: now),
        ])

        try store.remove(ids: [id])
        XCTAssertTrue(store.load().isEmpty)

        defaults.set(
            Data("not-json".utf8),
            forKey: ScreenTimeSharedContract.pendingRewardCompensationsKey
        )
        XCTAssertFalse(store.isReadable)
        XCTAssertThrowsError(try store.add(id: UUID(), requestedAt: now))
        #endif
    }

    func testRewardStartRollsBackScheduleWhenSchedulingOrPersistenceFails() {
        enum Failure: Error { case expected }
        var events: [String] = []

        XCTAssertThrowsError(
            try ScreenTimeRewardWindowTransaction.commitStart(
                schedule: {
                    events.append("schedule")
                    throw Failure.expected
                },
                persist: { events.append("persist") },
                rollbackSchedule: { events.append("cancel") }
            )
        )
        XCTAssertEqual(events, ["schedule", "cancel"])

        events = []
        XCTAssertThrowsError(
            try ScreenTimeRewardWindowTransaction.commitStart(
                schedule: { events.append("schedule") },
                persist: {
                    events.append("persist")
                    throw Failure.expected
                },
                rollbackPersistence: { events.append("restore") },
                rollbackSchedule: { events.append("cancel") }
            )
        )
        XCTAssertEqual(events, ["schedule", "persist", "restore", "cancel"])
    }

    func testRewardMutationDoesNotApplyOrCancelBeforePersistenceCommits() {
        enum Failure: Error { case expected }
        var events: [String] = []

        XCTAssertThrowsError(
            try ScreenTimeRewardWindowTransaction.commitMutation(
                persist: {
                    events.append("persist")
                    throw Failure.expected
                },
                apply: { events.append("apply") },
                cancelObsoleteSchedules: { events.append("cancel") }
            )
        )
        XCTAssertEqual(events, ["persist"])

        events = []
        XCTAssertNoThrow(
            try ScreenTimeRewardWindowTransaction.commitMutation(
                persist: { events.append("persist") },
                apply: { events.append("apply") },
                cancelObsoleteSchedules: { events.append("cancel") }
            )
        )
        XCTAssertEqual(events, ["persist", "apply", "cancel"])

        events = []
        XCTAssertThrowsError(
            try ScreenTimeRewardWindowTransaction.commitMutation(
                persist: { events.append("persist") },
                apply: {
                    events.append("apply")
                    throw Failure.expected
                },
                cancelObsoleteSchedules: { events.append("cancel") }
            )
        )
        XCTAssertEqual(events, ["persist", "apply"])
    }

    func testStartupConvergenceRetainsWriteAheadWhenShieldVerificationFails() {
        enum Failure: Error { case shieldVerification }
        var events: [String] = []
        var compensationIsDurable = false

        XCTAssertThrowsError(
            try ScreenTimeRewardWindowTransaction.commitCompensatedMutation(
                persistCompensation: {
                    events.append("persist-compensation")
                    compensationIsDurable = true
                },
                persistAndApply: {
                    events.append("persist-ledger")
                    events.append("verify-shield")
                    throw Failure.shieldVerification
                },
                cancelObsoleteSchedules: { events.append("cancel-schedule") },
                clearCompensation: {
                    events.append("clear-compensation")
                    compensationIsDurable = false
                }
            )
        )

        XCTAssertEqual(events, ["persist-compensation", "persist-ledger", "verify-shield"])
        XCTAssertTrue(compensationIsDurable, "Startup must remain retryable after a shield failure")
    }

    func testPersistedSchoolModeAlwaysBlocksOrdinaryRewardUnlockAfterRelaunch() {
        XCTAssertTrue(
            ScreenTimeSharedContract.schoolModeBlocksRewardUnlock(
                inMemoryIsActive: false,
                persistedIsActive: true
            )
        )
        XCTAssertTrue(
            ScreenTimeSharedContract.schoolModeBlocksRewardUnlock(
                inMemoryIsActive: true,
                persistedIsActive: false
            )
        )
        XCTAssertFalse(
            ScreenTimeSharedContract.schoolModeBlocksRewardUnlock(
                inMemoryIsActive: false,
                persistedIsActive: false
            )
        )
    }

    func testPaidUnlockRequiresVerifiedClearSchoolStoreBeforeCommit() {
        XCTAssertTrue(
            ScreenTimeSharedContract.paidUnlockCanCommit(
                schoolModeIsActive: false,
                schoolStoreIsClear: true
            )
        )
        XCTAssertFalse(
            ScreenTimeSharedContract.paidUnlockCanCommit(
                schoolModeIsActive: false,
                schoolStoreIsClear: false
            ),
            "A residual school shield must fail the paid unlock"
        )
        XCTAssertFalse(
            ScreenTimeSharedContract.paidUnlockCanCommit(
                schoolModeIsActive: false,
                schoolStoreIsClear: nil
            ),
            "Unknown school-store state must not return a chargeable success"
        )
        XCTAssertFalse(
            ScreenTimeSharedContract.paidUnlockCanCommit(
                schoolModeIsActive: true,
                schoolStoreIsClear: true
            )
        )
    }

    func testConcurrentAppUnlocksChargeAndTrackIndependentSessions() {
        let family = LocalFamilyStore()
        family.child.rewardBalanceMinutes = 120
        let controller = MockScreenTimeController(persistenceKey: nil)
        let start = Date(timeIntervalSince1970: 50_000)
        let firstID = UUID()
        let secondID = UUID()
        let useCase = StartRewardSessionUseCase(store: family, screenTimeController: controller)

        let first = useCase(
            minutes: 15,
            now: start,
            concurrentExternalDeviceStart: { _, now in
                ScreenTimeExternalSession(id: firstID, endsAt: now.addingTimeInterval(900))
            }
        )
        let second = useCase(
            minutes: 30,
            now: start.addingTimeInterval(60),
            concurrentExternalDeviceStart: { _, now in
                ScreenTimeExternalSession(id: secondID, endsAt: now.addingTimeInterval(1_800))
            }
        )

        XCTAssertEqual(first, .started(endsAt: start.addingTimeInterval(900)))
        XCTAssertEqual(second, .started(endsAt: start.addingTimeInterval(1_860)))
        XCTAssertEqual(controller.activeGrants.map(\.id), [firstID, secondID])
        XCTAssertEqual(controller.grantedMinutes(on: start), 31)
        XCTAssertEqual(family.child.rewardBalanceMinutes, 75)

        _ = controller.tick(now: start.addingTimeInterval(901))
        XCTAssertEqual(controller.sessionStatus, .active)
        XCTAssertEqual(controller.activeGrants.map(\.id), [secondID])
        XCTAssertEqual(controller.unlockEndsAt, start.addingTimeInterval(1_860))
    }

    func testFullyOverlappingAppUnlockDoesNotConsumeDailyAllowanceTwice() throws {
        let controller = MockScreenTimeController(persistenceKey: nil)
        let start = Date(timeIntervalSince1970: 50_000)
        try controller.adoptConcurrentExternalUnlock(
            sessionID: UUID(),
            minutes: 60,
            now: start,
            endsAt: start.addingTimeInterval(3_600)
        )

        XCTAssertEqual(controller.grantedMinutes(on: start), 60)
        XCTAssertEqual(
            controller.additionalGrantedMinutes(for: 60, startingAt: start),
            0,
            "A second App opened for the same wall-clock window must not double-charge the daily allowance"
        )
        XCTAssertEqual(
            RewardScreenTimeUI.availability(
                dailyRequiredMinutes: 0,
                cost: 20,
                availablePoints: 20,
                dailyRemainingMinutes: 0,
                isSchoolMode: false,
                isAuthorized: true,
                selectedAppIsActive: false
            ),
            .available
        )
    }

    func testSequentialAppUnlockConsumesAdditionalDailyAllowance() throws {
        let controller = MockScreenTimeController(persistenceKey: nil)
        let start = Date(timeIntervalSince1970: 50_000)
        try controller.adoptConcurrentExternalUnlock(
            sessionID: UUID(),
            minutes: 30,
            now: start,
            endsAt: start.addingTimeInterval(1_800)
        )

        XCTAssertEqual(
            controller.additionalGrantedMinutes(
                for: 30,
                startingAt: start.addingTimeInterval(1_800)
            ),
            30
        )
    }

    func testDailyAllowanceClipsUnlockWindowAcrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(
            from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 7,
                day: 27,
                hour: 23,
                minute: 30
            )
        )!
        let controller = MockScreenTimeController(persistenceKey: nil)
        try controller.adoptConcurrentExternalUnlock(
            sessionID: UUID(),
            minutes: 60,
            now: start,
            endsAt: start.addingTimeInterval(3_600)
        )

        XCTAssertEqual(controller.grantedMinutes(on: start, calendar: calendar), 30)
        XCTAssertEqual(
            controller.grantedMinutes(
                on: start.addingTimeInterval(3_600),
                calendar: calendar
            ),
            30
        )
    }

    func testEndingOneConcurrentAppLeavesTheOtherRunning() throws {
        let controller = MockScreenTimeController(persistenceKey: nil)
        let start = Date(timeIntervalSince1970: 60_000)
        let firstID = UUID()
        let secondID = UUID()
        try controller.adoptConcurrentExternalUnlock(
            sessionID: firstID,
            minutes: 15,
            now: start,
            endsAt: start.addingTimeInterval(900)
        )
        try controller.adoptConcurrentExternalUnlock(
            sessionID: secondID,
            minutes: 30,
            now: start,
            endsAt: start.addingTimeInterval(1_800)
        )

        let receipt = controller.endConcurrentExternalUnlock(
            sessionID: firstID,
            now: start.addingTimeInterval(300)
        )

        XCTAssertEqual(receipt?.grantedMinutes, 15)
        XCTAssertEqual(controller.sessionStatus, .active)
        XCTAssertEqual(controller.activeGrants.map(\.id), [secondID])
        XCTAssertEqual(controller.unlockEndsAt, start.addingTimeInterval(1_800))
    }

    func testCompletedConcurrentAppReceiptPreservesAliasAndQueuesOnce() throws {
        let controller = MockScreenTimeController(persistenceKey: nil)
        let start = Date(timeIntervalSince1970: 65_000)
        let sessionID = UUID()
        let appUsageRef = "app:0123456789abcdef0123456789abcdef"

        try controller.adoptConcurrentExternalUnlock(
            sessionID: sessionID,
            minutes: 15,
            now: start,
            endsAt: start.addingTimeInterval(900),
            authority: .growthPoints,
            appUsageRef: appUsageRef
        )

        let receipt = try XCTUnwrap(controller.endConcurrentExternalUnlock(
            sessionID: sessionID,
            now: start.addingTimeInterval(301)
        ))

        XCTAssertEqual(receipt.sessionID, sessionID)
        XCTAssertEqual(receipt.appUsageRef, appUsageRef)
        XCTAssertEqual(receipt.consumedMinutes, 6)
        XCTAssertEqual(controller.pendingActivityReceipts.map(\.id), [receipt.id])

        controller.markActivityReceiptQueued(receipt.id)

        XCTAssertTrue(controller.pendingActivityReceipts.isEmpty)
    }

    func testParentAndEmergencyUnlocksDoNotConsumeGrowthPointDailyLimit() throws {
        let controller = MockScreenTimeController(persistenceKey: nil)
        let start = Date(timeIntervalSince1970: 70_000)
        let growthPointID = UUID()
        let parentPINID = UUID()
        let emergencyID = UUID()

        try controller.adoptConcurrentExternalUnlock(
            sessionID: growthPointID,
            minutes: 15,
            now: start,
            endsAt: start.addingTimeInterval(900),
            authority: .growthPoints
        )
        try controller.adoptConcurrentExternalUnlock(
            sessionID: parentPINID,
            minutes: 30,
            now: start,
            endsAt: start.addingTimeInterval(1_800),
            authority: .parentPIN
        )
        try controller.adoptConcurrentExternalUnlock(
            sessionID: emergencyID,
            minutes: 60,
            now: start,
            endsAt: start.addingTimeInterval(3_600),
            authority: .schoolEmergency
        )

        XCTAssertEqual(controller.grantedMinutes(on: start), 15)

        let parentReceipt = try XCTUnwrap(controller.endConcurrentExternalUnlock(
            sessionID: parentPINID,
            now: start.addingTimeInterval(300)
        ))
        XCTAssertEqual(parentReceipt.resolvedAuthority, .parentPIN)
        XCTAssertEqual(controller.grantedMinutes(on: start), 15)
    }

    func testLegacyActiveGrantWithoutAuthorityDefaultsToGrowthPoints() throws {
        let sessionID = UUID()
        let json = """
        {
          "sessionStatus": "active",
          "unlockStartedAt": "1970-01-01T00:00:00Z",
          "unlockEndsAt": "1970-01-01T00:15:00Z",
          "activeMinutes": 15,
          "receipts": [],
          "activeGrants": [
            {
              "id": "\(sessionID.uuidString)",
              "startedAt": "1970-01-01T00:00:00Z",
              "endsAt": "1970-01-01T00:15:00Z",
              "minutes": 15
            }
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(ScreenTimeSessionSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.activeGrants?.first?.resolvedAuthority, .growthPoints)
    }

    func testGuardianCustomScreenRateControlsPointCost() {
        var policy = FamilyExchangePolicy.default
        policy.customScreenPointsPer15Minutes = 7

        XCTAssertEqual(policy.screenPointsRequired(forMinutes: 15), 7)
        XCTAssertEqual(policy.screenPointsRequired(forMinutes: 30), 14)
        XCTAssertEqual(policy.screenPointsRequired(forMinutes: 10), 5)
        XCTAssertEqual(policy.screenRateLabel, "每 15 分钟需要 7 成长积分")
    }

    func testParentScreenTimeActivityMergesAndDeduplicatesRecentEvents() {
        let older = FamilyCloudActivitySummary.RecentEvent(
            eventId: "older",
            kind: .screenTime,
            occurredAt: "2026-07-24T10:00:00Z",
            durationSeconds: 900,
            progressPercent: nil,
            displayName: "App Authorized Time",
            resourceRef: "authority:growth_points"
        )
        let duplicate = FamilyCloudActivitySummary.RecentEvent(
            eventId: "duplicate",
            kind: .screenTime,
            occurredAt: "2026-07-25T10:00:00Z",
            durationSeconds: 1_800,
            progressPercent: nil,
            displayName: "App Authorized Time",
            resourceRef: "authority:parent_pin"
        )
        let nonScreenTime = FamilyCloudActivitySummary.RecentEvent(
            eventId: "task",
            kind: .task,
            occurredAt: "2026-07-25T12:00:00Z",
            durationSeconds: 60,
            progressPercent: nil,
            displayName: "Task",
            resourceRef: nil
        )
        let history = FamilyCloudActivitySummary(
            windowDays: 90,
            summary: [],
            recent: [older, duplicate, nonScreenTime]
        )
        let today = FamilyCloudActivitySummary(
            windowDays: 1,
            summary: [],
            recent: [duplicate]
        )

        let events = ParentScreenTimeActivityFormatter.recentEvents(today: today, history: history)

        XCTAssertEqual(events.map(\.eventId), ["duplicate", "older"])
    }

    func testParentScreenTimeActivitySourceLabelsAreLocalized() {
        XCTAssertEqual(
            ParentScreenTimeActivityFormatter.sourceLabel(
                resourceRef: "authority:growth_points",
                language: .english
            ),
            "Growth Points"
        )
        XCTAssertEqual(
            ParentScreenTimeActivityFormatter.sourceLabel(
                resourceRef: "authority:parent_pin:app:0123456789abcdef0123456789abcdef",
                language: .chinese
            ),
            "家长 PIN"
        )
        XCTAssertEqual(
            ParentScreenTimeActivityFormatter.sourceLabel(
                resourceRef: nil,
                language: .english
            ),
            "Other Approval"
        )
        XCTAssertEqual(
            ParentScreenTimeActivityFormatter.sourceIcon(
                resourceRef: "authority:growth_points:app:0123456789abcdef0123456789abcdef"
            ),
            "leaf.fill"
        )
    }

    func testParentScreenTimeActivityAggregatesOnlyTodayAnonymousAppRows() {
        let first = FamilyCloudActivitySummary.ScreenTimeAppDailyRow(
            date: "2026-07-25",
            appRef: "app:0123456789abcdef0123456789abcdef",
            authority: "growth_points",
            durationSeconds: 900,
            eventCount: 1
        )
        let other = FamilyCloudActivitySummary.ScreenTimeAppDailyRow(
            date: "2026-07-25",
            appRef: "app:fedcba9876543210fedcba9876543210",
            authority: "growth_points",
            durationSeconds: 600,
            eventCount: 1
        )
        let yesterday = FamilyCloudActivitySummary.ScreenTimeAppDailyRow(
            date: "2026-07-24",
            appRef: "app:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            authority: "parent_pin",
            durationSeconds: 7_200,
            eventCount: 2
        )
        let today = FamilyCloudActivitySummary(
            windowDays: 1,
            summary: [],
            recent: [],
            screenTimeAppDaily: [first, other, yesterday]
        )
        let rows = ParentScreenTimeActivityFormatter.todayAppAuthorizationSummaries(
            today: today,
            localDate: "2026-07-25"
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.durationSeconds, 900)
        XCTAssertEqual(rows.first?.eventCount, 1)
        XCTAssertEqual(
            ParentScreenTimeActivityFormatter.appDisplayLabel(
                appRef: rows[0].appRef,
                language: .english
            ),
            "Controlled App • 0123"
        )
        XCTAssertEqual(
            ParentScreenTimeActivityFormatter.appDisplayLabel(
                appRef: rows[0].appRef,
                language: .chinese
            ),
            "受控 App • 0123"
        )
    }

    func testParentScreenTimeActivityGroupsRecentAppHistoryByDayAndAuthority() {
        let appRef = "app:0123456789abcdef0123456789abcdef"
        let summary = FamilyCloudActivitySummary(
            windowDays: 90,
            summary: [],
            recent: [],
            screenTimeAppDaily: [
                .init(
                    date: "2026-07-24",
                    appRef: appRef,
                    authority: "growth_points",
                    durationSeconds: 900,
                    eventCount: 1
                ),
                .init(
                    date: "2026-07-25",
                    appRef: appRef,
                    authority: "growth_points",
                    durationSeconds: 1_800,
                    eventCount: 2
                ),
                .init(
                    date: "2026-07-25",
                    appRef: appRef,
                    authority: "growth_points",
                    durationSeconds: 900,
                    eventCount: 1
                ),
                .init(
                    date: "2026-07-25",
                    appRef: appRef,
                    authority: "parent_pin",
                    durationSeconds: 3_600,
                    eventCount: 1
                ),
            ]
        )

        let days = ParentScreenTimeActivityFormatter.appAuthorizationHistory(
            history: summary,
            limitDays: 7
        )

        XCTAssertEqual(days.map(\.date), ["2026-07-25", "2026-07-24"])
        XCTAssertEqual(days[0].durationSeconds, 6_300)
        XCTAssertEqual(days[0].eventCount, 4)
        XCTAssertEqual(days[0].rows.count, 2)
        XCTAssertEqual(days[0].rows[0].authority, "parent_pin")
        XCTAssertEqual(days[0].rows[0].durationSeconds, 3_600)
        XCTAssertEqual(days[0].rows[1].durationSeconds, 2_700)
        XCTAssertTrue(
            ParentScreenTimeActivityFormatter.appAuthorizationHistory(
                history: summary,
                limitDays: 0
            ).isEmpty
        )
    }

    func testApplicationUsageAliasIsStableAnonymousAndTokenSpecific() throws {
        let suiteName = "screen-time-app-alias-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstToken = Data([0x01, 0x02, 0x03, 0x04])
        let secondToken = Data([0x04, 0x03, 0x02, 0x01])
        let firstAlias = ScreenTimeApplicationUsageAliasStore.appUsageRef(
            for: firstToken,
            defaults: defaults
        )
        let repeatedAlias = ScreenTimeApplicationUsageAliasStore.appUsageRef(
            for: firstToken,
            defaults: defaults
        )
        let secondAlias = ScreenTimeApplicationUsageAliasStore.appUsageRef(
            for: secondToken,
            defaults: defaults
        )

        let unwrappedFirstAlias = try XCTUnwrap(firstAlias)
        let unwrappedRepeatedAlias = try XCTUnwrap(repeatedAlias)
        let unwrappedSecondAlias = try XCTUnwrap(secondAlias)

        XCTAssertEqual(unwrappedFirstAlias, unwrappedRepeatedAlias)
        XCTAssertNotEqual(unwrappedFirstAlias, unwrappedSecondAlias)
        XCTAssertNotNil(unwrappedFirstAlias.range(of: #"^app:[a-f0-9]{32}$"#, options: .regularExpression))
        XCTAssertNotNil(unwrappedSecondAlias.range(of: #"^app:[a-f0-9]{32}$"#, options: .regularExpression))
        XCTAssertFalse(unwrappedFirstAlias.contains(firstToken.base64EncodedString()))
    }

    @MainActor
    func testRemoteNotificationCoordinatorQueuesRequestsUntilRootViewCanDrainThem() {
        let coordinator = FamilyRemoteNotificationCoordinator()
        let first = FamilyScreenTimeRemoteSyncRequest { _ in }
        let second = FamilyScreenTimeRemoteSyncRequest { _ in }

        coordinator.enqueue(first)
        coordinator.enqueue(second)

        let pending = coordinator.takePendingScreenTimeRequests()
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending[0] === first)
        XCTAssertTrue(pending[1] === second)
        XCTAssertTrue(coordinator.takePendingScreenTimeRequests().isEmpty)
    }

    @MainActor
    func testRemoteNotificationCoordinatorClaimsEachRequestOnlyOnce() {
        let coordinator = FamilyRemoteNotificationCoordinator()
        let request = FamilyScreenTimeRemoteSyncRequest { _ in }

        coordinator.enqueue(request)

        XCTAssertTrue(coordinator.claim(request))
        XCTAssertFalse(coordinator.claim(request))
        XCTAssertTrue(coordinator.takePendingScreenTimeRequests().isEmpty)
    }

    @MainActor
    func testRemoteNotificationCoordinatorFallsBackWhenNoRootViewClaimsRequest() async {
        let completed = expectation(description: "background Screen Time sync completed")
        var completionResult: UIBackgroundFetchResult?
        let coordinator = FamilyRemoteNotificationCoordinator(
            fallbackDelay: .zero,
            backgroundSync: { .newData }
        )
        let request = FamilyScreenTimeRemoteSyncRequest { result in
            completionResult = result
            completed.fulfill()
        }

        coordinator.enqueue(request)

        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(completionResult, .newData)
        XCTAssertTrue(coordinator.takePendingScreenTimeRequests().isEmpty)
    }
}

private final class MemoryWebsiteSafetyPersistence: WebsiteSafetyPersisting {
    var snapshot: WebsiteSafetySnapshot?

    func load() -> WebsiteSafetySnapshot? { snapshot }
    func save(_ snapshot: WebsiteSafetySnapshot) throws { self.snapshot = snapshot }
}
