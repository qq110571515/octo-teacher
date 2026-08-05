import XCTest
@testable import OctoTeacher

/// 家长-孩子全功能模拟第一批修复的回归测试（白板 SIM-004/005/006）。
/// 覆盖：孩子昵称长度护栏、愿望兑换事件口径、朗读文本纯函数。
final class ChildSimulationBatch1Tests: XCTestCase {

    // MARK: - SIM-005 昵称长度护栏

    func testSanitizedChildNameTrimsAndCapsAtTwelve() {
        XCTAssertEqual(LocalFamilyStore.sanitizedChildName("  乐乐  "), "乐乐")
        XCTAssertEqual(
            LocalFamilyStore.sanitizedChildName("一二三四五六七八九十十一十二十三"),
            "一二三四五六七八九十十一",
            "超过 12 字应截断"
        )
        XCTAssertEqual(LocalFamilyStore.sanitizedChildName("   "), "", "纯空白应清成空串由调用方判空")
    }

    func testApplyFamilySetupCapsChildNameLength() {
        let store = LocalFamilyStore()
        store.applyFamilySetup(
            childName: "超级无敌大名字超过十二个字了吧",
            dailyLimitMinutes: 60,
            keepStarterTasks: true
        )
        XCTAssertEqual(store.child.name.count, 12, "首启昵称应截断到 12 字")
    }

    func testApplyFamilySetupKeepsExistingNameWhenBlank() {
        let store = LocalFamilyStore()
        let original = store.child.name
        store.applyFamilySetup(childName: "   ", dailyLimitMinutes: 60, keepStarterTasks: true)
        XCTAssertEqual(store.child.name, original, "空昵称不应覆盖原名")
    }

    func testAddChildCapsNameLength() throws {
        let store = LocalFamilyStore()
        let added = try XCTUnwrap(store.addChild(name: "第二个孩子的名字也特别特别长", age: 6))
        XCTAssertEqual(added.name.count, 12)
    }

    func testUpdateChildProfileCapsNameLength() {
        let store = LocalFamilyStore()
        let childId = store.activeChildId
        XCTAssertTrue(
            store.updateChildProfile(
                childId: childId,
                name: "改一个特别长特别长的新名字啊",
                age: 8,
                dailyLimitMinutes: 60
            )
        )
        XCTAssertEqual(store.child.name.count, 12, "改名同样受 12 字护栏约束")
    }

    // MARK: - SIM-006 愿望兑换事件口径

    func testRedeemWishEventUsesGrowthPointsWording() throws {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 50
        let wish = try XCTUnwrap(store.submitWish(title: "一本恐龙书"))
        XCTAssertTrue(store.priceWish(wish.id, points: 30))
        XCTAssertTrue(store.redeemWish(wish.id))

        let event = try XCTUnwrap(
            store.events.first { $0.detail.contains("恐龙书") },
            "兑换愿望应写入家庭事件"
        )
        XCTAssertTrue(event.detail.contains("成长积分"), "事件文案应统一叫成长积分，而不是「分」")
        XCTAssertEqual(store.child.rewardBalanceMinutes, 20, "兑换后扣掉 30 成长积分")
    }

    func testChildWishListEmptyCopyGuidesPreReadersWithGrowthPointsAndVoice() {
        let displayed = [
            ChildWishListCopy.emptyTitle,
            ChildWishListCopy.emptyDetail,
            ChildWishListCopy.emptySpeakText,
            ChildWishListCopy.footer,
            ChildWishListCopy.balance(25)
        ].joined(separator: " ")

        XCTAssertTrue(displayed.contains("成长积分"))
        XCTAssertTrue(displayed.contains("小喇叭"))
        XCTAssertTrue(displayed.contains("麦克风"))
        XCTAssertTrue(displayed.contains("说愿望"))
        XCTAssertTrue(displayed.contains("不会自动花钱或购买"))
        XCTAssertTrue(displayed.contains("25 成长积分"))
        XCTAssertFalse(displayed.contains("分钟"))
    }

    // MARK: - SIM-001~003 朗读链路的纯函数部分

    func testSpeechLanguageCodeSelection() {
        XCTAssertEqual(SpeechReader.languageCode(for: "去拿书读吧"), "zh-CN")
        XCTAssertEqual(SpeechReader.languageCode(for: "Read a book"), "en-US")
    }
}
