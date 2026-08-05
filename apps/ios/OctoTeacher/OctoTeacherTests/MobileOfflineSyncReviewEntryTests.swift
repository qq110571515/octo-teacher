import XCTest
@testable import OctoTeacher

/// 离线同步复核台「多页签统一入口」纯文案配置（`MobileOfflineSyncReviewEntryCopy`）测试。
///
/// 入口本身只是导航文案，不触发 replay、不落定业务。覆盖：
/// - 孩子入口只描述安全同步状态，绝不出现冲突 / 回滚 / 写账本 / ledger / 成人复核内部原因 /
///   设备控制承诺等字样；
/// - 家长入口才说明待同步 / 冲突 / 回滚摘要，并明确本地只读、不写账本、不发成长积分、不解锁设备；
/// - 两种视角文案都不命中脱敏守卫，也不泄露内部标记。
final class MobileOfflineSyncReviewEntryTests: XCTestCase {

    private func copy(_ perspective: MobileHomePerspective) -> MobileOfflineSyncReviewEntryCopy {
        MobileOfflineSyncReviewEntryCopy(perspective: perspective)
    }

    private func strings(_ c: MobileOfflineSyncReviewEntryCopy) -> [String] {
        [c.title, c.subtitle]
    }

    func testChildCopyHidesAdultReviewSemantics() {
        let child = copy(.child)
        XCTAssertEqual(child.perspective, .child)
        // 孩子入口绝不出现成人复核语义或设备控制承诺。
        let forbidden = ["冲突", "回滚", "账本", "ledger", "成长积分", "积分", "解锁", "设备",
                         "退款", "权益", "驳回", "原因"]
        for text in strings(child) {
            for word in forbidden {
                XCTAssertFalse(
                    text.localizedCaseInsensitiveContains(word),
                    "孩子入口文案不应出现「\(word)」：\(text)"
                )
            }
        }
        // 孩子入口仍要给出安全的同步语境。
        XCTAssertTrue(child.subtitle.contains("同步"))
    }

    func testParentCopyDeclaresReadOnlyBoundary() {
        let parent = copy(.parent)
        XCTAssertEqual(parent.perspective, .parent)
        // 家长入口才说明待同步 / 冲突 / 回滚摘要。
        XCTAssertTrue(parent.subtitle.contains("冲突"))
        XCTAssertTrue(parent.subtitle.contains("回滚"))
        // 家长入口明确本地只读、不落定。
        XCTAssertTrue(parent.subtitle.contains("不写账本"))
        XCTAssertTrue(parent.subtitle.contains("不发成长积分"))
        XCTAssertTrue(parent.subtitle.contains("不解锁设备"))
    }

    func testChildAndParentCopyDiffer() {
        XCTAssertNotEqual(copy(.child), copy(.parent))
        XCTAssertNotEqual(copy(.child).subtitle, copy(.parent).subtitle)
    }

    func testNoSensitivePayloadInEntryStrings() {
        for perspective in MobileHomePerspective.allCases {
            for text in strings(copy(perspective)) {
                XCTAssertFalse(
                    MobileSyncPayloadGuard.isUnsafe(text),
                    "入口文案不应命中不安全负载：\(text)"
                )
                for marker in ["subject-", "actor-", "offline-demo", "http://", "https://",
                               "192.168.", "/Users/", "/Volumes/", "taskId", "claimId",
                               "publicRef", "token"] {
                    XCTAssertFalse(
                        text.localizedCaseInsensitiveContains(marker),
                        "入口文案不应泄露内部标记 \(marker)：\(text)"
                    )
                }
            }
        }
    }
}
