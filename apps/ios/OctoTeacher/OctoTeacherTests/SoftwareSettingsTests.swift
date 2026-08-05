import XCTest
@testable import OctoTeacher

final class SoftwareSettingsTests: XCTestCase {
    func testLegacySettingsResolveInterfaceLanguagesWithoutMigration() throws {
        let chinese = try JSONDecoder().decode(
            FamilySettings.self,
            from: Data(#"{"language":"chinese"}"#.utf8)
        )
        XCTAssertEqual(chinese.resolvedParentInterfaceLanguage, .chinese)
        XCTAssertEqual(chinese.resolvedChildInterfaceLanguage, .chinese)
        XCTAssertEqual(chinese.resolvedSchoolIntegration, .disconnected)

        let english = try JSONDecoder().decode(
            FamilySettings.self,
            from: Data(#"{"language":"english"}"#.utf8)
        )
        XCTAssertEqual(english.resolvedParentInterfaceLanguage, .english)
        XCTAssertEqual(english.resolvedChildInterfaceLanguage, .english)
    }

    func testParentAndChildInterfaceLanguagesAreIndependentAndPersisted() throws {
        let store = LocalFamilyStore()
        store.setParentInterfaceLanguage(.chinese)
        store.setChildInterfaceLanguage(.english)
        store.setRegion(.usa)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(FamilyStoreSnapshot.self, from: encoder.encode(store.snapshot))
        XCTAssertEqual(decoded.settings?.resolvedParentInterfaceLanguage, .chinese)
        XCTAssertEqual(decoded.settings?.resolvedChildInterfaceLanguage, .english)
        XCTAssertEqual(decoded.settings?.resolvedRegion, .usa)
    }

    func testSchoolIntegrationConsentIsAStoredContractNotAFakeConnection() {
        let store = LocalFamilyStore()
        var integration = store.settings.resolvedSchoolIntegration
        integration.allowsTeacherAssignments = true
        integration.sharesHomeworkCompletion = true
        store.setSchoolIntegration(integration)

        XCTAssertEqual(store.settings.resolvedSchoolIntegration.status, .notConnected)
        XCTAssertTrue(store.settings.resolvedSchoolIntegration.allowsTeacherAssignments)
        XCTAssertTrue(store.settings.resolvedSchoolIntegration.sharesHomeworkCompletion)
    }

    func testTaskLocalizedContentKeepsParentOriginalAndSelectsChildCopy() {
        let task = TaskTemplate(
            id: UUID(),
            title: "整理书包",
            category: .home,
            difficulty: .easy,
            rewardMinutes: 10,
            instructions: "把明天的书放进去。",
            requiredProof: .text,
            localizedContent: [
                TaskLocalizedContent(
                    language: .english,
                    title: "Pack your school bag",
                    instructions: "Put tomorrow's books in your bag."
                )
            ]
        )

        XCTAssertEqual(task.title, "整理书包")
        XCTAssertEqual(task.displayTitle(for: .english), "Pack your school bag")
        XCTAssertEqual(task.displayInstructions(for: .english), "Put tomorrow's books in your bag.")
        XCTAssertEqual(task.displayTitle(for: .chinese), "整理书包")
    }

    func testTaskTranslatorDetectsCrossLanguageNeedsAndParsesStrictJSON() throws {
        XCTAssertTrue(AITaskTranslator.needsTranslation(
            title: "整理书包",
            instructions: "放好课本",
            target: .english
        ))
        XCTAssertFalse(AITaskTranslator.needsTranslation(
            title: "Pack your bag",
            instructions: "Put your books inside.",
            target: .english
        ))
        let translated = try XCTUnwrap(AITaskTranslator.parse(
            #"{"title":"Pack your bag","instructions":"Put tomorrow's books inside."}"#,
            language: .english
        ))
        XCTAssertEqual(translated.language, .english)
        XCTAssertEqual(translated.title, "Pack your bag")
    }

    func testTaskBatchTranslatorRequiresEveryExpectedTask() throws {
        let first = UUID()
        let second = UUID()
        let raw = """
        {"tasks":[
          {"id":"\(first.uuidString)","title":"Pack your bag","instructions":"Put the books inside."},
          {"id":"\(second.uuidString)","title":"Brush your teeth","instructions":"Brush for two minutes."}
        ]}
        """
        let result = try XCTUnwrap(AITaskTranslator.parseBatch(
            raw,
            language: .english,
            expectedIDs: [first, second]
        ))
        XCTAssertEqual(result[first]?.title, "Pack your bag")
        XCTAssertEqual(result[second]?.title, "Brush your teeth")
        XCTAssertNil(AITaskTranslator.parseBatch(
            raw,
            language: .english,
            expectedIDs: [first, second, UUID()]
        ))
    }

    func testRootTabsHaveExplicitEnglishLabels() {
        XCTAssertEqual(OctoTeacherRootTab.child.label(for: .english), "Child")
        XCTAssertEqual(OctoTeacherRootTab.parent.label(for: .english), "Parent")
        XCTAssertEqual(OctoTeacherRootTab.more.label(for: .english), "More")
    }

    func testParentTaskPlanningCopyHasExplicitEnglishLabels() {
        XCTAssertEqual(ParentTaskStarterPreset.reading20.menuTitle(for: .english), "Read for 20 Minutes")
        XCTAssertEqual(ParentTaskStarterPreset.outdoorPlay.menuTitle(for: .english), "Play Outside")
        XCTAssertEqual(ParentTaskStarterPreset.tidyDesk.menuTitle(for: .english), "Tidy the Desk")
        XCTAssertEqual(ParentTaskStarterPreset.sleepReady.menuTitle(for: .english), "Get Ready for Bed")
        XCTAssertEqual(TaskCategory.learning.label(for: .english), "Learning")
        XCTAssertEqual(RejectionReason.proofUnclear.label(for: .english), "The proof is hard to see")
    }

    func testProviderSettingsEnglishCopyHasNoChineseLeakage() {
        for provider in AIProviderKind.allCases {
            assertHasNoHan(ParentAIProviderSettingsCopy.providerLabel(provider, language: .english))
            assertHasNoHan(ParentAIProviderSettingsCopy.providerBlurb(provider, language: .english))
        }

        let results: [AIProviderConnectionResult] = [
            .ok,
            .notConfigured,
            .unauthorized,
            .failed(statusCode: 429),
            .unreachable,
        ]
        for result in results {
            assertHasNoHan(ParentAIProviderSettingsCopy.connectionMessage(result, language: .english))
        }

        assertHasNoHan(ParentAICompanionImageConsentCopy.providerUnsupported(.english))
        assertHasNoHan(ParentAICompanionImageConsentCopy.disabledUntilGuidance(.english))
        assertHasNoHan(ParentAICompanionImageConsentCopy.readyFooter(.english))
    }

    func testProviderSettingsChineseCopyRemainsChinese() {
        XCTAssertTrue(containsHan(ParentAIProviderSettingsCopy.providerLabel(.alibabaQwen, language: .chinese)))
        XCTAssertTrue(containsHan(ParentAIProviderSettingsCopy.providerBlurb(.openAI, language: .chinese)))
        XCTAssertTrue(containsHan(ParentAIProviderSettingsCopy.connectionMessage(.ok, language: .chinese)))
        XCTAssertTrue(containsHan(ParentAICompanionImageConsentCopy.readyFooter(.chinese)))
    }

    func testReadingComposerEnglishCatalogAndVerificationCopyHasNoChineseLeakage() {
        for category in BookCategory.allCases {
            assertHasNoHan(ParentAIReadingComposerCopy.categoryTitle(category, language: .english))
            assertHasNoHan(ParentAIReadingComposerCopy.categoryAgeHint(category, language: .english))
        }
        for mode in TaskVerificationMode.allCases {
            assertHasNoHan(ParentAIReadingComposerCopy.verificationModeLabel(mode, language: .english))
        }
        for kind in TaskVerificationContentKind.allCases {
            assertHasNoHan(ParentAIReadingComposerCopy.contentKindLabel(kind, language: .english))
        }
        assertHasNoHan(ParentAIReadingComposerCopy.growthPoints(20, language: .english))
        assertHasNoHan(ParentAIReadingComposerCopy.downloadCandidateDetail(language: .english))
        assertHasNoHan(ParentAIReadingComposerCopy.downloadCandidateLicense(language: .english))
    }

    func testReadingComposerChineseCatalogAndVerificationCopyRemainsChinese() {
        XCTAssertEqual(
            ParentAIReadingComposerCopy.categoryTitle(.alphabet, language: .chinese),
            BookCategory.alphabet.rawValue
        )
        XCTAssertTrue(containsHan(ParentAIReadingComposerCopy.categoryAgeHint(.alphabet, language: .chinese)))
        XCTAssertTrue(containsHan(ParentAIReadingComposerCopy.verificationModeLabel(.choiceQuiz, language: .chinese)))
        XCTAssertTrue(containsHan(ParentAIReadingComposerCopy.contentKindLabel(.story, language: .chinese)))
        XCTAssertTrue(containsHan(ParentAIReadingComposerCopy.growthPoints(20, language: .chinese)))
    }

    func testReadingComposerGenerationPromptsFollowParentInterfaceLanguage() {
        let recommendation = ParentAIReadingComposerCopy.recommendationSystemPrompt(
            contentLanguage: .chinese,
            parentInterfaceLanguage: .english
        )
        XCTAssertTrue(recommendation.contains("blurb 是给家长看的：Write all task content in English."))

        let englishPlan = ParentAIReadingComposerCopy.readingPlanSystemPrompt(parentInterfaceLanguage: .english)
        XCTAssertTrue(englishPlan.contains("intro, sessions[].chapters, and sessions[].note must all be written in English"))

        let chinesePlan = ParentAIReadingComposerCopy.readingPlanSystemPrompt(parentInterfaceLanguage: .chinese)
        XCTAssertTrue(chinesePlan.contains("chapters 用中文描述"))
        XCTAssertFalse(chinesePlan.contains("must all be written in English"))

        let localDraft = ReadingSessionDraft(
            order: 1,
            chapters: "第 1-2 章：第一章 到 第二章",
            estimatedMinutes: 60,
            note: "幼儿图文书按每两章一次自动划分。"
        )
        let localizedDraft = ParentAIReadingComposerCopy.parentLocalizedDrafts(
            [localDraft],
            language: .english
        )[0]
        assertHasNoHan(localizedDraft.chapters)
        assertHasNoHan(localizedDraft.note)
        XCTAssertEqual(localizedDraft.chapters, "Chapters 1-2")
        XCTAssertEqual(localizedDraft.startCharacter, localDraft.startCharacter)
        XCTAssertEqual(localizedDraft.endCharacter, localDraft.endCharacter)
    }

    func testReadingComposerChildTaskCopyUsesResolvedContentAndInterfaceLanguage() {
        XCTAssertEqual(
            ParentAIReadingComposerCopy.childTaskLanguage(contentLanguage: .english, interfaceLanguage: .chinese),
            .english
        )
        XCTAssertEqual(
            ParentAIReadingComposerCopy.childTaskLanguage(contentLanguage: .chinese, interfaceLanguage: .english),
            .chinese
        )
        XCTAssertEqual(
            ParentAIReadingComposerCopy.childTaskLanguage(contentLanguage: .bilingual, interfaceLanguage: .english),
            .english
        )

        let englishTitle = ParentAIReadingComposerCopy.childTaskTitle(
            bookTitle: "Charlotte's Web",
            order: 2,
            language: .english
        )
        let englishInstructions = ParentAIReadingComposerCopy.childTaskInstructions(
            note: "本章生词较多，可陪读。",
            language: .english
        )
        let englishChapters = ParentAIReadingComposerCopy.childChapterPlan(
            "第 3-5 章：Wilbur 到 Charlotte",
            order: 2,
            sessionCount: 4,
            language: .english
        )
        assertHasNoHan(englishTitle)
        assertHasNoHan(englishInstructions)
        assertHasNoHan(englishChapters)
        XCTAssertEqual(englishChapters, "Chapters 3-5")

        XCTAssertTrue(containsHan(ParentAIReadingComposerCopy.childTaskTitle(
            bookTitle: "夏洛的网",
            order: 2,
            language: .chinese
        )))
        XCTAssertEqual(
            ParentAIReadingComposerCopy.childChapterPlan("第 3-5 章", order: 2, sessionCount: 4, language: .chinese),
            "第 3-5 章"
        )
    }

    private func assertHasNoHan(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(containsHan(value), "Unexpected Chinese copy: \(value)", file: file, line: line)
    }

    private func containsHan(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}
