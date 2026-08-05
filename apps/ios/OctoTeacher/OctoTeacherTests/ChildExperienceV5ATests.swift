import XCTest
@testable import OctoTeacher

/// v5 A 批回归：重复任务、家长角色、阅读自适应积分、学校类别。
final class ChildExperienceV5ATests: XCTestCase {

    private func dateOf(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func sampleTemplate(title: String = "每天读书") -> TaskTemplate {
        TaskTemplate(
            id: UUID(), title: title, category: .learning, difficulty: .easy,
            rewardMinutes: 15, instructions: "", requiredProof: .text
        )
    }

    // MARK: - 重复任务

    func testDailyRuleGeneratesOncePerDay() throws {
        let store = LocalFamilyStore()
        let before = store.assignments.count
        _ = try XCTUnwrap(store.addRecurringRule(template: sampleTemplate(), recurrence: .daily))
        XCTAssertEqual(store.assignments.count, before + 1, "登记后立即生成今天的实例")

        // 同日重复调用不再生成。
        store.generateDueRecurringTasks()
        store.generateDueRecurringTasks()
        XCTAssertEqual(store.assignments.count, before + 1)

        // 第二天生成新实例。
        store.generateDueRecurringTasks(now: Date().addingTimeInterval(86_400))
        XCTAssertEqual(store.assignments.count, before + 2)
    }

    func testWeeklyRuleOnlyFiresOnItsWeekday() throws {
        let store = LocalFamilyStore()
        let before = store.assignments.count
        // 2026-07-08 是周三（weekday=4）。
        let wednesday = dateOf(2026, 7, 8)
        let rule = RecurringTaskRule(
            id: UUID(), childId: store.activeChildId, template: sampleTemplate(title: "每周三练琴"),
            recurrence: .weekly, weekday: 4, lastGeneratedDayKey: nil
        )
        store.recurringRules.append(rule)

        store.generateDueRecurringTasks(now: dateOf(2026, 7, 7)) // 周二
        XCTAssertEqual(store.assignments.count, before, "非周三不生成")

        store.generateDueRecurringTasks(now: wednesday)
        XCTAssertEqual(store.assignments.count, before + 1)

        store.generateDueRecurringTasks(now: wednesday)
        XCTAssertEqual(store.assignments.count, before + 1, "同一天幂等")
    }

    func testOnceRecurrenceRejectedAsRule() {
        let store = LocalFamilyStore()
        XCTAssertNil(store.addRecurringRule(template: sampleTemplate(), recurrence: .once))
    }

    func testRecurringRuleSurvivesRoundTrip() throws {
        let store = LocalFamilyStore()
        _ = store.addRecurringRule(template: sampleTemplate(), recurrence: .daily)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.recurringRules?.count, 1)
        XCTAssertNotNil(decoded.recurringRules?.first?.lastGeneratedDayKey)
    }

    // MARK: - 家长角色

    func testGuardianFriendlyLabels() {
        let labels = GuardianRole.allCases.map(\.label)
        XCTAssertFalse(labels.contains("后妈"), "敏感称谓不能出现")
        XCTAssertFalse(labels.contains("保姆"), "敏感称谓不能出现")
        XCTAssertTrue(labels.contains("家庭老师"))
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    func testGuardianLifecycleAndEventAttribution() throws {
        let store = LocalFamilyStore()
        XCTAssertEqual(store.currentGuardianName, "家长", "未配置时用默认称呼")

        let mom = try XCTUnwrap(store.addGuardian(name: "", role: .mom))
        XCTAssertEqual(mom.displayName, "妈妈", "昵称留空用称谓")
        XCTAssertEqual(store.currentGuardianId, mom.id, "第一个大人自动成为当前操作人")

        let teacher = try XCTUnwrap(store.addGuardian(name: "张老师", role: .familyTeacher))
        store.setCurrentGuardian(teacher.id)
        XCTAssertEqual(store.currentGuardianName, "张老师")

        // 批准事件署名当前操作人。
        store.submit(store.assignments[0], text: "完成")
        _ = store.approve(store.assignments[0])
        XCTAssertTrue(store.events.first?.detail.contains("张老师") == true)

        XCTAssertNil(store.addGuardian(name: "张老师", role: .aunt), "重名不能添加")
    }

    // MARK: - 阅读自适应积分

    func testPlannerParsesSuggestedPoints() {
        let raw = """
        {"intro":"简介","sessions":[
            {"order":1,"chapters":"第1章","estimatedMinutes":60,"suggestedPoints":25,"note":""},
            {"order":2,"chapters":"第2章","estimatedMinutes":60,"suggestedPoints":999,"note":""}
        ]}
        """
        let result = AIReadingPlanner.parseWithIntro(raw)
        XCTAssertEqual(result.sessions[0].suggestedPoints, 25)
        XCTAssertEqual(result.sessions[1].suggestedPoints, 60, "积分建议封顶 60")
    }

    func testPlannerPromptUsesWordPictureBookAndParentSelectedRules() {
        let prompt = AIReadingPlanner.systemPrompt()
        XCTAssertTrue(prompt.contains("5,000-10,000"))
        XCTAssertTrue(prompt.contains("每 2 章"))
        XCTAssertTrue(prompt.contains("家长指定次数"))
        XCTAssertTrue(prompt.contains("suggestedPoints"))
    }

    // MARK: - 学校类别

    func testSchoolCategoryExists() {
        XCTAssertEqual(TaskCategory.school.label, "学校任务")
        XCTAssertTrue(TaskCategory.childDisplayOrder.contains(.school))
        XCTAssertEqual(TaskCategory.childDisplayOrder.count, TaskCategory.allCases.count)
    }

    /// 旧数据类别解码不受新增 case 影响。
    func testLegacyCategoryDecodes() throws {
        let category = try JSONDecoder().decode(TaskCategory.self, from: Data("\"health\"".utf8))
        XCTAssertEqual(category, .health)
        XCTAssertEqual(category.label, "体育锻炼")
    }
}
