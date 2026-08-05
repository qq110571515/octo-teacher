import Foundation

/// 培训市场的目录端口。首个版本由本地适配器供数，云端上线后只替换实现，
/// 家长端浏览、预览和安装流程不需要改写。
protocol TrainingMarketplaceCatalogProviding {
    func listings() -> [TrainingMarketplaceListing]
}

enum TrainingMarketplaceListingKind: String, Codable, Equatable {
    case libraryAsset = "library_asset"
    case singleContentPack = "single_content_pack"
    case coursePack = "course_pack"
    case mixedGrowthPack = "mixed_growth_pack"
    case officialProgram = "official_program"
}

enum TrainingMarketplaceCategory: String, CaseIterable, Identifiable, Codable {
    case all
    case routines
    case family
    case learning
    case outdoor
    case creativity
    case library

    var id: String { rawValue }

    func label(for language: AppInterfaceLanguage) -> String {
        switch self {
        case .all: return language.pick("全部", "All")
        case .routines: return language.pick("独立与作息", "Independence")
        case .family: return language.pick("家庭协作", "Family")
        case .learning: return language.pick("学习成长", "Learning")
        case .outdoor: return language.pick("户外运动", "Outdoor")
        case .creativity: return language.pick("创作表达", "Creativity")
        case .library: return language.pick("免费图书", "Free Books")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .routines: return "sunrise.fill"
        case .family: return "house.and.flag.fill"
        case .learning: return "book.closed.fill"
        case .outdoor: return "figure.run"
        case .creativity: return "paintpalette.fill"
        case .library: return "books.vertical.fill"
        }
    }
}

enum TrainingMarketplaceAvailability: Equatable {
    case free
    case betaAccess
    case pricePreview(String)
    case unavailable

    func label(for language: AppInterfaceLanguage) -> String {
        switch self {
        case .free:
            return language.pick("免费", "Free")
        case .betaAccess:
            return language.pick("内测可用", "Beta access")
        case .pricePreview(let price):
            return language.pick("价格预览 \(price)", "Price preview \(price)")
        case .unavailable:
            return language.pick("暂不可用", "Unavailable")
        }
    }

    var canInstallLocally: Bool {
        switch self {
        case .free, .betaAccess: return true
        case .pricePreview, .unavailable: return false
        }
    }
}

struct TrainingMarketplaceCreator: Equatable {
    var id: String
    var displayName: String
    var displayNameEnglish: String
    var bio: String
    var bioEnglish: String
    var isVerified: Bool
    var rating: Double
    var verifiedFamilyCount: Int

    func localizedName(_ language: AppInterfaceLanguage) -> String {
        language.pick(displayName, displayNameEnglish)
    }

    func localizedBio(_ language: AppInterfaceLanguage) -> String {
        language.pick(bio, bioEnglish)
    }
}

struct TrainingMarketplaceReview: Identifiable, Equatable {
    var id: String
    var title: String
    var titleEnglish: String
    var body: String
    var bodyEnglish: String
    var rating: Int
    var verifiedUse: Bool

    func localizedTitle(_ language: AppInterfaceLanguage) -> String {
        language.pick(title, titleEnglish)
    }

    func localizedBody(_ language: AppInterfaceLanguage) -> String {
        language.pick(body, bodyEnglish)
    }
}

struct TrainingMarketplacePlanItem: Equatable {
    var packType: PackType
    var templateID: String
    var dayOffset: Int

    func resolvedTemplate() -> PackTaskTemplate? {
        ParentPackTemplateLibrary.group(for: packType)?.templates.first { $0.id == templateID }
    }
}

enum TrainingMarketplaceResourceKind: String, Codable, Equatable {
    case book
    case video
    case creationTemplate = "creation_template"
}

enum MarketplaceResourceInstallBehavior: String, Codable, Equatable {
    case libraryReference = "library_reference"
    case videoReference = "video_reference"
    case creationTemplate = "creation_template"
}

struct TrainingMarketplaceResource: Identifiable, Codable, Equatable {
    var id: String
    var kind: TrainingMarketplaceResourceKind
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
    var installBehavior: MarketplaceResourceInstallBehavior

    func localizedTitle(_ language: AppInterfaceLanguage) -> String {
        language.pick(title, titleEnglish)
    }

    func localizedSummary(_ language: AppInterfaceLanguage) -> String {
        language.pick(summary, summaryEnglish)
    }
}

struct TrainingMarketplaceInstalledResource: Identifiable, Codable, Equatable {
    var id: String { resource.id }
    var listingID: String
    var listingVersion: String
    var installedAt: Date
    var resource: TrainingMarketplaceResource
    var sourceListingIDs: [String]?

    var resolvedSourceListingIDs: [String] {
        sourceListingIDs ?? [listingID]
    }
}

struct TrainingMarketplaceListing: Identifiable, Equatable {
    var id: String
    var version: String
    var kind: TrainingMarketplaceListingKind
    var category: TrainingMarketplaceCategory
    var title: String
    var titleEnglish: String
    var summary: String
    var summaryEnglish: String
    var detail: String
    var detailEnglish: String
    var minAge: Int
    var maxAge: Int
    var durationDays: Int
    var creator: TrainingMarketplaceCreator
    var availability: TrainingMarketplaceAvailability
    var rating: Double
    var ratingCount: Int
    var tags: [String]
    var tagsEnglish: [String]
    var planItems: [TrainingMarketplacePlanItem]
    var resources: [TrainingMarketplaceResource] = []
    var reviews: [TrainingMarketplaceReview]

    func localizedTitle(_ language: AppInterfaceLanguage) -> String {
        language.pick(title, titleEnglish)
    }

    func localizedSummary(_ language: AppInterfaceLanguage) -> String {
        language.pick(summary, summaryEnglish)
    }

    func localizedDetail(_ language: AppInterfaceLanguage) -> String {
        language.pick(detail, detailEnglish)
    }

    func localizedTags(_ language: AppInterfaceLanguage) -> [String] {
        language == .english ? tagsEnglish : tags
    }

    var isLibraryEntry: Bool { kind == .libraryAsset && resources.isEmpty }
    var isResourceCollection: Bool { !resources.isEmpty }
}

enum TrainingMarketplaceInstallPace: String, CaseIterable, Identifiable, Codable {
    case gentle
    case balanced
    case compact

    var id: String { rawValue }

    func label(for language: AppInterfaceLanguage) -> String {
        switch self {
        case .gentle: return language.pick("舒缓：每天 1 项", "Gentle: 1 per day")
        case .balanced: return language.pick("按创作者计划", "Creator schedule")
        case .compact: return language.pick("紧凑：每天最多 2 项", "Compact: up to 2 per day")
        }
    }

    func dayOffset(catalogOffset: Int, index: Int) -> Int {
        switch self {
        case .gentle: return index
        case .balanced: return catalogOffset
        case .compact: return index / 2
        }
    }
}

enum TrainingMarketplaceProofPreference: String, CaseIterable, Identifiable, Codable {
    case followPlan
    case text
    case photo

    var id: String { rawValue }

    func label(for language: AppInterfaceLanguage) -> String {
        switch self {
        case .followPlan: return language.pick("跟随任务设计", "Follow task design")
        case .text: return language.pick("统一写一句话/语音说明", "Use a short response")
        case .photo: return language.pick("统一拍照证明", "Use photo proof")
        }
    }

    func resolve(default proof: ProofKind) -> ProofKind {
        switch self {
        case .followPlan: return proof
        case .text: return .text
        case .photo: return .photo
        }
    }
}

struct TrainingMarketplaceInstallConfiguration: Equatable {
    var childID: UUID
    var startDate: Date
    var pace: TrainingMarketplaceInstallPace
    var pointsOverride: Int?
    var proofPreference: TrainingMarketplaceProofPreference
}

struct TrainingMarketplaceInstallationRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var listingID: String
    var listingVersion: String
    var childID: UUID
    var installedAt: Date
    var startDate: Date
    var pace: TrainingMarketplaceInstallPace
    var assignmentIDs: [UUID]
    var installedResourceIDs: [String]? = nil
}

enum TrainingMarketplaceInstallationError: Error, Equatable {
    case childNotFound
    case ageMismatch
    case alreadyInstalled
    case listingNotInstallable
    case emptyPlan
    case invalidPlanItem(String)

    func message(for language: AppInterfaceLanguage) -> String {
        switch self {
        case .childNotFound:
            return language.pick("没有找到要安装给的孩子。", "The selected child was not found.")
        case .ageMismatch:
            return language.pick("孩子年龄不在这个内容的建议范围内。", "The child is outside this listing's recommended age range.")
        case .alreadyInstalled:
            return language.pick("这个版本已经安装给该孩子。", "This version is already installed for this child.")
        case .listingNotInstallable:
            return language.pick("这个内容目前只能预览，尚不能安装。", "This listing is preview-only and cannot be installed yet.")
        case .emptyPlan:
            return language.pick("这个包没有可安装的任务或内容资源。", "This pack has no installable tasks or content resources.")
        case .invalidPlanItem:
            return language.pick("任务包内容不完整，已停止安装。", "The pack is incomplete, so installation was stopped.")
        }
    }
}

private struct TrainingMarketplaceListingSeed {
    var id: String
    var category: TrainingMarketplaceCategory
    var title: String
    var titleEnglish: String
    var summary: String
    var summaryEnglish: String
    var detail: String
    var detailEnglish: String
    var ages: ClosedRange<Int>
    var duration: Int
    var items: [TrainingMarketplacePlanItem]
    var tags: [String]
    var tagsEnglish: [String]
}

/// 不联网、不支付的本地内测目录。条目使用稳定 ID 与版本，后续云端响应可直接映射成同一模型。
struct LocalTrainingMarketplaceCatalogProvider: TrainingMarketplaceCatalogProviding {
    func listings() -> [TrainingMarketplaceListing] {
        [
            officialLibrary,
            independenceWeek,
            familyHelperWeek,
            outdoorReset,
            creativeWeekend,
            wholeFamilyStarter,
            expertPreview
        ]
    }

    private var officialCreator: TrainingMarketplaceCreator {
        TrainingMarketplaceCreator(
            id: "creator-octoteacher-official",
            displayName: "章鱼老师 官方",
            displayNameEnglish: "Octo Teacher Official",
            bio: "围绕家庭真实使用路径设计，并经过儿童安全与任务闭环检查。",
            bioEnglish: "Designed around real family routines with child-safety and workflow checks.",
            isVerified: true,
            rating: 4.9,
            verifiedFamilyCount: 38
        )
    }

    private var educatorCreator: TrainingMarketplaceCreator {
        TrainingMarketplaceCreator(
            id: "creator-family-rhythm-lab",
            displayName: "家庭节律实验室",
            displayNameEnglish: "Family Rhythm Lab",
            bio: "专注把家庭目标拆成孩子能够开始的小步骤。",
            bioEnglish: "Turns family goals into small steps children can actually start.",
            isVerified: true,
            rating: 4.7,
            verifiedFamilyCount: 24
        )
    }

    private var sampleReviews: [TrainingMarketplaceReview] {
        [
            TrainingMarketplaceReview(
                id: "review-pace",
                title: "节奏清楚",
                titleEnglish: "Clear pace",
                body: "安装前能看到每天做什么，积分也能先调整。",
                bodyEnglish: "We could preview each day and adjust points before installing.",
                rating: 5,
                verifiedUse: true
            ),
            TrainingMarketplaceReview(
                id: "review-start",
                title: "孩子知道从哪里开始",
                titleEnglish: "Easy to start",
                body: "没有一下塞很多要求，第一天就能照着做。",
                bodyEnglish: "It did not dump too many demands on day one.",
                rating: 4,
                verifiedUse: true
            )
        ]
    }

    private var officialLibrary: TrainingMarketplaceListing {
        TrainingMarketplaceListing(
            id: "octoteacher-free-library",
            version: "1.0.0",
            kind: .libraryAsset,
            category: .library,
            title: "章鱼老师 免费图书库",
            titleEnglish: "Octo Teacher Free Library",
            summary: "先挑选适龄图书，再由家长决定是否下载、导入和布置阅读。",
            summaryEnglish: "Choose age-appropriate books, then decide whether to download, import, and assign reading.",
            detail: "图书与任务包分开管理。浏览不会自动下载，也不会自动给孩子布置任务。",
            detailEnglish: "Books stay separate from task packs. Browsing never downloads or assigns anything automatically.",
            minAge: 3,
            maxAge: 18,
            durationDays: 0,
            creator: officialCreator,
            availability: .free,
            rating: 4.9,
            ratingCount: 38,
            tags: ["免费", "家长确认", "独立书库"],
            tagsEnglish: ["Free", "Parent approved", "Separate library"],
            planItems: [],
            reviews: sampleReviews
        )
    }

    private var independenceWeek: TrainingMarketplaceListing {
        listing(.init(
            id: "independence-week",
            category: .routines,
            title: "我的事情我来做",
            titleEnglish: "I Can Do It Myself",
            summary: "用 7 天练习洗漱、穿衣、书包、房间和睡前准备。",
            summaryEnglish: "A 7-day practice for washing up, dressing, packing, tidying, and bedtime.",
            detail: "每天只推进一个清晰动作，家长仍是最后审核人；任务不会直接兑换设备时间。",
            detailEnglish: "One clear action each day. Parents keep final approval, and tasks never unlock devices directly.",
            ages: 5...12,
            duration: 7,
            items: [
                item(.basicHabits, "habit-wash-up", 0),
                item(.basicHabits, "habit-dress-self", 1),
                item(.basicHabits, "habit-pack-bag", 2),
                item(.basicHabits, "habit-clothes-away", 3),
                item(.basicHabits, "habit-tidy-room", 4),
                item(.basicHabits, "habit-morning-ready", 5),
                item(.basicHabits, "habit-early-sleep", 6)
            ],
            tags: ["独立", "作息", "低压力"],
            tagsEnglish: ["Independence", "Routine", "Low pressure"]
        ))
    }

    private var familyHelperWeek: TrainingMarketplaceListing {
        listing(.init(
            id: "family-helper-week",
            category: .family,
            title: "家庭小帮手一周",
            titleEnglish: "Family Helper Week",
            summary: "从餐桌、衣物、垃圾和植物开始练习家庭协作。",
            summaryEnglish: "Practice family teamwork through tables, laundry, trash, and plant care.",
            detail: "每件事都来自现有家务包，证明方式和成长积分可在安装前统一调整。",
            detailEnglish: "Every task uses the existing chores workflow; proof and points can be adjusted before installation.",
            ages: 6...14,
            duration: 7,
            items: [
                item(.chores, "chore-set-table", 0),
                item(.chores, "chore-clear-table", 1),
                item(.chores, "chore-sort-laundry", 2),
                item(.chores, "chore-trash", 3),
                item(.chores, "chore-wipe-surface", 4),
                item(.chores, "chore-pet-care", 5)
            ],
            tags: ["家务", "协作", "一周"],
            tagsEnglish: ["Chores", "Teamwork", "One week"]
        ))
    }

    private var outdoorReset: TrainingMarketplaceListing {
        listing(.init(
            id: "outdoor-reset",
            category: .outdoor,
            title: "放下手机去户外",
            titleEnglish: "Put the Phone Down and Go Outside",
            summary: "5 次安全户外活动，把屏幕后的空档变成真实体验。",
            summaryEnglish: "Five safe outdoor activities that turn screen breaks into real experiences.",
            detail: "骑行、球类和公园活动保留大人陪同标记；安装不会自动操作 Screen Time。",
            detailEnglish: "Bike, ball, and park activities keep adult-supervision flags. Installation never changes Screen Time automatically.",
            ages: 6...15,
            duration: 7,
            items: [
                item(.outdoorSports, "outdoor-park-walk", 0),
                item(.outdoorSports, "outdoor-jump-rope", 1),
                item(.outdoorSports, "outdoor-ball-play", 3),
                item(.outdoorSports, "outdoor-nature-search", 5),
                item(.outdoorSports, "outdoor-family-game", 6)
            ],
            tags: ["户外", "运动", "少屏幕"],
            tagsEnglish: ["Outdoor", "Exercise", "Less screen"]
        ))
    }

    private var creativeWeekend: TrainingMarketplaceListing {
        listing(.init(
            id: "creative-weekend",
            category: .creativity,
            title: "会讲故事的创作周末",
            titleEnglish: "A Creative Story Weekend",
            summary: "画画、手工和故事表达组成一个轻量创作项目。",
            summaryEnglish: "A small creative project combining drawing, crafts, and storytelling.",
            detail: "作品进入现有创作广场，AI 小伙伴可以初评，家长仍负责最终确认。",
            detailEnglish: "Work appears in the existing Creation Plaza. The AI companion may give a first review, while parents make the final decision.",
            ages: 5...14,
            duration: 3,
            items: [
                item(.creativeWorks, "create-theme-drawing", 0),
                item(.creativeWorks, "create-handcraft", 1),
                item(.creativeWorks, "create-journal", 2)
            ],
            tags: ["绘画", "手工", "表达"],
            tagsEnglish: ["Drawing", "Crafts", "Expression"]
        ))
    }

    private var wholeFamilyStarter: TrainingMarketplaceListing {
        listing(.init(
            id: "whole-family-starter",
            category: .learning,
            title: "家庭成长启动计划",
            titleEnglish: "Family Growth Starter",
            summary: "把独立、家务、学习、户外、创作和亲情任务放进同一周。",
            summaryEnglish: "A one-week mix of independence, chores, learning, outdoor play, creativity, and family care.",
            detail: "这是混合成长包示范：每个任务仍回到原来的业务模块，市场只负责选择、预览和安装。",
            detailEnglish: "This mixed pack sends every task back to its original module. The marketplace only handles discovery, preview, and installation.",
            ages: 7...13,
            duration: 7,
            items: [
                item(.basicHabits, "habit-morning-ready", 0),
                item(.chores, "chore-set-table", 0),
                item(.learning, "learn-mental-math", 1),
                item(.outdoorSports, "outdoor-jump-rope", 2),
                item(.creativeWorks, "create-theme-drawing", 3),
                item(.familyResponsibility, "family-call-grandparents", 4),
                item(.learning, "learn-new-words", 5),
                item(.basicHabits, "habit-early-sleep", 6)
            ],
            tags: ["综合", "一周", "跨模块"],
            tagsEnglish: ["Mixed", "One week", "Cross-module"]
        ))
    }

    private var expertPreview: TrainingMarketplaceListing {
        var value = listing(.init(
            id: "expert-literacy-preview",
            category: .learning,
            title: "幼儿识字亲子课（预览）",
            titleEnglish: "Early Literacy Family Course (Preview)",
            summary: "展示未来创作者课程的简介、价格与适龄信息，当前不开放购买。",
            summaryEnglish: "A preview of future creator courses, including age guidance and price. Purchasing is not available.",
            detail: "该条目只验证产品展示，不创建订单、不写权益、不布置任务。",
            detailEnglish: "This listing only validates product presentation. It creates no order, entitlement, or task.",
            ages: 3...7,
            duration: 14,
            items: [],
            tags: ["价格预览", "尚未开放"],
            tagsEnglish: ["Price preview", "Not yet available"]
        ))
        value.creator = educatorCreator
        value.availability = .pricePreview("$4.99")
        value.rating = educatorCreator.rating
        value.ratingCount = educatorCreator.verifiedFamilyCount
        return value
    }

}

private extension LocalTrainingMarketplaceCatalogProvider {
    func listing(_ seed: TrainingMarketplaceListingSeed) -> TrainingMarketplaceListing {
        TrainingMarketplaceListing(
            id: seed.id,
            version: "1.0.0",
            kind: seed.items.count > 6 ? .mixedGrowthPack : .coursePack,
            category: seed.category,
            title: seed.title,
            titleEnglish: seed.titleEnglish,
            summary: seed.summary,
            summaryEnglish: seed.summaryEnglish,
            detail: seed.detail,
            detailEnglish: seed.detailEnglish,
            minAge: seed.ages.lowerBound,
            maxAge: seed.ages.upperBound,
            durationDays: seed.duration,
            creator: officialCreator,
            availability: .betaAccess,
            rating: officialCreator.rating,
            ratingCount: officialCreator.verifiedFamilyCount,
            tags: seed.tags,
            tagsEnglish: seed.tagsEnglish,
            planItems: seed.items,
            reviews: sampleReviews
        )
    }

    private func item(_ packType: PackType, _ templateID: String, _ dayOffset: Int) -> TrainingMarketplacePlanItem {
        TrainingMarketplacePlanItem(packType: packType, templateID: templateID, dayOffset: dayOffset)
    }
}

extension LocalFamilyStore {
    func marketplaceInstallation(
        listingID: String,
        childID: UUID
    ) -> TrainingMarketplaceInstallationRecord? {
        trainingMarketplaceInstallations.first {
            $0.listingID == listingID && $0.childID == childID
        }
    }

    /// 安装前先完整解析所有模板；任何一项缺失都会整体停止，不留下半包任务。
    @discardableResult
    func installTrainingMarketplaceListing(
        _ listing: TrainingMarketplaceListing,
        configuration: TrainingMarketplaceInstallConfiguration
    ) throws -> TrainingMarketplaceInstallationRecord {
        guard let targetChild = children.first(where: { $0.id == configuration.childID }) else {
            throw TrainingMarketplaceInstallationError.childNotFound
        }
        guard listing.availability.canInstallLocally, !listing.isLibraryEntry else {
            throw TrainingMarketplaceInstallationError.listingNotInstallable
        }
        guard (listing.minAge...listing.maxAge).contains(targetChild.age) else {
            throw TrainingMarketplaceInstallationError.ageMismatch
        }
        guard !listing.planItems.isEmpty || !listing.resources.isEmpty else {
            throw TrainingMarketplaceInstallationError.emptyPlan
        }
        guard marketplaceInstallation(
            listingID: listing.id,
            childID: configuration.childID
        ) == nil else {
            throw TrainingMarketplaceInstallationError.alreadyInstalled
        }

        let resolved: [(TrainingMarketplacePlanItem, PackTaskTemplate)] = try listing.planItems.map { item in
            guard let template = item.resolvedTemplate() else {
                throw TrainingMarketplaceInstallationError.invalidPlanItem(item.templateID)
            }
            return (item, template)
        }

        let normalizedStart = Calendar.current.startOfDay(for: configuration.startDate)
        let (newAssignments, newSteps) = makeMarketplaceTasks(
            resolved: resolved,
            configuration: configuration,
            normalizedStart: normalizedStart
        )

        let record = TrainingMarketplaceInstallationRecord(
            id: UUID(),
            listingID: listing.id,
            listingVersion: listing.version,
            childID: configuration.childID,
            installedAt: Date(),
            startDate: normalizedStart,
            pace: configuration.pace,
            assignmentIDs: newAssignments.map(\.id),
            installedResourceIDs: listing.resources.map(\.id)
        )

        assignments.append(contentsOf: newAssignments)
        growthPack.steps.append(contentsOf: newSteps)
        installMarketplaceResources(listing, installedAt: record.installedAt)
        trainingMarketplaceInstallations.append(record)
        events.insert(
            FamilyEvent(
                id: UUID(),
                kind: .taskAssigned,
                title: "已安装：\(listing.title)",
                detail: "\(currentGuardianName)给\(childName(for: configuration.childID))安装了 \(newAssignments.count) 个任务，版本 \(listing.version)。",
                minutes: nil,
                createdAt: Date()
            ),
            at: 0
        )
        persist()
        return record
    }

    private func makeMarketplaceTasks(
        resolved: [(TrainingMarketplacePlanItem, PackTaskTemplate)],
        configuration: TrainingMarketplaceInstallConfiguration,
        normalizedStart: Date
    ) -> ([TaskAssignment], [GrowthPackStep]) {
        let calendar = Calendar.current
        let initialOrder = growthPack.steps.map(\.order).max() ?? 0
        var assignments: [TaskAssignment] = []
        var steps: [GrowthPackStep] = []
        for (index, pair) in resolved.enumerated() {
            let (item, template) = pair
            let offset = configuration.pace.dayOffset(catalogOffset: item.dayOffset, index: index)
            let date = calendar.date(byAdding: .day, value: offset, to: normalizedStart) ?? normalizedStart
            let instructions = marketplaceInstructions(for: template)
            let task = marketplaceTask(item: item, template: template, configuration: configuration, instructions: instructions)
            let assignment = TaskAssignment(
                id: UUID(), childId: configuration.childID, task: task, date: date, status: .open, proof: .empty
            )
            assignments.append(assignment)
            steps.append(GrowthPackStep(
                id: UUID(), order: initialOrder + index + 1, title: task.title, detail: task.instructions,
                assignmentId: assignment.id, rewardMinutes: task.rewardMinutes
            ))
        }
        return (assignments, steps)
    }

    private func marketplaceTask(
        item: TrainingMarketplacePlanItem,
        template: PackTaskTemplate,
        configuration: TrainingMarketplaceInstallConfiguration,
        instructions: String
    ) -> TaskTemplate {
        let englishTitle = BuiltInTaskLocalization.englishTitle(for: template.title) ?? template.title
        let englishInstructions = BuiltInTaskLocalization.englishInstructions(for: template.instructions) ?? instructions
        return TaskTemplate(
            id: UUID(), title: template.title, category: template.category, difficulty: .easy,
            rewardMinutes: configuration.pointsOverride ?? template.suggestedRewardMinutes,
            instructions: instructions,
            requiredProof: configuration.proofPreference.resolve(default: template.requiredProof),
            adultSupervisionRequired: template.adultSupervisionRequired ? true : nil,
            reading: template.reading, creative: template.creative, packType: item.packType,
            localizedContent: [
                TaskLocalizedContent(language: .chinese, title: template.title, instructions: instructions),
                TaskLocalizedContent(language: .english, title: englishTitle, instructions: englishInstructions)
            ]
        )
    }

    private func installMarketplaceResources(_ listing: TrainingMarketplaceListing, installedAt: Date) {
        for resource in listing.resources {
            if let index = installedMarketplaceResources.firstIndex(where: { $0.id == resource.id }) {
                var existing = installedMarketplaceResources[index]
                var sourceListingIDs = existing.resolvedSourceListingIDs
                if !sourceListingIDs.contains(listing.id) {
                    sourceListingIDs.append(listing.id)
                }
                existing.listingID = listing.id
                existing.listingVersion = listing.version
                existing.installedAt = installedAt
                existing.resource = resource
                existing.sourceListingIDs = sourceListingIDs
                installedMarketplaceResources[index] = existing
            } else {
                installedMarketplaceResources.append(
                    TrainingMarketplaceInstalledResource(
                        listingID: listing.id,
                        listingVersion: listing.version,
                        installedAt: installedAt,
                        resource: resource,
                        sourceListingIDs: [listing.id]
                    )
                )
            }
        }
    }

    private func marketplaceInstructions(for template: PackTaskTemplate) -> String {
        var lines: [String] = []
        if let expectedMinutes = template.expectedMinutes {
            lines.append("建议用时：\(expectedMinutes) 分钟。")
        }
        let text = template.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { lines.append(text) }
        return lines.joined(separator: "\n")
    }
}
