import XCTest
@testable import OctoTeacher

/// v4 体验升级回归测试：内嵌播放、AI 选书、周期零花钱、愿望清单、每包默认分值。
final class ExperienceV4Tests: XCTestCase {

    private func dateOf(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - 视频内嵌解析

    func testYouTubeURLsResolveToEmbed() {
        let watch = VideoEmbedResolver.embedURL(for: "https://www.youtube.com/watch?v=abc123", bundleIdentifier: "com.octoteacher.app")
        XCTAssertEqual(watch?.scheme, "https")
        XCTAssertEqual(watch?.host, "www.youtube-nocookie.com")
        XCTAssertEqual(watch?.path, "/embed/abc123")
        XCTAssertEqual(
            URLComponents(url: watch!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "origin" })?.value,
            "https://com.octoteacher.app"
        )

        XCTAssertEqual(
            VideoEmbedResolver.youtubeVideoId(from: URL(string: "https://youtu.be/xyz789")!),
            "xyz789"
        )
        XCTAssertEqual(
            VideoEmbedResolver.youtubeVideoId(from: URL(string: "https://www.youtube.com/shorts/short1")!),
            "short1"
        )
    }

    func testYouTubeCompatibilityURLUsesStandardEmbedHost() throws {
        let url = try XCTUnwrap(VideoEmbedResolver.compatibilityEmbedURL(
            for: "https://youtu.be/abc123",
            bundleIdentifier: "COM.OctoTeacher.App"
        ))
        XCTAssertEqual(url.host, "www.youtube.com")
        XCTAssertEqual(url.path, "/embed/abc123")
        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "origin" })?.value,
            "https://com.octoteacher.app"
        )
        XCTAssertTrue(VideoEmbedResolver.isYouTubeEmbedURL(url))
    }

    func testYouTubeCompatibilityURLRejectsNonVideoPagesAndOtherPlatforms() {
        XCTAssertNil(VideoEmbedResolver.compatibilityEmbedURL(for: "https://www.youtube.com/results?search_query=volcano"))
        XCTAssertNil(VideoEmbedResolver.compatibilityEmbedURL(for: "https://www.bilibili.com/video/BV1abc"))

        XCTAssertFalse(VideoEmbedResolver.isYouTubeEmbedURL(URL(string: "https://www.youtube.com/watch?v=abc123")!))
        XCTAssertFalse(VideoEmbedResolver.isYouTubeEmbedURL(URL(string: "https://www.youtube.com/results?search_query=volcano")!))
    }

    func testYouTubePlaybackRequestCarriesAppReferrer() throws {
        let url = try XCTUnwrap(VideoEmbedResolver.embedURL(for: "https://www.youtube.com/watch?v=abc123", bundleIdentifier: "COM.OctoTeacher.App"))
        let request = VideoEmbedResolver.playbackRequest(for: url, bundleIdentifier: "COM.OctoTeacher.App")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://com.octoteacher.app")

        let compatibility = try XCTUnwrap(VideoEmbedResolver.compatibilityEmbedURL(for: "https://youtu.be/abc123", bundleIdentifier: "COM.OctoTeacher.App"))
        let compatibilityRequest = VideoEmbedResolver.playbackRequest(for: compatibility, bundleIdentifier: "COM.OctoTeacher.App")
        XCTAssertEqual(compatibilityRequest.value(forHTTPHeaderField: "Referer"), "https://com.octoteacher.app")

        let generic = try XCTUnwrap(URL(string: "https://example.com/lesson.mp4"))
        let genericRequest = VideoEmbedResolver.playbackRequest(for: generic, bundleIdentifier: "com.octoteacher.app")
        XCTAssertNil(genericRequest.value(forHTTPHeaderField: "Referer"))
    }

    func testYouTubeEmbeddedHTMLCarriesStrictReferrerPolicy() throws {
        let url = try XCTUnwrap(VideoEmbedResolver.embedURL(
            for: "https://www.youtube.com/watch?v=abc123",
            bundleIdentifier: "COM.OctoTeacher.App"
        ))
        let document = try XCTUnwrap(VideoEmbedResolver.embeddedHTML(for: url, bundleIdentifier: "COM.OctoTeacher.App"))

        XCTAssertEqual(document.baseURL.absoluteString, "https://com.octoteacher.app")
        XCTAssertTrue(document.html.contains("www.youtube-nocookie.com/embed/abc123"))
        XCTAssertTrue(document.html.contains(#"referrerpolicy="strict-origin-when-cross-origin""#))
        XCTAssertTrue(document.html.contains(#"<meta name="referrer" content="strict-origin-when-cross-origin">"#))
    }

    func testGenericVideoDoesNotUseYouTubeHTMLWrapper() throws {
        let generic = try XCTUnwrap(URL(string: "https://example.com/lesson.mp4"))
        XCTAssertNil(VideoEmbedResolver.embeddedHTML(for: generic))
    }

    func testBilibiliURLsResolveToPlayer() {
        let url = VideoEmbedResolver.embedURL(for: "https://www.bilibili.com/video/BV1abc/")
        XCTAssertEqual(url?.absoluteString, "https://player.bilibili.com/player.html?bvid=BV1abc&autoplay=0")
    }

    func testDirectHTTPSMediaPassesThroughAndGarbageFails() {
        XCTAssertEqual(
            VideoEmbedResolver.embedURL(for: "https://example.com/lesson.mp4")?.absoluteString,
            "https://example.com/lesson.mp4"
        )
        XCTAssertNil(VideoEmbedResolver.embedURL(for: "not a url at all ::"))
    }

    func testGenericWebPagesPurchasePagesAndInsecureLinksAreNotVideoEntrypoints() {
        XCTAssertNil(VideoEmbedResolver.embedURL(for: "https://example.com/lesson"))
        XCTAssertNil(VideoEmbedResolver.embedURL(for: "https://example.com/search?q=kids+book"))
        XCTAssertNil(VideoEmbedResolver.embedURL(for: "https://www.amazon.com/s?k=charlotte+web"))
        XCTAssertNil(VideoEmbedResolver.embedURL(for: "http://example.com/lesson.mp4"))
    }

    func testChildVideoPlaybackHelpUsesFamilyLanguageInsteadOfErrorCodes() {
        let help = ChildVideoPlayerCopy.allUserFacingPlaybackHelp.joined(separator: "\n")
        XCTAssertFalse(help.localizedCaseInsensitiveContains("error"))
        XCTAssertFalse(help.contains("153"))
        XCTAssertTrue(help.contains("章鱼老师 内播放方式"))
        XCTAssertTrue(help.contains("换一种播放方式"))
        XCTAssertTrue(help.contains("不是你的问题"))
    }

    // MARK: - 书籍类别与 AI 选书

    func testBookCategoryCatalogIsRich() {
        let categories = BookCategory.allCases
        XCTAssertGreaterThanOrEqual(categories.count, 20, "类别应覆盖幼儿到青少年")
        XCTAssertLessThanOrEqual(categories.count, 30)
        XCTAssertEqual(Set(categories.map(\.rawValue)).count, categories.count, "类别不能重名")
        for category in categories {
            XCTAssertFalse(category.ageHint.isEmpty)
        }
    }

    func testBookRecommenderParse() {
        let raw = """
        {"books":[
            {"title":"夏洛的网","author":"E. B. White","blurb":"蜘蛛和小猪的友谊。"},
            {"title":"  ","author":"x","blurb":"skip"}
        ]}
        """
        let books = AIBookRecommender.parse(raw)
        XCTAssertEqual(books.count, 1, "空标题必须跳过")
        XCTAssertEqual(books[0].title, "夏洛的网")
        XCTAssertTrue(AIBookRecommender.parse("不是JSON").isEmpty)
    }

    func testReadingPlannerParsesIntro() {
        let raw = """
        {"intro":"这本书讲友谊与成长。","sessions":[
            {"order":1,"chapters":"第1-3章","estimatedMinutes":60,"note":""}
        ]}
        """
        let result = AIReadingPlanner.parseWithIntro(raw)
        XCTAssertEqual(result.intro, "这本书讲友谊与成长。")
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions[0].estimatedMinutes, 60)
    }

    // MARK: - 每周零花钱

    func testWeeklyAllowanceCreditsOncePerWeek() {
        let store = LocalFamilyStore()
        var policy = FamilyExchangePolicy.default
        policy.allowanceCycle = .weekly
        policy.baseMonthlyAllowance = 10
        store.exchangePolicies[store.activeChildId] = policy

        // 同一周多次调用只入一次（周三与周四同周）。
        store.creditMonthlyAllowancesIfNeeded(now: dateOf(2026, 7, 1))
        store.creditMonthlyAllowancesIfNeeded(now: dateOf(2026, 7, 2))
        XCTAssertEqual(store.moneyLedger.filter { $0.kind == .baseAllowance }.count, 1)
        XCTAssertEqual(store.moneyLedger.first?.note, "本周基础零花钱")

        // 下一周再入一次。
        store.creditMonthlyAllowancesIfNeeded(now: dateOf(2026, 7, 8))
        XCTAssertEqual(store.moneyLedger.filter { $0.kind == .baseAllowance }.count, 2)
    }

    // MARK: - 愿望清单

    func testWishFullLifecycle() throws {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 100

        let wish = try XCTUnwrap(store.submitWish(title: "乐高恐龙套装"))
        XCTAssertEqual(wish.status, .proposed)

        // 未定价不能兑换。
        XCTAssertFalse(store.redeemWish(wish.id))

        XCTAssertTrue(store.priceWish(wish.id, points: 80))
        XCTAssertEqual(store.wishes.first?.status, .priced)

        XCTAssertTrue(store.redeemWish(wish.id))
        XCTAssertEqual(store.child.rewardBalanceMinutes, 20, "兑换扣 80 分")
        XCTAssertEqual(store.wishes.first?.status, .redeemed)

        XCTAssertTrue(store.markWishFulfilled(wish.id))
        XCTAssertEqual(store.wishes.first?.status, .fulfilled)
    }

    func testWishRedeemBlockedWhenInsufficientPoints() throws {
        let store = LocalFamilyStore()
        store.child.rewardBalanceMinutes = 10
        let wish = try XCTUnwrap(store.submitWish(title: "新自行车"))
        XCTAssertTrue(store.priceWish(wish.id, points: 500))
        XCTAssertFalse(store.redeemWish(wish.id), "分不够不能兑换")
        XCTAssertEqual(store.child.rewardBalanceMinutes, 10)
    }

    func testWishRejectAndValidation() throws {
        let store = LocalFamilyStore()
        XCTAssertNil(store.submitWish(title: "   "), "空愿望不能提交")
        let wish = try XCTUnwrap(store.submitWish(title: "去游乐园"))
        XCTAssertTrue(store.rejectWish(wish.id))
        XCTAssertEqual(store.wishes.first?.status, .rejected)
        XCTAssertFalse(store.priceWish(wish.id, points: 10), "已驳回不能再定价")
    }

    func testWishSurvivesSnapshotRoundTrip() throws {
        let store = LocalFamilyStore()
        _ = store.submitWish(title: "养一只小猫")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(store.snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: data)
        XCTAssertEqual(decoded.wishes?.first?.title, "养一只小猫")
    }

    // MARK: - 每包默认分值

    func testPackDefaultPointsOverrideTemplates() throws {
        let store = LocalFamilyStore()
        store.setPackDefaultPoints(30, for: .chores)

        let chores = try XCTUnwrap(ParentPackTemplateLibrary.group(for: .chores))
        store.assignPackTemplates([chores.templates[0]], packType: .chores)
        XCTAssertEqual(store.assignments.last?.task.rewardMinutes, 30, "包默认分值应覆盖模板建议")

        // 清除后恢复模板建议值。
        store.setPackDefaultPoints(0, for: .chores)
        store.assignPackTemplates([chores.templates[1]], packType: .chores)
        XCTAssertEqual(store.assignments.last?.task.rewardMinutes, chores.templates[1].suggestedRewardMinutes)
    }

    func testPackDefaultPointsClamped() {
        let store = LocalFamilyStore()
        store.setPackDefaultPoints(999, for: .learning)
        XCTAssertEqual(store.defaultPoints(for: .learning), 60, "分值封顶 60")
    }
}
