import XCTest
@testable import OctoTeacher

/// 「首日晚间节律包」模板与一键布置逻辑的 focused 测试（C-PARENT-001 / C-PARENT-003）。
final class FirstEveningRoutinePlanTests: XCTestCase {

    // MARK: - 模板内容

    /// 计划必须正好覆盖四个晚间场景：家务、阅读、户外、睡前放手机。
    func testPlanCoversFourEveningScenes() {
        XCTAssertEqual(FirstEveningRoutinePlan.templates.count, 4)

        let ids = FirstEveningRoutinePlan.templates.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "模板 id 不能重复")
        XCTAssertTrue(ids.contains("first-evening-chore-tidy-toys"))
        XCTAssertTrue(ids.contains("first-evening-reading-cozy"))
        XCTAssertTrue(ids.contains("first-evening-outdoor-play"))
        XCTAssertTrue(ids.contains("first-evening-phone-goodnight"))

        let categories = FirstEveningRoutinePlan.templates.map(\.category)
        XCTAssertEqual(categories.filter { $0 == .home }.count, 1, "家务 1 件")
        XCTAssertEqual(categories.filter { $0 == .learning }.count, 1, "阅读 1 件")
        XCTAssertEqual(categories.filter { $0 == .health }.count, 2, "户外 + 睡前放手机各 1 件")
    }

    func testPlanIdsDoNotCollideWithPackLibrary() {
        let libraryIds = Set(ParentPackTemplateLibrary.groups.flatMap { $0.templates.map(\.id) })
        for template in FirstEveningRoutinePlan.templates {
            XCTAssertFalse(libraryIds.contains(template.id), "\(template.id) 与任务包库撞 id")
        }
    }

    /// 半识字孩子端约束：标题短句、说明口语、无占位文案、无 ReadingSpec、
    /// 奖励落在家长任务表单的固定档位上；户外任务必须显式标记需要大人在场。
    func testPlanTemplatesAreChildFriendly() {
        let rewardTiers: Set<Int> = [5, 10, 15, 20, 30, 45, 60]
        for template in FirstEveningRoutinePlan.templates {
            XCTAssertLessThanOrEqual(template.title.count, 8, "「\(template.title)」标题太长，孩子念不动")
            XCTAssertFalse(template.instructions.isEmpty, "「\(template.title)」缺少朗读说明")
            XCTAssertLessThanOrEqual(template.instructions.count, 40, "「\(template.title)」说明太长，朗读听不完")
            XCTAssertFalse(template.instructions.contains("（布置时填写"), "一键布置没有编辑步骤，不允许占位文案")
            XCTAssertNil(template.reading, "一键布置不带 ReadingSpec，避免占位书名漏到孩子端")
            XCTAssertTrue(rewardTiers.contains(template.suggestedRewardMinutes), "「\(template.title)」奖励不在固定档位")
        }

        let supervisedTitles = Set(FirstEveningRoutinePlan.templates.filter(\.adultSupervisionRequired).map(\.title))
        XCTAssertEqual(supervisedTitles, Set(["出门玩一会儿"]), "只有户外出门任务需要大人在场")
        let outdoor = FirstEveningRoutinePlan.templates.first { $0.title == "出门玩一会儿" }
        XCTAssertTrue(outdoor?.instructions.contains("大人") == true)
    }

    // MARK: - 一键布置

    func testAssignPlanCreatesFourTasksStepsAndOneNamedEvent() {
        let store = LocalFamilyStore()
        let initialAssignments = store.assignments.count
        let initialSteps = store.growthPack.steps.count
        let initialEvents = store.events.count

        let count = store.assignFirstEveningRoutinePlan()

        XCTAssertEqual(count, 4)
        XCTAssertEqual(store.assignments.count, initialAssignments + 4)
        XCTAssertEqual(store.growthPack.steps.count, initialSteps + 4)
        XCTAssertEqual(store.events.count, initialEvents + 1, "只写一条汇总事件")
        XCTAssertEqual(store.events.first?.kind, .taskAssigned)
        XCTAssertEqual(store.events.first?.title, FirstEveningRoutinePlan.title)

        // 布置出来的任务全部可开始、归属当前孩子、奖励保留模板差异。
        let planTitles = Set(FirstEveningRoutinePlan.templates.map(\.title))
        let assigned = store.assignments.filter { planTitles.contains($0.task.title) }
        XCTAssertEqual(assigned.count, 4)
        for assignment in assigned {
            XCTAssertEqual(assignment.status, .open)
            XCTAssertEqual(assignment.childId, store.activeChildId)
        }
        let phoneTask = assigned.first { $0.task.title == "手机去睡觉" }
        XCTAssertEqual(phoneTask?.task.rewardMinutes, 20, "最难的睡前放手机应保留最高建议积分")
        let outdoorTask = assigned.first { $0.task.title == "出门玩一会儿" }
        XCTAssertEqual(outdoorTask?.task.needsAdultSupervision, true, "户外出门任务必须传递大人在场标记")
    }

    func testAssignPlanPreservesTemplatePointsWhenPackDefaultExists() {
        let store = LocalFamilyStore()
        store.setPackDefaultPoints(30, for: FirstEveningRoutinePlan.packType)

        XCTAssertEqual(store.assignFirstEveningRoutinePlan(), 4)

        let planTitles = Set(FirstEveningRoutinePlan.templates.map(\.title))
        let rewards = Dictionary(
            uniqueKeysWithValues: store.assignments
                .filter { planTitles.contains($0.task.title) }
                .map { ($0.task.title, $0.task.rewardMinutes) }
        )
        XCTAssertEqual(rewards["把玩具送回家"], 10)
        XCTAssertEqual(rewards["睡前读小书"], 15)
        XCTAssertEqual(rewards["出门玩一会儿"], 15)
        XCTAssertEqual(rewards["手机去睡觉"], 20)
    }

    /// 同一天重复点一键按钮不能翻倍成 8 个任务。
    func testAssignPlanTwiceSameDayIsNoOp() {
        let store = LocalFamilyStore()
        XCTAssertEqual(store.assignFirstEveningRoutinePlan(), 4)
        XCTAssertTrue(store.hasAssignedFirstEveningRoutinePlan())

        let assignmentsAfterFirst = store.assignments.count
        let eventsAfterFirst = store.events.count

        XCTAssertEqual(store.assignFirstEveningRoutinePlan(), 0)
        XCTAssertEqual(store.assignments.count, assignmentsAfterFirst)
        XCTAssertEqual(store.events.count, eventsAfterFirst, "no-op 不应再写事件")
    }

    /// 多孩子家庭：给老大布置过，不影响给老二一键布置。
    func testAssignPlanPerChildIndependently() throws {
        let store = LocalFamilyStore()
        let firstChildId = store.activeChildId
        XCTAssertEqual(store.assignFirstEveningRoutinePlan(), 4)

        let sibling = try XCTUnwrap(store.addChild(name: "小妹", age: 6))
        XCTAssertFalse(store.hasAssignedFirstEveningRoutinePlan(childId: sibling.id))
        XCTAssertEqual(store.assignFirstEveningRoutinePlan(childId: sibling.id), 4)
        XCTAssertTrue(store.hasAssignedFirstEveningRoutinePlan(childId: sibling.id))
        XCTAssertTrue(store.hasAssignedFirstEveningRoutinePlan(childId: firstChildId))
    }

    /// 昨天布置过不算今天已布置：节律包第二天可以再来一次。
    func testPlanAssignedYesterdayDoesNotBlockToday() {
        let store = LocalFamilyStore()
        XCTAssertEqual(store.assignFirstEveningRoutinePlan(), 4)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertFalse(store.hasAssignedFirstEveningRoutinePlan(on: tomorrow))
    }

    /// 回归：普通任务包布置的汇总事件标题仍是包类型名，不受 eventTitle 参数影响。
    func testPackLibraryEventTitleUnchanged() throws {
        let store = LocalFamilyStore()
        let chores = try XCTUnwrap(ParentPackTemplateLibrary.group(for: .chores))
        store.assignPackTemplates([chores.templates[0]], packType: .chores)
        XCTAssertEqual(store.events.first?.title, PackType.chores.label)
    }
}
