import XCTest
@testable import OctoTeacher

/// 多孩子家庭的回归测试：v1→v2 数据迁移、按孩子分账、任务归属与清理。
final class LocalFamilyStoreMultiChildTests: XCTestCase {

    // MARK: - 数据迁移

    /// v1 旧持久化文件（单孩子 child 字段）必须能解码为 v2（children 数组）。
    func testLegacyV1SnapshotMigratesToChildrenArray() throws {
        let childId = UUID()
        let legacyJSON = """
        {
            "schemaVersion": 1,
            "child": {
                "id": "\(childId.uuidString)",
                "name": "乐乐",
                "age": 9,
                "dailyLimitMinutes": 60,
                "rewardBalanceMinutes": 25
            },
            "assignments": [],
            "growthPack": {
                "id": "\(UUID().uuidString)",
                "title": "今日成长计划",
                "summary": "按顺序完成",
                "steps": []
            },
            "rewards": [],
            "relatives": [],
            "suggestions": [],
            "events": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(FamilyStoreSnapshot.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(snapshot.children.count, 1)
        XCTAssertEqual(snapshot.children[0].name, "乐乐")
        XCTAssertEqual(snapshot.children[0].rewardBalanceMinutes, 25)
        XCTAssertEqual(snapshot.activeChildId, childId)
    }

    /// v2 快照编码/解码 round-trip 完整保留多孩子结构。
    func testV2SnapshotRoundTrip() throws {
        let store = LocalFamilyStore()
        store.addChild(name: "妹妹", age: 6)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(store.snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, FamilyStoreSnapshot.currentSchemaVersion)
        XCTAssertEqual(decoded.children.count, 2)
        XCTAssertEqual(decoded.activeChildId, store.activeChildId)
    }

    // MARK: - 孩子管理

    func testAddChildValidation() {
        let store = LocalFamilyStore()
        XCTAssertNil(store.addChild(name: "   ", age: 8), "空昵称不能添加")

        let added = store.addChild(name: "弟弟", age: 5)
        XCTAssertNotNil(added)
        XCTAssertEqual(store.children.count, 2)

        XCTAssertNil(store.addChild(name: "弟弟", age: 7), "重名不能添加")
    }

    func testSetActiveChildSwitchesChildView() throws {
        let store = LocalFamilyStore()
        let first = store.child
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 6))

        store.setActiveChild(second.id)
        XCTAssertEqual(store.child.id, second.id)
        XCTAssertEqual(store.child.name, "妹妹")

        // 切回第一个孩子。
        store.setActiveChild(first.id)
        XCTAssertEqual(store.child.id, first.id)
    }

    func testCannotRemoveLastChild() {
        let store = LocalFamilyStore()
        XCTAssertFalse(store.removeChild(store.child.id))
        XCTAssertEqual(store.children.count, 1)
    }

    func testRemoveChildCleansAssignmentsAndResetsActive() throws {
        let store = LocalFamilyStore()
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 6))
        store.setActiveChild(second.id)
        store.assignNewTask(
            title: "妹妹的任务",
            instructions: "",
            category: .home,
            rewardMinutes: 10,
            requiredProof: .text
        )
        XCTAssertEqual(store.assignments.filter { $0.childId == second.id }.count, 1)
        let stepCountBefore = store.growthPack.steps.count

        XCTAssertTrue(store.removeChild(second.id))
        XCTAssertTrue(store.assignments.allSatisfy { $0.childId != second.id })
        XCTAssertEqual(store.growthPack.steps.count, stepCountBefore - 1)
        // 被移除的孩子是活跃孩子时，自动切回第一个孩子。
        XCTAssertEqual(store.activeChildId, store.children[0].id)
        // 步骤顺序压缩后仍连续。
        XCTAssertEqual(store.growthPack.steps.map(\.order), Array(1...store.growthPack.steps.count))
    }

    // MARK: - 任务归属与展示过滤

    func testAssignDefaultsToActiveChildAndFiltersTodayTasks() throws {
        let store = LocalFamilyStore()
        let first = store.child
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 6))

        // 给第二个孩子布置（显式 childId）。
        let assignment = try XCTUnwrap(
            store.assignNewTask(
                title: "给妹妹的任务",
                instructions: "",
                category: .home,
                rewardMinutes: 10,
                requiredProof: .text,
                childId: second.id
            )
        )
        XCTAssertEqual(assignment.childId, second.id)

        // 活跃孩子是老大：今日任务里看不到妹妹的任务。
        XCTAssertEqual(store.activeChildId, first.id)
        XCTAssertFalse(store.todayTasks.contains { $0.title == "给妹妹的任务" })

        // 切到妹妹：能看到。
        store.setActiveChild(second.id)
        XCTAssertTrue(store.todayTasks.contains { $0.title == "给妹妹的任务" })
    }

    func testPackTemplatesAssignToExplicitChild() throws {
        let store = LocalFamilyStore()
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 6))
        let chores = try XCTUnwrap(ParentPackTemplateLibrary.group(for: .chores))

        let count = store.assignPackTemplates(Array(chores.templates.prefix(2)), packType: .chores, childId: second.id)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(store.assignments.filter { $0.childId == second.id }.count, 2)
    }

    // MARK: - 多孩子分账

    /// 批准时奖励必须记到任务所属孩子头上，即使当前活跃孩子是别人。
    func testApproveCreditsOwnerChildNotActiveChild() throws {
        let store = LocalFamilyStore()
        let first = store.child
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 6))

        let assignment = try XCTUnwrap(
            store.assignNewTask(
                title: "妹妹的阅读",
                instructions: "",
                category: .learning,
                rewardMinutes: 20,
                requiredProof: .text,
                childId: second.id
            )
        )
        store.setActiveChild(second.id)
        store.submit(assignment, text: "读完了")

        // 家长在老大的上下文里批准。
        store.setActiveChild(first.id)
        let submitted = try XCTUnwrap(store.assignments.first { $0.id == assignment.id })
        let reward = try XCTUnwrap(store.approve(submitted))

        XCTAssertEqual(reward.childId, second.id)
        XCTAssertEqual(store.children.first { $0.id == second.id }?.rewardBalanceMinutes, 20)
        XCTAssertEqual(store.children.first { $0.id == first.id }?.rewardBalanceMinutes, first.rewardBalanceMinutes, "老大余额不能变")
    }

    func testCreditBalancePerChild() throws {
        let store = LocalFamilyStore()
        let first = store.child
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 6))

        let assignment = try XCTUnwrap(
            store.assignNewTask(
                title: "妹妹的任务",
                instructions: "",
                category: .home,
                rewardMinutes: 15,
                requiredProof: .text,
                childId: second.id
            )
        )
        store.submit(assignment, text: "做完了")

        // 妹妹有 15 分钟待批准；老大没有。
        XCTAssertEqual(store.creditBalance(for: second.id).pendingMinutes, 15)
        XCTAssertEqual(store.creditBalance(for: first.id).pendingMinutes, 0)
    }

    // MARK: - 步骤解锁按孩子独立

    func testStepUnlockSequencesAreIndependentPerChild() throws {
        let store = LocalFamilyStore()
        // 老大的种子任务第一步未批准。
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 6))
        let assignment = try XCTUnwrap(
            store.assignNewTask(
                title: "妹妹的第一步",
                instructions: "",
                category: .home,
                rewardMinutes: 10,
                requiredProof: .text,
                childId: second.id
            )
        )
        let step = try XCTUnwrap(store.growthPack.steps.first { $0.assignmentId == assignment.id })
        // 尽管老大前面有未批准的步骤，妹妹的第一步应当是解锁的。
        XCTAssertTrue(store.isStepUnlocked(step))
        // steps(for:) 只返回该孩子自己的步骤。
        XCTAssertEqual(store.steps(for: second.id).count, 1)
    }
}
