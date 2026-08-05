import XCTest
@testable import OctoTeacher

/// 中英文切换第一轮大修的 focused 回归：
/// 每个孩子独立界面语言、Root surface 语言 all-or-nothing、
/// 幼儿版英文无中文泄漏、TTS 音色映射、内置/自定义任务英文展示、旧数据解码兼容。
final class ChildInterfaceLanguageTests: XCTestCase {

    private func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
    }

    // MARK: - 每孩子独立界面语言

    func testPerChildInterfaceLanguageDoesNotLeakBetweenSiblings() throws {
        let store = LocalFamilyStore()
        store.setFamilyLanguage(.chinese)
        let first = store.activeChildId
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 5))

        store.setChildInterfaceLanguage(.chinese, for: first)
        store.setChildInterfaceLanguage(.english, for: second.id)

        XCTAssertEqual(store.childInterfaceLanguage(for: first), .chinese)
        XCTAssertEqual(store.childInterfaceLanguage(for: second.id), .english)

        store.setActiveChild(first)
        XCTAssertEqual(store.activeChildInterfaceLanguage, .chinese)
        store.setActiveChild(second.id)
        XCTAssertEqual(store.activeChildInterfaceLanguage, .english)
        // 切回后不串。
        store.setActiveChild(first)
        XCTAssertEqual(store.activeChildInterfaceLanguage, .chinese)
        XCTAssertEqual(store.activeChildLocalization.language, .chinese)
    }

    func testChildInterfaceLanguageFallsBackToFamilyDefaults() throws {
        let store = LocalFamilyStore()
        // 没有 per-child 值时回退到全局孩子界面语言。
        store.setChildInterfaceLanguage(.english)
        XCTAssertEqual(store.activeChildInterfaceLanguage, .english)

        // 再没有全局孩子界面语言时回退到家庭语言。
        let fresh = LocalFamilyStore()
        fresh.setFamilyLanguage(.english)
        XCTAssertEqual(fresh.activeChildInterfaceLanguage, .english)
        fresh.setFamilyLanguage(.chinese)
        XCTAssertEqual(fresh.activeChildInterfaceLanguage, .chinese)
    }

    func testPerChildInterfaceLanguageSurvivesPersistenceRoundTrip() throws {
        let store = LocalFamilyStore()
        let second = try XCTUnwrap(store.addChild(name: "弟弟", age: 6))
        store.setChildInterfaceLanguage(.english, for: second.id)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        let decodedSecond = try XCTUnwrap(decoded.children.first(where: { $0.id == second.id }))
        XCTAssertEqual(decodedSecond.interfaceLanguage, .english)
        XCTAssertNil(decoded.children[0].interfaceLanguage, "未设置的孩子保持 nil，继续跟随家庭")
    }

    func testScreenTimeExtensionLanguageSnapshotSurvivesLegacyAndSystemFallbacks() {
        let suiteName = "octoteacher.tests.language.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertEqual(
            ScreenTimeSharedContract.resolvedChildInterfaceLanguageRawValue(
                defaults: defaults,
                preferredLanguages: ["en-US"]
            ),
            "english"
        )

        ScreenTimeSharedContract.publishChildInterfaceLanguage(
            "chinese",
            defaults: defaults,
            now: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertEqual(
            ScreenTimeSharedContract.resolvedChildInterfaceLanguageRawValue(
                defaults: defaults,
                preferredLanguages: ["en-US"]
            ),
            "chinese"
        )

        defaults.removeObject(forKey: ScreenTimeSharedContract.childInterfaceLanguageSnapshotKey)
        defaults.set("english", forKey: ScreenTimeSharedContract.childInterfaceLanguageKey)
        XCTAssertEqual(
            ScreenTimeSharedContract.resolvedChildInterfaceLanguageRawValue(
                defaults: defaults,
                preferredLanguages: ["zh-CN"]
            ),
            "english",
            "旧版 App Group 语言值必须继续被 Shield Extension 识别"
        )
    }

    func testShieldRequestCarriesLanguageAcrossExtensionAndMainAppBoundary() throws {
        let request = PersistedShieldActionRequest(
            id: UUID(),
            intent: .redeemGrowthPoints,
            targetKind: .application,
            tokenData: Data([1, 2, 3]),
            createdAt: Date(timeIntervalSince1970: 1_000),
            interfaceLanguageRawValue: "english"
        )

        let decoded = try JSONDecoder().decode(
            PersistedShieldActionRequest.self,
            from: JSONEncoder().encode(request)
        )
        XCTAssertEqual(decoded.validatedInterfaceLanguageRawValue, "english")
        XCTAssertEqual(
            ScreenTimeSharedContract.shieldInterfaceLanguageRawValue(
                request: decoded,
                fallback: "chinese"
            ),
            "english"
        )
    }

    func testLegacyShieldRequestWithoutLanguageStillDecodesAndUsesFallback() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","intent":"redeemGrowthPoints","targetKind":"application","tokenData":"AQID","createdAt":1000}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let request = try decoder.decode(
            PersistedShieldActionRequest.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(request.validatedInterfaceLanguageRawValue)
        XCTAssertEqual(
            ScreenTimeSharedContract.shieldInterfaceLanguageRawValue(
                request: request,
                fallback: "chinese"
            ),
            "chinese"
        )
    }

    func testCurrentHostChildLanguageOverridesStaleShieldRequestLanguage() {
        let request = PersistedShieldActionRequest(
            id: UUID(),
            intent: .redeemGrowthPoints,
            targetKind: .application,
            tokenData: Data([1]),
            createdAt: Date(),
            interfaceLanguageRawValue: "chinese"
        )

        XCTAssertEqual(
            ScreenTimeSharedContract.hostInterfaceLanguageRawValue(
                currentChildLanguage: "english",
                request: request,
                fallback: "chinese"
            ),
            "english"
        )
    }

    func testHostLanguageUsesShieldRequestWhenCurrentChildLanguageIsUnavailable() {
        let request = PersistedShieldActionRequest(
            id: UUID(),
            intent: .redeemGrowthPoints,
            targetKind: .application,
            tokenData: Data([1]),
            createdAt: Date(),
            interfaceLanguageRawValue: "chinese"
        )

        XCTAssertEqual(
            ScreenTimeSharedContract.hostInterfaceLanguageRawValue(
                currentChildLanguage: nil,
                request: request,
                fallback: "english"
            ),
            "chinese"
        )
    }

    func testHostLanguageFallsBackToCurrentLanguageWithoutValidRequest() {
        XCTAssertEqual(
            ScreenTimeSharedContract.hostInterfaceLanguageRawValue(
                currentChildLanguage: "english",
                request: nil,
                fallback: "chinese"
            ),
            "english"
        )
    }

    // MARK: - 旧数据解码兼容

    func testLegacyChildProfileWithoutInterfaceLanguageDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"乐乐","age":8,"dailyLimitMinutes":60,"rewardBalanceMinutes":0}
        """
        let child = try JSONDecoder().decode(ChildProfile.self, from: Data(json.utf8))
        XCTAssertNil(child.interfaceLanguage)
    }

    func testLegacyFamilySettingsDecodingRemainsCompatible() throws {
        let chinese = try JSONDecoder().decode(
            FamilySettings.self,
            from: Data(#"{"language":"chinese"}"#.utf8)
        )
        XCTAssertEqual(chinese.resolvedParentInterfaceLanguage, .chinese)
        XCTAssertEqual(chinese.resolvedChildInterfaceLanguage, .chinese)

        let mixed = try JSONDecoder().decode(
            FamilySettings.self,
            from: Data(#"{"language":"chinese","parentInterfaceLanguage":"chinese","childInterfaceLanguage":"english"}"#.utf8)
        )
        XCTAssertEqual(mixed.resolvedParentInterfaceLanguage, .chinese)
        XCTAssertEqual(mixed.resolvedChildInterfaceLanguage, .english)
    }

    // MARK: - Root surface 语言 all-or-nothing

    func testRootSurfaceLanguageFollowsSelectedSurfaceOnly() {
        // 家长中文 + 孩子英文：孩子/学校 surface 全英文，其余全中文。
        for tab in OctoTeacherRootTab.allCases {
            let language = OctoTeacherRootTab.surfaceLanguage(
                selectedTag: tab.tag,
                parentLanguage: .chinese,
                activeChildLanguage: .english
            )
            if tab.isChildFacingSurface {
                XCTAssertEqual(language, .english, "\(tab) 应使用孩子语言")
            } else {
                XCTAssertEqual(language, .chinese, "\(tab) 应使用家长语言")
            }
        }
        // 未知 tag 回退到孩子 surface（默认首 Tab 是孩子）。
        XCTAssertEqual(
            OctoTeacherRootTab.surfaceLanguage(selectedTag: 999, parentLanguage: .chinese, activeChildLanguage: .english),
            .english
        )
    }

    func testRootTabLabelsAreSingleLanguagePerSurface() {
        let englishLabels = OctoTeacherRootTab.ordered.map { $0.label(for: .english) }
        XCTAssertFalse(englishLabels.contains(where: containsCJK), "英文 surface 下 Tab 标题不能混中文")
        let chineseLabels = OctoTeacherRootTab.ordered.map { $0.label(for: .chinese) }
        XCTAssertTrue(chineseLabels.allSatisfy(containsCJK), "中文 surface 下 Tab 标题应全中文")
    }

    func testGuardianChildPreviewLanguageIsIndependentFromActualChildLanguage() {
        XCTAssertEqual(
            GuardianChildPreviewLanguage.followChild.resolvedLanguage(childLanguage: .english),
            .english
        )
        XCTAssertEqual(
            GuardianChildPreviewLanguage.chinese.resolvedLanguage(childLanguage: .english),
            .chinese,
            "家长本机中文预览不能覆盖孩子手机的英文配置"
        )
        XCTAssertEqual(
            GuardianChildPreviewLanguage.english.resolvedLanguage(childLanguage: .chinese),
            .english
        )
        XCTAssertEqual(GuardianChildPreviewLanguagePreference.resolve(nil), .followChild)
        XCTAssertEqual(GuardianChildPreviewLanguagePreference.resolve("chinese"), .chinese)
        XCTAssertEqual(GuardianChildPreviewLanguagePreference.resolve("unknown"), .followChild)
    }

    // MARK: - 幼儿版英文文案无中文

    func testPreReaderEnglishVisibleAndSpeechCopyHasNoChinese() {
        var texts: [String] = [
            PreReaderHomeCopy.emptyTaskTitle(for: .english),
            PreReaderHomeCopy.emptyTaskDetail(for: .english),
            PreReaderHomeCopy.emptyTaskSpeech(for: .english),
            PreReaderHomeCopy.rewardLabel(points: 20, language: .english),
            PreReaderHomeCopy.taskSpeech(category: "Chores", title: "Tidy your desk", rewardPoints: 10, language: .english),
            PreReaderHomeCopy.greetingSpeech(childName: "Momo", done: 1, total: 3, nextTaskTitle: "Read a book", language: .english),
            PreReaderHomeCopy.greetingSpeech(childName: " ", done: 0, total: 0, nextTaskTitle: nil, language: .english)
        ]
        if let summary = PreReaderHomeCopy.progressSummary(done: 11, total: 14, language: .english) {
            texts.append(summary)
        }
        for text in texts {
            XCTAssertFalse(containsCJK(text), "英文幼儿版文案泄漏中文：\(text)")
        }
        // 中文默认签名保持不变（兼容既有测试与真机行为）。
        XCTAssertEqual(PreReaderHomeCopy.rewardLabel(points: 20), "20 成长积分")
    }

    // MARK: - TTS 音色映射

    func testSpeechReaderVoiceLocaleMapping() {
        XCTAssertEqual(SpeechReader.voiceLanguageCode(for: .english), "en-US")
        XCTAssertEqual(SpeechReader.voiceLanguageCode(for: .chinese), "zh-CN")
        // 显式语言优先于文本内容判断。
        XCTAssertEqual(SpeechReader.voiceLanguageCode(language: .english, text: "读一读这个"), "en-US")
        XCTAssertEqual(SpeechReader.voiceLanguageCode(language: .chinese, text: "read this"), "zh-CN")
        // 未指定语言时按内容自动判断（书本正文等场景）。
        XCTAssertEqual(SpeechReader.voiceLanguageCode(language: nil, text: "你好"), "zh-CN")
        XCTAssertEqual(SpeechReader.voiceLanguageCode(language: nil, text: "hello"), "en-US")
        XCTAssertNotEqual(
            SpeechCache.textKey("OK", voiceStyle: .warm, language: .english),
            SpeechCache.textKey("OK", voiceStyle: .warm, language: .chinese),
            "同一句短文本在不同孩子语言下不能复用错误音色的缓存"
        )
    }

    // MARK: - 任务展示语言

    func testCustomChineseTaskUsesLocalizedEnglishVersionForEnglishChild() {
        let task = TaskTemplate(
            id: UUID(),
            title: "帮妈妈择菜",
            category: .home,
            difficulty: .easy,
            rewardMinutes: 10,
            instructions: "把今晚要炒的青菜择好、洗干净。",
            requiredProof: .photo,
            localizedContent: [
                TaskLocalizedContent(
                    language: .english,
                    title: "Help Mom prep the vegetables",
                    instructions: "Trim and wash tonight's greens."
                )
            ]
        )
        XCTAssertEqual(task.displayTitle(for: .english), "Help Mom prep the vegetables")
        XCTAssertEqual(task.displayInstructions(for: .english), "Trim and wash tonight's greens.")
        // 原文永远保留，中文孩子仍看中文。
        XCTAssertEqual(task.displayTitle(for: .chinese), "帮妈妈择菜")
    }

    func testCustomTaskWithoutTranslationShowsExplicitPendingFallback() {
        // 中文自定义任务、无翻译缓存：英文孩子看到显式等待翻译提示，不静默看中文。
        let chineseTask = TaskTemplate(
            id: UUID(),
            title: "帮外婆包饺子",
            category: .home,
            difficulty: .easy,
            rewardMinutes: 10,
            instructions: "周末和外婆一起包二十个饺子。",
            requiredProof: .photo
        )
        let englishTitle = chineseTask.displayTitle(for: .english)
        XCTAssertEqual(englishTitle, "Task translation pending")
        XCTAssertFalse(containsCJK(englishTitle), "英文孩子的等待翻译提示不能带中文原文")
        let englishInstructions = chineseTask.displayInstructions(for: .english)
        XCTAssertFalse(containsCJK(englishInstructions))
        XCTAssertTrue(englishInstructions.hasPrefix("Ask a grown-up to finish the translation"))
        // 中文孩子不受影响。
        XCTAssertEqual(chineseTask.displayTitle(for: .chinese), "帮外婆包饺子")

        // 对称：纯英文自定义任务、无翻译缓存，中文孩子看到中文提示。
        let englishTask = TaskTemplate(
            id: UUID(),
            title: "Water the balcony plants",
            category: .home,
            difficulty: .easy,
            rewardMinutes: 5,
            instructions: "Give every pot on the balcony a small drink of water.",
            requiredProof: .photo
        )
        let chineseTitle = englishTask.displayTitle(for: .chinese)
        XCTAssertEqual(chineseTitle, "任务翻译准备中")
        XCTAssertFalse(chineseTitle.contains("Water the balcony plants"))
        XCTAssertEqual(englishTask.displayInstructions(for: .chinese), "请让大人完成翻译后再开始这个任务。")
        XCTAssertEqual(englishTask.displayTitle(for: .english), "Water the balcony plants")

        // 纯数字/表情不触发提示。
        XCTAssertFalse(TaskLanguageFallback.needsTranslationNotice("123 🎉", for: .chinese))
        XCTAssertFalse(TaskLanguageFallback.needsTranslationNotice("123 🎉", for: .english))
    }

    func testVideoResourceTitleRemainsVisibleAcrossInterfaceLanguages() {
        var task = TaskTemplate(
            id: UUID(),
            title: "How Volcanoes Work",
            category: .learning,
            difficulty: .easy,
            rewardMinutes: 15,
            instructions: "Watch the video.",
            requiredProof: .text
        )
        task.video = VideoSpec(
            urlString: "https://www.youtube.com/watch?v=volcano",
            platformLabel: "YouTube",
            minWatchMinutes: 8
        )

        XCTAssertEqual(task.displayTitle(for: .chinese), "How Volcanoes Work")
        XCTAssertEqual(task.displayTitle(for: .english), "How Volcanoes Work")
    }

    func testGenericVideoTitleUsesLocalizedLearningVideoFallback() {
        var task = TaskTemplate(
            id: UUID(),
            title: "看视频学习",
            category: .learning,
            difficulty: .easy,
            rewardMinutes: 15,
            instructions: "",
            requiredProof: .text
        )
        task.video = VideoSpec(
            urlString: "https://www.youtube.com/watch?v=lesson",
            platformLabel: "YouTube",
            minWatchMinutes: 5
        )

        XCTAssertEqual(task.displayTitle(for: .chinese), "学习视频")
        XCTAssertEqual(task.displayTitle(for: .english), "Learning Video")
    }

    func testBuiltInChineseTasksHaveDeterministicEnglishMapping() {
        // 种子任务与晚间节律包必须有确定性英文映射，英文模式不允许静默展示中文。
        let seedTitles = ["阅读 15 分钟", "整理书桌", "运动 20 分钟"]
        for title in seedTitles {
            let english = BuiltInTaskLocalization.englishTitle(for: title)
            XCTAssertNotNil(english, "内置任务缺英文映射：\(title)")
            XCTAssertFalse(containsCJK(english ?? ""), "映射结果仍含中文：\(title)")
        }
        for template in FirstEveningRoutinePlan.templates {
            XCTAssertNotNil(BuiltInTaskLocalization.englishTitle(for: template.title))
            XCTAssertNotNil(BuiltInTaskLocalization.englishInstructions(for: template.instructions))
        }
        for group in ParentPackTemplateLibrary.groups {
            for template in group.templates {
                XCTAssertNotNil(
                    BuiltInTaskLocalization.englishTitle(for: template.title),
                    "包模板缺英文标题映射：\(template.title)"
                )
                XCTAssertNotNil(
                    BuiltInTaskLocalization.englishInstructions(for: template.instructions),
                    "包模板缺英文说明映射：\(template.title)"
                )
            }
        }

        // 通过 displayTitle 接入：无翻译缓存时英文孩子看到确定性英文。
        let builtIn = TaskTemplate(
            id: UUID(),
            title: "整理书桌",
            category: .home,
            difficulty: .easy,
            rewardMinutes: 15,
            instructions: "把书桌整理到可以写作业或阅读的状态，拍一张照片给爸爸妈妈看。",
            requiredProof: .photo
        )
        XCTAssertEqual(builtIn.displayTitle(for: .english), "Tidy your desk")
        XCTAssertFalse(containsCJK(builtIn.displayInstructions(for: .english)))
        XCTAssertEqual(builtIn.displayTitle(for: .chinese), "整理书桌")
    }

    // MARK: - 今日任务工作台 / 奖励出口英文无中文

    func testTodayTaskWorkbenchEnglishChildSeesNoChineseDynamicCopy() {
        let store = LocalFamilyStore()
        store.setChildInterfaceLanguage(.english, for: store.activeChildId)

        let workbench = MobileTodayTaskPackageWorkbenchBuilder().build(store: store)
        XCTAssertFalse(workbench.cards.isEmpty, "种子任务应生成任务卡")
        for card in workbench.cards {
            XCTAssertFalse(containsCJK(card.title), "英文任务卡标题泄漏中文：\(card.title)")
            XCTAssertFalse(containsCJK(card.categoryLabel), "英文类别泄漏中文：\(card.categoryLabel)")
            XCTAssertFalse(containsCJK(card.nextStep), "英文 nextStep 泄漏中文：\(card.nextStep)")
            XCTAssertFalse(containsCJK(card.creditHint), "英文 creditHint 泄漏中文：\(card.creditHint)")
            XCTAssertFalse(containsCJK(card.state.label(for: .english)))
            XCTAssertFalse(containsCJK(card.proof.label(for: .english)))
        }
        XCTAssertFalse(containsCJK(workbench.packTitle), "英文成长包标题泄漏中文：\(workbench.packTitle)")
        XCTAssertFalse(containsCJK(workbench.packSummary), "英文成长包摘要泄漏中文：\(workbench.packSummary)")
        XCTAssertFalse(containsCJK(workbench.credit.headline(for: .english)))
    }

    @MainActor
    func testRewardPathwayEnglishChildOutletsHaveNoChinese() {
        let store = LocalFamilyStore()
        store.setChildInterfaceLanguage(.english, for: store.activeChildId)
        // 孩子昵称是用户数据可以是中文；这里改成英文名，专门检验模板文案本身。
        store.updateChildProfile(
            childId: store.activeChildId,
            name: "Momo",
            age: store.child.age,
            dailyLimitMinutes: store.child.dailyLimitMinutes
        )
        let snapshot = RewardPathwayBuilder().build(
            store: store,
            screenTime: MockScreenTimeController(),
            viewerRole: .child
        )
        XCTAssertFalse(containsCJK(snapshot.title))
        XCTAssertFalse(containsCJK(snapshot.headline))
        for outlet in snapshot.outlets {
            for text in [outlet.title, outlet.childExplanation, outlet.status, outlet.availability, outlet.nextStep, outlet.speakText] {
                XCTAssertFalse(containsCJK(text), "英文奖励出口泄漏中文：\(text)")
            }
        }
        for note in snapshot.safetyNotes {
            XCTAssertFalse(containsCJK(note))
        }
    }

    // MARK: - 第二轮：孩子端 copy API 英文输出 CJK 扫描

    func testChildVideoPlayerCopyEnglishHasNoChinese() {
        for text in ChildVideoPlayerCopy.allUserFacingPlaybackHelp(for: .english) {
            XCTAssertFalse(containsCJK(text), "英文视频播放帮助泄漏中文：\(text)")
        }
        // 中文默认集合保持中文（兼容既有测试与中文孩子）。
        XCTAssertTrue(ChildVideoPlayerCopy.allUserFacingPlaybackHelp.allSatisfy(containsCJK))
    }

    func testQuizAndBadgeCopyEnglishHasNoChinese() {
        for subject in LearningSubject.allCases {
            XCTAssertFalse(containsCJK(subject.label(for: .english)), "英文学科名泄漏中文：\(subject)")
            XCTAssertTrue(containsCJK(subject.label(for: .chinese)))
        }
        for tier in BadgeLadder.tiers {
            let english = BadgeLadder.displayName(tier.name, for: .english)
            XCTAssertFalse(containsCJK(english), "英文徽章名泄漏中文：\(tier.name)")
            XCTAssertEqual(BadgeLadder.displayName(tier.name, for: .chinese), tier.name)
        }
        for text in [
            ChildQuizResultCopy.summary(correct: 5, subject: .science, language: .english),
            ChildQuizResultCopy.speakText(correct: 5, subject: .science, language: .english)
        ] {
            XCTAssertFalse(containsCJK(text), "英文小考试结果文案泄漏中文：\(text)")
        }
        // 默认签名保持中文，兼容既有调用。
        XCTAssertTrue(containsCJK(ChildQuizResultCopy.summary(correct: 5, subject: .science)))
    }

    func testEconomyChildLabelsEnglishHaveNoChinese() {
        let kinds: [MoneyLedgerEntryKind] = [.baseAllowance, .creditExchange, .parentAdjustment]
        for kind in kinds {
            XCTAssertFalse(containsCJK(kind.label(for: .english)))
            XCTAssertTrue(containsCJK(kind.label(for: .chinese)))
        }
        let statuses: [MoneyLedgerEntryStatus] = [.awaitingApproval, .pendingPayout, .paid, .rejected]
        for status in statuses {
            XCTAssertFalse(containsCJK(status.label(for: .english)))
        }
        let wishStatuses: [WishStatus] = [.proposed, .priced, .redeemed, .fulfilled, .rejected]
        for status in wishStatuses {
            XCTAssertFalse(containsCJK(status.label(for: .english)))
            XCTAssertTrue(containsCJK(status.label(for: .chinese)))
        }
    }

    func testOfflineOutboxChildCopyEnglishHasNoChinese() {
        for role in MobileOfflineActorRole.allCases {
            XCTAssertFalse(containsCJK(role.label(for: .english)))
        }
        for kind in MobileOfflineMutationKind.allCases {
            XCTAssertFalse(containsCJK(kind.label(for: .english)))
        }
        let statuses: [MobileOfflineMutationStatus] = [.pending, .conflict, .rolledBack]
        for status in statuses {
            XCTAssertFalse(containsCJK(status.label(for: .english)))
            XCTAssertTrue(containsCJK(status.label(for: .chinese)))
        }
        let reasons: [MobileOfflineConflictReason] = [
            .duplicateReplay, .staleVersion, .alreadyResolved, .supersededByGuardian
        ]
        for reason in reasons {
            XCTAssertFalse(containsCJK(reason.hint(for: .english)), "英文冲突提示泄漏中文：\(reason)")
            XCTAssertFalse(containsCJK(reason.nextStep(for: .english)), "英文下一步泄漏中文：\(reason)")
            XCTAssertTrue(containsCJK(reason.hint(for: .chinese)))
        }
    }

    func testProofSubmissionEncouragementFollowsChildLanguage() {
        let task = TaskTemplate(
            id: UUID(),
            title: "阅读 15 分钟",
            category: .learning,
            difficulty: .easy,
            rewardMinutes: 10,
            instructions: "读一本书或一篇文章，然后写下一句今天学到的内容。",
            requiredProof: .text
        )
        let proof = ProofDraft(kind: .text, text: "I read a story about whales.", photoPlaceholderName: nil, status: .submitted)
        let english = ChildProofSubmissionEncouragement.make(task: task, proof: proof, rewardMinutes: 10, language: .english)
        for text in english.displayValues {
            XCTAssertFalse(containsCJK(text), "英文提交鼓励语泄漏中文：\(text)")
        }
        let chinese = ChildProofSubmissionEncouragement.make(task: task, proof: proof, rewardMinutes: 10)
        XCTAssertTrue(chinese.displayValues.allSatisfy(containsCJK), "中文孩子提交鼓励语应保持中文")
    }

    func testCreativeFeedbackAndLocalReviewFollowChildLanguage() {
        let task = TaskTemplate(
            id: UUID(),
            title: "做一个小手工",
            category: .creative,
            difficulty: .easy,
            rewardMinutes: 10,
            instructions: "用家里的材料做一个小手工，拍照留念。",
            requiredProof: .photo
        )
        let statuses: [TaskAssignmentStatus] = [.open, .submitted, .approved, .rejected, .cancelled]
        for status in statuses {
            let assignment = TaskAssignment(
                id: UUID(),
                childId: UUID(),
                task: task,
                date: Date(timeIntervalSince1970: 1_750_000_000),
                status: status,
                proof: ProofDraft(kind: .photo, text: "", photoPlaceholderName: nil, status: .empty)
            )
            XCTAssertFalse(
                containsCJK(CreativeCenterCopy.childFeedback(for: assignment, language: .english)),
                "英文创作反馈泄漏中文：\(status)"
            )
            XCTAssertTrue(containsCJK(CreativeCenterCopy.childFeedback(for: assignment, language: .chinese)))
        }

        // 本地兜底初评的 childFeedback 跟随孩子语言；summary 面向家长保持中文。
        let englishReview = AIProofReviewer.localReview(
            task: task,
            childText: "I glued two boxes together to make a robot.",
            proofKind: .photo,
            hasLocalPhoto: true,
            childLanguage: .english
        )
        XCTAssertFalse(containsCJK(englishReview.childFeedback ?? ""), "英文本地初评点评泄漏中文")
        let chineseReview = AIProofReviewer.localReview(
            task: task,
            childText: "我做了一个纸盒机器人。",
            proofKind: .photo,
            hasLocalPhoto: true
        )
        XCTAssertTrue(containsCJK(chineseReview.childFeedback ?? ""))
        // 云端初评 prompt 会按孩子语言要求 childFeedback 的语言。
        XCTAssertTrue(AIProofReviewer.systemPrompt(childLanguage: .english).contains("英文"))
    }

    func testAICompanionShellLabelsEnglishHaveNoChinese() {
        for mode in AICompanionMode.allCases {
            XCTAssertFalse(containsCJK(mode.label(for: .english)))
            XCTAssertTrue(containsCJK(mode.label(for: .chinese)))
        }
        for question in AICompanionPresetQuestion.allCases {
            XCTAssertFalse(containsCJK(question.label(for: .english)))
        }
        for style in AICompanionVoiceStyle.allCases {
            XCTAssertFalse(containsCJK(style.label(for: .english)))
        }
    }

    func testReadingAndWishCopyEnglishHasNoChinese() {
        var texts: [String] = [
            ChildReadingProgressCopy.label(seconds: 200, targetMinutes: 15, isPreReader: false, language: .english),
            ChildReadingProgressCopy.label(seconds: 1_000, targetMinutes: 15, isPreReader: true, language: .english),
            ChildReadingProgressCopy.numericLabel(seconds: 95, language: .english),
            ChildWishListCopy.emptyTitle(for: .english),
            ChildWishListCopy.emptyDetail(for: .english),
            ChildWishListCopy.emptySpeakText(for: .english),
            ChildWishListCopy.footer(for: .english)
        ]
        texts += ChildVideoPlayerCopy.allUserFacingPlaybackHelp(for: .english)
        for text in texts {
            XCTAssertFalse(containsCJK(text), "英文阅读/愿望文案泄漏中文：\(text)")
        }
        // 中文默认签名不受影响。
        XCTAssertTrue(containsCJK(ChildReadingProgressCopy.numericLabel(seconds: 95)))
    }

    func testTodayWorkbenchFindingsAndOfflineHintFollowChildLanguage() {
        let store = LocalFamilyStore()
        store.setChildInterfaceLanguage(.english, for: store.activeChildId)
        let workbench = MobileTodayTaskPackageWorkbenchBuilder().build(store: store)
        for finding in workbench.findings {
            XCTAssertFalse(containsCJK(finding.message), "英文工作台发现项泄漏中文：\(finding.message)")
        }
        XCTAssertFalse(containsCJK(workbench.offlineHint.title))
        XCTAssertFalse(containsCJK(workbench.offlineHint.message))

        store.setChildInterfaceLanguage(.chinese, for: store.activeChildId)
        let chineseWorkbench = MobileTodayTaskPackageWorkbenchBuilder().build(store: store)
        XCTAssertTrue(chineseWorkbench.findings.allSatisfy { containsCJK($0.message) }, "中文孩子发现项应保持中文")
    }

    // MARK: - 语言切换互不影响

    func testSwitchingActiveChildKeepsWorkbenchLanguageInSync() throws {
        let store = LocalFamilyStore()
        let first = store.activeChildId
        let second = try XCTUnwrap(store.addChild(name: "妹妹", age: 5))
        store.setChildInterfaceLanguage(.chinese, for: first)
        store.setChildInterfaceLanguage(.english, for: second.id)
        store.assignNewTask(
            title: "整理书桌",
            instructions: "把书桌整理到可以写作业或阅读的状态，拍一张照片给爸爸妈妈看。",
            category: .home,
            rewardMinutes: 10,
            requiredProof: .photo,
            childId: second.id
        )

        store.setActiveChild(first)
        let chineseWorkbench = MobileTodayTaskPackageWorkbenchBuilder().build(store: store)
        XCTAssertTrue(chineseWorkbench.cards.allSatisfy { containsCJK($0.title) }, "中文孩子应看到中文任务")

        store.setActiveChild(second.id)
        let englishWorkbench = MobileTodayTaskPackageWorkbenchBuilder().build(store: store)
        XCTAssertTrue(englishWorkbench.cards.allSatisfy { !containsCJK($0.title) }, "英文孩子不应看到中文任务标题")
    }
}
