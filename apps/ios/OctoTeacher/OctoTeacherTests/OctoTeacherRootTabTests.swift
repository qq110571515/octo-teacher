import XCTest
@testable import OctoTeacher

final class OctoTeacherRootTabTests: XCTestCase {

    func testFamilyModeKeepsOnlyDailyTabs() {
        // 家庭日常模式聚焦孩子/家长两条主路径，家庭与更多兜底。
        XCTAssertEqual(
            OctoTeacherRootTab.ordered,
            [.child, .parent, .family, .more]
        )
    }

    func testAuditModeKeepsFullPlatformTabs() {
        // UI 测试 / 模块审计模式保留完整平台入口，供点击路径测试直达。
        XCTAssertEqual(
            OctoTeacherRootTab.auditOrdered,
            [.home, .modules, .child, .parent, .school, .family]
        )
    }

    func testEveryCaseAppearsInSomeMode() {
        let reachable = Set(OctoTeacherRootTab.ordered + OctoTeacherRootTab.auditOrdered)
        for tab in OctoTeacherRootTab.allCases {
            XCTAssertTrue(reachable.contains(tab), "Tab \(tab) 在任何模式下都不可见")
        }
    }

    func testNoTopLevelRewardTab() {
        // 顶层不单列“奖励”Tab，奖励从孩子首页/钱包进入。
        for tabs in [OctoTeacherRootTab.ordered, OctoTeacherRootTab.auditOrdered] {
            XCTAssertFalse(tabs.map(\.label).contains("奖励"))
        }
    }

    func testTagsAreUniqueAndStable() {
        let allTags = OctoTeacherRootTab.allCases.map(\.tag)
        XCTAssertEqual(Set(allTags).count, allTags.count, "tag 必须唯一")
        XCTAssertEqual(
            OctoTeacherRootTab.ordered.map(\.tag),
            [2, 3, 5, 6],
            "家庭模式 tag 必须与 case rawValue 稳定对应"
        )
    }

    func testLabelsAreChineseAndNonEmpty() {
        XCTAssertEqual(
            OctoTeacherRootTab.ordered.map(\.label),
            ["孩子", "家长", "家庭", "更多"]
        )
        for tab in OctoTeacherRootTab.allCases {
            XCTAssertFalse(tab.label.isEmpty)
            // 顶层 Tab 标题不暴露 ASCII / 英文标签。
            XCTAssertFalse(
                tab.label.contains { $0.isASCII },
                "Tab 标题不应包含 ASCII 字符：\(tab.label)"
            )
        }
    }

    func testSystemImagesAreNonEmpty() {
        for tab in OctoTeacherRootTab.allCases {
            XCTAssertFalse(tab.systemImage.isEmpty, "systemImage 不应为空：\(tab)")
        }
    }
}
