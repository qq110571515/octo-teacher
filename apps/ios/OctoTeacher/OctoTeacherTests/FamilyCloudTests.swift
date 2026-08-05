import XCTest
import Security
@testable import OctoTeacher

final class FamilyCloudTests: XCTestCase {
    func testChildDeviceSessionRemainsReadableForBackgroundPushAfterFirstUnlock() {
        XCTAssertEqual(
            KeychainFamilyCloudSecretStore.accessibility(
                for: "child_device_session"
            ) as String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertEqual(
            KeychainFamilyCloudSecretStore.accessibility(
                for: "guardian_session"
            ) as String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
    }

    func testFamilyRequestsAdvertiseCurrentChildDeviceProtocol() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            (200, Self.childProfileJSON)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }

        let client = FamilyCloudClient(
            baseURL: URL(string: "https://example.test/api/v1/")!,
            session: session
        )
        _ = try await client.loadChildProfile(token: "child-session")

        XCTAssertEqual(FamilyCloudURLProtocolStub.requests.count, 1)
        XCTAssertEqual(
            FamilyCloudURLProtocolStub.requests.first?.value(
                forHTTPHeaderField: "X-Octo-Child-Protocol"
            ),
            "2"
        )
    }

    @MainActor
    func testBootstrapPersistsRebindModeWhenChildBindingProtocolIsStale() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("stale-child-session", account: "child_device_session"))
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { _ in
            (409, #"{"error":"child_device_rebind_required"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }

        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(
                baseURL: URL(string: "https://example.test/api/v1/")!,
                session: session
            ),
            secrets: secrets,
            syncStateStore: InMemoryFamilyCloudSyncStateStore()
        )
        await store.bootstrap()

        XCTAssertNil(store.childDeviceToken)
        XCTAssertTrue(store.childDeviceRebindRequired)
        XCTAssertTrue(store.isChildDevice)
        XCTAssertNotNil(store.lastSyncError)

        let restartedStore = FamilyCloudSessionStore(
            client: FamilyCloudClient(
                baseURL: URL(string: "https://example.test/api/v1/")!,
                session: session
            ),
            secrets: secrets,
            syncStateStore: InMemoryFamilyCloudSyncStateStore()
        )
        XCTAssertNil(restartedStore.childDeviceToken)
        XCTAssertTrue(restartedStore.childDeviceRebindRequired)
        XCTAssertTrue(restartedStore.isChildDevice)
    }

    func testGuardianActivitySummaryDecodesScreenTimeAndCreation() throws {
        let json = """
        {
          "windowDays": 90,
          "summary": [
            {"childProfileId":"child","kind":"screen_time","eventCount":2,"durationSeconds":2700},
            {"childProfileId":"child","kind":"creation","eventCount":1,"durationSeconds":600,"maxProgressPercent":100}
          ],
          "recent": [
            {"eventId":"event-1","kind":"screen_time","occurredAt":"2026-07-21T18:00:00Z","durationSeconds":1800,"displayName":"App Authorized Time","resourceRef":"authority:growth_points"}
          ]
        }
        """

        let summary = try JSONDecoder().decode(FamilyCloudActivitySummary.self, from: Data(json.utf8))

        XCTAssertEqual(summary.windowDays, 90)
        XCTAssertEqual(summary.screenTimeAuthorizedSeconds, 2700)
        XCTAssertEqual(summary.screenTimeAuthorizationCount, 2)
        XCTAssertEqual(summary.summary.last?.kind, .creation)
        XCTAssertEqual(summary.recent.first?.kind, .screenTime)
        XCTAssertTrue(summary.screenTimeDaily.isEmpty)
        XCTAssertTrue(summary.screenTimeAppDaily.isEmpty)
    }

    func testGuardianActivitySummaryDecodesDailyAndAnonymousAppRows() throws {
        let json = """
        {
          "windowDays": 30,
          "summary": [],
          "recent": [],
          "screenTimeDaily": [
            {"date":"2026-07-25","durationSeconds":3600,"eventCount":2}
          ],
          "screenTimeAppDaily": [
            {
              "date":"2026-07-25",
              "appRef":"app:0123456789abcdef0123456789abcdef",
              "authority":"growth_points",
              "durationSeconds":2700,
              "eventCount":2
            }
          ]
        }
        """

        let summary = try JSONDecoder().decode(
            FamilyCloudActivitySummary.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(summary.screenTimeDaily.first?.durationSeconds, 3600)
        XCTAssertEqual(
            summary.screenTimeAppDaily.first?.appRef,
            "app:0123456789abcdef0123456789abcdef"
        )
    }

    func testTaskSyncPageDecodesCursorAndPagination() throws {
        let json = """
        {"tasks":[],"cursor":42,"hasMore":true}
        """
        let page = try JSONDecoder().decode(FamilyCloudTaskPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.cursor, 42)
        XCTAssertTrue(page.hasMore)
    }

    func testCloudTaskDateCodecRoundTripsWithoutLocalTimezoneDrift() throws {
        let date = try XCTUnwrap(FamilyCloudTaskDateCodec.decode("2026-07-12"))

        XCTAssertEqual(FamilyCloudTaskDateCodec.encode(date), "2026-07-12")
        XCTAssertEqual(date.timeIntervalSince1970, 1_783_814_400)
    }

    func testPendingChildSubmissionStatePersistsForRetry() {
        let persistence = InMemoryFamilyCloudSyncStateStore()
        let pending = PendingFamilyCloudSubmission(
            mutationRef: "child:mutation-123",
            localAssignmentId: UUID(),
            cloudTaskId: "cloud-task",
            expectedVersion: 3,
            evidenceSummary: "完成了本章阅读",
            queuedAt: Date(timeIntervalSince1970: 100)
        )
        persistence.save(FamilyCloudSyncState(childCursor: 19, pendingChildSubmissions: [pending]))

        XCTAssertEqual(persistence.load().childCursor, 19)
        XCTAssertEqual(persistence.load().pendingChildSubmissions, [pending])
    }

    func testPendingChildWithdrawalStatePersistsForRetry() {
        let persistence = InMemoryFamilyCloudSyncStateStore()
        let pending = PendingFamilyCloudWithdrawal(
            mutationRef: "child-withdraw:mutation-123",
            localAssignmentId: UUID(),
            cloudTaskId: "cloud-task",
            expectedVersion: 4,
            queuedAt: Date(timeIntervalSince1970: 100)
        )
        persistence.save(FamilyCloudSyncState(pendingChildWithdrawals: [pending]))

        XCTAssertEqual(persistence.load().pendingChildWithdrawals, [pending])
    }

    @MainActor
    func testGuardianTaskOutboxAndFamilySnapshotPersistAcrossRestart() throws {
        let assignmentID = UUID()
        let upload = FamilyCloudTaskUpload(
            childClientRef: UUID().uuidString.lowercased(),
            clientRef: assignmentID.uuidString.lowercased(),
            title: "整理书包",
            titleEnglish: "Pack my school bag",
            status: "assigned",
            growthPoints: 12,
            requiresEvidence: true,
            plannedFor: "2026-07-17",
            version: 1,
            baseVersion: nil,
            taskPayload: nil
        )
        let queued = PendingFamilyCloudGuardianTaskUpsert(
            mutationRef: "guardian:stable-mutation",
            upload: upload,
            queuedAt: Date(timeIntervalSince1970: 100)
        )
        let family = FamilyCloudSnapshot(
            family: .init(
                id: "family",
                publicRef: "family-public",
                displayName: "Octo Home",
                isCreator: true
            ),
            guardians: [],
            children: [],
            devices: []
        )
        let persistence = InMemoryFamilyCloudSyncStateStore()
        XCTAssertTrue(persistence.save(FamilyCloudSyncState(
            pendingGuardianTaskUpserts: [queued],
            guardianTaskBaselineEstablished: true,
            cachedFamily: family,
            familySnapshotGeneration: 7
        )))

        let restored = FamilyCloudSessionStore(
            secrets: InMemoryFamilyCloudSecretStore(),
            syncStateStore: persistence
        )

        XCTAssertEqual(restored.pendingGuardianTaskUpsertCount, 1)
        XCTAssertEqual(restored.family, family)
        XCTAssertEqual(persistence.load().familySnapshotGeneration, 7)
    }

    @MainActor
    func testOfflineChildWithdrawalIsQueuedForReconnect() async {
        let assignmentID = UUID()
        let persistence = InMemoryFamilyCloudSyncStateStore()
        let store = FamilyCloudSessionStore(
            secrets: InMemoryFamilyCloudSecretStore(),
            syncStateStore: persistence
        )

        await store.withdrawChildTask(localAssignmentId: assignmentID)

        let queued = persistence.load().pendingChildWithdrawals
        XCTAssertEqual(queued?.count, 1)
        XCTAssertEqual(queued?.first?.localAssignmentId, assignmentID)
        XCTAssertNil(queued?.first?.cloudTaskId)
        XCTAssertEqual(store.message, "撤回已保存在本机，连接家庭后会自动同步。")
    }

    func testPointMutationFailuresSeparateRecoveryFromDeadLetter() {
        XCTAssertEqual(
            familyCloudPointMutationFailureDisposition(serverCode: "insufficient_growth_points"),
            .refreshAndRetry
        )
        XCTAssertEqual(
            familyCloudPointMutationFailureDisposition(serverCode: "points_refund_invalid"),
            .refreshAndRetry
        )
        XCTAssertEqual(
            familyCloudPointMutationFailureDisposition(serverCode: "points_source_ref_conflict"),
            .deadLetter
        )
        XCTAssertEqual(
            familyCloudPointMutationFailureDisposition(serverCode: "invalid_points_delta"),
            .deadLetter
        )
        XCTAssertEqual(
            familyCloudPointMutationFailureDisposition(serverCode: "family_api_unavailable"),
            .retryLater
        )
    }

    @MainActor
    func testGuardianDecisionPersistsVersionObservedAtDecisionTime() {
        let assignmentID = UUID()
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("guardian-session", account: "guardian_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        persistence.save(FamilyCloudSyncState(cachedTasks: [Self.cloudTask(
            assignmentID: assignmentID,
            status: "submitted",
            version: 4
        )]))
        let store = FamilyCloudSessionStore(secrets: secrets, syncStateStore: persistence)

        XCTAssertTrue(store.queueGuardianTaskDecision(assignmentId: assignmentID, status: .approved))

        XCTAssertEqual(persistence.load().pendingGuardianDecisions?.first?.expectedVersion, 4)
        XCTAssertEqual(persistence.load().pendingGuardianDecisions?.first?.status, "approved")
    }

    @MainActor
    func testGuardianDecisionReportsFailureInsteadOfSilentlyDroppingQueueEntry() {
        let assignmentID = UUID()
        let persistence = InMemoryFamilyCloudSyncStateStore()
        let store = FamilyCloudSessionStore(
            secrets: InMemoryFamilyCloudSecretStore(),
            syncStateStore: persistence
        )

        XCTAssertFalse(store.queueGuardianTaskDecision(assignmentId: assignmentID, status: .approved))
        XCTAssertEqual(store.lastSyncError, "guardian_decision_session_unavailable")
        XCTAssertTrue(persistence.load().pendingGuardianDecisions?.isEmpty ?? true)
    }

    @MainActor
    func testGuardianDecisionDoesNotPromiseSuccessWhenDiskSaveFails() {
        let assignmentID = UUID()
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("guardian-session", account: "guardian_session"))
        let initialState = FamilyCloudSyncState(cachedTasks: [Self.cloudTask(
            assignmentID: assignmentID,
            status: "submitted",
            version: 4
        )])
        let persistence = FailingDiskFamilyCloudSyncStateStore(initialState: initialState)
        let store = FamilyCloudSessionStore(secrets: secrets, syncStateStore: persistence)

        XCTAssertFalse(store.queueGuardianTaskDecision(assignmentId: assignmentID, status: .approved))

        XCTAssertEqual(store.lastSyncError, "family_cloud_local_persistence_failed")
        XCTAssertEqual(store.pendingGuardianDecisionCount, 0)
        XCTAssertNil(persistence.load().pendingGuardianDecisions)
        XCTAssertEqual(persistence.saveAttempts, 1)
    }

    @MainActor
    func testChildWithdrawalDoesNotReportQueuedWhenDiskSaveFails() async {
        let assignmentID = UUID()
        let task = Self.cloudTask(assignmentID: assignmentID, status: "submitted", version: 4)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = FailingDiskFamilyCloudSyncStateStore(
            initialState: FamilyCloudSyncState(cachedTasks: [task])
        )
        let store = FamilyCloudSessionStore(secrets: secrets, syncStateStore: persistence)

        let queued = await store.withdrawChildTask(localAssignmentId: assignmentID)

        XCTAssertFalse(queued)
        XCTAssertEqual(store.pendingChildWithdrawalCount, 0)
        XCTAssertNil(persistence.load().pendingChildWithdrawals)
        XCTAssertEqual(
            store.localizedMessage(for: .english),
            "The withdrawal could not be saved. Free storage space and try again."
        )
    }

    @MainActor
    func testPointMutationDoesNotEnterLedgerWhenDiskSaveFails() {
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = FailingDiskFamilyCloudSyncStateStore()
        let store = FamilyCloudSessionStore(secrets: secrets, syncStateStore: persistence)

        let queued = store.queuePointMutation(
            mutationRef: "points:disk-failure",
            kind: .screenTimeSpend,
            delta: -15,
            sourceRef: "unlock:disk-failure",
            local: LocalFamilyStore()
        )

        XCTAssertFalse(queued)
        XCTAssertEqual(store.pendingPointMutationCount, 0)
        XCTAssertEqual(store.pendingActivityEventCount, 0)
        XCTAssertNil(persistence.load().pendingPointMutations)
        XCTAssertNil(persistence.load().pendingActivityEvents)
        XCTAssertEqual(store.lastSyncError, "family_cloud_local_persistence_failed")
    }

    @MainActor
    func testPointMutationAndCompletedSessionUploadIndependently() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        let uploadsFinished = expectation(description: "point and activity uploads finish")
        uploadsFinished.expectedFulfillmentCount = 2
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/device/points/mutations") {
                uploadsFinished.fulfill()
                return (200, #"{"balance":85,"applied":true}"#)
            }
            if path.hasSuffix("/device/activity/events") {
                uploadsFinished.fulfill()
                return (
                    200,
                    #"{"acceptedCount":1,"duplicateCount":0,"events":[{"clientRef":"screen-time-complete:11111111-1111-1111-1111-111111111111","status":"accepted","eventId":"event-1"}]}"#
                )
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )

        XCTAssertTrue(store.queuePointMutation(
            mutationRef: "points:screen-time:1",
            kind: .screenTimeSpend,
            delta: -15,
            sourceRef: "unlock:screen-time:1",
            local: LocalFamilyStore()
        ))
        XCTAssertTrue(store.queueScreenTimeAuthorizationReceipt(
            Self.completedScreenTimeReceipt(
                sessionID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                consumedMinutes: 17
            )
        ))
        await fulfillment(of: [uploadsFinished], timeout: 2)
        for _ in 0..<50 where
            store.pendingPointMutationCount != 0 || store.pendingActivityEventCount != 0
        {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(store.pendingPointMutationCount, 0)
        XCTAssertEqual(store.pendingActivityEventCount, 0)
        XCTAssertEqual(persistence.load().pendingPointMutations, [])
        XCTAssertEqual(persistence.load().pendingActivityEvents, [])
        XCTAssertTrue(FamilyCloudURLProtocolStub.requests.contains(where: {
            $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/device/points/mutations") == true
        }))
        XCTAssertTrue(FamilyCloudURLProtocolStub.requests.contains(where: {
            $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/device/activity/events") == true
        }))
    }

    @MainActor
    func testAcknowledgedPointMutationDoesNotUploadAgainAfterRestart() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        let uploadsFinished = expectation(description: "initial point and activity uploads finish")
        uploadsFinished.expectedFulfillmentCount = 2
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            if request.url?.path.hasSuffix("/device/points/mutations") == true {
                uploadsFinished.fulfill()
                return (200, #"{"balance":85,"applied":true}"#)
            }
            if request.url?.path.hasSuffix("/device/activity/events") == true {
                uploadsFinished.fulfill()
                return (
                    200,
                    #"{"acceptedCount":1,"duplicateCount":0,"events":[{"clientRef":"screen-time-complete:22222222-2222-2222-2222-222222222222","status":"accepted","eventId":"event-1"}]}"#
                )
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let client = FamilyCloudClient(
            baseURL: URL(string: "https://example.test/api/v1/")!,
            session: session
        )
        let firstStore = FamilyCloudSessionStore(
            client: client,
            secrets: secrets,
            syncStateStore: persistence
        )
        let local = LocalFamilyStore()

        XCTAssertTrue(firstStore.queuePointMutation(
            mutationRef: "points:restart-safe",
            kind: .screenTimeSpend,
            delta: -15,
            sourceRef: "unlock:restart-safe",
            local: local
        ))
        let completedReceipt = Self.completedScreenTimeReceipt(
            sessionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            consumedMinutes: 19
        )
        XCTAssertTrue(firstStore.queueScreenTimeAuthorizationReceipt(
            completedReceipt
        ))
        await fulfillment(of: [uploadsFinished], timeout: 2)
        for _ in 0..<50 where
            firstStore.pendingPointMutationCount != 0 || firstStore.pendingActivityEventCount != 0
        {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(persistence.load().acknowledgedPointMutationRefs, ["points:restart-safe"])
        XCTAssertEqual(
            persistence.load().acknowledgedActivityEventRefs,
            ["screen-time-complete:22222222-2222-2222-2222-222222222222"]
        )
        let requestCountAfterFirstUpload = FamilyCloudURLProtocolStub.requests.count
        let restartedStore = FamilyCloudSessionStore(
            client: client,
            secrets: secrets,
            syncStateStore: persistence
        )

        XCTAssertTrue(restartedStore.queuePointMutation(
            mutationRef: "points:restart-safe",
            kind: .screenTimeSpend,
            delta: -15,
            sourceRef: "unlock:restart-safe",
            local: local
        ))
        XCTAssertTrue(restartedStore.queueScreenTimeAuthorizationReceipt(
            completedReceipt
        ))
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(FamilyCloudURLProtocolStub.requests.count, requestCountAfterFirstUpload)
        XCTAssertEqual(restartedStore.pendingPointMutationCount, 0)
        XCTAssertEqual(restartedStore.pendingActivityEventCount, 0)
    }

    @MainActor
    func testRestartRetriesOriginalActivityWithoutReapplyingAcknowledgedPointMutation() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        let initialRequestsFinished = expectation(description: "initial point succeeds and activity fails")
        initialRequestsFinished.expectedFulfillmentCount = 2
        var activityBodies: [String] = []
        var pointRequestCount = 0
        var activityRequestCount = 0
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            if request.url?.path.hasSuffix("/device/points/mutations") == true {
                pointRequestCount += 1
                initialRequestsFinished.fulfill()
                return (200, #"{"balance":85,"applied":true}"#)
            }
            if request.url?.path.hasSuffix("/device/activity/events") == true {
                activityRequestCount += 1
                activityBodies.append(Self.requestBodyString(request) ?? "")
                initialRequestsFinished.fulfill()
                return (500, #"{"error":"temporary_activity_failure"}"#)
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let client = FamilyCloudClient(
            baseURL: URL(string: "https://example.test/api/v1/")!,
            session: session
        )
        let firstStore = FamilyCloudSessionStore(
            client: client,
            secrets: secrets,
            syncStateStore: persistence
        )
        let local = LocalFamilyStore()

        XCTAssertTrue(firstStore.queuePointMutation(
            mutationRef: "points:partial-recovery",
            kind: .screenTimeSpend,
            delta: -15,
            sourceRef: "unlock:partial-recovery",
            local: local
        ))
        let partialReceipt = Self.completedScreenTimeReceipt(
            sessionID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            consumedMinutes: 23
        )
        XCTAssertTrue(firstStore.queueScreenTimeAuthorizationReceipt(
            partialReceipt
        ))
        await fulfillment(of: [initialRequestsFinished], timeout: 2)
        for _ in 0..<50 where firstStore.pendingPointMutationCount != 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(firstStore.pendingPointMutationCount, 0)
        XCTAssertEqual(firstStore.pendingActivityEventCount, 1)
        XCTAssertEqual(pointRequestCount, 1)
        XCTAssertEqual(activityRequestCount, 1)
        XCTAssertEqual(
            persistence.load().acknowledgedPointMutationRefs,
            ["points:partial-recovery"]
        )
        XCTAssertEqual(
            persistence.load().pendingActivityEvents?.first?.clientRef,
            "screen-time-complete:33333333-3333-3333-3333-333333333333"
        )

        let activityRetryFinished = expectation(description: "persisted activity retry succeeds")
        FamilyCloudURLProtocolStub.handler = { request in
            if request.url?.path.hasSuffix("/device/points/mutations") == true {
                pointRequestCount += 1
                return (500, #"{"error":"point_must_not_repeat"}"#)
            }
            if request.url?.path.hasSuffix("/device/activity/events") == true {
                activityRequestCount += 1
                activityBodies.append(Self.requestBodyString(request) ?? "")
                activityRetryFinished.fulfill()
                return (
                    200,
                    #"{"acceptedCount":1,"duplicateCount":0,"events":[{"clientRef":"screen-time-complete:33333333-3333-3333-3333-333333333333","status":"accepted","eventId":"event-1"}]}"#
                )
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        let restartedStore = FamilyCloudSessionStore(
            client: client,
            secrets: secrets,
            syncStateStore: persistence
        )

        XCTAssertTrue(restartedStore.queuePointMutation(
            mutationRef: "points:partial-recovery",
            kind: .screenTimeSpend,
            delta: -15,
            sourceRef: "unlock:partial-recovery",
            local: local
        ))
        XCTAssertTrue(restartedStore.queueScreenTimeAuthorizationReceipt(
            partialReceipt
        ))
        await fulfillment(of: [activityRetryFinished], timeout: 2)
        for _ in 0..<50 where restartedStore.pendingActivityEventCount != 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(pointRequestCount, 1)
        XCTAssertEqual(activityRequestCount, 2)
        XCTAssertEqual(activityBodies.count, 2)
        let canonicalActivityBodies = activityBodies.compactMap { body -> Data? in
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)),
                JSONSerialization.isValidJSONObject(object)
            else {
                return nil
            }
            return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        XCTAssertEqual(canonicalActivityBodies.count, 2)
        XCTAssertEqual(canonicalActivityBodies.first, canonicalActivityBodies.last)
        XCTAssertEqual(restartedStore.pendingPointMutationCount, 0)
        XCTAssertEqual(restartedStore.pendingActivityEventCount, 0)
        XCTAssertEqual(
            persistence.load().acknowledgedActivityEventRefs,
            ["screen-time-complete:33333333-3333-3333-3333-333333333333"]
        )
    }

    @MainActor
    func testParentPINAuthorizationImmediatelyUploadsAnonymousAppUsage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        let uploadFinished = expectation(description: "parent PIN activity upload finishes")
        var uploadedBody = ""
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            guard request.url?.path.hasSuffix("/device/activity/events") == true else {
                return (404, #"{"error":"unexpected_test_request"}"#)
            }
            uploadedBody = Self.requestBodyString(request) ?? ""
            uploadFinished.fulfill()
            return (
                200,
                #"{"acceptedCount":1,"duplicateCount":0,"events":[{"clientRef":"screen-time-complete:44444444-4444-4444-4444-444444444444","status":"accepted","eventId":"event-1"}]}"#
            )
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )

        XCTAssertTrue(store.queueScreenTimeAuthorizationReceipt(
            Self.completedScreenTimeReceipt(
                sessionID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                authority: .parentPIN,
                grantedMinutes: 120,
                consumedMinutes: 37,
                appUsageRef: "app:0123456789abcdef0123456789abcdef"
            )
        ))
        await fulfillment(of: [uploadFinished], timeout: 2)
        for _ in 0..<50 where store.pendingActivityEventCount != 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(store.pendingActivityEventCount, 0)
        XCTAssertEqual(persistence.load().pendingActivityEvents, [])
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(uploadedBody.utf8)) as? [String: Any]
        )
        let events = try XCTUnwrap(payload["events"] as? [[String: Any]])
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(
            event["clientRef"] as? String,
            "screen-time-complete:44444444-4444-4444-4444-444444444444"
        )
        XCTAssertEqual(event["kind"] as? String, "screen_time")
        XCTAssertEqual(event["durationSeconds"] as? Int, 2_220)
        XCTAssertEqual(
            event["resourceRef"] as? String,
            "authority:parent_pin:app:0123456789abcdef0123456789abcdef"
        )
    }

    @MainActor
    func testAcknowledgedParentPINAuthorizationDoesNotUploadAgainAfterRestart() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        let uploadFinished = expectation(description: "initial parent PIN activity upload finishes")
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            guard request.url?.path.hasSuffix("/device/activity/events") == true else {
                return (404, #"{"error":"unexpected_test_request"}"#)
            }
            uploadFinished.fulfill()
            return (
                200,
                #"{"acceptedCount":1,"duplicateCount":0,"events":[{"clientRef":"screen-time-complete:55555555-5555-5555-5555-555555555555","status":"accepted","eventId":"event-1"}]}"#
            )
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let client = FamilyCloudClient(
            baseURL: URL(string: "https://example.test/api/v1/")!,
            session: session
        )
        let firstStore = FamilyCloudSessionStore(
            client: client,
            secrets: secrets,
            syncStateStore: persistence
        )

        let parentPINReceipt = Self.completedScreenTimeReceipt(
            sessionID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            authority: .parentPIN,
            grantedMinutes: 120,
            consumedMinutes: 41,
            appUsageRef: "app:0123456789abcdef0123456789abcdef"
        )
        XCTAssertTrue(firstStore.queueScreenTimeAuthorizationReceipt(
            parentPINReceipt
        ))
        await fulfillment(of: [uploadFinished], timeout: 2)
        for _ in 0..<50 where firstStore.pendingActivityEventCount != 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(
            persistence.load().acknowledgedActivityEventRefs,
            ["screen-time-complete:55555555-5555-5555-5555-555555555555"]
        )
        let requestCountAfterFirstUpload = FamilyCloudURLProtocolStub.requests.count
        let restartedStore = FamilyCloudSessionStore(
            client: client,
            secrets: secrets,
            syncStateStore: persistence
        )

        XCTAssertTrue(restartedStore.queueScreenTimeAuthorizationReceipt(
            parentPINReceipt
        ))
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(FamilyCloudURLProtocolStub.requests.count, requestCountAfterFirstUpload)
        XCTAssertEqual(restartedStore.pendingActivityEventCount, 0)
    }

    @MainActor
    func testScreenTimeResourceRefOnlyAcceptsValidatedAnonymousAppAlias() {
        let validAlias = "app:0123456789abcdef0123456789abcdef"

        XCTAssertEqual(
            FamilyCloudSessionStore.screenTimeResourceRef(
                authority: .growthPoints,
                appUsageRef: validAlias
            ),
            "authority:growth_points:\(validAlias)"
        )
        XCTAssertEqual(
            FamilyCloudSessionStore.screenTimeResourceRef(
                authority: .parentPIN,
                appUsageRef: "app:not-a-valid-alias"
            ),
            "authority:parent_pin"
        )
        XCTAssertEqual(
            FamilyCloudSessionStore.screenTimeResourceRef(
                authority: .schoolEmergency,
                appUsageRef: nil
            ),
            "authority:school_emergency"
        )
    }

    func testLegacySyncStateDecodesWithoutSnapshotCache() throws {
        let assignmentID = UUID()
        let json = """
        {
          "guardianCursors":{"family":19},
          "childCursor":42,
          "pendingChildSubmissions":[{
            "mutationRef":"child:legacy",
            "localAssignmentId":"\(assignmentID.uuidString)",
            "cloudTaskId":"cloud-task",
            "expectedVersion":3,
            "evidenceSummary":"done",
            "queuedAt":100
          }]
        }
        """

        let state = try JSONDecoder().decode(FamilyCloudSyncState.self, from: Data(json.utf8))

        XCTAssertEqual(state.childCursor, 42)
        XCTAssertEqual(state.pendingChildSubmissions.first?.localAssignmentId, assignmentID)
        XCTAssertNil(state.cachedTasks)
        XCTAssertNil(state.guardianSnapshotDates)
        XCTAssertNil(state.childSnapshotDate)
        XCTAssertNil(state.pendingGuardianProfileClientRefs)
        XCTAssertNil(state.pendingChildWithdrawals)
    }

    func testLegacyUnversionedGuardianDecisionDecodesFailClosed() throws {
        let assignmentID = UUID()
        let json = """
        {
          "guardianCursors":{},
          "childCursor":0,
          "pendingChildSubmissions":[],
          "pendingGuardianDecisions":[{
            "assignmentId":"\(assignmentID.uuidString)",
            "status":"approved",
            "queuedAt":100
          }]
        }
        """

        let state = try JSONDecoder().decode(FamilyCloudSyncState.self, from: Data(json.utf8))

        XCTAssertEqual(state.pendingGuardianDecisions?.first?.expectedVersion, 0)
    }

    @MainActor
    func testGuardianProfileSyncIntentPersistsAcrossRestart() {
        let persistence = InMemoryFamilyCloudSyncStateStore()
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("guardian-session", account: "guardian_session"))
        let childID = UUID()
        let store = FamilyCloudSessionStore(secrets: secrets, syncStateStore: persistence)

        store.queueGuardianProfileSync(for: childID, fields: [.contentLanguage])

        XCTAssertEqual(store.pendingGuardianProfileCount, 1)
        XCTAssertEqual(
            persistence.load().pendingGuardianProfileClientRefs,
            [childID.uuidString.lowercased()]
        )
        XCTAssertEqual(
            persistence.load().pendingGuardianProfileFields?[childID.uuidString.lowercased()],
            [.contentLanguage]
        )
        XCTAssertEqual(
            persistence.load().pendingGuardianProfileGenerations?[childID.uuidString.lowercased()],
            1
        )
        store.queueGuardianProfileSync(for: childID, fields: [.contentLanguage])
        XCTAssertEqual(
            persistence.load().pendingGuardianProfileGenerations?[childID.uuidString.lowercased()],
            2,
            "A repeated edit of the same field must remain distinguishable from an in-flight request"
        )
        let restored = FamilyCloudSessionStore(secrets: secrets, syncStateStore: persistence)
        XCTAssertEqual(restored.pendingGuardianProfileCount, 1)
    }

    @MainActor
    func testGuardianContentEditRebasesOnChildDeviceLanguage() {
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("guardian-session", account: "guardian_session"))
        let sessionStore = FamilyCloudSessionStore(
            secrets: secrets,
            syncStateStore: InMemoryFamilyCloudSyncStateStore()
        )
        let local = LocalFamilyStore()
        let childID = local.activeChildId
        local.setChildInterfaceLanguage(.chinese, for: childID)
        local.setContentLanguage(.bilingual, for: childID)
        let child = local.child
        let cloudChild = FamilyCloudSnapshot.Child(
            id: "cloud-child",
            publicRef: "child-public",
            clientRef: childID.uuidString.lowercased(),
            displayName: child.name,
            birthYear: Calendar.current.component(.year, from: Date()) - child.age,
            preReaderMode: child.isPreReader,
            interfaceLanguage: .english,
            contentLanguage: .english,
            dailyLimitMinutes: child.dailyLimitMinutes,
            exchangePolicy: local.policy(for: childID),
            profileVersion: 9
        )

        let request = sessionStore.makeGuardianProfileRequest(
            localChild: child,
            local: local,
            cloudChild: cloudChild,
            changedFields: [.contentLanguage]
        )

        XCTAssertEqual(request.contentLanguage, .bilingual)
        XCTAssertEqual(
            request.interfaceLanguage,
            .english,
            "An unrelated guardian edit must preserve the newer language chosen on the child device"
        )
    }

    func testUnresolvedChildSubmissionPersistsUntilCloudTaskCanBeRecovered() {
        let persistence = InMemoryFamilyCloudSyncStateStore()
        let pending = PendingFamilyCloudSubmission(
            mutationRef: "child:unresolved",
            localAssignmentId: UUID(),
            cloudTaskId: nil,
            expectedVersion: 1,
            evidenceSummary: "按时睡觉",
            queuedAt: Date(timeIntervalSince1970: 100)
        )
        persistence.save(FamilyCloudSyncState(childCursor: 166, pendingChildSubmissions: [pending]))

        XCTAssertEqual(persistence.load().pendingChildSubmissions, [pending])
        XCTAssertNil(persistence.load().pendingChildSubmissions.first?.cloudTaskId)
    }

    @MainActor
    func testRestartedChildDeviceRecoversOldTaskMappingBeforeSubmission() async throws {
        let assignmentID = UUID()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        persistence.save(FamilyCloudSyncState(childCursor: 166))
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.hasSuffix("/device/profile") {
                return (200, Self.childProfileJSON)
            }
            if path.hasSuffix("/device/ai/status") {
                return (200, #"{"ai":{"configured":false,"guidanceEnabled":false,"imageUploadEnabled":false,"voiceEnabled":false}}"#)
            }
            if path.hasSuffix("/device/tasks"), query.contains("snapshot=1") {
                return (200, Self.taskPageJSON(assignmentID: assignmentID, status: "assigned", version: 7))
            }
            if path.hasSuffix("/device/tasks"), query.contains("cursor=166") || query.contains("cursor=177") {
                return (200, #"{"tasks":[],"cursor":177,"hasMore":false}"#)
            }
            if path.hasSuffix("/device/tasks/cloud-alex-bedtime/submit") {
                return (200, Self.taskEnvelopeJSON(task: Self.cloudTask(
                    assignmentID: assignmentID,
                    status: "submitted",
                    version: 8
                )))
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )
        let local = LocalFamilyStore()
        let assigned = FamilyCloudTask(
            id: "cloud-alex-bedtime",
            childProfileId: "cloud-alex",
            clientRef: assignmentID.uuidString,
            title: "按时上床睡觉",
            titleEnglish: "Go to bed on time",
            status: "assigned",
            growthPoints: 20,
            requiresEvidence: false,
            plannedFor: "2026-07-13",
            evidenceSummary: nil,
            version: 7,
            updatedAt: "2026-07-13T16:00:00.000Z"
        )
        local.applyCloudFamilyTasks([assigned], childName: "Alex")
        let localAssignment = try XCTUnwrap(local.assignments.first(where: { $0.id == assignmentID }))
        XCTAssertTrue(local.submit(
            localAssignment,
            proof: ProofDraft(kind: .text, text: "完成", photoPlaceholderName: nil, status: .drafting)
        ))

        try await store.refreshChildTasks(into: local)

        XCTAssertEqual(store.cloudTasks.first?.status, "submitted")
        XCTAssertEqual(store.pendingChildSubmissionCount, 0)
        XCTAssertEqual(local.assignments.first(where: { $0.id == assignmentID })?.status, .submitted)
        XCTAssertTrue(FamilyCloudURLProtocolStub.requests.contains(where: {
            $0.httpMethod == "GET" && $0.url?.query?.contains("snapshot=1") == true
        }))
        let incrementalRequests = FamilyCloudURLProtocolStub.requests.filter {
            $0.httpMethod == "GET" && $0.url?.path.hasSuffix("/device/tasks") == true &&
                $0.url?.query?.contains("cursor=") == true
        }
        XCTAssertEqual(incrementalRequests.first?.url?.query, "cursor=166")
        XCTAssertTrue(FamilyCloudURLProtocolStub.requests.contains(where: {
            $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/device/tasks/cloud-alex-bedtime/submit") == true
        }))
        XCTAssertEqual(persistence.load().cachedTasks?.first?.status, "submitted")
    }

    @MainActor
    func testChildBootstrapPullsLegacyTombstoneBeforeSnapshotCursorAdvance() async {
        let assignmentID = UUID()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        persistence.save(FamilyCloudSyncState(
            childCursor: 41,
            cachedTasks: [Self.cloudTask(assignmentID: assignmentID, status: "assigned", version: 1)]
        ))
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.hasSuffix("/device/profile") { return (200, Self.childProfileJSON) }
            if path.hasSuffix("/device/ai/status") {
                return (200, #"{"ai":{"configured":false,"guidanceEnabled":false,"imageUploadEnabled":false,"voiceEnabled":false}}"#)
            }
            if path.hasSuffix("/device/tasks"), query.contains("snapshot=1") {
                return (200, #"{"tasks":[],"cursor":100,"hasMore":false}"#)
            }
            if path.hasSuffix("/device/tasks"), query.contains("cursor=41") {
                return (200, #"{"tasks":[],"removedClientRefs":["\#(assignmentID.uuidString)"],"cursor":75,"hasMore":false}"#)
            }
            if path.hasSuffix("/device/tasks"), query.contains("cursor=100") {
                return (200, #"{"tasks":[],"cursor":100,"hasMore":false}"#)
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )

        await store.bootstrap()

        let incremental = FamilyCloudURLProtocolStub.requests.filter {
            $0.url?.path.hasSuffix("/device/tasks") == true && $0.url?.query?.contains("cursor=") == true
        }
        XCTAssertEqual(incremental.first?.url?.query, "cursor=41")
        XCTAssertEqual(persistence.load().childCursor, 100)
        XCTAssertTrue(store.cloudTasks.isEmpty)
    }

    @MainActor
    func testChildLinkPullsChangesFromZeroBeforeAcceptingSnapshotCursor() async throws {
        let assignmentID = UUID()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        let persistence = InMemoryFamilyCloudSyncStateStore()
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.hasSuffix("/family-invites/claim") {
                return (200, #"{"kind":"child_device","deviceSessionToken":"linked-child-session","family":{"id":"family","publicRef":"family-public","displayName":"Home"},"child":{"id":"cloud-alex","publicRef":"child-public","clientRef":"\#(assignmentID.uuidString)","displayName":"Alex"}}"#)
            }
            if path.hasSuffix("/device/ai/status") {
                return (200, #"{"ai":{"configured":false,"guidanceEnabled":false,"imageUploadEnabled":false,"voiceEnabled":false}}"#)
            }
            if path.hasSuffix("/device/tasks"), query.contains("snapshot=1") {
                return (200, #"{"tasks":[],"cursor":100,"hasMore":false}"#)
            }
            if path.hasSuffix("/device/tasks"), query.contains("cursor=0") {
                return (200, #"{"tasks":[],"removedClientRefs":["\#(assignmentID.uuidString)"],"cursor":75,"hasMore":false}"#)
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )
        let invite = FamilyCloudJoinPayload(
            version: 2,
            publicRef: "invite_12345678",
            secret: "one-time-secret",
            kind: "child_device",
            expiresAt: "2026-07-17T00:00:00.000Z"
        )

        try await store.claim(invite)

        let incremental = FamilyCloudURLProtocolStub.requests.filter {
            $0.url?.path.hasSuffix("/device/tasks") == true && $0.url?.query?.contains("cursor=") == true
        }
        XCTAssertEqual(incremental.first?.url?.query, "cursor=0")
        XCTAssertEqual(persistence.load().childCursor, 100)
    }

    @MainActor
    func testChildRefreshAppliesLegacyTombstonePulledFromOldCursor() async throws {
        let assignmentID = UUID()
        let task = Self.cloudTask(assignmentID: assignmentID, status: "assigned", version: 1)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        persistence.save(FamilyCloudSyncState(childCursor: 41, cachedTasks: [task]))
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.hasSuffix("/device/profile") { return (200, Self.childProfileJSON) }
            if path.hasSuffix("/device/ai/status") {
                return (200, #"{"ai":{"configured":false,"guidanceEnabled":false,"imageUploadEnabled":false,"voiceEnabled":false}}"#)
            }
            if path.hasSuffix("/device/tasks"), query.contains("snapshot=1") {
                return (200, #"{"tasks":[],"cursor":100,"hasMore":false}"#)
            }
            if path.hasSuffix("/device/tasks"), query.contains("cursor=41") {
                return (200, #"{"tasks":[],"removedClientRefs":["\#(assignmentID.uuidString)"],"cursor":75,"hasMore":false}"#)
            }
            if path.hasSuffix("/device/tasks"), query.contains("cursor=100") {
                return (200, #"{"tasks":[],"cursor":100,"hasMore":false}"#)
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )
        let local = LocalFamilyStore()
        local.applyCloudFamilyTasks([task], childName: "Alex")
        XCTAssertTrue(local.assignments.contains(where: { $0.id == assignmentID }))

        try await store.refreshChildTasks(into: local)

        XCTAssertFalse(local.assignments.contains(where: { $0.id == assignmentID }))
        let incremental = FamilyCloudURLProtocolStub.requests.filter {
            $0.url?.path.hasSuffix("/device/tasks") == true && $0.url?.query?.contains("cursor=") == true
        }
        XCTAssertEqual(incremental.first?.url?.query, "cursor=41")
    }

    @MainActor
    func testManualChildRefreshUsesAuthoritativeSnapshotAndRemovesStaleTasks() async throws {
        let staleAssignmentID = UUID()
        let staleTask = Self.cloudTask(assignmentID: staleAssignmentID, status: "assigned", version: 1)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        XCTAssertTrue(persistence.save(FamilyCloudSyncState(childCursor: 41, cachedTasks: [staleTask])))
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/device/ai/status") {
                return (200, #"{"ai":{"configured":false,"guidanceEnabled":false,"imageUploadEnabled":false,"voiceEnabled":false}}"#)
            }
            if path.hasSuffix("/device/surface") {
                return (200, Self.childSurfaceJSON(taskCursor: 100))
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )
        let local = LocalFamilyStore()
        local.applyCloudFamilyTasks([staleTask], childName: "Alex")

        try await store.refreshChildSurface(into: local, forceFullSnapshot: true)

        XCTAssertFalse(local.assignments.contains(where: { $0.id == staleAssignmentID }))
        XCTAssertEqual(persistence.load().childCursor, 100)
        XCTAssertFalse(FamilyCloudURLProtocolStub.requests.contains(where: {
            $0.url?.path.hasSuffix("/device/tasks") == true
        }))
        XCTAssertTrue(FamilyCloudURLProtocolStub.requests.contains(where: {
            $0.url?.path.hasSuffix("/device/surface") == true
        }))
    }

    @MainActor
    func testPersistedChildTombstoneReplaysAfterCursorSaveAndStoreRecreation() async throws {
        let assignmentID = UUID()
        let task = Self.cloudTask(assignmentID: assignmentID, status: "assigned", version: 1)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let client = FamilyCloudClient(
            baseURL: URL(string: "https://example.test/api/v1/")!,
            session: session
        )
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        XCTAssertTrue(persistence.save(FamilyCloudSyncState(
            childCursor: 75,
            pendingRemovedTaskClientRefs: [assignmentID.uuidString.lowercased()],
            cachedTasks: []
        )))

        // Process one has already durably advanced the cursor and saved the tombstone.
        _ = FamilyCloudSessionStore(client: client, secrets: secrets, syncStateStore: persistence)
        // Simulate a crash before LocalFamilyStore received that tombstone.
        let restartedStore = FamilyCloudSessionStore(
            client: client,
            secrets: secrets,
            syncStateStore: persistence
        )
        let local = LocalFamilyStore()
        local.applyCloudFamilyTasks([task], childName: "Alex")
        XCTAssertTrue(local.assignments.contains(where: { $0.id == assignmentID }))

        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.hasSuffix("/device/profile") { return (200, Self.childProfileJSON) }
            if path.hasSuffix("/device/ai/status") {
                return (200, #"{"ai":{"configured":false,"guidanceEnabled":false,"imageUploadEnabled":false,"voiceEnabled":false}}"#)
            }
            if path.hasSuffix("/device/tasks"), query.contains("snapshot=1") {
                return (200, #"{"tasks":[],"cursor":75,"hasMore":false}"#)
            }
            if path.hasSuffix("/device/tasks"), query.contains("cursor=75") {
                return (200, #"{"tasks":[],"cursor":75,"hasMore":false}"#)
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }

        try await restartedStore.refreshChildTasks(into: local)

        XCTAssertFalse(local.assignments.contains(where: { $0.id == assignmentID }))
        XCTAssertEqual(persistence.load().childCursor, 75)
        XCTAssertTrue(persistence.load().pendingRemovedTaskClientRefs?.isEmpty ?? true)
        XCTAssertFalse(FamilyCloudURLProtocolStub.requests.contains(where: {
            $0.url?.query?.contains("cursor=0") == true
        }))
    }

    @MainActor
    func testChildWithdrawalReachesCloudAndClearsDurableOutbox() async throws {
        let assignmentID = UUID()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        persistence.save(FamilyCloudSyncState(
            childCursor: 177,
            cachedTasks: [FamilyCloudTask(
                id: "cloud-alex-bedtime",
                childProfileId: "cloud-alex",
                clientRef: assignmentID.uuidString,
                title: "按时上床睡觉",
                titleEnglish: "Go to bed on time",
                status: "submitted",
                growthPoints: 20,
                requiresEvidence: false,
                plannedFor: "2026-07-13",
                evidenceSummary: "完成",
                version: 8,
                updatedAt: "2026-07-13T17:00:00.000Z"
            )]
        ))
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            if request.url?.path.hasSuffix("/device/tasks/cloud-alex-bedtime/withdraw") == true {
                return (200, #"{"task":{"id":"cloud-alex-bedtime","childProfileId":"cloud-alex","clientRef":"\#(assignmentID.uuidString)","title":"按时上床睡觉","titleEnglish":"Go to bed on time","status":"assigned","growthPoints":20,"requiresEvidence":false,"plannedFor":"2026-07-13","version":9,"updatedAt":"2026-07-13T17:05:00.000Z"}}"#)
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )

        await store.withdrawChildTask(localAssignmentId: assignmentID)

        XCTAssertEqual(store.cloudTasks.first?.status, "assigned")
        XCTAssertEqual(store.pendingChildWithdrawalCount, 0)
        XCTAssertEqual(persistence.load().pendingChildWithdrawals, [])
        XCTAssertTrue(FamilyCloudURLProtocolStub.requests.contains(where: {
            $0.httpMethod == "POST" &&
                $0.url?.path.hasSuffix("/device/tasks/cloud-alex-bedtime/withdraw") == true
        }))
    }

    @MainActor
    func testRecoverablePointFailureRefreshesProfileBeforeReplayingOutboxEntry() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
        let mutation = PendingFamilyCloudPointMutation(
            mutationRef: "points:recoverable:1",
            kind: .screenTimeSpend,
            delta: -10,
            sourceRef: "unlock:recoverable:1",
            queuedAt: Date(timeIntervalSince1970: 100)
        )
        let persistence = InMemoryFamilyCloudSyncStateStore()
        persistence.save(FamilyCloudSyncState(pendingPointMutations: [mutation]))
        var pointAttempts = 0
        var events: [String] = []
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/device/profile") {
                events.append("profile")
                return (200, Self.childProfileJSON)
            }
            if path.hasSuffix("/device/ai/status") {
                return (200, #"{"ai":{"configured":false,"guidanceEnabled":false,"imageUploadEnabled":false,"voiceEnabled":false}}"#)
            }
            if path.hasSuffix("/device/tasks") {
                return (200, #"{"tasks":[],"cursor":0,"hasMore":false}"#)
            }
            if path.hasSuffix("/device/points/mutations") {
                pointAttempts += 1
                events.append("mutation")
                if pointAttempts == 1 {
                    return (409, #"{"error":"insufficient_growth_points"}"#)
                }
                return (200, #"{"balance":20,"applied":true}"#)
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )

        try await store.refreshChildTasks(into: LocalFamilyStore())

        XCTAssertEqual(events.suffix(3), ["mutation", "profile", "mutation"])
        XCTAssertEqual(pointAttempts, 2)
        XCTAssertEqual(persistence.load().pendingPointMutations, [])
        XCTAssertTrue(persistence.load().failedPointMutations?.isEmpty ?? true)
    }

    @MainActor
    func testRecoverablePointFailureRemainsQueuedWhenReplayStillNeedsLedger() async throws {
        for serverCode in ["insufficient_growth_points", "points_refund_invalid"] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
            let session = URLSession(configuration: configuration)
            let secrets = InMemoryFamilyCloudSecretStore()
            XCTAssertTrue(secrets.save("child-session", account: "child_device_session"))
            let mutation = PendingFamilyCloudPointMutation(
                mutationRef: "points:recoverable:\(serverCode)",
                kind: serverCode == "points_refund_invalid" ? .screenTimeRefund : .screenTimeSpend,
                delta: serverCode == "points_refund_invalid" ? 10 : -10,
                sourceRef: "unlock:recoverable:\(serverCode)",
                queuedAt: Date(timeIntervalSince1970: 100)
            )
            let persistence = InMemoryFamilyCloudSyncStateStore()
            persistence.save(FamilyCloudSyncState(pendingPointMutations: [mutation]))
            var pointAttempts = 0
            var profileLoads = 0
            FamilyCloudURLProtocolStub.requests = []
            FamilyCloudURLProtocolStub.handler = { request in
                let path = request.url?.path ?? ""
                if path.hasSuffix("/device/profile") {
                    profileLoads += 1
                    return (200, Self.childProfileJSON)
                }
                if path.hasSuffix("/device/ai/status") {
                    return (200, #"{"ai":{"configured":false,"guidanceEnabled":false,"imageUploadEnabled":false,"voiceEnabled":false}}"#)
                }
                if path.hasSuffix("/device/tasks") {
                    return (200, #"{"tasks":[],"cursor":0,"hasMore":false}"#)
                }
                if path.hasSuffix("/device/points/mutations") {
                    pointAttempts += 1
                    return (409, "{\"error\":\"\(serverCode)\"}")
                }
                return (404, #"{"error":"unexpected_test_request"}"#)
            }
            let store = FamilyCloudSessionStore(
                client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
                secrets: secrets,
                syncStateStore: persistence
            )

            try await store.refreshChildTasks(into: LocalFamilyStore())

            XCTAssertEqual(pointAttempts, 2, serverCode)
            XCTAssertEqual(profileLoads, 2, serverCode)
            XCTAssertEqual(persistence.load().pendingPointMutations, [mutation], serverCode)
            XCTAssertTrue(persistence.load().failedPointMutations?.isEmpty ?? true, serverCode)
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
    }

    @MainActor
    func testGuardianFirstBaselineDropsLegacyLocalTasksAndUsesCloudFamilyIdentity() async throws {
        let local = LocalFamilyStore()
        local.applyFamilySetup(childName: "Alex", dailyLimitMinutes: 120, keepStarterTasks: false)
        let legacy = try XCTUnwrap(local.assignNewTask(
            title: "旧手机遗留任务",
            instructions: "",
            category: .family,
            rewardMinutes: 99,
            requiredProof: .text
        ))
        let family = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family-public", displayName: "Cloud Home", isCreator: true),
            guardians: [],
            children: [],
            devices: []
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("guardian-session", account: "guardian_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        XCTAssertTrue(persistence.save(FamilyCloudSyncState(cachedFamily: family)))
        var postCount = 0
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            if path.hasSuffix("/auth/session") {
                return (200, Self.guardianSessionJSON(childID: local.child.id))
            }
            if path.hasSuffix("/families/family/tasks"), request.httpMethod == "GET" {
                if query.contains("snapshot=1") {
                    return (200, #"{"tasks":[],"cursor":10,"hasMore":false,"removedClientRefs":[]}"#)
                }
                return (200, #"{"tasks":[],"cursor":10,"hasMore":false,"removedClientRefs":[]}"#)
            }
            if path.hasSuffix("/families/family/tasks"), request.httpMethod == "POST" {
                postCount += 1
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )

        try await store.syncGuardianTasks(from: local)

        XCTAssertFalse(local.assignments.contains(where: { $0.id == legacy.id }))
        XCTAssertEqual(local.familyNetwork.familyName, "Home")
        XCTAssertEqual(postCount, 0, "Legacy local cache must not become a cloud write")
        XCTAssertEqual(persistence.load().guardianTaskBaselineEstablished, true)
    }

    @MainActor
    func testGuardianFirstBaselinePreservesAndUploadsExplicitlyQueuedTask() async throws {
        let local = LocalFamilyStore()
        local.applyFamilySetup(childName: "Alex", dailyLimitMinutes: 120, keepStarterTasks: false)
        let assignment = try XCTUnwrap(local.assignNewTask(
            title: "今晚收拾书包",
            instructions: "完成后告诉家长",
            category: .family,
            rewardMinutes: 20,
            requiredProof: .text
        ))
        let family = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family-public", displayName: "Cloud Home", isCreator: true),
            guardians: [], children: [], devices: []
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("guardian-session", account: "guardian_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        XCTAssertTrue(persistence.save(FamilyCloudSyncState(cachedFamily: family)))
        var postCount = 0
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/auth/session") {
                return (200, Self.guardianSessionJSON(childID: local.child.id))
            }
            if path.hasSuffix("/families/family/tasks"), request.httpMethod == "GET" {
                return (200, #"{"tasks":[],"cursor":10,"hasMore":false,"removedClientRefs":[]}"#)
            }
            if path.hasSuffix("/families/family/tasks"), request.httpMethod == "POST" {
                postCount += 1
                return (200, Self.taskPageJSON(
                    task: Self.cloudTask(assignmentID: assignment.id, status: "assigned", version: 1),
                    cursor: 11
                ))
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )
        XCTAssertTrue(store.queueGuardianTaskUpsert(assignmentId: assignment.id, local: local))

        try await store.syncGuardianTasks(from: local)

        XCTAssertTrue(local.assignments.contains(where: { $0.id == assignment.id }))
        XCTAssertEqual(postCount, 1)
        XCTAssertEqual(persistence.load().pendingGuardianTaskUpserts?.count, 0)
        XCTAssertEqual(persistence.load().guardianTaskBaselineEstablished, true)
    }

    @MainActor
    func testGuardianFullSnapshotAbsenceDoesNotCancelQueuedTaskIntent() async throws {
        let local = LocalFamilyStore()
        local.applyFamilySetup(childName: "Alex", dailyLimitMinutes: 120, keepStarterTasks: false)
        let assignment = try XCTUnwrap(local.assignNewTask(
            title: "用乐高完成一个主题作品",
            instructions: "完成后拍照",
            category: .creative,
            rewardMinutes: 30,
            requiredProof: .photo
        ))
        let family = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family-public", displayName: "Cloud Home", isCreator: true),
            guardians: [], children: [], devices: []
        )
        let cachedTask = Self.cloudTask(assignmentID: assignment.id, status: "assigned", version: 1)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("guardian-session", account: "guardian_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        XCTAssertTrue(persistence.save(FamilyCloudSyncState(
            guardianCursors: ["family": 10],
            guardianTaskBaselineEstablished: true,
            cachedTasks: [cachedTask],
            cachedFamily: family,
            guardianSnapshotDates: ["family": Date()]
        )))
        var postCount = 0
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/auth/session") {
                return (200, Self.guardianSessionJSON(childID: local.child.id))
            }
            if path.hasSuffix("/families/family/tasks"), request.httpMethod == "GET" {
                return (200, #"{"tasks":[],"cursor":10,"hasMore":false,"removedClientRefs":[]}"#)
            }
            if path.hasSuffix("/families/family/tasks"), request.httpMethod == "POST" {
                postCount += 1
                return (200, Self.taskPageJSON(
                    task: Self.cloudTask(assignmentID: assignment.id, status: "assigned", version: 2),
                    cursor: 11
                ))
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )
        XCTAssertTrue(store.queueGuardianTaskUpsert(assignmentId: assignment.id, local: local))

        try await store.syncGuardianTasks(from: local, forceFullSnapshot: true)

        XCTAssertTrue(local.assignments.contains(where: { $0.id == assignment.id }))
        XCTAssertEqual(postCount, 1)
        XCTAssertEqual(store.pendingGuardianTaskUpsertCount, 0)
    }

    @MainActor
    func testGuardianBatchQueueUsesIndependentMutationReferences() throws {
        let local = LocalFamilyStore()
        local.applyFamilySetup(childName: "Alex", dailyLimitMinutes: 120, keepStarterTasks: false)
        let first = try XCTUnwrap(local.assignNewTask(
            title: "整理书包",
            instructions: "",
            category: .family,
            rewardMinutes: 10,
            requiredProof: .text
        ))
        let second = try XCTUnwrap(local.assignNewTask(
            title: "睡前阅读",
            instructions: "",
            category: .learning,
            rewardMinutes: 15,
            requiredProof: .text
        ))
        let family = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family-public", displayName: "Cloud Home", isCreator: true),
            guardians: [], children: [], devices: []
        )
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("guardian-session", account: "guardian_session"))
        let persistence = InMemoryFamilyCloudSyncStateStore()
        XCTAssertTrue(persistence.save(FamilyCloudSyncState(cachedFamily: family)))
        let store = FamilyCloudSessionStore(secrets: secrets, syncStateStore: persistence)

        XCTAssertTrue(store.queueGuardianTaskUpserts(
            assignmentIds: [first.id, second.id],
            local: local
        ))

        let pending = try XCTUnwrap(persistence.load().pendingGuardianTaskUpserts)
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(Set(pending.map(\.mutationRef)).count, 2)
    }

    @MainActor
    func testGuardianIncrementalTombstoneRemovesLocalTaskAndCancelsQueuedWrite() async throws {
        let local = LocalFamilyStore()
        local.applyFamilySetup(childName: "Alex", dailyLimitMinutes: 120, keepStarterTasks: false)
        let assignmentID = UUID()
        let cloudTask = Self.cloudTask(assignmentID: assignmentID, status: "assigned", version: 4)
        local.applyCloudFamilyTasks([cloudTask], childName: nil)
        let upload = FamilyCloudTaskUpload(
            childClientRef: local.child.id.uuidString.lowercased(),
            clientRef: assignmentID.uuidString.lowercased(),
            title: "stale local edit",
            titleEnglish: nil,
            status: "assigned",
            growthPoints: 99,
            requiresEvidence: false,
            plannedFor: nil,
            version: 4,
            baseVersion: 4,
            taskPayload: nil
        )
        let family = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family-public", displayName: "Home", isCreator: true),
            guardians: [], children: [], devices: []
        )
        let persistence = InMemoryFamilyCloudSyncStateStore()
        XCTAssertTrue(persistence.save(FamilyCloudSyncState(
            guardianCursors: ["family": 4],
            pendingGuardianTaskUpserts: [.init(
                mutationRef: "guardian:stale",
                upload: upload,
                queuedAt: Date(timeIntervalSince1970: 100)
            )],
            guardianTaskBaselineEstablished: true,
            cachedTasks: [cloudTask],
            cachedFamily: family,
            guardianSnapshotDates: ["family": Date()]
        )))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("guardian-session", account: "guardian_session"))
        var postCount = 0
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/auth/session") {
                return (200, Self.guardianSessionJSON(childID: local.child.id))
            }
            if path.hasSuffix("/families/family/tasks"), request.httpMethod == "GET" {
                let response = """
                {"tasks":[],"cursor":5,"hasMore":false,"removedClientRefs":["\(assignmentID.uuidString.lowercased())"]}
                """
                return (200, response)
            }
            if path.hasSuffix("/families/family/tasks"), request.httpMethod == "POST" {
                postCount += 1
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )

        try await store.syncGuardianTasks(from: local)

        XCTAssertFalse(local.assignments.contains(where: { $0.id == assignmentID }))
        XCTAssertEqual(store.pendingGuardianTaskUpsertCount, 0)
        XCTAssertEqual(postCount, 0, "A tombstoned task must never be resurrected from the outbox")
        XCTAssertEqual(persistence.load().guardianCursors["family"], 5)
    }

    @MainActor
    func testManualGuardianPreviewRefreshDoesNotAdvanceFamilyTaskCursor() async throws {
        let local = LocalFamilyStore()
        local.applyFamilySetup(childName: "Alex", dailyLimitMinutes: 120, keepStarterTasks: false)
        let staleAssignmentID = UUID()
        let staleTask = Self.cloudTask(assignmentID: staleAssignmentID, status: "assigned", version: 1)
        local.applyCloudFamilyTasks([staleTask], childName: nil)
        let family = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family-public", displayName: "Home", isCreator: true),
            guardians: [],
            children: [
                .init(
                    id: "cloud-alex",
                    publicRef: "child-public",
                    clientRef: local.child.id.uuidString,
                    displayName: "Alex"
                )
            ],
            devices: []
        )
        let persistence = InMemoryFamilyCloudSyncStateStore()
        XCTAssertTrue(persistence.save(FamilyCloudSyncState(
            guardianCursors: ["family": 41],
            guardianTaskBaselineEstablished: true,
            cachedTasks: [staleTask],
            cachedFamily: family,
            guardianSnapshotDates: ["family": Date()]
        )))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("guardian-session", account: "guardian_session"))
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/auth/session") {
                return (200, Self.guardianSessionJSON(childID: local.child.id))
            }
            if path.hasSuffix("/families/family/children/cloud-alex/surface") {
                return (200, Self.childSurfaceJSON(childID: local.child.id, taskCursor: 100))
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )

        try await store.refreshChildSurface(into: local, forceFullSnapshot: true)

        XCTAssertFalse(local.assignments.contains(where: { $0.id == staleAssignmentID }))
        XCTAssertEqual(
            persistence.load().guardianCursors["family"],
            41,
            "A single-child surface cursor must not skip another child's family-level task changes"
        )
        XCTAssertEqual(persistence.load().guardianTaskBaselineEstablished, true)
        XCTAssertFalse(FamilyCloudURLProtocolStub.requests.contains(where: {
            $0.url?.path.hasSuffix("/families/family/tasks") == true
        }))
        XCTAssertTrue(FamilyCloudURLProtocolStub.requests.contains(where: {
            $0.url?.path.hasSuffix("/families/family/children/cloud-alex/surface") == true
        }))
    }

    @MainActor
    func testGuardianDecisionVersionChangeRequiresFreshReviewWithoutRebaseUpload() async throws {
        let local = LocalFamilyStore()
        let childID = local.child.id
        let assignmentID = UUID()
        let submittedV2 = Self.cloudTask(
            assignmentID: assignmentID,
            status: "submitted",
            version: 2,
            evidenceSummary: "first proof"
        )
        let submittedV3 = Self.cloudTask(
            assignmentID: assignmentID,
            status: "submitted",
            version: 3,
            evidenceSummary: "replacement proof"
        )
        let approvedV4 = Self.cloudTask(
            assignmentID: assignmentID,
            status: "approved",
            version: 4,
            evidenceSummary: "replacement proof"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FamilyCloudURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let secrets = InMemoryFamilyCloudSecretStore()
        XCTAssertTrue(secrets.save("guardian-session", account: "guardian_session"))
        let family = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family-public", displayName: "Home", isCreator: true),
            guardians: [],
            children: [
                .init(
                    id: "cloud-alex",
                    publicRef: "child-public",
                    clientRef: childID.uuidString,
                    displayName: "Alex",
                    growthPointBalance: 0
                )
            ],
            devices: []
        )
        let persistence = InMemoryFamilyCloudSyncStateStore()
        persistence.save(FamilyCloudSyncState(
            guardianCursors: ["family": 2],
            guardianTaskBaselineEstablished: true,
            cachedTasks: [submittedV2],
            cachedFamily: family,
            guardianSnapshotDates: ["family": Date()]
        ))
        var incrementalLoads = 0
        var sessionLoads = 0
        var uploadedBodies: [String] = []
        FamilyCloudURLProtocolStub.requests = []
        FamilyCloudURLProtocolStub.handler = { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/auth/session") {
                sessionLoads += 1
                return (200, Self.guardianSessionJSON(
                    childID: childID,
                    growthPointBalance: sessionLoads > 1 ? 20 : 0
                ))
            }
            if path.hasSuffix("/families/family/tasks"), request.httpMethod == "GET" {
                incrementalLoads += 1
                return (200, Self.taskPageJSON(task: submittedV3, cursor: 3))
            }
            if path.hasSuffix("/families/family/tasks"), request.httpMethod == "POST" {
                uploadedBodies.append(Self.requestBodyString(request) ?? "")
                return (200, Self.taskPageJSON(task: approvedV4, cursor: Int64(approvedV4.version)))
            }
            return (404, #"{"error":"unexpected_test_request"}"#)
        }
        defer {
            FamilyCloudURLProtocolStub.handler = nil
            FamilyCloudURLProtocolStub.requests = []
        }
        let store = FamilyCloudSessionStore(
            client: FamilyCloudClient(baseURL: URL(string: "https://example.test/api/v1/")!, session: session),
            secrets: secrets,
            syncStateStore: persistence
        )
        local.applyCloudFamilyTasks([submittedV2], familySnapshot: family, childName: nil)
        let assignment = try XCTUnwrap(local.assignments.first(where: { $0.id == assignmentID }))
        XCTAssertNotNil(local.approve(assignment))
        XCTAssertTrue(store.queueGuardianTaskDecision(assignmentId: assignmentID, status: .approved))
        XCTAssertEqual(persistence.load().pendingGuardianDecisions?.first?.expectedVersion, 2)

        try await store.syncGuardianTasks(from: local)

        XCTAssertEqual(local.assignments.first(where: { $0.id == assignmentID })?.status, .submitted)
        XCTAssertEqual(local.assignments.first(where: { $0.id == assignmentID })?.proof.text, "replacement proof")
        XCTAssertEqual(local.rewards.count, 1)
        XCTAssertEqual(local.child.rewardBalanceMinutes, 0)
        XCTAssertEqual(store.pendingGuardianDecisionCount, 0)
        XCTAssertEqual(store.message, "任务证明已更新，请基于最新证明重新审核。")
        XCTAssertTrue(uploadedBodies.isEmpty, "A stale local decision must never upload a cloud task body")

        let replacement = try XCTUnwrap(local.assignments.first(where: { $0.id == assignmentID }))
        XCTAssertNil(local.approve(replacement), "新证明仍需审核，但同一任务不应再次发积分")
        XCTAssertTrue(store.queueGuardianTaskDecision(assignmentId: assignmentID, status: .approved))
        XCTAssertEqual(persistence.load().pendingGuardianDecisions?.first?.expectedVersion, 3)

        try await store.syncGuardianTasks(from: local)

        XCTAssertEqual(local.assignments.first(where: { $0.id == assignmentID })?.status, .approved)
        XCTAssertEqual(local.rewards.count, 1)
        XCTAssertEqual(local.child.rewardBalanceMinutes, 20)
        XCTAssertEqual(store.pendingGuardianDecisionCount, 0)
        XCTAssertEqual(uploadedBodies.count, 1)
        XCTAssertTrue(uploadedBodies[0].contains(#""status":"approved""#))
        let secondUpload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(uploadedBodies[0].utf8)) as? [String: Any]
        )
        let uploadedTasks = try XCTUnwrap(secondUpload["tasks"] as? [[String: Any]])
        let approvedTask = try XCTUnwrap(uploadedTasks.first(where: {
            ($0["clientRef"] as? String)?.lowercased() == assignmentID.uuidString.lowercased()
        }))
        XCTAssertEqual(approvedTask["baseVersion"] as? Int, 3)
    }

    func testCloudExportContractIncludesOnlyDeclaredMinimalScope() throws {
        let json = """
        {
          "exportVersion": "2026-07-family-export-v1",
          "exportedAt": "2026-07-10T12:00:00.000Z",
          "scope": "cloud_family_minimal_sync",
          "scopeNote": "Local private content is excluded.",
          "family": {
            "family": {"id":"family-id","publicRef":"family_public","displayName":"My Family","isCreator":true},
            "guardians": [], "children": [], "devices": []
          },
          "tasks": [],
          "audit": [{"action":"family.created","actorKind":"guardian","createdAt":"2026-07-10T12:00:00.000Z"}]
        }
        """
        let export = try JSONDecoder().decode(FamilyCloudExport.self, from: Data(json.utf8))

        XCTAssertEqual(export.scope, "cloud_family_minimal_sync")
        XCTAssertEqual(export.family.family.publicRef, "family_public")
        XCTAssertEqual(export.audit.first?.action, "family.created")
    }

    func testCloudJoinPayloadV2RoundTripsFromServerFormat() throws {
        let payload = FamilyCloudJoinPayload(
            version: 2,
            publicRef: "invite_12345678",
            secret: "one-time-secret",
            kind: "child_device",
            expiresAt: "2026-07-10T12:00:00.000Z"
        )
        let data = try JSONEncoder().encode(payload)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let decoded = try XCTUnwrap(FamilyCloudJoinPayload.decode(FamilyCloudJoinPayload.schemePrefix + encoded))

        XCTAssertEqual(decoded, payload)
        XCTAssertTrue(decoded.isChildDevice)
        XCTAssertFalse(decoded.isGuardian)
    }

    func testCloudJoinPayloadRejectsLegacyAndUnknownKinds() throws {
        XCTAssertNil(FamilyCloudJoinPayload.decode("octoteacher://family/join/legacy"))
        let invalid = FamilyCloudJoinPayload(
            version: 2,
            publicRef: "invite_12345678",
            secret: "secret",
            kind: "relative",
            expiresAt: "2026-07-10T12:00:00.000Z"
        )
        let data = try JSONEncoder().encode(invalid)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertNil(FamilyCloudJoinPayload.decode(FamilyCloudJoinPayload.schemePrefix + encoded))
    }

    @MainActor
    func testCloudTaskImportIsIdempotentAndUsesMinimalFields() throws {
        let store = LocalFamilyStore()
        let taskId = UUID()
        let cloud = FamilyCloudTask(
            id: "server-task",
            childProfileId: "child-server",
            clientRef: taskId.uuidString,
            title: "整理书包",
            titleEnglish: "Pack my school bag",
            status: "assigned",
            growthPoints: 12,
            requiresEvidence: true,
            plannedFor: "2026-07-10",
            evidenceSummary: nil,
            version: 1,
            updatedAt: "2026-07-10T12:00:00.000Z"
        )

        store.applyCloudFamilyTasks([cloud], childName: "Sam")
        store.applyCloudFamilyTasks([cloud], childName: "Sam")

        let imported = store.assignments.filter { $0.id == taskId }
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.task.title, "整理书包")
        XCTAssertEqual(imported.first?.task.rewardMinutes, 12)
        XCTAssertEqual(imported.first?.task.displayTitle(for: .english), "Pack my school bag")
        XCTAssertEqual(store.child.name, "Sam")
    }

    @MainActor
    func testGuardianApprovedCloudTaskGrantsChildPointsExactlyOnce() throws {
        let store = LocalFamilyStore()
        let taskId = UUID()
        let approved = FamilyCloudTask(
            id: "server-approved",
            childProfileId: "child-server",
            clientRef: taskId.uuidString,
            title: "收拾玩具",
            titleEnglish: "Put away toys",
            status: "approved",
            growthPoints: 15,
            requiresEvidence: false,
            plannedFor: nil,
            evidenceSummary: nil,
            version: 2,
            updatedAt: "2026-07-10T12:00:00.000Z"
        )
        let before = store.child.rewardBalanceMinutes

        store.applyCloudFamilyTasks([approved], childName: nil)
        store.applyCloudFamilyTasks([approved], childName: nil)

        XCTAssertEqual(store.child.rewardBalanceMinutes, before + 15)
        XCTAssertEqual(store.rewards.filter { $0.reason == "收拾玩具" }.count, 1)
        XCTAssertEqual(store.assignments.first(where: { $0.id == taskId })?.status, .approved)
    }

    @MainActor
    func testStaleSubmittedCloudTaskCannotReopenLocallyApprovedTask() throws {
        let store = LocalFamilyStore()
        let taskId = UUID()
        let submitted = FamilyCloudTask(
            id: "server-submitted",
            childProfileId: "child-server",
            clientRef: taskId.uuidString,
            title: "出门玩一会儿",
            titleEnglish: "Play outside",
            status: "submitted",
            growthPoints: 15,
            requiresEvidence: true,
            plannedFor: "2026-07-12",
            evidenceSummary: "I played outside.",
            version: 2,
            updatedAt: "2026-07-12T12:00:00.000Z"
        )
        store.applyCloudFamilyTasks([submitted], childName: nil)
        let assignment = try XCTUnwrap(store.assignments.first(where: { $0.id == taskId }))
        let before = store.child.rewardBalanceMinutes

        XCTAssertNotNil(store.approve(assignment))
        store.applyCloudFamilyTasks(
            [submitted],
            childName: nil,
            preservingLocalStatusesFor: [taskId]
        )

        XCTAssertEqual(store.assignments.first(where: { $0.id == taskId })?.status, .approved)
        XCTAssertEqual(store.child.rewardBalanceMinutes, before + 15)
        XCTAssertEqual(store.rewards.filter { $0.reason == "出门玩一会儿" }.count, 1)
    }

    @MainActor
    func testCloudApprovalConvergesAfterPendingLocalDecisionUploads() throws {
        let store = LocalFamilyStore()
        let taskId = UUID()
        var cloud = FamilyCloudTask(
            id: "server-converged",
            childProfileId: "child-server",
            clientRef: taskId.uuidString,
            title: "整理书包",
            titleEnglish: "Pack the school bag",
            status: "submitted",
            growthPoints: 12,
            requiresEvidence: true,
            plannedFor: "2026-07-12",
            evidenceSummary: "Done.",
            version: 2,
            updatedAt: "2026-07-12T12:00:00.000Z"
        )
        store.applyCloudFamilyTasks([cloud], childName: nil)
        let assignment = try XCTUnwrap(store.assignments.first(where: { $0.id == taskId }))
        store.reject(assignment)

        cloud.status = "approved"
        cloud.version = 3
        store.applyCloudFamilyTasks([cloud], childName: nil)

        XCTAssertEqual(store.assignments.first(where: { $0.id == taskId })?.status, .approved)
        XCTAssertEqual(store.rewards.filter { $0.reason == "整理书包" }.count, 1)
    }

    @MainActor
    func testCloudTasksMapToTheirOwnChildInsteadOfTheActiveChild() throws {
        let store = LocalFamilyStore()
        let second = try XCTUnwrap(store.addChild(name: "Alex", age: 6))
        let assignmentId = UUID()
        let cloud = FamilyCloudTask(
            id: "server-alex-task",
            childProfileId: "cloud-alex",
            clientRef: assignmentId.uuidString,
            title: "整理积木",
            titleEnglish: "Put away blocks",
            status: "assigned",
            growthPoints: 10,
            requiresEvidence: false,
            plannedFor: "2026-07-12",
            evidenceSummary: nil,
            version: 1,
            updatedAt: "2026-07-10T12:00:00.000Z"
        )
        let snapshot = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family_public", displayName: "Home", isCreator: true),
            guardians: [],
            children: [
                .init(
                    id: "cloud-alex",
                    publicRef: "child_public",
                    clientRef: second.id.uuidString.lowercased(),
                    displayName: second.name,
                    birthYear: 2020
                )
            ],
            devices: []
        )

        store.applyCloudFamilyTasks([cloud], familySnapshot: snapshot, childName: nil)

        XCTAssertEqual(store.assignments.first(where: { $0.id == assignmentId })?.childId, second.id)
        XCTAssertNotEqual(store.activeChildId, second.id)
        let assignedDate = try XCTUnwrap(store.assignments.first(where: { $0.id == assignmentId })?.date)
        XCTAssertEqual(assignedDate, Date(timeIntervalSince1970: 1_783_814_400))
    }

    @MainActor
    func testGuardianSurfaceRefreshDoesNotActivateAChildThatIsNoLongerSelected() throws {
        let store = LocalFamilyStore()
        let originalChildID = store.activeChildId
        let second = try XCTUnwrap(store.addChild(name: "Alex", age: 6))
        let surfaceChild = FamilyChildSurface.Child(
            id: "cloud-alex",
            publicRef: "child-public",
            clientRef: second.id.uuidString.lowercased(),
            displayName: "Alex Cloud",
            birthYear: Calendar.current.component(.year, from: Date()) - 7,
            preReaderMode: true,
            interfaceLanguage: .english,
            contentLanguage: .english,
            growthPointBalance: 42
        )

        store.applyCloudChildSurfaceProfile(surfaceChild, makeActive: false)

        XCTAssertEqual(store.activeChildId, originalChildID)
        let refreshed = try XCTUnwrap(store.children.first(where: { $0.id == second.id }))
        XCTAssertEqual(refreshed.name, "Alex Cloud")
        XCTAssertEqual(refreshed.rewardBalanceMinutes, 42)
        XCTAssertTrue(refreshed.isPreReader)
        XCTAssertEqual(refreshed.interfaceLanguage, .english)
    }

    @MainActor
    func testGuardianCloudTaskWithUnknownChildIsNotLeakedToActiveChild() {
        let store = LocalFamilyStore()
        let assignmentId = UUID()
        let cloud = FamilyCloudTask(
            id: "server-unknown-child",
            childProfileId: "missing-child",
            clientRef: assignmentId.uuidString,
            title: "Private task for another child",
            titleEnglish: nil,
            status: "assigned",
            growthPoints: 10,
            requiresEvidence: false,
            plannedFor: nil,
            evidenceSummary: nil,
            version: 1,
            updatedAt: "2026-07-10T12:00:00.000Z"
        )
        let snapshot = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family_public", displayName: "Home", isCreator: true),
            guardians: [], children: [], devices: []
        )

        store.applyCloudFamilyTasks([cloud], familySnapshot: snapshot, childName: nil)

        XCTAssertFalse(store.assignments.contains(where: { $0.id == assignmentId }))
    }

    @MainActor
    func testBoundChildProfileControlsIdentityLanguageAndPreReaderMode() {
        let store = LocalFamilyStore()
        let parentChildID = UUID()
        var policy = FamilyExchangePolicy.default
        policy.customScreenExchangeMinutes = 45
        policy.customScreenPointsPer15Minutes = 80
        policy.pointsPerCurrencyUnit = 25
        let profile = ChildDeviceProfileResponse(
            id: "cloud-alex",
            publicRef: "child-public",
            clientRef: parentChildID.uuidString.lowercased(),
            displayName: "Alex",
            birthYear: Calendar.current.component(.year, from: Date()) - 7,
            preReaderMode: true,
            interfaceLanguage: .english,
            contentLanguage: .english,
            dailyLimitMinutes: 720,
            exchangePolicy: policy,
            profileVersion: 3,
            family: .init(id: "family", publicRef: "family-public", displayName: "Home")
        )

        store.applyCloudChildProfile(profile)

        XCTAssertEqual(store.children.count, 1)
        XCTAssertEqual(store.activeChildId, parentChildID)
        XCTAssertEqual(store.child.name, "Alex")
        XCTAssertEqual(store.child.age, 7)
        XCTAssertTrue(store.isPreReaderActive)
        XCTAssertEqual(store.activeChildInterfaceLanguage, .english)
        XCTAssertEqual(store.activeContentLanguage, .english)
        XCTAssertEqual(store.child.dailyLimitMinutes, 720)
        XCTAssertEqual(store.policy(for: parentChildID).resolvedScreenExchangeMinutes, 45)
        XCTAssertEqual(store.policy(for: parentChildID).screenPointsRequired(forMinutes: 45), 80)
        XCTAssertEqual(store.policy(for: parentChildID).pointsPerCurrencyUnit, 25)
    }

    @MainActor
    func testGuardianProfileMergeAppliesCloudLanguageButPreservesPendingLocalEdit() throws {
        let store = LocalFamilyStore()
        let child = store.child
        store.setChildInterfaceLanguage(.english, for: child.id)
        let cloud = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family-public", displayName: "Home", isCreator: true),
            guardians: [],
            children: [
                .init(
                    id: "cloud-child",
                    publicRef: "child-public",
                    clientRef: child.id.uuidString.lowercased(),
                    displayName: child.name,
                    birthYear: Calendar.current.component(.year, from: Date()) - child.age,
                    preReaderMode: true,
                    interfaceLanguage: .chinese,
                    contentLanguage: .english,
                    dailyLimitMinutes: 120,
                    exchangePolicy: .default,
                    profileVersion: 7
                )
            ],
            devices: []
        )

        store.applyCloudGuardianProfiles(cloud)
        XCTAssertEqual(store.childInterfaceLanguage(for: child.id), .chinese)
        XCTAssertTrue(store.children.first(where: { $0.id == child.id })?.isPreReader == true)
        XCTAssertEqual(store.children.first(where: { $0.id == child.id })?.dailyLimitMinutes, 120)

        store.setChildInterfaceLanguage(.english, for: child.id)
        store.applyCloudGuardianProfiles(
            cloud,
            preservingClientRefs: [child.id.uuidString.lowercased()]
        )
        XCTAssertEqual(
            store.childInterfaceLanguage(for: child.id),
            .english,
            "A cloud pull must not overwrite an explicit local edit waiting for upload"
        )
    }

    @MainActor
    func testGuardianCloudChildrenReplaceLegacyGenericSeedAndRemainSelectable() throws {
        let store = LocalFamilyStore()
        XCTAssertEqual(store.children.count, 1)
        let samID = UUID()
        let alexID = UUID()
        let cloud = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family-public", displayName: "Home", isCreator: true),
            guardians: [],
            children: [
                .init(
                    id: "cloud-sam",
                    publicRef: "child-sam",
                    clientRef: samID.uuidString.lowercased(),
                    displayName: "Sam",
                    birthYear: Calendar.current.component(.year, from: Date()) - 11,
                    preReaderMode: false,
                    interfaceLanguage: .english,
                    contentLanguage: .english,
                    dailyLimitMinutes: 180,
                    exchangePolicy: .default,
                    profileVersion: 2
                ),
                .init(
                    id: "cloud-alex",
                    publicRef: "child-alex",
                    clientRef: alexID.uuidString.lowercased(),
                    displayName: "Alex",
                    birthYear: Calendar.current.component(.year, from: Date()) - 7,
                    preReaderMode: true,
                    interfaceLanguage: .english,
                    contentLanguage: .english,
                    dailyLimitMinutes: 120,
                    exchangePolicy: .default,
                    profileVersion: 4
                )
            ],
            devices: []
        )

        store.applyCloudGuardianProfiles(cloud)

        XCTAssertEqual(store.children.map(\.id), [samID, alexID])
        XCTAssertEqual(store.children.map(\.name), ["Sam", "Alex"])
        XCTAssertFalse(store.children.contains(where: { $0.name == "孩子" }))
        XCTAssertEqual(store.activeChildId, samID)
        XCTAssertEqual(
            Set(store.familyNetwork.activeMembers(role: .child).compactMap(\.childId)),
            Set([samID, alexID])
        )

        store.setActiveChild(alexID)
        XCTAssertEqual(store.child.name, "Alex")
        XCTAssertTrue(store.isPreReaderActive)
    }

    @MainActor
    func testGuardianCloudMergePreservesOnlyExplicitPendingLocalChild() throws {
        let store = LocalFamilyStore()
        let localOnly = try XCTUnwrap(store.addChild(name: "Mia", age: 6))
        let cloudChildID = UUID()
        let cloud = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family-public", displayName: "Home", isCreator: true),
            guardians: [],
            children: [
                .init(
                    id: "cloud-sam",
                    publicRef: "child-sam",
                    clientRef: cloudChildID.uuidString.lowercased(),
                    displayName: "Sam",
                    birthYear: Calendar.current.component(.year, from: Date()) - 11,
                    preReaderMode: false,
                    interfaceLanguage: .english,
                    contentLanguage: .english,
                    dailyLimitMinutes: 180,
                    exchangePolicy: .default,
                    profileVersion: 1
                )
            ],
            devices: []
        )

        store.applyCloudGuardianProfiles(
            cloud,
            preservingClientRefs: [localOnly.id.uuidString.lowercased()]
        )
        XCTAssertEqual(Set(store.children.map(\.id)), Set([cloudChildID, localOnly.id]))

        store.applyCloudGuardianProfiles(cloud)
        XCTAssertEqual(store.children.map(\.id), [cloudChildID])
        XCTAssertEqual(store.children.map(\.name), ["Sam"])
    }

    @MainActor
    func testGuardianCloudArchiveCancelsUnfinishedWorkButKeepsApprovedHistory() throws {
        let store = LocalFamilyStore()
        let archivedChild = try XCTUnwrap(store.addChild(name: "Mia", age: 6))
        let openTask = try XCTUnwrap(store.assignNewTask(
            title: "收拾玩具",
            instructions: "Put toys away.",
            category: .home,
            rewardMinutes: 10,
            requiredProof: .text,
            childId: archivedChild.id
        ))
        let approvedTask = try XCTUnwrap(store.assignNewTask(
            title: "按时睡觉",
            instructions: "Go to bed on time.",
            category: .home,
            rewardMinutes: 10,
            requiredProof: .text,
            childId: archivedChild.id
        ))
        let approvedIndex = try XCTUnwrap(store.assignments.firstIndex(where: { $0.id == approvedTask.id }))
        store.assignments[approvedIndex].status = .approved

        let cloudChildID = UUID()
        let cloud = FamilyCloudSnapshot(
            family: .init(id: "family", publicRef: "family-public", displayName: "Home", isCreator: true),
            guardians: [],
            children: [
                .init(
                    id: "cloud-sam",
                    publicRef: "child-sam",
                    clientRef: cloudChildID.uuidString.lowercased(),
                    displayName: "Sam",
                    birthYear: Calendar.current.component(.year, from: Date()) - 11,
                    preReaderMode: false,
                    interfaceLanguage: .english,
                    contentLanguage: .english,
                    dailyLimitMinutes: 180,
                    exchangePolicy: .default,
                    profileVersion: 1
                )
            ],
            devices: []
        )

        store.applyCloudGuardianProfiles(cloud)

        XCTAssertEqual(store.assignments.first(where: { $0.id == openTask.id })?.status, .cancelled)
        XCTAssertEqual(store.assignments.first(where: { $0.id == approvedTask.id })?.status, .approved)
    }

    @MainActor
    func testVersionedCloudPayloadPreservesReadingTaskAndBookReference() {
        let store = LocalFamilyStore()
        let assignmentID = UUID()
        let bookID = UUID()
        let template = TaskTemplate(
            id: UUID(),
            title: "读《The Picture Alphabet》",
            category: .learning,
            difficulty: .easy,
            rewardMinutes: 20,
            instructions: "Read the next chapter.",
            requiredProof: .text,
            reading: ReadingSpec(
                bookTitle: "The Picture Alphabet",
                minMinutes: 10,
                chapterPlanText: "Chapter 1",
                importedBookId: bookID
            ),
            localizedContent: [
                TaskLocalizedContent(language: .english, title: "Read The Picture Alphabet", instructions: "Read the next chapter.")
            ]
        )
        let cloud = FamilyCloudTask(
            id: "server-reading",
            childProfileId: "cloud-child",
            clientRef: assignmentID.uuidString,
            title: template.title,
            titleEnglish: "Read The Picture Alphabet",
            status: "assigned",
            growthPoints: 20,
            requiresEvidence: true,
            plannedFor: "2026-07-11",
            evidenceSummary: nil,
            taskPayload: FamilyCloudTaskPayload(
                task: template,
                bookResource: FamilyCloudBookResource(
                    id: bookID,
                    title: "The Picture Alphabet",
                    format: "epub",
                    sourceName: "Project Gutenberg",
                    sourceURLString: "https://example.com/picture-alphabet.epub"
                ),
                readingMode: .digitalLoaded,
                contentReadiness: .ready
            ),
            version: 1,
            updatedAt: "2026-07-11T12:00:00.000Z"
        )

        store.applyCloudFamilyTasks([cloud], childName: "Alex")

        let imported = store.assignments.first(where: { $0.id == assignmentID })
        XCTAssertEqual(imported?.task.category, .learning)
        XCTAssertEqual(imported?.task.instructions, "Read the next chapter.")
        XCTAssertEqual(imported?.task.reading?.importedBookId, bookID)
        XCTAssertEqual(imported?.task.displayTitle(for: .english), "Read The Picture Alphabet")
        XCTAssertEqual(
            store.growthPack.steps.filter { $0.assignmentId == assignmentID }.count,
            1,
            "Cloud tasks must be visible in the child growth-plan UI"
        )

        store.applyCloudFamilyTasks([cloud], childName: "Alex")
        XCTAssertEqual(
            store.growthPack.steps.filter { $0.assignmentId == assignmentID }.count,
            1,
            "Repeated cloud refreshes must not duplicate the visible step"
        )
    }

    private static func cloudTask(
        assignmentID: UUID,
        status: String,
        version: Int,
        evidenceSummary: String? = nil
    ) -> FamilyCloudTask {
        let task = TaskTemplate(
            id: UUID(),
            title: "按时上床睡觉",
            category: .family,
            difficulty: .easy,
            rewardMinutes: 20,
            instructions: "",
            requiredProof: .text
        )
        return FamilyCloudTask(
            id: "cloud-alex-bedtime",
            childProfileId: "cloud-alex",
            clientRef: assignmentID.uuidString,
            title: "按时上床睡觉",
            titleEnglish: "Go to bed on time",
            status: status,
            growthPoints: 20,
            requiresEvidence: false,
            plannedFor: "2026-07-13",
            evidenceSummary: evidenceSummary ?? (status == "submitted" ? "完成" : nil),
            taskPayload: FamilyCloudTaskPayload(
                task: task,
                bookResource: nil,
                readingMode: nil,
                contentReadiness: .notRequired
            ),
            version: version,
            updatedAt: "2026-07-13T16:00:00.000Z"
        )
    }

    private static func guardianSessionJSON(childID: UUID, growthPointBalance: Int = 0) -> String {
        #"{"guardian":{"id":"guardian","displayName":"Parent"},"family":{"family":{"id":"family","publicRef":"family-public","displayName":"Home","isCreator":true},"guardians":[],"children":[{"id":"cloud-alex","publicRef":"child-public","clientRef":"\#(childID.uuidString)","displayName":"Alex","growthPointBalance":\#(growthPointBalance)}],"devices":[]}}"#
    }

    private static func childSurfaceJSON(
        childID: UUID? = nil,
        taskCursor: Int64,
        tasks: [FamilyCloudTask] = []
    ) -> String {
        let modules = [
            FamilyChildSurface.Module(id: "module:today", key: .today, title: "今天任务", titleEnglish: "Today", sortOrder: 100),
            FamilyChildSurface.Module(id: "module:reading", key: .reading, title: "图书馆", titleEnglish: "Library", sortOrder: 200),
            FamilyChildSurface.Module(id: "module:video", key: .video, title: "教育视频", titleEnglish: "Educational Videos", sortOrder: 300),
            FamilyChildSurface.Module(id: "module:creation", key: .creation, title: "创作广场", titleEnglish: "Creation Plaza", sortOrder: 400),
            FamilyChildSurface.Module(id: "module:completed", key: .completed, title: "完成回看", titleEnglish: "Completed", sortOrder: 500),
        ]
        let surface = FamilyChildSurface(
            schemaVersion: 1,
            generatedAt: "2026-07-17T20:00:00.000Z",
            cursor: "surface-cursor",
            surfaceVersion: "surface-version",
            child: .init(
                id: "cloud-alex",
                publicRef: "child-public",
                clientRef: childID?.uuidString,
                displayName: "Alex",
                birthYear: 2019,
                preReaderMode: true,
                interfaceLanguage: .english,
                contentLanguage: .english,
                growthPointBalance: 35
            ),
            modules: modules,
            tasks: tasks.enumerated().map { index, task in
                .init(
                    itemId: "task:\(task.clientRef.lowercased())",
                    moduleId: "module:today",
                    sortOrder: 1_000_000 + index,
                    task: task
                )
            },
            library: .init(books: [], videos: [], creations: []),
            sync: .init(
                taskCursor: taskCursor,
                removedRefs: .init(tasks: [], content: [])
            )
        )
        let data = try! JSONEncoder().encode(surface)
        return #"{"surface":\#(String(decoding: data, as: UTF8.self))}"#
    }

    private static func completedScreenTimeReceipt(
        sessionID: UUID,
        authority: ScreenTimeGrantAuthority = .growthPoints,
        grantedMinutes: Int = 45,
        consumedMinutes: Int,
        appUsageRef: String? = nil
    ) -> RewardSessionReceipt {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        return RewardSessionReceipt(
            id: sessionID,
            sessionID: sessionID,
            appUsageRef: appUsageRef,
            grantedMinutes: grantedMinutes,
            startedAt: startedAt,
            plannedEndsAt: startedAt.addingTimeInterval(TimeInterval(grantedMinutes * 60)),
            endedAt: startedAt.addingTimeInterval(TimeInterval(consumedMinutes * 60)),
            endReason: consumedMinutes < grantedMinutes ? .parentEnded : .expired,
            consumedMinutes: consumedMinutes,
            unusedMinutes: max(0, grantedMinutes - consumedMinutes),
            authority: authority
        )
    }

    private static let childProfileJSON = #"{"child":{"id":"cloud-alex","publicRef":"child-public","clientRef":"8e4ef1e3-1151-4d85-b398-088978017070","displayName":"Alex","birthYear":2019,"preReaderMode":true,"interfaceLanguage":"english","contentLanguage":"english","profileVersion":3,"family":{"id":"family","publicRef":"family-public","displayName":"Home"}}}"#

    private static func taskPageJSON(task: FamilyCloudTask, cursor: Int64) -> String {
        let data = try! JSONEncoder().encode(FamilyCloudTaskPage(
            tasks: [task],
            cursor: cursor,
            hasMore: false
        ))
        return String(decoding: data, as: UTF8.self)
    }

    private static func taskEnvelopeJSON(task: FamilyCloudTask) -> String {
        let taskData = try! JSONEncoder().encode(task)
        return #"{"task":\#(String(decoding: taskData, as: UTF8.self))}"#
    }

    private static func taskPageJSON(assignmentID: UUID, status: String, version: Int) -> String {
        taskPageJSON(
            task: cloudTask(assignmentID: assignmentID, status: status, version: version),
            cursor: 177
        )
    }

    private static func requestBodyString(_ request: URLRequest) -> String? {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8)
        }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return String(data: data, encoding: .utf8)
    }
}

final class FamilyCloudURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (statusCode, body) = handler(request)
        guard
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: nil,
                  headerFields: nil
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class FailingDiskFamilyCloudSyncStateStore: FamilyCloudSyncStateStoring {
    private var state: FamilyCloudSyncState
    private(set) var saveAttempts = 0

    init(initialState: FamilyCloudSyncState = FamilyCloudSyncState()) {
        state = initialState
    }

    func load() -> FamilyCloudSyncState { state }

    @discardableResult
    func save(_ state: FamilyCloudSyncState) -> Bool {
        saveAttempts += 1
        return false
    }
}
