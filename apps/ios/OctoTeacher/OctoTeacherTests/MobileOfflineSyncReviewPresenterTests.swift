import XCTest
@testable import OctoTeacher

/// 离线同步复核台纯逻辑展示映射（`MobileOfflineSyncReviewPresenter`）测试。
///
/// 覆盖角色裁剪与脱敏只读边界：
/// - 孩子只看安全态（confirmed / needsGuardianReview），看不到冲突原因明细与回滚摘要；
/// - 家长才看冲突/回滚摘要与全部逐条结果；
/// - 计数行按视角裁剪：孩子端不暴露冲突/回滚数量；
/// - 文案明确只读、不落定（不写账本、不发成长积分、不解锁设备）。
final class MobileOfflineSyncReviewPresenterTests: XCTestCase {

    /// 用 mock outbox 跑一次确定性重放，得到一个含冲突/回滚的报告。
    private func makeFixture() -> (MobileOfflineOutboxStore, MobileOfflineReplayReport) {
        let outbox = MobileOfflineOutboxStore.mock()
        let report = MobileOfflineReplayEngine().replay(mutations: outbox.mutations)
        // 把冲突/回滚回填进 outbox，保证 publicStatus / conflictHints 与报告一致。
        for result in report.results {
            switch result.status {
            case .conflict:
                outbox.markConflict(clientMutationRef: result.clientMutationRef, reason: result.conflictReason ?? .alreadyResolved)
            case .rolledBack:
                outbox.rollback(clientMutationRef: result.clientMutationRef, reason: result.conflictReason ?? .supersededByGuardian)
            case .confirmed, .needsGuardianReview:
                break
            }
        }
        return (outbox, report)
    }

    private func presenter(
        _ perspective: MobileHomePerspective
    ) -> MobileOfflineSyncReviewPresenter {
        let (outbox, report) = makeFixture()
        return MobileOfflineSyncReviewPresenter(
            perspective: perspective,
            status: outbox.publicStatus,
            conflictHints: outbox.conflictHints,
            report: report
        )
    }

    func testChildHidesConflictAndRollbackDetails() {
        let child = presenter(.child)
        XCTAssertFalse(child.showsConflictDetails, "孩子端不展示冲突/回滚明细")
        XCTAssertTrue(child.visibleConflictHints.isEmpty, "孩子端冲突提示恒为空")
        // 孩子端可见结果只含安全态。
        XCTAssertTrue(
            child.visibleResults.allSatisfy { $0.status == .confirmed || $0.status == .needsGuardianReview },
            "孩子端只看 confirmed / needsGuardianReview 两种安全态"
        )
        XCTAssertFalse(
            child.visibleResults.contains { $0.status == .conflict || $0.status == .rolledBack },
            "孩子端绝不展示冲突/回滚结果"
        )
        // 孩子端计数行只暴露「待同步」一项。
        XCTAssertEqual(child.statusCounts.map(\.label), ["待同步"])
        XCTAssertFalse(child.hasAttention)
    }

    func testParentSeesConflictAndRollbackSummary() {
        let parent = presenter(.parent)
        XCTAssertTrue(parent.showsConflictDetails, "家长端展示冲突/回滚明细")
        // fixture 预置了一条冲突与一条回滚，家长应能看到。
        XCTAssertFalse(parent.visibleConflictHints.isEmpty, "家长端应看到冲突/回滚摘要")
        XCTAssertTrue(parent.visibleConflictHints.contains { $0.rolledBack }, "家长端应能看到回滚摘要")
        // 家长端逐条结果包含全部态。
        XCTAssertEqual(parent.visibleResults.count, parent.report.results.count)
        XCTAssertEqual(parent.statusCounts.map(\.label), ["待同步", "冲突", "已回滚"])
    }

    func testFootnotesDeclareReadOnlyBoundary() {
        let child = presenter(.child)
        let parent = presenter(.parent)
        XCTAssertTrue(child.footnote.contains("不会发积分"))
        XCTAssertTrue(child.footnote.contains("不会解锁设备"))
        XCTAssertTrue(parent.footnote.contains("不写账本"))
        XCTAssertTrue(parent.footnote.contains("不发成长积分"))
        XCTAssertTrue(parent.footnote.contains("不解锁设备"))
    }

    func testPresenterIsPureAndDoesNotMutateStores() {
        let outbox = MobileOfflineOutboxStore.mock()
        let report = MobileOfflineReplayEngine().replay(mutations: outbox.mutations)
        let pendingBefore = outbox.publicStatus.pendingCount

        let presenter = MobileOfflineSyncReviewPresenter(
            perspective: .parent,
            status: outbox.publicStatus,
            conflictHints: outbox.conflictHints,
            report: report
        )
        // 读取派生值多次，不应改动任何 store。
        _ = presenter.headline
        _ = presenter.visibleResults
        _ = presenter.visibleConflictHints
        _ = presenter.statusCounts

        XCTAssertEqual(outbox.publicStatus.pendingCount, pendingBefore, "Presenter 只读，不应改动 outbox 队列")
    }

    func testNoSensitivePayloadInDisplayedStrings() {
        for perspective in MobileHomePerspective.allCases {
            let p = presenter(perspective)
            var strings: [String] = [p.headline, p.footnote]
            strings.append(contentsOf: p.statusCounts.map(\.label))
            for result in p.visibleResults {
                strings.append(contentsOf: [result.kindLabel, result.actorLabel, result.message, result.nextStep])
            }
            for hint in p.visibleConflictHints {
                strings.append(contentsOf: [hint.kindLabel, hint.actorLabel, hint.message, hint.nextStep])
            }
            for text in strings {
                XCTAssertFalse(MobileSyncPayloadGuard.isUnsafe(text), "复核台展示文本不应命中不安全负载：\(text)")
                for marker in ["subject-", "actor-", "offline-demo", "http://", "https://", "192.168.", "/Users/", "/Volumes/", "taskId", "claimId"] {
                    XCTAssertFalse(text.localizedCaseInsensitiveContains(marker), "复核台展示文本不应泄露内部标记 \(marker)：\(text)")
                }
            }
        }
    }
}
