import XCTest
@testable import OctoTeacher

/// v5H 回归：购书渠道、AI 内容默认关闭、视频页判断、照片补充证明、音色选择。
final class ExperienceFixV5HTests: XCTestCase {

    // MARK: - 购书渠道

    func testChineseBookChannelsProvideAtLeastThree() {
        let channels = BookMarketLinks.channels(for: "夏洛的网", region: .china, contentLanguage: .chinese)
        XCTAssertGreaterThanOrEqual(channels.count, 3, "每本书至少 3 个渠道")
        XCTAssertEqual(Set(channels.map(\.name)).count, channels.count, "渠道不重复")
        for channel in channels {
            XCTAssertTrue(channel.url.absoluteString.hasPrefix("https://"), "\(channel.name) 必须是 https")
        }
    }

    func testEnglishAndBilingualChannels() {
        XCTAssertGreaterThanOrEqual(BookMarketLinks.channels(for: "Charlotte's Web", region: .usa, contentLanguage: .english).count, 3)
        XCTAssertGreaterThanOrEqual(BookMarketLinks.channels(for: "小王子", region: .china, contentLanguage: .bilingual).count, 3)
    }

    func testChannelURLEncodesTitle() {
        let channels = BookMarketLinks.channels(for: "夏洛的网 中文版", region: .china, contentLanguage: .chinese)
        XCTAssertFalse(channels[0].url.absoluteString.contains(" "), "书名必须 URL 编码")
    }

    // MARK: - AI 阅读内容默认关闭（版权护栏）

    func testAIContentDefaultsOff() {
        let spec = ReadingSpec(bookTitle: "夏洛的网", minMinutes: 60, chapterPlanText: "第1章")
        XCTAssertFalse(spec.aiContentAllowed, "未显式允许时不得生成 AI 内容")

        let allowed = ReadingSpec(bookTitle: "夏洛的网", minMinutes: 60, chapterPlanText: "第1章", allowAIContent: true)
        XCTAssertTrue(allowed.aiContentAllowed)
    }

    func testLegacySpecWithoutFlagDecodesOff() throws {
        let json = #"{"bookTitle":"小王子","minMinutes":30,"chapterPlanText":"第1章"}"#
        let spec = try JSONDecoder().decode(ReadingSpec.self, from: Data(json.utf8))
        XCTAssertFalse(spec.aiContentAllowed)
    }

    // MARK: - 视频页判断（含单页应用地址形态）

    func testVideoPageDetection() {
        XCTAssertTrue(ParentVideoFinderView.looksLikeVideoPage(URL(string: "https://m.youtube.com/watch?v=abc")))
        XCTAssertTrue(ParentVideoFinderView.looksLikeVideoPage(URL(string: "https://www.youtube.com/shorts/xyz")))
        XCTAssertTrue(ParentVideoFinderView.looksLikeVideoPage(URL(string: "https://youtu.be/abc")))
        XCTAssertTrue(ParentVideoFinderView.looksLikeVideoPage(URL(string: "https://www.bilibili.com/video/BV1abc")))
        XCTAssertFalse(ParentVideoFinderView.looksLikeVideoPage(URL(string: "https://www.youtube.com/results?search_query=volcano")))
        XCTAssertFalse(ParentVideoFinderView.looksLikeVideoPage(nil))
    }

    // MARK: - 照片补充证明

    func testTextProofCarriesOptionalPhoto() throws {
        let store = LocalFamilyStore()
        let assignment = store.assignments[0]
        let proof = ProofDraft(
            kind: .text,
            text: "整理好了",
            photoPlaceholderName: nil,
            photoFileName: "photo-abc.jpg",
            status: .submitted
        )
        store.submit(assignment, proof: proof)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.assignments[0].proof.photoFileName, "photo-abc.jpg", "文字任务可附照片")
    }

    // MARK: - 音色选择

    func testBestVoiceReturnsSomethingForBothLanguages() {
        // 模拟器至少有默认音色；断言不为 nil 且语言前缀正确。
        let chinese = SpeechReader.bestVoice(for: "zh-CN")
        XCTAssertNotNil(chinese)
        XCTAssertTrue(chinese?.language.hasPrefix("zh") == true)
        let english = SpeechReader.bestVoice(for: "en-US")
        XCTAssertTrue(english?.language.hasPrefix("en") == true)
    }
}
