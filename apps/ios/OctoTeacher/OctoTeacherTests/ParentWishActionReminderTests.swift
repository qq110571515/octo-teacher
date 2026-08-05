import XCTest
@testable import OctoTeacher

final class ParentWishActionReminderTests: XCTestCase {
    func testNoReminderWhenNoWishNeedsGuardianAction() throws {
        let store = LocalFamilyStore()
        XCTAssertNil(ParentWishActionReminder.build(wishes: store.wishes))

        let wish = try XCTUnwrap(store.submitWish(title: "恐龙图鉴", childId: store.activeChildId))
        XCTAssertTrue(store.priceWish(wish.id, points: 30))
        // priced 状态轮到孩子攒分，不需要家长动手，首页不该提醒。
        XCTAssertNil(ParentWishActionReminder.build(wishes: store.wishes))
    }

    func testProposedWishSurfacesPricingReminderWithPointsExplanation() throws {
        let store = LocalFamilyStore()
        _ = try XCTUnwrap(store.submitWish(title: "滑板课", childId: store.activeChildId))

        let reminder = try XCTUnwrap(ParentWishActionReminder.build(wishes: store.wishes))
        XCTAssertEqual(reminder.pricingCount, 1)
        XCTAssertEqual(reminder.fulfillmentCount, 0)
        XCTAssertTrue(reminder.headline.contains("定成长积分价格"))
        XCTAssertTrue(reminder.detail.contains("还差多少成长积分"))
    }

    func testRedeemedWishSurfacesFulfillmentReminder() throws {
        let store = LocalFamilyStore()
        var child = store.child
        child.rewardBalanceMinutes = 120
        store.child = child

        let wish = try XCTUnwrap(store.submitWish(title: "恐龙图鉴", childId: store.activeChildId))
        XCTAssertTrue(store.priceWish(wish.id, points: 30))
        XCTAssertTrue(store.redeemWish(wish.id))

        let reminder = try XCTUnwrap(ParentWishActionReminder.build(wishes: store.wishes))
        XCTAssertEqual(reminder.pricingCount, 0)
        XCTAssertEqual(reminder.fulfillmentCount, 1)
        XCTAssertTrue(reminder.headline.contains("线下兑现"))
        XCTAssertTrue(reminder.detail.contains("已兑现"))
    }

    func testRejectedAndFulfilledWishesDoNotCount() throws {
        let store = LocalFamilyStore()
        var child = store.child
        child.rewardBalanceMinutes = 120
        store.child = child

        let rejected = try XCTUnwrap(store.submitWish(title: "买手机", childId: store.activeChildId))
        XCTAssertTrue(store.rejectWish(rejected.id))
        let fulfilled = try XCTUnwrap(store.submitWish(title: "恐龙图鉴", childId: store.activeChildId))
        XCTAssertTrue(store.priceWish(fulfilled.id, points: 30))
        XCTAssertTrue(store.redeemWish(fulfilled.id))
        XCTAssertTrue(store.markWishFulfilled(fulfilled.id))

        XCTAssertNil(ParentWishActionReminder.build(wishes: store.wishes))
    }
}
