import XCTest
@testable import OctoTeacher

final class MobileGrowthPackAdaptiveScheduleTests: XCTestCase {

    private func build(
        role: MobileGrowthPackExecutionHubRole,
        input: MobileGrowthPackAdaptiveScheduleInput = .mock
    ) -> MobileGrowthPackAdaptiveSchedule {
        MobileGrowthPackAdaptiveScheduleBuilder().build(role: role, input: input)
    }

    func testChildSeesSafeTodayPlanWithoutAdultSensitiveDetails() {
        let schedule = build(role: .child)

        XCTAssertEqual(schedule.role, .child)
        // 复核节奏对孩子隐藏，孩子只看到 7 个排期。
        XCTAssertEqual(schedule.publicSummary.slotCount, 8)
        XCTAssertEqual(schedule.publicSummary.visibleSlotCount, 7)
        XCTAssertFalse(schedule.slots.contains { $0.kind == .reviewCadence })
        XCTAssertTrue(schedule.slots.contains { $0.kind == .schoolHomework })
        XCTAssertTrue(schedule.slots.contains { $0.kind == .sleepQuietWindow })
        XCTAssertTrue(schedule.slots.contains { $0.kind == .rewardWindow })
        XCTAssertGreaterThanOrEqual(schedule.publicSummary.suitableNowCount, 1)
        XCTAssertGreaterThanOrEqual(schedule.publicSummary.notNowCount, 1)
        XCTAssertTrue(schedule.findings.allSatisfy(\.visibleToChild))
        XCTAssertFalse(schedule.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(schedule.hasUnsafeDisplayPayload)

        let text = schedule.displayValues.joined(separator: " ")
        for forbidden in [
            "答案键",
            "answer key",
            "成长积分金额",
            "账本明细",
            "复核策略",
            "order:",
            "ledger:",
            "device:",
            "calendar:",
            "schedule:",
            "provider:",
            "model:",
            "transcript",
            "http://",
            "https://",
            "/Users/"
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
    }

    func testGuardianSeesScheduleConflictsAndReviewBoundaries() {
        let schedule = build(role: .guardian)

        XCTAssertEqual(schedule.role, .guardian)
        XCTAssertEqual(schedule.publicSummary.visibleSlotCount, 8)
        XCTAssertTrue(schedule.slots.contains { $0.kind == .reviewCadence })
        XCTAssertEqual(schedule.publicSummary.sleepConflictCount, 1)
        XCTAssertEqual(schedule.publicSummary.homeworkConflictCount, 1)
        XCTAssertEqual(schedule.publicSummary.rewardConflictCount, 1)
        XCTAssertGreaterThanOrEqual(schedule.publicSummary.evidenceGapCount, 1)
        XCTAssertGreaterThanOrEqual(schedule.publicSummary.guardianReviewCount, 1)
        XCTAssertFalse(schedule.publicSummary.hasTriggeredSideEffect)
        XCTAssertFalse(schedule.hasUnsafeDisplayPayload)
    }

    func testSleepHomeworkAndRewardConflictsRaiseFindings() {
        let schedule = build(role: .guardian)
        let codes = Set(schedule.findings.map(\.code))

        XCTAssertTrue(codes.contains(.sleepWindowProtected))
        XCTAssertTrue(codes.contains(.homeworkPriorityConflict))
        XCTAssertTrue(codes.contains(.evidenceGap))
        XCTAssertTrue(codes.contains(.rewardWindowReview))
        XCTAssertTrue(schedule.findings.contains { $0.code == .rewardWindowReview && $0.actionRequired })

        let childSchedule = build(role: .child)
        let childCodes = Set(childSchedule.findings.map(\.code))
        // 奖励窗口复核与家长复核提示不向孩子暴露。
        XCTAssertFalse(childCodes.contains(.rewardWindowReview))
        XCTAssertFalse(childCodes.contains(.guardianReviewRequired))
        XCTAssertTrue(childCodes.contains(.sleepWindowProtected))
        XCTAssertTrue(childCodes.contains(.homeworkPriorityConflict))
    }

    func testScheduleOrderingIsDeterministicAndStable() {
        let schedule = build(role: .child)
        let sortOrders = schedule.slots.map(\.sortOrder)

        XCTAssertEqual(sortOrders, sortOrders.sorted())
        // 作业排在成长包步骤之前，睡眠/奖励排在靠后。
        let kinds = schedule.slots.map(\.kind)
        if let homeworkIndex = kinds.firstIndex(of: .schoolHomework),
           let growthIndex = kinds.firstIndex(of: .growthPackStep),
           let sleepIndex = kinds.firstIndex(of: .sleepQuietWindow) {
            XCTAssertLessThan(homeworkIndex, growthIndex)
            XCTAssertLessThan(growthIndex, sleepIndex)
        } else {
            XCTFail("缺少关键排期项")
        }
        XCTAssertEqual(schedule.slots.map(\.publicSlotRef), build(role: .child).slots.map(\.publicSlotRef))
        XCTAssertNotEqual(schedule.slots.map(\.publicSlotRef), build(role: .guardian).slots.map(\.publicSlotRef))
    }

    func testUnsafePayloadHidesScheduleWithoutEchoingRawValue() {
        let schedule = build(
            role: .guardian,
            input: MobileGrowthPackAdaptiveScheduleInput(
                generatedAt: "2026-06-25T01:10:00.000Z",
                unsafePayload: "calendar:raw child:raw schedule:raw ledger:raw http://example.invalid"
            )
        )

        XCTAssertTrue(schedule.slots.isEmpty)
        XCTAssertEqual(schedule.publicSummary.findingCodes, [.unsafePayloadBlocked])
        XCTAssertFalse(schedule.displayValues.joined(separator: " ").localizedCaseInsensitiveContains("example.invalid"))
        XCTAssertFalse(schedule.publicSummary.hasTriggeredSideEffect)
    }

    func testUnmarkedPersonalPayloadIsNeverEchoed() {
        let schedule = build(
            role: .child,
            input: MobileGrowthPackAdaptiveScheduleInput(
                generatedAt: "2026-06-25T01:10:00.000Z",
                unsafePayload: "家长张三 电话13800000000 家庭住址示例路1号"
            )
        )

        let text = schedule.displayValues.joined(separator: " ")
        for forbidden in ["张三", "13800000000", "示例路1号"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
        XCTAssertFalse(schedule.publicSummary.hasTriggeredSideEffect)
    }

    func testPublicRefsAndDisplayValuesAreStableAndRedacted() {
        let schedule = build(role: .guardian)
        let refs = schedule.slots.map(\.publicSlotRef)

        XCTAssertEqual(Set(refs).count, refs.count)
        XCTAssertTrue(refs.allSatisfy { $0.hasPrefix("gpas-") })
        for value in schedule.displayValues {
            for forbidden in ["child:", "family:", "calendar:", "schedule:", "ledger:", "token", "192.168.", ".local", "/Volumes/"] {
                XCTAssertFalse(value.localizedCaseInsensitiveContains(forbidden), "\(value) contains \(forbidden)")
            }
        }
    }

    func testAllSlotsAndSummaryRemainReadOnly() {
        for role in MobileGrowthPackExecutionHubRole.allCases {
            let schedule = build(role: role)

            XCTAssertFalse(schedule.publicSummary.callsNetwork)
            XCTAssertFalse(schedule.publicSummary.callsAiProvider)
            XCTAssertFalse(schedule.publicSummary.callsLocalModel)
            XCTAssertFalse(schedule.publicSummary.callsLms)
            XCTAssertFalse(schedule.publicSummary.writesSchoolSystem)
            XCTAssertFalse(schedule.publicSummary.writesLedger)
            XCTAssertFalse(schedule.publicSummary.grantsCredit)
            XCTAssertFalse(schedule.publicSummary.unlocksDevice)
            XCTAssertFalse(schedule.publicSummary.sendsNotification)
            XCTAssertFalse(schedule.publicSummary.opensExternalLink)
            XCTAssertFalse(schedule.publicSummary.opensCamera)
            XCTAssertFalse(schedule.publicSummary.opensPhotoLibrary)
            XCTAssertFalse(schedule.publicSummary.opensFilePicker)
            XCTAssertFalse(schedule.publicSummary.opensSystemCalendar)
            XCTAssertFalse(schedule.publicSummary.readsHealthKit)
            XCTAssertFalse(schedule.publicSummary.controlsScreenTime)
            XCTAssertFalse(schedule.publicSummary.uploadsMedia)
            XCTAssertFalse(schedule.publicSummary.publishesContent)
            XCTAssertFalse(schedule.publicSummary.createsOrder)
            XCTAssertFalse(schedule.publicSummary.writesEntitlement)
            XCTAssertFalse(schedule.publicSummary.hasTriggeredSideEffect)
            XCTAssertTrue(schedule.slots.allSatisfy { !$0.hasTriggeredSideEffect })
        }
    }

    @MainActor
    func testViewInitializersCompileWithLockedRoles() {
        _ = MobileGrowthPackAdaptiveScheduleView()
        _ = MobileGrowthPackAdaptiveScheduleView(initialRole: .guardian, allowedRoles: [])
        _ = MobileGrowthPackAdaptiveScheduleView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackAdaptiveScheduleView(initialRole: .guardian, allowedRoles: [.guardian])
        // 入口路由只传角色与安全枚举，构造执行中心不触发副作用。
        _ = MobileGrowthPackExecutionHubView(initialRole: .child, allowedRoles: [.child])
        _ = MobileGrowthPackExecutionHubView(initialRole: .guardian, allowedRoles: [.guardian])
    }
}
