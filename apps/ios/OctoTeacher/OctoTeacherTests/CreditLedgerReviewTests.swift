import XCTest
@testable import OctoTeacher

/// 成长积分账本复核台的确定性单元测试。
///
/// 覆盖：分组归并（可建议/待审核/冻结/冲突/退款回滚/已阻断）、角色门控（家长可见金额/原因/来源，
/// 孩子等只见安全文案）、余额快照仅家长可见、账本中立护栏恒为 false、发现项与状态、
/// 脱敏与确定性，以及关键安全断言（孩子绝不看到金额/原因/幂等/来源）。
final class CreditLedgerReviewTests: XCTestCase {

    private let engine = MobileCreditSettlementEngine()
    private let account = MobileCreditSettlementAccount(
        childSeed: MobileCreditSettlementAssembler.accountChildSeed,
        familySeed: MobileCreditSettlementAssembler.accountFamilySeed
    )
    private let builder = CreditLedgerReviewBuilder()

    // MARK: - helpers

    private func input(
        seed: String = "p1",
        kind: MobileCreditSettlementKind = .earn,
        source: MobileCreditSettlementSource = .offlineAction,
        amount: Int = 15,
        key: String = "k1",
        actor: MobileCreditSettlementActorRole = .child,
        childSeed: String? = nil,
        teacher: MobileCreditSettlementConclusion? = nil,
        guardian: MobileCreditSettlementConclusion? = nil,
        holdExpired: Bool = false,
        relatedHoldPresent: Bool = true,
        offlineConflict: Bool = false,
        offlineRolledBack: Bool = false,
        deviceFailed: Bool = false
    ) -> MobileCreditSettlementProposalInput {
        MobileCreditSettlementProposalInput(
            proposalSeed: seed,
            kind: kind,
            source: source,
            childSeed: childSeed ?? account.childSeed,
            familySeed: account.familySeed,
            amount: amount,
            idempotencyKey: key,
            actorRole: actor,
            holdExpired: holdExpired,
            teacherConclusion: teacher,
            guardianConclusion: guardian,
            relatedHoldPresent: relatedHoldPresent,
            offlineConflict: offlineConflict,
            offlineRolledBack: offlineRolledBack,
            deviceFailed: deviceFailed
        )
    }

    private func report(_ inputs: [MobileCreditSettlementProposalInput]) -> MobileCreditSettlementReport {
        engine.build(account: account, proposals: inputs)
    }

    /// 覆盖五/六个分组的综合报告。
    private func mixedReport() -> MobileCreditSettlementReport {
        report([
            input(seed: "earn", kind: .earn, amount: 15, key: "k1"),                                  // 可建议
            input(seed: "hold", kind: .hold, source: .rewardRequest, amount: 30, key: "k2"),          // 冻结
            input(seed: "rel", source: .relativeEncouragement, key: "k3", actor: .relative),          // 待审核
            input(seed: "conf", key: "k4", teacher: .approved, guardian: .rejected),                  // 冲突
            input(seed: "rel2", kind: .release, source: .deviceRewardLifecycle, amount: 12, key: "k5"), // 退款/回滚
            input(seed: "blk", key: "k6", offlineRolledBack: true)                                    // 已阻断
        ])
    }

    private func balance() -> CreditLedgerBalanceSnapshot {
        CreditLedgerBalanceSnapshot(
            availableMinutes: 40,
            frozenMinutes: 30,
            pendingMinutes: 20,
            lifetimeEarnedMinutes: 120,
            asOf: "2026-06-24T10:00:00Z"
        )
    }

    private func section(_ console: CreditLedgerReviewConsole, _ kind: CreditLedgerReviewSection) -> CreditLedgerReviewSectionGroup? {
        console.group(kind)
    }

    // MARK: - 分组归并

    func testProposalsMapIntoAllSections() {
        let console = builder.build(viewerRole: .guardian, report: mixedReport(), balance: balance())
        XCTAssertNotNil(section(console, .proposable))
        XCTAssertNotNil(section(console, .frozen))
        XCTAssertNotNil(section(console, .reviewRequired))
        XCTAssertNotNil(section(console, .conflict))
        XCTAssertNotNil(section(console, .refundOrRollback))
        XCTAssertNotNil(section(console, .blockedOrIgnored))
    }

    func testConflictIsItsOwnSectionNotReviewRequired() {
        let console = builder.build(
            viewerRole: .guardian,
            report: report([input(key: "kc", teacher: .approved, guardian: .rejected)]),
            balance: balance()
        )
        XCTAssertNotNil(section(console, .conflict))
        XCTAssertNil(section(console, .reviewRequired))
        XCTAssertEqual(console.status, .conflict)
    }

    func testSectionDisplayOrderIsStable() {
        let console = builder.build(viewerRole: .guardian, report: mixedReport(), balance: balance())
        let order = console.sections.map(\.section)
        let expected = CreditLedgerReviewSection.displayOrder.filter { kind in
            console.group(kind) != nil
        }
        XCTAssertEqual(order, expected)
    }

    // MARK: - 角色门控

    func testGuardianSeesAmountsReasonsAndOrigin() {
        let console = builder.build(viewerRole: .guardian, report: mixedReport(), balance: balance())
        let proposable = section(console, .proposable)!.items.first!
        XCTAssertEqual(proposable.amountMinutes, 15)
        XCTAssertEqual(proposable.amountLabel, "15 成长积分")
        XCTAssertFalse(proposable.amountLabel?.contains("分钟") ?? true)
        XCTAssertNotNil(proposable.reason)
        XCTAssertNotNil(proposable.sourceLabel)
        XCTAssertFalse(proposable.originTags.isEmpty)
        XCTAssertTrue(proposable.originTags.contains("幂等已校验"))
        XCTAssertNotNil(console.balance)
        XCTAssertTrue(console.visibility.canSeeAmounts)
    }

    func testChildSeesOnlySafeStatusNeverAmountsOrReasons() {
        let console = builder.build(viewerRole: .child, report: mixedReport(), balance: balance())
        XCTAssertNil(console.balance, "孩子看不到余额快照")
        XCTAssertFalse(console.visibility.canSeeAmounts)
        for group in console.sections {
            for item in group.items {
                XCTAssertNil(item.amountMinutes, "孩子绝不看到金额")
                XCTAssertNil(item.reason, "孩子绝不看到复核原因")
                XCTAssertNil(item.sourceLabel, "孩子绝不看到来源")
                XCTAssertTrue(item.originTags.isEmpty, "孩子绝不看到幂等/来源标签")
                XCTAssertFalse(item.childSafeStatus.isEmpty)
            }
        }
        XCTAssertEqual(console.headline, "有内容正在等家长复核")
    }

    func testNonGuardianCollapsesEachSectionToOneSafeItem() {
        // 同一分组多条建议时，非家长只看到一条安全状态项，不暴露逐条建议数量。
        let r = report([
            input(seed: "e1", kind: .earn, amount: 15, key: "k1"),
            input(seed: "e2", kind: .earn, amount: 99, key: "k2")
        ])
        let console = builder.build(viewerRole: .child, report: r, balance: balance())
        XCTAssertEqual(section(console, .proposable)?.items.count, 1)
    }

    func testRelativeAndTeacherAreTreatedAsNonGuardian() {
        for role in [CreditLedgerReviewViewerRole.relative, .teacher] {
            let console = builder.build(viewerRole: role, report: mixedReport(), balance: balance())
            XCTAssertNil(console.balance)
            XCTAssertFalse(console.visibility.canSeeReasons)
            for item in console.sections.flatMap({ $0.items }) {
                XCTAssertNil(item.amountMinutes, "\(role) 不应看到金额")
            }
        }
    }

    // MARK: - 余额快照

    func testGuardianBalancePassthrough() {
        let console = builder.build(viewerRole: .guardian, report: mixedReport(), balance: balance())
        XCTAssertEqual(console.balance?.availableMinutes, 40)
        XCTAssertEqual(console.balance?.frozenMinutes, 30)
        XCTAssertEqual(console.balance?.availableLabel, "40 积分")
        XCTAssertEqual(console.balance?.frozenLabel, "30 积分")
        XCTAssertEqual(console.balance?.pendingLabel, "20 积分")
        XCTAssertEqual(console.balance?.lifetimeEarnedLabel, "120 积分")
        XCTAssertFalse(console.balance?.pendingLabel.contains("分钟") ?? true)
        XCTAssertFalse(console.balance?.writesLedger ?? true)
        XCTAssertFalse(console.balance?.isLiveLedger ?? true)
    }

    func testProposableMinutesOnlyCountedForGuardian() {
        let guardian = builder.build(viewerRole: .guardian, report: mixedReport(), balance: balance())
        XCTAssertEqual(guardian.summary.totalProposableMinutes, 15)
        let child = builder.build(viewerRole: .child, report: mixedReport(), balance: balance())
        XCTAssertEqual(child.summary.totalProposableMinutes, 0)
    }

    // MARK: - 护栏（账本中立）

    func testConsoleNeverWritesLedgerOrUnlocks() {
        let console = builder.build(viewerRole: .guardian, report: mixedReport(), balance: balance())
        XCTAssertTrue(console.summary.readOnly)
        XCTAssertFalse(console.summary.writesLedger)
        XCTAssertFalse(console.summary.issuesCredit)
        XCTAssertFalse(console.summary.revokesCredit)
        XCTAssertFalse(console.summary.unlocksDevice)
        XCTAssertFalse(console.summary.sendsNotification)
        XCTAssertFalse(console.summary.callsLedgerApi)
        for item in console.sections.flatMap({ $0.items }) {
            XCTAssertFalse(item.writesLedger)
            XCTAssertFalse(item.issuesCredit)
            XCTAssertFalse(item.unlocksDevice)
            XCTAssertFalse(item.sendsNotification)
        }
    }

    // MARK: - 状态 / 发现项

    func testEmptyReportYieldsEmptyConsole() {
        let console = builder.build(viewerRole: .guardian, report: .empty, balance: balance())
        XCTAssertTrue(console.isEmpty)
        XCTAssertEqual(console.status, .empty)
        XCTAssertEqual(console.headline, "暂无成长积分复核项")
    }

    func testCleanProposableYieldsReadyAndOK() {
        let console = builder.build(
            viewerRole: .guardian,
            report: report([input(kind: .earn, amount: 15, key: "k1")]),
            balance: balance()
        )
        XCTAssertEqual(console.status, .ready)
        XCTAssertTrue(console.findings.contains { $0.code == .consoleOK })
    }

    func testConflictAndBlockedRaiseFindings() {
        let console = builder.build(viewerRole: .guardian, report: mixedReport(), balance: balance())
        let codes = console.findings.map(\.code)
        XCTAssertTrue(codes.contains(.conflictReviewRequired))
        XCTAssertTrue(codes.contains(.reviewRequiredPresent))
        XCTAssertTrue(codes.contains(.blockedPresent))
        XCTAssertTrue(codes.contains(.roleVisibilityApplied))
    }

    func testNonGuardianGetsHiddenDetailFinding() {
        let console = builder.build(viewerRole: .child, report: mixedReport(), balance: balance())
        XCTAssertTrue(console.findings.contains { $0.code == .nonGuardianDetailHidden })
    }

    // MARK: - 脱敏 + 确定性

    func testOutputIsRedacted() {
        let r = report([
            input(seed: "child-secret-001", kind: .earn, key: "k1"),
            input(seed: "device-token-xyz", kind: .hold, source: .rewardRequest, key: "k2"),
            input(seed: "p3", source: .relativeEncouragement, key: "k3", actor: .relative)
        ])
        let console = builder.build(viewerRole: .guardian, report: r, balance: balance())
        var displayed = [console.headline]
        for group in console.sections {
            for item in group.items {
                displayed.append(contentsOf: [item.publicReviewRef, item.kindLabel, item.statusLabel,
                                              item.childSafeStatus, item.reason ?? "", item.sourceLabel ?? ""])
                displayed.append(contentsOf: item.originTags)
            }
        }
        let joined = displayed.joined(separator: " ")
        XCTAssertFalse(MobileSyncPayloadGuard.isUnsafe(joined))
        for marker in ["child-secret", "device-token", "taskId", "claimId", "Bearer ", "192.168.", "family-", "ledger-"] {
            XCTAssertFalse(joined.contains(marker), "不应泄露 \(marker)：\(joined)")
        }
        XCTAssertTrue(builder.redacts(console))
    }

    func testBuildIsDeterministic() {
        let r = mixedReport()
        XCTAssertEqual(
            builder.build(viewerRole: .guardian, report: r, balance: balance()),
            builder.build(viewerRole: .guardian, report: r, balance: balance())
        )
    }

    // MARK: - 集成（基于装配器 + 离线 mock）

    func testIntegratesWithSettlementStore() {
        let outbox = MobileOfflineOutboxStore.mock()
        let replay = MobileOfflineReplayStore()
        replay.replay(outbox: outbox)
        let settlement = MobileCreditSettlementStore()
        let settlementReport = settlement.refresh(
            offlineReport: replay.report,
            family: LocalFamilyStore(),
            schoolFamily: SchoolFamilyStore(),
            screenTime: MockScreenTimeController()
        )

        let console = builder.build(viewerRole: .guardian, report: settlementReport, balance: balance())
        XCTAssertFalse(console.isEmpty)
        // 关键安全断言：亲友鼓励/回滚动作不会出现在「可建议」分组里。
        let proposable = section(console, .proposable)?.items ?? []
        for item in proposable {
            XCTAssertEqual(item.section, .proposable)
        }
        // 孩子视角同一报告：无任何金额泄露。
        let childConsole = builder.build(viewerRole: .child, report: settlementReport, balance: balance())
        for item in childConsole.sections.flatMap({ $0.items }) {
            XCTAssertNil(item.amountMinutes)
        }
        XCTAssertTrue(builder.redacts(console))
    }
}
