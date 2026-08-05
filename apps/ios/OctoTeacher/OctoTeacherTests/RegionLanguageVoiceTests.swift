import XCTest
@testable import OctoTeacher

/// v5I 回归：地区渠道矩阵、家长/孩子语言分离、云端语音门禁与缓存。
final class RegionLanguageVoiceTests: XCTestCase {

    // MARK: - 地区渠道

    /// v5K 起渠道为电子书且内容语言主导：中文内容 → 中文电子书渠道。
    func testChineseContentChannels() {
        let channels = BookMarketLinks.channels(for: "夏洛的网", region: .china, contentLanguage: .chinese)
        XCTAssertGreaterThanOrEqual(channels.count, 5)
        XCTAssertTrue(channels.contains { $0.name == "微信读书" })
        XCTAssertFalse(channels.contains { $0.name == "当当" }, "纸书渠道已移除")
    }

    func testEnglishContentChannels() {
        let channels = BookMarketLinks.channels(for: "Charlotte's Web", region: .usa, contentLanguage: .english)
        XCTAssertGreaterThanOrEqual(channels.count, 5)
        XCTAssertTrue(channels.contains { $0.name.contains("Kindle") })
        XCTAssertFalse(channels.contains { $0.name == "微信读书" })
    }

    /// 双语内容混合两边电子书渠道。
    func testCrossLanguageSupplementChannels() {
        let bilingual = BookMarketLinks.channels(for: "小王子", region: .usa, contentLanguage: .bilingual)
        XCTAssertTrue(bilingual.contains { $0.name == "微信读书" })
        XCTAssertTrue(bilingual.contains { $0.name.contains("Kindle") })
    }

    // MARK: - 家长/孩子语言分离

    func testChildContentLanguageFallsBackToFamily() throws {
        let store = LocalFamilyStore()
        store.setFamilyLanguage(.chinese)
        XCTAssertEqual(store.activeContentLanguage, .chinese, "未单独设置时跟随家庭")

        // 家长中文，孩子学英文。
        store.setContentLanguage(.english, for: store.activeChildId)
        XCTAssertEqual(store.activeContentLanguage, .english)
        XCTAssertEqual(store.settings.language, .chinese, "家长语言不受影响")

        // 兄妹可以不同。
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 5))
        XCTAssertEqual(store.effectiveContentLanguage(for: second.id), .chinese)
    }

    func testRecommenderPromptSeparatesChildAndParentLanguage() {
        let prompt = AIBookRecommender.systemPrompt(language: .english, parentLanguage: .chinese)
        XCTAssertTrue(prompt.contains("English"), "书名/内容语言跟孩子")
        XCTAssertTrue(prompt.contains("blurb 是给家长看的"), "简介语言跟家长")
    }

    func testRegionAndLanguageSurviveRoundTrip() throws {
        let store = LocalFamilyStore()
        store.setRegion(.usa)
        store.setContentLanguage(.english, for: store.activeChildId)
        store.setCloudVoice(false)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.settings?.resolvedRegion, .usa)
        XCTAssertEqual(decoded.settings?.resolvedCloudVoice, false)
        XCTAssertEqual(decoded.children[0].contentLanguage, .english)
    }

    func testLegacySettingsDefaultToChinaAndCloudVoiceOn() throws {
        let json = #"{"language":"chinese"}"#
        let settings = try JSONDecoder().decode(FamilySettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.resolvedRegion, .china)
        XCTAssertTrue(settings.resolvedCloudVoice)
    }

    // MARK: - 云端语音

    @MainActor
    func testCloudVoiceGating() {
        let store = ParentAIProviderStore(keyStore: InMemoryAIProviderKeyStore(), defaults: nil)
        XCTAssertFalse(store.isCloudVoiceCapable, "无配置不可用")
        store.apply(kind: .anthropicClaude, baseURLString: "", modelName: "", key: "sk")
        XCTAssertFalse(store.isCloudVoiceCapable, "Claude 无 TTS 接口")
        store.apply(kind: .openAI, baseURLString: "", modelName: "", key: "sk")
        XCTAssertTrue(store.isCloudVoiceCapable)
    }

    func testSpeechCacheKeyDeterministicAndDistinct() {
        XCTAssertEqual(SpeechCache.key(for: "你好"), SpeechCache.key(for: "你好"))
        XCTAssertNotEqual(SpeechCache.key(for: "你好"), SpeechCache.key(for: "你好呀"))
        XCTAssertTrue(SpeechCache.key(for: "你好").hasSuffix(".mp3"))
    }

    func testCompanionVoiceStylesDriveSpeechTuningAndCacheKeys() {
        XCTAssertEqual(AICompanionVoiceStyle.warm.openAISpeechVoice, "nova")
        XCTAssertEqual(AICompanionVoiceStyle.bright.openAISpeechVoice, "shimmer")
        XCTAssertEqual(AICompanionVoiceStyle.calm.openAISpeechVoice, "onyx")
        XCTAssertGreaterThan(AICompanionVoiceStyle.bright.localPitchMultiplier, AICompanionVoiceStyle.warm.localPitchMultiplier)
        XCTAssertLessThan(AICompanionVoiceStyle.calm.localSpeechRate, AICompanionVoiceStyle.warm.localSpeechRate)

        let text = "你好"
        XCTAssertNotEqual(
            SpeechCache.key(for: SpeechCache.textKey(text, voiceStyle: .warm)),
            SpeechCache.key(for: SpeechCache.textKey(text, voiceStyle: .bright))
        )
        XCTAssertEqual(SpeechCache.textKey(text, voiceStyle: nil), text)
    }

    func testSpeechCacheRoundTrip() {
        let text = "cache-test-\(UUID().uuidString)"
        XCTAssertNil(SpeechCache.load(text: text))
        SpeechCache.store(Data("mp3-bytes".utf8), text: text)
        XCTAssertEqual(SpeechCache.load(text: text), Data("mp3-bytes".utf8))
    }
}
