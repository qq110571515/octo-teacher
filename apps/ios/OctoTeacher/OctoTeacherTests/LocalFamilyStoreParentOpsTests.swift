import XCTest
@testable import OctoTeacher

/// 家长布置 / 编辑 / 删除任务与家庭数据持久化的回归测试。
final class LocalFamilyStoreParentOpsTests: XCTestCase {

    // MARK: - 布置新任务

    func testParentTaskStarterPresetsCoverCommonFamilyScenes() {
        XCTAssertEqual(
            ParentTaskStarterPreset.allCases.map(\.id),
            ["reading20", "outdoorPlay", "tidyDesk", "sleepReady"]
        )

        XCTAssertEqual(ParentTaskStarterPreset.reading20.kind, .reading)
        XCTAssertEqual(ParentTaskStarterPreset.reading20.category, .learning)
        XCTAssertEqual(ParentTaskStarterPreset.reading20.readingMinMinutes, 20)

        XCTAssertEqual(ParentTaskStarterPreset.outdoorPlay.kind, .outdoor)
        XCTAssertEqual(ParentTaskStarterPreset.outdoorPlay.category, .health)
        XCTAssertEqual(ParentTaskStarterPreset.outdoorPlay.requiredProof, .photo)
        XCTAssertTrue(ParentTaskStarterPreset.outdoorPlay.needsAdult)

        XCTAssertEqual(ParentTaskStarterPreset.tidyDesk.category, .home)
        XCTAssertEqual(ParentTaskStarterPreset.sleepReady.category, .home)
    }

    func testAssignNewTaskAppendsAssignmentAndGrowthStep() throws {
        let store = LocalFamilyStore()
        let initialCount = store.assignments.count

        let assignment = try XCTUnwrap(
            store.assignNewTask(
                title: "练琴 20 分钟",
                instructions: "弹完本周曲目，录一句感想。",
                category: .creative,
                rewardMinutes: 20,
                requiredProof: .text
            )
        )

        XCTAssertEqual(store.assignments.count, initialCount + 1)
        XCTAssertEqual(assignment.status, .open)
        XCTAssertEqual(assignment.task.title, "练琴 20 分钟")

        // 成长包同步追加一步，顺序连续。
        let step = try XCTUnwrap(store.growthPack.steps.first { $0.assignmentId == assignment.id })
        XCTAssertEqual(step.order, store.growthPack.steps.count)
        XCTAssertEqual(step.rewardMinutes, 20)

        // 事件流记录布置动作。
        XCTAssertEqual(store.recentGrowthRecords().first?.kind, .taskAssigned)
    }

    func testAssignNewTaskRejectsEmptyTitleOrNonPositiveReward() {
        let store = LocalFamilyStore()
        let initialCount = store.assignments.count

        XCTAssertNil(store.assignNewTask(
            title: "   ",
            instructions: "",
            category: .home,
            rewardMinutes: 15,
            requiredProof: .text
        ))
        XCTAssertNil(store.assignNewTask(
            title: "有效标题",
            instructions: "",
            category: .home,
            rewardMinutes: 0,
            requiredProof: .text
        ))
        XCTAssertEqual(store.assignments.count, initialCount)
    }

    // MARK: - 编辑任务

    func testUpdateTaskChangesTemplateAndGrowthStep() throws {
        let store = LocalFamilyStore()
        let target = store.assignments[0]

        let updated = store.updateTask(
            assignmentId: target.id,
            title: "阅读 30 分钟",
            instructions: "读完写两句感想。",
            category: .learning,
            rewardMinutes: 30,
            requiredProof: .text,
            adultSupervisionRequired: false,
            reading: nil,
            video: nil
        )

        XCTAssertTrue(updated)
        XCTAssertEqual(store.assignments[0].task.title, "阅读 30 分钟")
        XCTAssertEqual(store.assignments[0].task.rewardMinutes, 30)

        let step = try XCTUnwrap(store.growthPack.steps.first { $0.assignmentId == target.id })
        XCTAssertEqual(step.title, "阅读 30 分钟")
        XCTAssertEqual(step.rewardMinutes, 30)
    }

    func testUpdateTaskCanSetAndClearVideoSpecAndAdultSupervision() throws {
        let store = LocalFamilyStore()
        let assignment = try XCTUnwrap(
            store.assignNewTask(
                title: "看学习视频",
                instructions: "",
                category: .learning,
                rewardMinutes: 15,
                requiredProof: .text,
                video: VideoSpec(urlString: "https://www.youtube.com/watch?v=old", platformLabel: "YouTube", minWatchMinutes: 10)
            )
        )

        XCTAssertTrue(store.updateTask(
            assignmentId: assignment.id,
            title: "看新的学习视频",
            instructions: "看完说一句学到了什么。",
            category: .learning,
            rewardMinutes: 20,
            requiredProof: .text,
            adultSupervisionRequired: true,
            reading: nil,
            video: VideoSpec(urlString: "https://www.youtube.com/watch?v=new", platformLabel: "YouTube", minWatchMinutes: 20)
        ))

        let updated = try XCTUnwrap(store.assignments.first { $0.id == assignment.id })
        XCTAssertEqual(updated.task.video?.urlString, "https://www.youtube.com/watch?v=new")
        XCTAssertEqual(updated.task.video?.minWatchMinutes, 20)
        XCTAssertTrue(updated.task.needsAdultSupervision)

        XCTAssertTrue(store.updateTask(
            assignmentId: assignment.id,
            title: "改成普通任务",
            instructions: "",
            category: .home,
            rewardMinutes: 10,
            requiredProof: .text,
            adultSupervisionRequired: false,
            reading: nil,
            video: nil
        ))

        let cleared = try XCTUnwrap(store.assignments.first { $0.id == assignment.id })
        XCTAssertNil(cleared.task.video)
        XCTAssertFalse(cleared.task.needsAdultSupervision)
    }

    func testSubmittedOrApprovedTaskCannotBeEditedOrRemoved() {
        let store = LocalFamilyStore()
        store.submit(store.assignments[0], text: "done")

        XCTAssertFalse(store.canParentModify(store.assignments[0]))
        XCTAssertFalse(store.updateTask(
            assignmentId: store.assignments[0].id,
            title: "改名",
            instructions: "",
            category: .home,
            rewardMinutes: 10,
            requiredProof: .text,
            adultSupervisionRequired: false,
            reading: nil,
            video: nil
        ))
        XCTAssertFalse(store.removeAssignment(store.assignments[0].id))

        _ = store.approve(store.assignments[0])
        XCTAssertFalse(store.canParentModify(store.assignments[0]))
        XCTAssertFalse(store.removeAssignment(store.assignments[0].id))
    }

    func testCancelAssignmentKeepsAuditButRemovesFromActiveViews() throws {
        let store = LocalFamilyStore()
        let target = try XCTUnwrap(store.assignments.first)
        let initialStepCount = store.growthPack.steps.count

        XCTAssertTrue(store.cancelAssignment(target.id, actor: .guardian))

        let cancelled = try XCTUnwrap(store.assignments.first { $0.id == target.id })
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertEqual(store.growthPack.steps.count, initialStepCount, "撤销保留步骤历史，不做真删除")
        XCTAssertFalse(store.todayTasks.contains { $0.id == target.id })
        XCTAssertFalse(store.steps(for: target.childId).contains { $0.assignmentId == target.id })
        XCTAssertEqual(store.recentGrowthRecords().first?.kind, .taskCancelled)
        XCTAssertEqual(store.todayCompletion.total, store.assignments.count - 1)
    }

    func testApprovedAssignmentCannotBeCancelled() throws {
        let store = LocalFamilyStore()
        let target = try XCTUnwrap(store.assignments.first)

        _ = store.approve(target)

        XCTAssertFalse(store.cancelAssignment(target.id, actor: .guardian))
        XCTAssertEqual(store.assignments.first { $0.id == target.id }?.status, .approved)
    }

    func testChildCanWithdrawSubmittedProofForRetry() throws {
        let store = LocalFamilyStore()
        let target = try XCTUnwrap(store.assignments.first)
        store.submit(target, text: "done")

        XCTAssertTrue(store.withdrawSubmittedAssignment(target.id))

        let updated = try XCTUnwrap(store.assignments.first { $0.id == target.id })
        XCTAssertEqual(updated.status, .open)
        XCTAssertEqual(updated.proof.status, .drafting)
        XCTAssertNil(updated.aiReview)
        XCTAssertEqual(store.recentGrowthRecords().first?.kind, .taskCancelled)
    }

    func testRejectedTaskCanBeEditedForRetry() {
        let store = LocalFamilyStore()
        store.submit(store.assignments[0], text: "done")
        store.reject(store.assignments[0], reason: .incomplete)

        XCTAssertTrue(store.canParentModify(store.assignments[0]))
        XCTAssertTrue(store.updateTask(
            assignmentId: store.assignments[0].id,
            title: "阅读 10 分钟（降低难度）",
            instructions: "",
            category: .learning,
            rewardMinutes: 10,
            requiredProof: .text,
            adultSupervisionRequired: false,
            reading: nil,
            video: nil
        ))
    }

    // MARK: - 删除任务

    func testRemoveAssignmentAlsoRemovesStepAndCompactsOrder() throws {
        let store = LocalFamilyStore()
        let removed = store.assignments[1]

        XCTAssertTrue(store.removeAssignment(removed.id))

        XCTAssertNil(store.assignments.first { $0.id == removed.id })
        XCTAssertNil(store.growthPack.steps.first { $0.assignmentId == removed.id })
        // 剩余步骤顺序压缩为 1..n。
        XCTAssertEqual(store.growthPack.steps.map(\.order), Array(1...store.growthPack.steps.count))
    }

    // MARK: - 首次设置

    func testApplyFamilySetupRenamesChildAndCanClearStarterTasks() {
        let store = LocalFamilyStore()
        store.applyFamilySetup(childName: "乐乐", dailyLimitMinutes: 90, keepStarterTasks: false)

        XCTAssertEqual(store.child.name, "乐乐")
        XCTAssertEqual(store.child.dailyLimitMinutes, 90)
        XCTAssertTrue(store.assignments.isEmpty)
        XCTAssertTrue(store.growthPack.steps.isEmpty)
    }

    func testApplyFamilySetupKeepsStarterTasksWhenAsked() {
        let store = LocalFamilyStore()
        let count = store.assignments.count
        store.applyFamilySetup(childName: "小雨", dailyLimitMinutes: 60, keepStarterTasks: true)

        XCTAssertEqual(store.assignments.count, count)
        XCTAssertEqual(store.child.name, "小雨")
    }

    // MARK: - 照片证明

    func testPhotoProofRequiresFileNameToSubmit() {
        let store = LocalFamilyStore()
        _ = store.assignNewTask(
            title: "收拾房间",
            instructions: "拍一张收拾好的照片。",
            category: .home,
            rewardMinutes: 15,
            requiredProof: .photo
        )
        let assignment = store.assignments.last!
        XCTAssertEqual(assignment.task.requiredProof, .photo)

        let empty = ProofDraft(kind: .photo, text: "", photoPlaceholderName: nil, photoFileName: nil, status: .drafting)
        store.submit(assignment, proof: empty)
        XCTAssertEqual(store.assignments.last!.status, .open, "没有照片不能提交")

        let withPhoto = ProofDraft(kind: .photo, text: "收好啦", photoPlaceholderName: nil, photoFileName: "proof-abc.jpg", status: .drafting)
        store.submit(assignment, proof: withPhoto)
        XCTAssertEqual(store.assignments.last!.status, .submitted)
        XCTAssertEqual(store.assignments.last!.proof.photoFileName, "proof-abc.jpg")
    }

    // MARK: - 持久化

    /// 内存持久化桩：验证 store 在状态变更后保存、init 时恢复。
    private final class InMemoryPersistence: FamilyStorePersisting {
        var stored: FamilyStoreSnapshot?
        var saveCount = 0

        func load() -> FamilyStoreSnapshot? { stored }
        func save(_ snapshot: FamilyStoreSnapshot) {
            stored = snapshot
            saveCount += 1
        }
    }

    func testMutationsPersistAndRestoreAcrossRelaunch() throws {
        let persistence = InMemoryPersistence()

        // 第一次启动：种子数据 + 家长布置 + 孩子提交 + 家长批准。
        let first = LocalFamilyStore(persistence: persistence)
        _ = first.assignNewTask(
            title: "浇花",
            instructions: "",
            category: .home,
            rewardMinutes: 5,
            requiredProof: .text
        )
        first.submit(first.assignments[0], text: "读完了")
        _ = first.approve(first.assignments[0])
        XCTAssertGreaterThan(persistence.saveCount, 0)

        // 模拟 App 重启：从持久化恢复。
        let second = LocalFamilyStore(persistence: persistence)
        XCTAssertEqual(second.child.rewardBalanceMinutes, first.child.rewardBalanceMinutes)
        XCTAssertEqual(second.assignments.count, first.assignments.count)
        XCTAssertEqual(second.assignments[0].status, .approved)
        XCTAssertTrue(second.assignments.contains { $0.task.title == "浇花" })
        XCTAssertEqual(second.rewards.count, first.rewards.count)
        XCTAssertEqual(second.events.count, first.events.count)
    }

    func testFileRoundTripRestoresSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("octoteacher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("family.json")

        let persistence = FileFamilyStorePersistence(fileURL: fileURL)
        let store = LocalFamilyStore(persistence: persistence)
        store.submit(store.assignments[0], text: "完成")
        _ = store.approve(store.assignments[0])

        let restored = try XCTUnwrap(persistence.load())
        XCTAssertEqual(restored.children[0].rewardBalanceMinutes, store.child.rewardBalanceMinutes)
        XCTAssertEqual(restored.assignments[0].status, .approved)
        XCTAssertEqual(restored.schemaVersion, FamilyStoreSnapshot.currentSchemaVersion)
    }

    func testCorruptedFileFallsBackToSeed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("octoteacher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("family.json")
        try Data("not json at all".utf8).write(to: fileURL)

        let store = LocalFamilyStore(persistence: FileFamilyStorePersistence(fileURL: fileURL))
        XCTAssertEqual(store.assignments.count, 3, "损坏文件应回退到种子数据")
        XCTAssertEqual(store.child.rewardBalanceMinutes, 0)
    }
}
