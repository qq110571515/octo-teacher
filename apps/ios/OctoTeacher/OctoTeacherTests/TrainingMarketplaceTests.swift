import XCTest
@testable import OctoTeacher

final class TrainingMarketplaceTests: XCTestCase {
    func testCloudCatalogDecodesVersionedRedactedListing() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarketplaceCatalogURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        MarketplaceCatalogURLProtocolStub.stub = (200, Self.cloudCatalogJSON)
        defer { MarketplaceCatalogURLProtocolStub.stub = nil }

        let provider = CloudTrainingMarketplaceCatalogProvider(
            endpoint: URL(string: "https://example.test/api/v1/marketplace/listings")!,
            session: session
        )
        let listings = try await provider.loadListings()

        XCTAssertEqual(listings.count, 1)
        XCTAssertEqual(listings[0].id, "cloud-learning-pack")
        XCTAssertEqual(listings[0].version, "2.0.0")
        XCTAssertEqual(listings[0].planItems.first?.templateID, "learn-mental-math")
        XCTAssertEqual(listings[0].availability, .betaAccess)
        XCTAssertEqual(MarketplaceCatalogURLProtocolStub.lastRequest?.httpMethod, "GET")
    }

    func testCloudCatalogRejectsUnsupportedSchemaWithoutTouchingLocalStore() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarketplaceCatalogURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        MarketplaceCatalogURLProtocolStub.stub = (200, #"{"schemaVersion":99,"listings":[]}"#)
        defer { MarketplaceCatalogURLProtocolStub.stub = nil }
        let provider = CloudTrainingMarketplaceCatalogProvider(
            endpoint: URL(string: "https://example.test/api/v1/marketplace/listings")!,
            session: session
        )
        let store = LocalFamilyStore()
        let initial = store.snapshot

        do {
            _ = try await provider.loadListings()
            XCTFail("Expected unsupported schema")
        } catch {
            XCTAssertEqual(error as? TrainingMarketplaceCloudCatalogError, .unsupportedSchema)
        }
        XCTAssertEqual(store.snapshot, initial)
    }

    func testPricePreviewShowsActualPrice() {
        XCTAssertEqual(
            TrainingMarketplaceAvailability.pricePreview("$4.99").label(for: .chinese),
            "价格预览 $4.99"
        )
        XCTAssertEqual(
            TrainingMarketplaceAvailability.pricePreview("$4.99").label(for: .english),
            "Price preview $4.99"
        )
    }

    private let provider = LocalTrainingMarketplaceCatalogProvider()

    func testLocalCatalogHasStableUniqueInstallableListings() throws {
        let listings = provider.listings()
        XCTAssertGreaterThanOrEqual(listings.count, 6)
        XCTAssertEqual(listings.map(\.id).count, Set(listings.map(\.id)).count)
        XCTAssertTrue(listings.contains { $0.kind == .libraryAsset })
        XCTAssertTrue(listings.contains { $0.kind == .mixedGrowthPack })

        for listing in listings where listing.availability.canInstallLocally && !listing.isLibraryEntry {
            XCTAssertFalse(listing.planItems.isEmpty, listing.id)
            XCTAssertFalse(listing.version.isEmpty, listing.id)
            for item in listing.planItems {
                XCTAssertNotNil(item.resolvedTemplate(), "Missing \(item.packType.rawValue)/\(item.templateID)")
            }
        }
    }

    func testLibraryEntryStaysSeparateFromTaskInstallation() throws {
        let library = try XCTUnwrap(provider.listings().first { $0.isLibraryEntry })
        XCTAssertTrue(library.planItems.isEmpty)

        let store = LocalFamilyStore()
        XCTAssertThrowsError(
            try store.installTrainingMarketplaceListing(
                library,
                configuration: configuration(for: store.child.id)
            )
        ) { error in
            XCTAssertEqual(error as? TrainingMarketplaceInstallationError, .listingNotInstallable)
        }
    }

    func testInstallWritesScheduledTasksAndPersistentReceiptAtomically() throws {
        let listing = try XCTUnwrap(provider.listings().first { $0.id == "independence-week" })
        let store = LocalFamilyStore()
        let initialAssignmentCount = store.assignments.count
        let initialStepCount = store.growthPack.steps.count
        let initialEventCount = store.events.count
        let start = Calendar.current.startOfDay(for: Date())

        let receipt = try store.installTrainingMarketplaceListing(
            listing,
            configuration: TrainingMarketplaceInstallConfiguration(
                childID: store.child.id,
                startDate: start,
                pace: .balanced,
                pointsOverride: 25,
                proofPreference: .followPlan
            )
        )

        XCTAssertEqual(receipt.assignmentIDs.count, listing.planItems.count)
        XCTAssertEqual(store.assignments.count, initialAssignmentCount + listing.planItems.count)
        XCTAssertEqual(store.growthPack.steps.count, initialStepCount + listing.planItems.count)
        XCTAssertEqual(store.events.count, initialEventCount + 1)
        XCTAssertEqual(store.trainingMarketplaceInstallations, [receipt])

        let installedAssignments = store.assignments.filter { receipt.assignmentIDs.contains($0.id) }
        XCTAssertEqual(installedAssignments.count, listing.planItems.count)
        XCTAssertTrue(installedAssignments.allSatisfy { $0.childId == store.child.id })
        XCTAssertTrue(installedAssignments.allSatisfy { $0.task.rewardMinutes == 25 })
        XCTAssertTrue(installedAssignments.allSatisfy {
            $0.task.localizedContent?.contains(where: { $0.language == .english }) == true
        })
        XCTAssertEqual(installedAssignments.map(\.date).min(), start)
        XCTAssertEqual(
            Calendar.current.dateComponents(
                [.day],
                from: start,
                to: try XCTUnwrap(installedAssignments.map(\.date).max())
            ).day,
            6
        )

        let data = try JSONEncoder().encode(store.snapshot)
        let decoded = try JSONDecoder().decode(FamilyStoreSnapshot.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 8)
        XCTAssertEqual(decoded.trainingMarketplaceInstallations, [receipt])
    }

    func testDuplicateVersionForSameChildIsBlockedWithoutPartialWrites() throws {
        var listing = try XCTUnwrap(provider.listings().first { $0.id == "family-helper-week" })
        let store = LocalFamilyStore()
        _ = try store.installTrainingMarketplaceListing(
            listing,
            configuration: configuration(for: store.child.id)
        )
        let assignmentCount = store.assignments.count
        let eventCount = store.events.count
        listing.version = "1.1.0"

        XCTAssertThrowsError(
            try store.installTrainingMarketplaceListing(
                listing,
                configuration: configuration(for: store.child.id)
            )
        ) { error in
            XCTAssertEqual(error as? TrainingMarketplaceInstallationError, .alreadyInstalled)
        }
        XCTAssertEqual(store.assignments.count, assignmentCount)
        XCTAssertEqual(store.events.count, eventCount)
        XCTAssertEqual(store.trainingMarketplaceInstallations.count, 1)
    }

    func testResourceCollectionInstallsIntoContentCentersWithoutCreatingTasks() throws {
        let store = LocalFamilyStore()
        let initialAssignmentCount = store.assignments.count
        let resource = TrainingMarketplaceResource(
            id: "video-ev-test",
            kind: .video,
            title: "测试教育视频",
            titleEnglish: "Test Educational Video",
            summary: "测试摘要",
            summaryEnglish: "Test summary",
            sourceName: "Test Channel",
            sourceURL: "https://www.youtube.com/watch?v=test",
            thumbnailURL: nil,
            languageCode: "en",
            minAge: 3,
            maxAge: 13,
            durationSeconds: 600,
            categories: ["科学"],
            categoriesEnglish: ["Science"],
            installBehavior: .videoReference
        )
        let listing = TrainingMarketplaceListing(
            id: "test-video-library",
            version: "1.0.0",
            kind: .libraryAsset,
            category: .learning,
            title: "测试视频库",
            titleEnglish: "Test Video Library",
            summary: "摘要",
            summaryEnglish: "Summary",
            detail: "详情",
            detailEnglish: "Detail",
            minAge: 3,
            maxAge: 13,
            durationDays: 0,
            creator: TrainingMarketplaceCreator(
                id: "test-creator",
                displayName: "测试",
                displayNameEnglish: "Test",
                bio: "测试",
                bioEnglish: "Test",
                isVerified: true,
                rating: 5,
                verifiedFamilyCount: 1
            ),
            availability: .free,
            rating: 5,
            ratingCount: 1,
            tags: [],
            tagsEnglish: [],
            planItems: [],
            resources: [resource],
            reviews: []
        )

        let receipt = try store.installTrainingMarketplaceListing(
            listing,
            configuration: configuration(for: store.child.id)
        )

        XCTAssertEqual(store.assignments.count, initialAssignmentCount)
        XCTAssertEqual(receipt.assignmentIDs, [])
        XCTAssertEqual(receipt.installedResourceIDs, [resource.id])
        XCTAssertEqual(store.installedMarketplaceResources.map(\.resource), [resource])

        var secondListing = listing
        secondListing.id = "test-video-library-secondary"
        secondListing.version = "2.0.0"
        _ = try store.installTrainingMarketplaceListing(
            secondListing,
            configuration: configuration(for: store.child.id)
        )

        XCTAssertEqual(store.installedMarketplaceResources.count, 1)
        XCTAssertEqual(store.installedMarketplaceResources.first?.listingID, secondListing.id)
        XCTAssertEqual(store.installedMarketplaceResources.first?.listingVersion, secondListing.version)
        XCTAssertEqual(
            Set(try XCTUnwrap(store.installedMarketplaceResources.first).resolvedSourceListingIDs),
            Set([listing.id, secondListing.id])
        )

        let restored = try JSONDecoder().decode(
            FamilyStoreSnapshot.self,
            from: JSONEncoder().encode(store.snapshot)
        )
        XCTAssertEqual(restored.installedMarketplaceResources?.map(\.resource), [resource])
        XCTAssertEqual(
            Set(try XCTUnwrap(restored.installedMarketplaceResources?.first).resolvedSourceListingIDs),
            Set([listing.id, secondListing.id])
        )
    }

    func testInstalledPackRestoresFromFilePersistenceAfterRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("training-marketplace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileFamilyStorePersistence(fileURL: directory.appendingPathComponent("family.json"))
        let listing = try XCTUnwrap(provider.listings().first { $0.id == "outdoor-reset" })

        let firstLaunch = LocalFamilyStore(persistence: persistence)
        let receipt = try firstLaunch.installTrainingMarketplaceListing(
            listing,
            configuration: configuration(for: firstLaunch.child.id)
        )

        let relaunched = LocalFamilyStore(persistence: persistence)
        let restoredReceipt = try XCTUnwrap(relaunched.trainingMarketplaceInstallations.first)
        XCTAssertEqual(restoredReceipt.id, receipt.id)
        XCTAssertEqual(restoredReceipt.listingID, receipt.listingID)
        XCTAssertEqual(restoredReceipt.listingVersion, receipt.listingVersion)
        XCTAssertEqual(restoredReceipt.childID, receipt.childID)
        XCTAssertEqual(restoredReceipt.assignmentIDs, receipt.assignmentIDs)
        XCTAssertEqual(restoredReceipt.startDate, receipt.startDate)
        XCTAssertLessThan(abs(restoredReceipt.installedAt.timeIntervalSince(receipt.installedAt)), 1)
        XCTAssertEqual(
            relaunched.assignments.filter { receipt.assignmentIDs.contains($0.id) }.count,
            receipt.assignmentIDs.count
        )
        XCTAssertNotNil(
            relaunched.marketplaceInstallation(listingID: listing.id, childID: relaunched.child.id)
        )
    }

    func testAgeGateAndSecondChildInstallation() throws {
        let listing = try XCTUnwrap(provider.listings().first { $0.id == "independence-week" })
        let store = LocalFamilyStore()
        let older = try XCTUnwrap(store.addChild(name: "姐姐", age: 16))
        let younger = try XCTUnwrap(store.addChild(name: "弟弟", age: 7))

        XCTAssertThrowsError(
            try store.installTrainingMarketplaceListing(
                listing,
                configuration: configuration(for: older.id)
            )
        ) { error in
            XCTAssertEqual(error as? TrainingMarketplaceInstallationError, .ageMismatch)
        }

        let receipt = try store.installTrainingMarketplaceListing(
            listing,
            configuration: configuration(for: younger.id)
        )
        XCTAssertTrue(store.assignments.filter { receipt.assignmentIDs.contains($0.id) }.allSatisfy {
            $0.childId == younger.id
        })
    }

    func testPricePreviewDoesNotInstallOrCreateFakeTransactions() throws {
        let preview = try XCTUnwrap(provider.listings().first {
            if case .pricePreview = $0.availability { return true }
            return false
        })
        let store = LocalFamilyStore()
        let initialSnapshot = store.snapshot

        XCTAssertThrowsError(
            try store.installTrainingMarketplaceListing(
                preview,
                configuration: configuration(for: store.child.id)
            )
        ) { error in
            XCTAssertEqual(error as? TrainingMarketplaceInstallationError, .listingNotInstallable)
        }
        XCTAssertEqual(store.snapshot, initialSnapshot)
    }

    private func configuration(for childID: UUID) -> TrainingMarketplaceInstallConfiguration {
        TrainingMarketplaceInstallConfiguration(
            childID: childID,
            startDate: Date(),
            pace: .balanced,
            pointsOverride: nil,
            proofPreference: .followPlan
        )
    }

    private static let cloudCatalogJSON = #"""
    {
      "schemaVersion": 1,
      "generatedAt": "2026-07-10T12:00:00.000Z",
      "listings": [{
        "id": "cloud-learning-pack",
        "version": "2.0.0",
        "kind": "course_pack",
        "category": "learning",
        "title": "云端数学练习",
        "titleEnglish": "Cloud Math Practice",
        "summary": "适龄练习",
        "summaryEnglish": "Age-appropriate practice",
        "detail": "家长确认后安装。",
        "detailEnglish": "Install after parent confirmation.",
        "minAge": 6,
        "maxAge": 12,
        "durationDays": 7,
        "creator": {
          "id": "creator-public",
          "displayName": "公开创作者",
          "displayNameEnglish": "Public Creator",
          "bio": "公开简介",
          "bioEnglish": "Public bio",
          "isVerified": true,
          "rating": 4.8,
          "verifiedFamilyCount": 12
        },
        "availability": {"kind": "beta_access"},
        "rating": 4.8,
        "ratingCount": 12,
        "tags": ["数学"],
        "tagsEnglish": ["Math"],
        "planItems": [{"packType": "learning", "templateID": "learn-mental-math", "dayOffset": 0}],
        "reviews": [],
        "contentHash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "criticalUpdate": false
      }]
    }
    """#
}

final class MarketplaceCatalogURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var stub: (Int, String)?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let (status, body) = Self.stub,
              let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
