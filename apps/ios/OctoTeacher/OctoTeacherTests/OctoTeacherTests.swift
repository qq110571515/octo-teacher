import XCTest
@testable import OctoTeacher

final class OctoTeacherTests: XCTestCase {
    func testDefaultFamilySeedLooksLikeARealChineseFirstRun() {
        let store = LocalFamilyStore()
        let visibleSeedText = (
            [store.child.name, store.growthPack.title, store.growthPack.summary]
                + store.assignments.flatMap { [$0.task.title, $0.task.instructions] }
        ).joined(separator: "\n")

        XCTAssertFalse(visibleSeedText.contains("Alex"))
        XCTAssertFalse(visibleSeedText.contains("Read for 15 minutes"))
        XCTAssertFalse(visibleSeedText.contains("Clean your desk"))
        XCTAssertFalse(visibleSeedText.contains("Exercise for 20 minutes"))
        XCTAssertFalse(visibleSeedText.contains("Daily Habits Pack"))
        XCTAssertTrue(store.assignments.contains { $0.task.title == "阅读 15 分钟" })
        XCTAssertTrue(store.assignments.contains { $0.task.title == "整理书桌" })
        XCTAssertTrue(store.assignments.contains { $0.task.title == "运动 20 分钟" })
        XCTAssertEqual(store.growthPack.title, "今日成长计划")
    }

    func testApprovingTaskAddsRewardMinutes() throws {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        XCTAssertEqual(store.child.rewardBalanceMinutes, 0)

        let reward = try XCTUnwrap(store.approve(assignment))

        XCTAssertEqual(reward.minutes, assignment.task.rewardMinutes)
        XCTAssertEqual(store.child.rewardBalanceMinutes, assignment.task.rewardMinutes)
        XCTAssertEqual(store.assignments[0].status, .approved)
    }

    func testStartingRewardSessionSpendsMinutesAndUnlocks() {
        let store = LocalFamilyStore()
        let screenTimeController = MockScreenTimeController()
        _ = store.approve(store.assignments[0])

        StartRewardSessionUseCase(store: store, screenTimeController: screenTimeController)(minutes: 15)

        XCTAssertEqual(store.child.rewardBalanceMinutes, 0)
        XCTAssertEqual(screenTimeController.shieldState, .unlocked)
        XCTAssertNotNil(screenTimeController.unlockEndsAt)
    }

    func testMockScreenTimeRelocksAfterUnlockExpires() {
        let screenTimeController = MockScreenTimeController()

        screenTimeController.unshield(for: 15)
        XCTAssertEqual(screenTimeController.shieldState, .unlocked)

        let later = Calendar.current.date(byAdding: .minute, value: 16, to: Date())!
        screenTimeController.tick(now: later)

        XCTAssertEqual(screenTimeController.shieldState, .locked)
        XCTAssertNil(screenTimeController.unlockEndsAt)
    }

    // MARK: - 证明提交闭环

    func testSubmittingTextProofMovesTaskToSubmitted() {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        let proof = ProofDraft(kind: .text, text: "Read a chapter", photoPlaceholderName: nil, status: .drafting)
        store.submit(assignment, proof: proof)

        XCTAssertEqual(store.assignments[0].status, .submitted)
        XCTAssertEqual(store.assignments[0].proof.status, .submitted)
        XCTAssertEqual(store.assignments[0].proof.text, "Read a chapter")
    }

    func testEmptyProofIsRejectedAndTaskStaysOpen() {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        store.submit(assignment, proof: .empty)

        XCTAssertEqual(store.assignments[0].status, .open)
        XCTAssertEqual(store.assignments[0].proof.status, .empty)
    }

    func testPhotoProofRequiresRealPhotoFile() {
        let store = LocalFamilyStore()
        // 第二个种子任务（整理书桌）要求真实照片证明。
        let assignment = store.assignments[1]
        XCTAssertEqual(assignment.task.requiredProof, .photo)

        let emptyPhoto = ProofDraft(kind: .photo, text: "", photoPlaceholderName: nil, photoFileName: nil, status: .drafting)
        store.submit(assignment, proof: emptyPhoto)
        XCTAssertEqual(store.assignments[1].status, .open)

        let withPhoto = ProofDraft(kind: .photo, text: "", photoPlaceholderName: nil, photoFileName: "proof-desk.jpg", status: .drafting)
        store.submit(assignment, proof: withPhoto)
        XCTAssertEqual(store.assignments[1].status, .submitted)
    }

    /// 旧的图片占位证明仍保持原有校验行为（兼容旧演示任务）。
    func testPhotoPlaceholderProofStillRequiresPlaceholderName() {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        let emptyPlaceholder = ProofDraft(kind: .photoPlaceholder, text: "", photoPlaceholderName: nil, status: .drafting)
        XCTAssertFalse(emptyPlaceholder.hasContent)

        let withRealPhoto = ProofDraft(kind: .photoPlaceholder, text: "", photoPlaceholderName: nil, photoFileName: "proof-real.jpg", status: .drafting)
        XCTAssertTrue(withRealPhoto.hasContent, "旧图片占位任务也应优先接受真实照片")

        let withPlaceholder = ProofDraft(kind: .photoPlaceholder, text: "", photoPlaceholderName: "local-photo-placeholder", status: .drafting)
        XCTAssertTrue(withPlaceholder.hasContent)
        store.submit(assignment, proof: withPlaceholder)
        XCTAssertEqual(store.assignments[0].status, .submitted)
    }

    // MARK: - 成长积分余额快照

    func testCreditBalanceTracksPendingThenAvailable() {
        let store = LocalFamilyStore()
        XCTAssertEqual(store.creditBalance, .zero)

        let assignment = store.assignments[0]
        store.submit(assignment, text: "done")

        XCTAssertEqual(store.creditBalance.pendingMinutes, assignment.task.rewardMinutes)
        XCTAssertEqual(store.creditBalance.availableMinutes, 0)

        _ = store.approve(store.assignments[0])

        XCTAssertEqual(store.creditBalance.pendingMinutes, 0)
        XCTAssertEqual(store.creditBalance.availableMinutes, assignment.task.rewardMinutes)
        XCTAssertEqual(store.creditBalance.lifetimeEarnedMinutes, assignment.task.rewardMinutes)
    }

    // MARK: - 成长包步骤解锁

    func testGrowthPackStepsUnlockInOrder() {
        // 默认是自由模式；本测试显式开启顺序模式，覆盖未来闯关型包的语义。
        let store = LocalFamilyStore()
        store.growthPack.sequencing = .sequential
        let steps = store.growthPack.steps
        XCTAssertEqual(steps.count, store.assignments.count)

        // 第一步可执行，后续步骤先锁定。
        XCTAssertEqual(store.progress(for: steps[0]), .active)
        XCTAssertEqual(store.progress(for: steps[1]), .locked)

        // 提交第一步 -> submitted，第二步仍锁定。
        store.submit(store.assignments[0], text: "done")
        XCTAssertEqual(store.progress(for: steps[0]), .submitted)
        XCTAssertEqual(store.progress(for: steps[1]), .locked)

        // 批准第一步 -> approved，第二步解锁。
        _ = store.approve(store.assignments[0])
        XCTAssertEqual(store.progress(for: steps[0]), .approved)
        XCTAssertEqual(store.progress(for: steps[1]), .active)
    }

    // MARK: - 家长批准与家庭参与台

    /// 重复批准同一任务不应重复发放成长积分（幂等保护）。
    func testApprovingTwiceDoesNotDoubleGrant() throws {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        let first = try XCTUnwrap(store.approve(assignment))
        XCTAssertEqual(store.child.rewardBalanceMinutes, first.minutes)
        XCTAssertEqual(first.sourceAssignmentId, assignment.id)

        let second = store.approve(store.assignments[0])
        XCTAssertNil(second, "已批准任务再次批准应返回 nil")
        XCTAssertEqual(store.child.rewardBalanceMinutes, first.minutes, "余额不应被重复发放")
        XCTAssertEqual(store.rewards.count, 1, "不应产生第二条奖励记录")
    }

    /// 云冲突可把任务状态恢复为待审核，但同一 assignment 的奖励来源仍只能结算一次。
    func testApprovalAfterCloudStatusRollbackDoesNotDoubleGrant() throws {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]
        let first = try XCTUnwrap(store.approve(assignment))
        let eventCount = store.events.count
        let subjectProgress = store.subjectProgress

        store.assignments[0].status = .submitted
        let second = store.approve(store.assignments[0])

        XCTAssertNil(second)
        XCTAssertEqual(store.assignments[0].status, .approved)
        XCTAssertEqual(store.child.rewardBalanceMinutes, first.minutes)
        XCTAssertEqual(store.rewards.count, 1)
        XCTAssertEqual(store.events.count, eventCount)
        XCTAssertEqual(store.subjectProgress, subjectProgress)

        let restored = try JSONDecoder().decode(
            FamilyStoreSnapshot.self,
            from: JSONEncoder().encode(store.snapshot)
        )
        XCTAssertEqual(restored.rewards.first?.sourceAssignmentId, assignment.id)
    }

    func testLegacyRewardGrantDecodesWithoutAssignmentSource() throws {
        let rewardID = UUID()
        let childID = UUID()
        let data = Data("""
        {
          "id":"\(rewardID.uuidString)",
          "childId":"\(childID.uuidString)",
          "minutes":20,
          "reason":"Legacy task reward",
          "grantedAt":0
        }
        """.utf8)

        let reward = try JSONDecoder().decode(RewardGrant.self, from: data)

        XCTAssertEqual(reward.id, rewardID)
        XCTAssertNil(reward.sourceAssignmentId)
    }

    /// v8 及更早快照没有 sourceAssignmentId。恢复后即使云端把任务退回待审核，也不能重复发奖。
    func testLegacySnapshotRewardMigratesAndCloudRollbackApprovalDoesNotDoubleGrant() throws {
        let original = LocalFamilyStore()
        let assignment = original.assignments[0]
        let firstReward = try XCTUnwrap(original.approve(assignment))
        var legacySnapshot = original.snapshot
        legacySnapshot.assignments[0].status = .submitted

        let encoded = try JSONEncoder().encode(legacySnapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var legacyRewards = try XCTUnwrap(object["rewards"] as? [[String: Any]])
        legacyRewards[0].removeValue(forKey: "sourceAssignmentId")
        object["rewards"] = legacyRewards
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decodedLegacySnapshot = try JSONDecoder().decode(FamilyStoreSnapshot.self, from: legacyData)
        XCTAssertNil(decodedLegacySnapshot.rewards.first?.sourceAssignmentId)

        let persistence = LegacyRewardSnapshotPersistence(snapshot: decodedLegacySnapshot)
        let restored = LocalFamilyStore(persistence: persistence)
        let eventCount = restored.events.count
        let subjectProgress = restored.subjectProgress

        XCTAssertEqual(restored.rewards.first?.sourceAssignmentId, assignment.id)
        XCTAssertNil(restored.approve(restored.assignments[0]))
        XCTAssertEqual(restored.assignments[0].status, .approved)
        XCTAssertEqual(restored.child.rewardBalanceMinutes, firstReward.minutes)
        XCTAssertEqual(restored.rewards.count, 1)
        XCTAssertEqual(restored.events.count, eventCount)
        XCTAssertEqual(restored.subjectProgress, subjectProgress)
        XCTAssertEqual(persistence.snapshot?.rewards.first?.sourceAssignmentId, assignment.id)
    }

    /// 同一孩子存在两个同名同分任务时，旧奖励来源无法安全判断，迁移必须保持保守。
    func testLegacyRewardMigrationDoesNotMergeAmbiguousAssignments() throws {
        let original = LocalFamilyStore()
        let assignment = original.assignments[0]
        _ = try XCTUnwrap(original.approve(assignment))
        var legacySnapshot = original.snapshot
        legacySnapshot.rewards[0].sourceAssignmentId = nil
        var duplicate = assignment
        duplicate = TaskAssignment(
            id: UUID(),
            childId: duplicate.childId,
            task: duplicate.task,
            date: duplicate.date,
            status: .submitted,
            proof: duplicate.proof
        )
        legacySnapshot.assignments.append(duplicate)

        let persistence = LegacyRewardSnapshotPersistence(snapshot: legacySnapshot)
        let restored = LocalFamilyStore(persistence: persistence)

        XCTAssertNil(restored.rewards.first?.sourceAssignmentId)
    }

    /// 驳回任务不发任何成长积分，并记录原因，孩子可重做。
    func testRejectingGrantsNoCreditAndRecordsReason() {
        let store = LocalFamilyStore()
        store.submit(store.assignments[0], text: "done")

        store.reject(store.assignments[0], reason: .proofUnclear)

        XCTAssertEqual(store.assignments[0].status, .rejected)
        XCTAssertEqual(store.assignments[0].rejectionReason, .proofUnclear)
        XCTAssertEqual(store.assignments[0].proof.status, .drafting)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 0, "驳回不应发成长积分")
        XCTAssertEqual(store.creditBalance.lifetimeEarnedMinutes, 0)
        XCTAssertTrue(store.rewards.isEmpty)
    }

    /// 批准会写入一条事件摘要，进入最近成长记录。
    func testApprovalAppendsEventSummary() throws {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]

        _ = try XCTUnwrap(store.approve(assignment))

        let records = store.recentGrowthRecords()
        XCTAssertEqual(records.first?.kind, .taskApproved)
        XCTAssertEqual(records.first?.minutes, assignment.task.rewardMinutes)
    }

    /// 亲友不能直接解锁设备：用例永远返回 false，且设备保持锁定。
    func testRelativeCannotUnlockDevice() {
        let store = LocalFamilyStore()
        let screenTimeController = MockScreenTimeController()
        let relative = store.relatives[0]

        let useCase = RelativeDeviceUnlockRequestUseCase(screenTimeController: screenTimeController)
        let unlocked = useCase(from: relative, minutes: 30)

        XCTAssertFalse(unlocked, "亲友请求解锁设备必须被拒绝")
        XCTAssertEqual(screenTimeController.shieldState, .locked)
        XCTAssertNil(screenTimeController.unlockEndsAt)
    }

    /// 任何亲友的能力都不允许发成长积分或解锁设备（安全边界恒为 false）。
    func testNoRelativeCanGrantCreditOrUnlockDevice() {
        let store = LocalFamilyStore()
        let summary = store.relativeParticipationSummary

        XCTAssertFalse(summary.anyRelativeCanGrantCredit)
        XCTAssertFalse(summary.anyRelativeCanUnlockDevice)
        for relative in store.relatives {
            XCTAssertFalse(relative.capability.canApproveTasks)
            XCTAssertFalse(relative.capability.canGrantCredit)
            XCTAssertFalse(relative.capability.canUnlockDevice)
        }
    }

    /// 亲友留建议只写入建议占位，绝不发成长积分、不改任务状态。
    func testRelativeSuggestionDoesNotGrantCreditOrChangeTasks() {
        let store = LocalFamilyStore()
        let relative = store.relatives[0]
        XCTAssertTrue(relative.capability.canSuggest)

        let ok = store.relativeSuggest(from: relative, message: "做得好，继续加油")

        XCTAssertTrue(ok)
        XCTAssertEqual(store.suggestions.count, 1)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 0, "建议不应发成长积分")
        XCTAssertEqual(store.assignments[0].status, .open, "建议不应改变任务状态")
        XCTAssertEqual(store.recentGrowthRecords().first?.kind, .relativeSuggested)
    }

    /// 仅可查看的亲友不能留建议。
    func testViewOnlyRelativeCannotSuggest() throws {
        let store = LocalFamilyStore()
        let viewOnly = try XCTUnwrap(store.relatives.first { !$0.capability.canSuggest })

        let ok = store.relativeSuggest(from: viewOnly, message: "想留一句")

        XCTAssertFalse(ok)
        XCTAssertTrue(store.suggestions.isEmpty)
    }

    // MARK: - 今日任务展示模型

    func testTodayTasksMirrorAssignments() {
        let store = LocalFamilyStore()
        let tasks = store.todayTasks

        XCTAssertEqual(tasks.count, store.assignments.count)
        XCTAssertEqual(tasks[0].id, store.assignments[0].id)
        XCTAssertEqual(tasks[0].status, .open)

        store.submit(store.assignments[0], text: "done")
        XCTAssertEqual(store.todayTasks[0].status, .submitted)
        XCTAssertEqual(store.todayTasks[0].proofStatus, .submitted)
    }

    // MARK: - 屏幕时间会话硬化

    /// 固定时间锚点，保证会话测试完全确定。
    private let sessionAnchor = Date(timeIntervalSince1970: 1_700_000_000)

    /// 余额不足：不扣成长积分、不解锁、保持锁定。
    func testInsufficientBalanceDoesNotSpendOrUnlock() {
        let store = LocalFamilyStore()
        let controller = MockScreenTimeController()
        XCTAssertEqual(store.child.rewardBalanceMinutes, 0)

        let result = StartRewardSessionUseCase(store: store, screenTimeController: controller)(minutes: 15)

        XCTAssertEqual(result, .insufficientBalance)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 0)
        XCTAssertEqual(controller.sessionStatus, .locked)
        XCTAssertEqual(controller.shieldState, .locked)
        XCTAssertNil(controller.unlockEndsAt)
    }

    /// 非法分钟数（<= 0）：不扣成长积分。
    func testInvalidMinutesDoesNotSpend() {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 60
        let controller = MockScreenTimeController()

        let result = StartRewardSessionUseCase(store: store, screenTimeController: controller)(minutes: 0)

        XCTAssertEqual(result, .invalidMinutes)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 60)
        XCTAssertEqual(controller.sessionStatus, .locked)
    }

    /// 开启会话进入 active，并返回计划到期时间。
    func testStartingSessionEntersActiveWithEndsAt() {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 60
        let controller = MockScreenTimeController()

        let result = StartRewardSessionUseCase(store: store, screenTimeController: controller)(
            minutes: 15,
            now: sessionAnchor
        )

        XCTAssertEqual(result, .started(endsAt: sessionAnchor.addingTimeInterval(15 * 60)))
        XCTAssertEqual(store.child.rewardBalanceMinutes, 45)
        XCTAssertEqual(controller.sessionStatus, .active)
        XCTAssertEqual(controller.shieldState, .unlocked)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.kind, .startUnlock)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.status, .succeeded)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.requestedMinutes, 15)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.plannedEndsAt, sessionAnchor.addingTimeInterval(15 * 60))
    }

    /// 真实 Screen Time 执行面成功后，本地会话账本接管 active 状态并记录成功回执。
    func testExternalScreenTimeSuccessAdoptsLocalSessionAndSpendsCredit() {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 60
        let controller = MockScreenTimeController()
        let expectedEndsAt = sessionAnchor.addingTimeInterval(15 * 60)
        var externalStartCallCount = 0

        let result = StartRewardSessionUseCase(store: store, screenTimeController: controller)(
            minutes: 15,
            now: sessionAnchor,
            externalDeviceStart: { minutes, now in
                externalStartCallCount += 1
                XCTAssertEqual(minutes, 15)
                XCTAssertEqual(now, self.sessionAnchor)
                return expectedEndsAt
            }
        )

        XCTAssertEqual(result, .started(endsAt: expectedEndsAt))
        XCTAssertEqual(externalStartCallCount, 1)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 45)
        XCTAssertEqual(controller.sessionStatus, .active)
        XCTAssertEqual(controller.unlockEndsAt, expectedEndsAt)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.kind, .startUnlock)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.status, .succeeded)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.plannedEndsAt, expectedEndsAt)
    }

    /// 真实 Screen Time 执行面失败时，扣掉的成长积分必须回滚，并留下设备命令失败回执。
    func testExternalScreenTimeFailureRollsBackCreditAndRecordsFailure() {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 60
        let controller = MockScreenTimeController()
        var relockCalled = false

        let result = StartRewardSessionUseCase(store: store, screenTimeController: controller)(
            minutes: 15,
            now: sessionAnchor,
            externalDeviceStart: { _, _ in
                throw UnlockError.deviceCommandFailed
            },
            externalDeviceRelock: {
                relockCalled = true
            }
        )

        XCTAssertEqual(result, .deviceFailureRolledBack)
        XCTAssertTrue(relockCalled)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 60)
        XCTAssertEqual(controller.sessionStatus, .locked)
        XCTAssertNil(controller.unlockEndsAt)
        XCTAssertTrue(controller.receipts.isEmpty)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.kind, .startUnlock)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.status, .failed)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.failureReason, .deviceCommandFailed)
    }

    /// 真实执行面已经打开 App，但本地采用失败时，整个奖励事务未提交，
    /// 调用方必须保留精准 App 凭据供孩子重试。
    func testConcurrentAdoptionFailureDoesNotCommitTransaction() throws {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 60
        let controller = MockScreenTimeController()
        let sessionID = UUID()
        let expectedEndsAt = sessionAnchor.addingTimeInterval(15 * 60)
        try controller.adoptConcurrentExternalUnlock(
            sessionID: sessionID,
            minutes: 15,
            now: sessionAnchor,
            endsAt: expectedEndsAt
        )
        var relockedSessionID: UUID?
        var transactionCommitCount = 0

        let result = StartRewardSessionUseCase(store: store, screenTimeController: controller)(
            minutes: 15,
            now: sessionAnchor,
            concurrentExternalDeviceStart: { _, _ in
                ScreenTimeExternalSession(id: sessionID, endsAt: expectedEndsAt)
            },
            concurrentExternalDeviceRelock: { relockedSessionID = $0 },
            transactionCommitted: { transactionCommitCount += 1 }
        )

        XCTAssertEqual(result, .alreadyActive)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 60)
        XCTAssertEqual(relockedSessionID, sessionID)
        XCTAssertEqual(transactionCommitCount, 0)
    }

    /// 精准 App 的设备窗口、本地会话与积分账本全部成功后，事务提交回调只触发一次。
    func testConcurrentUnlockCommitsTransactionExactlyOnce() {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 60
        let controller = MockScreenTimeController()
        let sessionID = UUID()
        let expectedEndsAt = sessionAnchor.addingTimeInterval(15 * 60)
        var transactionCommitCount = 0

        let result = StartRewardSessionUseCase(store: store, screenTimeController: controller)(
            minutes: 15,
            now: sessionAnchor,
            concurrentExternalDeviceStart: { _, _ in
                ScreenTimeExternalSession(id: sessionID, endsAt: expectedEndsAt)
            },
            transactionCommitted: { transactionCommitCount += 1 }
        )

        XCTAssertEqual(result, .started(endsAt: expectedEndsAt))
        XCTAssertEqual(store.child.rewardBalanceMinutes, 45)
        XCTAssertEqual(controller.activeGrants.map(\.id), [sessionID])
        XCTAssertEqual(transactionCommitCount, 1)
    }

    /// 重复解锁被拒绝且不叠加时间；已扣成长积分回滚，净扣一次。
    func testRepeatedUnlockIsRejectedAndRollsBack() {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 60
        let controller = MockScreenTimeController()
        let useCase = StartRewardSessionUseCase(store: store, screenTimeController: controller)

        let first = useCase(minutes: 15, now: sessionAnchor)
        XCTAssertEqual(first, .started(endsAt: sessionAnchor.addingTimeInterval(15 * 60)))
        XCTAssertEqual(store.child.rewardBalanceMinutes, 45)

        let second = useCase(minutes: 15, now: sessionAnchor.addingTimeInterval(60))
        XCTAssertEqual(second, .alreadyActive)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 45, "重复解锁应回滚，成长积分净扣一次")
        XCTAssertEqual(controller.sessionStatus, .active)
        XCTAssertEqual(controller.unlockEndsAt, sessionAnchor.addingTimeInterval(15 * 60), "到期时间不应被叠加")
        XCTAssertTrue(controller.receipts.isEmpty)
    }

    /// 到期 tick：未到期不结算；到期生成「到期」收据并重锁，过期窗口不再解锁。
    func testExpiredTickProducesReceiptAndRelocks() throws {
        let controller = MockScreenTimeController()
        try controller.startSession(minutes: 15, now: sessionAnchor)

        let early = controller.tick(now: sessionAnchor.addingTimeInterval(10 * 60))
        XCTAssertNil(early, "未到期不应结算")
        XCTAssertEqual(controller.sessionStatus, .active)

        let receipt = try XCTUnwrap(controller.tick(now: sessionAnchor.addingTimeInterval(15 * 60)))
        XCTAssertEqual(controller.sessionStatus, .expired)
        XCTAssertEqual(controller.shieldState, .locked, "过期窗口必须保持锁定")
        XCTAssertNil(controller.unlockEndsAt)
        XCTAssertEqual(receipt.endReason, .expired)
        XCTAssertEqual(receipt.grantedMinutes, 15)
        XCTAssertEqual(receipt.consumedMinutes, 15)
        XCTAssertEqual(receipt.unusedMinutes, 0)
        XCTAssertEqual(controller.receipts.count, 1)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.kind, .automaticRelock)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.status, .succeeded)
    }

    /// 家长提前结束：生成「家长结束」收据，记录已用/未用分钟，并重锁。
    func testParentEarlyEndProducesReceiptWithUnusedMinutes() throws {
        let controller = MockScreenTimeController()
        try controller.startSession(minutes: 15, now: sessionAnchor)

        let receipt = try XCTUnwrap(controller.endSessionByParent(now: sessionAnchor.addingTimeInterval(5 * 60)))
        XCTAssertEqual(controller.sessionStatus, .locked)
        XCTAssertEqual(controller.shieldState, .locked)
        XCTAssertNil(controller.unlockEndsAt)
        XCTAssertEqual(receipt.endReason, .parentEnded)
        XCTAssertEqual(receipt.grantedMinutes, 15)
        XCTAssertEqual(receipt.consumedMinutes, 5)
        XCTAssertEqual(receipt.unusedMinutes, 10)
    }

    /// 没有进行中会话时，家长结束/重锁只确保锁定，不产生收据。
    func testEndingWithoutActiveSessionStaysLocked() {
        let controller = MockScreenTimeController()
        let receipt = controller.endSessionByParent(now: sessionAnchor)

        XCTAssertNil(receipt)
        XCTAssertEqual(controller.sessionStatus, .locked)
        XCTAssertTrue(controller.receipts.isEmpty)
    }

    /// 解锁会话跨 App 重启保留：active 会话恢复后仍在倒计时，到期由 tick 正常重锁。
    func testScreenTimeSessionSurvivesRelaunch() throws {
        let suiteName = "octoteacher-screentime-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "session"

        let first = MockScreenTimeController(persistenceKey: key, defaults: defaults)
        try first.startSession(minutes: 15, now: sessionAnchor)
        XCTAssertEqual(first.sessionStatus, .active)

        // 模拟 App 重启：恢复会话。
        let second = MockScreenTimeController(persistenceKey: key, defaults: defaults)
        XCTAssertEqual(second.sessionStatus, .active)
        XCTAssertEqual(second.unlockEndsAt, sessionAnchor.addingTimeInterval(15 * 60))
        XCTAssertEqual(second.shieldState, .unlocked)

        // 恢复后到期照常结算重锁。
        let receipt = try XCTUnwrap(second.tick(now: sessionAnchor.addingTimeInterval(15 * 60)))
        XCTAssertEqual(receipt.endReason, .expired)
        XCTAssertEqual(second.shieldState, .locked)

        // 再次重启：会话已结束，保持锁定并保留收据。
        let third = MockScreenTimeController(persistenceKey: key, defaults: defaults)
        XCTAssertEqual(third.shieldState, .locked)
        XCTAssertEqual(third.receipts.count, 1)
    }

    func testStaleSessionResetDoesNotCreateRelockReceipt() throws {
        let suiteName = "octoteacher-screentime-reset-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "session"

        let first = MockScreenTimeController(persistenceKey: key, defaults: defaults)
        try first.startSession(minutes: 15, now: sessionAnchor)
        let receiptCount = first.deviceCommandReceipts.count

        let restored = MockScreenTimeController(persistenceKey: key, defaults: defaults)
        restored.resetPersistedSessionWithoutRelock()

        XCTAssertEqual(restored.sessionStatus, .locked)
        XCTAssertNil(restored.unlockEndsAt)
        XCTAssertEqual(restored.deviceCommandReceipts.count, receiptCount)
        XCTAssertEqual(restored.latestDeviceCommandReceipt?.kind, .startUnlock)

        let relaunched = MockScreenTimeController(persistenceKey: key, defaults: defaults)
        XCTAssertEqual(relaunched.sessionStatus, .locked)
        XCTAssertNil(relaunched.tick(now: sessionAnchor.addingTimeInterval(30 * 60)))
        XCTAssertEqual(relaunched.deviceCommandReceipts.count, receiptCount)
    }

    /// 设备命令失败：扣掉的成长积分必须回滚，孩子不损失奖励，且不产生会话或收据。
    func testDeviceFailureRollsBackCredit() {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 30
        let controller = MockScreenTimeController()
        controller.simulateDeviceFailure = true

        let result = StartRewardSessionUseCase(store: store, screenTimeController: controller)(
            minutes: 15,
            now: sessionAnchor
        )

        XCTAssertEqual(result, .deviceFailureRolledBack)
        XCTAssertEqual(store.child.rewardBalanceMinutes, 30, "失败会话必须回滚成长积分")
        XCTAssertEqual(controller.sessionStatus, .locked)
        XCTAssertEqual(controller.shieldState, .locked)
        XCTAssertNil(controller.unlockEndsAt)
        XCTAssertTrue(controller.receipts.isEmpty, "失败不产生收据")
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.kind, .startUnlock)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.status, .failed)
        XCTAssertEqual(controller.latestDeviceCommandReceipt?.failureReason, .deviceCommandFailed)
    }
}

private final class LegacyRewardSnapshotPersistence: FamilyStorePersisting {
    var snapshot: FamilyStoreSnapshot?

    init(snapshot: FamilyStoreSnapshot?) {
        self.snapshot = snapshot
    }

    func load() -> FamilyStoreSnapshot? { snapshot }
    func save(_ snapshot: FamilyStoreSnapshot) { self.snapshot = snapshot }
}
