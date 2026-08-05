import XCTest
@testable import OctoTeacher

/// 任务包模板库与批量布置的回归测试（成长包平台化阶段 1）。
final class ParentPackLibraryTests: XCTestCase {

    // MARK: - 模板库完整性

    func testLibraryCoversAllPackTypes() {
        let coveredTypes = Set(ParentPackTemplateLibrary.groups.map(\.packType))
        XCTAssertEqual(coveredTypes, Set(PackType.allCases))
        XCTAssertEqual(ParentPackTemplateLibrary.groups.count, PackType.allCases.count)
    }

    func testEveryTemplateIsWellFormed() {
        for group in ParentPackTemplateLibrary.groups {
            XCTAssertFalse(group.summary.isEmpty, "\(group.title) 缺少说明")
            XCTAssertFalse(group.templates.isEmpty, "\(group.title) 没有模板")
            for template in group.templates {
                XCTAssertFalse(template.title.isEmpty)
                XCTAssertFalse(template.instructions.isEmpty)
                XCTAssertTrue(
                    (5...60).contains(template.suggestedRewardMinutes),
                    "\(template.title) 成长积分越界"
                )
            }
        }
    }

    func testTemplateIdsAreUniqueAcrossLibrary() {
        let ids = ParentPackTemplateLibrary.groups.flatMap { $0.templates.map(\.id) }
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testDangerousSkillTemplatesRequireAdultSupervision() throws {
        let skills = try XCTUnwrap(ParentPackTemplateLibrary.group(for: .skillExtension))
        let dangerous = ["skill-fix-toy", "skill-sew-button", "skill-simple-dish"]
        for id in dangerous {
            let template = try XCTUnwrap(skills.templates.first { $0.id == id })
            XCTAssertTrue(template.adultSupervisionRequired, "\(template.title) 必须标记需要大人在场")
        }
    }

    func testBasicHabitsArePersonalIndependencePackage() throws {
        let independence = try XCTUnwrap(ParentPackTemplateLibrary.group(for: .basicHabits))
        XCTAssertEqual(independence.title, "个人独立性任务包")
        XCTAssertTrue(independence.summary.contains("睡觉"))
        XCTAssertTrue(independence.summary.contains("书包"))

        let titles = independence.templates.map(\.title).joined(separator: " ")
        for keyword in ["睡觉", "穿衣", "洗脸", "刷牙", "洗澡", "衣服", "书包", "房间"] {
            XCTAssertTrue(titles.contains(keyword), "个人独立性任务包缺少 \(keyword)")
        }
    }

    func testChorePackageUsesSameBigItemSubtaskLogic() throws {
        let chores = try XCTUnwrap(ParentPackTemplateLibrary.group(for: .chores))
        XCTAssertTrue(chores.summary.contains("家庭协作"))
        XCTAssertGreaterThanOrEqual(chores.templates.count, 7)

        let titles = chores.templates.map(\.title).joined(separator: " ")
        for keyword in ["餐桌", "垃圾", "植物", "衣服", "擦"] {
            XCTAssertTrue(titles.contains(keyword), "家务包缺少 \(keyword)")
        }
    }

    func testOutdoorSportsPackageSupportsSafeCustomizableActivities() throws {
        let outdoor = try XCTUnwrap(ParentPackTemplateLibrary.group(for: .outdoorSports))
        XCTAssertEqual(outdoor.title, "户外运动包")
        XCTAssertTrue(outdoor.summary.contains("自定义"))
        XCTAssertGreaterThanOrEqual(outdoor.templates.count, 6)

        let titles = outdoor.templates.map(\.title).joined(separator: " ")
        for keyword in ["公园", "跳绳", "球", "骑车", "自然"] {
            XCTAssertTrue(titles.contains(keyword), "户外运动包缺少 \(keyword)")
        }

        let supervisedTitles = outdoor.templates
            .filter(\.adultSupervisionRequired)
            .map(\.title)
            .joined(separator: " ")
        XCTAssertTrue(supervisedTitles.contains("骑车"))
        XCTAssertTrue(supervisedTitles.contains("公园"))
    }

    /// 金融素养包不出现任何真实交易操作（DECISIONS 2026-07-04: No Real-Money Transactions In App）。
    func testFinanceTemplatesStayRecordAndSimulationOnly() throws {
        let finance = try XCTUnwrap(ParentPackTemplateLibrary.group(for: .financeLiteracy))
        let forbiddenWords = ["支付", "转账", "收款", "下单", "汇款"]
        for template in finance.templates {
            for word in forbiddenWords {
                XCTAssertFalse(template.title.contains(word), "\(template.title) 含真实交易词")
                XCTAssertFalse(template.instructions.contains(word), "\(template.title) 说明含真实交易词")
            }
        }
    }

    // MARK: - 批量布置

    func testAssignPackTemplatesCreatesAssignmentsStepsAndOneEvent() throws {
        let store = LocalFamilyStore()
        let initialAssignments = store.assignments.count
        let initialSteps = store.growthPack.steps.count
        let initialEvents = store.events.count

        let chores = try XCTUnwrap(ParentPackTemplateLibrary.group(for: .chores))
        let picked = Array(chores.templates.prefix(3))

        let count = store.assignPackTemplates(picked, packType: .chores)

        XCTAssertEqual(count, 3)
        XCTAssertEqual(store.assignments.count, initialAssignments + 3)
        XCTAssertEqual(store.growthPack.steps.count, initialSteps + 3)
        // 只写一条汇总事件。
        XCTAssertEqual(store.events.count, initialEvents + 1)
        XCTAssertEqual(store.events.first?.kind, .taskAssigned)
        XCTAssertEqual(store.events.first?.title, PackType.chores.label)

        // 步骤顺序保持连续。
        let orders = store.growthPack.steps.map(\.order)
        XCTAssertEqual(orders, Array(1...store.growthPack.steps.count))
    }

    func testAssignPackTemplatesWithEmptySelectionIsNoOp() {
        let store = LocalFamilyStore()
        let initialAssignments = store.assignments.count
        let initialEvents = store.events.count

        XCTAssertEqual(store.assignPackTemplates([], packType: .chores), 0)
        XCTAssertEqual(store.assignments.count, initialAssignments)
        XCTAssertEqual(store.events.count, initialEvents)
    }

    func testAssignedTemplateCarriesSupervisionAndReadingSpec() throws {
        let store = LocalFamilyStore()
        let skills = try XCTUnwrap(ParentPackTemplateLibrary.group(for: .skillExtension))
        let supervised = try XCTUnwrap(skills.templates.first { $0.adultSupervisionRequired })

        store.assignPackTemplates([supervised], packType: .skillExtension)
        let assignment = try XCTUnwrap(store.assignments.last)
        XCTAssertTrue(assignment.task.needsAdultSupervision)

        let learning = try XCTUnwrap(ParentPackTemplateLibrary.group(for: .learning))
        let readingTemplate = try XCTUnwrap(learning.templates.first { $0.reading != nil })
        store.assignPackTemplates([readingTemplate], packType: .learning)
        let readingAssignment = try XCTUnwrap(store.assignments.last)
        XCTAssertNotNil(readingAssignment.task.reading)
    }

    func testCustomPackTemplatePersistsAndKeepsItsOwnDurationAndPoints() throws {
        let store = LocalFamilyStore()
        let custom = try XCTUnwrap(
            store.addCustomPackTemplate(
                packType: .outdoorSports,
                title: "骑车 20 分钟",
                instructions: "戴好头盔，只在小区安全区域骑。",
                expectedMinutes: 20,
                rewardPoints: 18,
                requiredProof: .photo,
                adultSupervisionRequired: true
            )
        )

        XCTAssertTrue(custom.isCustom)
        XCTAssertEqual(custom.expectedMinutes, 20)
        XCTAssertTrue(store.templates(for: .outdoorSports).contains { $0.id == custom.id })

        store.setPackDefaultPoints(60, for: .outdoorSports)
        XCTAssertEqual(store.assignPackTemplates([custom], packType: .outdoorSports), 1)
        let assignment = try XCTUnwrap(store.assignments.last)
        XCTAssertEqual(assignment.task.packType, .outdoorSports)
        XCTAssertEqual(assignment.task.rewardMinutes, 18, "自定义任务的积分是家长明确输入，不应被包默认分覆盖")
        XCTAssertTrue(assignment.task.instructions.contains("建议用时：20 分钟"))
        XCTAssertTrue(assignment.task.needsAdultSupervision)

        let data = try JSONEncoder().encode(store.snapshot)
        let decoded = try JSONDecoder().decode(FamilyStoreSnapshot.self, from: data)
        let restored = try XCTUnwrap(decoded.customPackTemplates?[PackType.outdoorSports.rawValue]?.first)
        XCTAssertEqual(restored.title, "骑车 20 分钟")
        XCTAssertEqual(restored.expectedMinutes, 20)
    }

    func testCustomPackTemplateCanBeRemoved() throws {
        let store = LocalFamilyStore()
        let custom = try XCTUnwrap(
            store.addCustomPackTemplate(
                packType: .chores,
                title: "给植物浇水",
                instructions: "",
                expectedMinutes: 10,
                rewardPoints: 8,
                requiredProof: .text,
                adultSupervisionRequired: false
            )
        )

        XCTAssertTrue(store.removeCustomPackTemplate(id: custom.id, from: .chores))
        XCTAssertFalse(store.templates(for: .chores).contains { $0.id == custom.id })
    }

    // MARK: - 阅读任务与持久化兼容

    func testAssignNewReadingTaskStoresSpec() throws {
        let store = LocalFamilyStore()
        let assignment = try XCTUnwrap(
            store.assignNewTask(
                title: "读《夏洛的网》",
                instructions: "读完说说学到了什么。",
                category: .learning,
                rewardMinutes: 20,
                requiredProof: .text,
                reading: ReadingSpec(bookTitle: "夏洛的网", minMinutes: 30, chapterPlanText: "第 1-2 章")
            )
        )
        XCTAssertEqual(assignment.task.reading?.bookTitle, "夏洛的网")
        XCTAssertEqual(assignment.task.reading?.minMinutes, 30)
    }

    func testUpdateTaskCanSetAndClearReadingSpec() throws {
        let store = LocalFamilyStore()
        let assignment = try XCTUnwrap(
            store.assignNewTask(
                title: "阅读时间",
                instructions: "",
                category: .learning,
                rewardMinutes: 15,
                requiredProof: .text
            )
        )

        XCTAssertTrue(
            store.updateTask(
                assignmentId: assignment.id,
                title: "阅读时间",
                instructions: "",
                category: .learning,
                rewardMinutes: 15,
                requiredProof: .text,
                adultSupervisionRequired: false,
                reading: ReadingSpec(bookTitle: "小王子", minMinutes: 20, chapterPlanText: ""),
                video: nil
            )
        )
        XCTAssertEqual(
            store.assignments.first { $0.id == assignment.id }?.task.reading?.bookTitle,
            "小王子"
        )

        XCTAssertTrue(
            store.updateTask(
                assignmentId: assignment.id,
                title: "阅读时间",
                instructions: "",
                category: .learning,
                rewardMinutes: 15,
                requiredProof: .text,
                adultSupervisionRequired: false,
                reading: nil,
                video: nil
            )
        )
        XCTAssertNil(store.assignments.first { $0.id == assignment.id }?.task.reading)
    }

    /// 旧版持久化 JSON（没有 reading / adultSupervisionRequired 字段）必须仍能解码。
    func testDecodingLegacyTaskTemplateWithoutNewFields() throws {
        let legacyJSON = """
        {
            "id": "\(UUID().uuidString)",
            "title": "阅读 15 分钟",
            "category": "learning",
            "difficulty": "easy",
            "rewardMinutes": 15,
            "instructions": "读一本书。",
            "requiredProof": "text"
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let template = try JSONDecoder().decode(TaskTemplate.self, from: data)
        XCTAssertNil(template.reading)
        XCTAssertFalse(template.needsAdultSupervision)
    }

    func testDecodingLegacyPackTaskTemplateWithoutExpectedMinutes() throws {
        let legacyJSON = """
        {
            "id": "legacy-chore",
            "title": "擦桌子",
            "instructions": "把餐桌擦干净。",
            "category": "home",
            "suggestedRewardMinutes": 10,
            "requiredProof": "text",
            "adultSupervisionRequired": false
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let template = try JSONDecoder().decode(PackTaskTemplate.self, from: data)
        XCTAssertNil(template.expectedMinutes)
        XCTAssertFalse(template.isCustom)
    }

    /// 家庭每日解锁上限硬边界：最低 15 分钟，最高 12 小时（720 分钟）。
    func testFamilyDailyLimitClampedToTwelveHours() {
        let store = LocalFamilyStore()

        store.applyFamilySetup(childName: "乐乐", dailyLimitMinutes: 10_000, keepStarterTasks: true)
        XCTAssertEqual(store.child.dailyLimitMinutes, 720)

        store.applyFamilySetup(childName: "乐乐", dailyLimitMinutes: 1, keepStarterTasks: true)
        XCTAssertEqual(store.child.dailyLimitMinutes, 15)

        store.applyFamilySetup(childName: "乐乐", dailyLimitMinutes: 120, keepStarterTasks: true)
        XCTAssertEqual(store.child.dailyLimitMinutes, 120)
    }

    /// 带阅读规格的任务经快照编码/解码后完整保留（持久化 round-trip）。
    func testReadingSpecSurvivesSnapshotRoundTrip() throws {
        let store = LocalFamilyStore()
        store.assignNewTask(
            title: "读《夏洛的网》",
            instructions: "读完说说学到了什么。",
            category: .learning,
            rewardMinutes: 20,
            requiredProof: .text,
            adultSupervisionRequired: false,
            reading: ReadingSpec(bookTitle: "夏洛的网", minMinutes: 30, chapterPlanText: "第 1-2 章")
        )

        let data = try JSONEncoder().encode(store.snapshot)
        let decoded = try JSONDecoder().decode(FamilyStoreSnapshot.self, from: data)
        let restored = try XCTUnwrap(decoded.assignments.last?.task.reading)
        XCTAssertEqual(restored.bookTitle, "夏洛的网")
        XCTAssertEqual(restored.minMinutes, 30)
        XCTAssertEqual(restored.chapterPlanText, "第 1-2 章")
    }
}
