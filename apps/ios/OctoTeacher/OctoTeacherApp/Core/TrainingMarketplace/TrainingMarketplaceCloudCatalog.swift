import Foundation

protocol TrainingMarketplaceCloudCatalogLoading: Sendable {
    func loadListings() async throws -> [TrainingMarketplaceListing]
}

enum TrainingMarketplaceCloudCatalogError: Error, Equatable {
    case invalidResponse
    case unsupportedSchema
    case invalidCatalog
}

struct CloudTrainingMarketplaceCatalogProvider: TrainingMarketplaceCloudCatalogLoading {
    static let productionEndpoint = URL(
        string: "https://api.octoteacher.com/api/v1/marketplace/listings"
    )!

    var endpoint: URL
    var session: URLSession

    init(endpoint: URL = Self.productionEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func loadListings() async throws -> [TrainingMarketplaceListing] {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TrainingMarketplaceCloudCatalogError.invalidResponse
        }
        let payload = try JSONDecoder().decode(TrainingMarketplaceCatalogPayload.self, from: data)
        guard payload.schemaVersion == 1 else {
            throw TrainingMarketplaceCloudCatalogError.unsupportedSchema
        }
        let listings = payload.listings.prefix(100).compactMap(\.resolvedListing)
        guard payload.listings.isEmpty || !listings.isEmpty else {
            throw TrainingMarketplaceCloudCatalogError.invalidCatalog
        }
        return listings
    }
}

private struct TrainingMarketplaceCatalogPayload: Decodable {
    var schemaVersion: Int
    var listings: [TrainingMarketplaceListingPayload]
}

private struct TrainingMarketplaceListingPayload: Decodable {
    struct Creator: Decodable {
        var id: String
        var displayName: String
        var displayNameEnglish: String
        var bio: String
        var bioEnglish: String
        var isVerified: Bool
        var rating: Double
        var verifiedFamilyCount: Int
    }

    struct Availability: Decodable {
        var kind: String
        var pricePreview: String?
    }

    struct PlanItem: Decodable {
        var packType: String
        var templateID: String
        var dayOffset: Int
    }

    struct Resource: Decodable {
        var id: String
        var kind: String
        var title: String
        var titleEnglish: String
        var summary: String
        var summaryEnglish: String
        var sourceName: String
        var sourceURL: String
        var thumbnailURL: String?
        var languageCode: String
        var minAge: Int
        var maxAge: Int
        var durationSeconds: Int
        var categories: [String]
        var categoriesEnglish: [String]
        var installBehavior: String
    }

    struct Review: Decodable {
        var id: String
        var title: String
        var titleEnglish: String
        var body: String
        var bodyEnglish: String
        var rating: Int
        var verifiedUse: Bool
    }

    var id: String
    var version: String
    var kind: String
    var category: String
    var title: String
    var titleEnglish: String
    var summary: String
    var summaryEnglish: String
    var detail: String
    var detailEnglish: String
    var minAge: Int
    var maxAge: Int
    var durationDays: Int
    var creator: Creator
    var availability: Availability
    var rating: Double
    var ratingCount: Int
    var tags: [String]
    var tagsEnglish: [String]
    var planItems: [PlanItem]
    var resources: [Resource]?
    var reviews: [Review]
    var contentHash: String
    var criticalUpdate: Bool

    var resolvedListing: TrainingMarketplaceListing? {
        guard !id.isEmpty,
              !version.isEmpty,
              !title.isEmpty,
              !titleEnglish.isEmpty,
              contentHash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              let resolvedKind = TrainingMarketplaceListingKind(rawValue: kind),
              let resolvedCategory = TrainingMarketplaceCategory(rawValue: category),
              (2...18).contains(minAge),
              (minAge...18).contains(maxAge),
              (0...365).contains(durationDays),
              let resolvedAvailability else { return nil }

        let resolvedItems = planItems.prefix(100).compactMap { item -> TrainingMarketplacePlanItem? in
            guard let packType = PackType(rawValue: item.packType),
                  !item.templateID.isEmpty,
                  (0...365).contains(item.dayOffset) else { return nil }
            return TrainingMarketplacePlanItem(
                packType: packType,
                templateID: String(item.templateID.prefix(120)),
                dayOffset: item.dayOffset
            )
        }
        guard resolvedItems.count == planItems.count else { return nil }
        let resolvedResources = (resources ?? []).prefix(500).compactMap { item -> TrainingMarketplaceResource? in
            guard let kind = TrainingMarketplaceResourceKind(rawValue: item.kind),
                  let behavior = MarketplaceResourceInstallBehavior(rawValue: item.installBehavior),
                  !item.id.isEmpty,
                  URL(string: item.sourceURL) != nil,
                  (2...18).contains(item.minAge),
                  (item.minAge...18).contains(item.maxAge),
                  item.durationSeconds >= 0 else { return nil }
            return TrainingMarketplaceResource(
                id: String(item.id.prefix(120)),
                kind: kind,
                title: String(item.title.prefix(180)),
                titleEnglish: String(item.titleEnglish.prefix(180)),
                summary: String(item.summary.prefix(1_000)),
                summaryEnglish: String(item.summaryEnglish.prefix(1_000)),
                sourceName: String(item.sourceName.prefix(160)),
                sourceURL: String(item.sourceURL.prefix(2_000)),
                thumbnailURL: item.thumbnailURL.map { String($0.prefix(2_000)) },
                languageCode: String(item.languageCode.prefix(20)),
                minAge: item.minAge,
                maxAge: item.maxAge,
                durationSeconds: min(86_400, item.durationSeconds),
                categories: item.categories.prefix(12).map { String($0.prefix(80)) },
                categoriesEnglish: item.categoriesEnglish.prefix(12).map { String($0.prefix(80)) },
                installBehavior: behavior
            )
        }
        guard resolvedResources.count == (resources ?? []).count else { return nil }
        if resolvedAvailability.canInstallLocally,
           resolvedKind != .libraryAsset,
           resolvedItems.isEmpty,
           resolvedResources.isEmpty { return nil }

        return TrainingMarketplaceListing(
            id: String(id.prefix(120)),
            version: String(version.prefix(40)),
            kind: resolvedKind,
            category: resolvedCategory,
            title: String(title.prefix(120)),
            titleEnglish: String(titleEnglish.prefix(120)),
            summary: String(summary.prefix(360)),
            summaryEnglish: String(summaryEnglish.prefix(360)),
            detail: String(detail.prefix(2_000)),
            detailEnglish: String(detailEnglish.prefix(2_000)),
            minAge: minAge,
            maxAge: maxAge,
            durationDays: durationDays,
            creator: TrainingMarketplaceCreator(
                id: String(creator.id.prefix(120)),
                displayName: String(creator.displayName.prefix(120)),
                displayNameEnglish: String(creator.displayNameEnglish.prefix(120)),
                bio: String(creator.bio.prefix(500)),
                bioEnglish: String(creator.bioEnglish.prefix(500)),
                isVerified: creator.isVerified,
                rating: min(5, max(0, creator.rating)),
                verifiedFamilyCount: min(1_000_000, max(0, creator.verifiedFamilyCount))
            ),
            availability: resolvedAvailability,
            rating: min(5, max(0, rating)),
            ratingCount: min(1_000_000, max(0, ratingCount)),
            tags: tags.prefix(20).map { String($0.prefix(60)) },
            tagsEnglish: tagsEnglish.prefix(20).map { String($0.prefix(60)) },
            planItems: resolvedItems,
            resources: resolvedResources,
            reviews: reviews.prefix(20).map {
                TrainingMarketplaceReview(
                    id: String($0.id.prefix(120)),
                    title: String($0.title.prefix(120)),
                    titleEnglish: String($0.titleEnglish.prefix(120)),
                    body: String($0.body.prefix(800)),
                    bodyEnglish: String($0.bodyEnglish.prefix(800)),
                    rating: min(5, max(1, $0.rating)),
                    verifiedUse: $0.verifiedUse
                )
            }
        )
    }

    private var resolvedAvailability: TrainingMarketplaceAvailability? {
        switch availability.kind {
        case "free": return .free
        case "beta_access": return .betaAccess
        case "price_preview":
            guard let price = availability.pricePreview, !price.isEmpty else { return nil }
            return .pricePreview(String(price.prefix(40)))
        case "unavailable": return .unavailable
        default: return nil
        }
    }
}
