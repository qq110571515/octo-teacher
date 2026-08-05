import XCTest
@testable import OctoTeacher

/// 家庭成长荣誉卡片视图（`family-growth-feed-mobile-contract` 在 iOS 的本地落地）的确定性单元测试。
///
/// 覆盖：脱敏 publicRef 稳定且不含原文、孩子/家长可见全量、亲友只见已通过且对亲友开放、
/// 私密/待审核/已撤回/已阻断对亲友不可见、正式荣誉只算已通过、已阻断只给脱敏说明、
/// 支持性文案与下一步恒存在、可见范围计数、视角概览待处理计数边界，以及 fixture 不泄露敏感标识。
final class FamilyGrowthAchievementTests: XCTestCase {

    private let store = FamilyGrowthAchievementStore()

    // MARK: - 脱敏

    func testPublicRefStableAndPrefixed() {
        let a = FamilyGrowthRedaction.publicRef(prefix: "card", source: "honor-reading-star")
        let b = FamilyGrowthRedaction.publicRef(prefix: "card", source: "honor-reading-star")
        XCTAssertEqual(a, b, "同一 seed 必须产出稳定引用")
        XCTAssertTrue(a.hasPrefix("card:"))
        XCTAssertFalse(a.contains("honor-reading-star"), "脱敏引用不得包含原始 seed")
    }

    func testPublicRefDiffersBySeed() {
        let a = FamilyGrowthRedaction.publicRef(prefix: "card", source: "seed-a")
        let b = FamilyGrowthRedaction.publicRef(prefix: "card", source: "seed-b")
        XCTAssertNotEqual(a, b)
    }

    func testCardPublicRefDoesNotLeakInternalSeed() {
        for card in store.cards {
            XCTAssertFalse(card.publicRef.contains(card.internalSeed),
                           "卡片公开引用不得暴露 internalSeed")
            XCTAssertTrue(card.publicRef.hasPrefix("card:"))
        }
    }

    // MARK: - 角色可见性

    func testRelativeOnlySeesPublishedFamilyOrAllowedRelatives() {
        let cards = store.summary(for: .relative).cards
        XCTAssertFalse(cards.isEmpty, "亲友应能看到部分已通过且开放的内容")
        for card in cards {
            XCTAssertEqual(card.lifecycle, .published, "亲友只能看到已通过内容")
            XCTAssertTrue(
                card.visibility == .family || (card.visibility == .relatives && card.allowsRelative),
                "亲友只能看到家庭可见或被授权的亲友可见内容"
            )
            XCTAssertNotEqual(card.visibility, .privateOnly)
            XCTAssertNotEqual(card.visibility, .publicShare)
        }
    }

    func testRelativeNeverSeesPendingWithdrawnOrBlocked() {
        let cards = store.summary(for: .relative).cards
        XCTAssertTrue(cards.allSatisfy { $0.isFormalHonor },
                      "亲友视角不得出现任何非正式荣誉（待审核/已撤回/已阻断）")
    }

    func testRelativeNeverSeesPrivateContent() {
        let cards = store.summary(for: .relative).cards
        XCTAssertFalse(cards.contains { $0.visibility == .privateOnly })
    }

    func testHouseholdSeesEverythingIncludingPendingAndBlocked() {
        let childCards = store.summary(for: .child).cards
        let guardianCards = store.summary(for: .guardian).cards
        XCTAssertEqual(childCards.count, store.cards.count, "孩子应可见全量卡片")
        XCTAssertEqual(guardianCards.count, store.cards.count, "家长应可见全量卡片")
        XCTAssertTrue(guardianCards.contains { $0.lifecycle == .pending })
        XCTAssertTrue(guardianCards.contains { $0.lifecycle == .withdrawn })
        XCTAssertTrue(guardianCards.contains { $0.lifecycle == .blocked })
        XCTAssertTrue(guardianCards.contains { $0.visibility == .privateOnly })
    }

    func testRelativeSeesFewerThanHousehold() {
        let relative = store.summary(for: .relative).cards.count
        let household = store.summary(for: .guardian).cards.count
        XCTAssertLessThan(relative, household, "亲友可见集合必须严格小于家庭内部")
    }

    // MARK: - 正式荣誉与状态

    func testFormalHonorOnlyPublished() {
        for card in store.cards where !card.isFormalHonor {
            XCTAssertNotEqual(card.lifecycle, .published)
        }
        for card in store.cards where card.lifecycle == .published {
            XCTAssertTrue(card.isFormalHonor)
        }
    }

    func testBlockedSummaryNeverLeaksOriginalText() {
        guard let blocked = store.cards.first(where: { $0.lifecycle == .blocked }) else {
            return XCTFail("应存在已阻断 fixture")
        }
        let shown = blocked.displaySummary(for: .guardian)
        XCTAssertTrue(shown.contains("已阻断"), "已阻断内容应展示脱敏说明")
        XCTAssertNotEqual(shown, blocked.summary, "已阻断内容不得直接展示原 summary")
    }

    func testStatusNoteOnlyForHouseholdAndNonPublished() {
        for card in store.cards {
            // 亲友永远拿不到状态说明。
            XCTAssertNil(card.statusNote(for: .relative))
            if card.lifecycle == .published {
                XCTAssertNil(card.statusNote(for: .guardian))
            } else {
                XCTAssertNotNil(card.statusNote(for: .guardian))
            }
        }
    }

    // MARK: - 支持性文案 / 下一步 / 脱敏内容

    func testEverySupportiveCopyAndNextStepPresent() {
        for card in store.cards {
            XCTAssertFalse(card.supportiveCopy.trimmingCharacters(in: .whitespaces).isEmpty,
                           "每张卡片都应有支持性文案")
            XCTAssertFalse(card.nextStep.trimmingCharacters(in: .whitespaces).isEmpty,
                           "每张卡片都应有下一步建议")
        }
    }

    func testFixturesDoNotLeakSensitiveMarkers() {
        let blocked: [String] = ["Bearer ", "api_key", "api-key", "device-token",
                                 "192.168", "10.0.", ".local", "file://", "C:\\", "sk-"]
        for card in store.cards {
            let haystack = [card.title, card.summary, card.supportiveCopy, card.nextStep,
                            card.occurredLabel, card.tags.joined(separator: " ")]
                .joined(separator: " ")
            for marker in blocked {
                XCTAssertFalse(haystack.contains(marker),
                               "fixture 不得包含敏感标识：\(marker)")
            }
        }
    }

    // MARK: - 汇总计数

    func testVisibilityCountsMatchVisibleCards() {
        let summary = store.summary(for: .guardian)
        let total = summary.visibilityCounts.values.reduce(0, +)
        XCTAssertEqual(total, summary.cards.count)
    }

    func testPendingCountIsZeroForRelative() {
        let summary = store.summary(for: .relative)
        XCTAssertEqual(summary.pendingCount, 0, "亲友视角不应出现待处理内容")
        XCTAssertEqual(summary.formalHonorCount, summary.cards.count)
    }

    func testGrowthCardOverallWithinBounds() {
        guard let card = store.cards.first(where: { $0.kind == .growthCard }) else {
            return XCTFail("应存在成长球星卡 fixture")
        }
        guard let overall = card.overallRating else {
            return XCTFail("成长球星卡应有综合评分")
        }
        XCTAssertGreaterThanOrEqual(overall, 1)
        XCTAssertLessThanOrEqual(overall, 99)
    }

    func testStableOrderingIsDeterministic() {
        let first = store.summary(for: .guardian).cards.map(\.publicRef)
        let second = store.summary(for: .guardian).cards.map(\.publicRef)
        XCTAssertEqual(first, second, "排序必须确定（无随机/无时钟）")
    }
}
