import XCTest
@testable import OctoTeacher

/// P4-P6：AI 包任务生成、任务编辑、书链接识别的回归测试。
final class AIPackWorkbenchTests: XCTestCase {

    // MARK: - 生成器解析与护栏

    func testGeneratorParsesValidTasks() {
        let raw = """
        {"tasks":[
            {"title":"整理玩具架","instructions":"把玩具分类放好","category":"home",
             "rewardPoints":15,"requiredProof":"photo","adultSupervisionRequired":false},
            {"title":"读《夏洛的网》第7-8章","instructions":"读完复述","category":"learning",
             "rewardPoints":20,"requiredProof":"text",
             "reading":{"bookTitle":"夏洛的网","minMinutes":30,"chapterPlanText":"第7-8章"}}
        ]}
        """
        let drafts = AIPackTaskGenerator.parse(raw, packType: .chores)
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].category, .home)
        XCTAssertEqual(drafts[0].requiredProof, .photo)
        XCTAssertEqual(drafts[1].reading?.bookTitle, "夏洛的网")
    }

    func testGeneratorClampsPointsAndCapsCount() {
        let tasks = (1...10).map {
            #"{"title":"任务\#($0)","rewardPoints":999}"#
        }.joined(separator: ",")
        let drafts = AIPackTaskGenerator.parse(#"{"tasks":[\#(tasks)]}"#, packType: .chores)
        XCTAssertEqual(drafts.count, 6, "生成数量上限 6")
        XCTAssertTrue(drafts.allSatisfy { $0.rewardPoints == 60 }, "分值封顶 60")
    }

    func testGeneratorForcesAdultSupervisionOnDangerKeywords() {
        let raw = """
        {"tasks":[{"title":"学会用小刀削苹果","instructions":"注意安全","category":"creative",
                   "rewardPoints":20,"adultSupervisionRequired":false}]}
        """
        let drafts = AIPackTaskGenerator.parse(raw, packType: .skillExtension)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertTrue(drafts[0].adultSupervisionRequired, "危险关键词必须强制需大人在场")
    }

    func testGeneratorDropsFinanceTasksWithRealMoneyWords() {
        let raw = """
        {"tasks":[
            {"title":"记录一周零花钱","rewardPoints":15},
            {"title":"学会用手机支付买东西","rewardPoints":15}
        ]}
        """
        let drafts = AIPackTaskGenerator.parse(raw, packType: .financeLiteracy)
        XCTAssertEqual(drafts.count, 1, "含真实交易词的金融任务必须丢弃")
        XCTAssertEqual(drafts[0].title, "记录一周零花钱")
    }

    func testGeneratorHandlesMalformedOutput() {
        XCTAssertTrue(AIPackTaskGenerator.parse("抱歉我不能生成", packType: .chores).isEmpty)
    }

    func testSystemPromptCarriesStrategyAndLanguage() {
        let prompt = AIPackTaskGenerator.systemPrompt(packType: .learning, language: .english)
        XCTAssertTrue(prompt.contains("阅读进度"), "学习包策略应包含按进度推进")
        XCTAssertTrue(prompt.contains("English"), "语言指令应注入")
    }

    func testUserPromptCarriesDigest() {
        let prompt = AIPackTaskGenerator.userPrompt(digest: "乐乐，9 岁，兴趣：恐龙", count: 4)
        XCTAssertTrue(prompt.contains("恐龙"))
        XCTAssertTrue(prompt.contains("4 个任务"))
    }

    // MARK: - 布置草稿

    func testAssignGeneratedDraftsStampsPackType() throws {
        let store = LocalFamilyStore()
        let draft = GeneratedTaskDraft(
            title: "AI 生成的家务",
            instructions: "说明",
            category: .home,
            rewardPoints: 15,
            requiredProof: .text,
            adultSupervisionRequired: false,
            reading: nil
        )
        let count = store.assignGeneratedDrafts([draft], packType: .chores)
        XCTAssertEqual(count, 1)
        let assigned = try XCTUnwrap(store.assignments.last)
        XCTAssertEqual(assigned.task.packType, .chores, "任务必须记录所属包")
        XCTAssertEqual(assigned.task.rewardMinutes, 15)
    }

    // MARK: - AI 任务编辑

    func testTaskEditorParsesFirstTask() {
        let raw = """
        {"tasks":[{"title":"整理玩具架（简单版）","instructions":"只整理一层",
                   "category":"home","rewardPoints":10,"requiredProof":"text"}]}
        """
        let draft = AITaskEditor.parse(raw, packType: .chores)
        XCTAssertEqual(draft?.title, "整理玩具架（简单版）")
        XCTAssertEqual(draft?.rewardPoints, 10)
    }

    func testTaskEditorPromptCarriesOriginalAndIntent() {
        let task = TaskTemplate(
            id: UUID(),
            title: "练琴 20 分钟",
            category: .creative,
            difficulty: .easy,
            rewardMinutes: 20,
            instructions: "弹完本周曲目",
            requiredProof: .text
        )
        let prompt = AITaskEditor.userPrompt(task: task, intent: "降低难度", digest: "乐乐 9 岁")
        XCTAssertTrue(prompt.contains("练琴 20 分钟"))
        XCTAssertTrue(prompt.contains("降低难度"))
        XCTAssertTrue(prompt.contains("乐乐"))
        XCTAssertTrue(prompt.contains("奖励 20 成长积分"))
        XCTAssertFalse(prompt.contains("奖励 20 分。"))
    }

    func testParentPackWorkbenchRewardLabelUsesGrowthCredits() {
        XCTAssertEqual(ParentPackWorkbenchCopy.rewardLabel(points: 20), "20 成长积分")
    }

    // MARK: - 书链接识别

    func testBookLinkReaderParsesTitle() {
        XCTAssertEqual(AIBookLinkReader.parse(#"{"bookTitle":"夏洛的网","author":"E. B. White"}"#), "夏洛的网")
        XCTAssertNil(AIBookLinkReader.parse(#"{"bookTitle":""}"#))
        XCTAssertNil(AIBookLinkReader.parse("not-json"))
    }
}
