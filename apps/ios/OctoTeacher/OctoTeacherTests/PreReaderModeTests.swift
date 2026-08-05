import XCTest
@testable import OctoTeacher

/// v5E 幼儿模式回归：按孩子开关、朗读联动、持久化。
final class PreReaderModeTests: XCTestCase {

    func testPreReaderDefaultsOff() {
        let store = LocalFamilyStore()
        XCTAssertFalse(store.child.isPreReader)
        XCTAssertFalse(store.isPreReaderActive)
    }

    func testPreReaderDefaultsOnThroughAgeSevenAndCanBeExplicitlyDisabled() {
        let child = ChildProfile(
            id: UUID(),
            name: "Alex",
            age: 7,
            dailyLimitMinutes: 60,
            rewardBalanceMinutes: 0
        )
        XCTAssertTrue(child.isPreReader)

        var explicitlyDisabled = child
        explicitlyDisabled.preReaderMode = false
        XCTAssertFalse(explicitlyDisabled.isPreReader)
    }

    func testPreReaderPerChildAndImpliesSpeech() throws {
        let store = LocalFamilyStore()
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 4))
        store.setPreReaderMode(true, for: second.id)

        // 老大不受影响。
        XCTAssertFalse(store.isPreReaderActive)
        XCTAssertFalse(store.isSpeechEnabled, "家庭朗读关且老大非幼儿：不朗读")

        // 切到妹妹：幼儿模式激活，朗读自动生效（无需家庭开关）。
        store.setActiveChild(second.id)
        XCTAssertTrue(store.isPreReaderActive)
        XCTAssertTrue(store.isSpeechEnabled, "幼儿模式必须隐含开启朗读")
    }

    func testFamilyReadAloudStillWorksForReaders() {
        let store = LocalFamilyStore()
        store.setReadAloud(true)
        XCTAssertTrue(store.isSpeechEnabled)
        XCTAssertFalse(store.isPreReaderActive, "家庭朗读开但不是幼儿模式：界面仍是普通版")
    }

    func testPreReaderSurvivesRoundTrip() throws {
        let store = LocalFamilyStore()
        store.setPreReaderMode(true, for: store.child.id)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.children[0].isPreReader, true)
    }

    func testPreReaderRewardCopyUsesGrowthCreditsAndManualSpeakerText() {
        XCTAssertEqual(GrowthCreditCopy.label(points: 20), "20 成长积分")
        XCTAssertEqual(GrowthCreditCopy.label(points: -1), "0 成长积分")
        XCTAssertEqual(PreReaderHomeCopy.rewardLabel(points: 20), "20 成长积分")
        XCTAssertEqual(PreReaderHomeCopy.rewardLabel(points: -1), "0 成长积分")
        XCTAssertEqual(
            PreReaderHomeCopy.taskSpeech(category: "学习", title: "读一页绘本", rewardPoints: 20),
            "学习：读一页绘本。做完有 20 成长积分。"
        )
        XCTAssertEqual(
            PreReaderHomeCopy.taskSpeech(category: "  ", title: "\n", rewardPoints: -5),
            "任务：小任务。做完有 0 成长积分。"
        )
        XCTAssertEqual(
            PreReaderHomeCopy.greetingSpeech(childName: "乐乐", done: 1, total: 3, nextTaskTitle: "读一页绘本"),
            "你好，乐乐！今天有 3 个任务，已经完成 1 个。现在可以先做：读一页绘本。"
        )
        XCTAssertEqual(
            PreReaderHomeCopy.greetingSpeech(childName: "  ", done: 0, total: 0, nextTaskTitle: nil),
            "你好，小朋友！今天还没有任务，去玩吧！"
        )
    }

    func testPreReaderEmptyTaskCopyGuidesChildWithSpeaker() {
        XCTAssertEqual(PreReaderHomeCopy.emptyTaskTitle, "今天还没有任务")
        XCTAssertEqual(PreReaderHomeCopy.emptyTaskDetail, "等大人布置好任务，这里就会出现大卡片。")
        // 朗读文案要先说清状态，再给不识字的孩子指一条能做的路。
        XCTAssertTrue(PreReaderHomeCopy.emptyTaskSpeech.hasPrefix("今天还没有任务"))
        XCTAssertTrue(PreReaderHomeCopy.emptyTaskSpeech.contains("小伙伴"))
    }

    func testPreReaderHomePrimaryButtonsUseStableSemanticIcons() {
        XCTAssertEqual(PreReaderHomeIcon.companion, TaskIconProvider.Icon(emoji: "🐙", assetName: BrandIdentity.logoAssetName))
        XCTAssertEqual(PreReaderHomeIcon.screenTime, TaskIconProvider.Icon(emoji: "🎮", systemImageName: "gamecontroller.fill"))
        XCTAssertEqual(PreReaderHomeIcon.wish, TaskIconProvider.Icon(emoji: "🎁", systemImageName: "gift.fill"))
        XCTAssertEqual(PreReaderHomeIcon.creative, TaskIconProvider.Icon(emoji: "🎨", systemImageName: "paintpalette.fill"))
        XCTAssertEqual(PreReaderHomeIcon.badge, TaskIconProvider.Icon(emoji: "🏆", systemImageName: "trophy.fill"))
    }

    func testPreReaderProgressStarsScaleWhenTaskCountExceedsTen() {
        XCTAssertEqual(
            PreReaderHomeCopy.progressStars(done: 3, total: 5),
            ["⭐", "⭐", "⭐", "☆", "☆"]
        )
        XCTAssertNil(PreReaderHomeCopy.progressSummary(done: 3, total: 5))

        XCTAssertEqual(PreReaderHomeCopy.progressStars(done: 0, total: 14).count, 10)
        XCTAssertEqual(
            PreReaderHomeCopy.progressStars(done: 10, total: 14),
            ["⭐", "⭐", "⭐", "⭐", "⭐", "⭐", "⭐", "☆", "☆", "☆"]
        )
        XCTAssertEqual(
            PreReaderHomeCopy.progressStars(done: 11, total: 14),
            ["⭐", "⭐", "⭐", "⭐", "⭐", "⭐", "⭐", "⭐", "☆", "☆"]
        )
        XCTAssertEqual(PreReaderHomeCopy.progressSummary(done: 11, total: 14), "已完成 11/14")
        XCTAssertEqual(
            PreReaderHomeCopy.progressStars(done: 99, total: 14),
            Array(repeating: "⭐", count: 10)
        )
        XCTAssertEqual(PreReaderHomeCopy.progressSummary(done: 99, total: 14), "已完成 14/14")
    }

    func testPreReaderHomeStartsCompactAndKeepsEveryTaskReachable() {
        XCTAssertEqual(PreReaderHomeLayout.primaryTaskLimit, 2)
        XCTAssertFalse(PreReaderHomeLayout.tasksExpandedByDefault)
        XCTAssertFalse(PreReaderHomeLayout.toolsExpandedByDefault)
        XCTAssertFalse(PreReaderHomeLayout.completedExpandedByDefault)

        XCTAssertEqual(PreReaderHomeLayout.visibleTaskCount(total: -1, isExpanded: false), 0)
        XCTAssertEqual(PreReaderHomeLayout.visibleTaskCount(total: 1, isExpanded: false), 1)
        XCTAssertEqual(PreReaderHomeLayout.visibleTaskCount(total: 12, isExpanded: false), 2)
        XCTAssertEqual(PreReaderHomeLayout.visibleTaskCount(total: 12, isExpanded: true), 12)
    }

    func testPreReaderHomeUsesStableTabAwareBottomMargin() {
        XCTAssertEqual(PreReaderHomeLayout.bottomContentMargin, 24)
        XCTAssertLessThan(PreReaderHomeLayout.bottomContentMargin, 44)
    }

    func testAICompanionProfileDefaultsAndSurvivesRoundTrip() throws {
        let store = LocalFamilyStore()
        XCTAssertEqual(store.child.companionDisplayName, "AI 章鱼老师")
        XCTAssertEqual(store.child.companionVoiceStyle, .warm)
        XCTAssertEqual(store.child.companionPersonalityStyle, .gentleGuide)
        XCTAssertTrue(store.child.companionAvatarDescription.contains("章鱼"))

        XCTAssertTrue(store.setAICompanionProfile(
            name: "小云",
            voice: .bright,
            personality: .playfulCoach,
            avatarDescription: "一只蓝色星星小龙"
        ))
        XCTAssertEqual(store.child.companionDisplayName, "小云")
        XCTAssertEqual(store.child.companionVoiceStyle, .bright)
        XCTAssertEqual(store.child.companionPersonalityStyle, .playfulCoach)
        XCTAssertEqual(store.child.companionAvatarDescription, "一只蓝色星星小龙")

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.children[0].companionDisplayName, "小云")
        XCTAssertEqual(decoded.children[0].companionVoiceStyle, .bright)
        XCTAssertEqual(decoded.children[0].companionPersonalityStyle, .playfulCoach)
        XCTAssertEqual(decoded.children[0].companionAvatarDescription, "一只蓝色星星小龙")
    }

    /// 旧档案（无 preReaderMode 字段）按年龄选择默认界面。
    func testLegacyProfileDecodesAsNonPreReader() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"乐乐","age":9,"dailyLimitMinutes":60,"rewardBalanceMinutes":0}
        """
        let profile = try JSONDecoder().decode(ChildProfile.self, from: Data(json.utf8))
        XCTAssertFalse(profile.isPreReader)
        XCTAssertEqual(profile.companionDisplayName, "AI 章鱼老师")
        XCTAssertTrue(profile.companionAvatarDescription.contains("章鱼"))
    }
}
