import SwiftUI

enum ChildQuizResultCopy {
    static func summary(correct: Int, subject: LearningSubject, language: AppInterfaceLanguage = .chinese) -> String {
        let subjectLabel = subject.label(for: language)
        return language.pick(
            "获得 \(GrowthCreditCopy.label(points: correct))，\(subjectLabel)成长进度已更新。",
            "You earned \(GrowthCreditCopy.label(points: correct, language: .english)), and your \(subjectLabel) progress is updated."
        )
    }

    static func speakText(correct: Int, subject: LearningSubject, language: AppInterfaceLanguage = .chinese) -> String {
        let subjectLabel = subject.label(for: language)
        return language.pick(
            "答对 \(max(0, correct)) 题，获得 \(GrowthCreditCopy.label(points: correct))。\(subjectLabel)成长进度也更新了，继续加油！",
            "You got \(max(0, correct)) questions right and earned \(GrowthCreditCopy.label(points: correct, language: .english)). Your \(subjectLabel) progress is updated too — keep going!"
        )
    }
}

/// 孩子端 AI 考试：针对刚学完的内容出 5-10 道选择题。
/// 答错立即显示答案和推理过程（可朗读）；每个任务只能考一次，防刷分。
struct ChildQuizView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @Environment(\.dismiss) private var dismiss

    let assignment: TaskAssignment
    let subject: LearningSubject
    let awardsProgressOnFinish: Bool

    @State private var questions: [QuizQuestion] = []
    @State private var currentIndex = 0
    @State private var selectedOption: Int?
    @State private var correctCount = 0
    @State private var isLoading = true
    @State private var isFinished = false
    @State private var loadFailed = false

    private let optionColors: [Color] = [.blue, .orange, .green, .purple]

    /// 当前孩子的界面语言：题目壳、结果和朗读提示都从这里取。
    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    init(assignment: TaskAssignment, subject: LearningSubject, awardsProgressOnFinish: Bool = true) {
        self.assignment = assignment
        self.subject = subject
        self.awardsProgressOnFinish = awardsProgressOnFinish
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(loc.pick("AI 老师正在出题……", "Your AI teacher is writing questions…"))
                        .font(.headline)
                }
            } else if loadFailed {
                ContentUnavailableView(
                    loc.pick("这次出题没成功", "The quiz didn't load this time"),
                    systemImage: "wifi.slash",
                    description: Text(loc.pick("过一会儿再来试试。", "Come back and try again in a little while."))
                )
            } else if isFinished {
                resultView
            } else {
                questionView
            }
        }
        .navigationTitle(loc.pick(
            "\(subject.label(for: loc.language))小考试",
            "\(subject.label(for: loc.language)) Mini Quiz"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadQuestions() }
    }

    // MARK: - 题目

    private var questionView: some View {
        let question = questions[currentIndex]
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(loc.pick(
                        "第 \(currentIndex + 1) / \(questions.count) 题",
                        "Question \(currentIndex + 1) of \(questions.count)"
                    ))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    // 题干和选项是 AI 生成的数据内容，语言不强制指定，由朗读器按文本自动判断。
                    SpeakButton(text: questionSpeechText(question))
                }
                Text(question.question)
                    .font(.title3.bold())

                ForEach(question.options.indices, id: \.self) { index in
                    Button {
                        answer(index)
                    } label: {
                        HStack {
                            Image(systemName: "\(index + 1).circle.fill")
                                .font(.title2)
                            Text(question.options[index])
                                .font(.body)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if let selected = selectedOption {
                                if index == question.answerIndex {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                } else if index == selected {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(optionColors[index % 4].opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedOption != nil)
                    .accessibilityIdentifier("quiz-option-\(index)")
                }

                if let selected = selectedOption {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(
                                selected == question.answerIndex
                                    ? loc.pick("答对啦！", "You got it!")
                                    : loc.pick("没关系，看看为什么", "It's okay — let's see why"),
                                systemImage: selected == question.answerIndex ? "hand.thumbsup.fill" : "lightbulb.fill"
                            )
                            .font(.headline)
                            .foregroundStyle(selected == question.answerIndex ? .green : .orange)
                            Spacer()
                            // 解析是 AI 生成的数据内容，朗读语言自动判断。
                            SpeakButton(text: question.explanation)
                        }
                        if !question.explanation.isEmpty {
                            Text(question.explanation)
                                .font(.callout)
                        }
                        Button {
                            next()
                        } label: {
                            Label(
                                currentIndex + 1 < questions.count
                                    ? loc.pick("下一题", "Next question")
                                    : loc.pick("看成绩", "See my score"),
                                systemImage: "arrow.right.circle.fill"
                            )
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("quiz-next")
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
        }
    }

    /// 朗读整题：题干 + 每个选项。「选项 n」是壳文案跟随界面语言；
    /// 题干/选项本身是数据内容，保持原文。
    private func questionSpeechText(_ question: QuizQuestion) -> String {
        let separator = loc.pick("。", ". ")
        let options = question.options.enumerated().map { pair in
            loc.pick("选项\(pair.offset + 1)：\(pair.element)", "Option \(pair.offset + 1): \(pair.element)")
        }
        return question.question + separator + options.joined(separator: separator)
    }

    // MARK: - 成绩

    private var resultView: some View {
        VStack(spacing: 16) {
            Image(systemName: correctCount * 2 >= questions.count ? "trophy.fill" : "star.fill")
                .font(.system(size: 64))
                .foregroundStyle(.yellow)
            Text(loc.pick(
                "答对 \(correctCount) / \(questions.count) 题",
                "\(correctCount) of \(questions.count) correct"
            ))
                .font(.title.bold())
            Text(ChildQuizResultCopy.summary(correct: correctCount, subject: subject, language: loc.language))
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack {
                SpeakButton(
                    text: ChildQuizResultCopy.speakText(correct: correctCount, subject: subject, language: loc.language),
                    language: loc.language
                )
                Button {
                    dismiss()
                } label: {
                    Label(loc.pick("完成", "Done"), systemImage: "checkmark.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - 动作

    private func loadQuestions() async {
        do {
            let verification = assignment.task.verification
            let minutes = assignment.task.video?.minWatchMinutes
                ?? assignment.task.reading?.minMinutes
                ?? assignment.task.rewardMinutes
            let count = verification?.resolvedQuestionCount ?? AIQuizGenerator.questionCount(forMinutes: minutes)
            let raw = try await aiProvider.completeDraftJSON(
                system: AIQuizGenerator.systemPrompt(
                    language: store.activeContentLanguage,
                    count: count,
                    contentKind: verification?.contentKind
                ),
                user: AIQuizGenerator.userPrompt(
                    task: assignment.task,
                    childAge: store.child.age,
                    contentExcerpt: learningContentExcerpt()
                ),
                using: OpenAIStyleChatClient()
            )
            let parsed = AIQuizGenerator.parse(raw)
            if parsed.isEmpty {
                loadFailed = true
            } else {
                questions = parsed
            }
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func answer(_ index: Int) {
        guard selectedOption == nil else { return }
        selectedOption = index
        if index == questions[currentIndex].answerIndex {
            correctCount += 1
        }
    }

    private func next() {
        if currentIndex + 1 < questions.count {
            currentIndex += 1
            selectedOption = nil
        } else {
            isFinished = true
            if awardsProgressOnFinish {
                _ = store.recordQuizResult(
                    assignmentId: assignment.id,
                    subject: subject,
                    correct: correctCount,
                    total: questions.count
                )
            } else {
                let ratio = questions.isEmpty ? 0 : Double(correctCount) / Double(questions.count)
                // 家长端审核摘要（孩子不可见），保持中文。
                store.attachAIReview(
                    AIReviewSummary(
                        confidence: ratio,
                        summary: "孩子完成了学习验收小测，答对 \(correctCount) / \(questions.count) 题。请结合阅读/观看过程最终判断。",
                        recommendation: ratio >= 0.6 ? "suggest_approve" : "needs_parent_judgment",
                        source: "local_rule"
                    ),
                    to: assignment.id
                )
            }
        }
    }

    private func learningContentExcerpt() -> String? {
        if let summary = assignment.task.verification?.parentApprovedSummary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        if let summary = assignment.task.video?.contentSummary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        guard let reading = assignment.task.reading else { return nil }
        if let book = store.book(for: reading),
           let excerpt = BookFileStore.shared.readingExcerpt(book: book, reading: reading) {
            return excerpt
        }
        return reading.inAppContent.map { String($0.prefix(4_000)) }
    }
}

/// 孩子端徽章馆：每个学科的千小时进度与当前徽章，终点是诺贝尔级。
struct ChildBadgesView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage

    /// 当前孩子的界面语言：徽章页所有可见文案与朗读都从这里取。
    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    var body: some View {
        List {
            Section {
                ForEach(LearningSubject.allCases) { subject in
                    let entry = store.progressEntry(subject: subject, childId: store.activeChildId)
                    let hours = entry.studyHours
                    let current = BadgeLadder.currentTier(hours: hours)
                    let next = BadgeLadder.nextTier(hours: hours)
                    let subjectLabel = subject.label(for: loc.language)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(subjectLabel, systemImage: subject.systemImage)
                                .font(.headline)
                            Spacer()
                            if let current {
                                Label(
                                    BadgeLadder.displayName(current.name, for: loc.language),
                                    systemImage: current.icon
                                )
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.orange)
                            } else {
                                Text(loc.pick("还没有徽章", "No badge yet"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            SpeakButton(
                                text: badgeSpeechText(
                                    subjectLabel: subjectLabel,
                                    hours: hours,
                                    current: current,
                                    next: next
                                ),
                                language: loc.language
                            )
                        }
                        if let next {
                            ProgressView(value: min(hours, next.hours), total: next.hours)
                                .tint(.orange)
                            Text(nextTierCaption(hours: hours, next: next, quizPoints: entry.quizPoints))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Label(
                                loc.pick("已达成诺贝尔级！", "Nobel Level reached!"),
                                systemImage: "trophy.fill"
                            )
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.yellow)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(loc.pick("我的学科徽章", "My Subject Badges"))
            } footer: {
                Text(loc.pick(
                    "认真学习和考试都会累积学时；每个学科学满 1000 小时就能拿到最高的诺贝尔级徽章——很少有人能做到，试试看！",
                    "Studying and quizzes both add learning hours. Reach 1000 hours in a subject to earn the top Nobel Level badge — very few people ever do. Give it a try!"
                ))
            }
        }
        .navigationTitle(loc.pick("徽章馆", "Badge Hall"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 小喇叭朗读：学科进度 + 当前徽章 + 下一个目标。
    private func badgeSpeechText(
        subjectLabel: String,
        hours: Double,
        current: (hours: Double, name: String, icon: String)?,
        next: (hours: Double, name: String, icon: String)?
    ) -> String {
        let currentPart = current.map { tier in
            loc.pick(
                "现在是\(tier.name)徽章。",
                "Your badge right now is \(BadgeLadder.displayName(tier.name, for: .english)). "
            )
        } ?? ""
        let nextPart = next.map { tier in
            loc.pick(
                "学到 \(Int(tier.hours)) 小时就能拿到\(tier.name)徽章！",
                "Study \(Int(tier.hours)) hours to earn the \(BadgeLadder.displayName(tier.name, for: .english)) badge!"
            )
        } ?? loc.pick("已经是最高的诺贝尔级啦！", "You're already at the top — Nobel Level!")
        return loc.pick(
            "\(subjectLabel)：已经学了 \(Int(hours)) 小时。\(currentPart)\(nextPart)",
            "\(subjectLabel): you've studied \(Int(hours)) hours. \(currentPart)\(nextPart)"
        )
    }

    /// 下一档徽章的进度小字。
    private func nextTierCaption(
        hours: Double,
        next: (hours: Double, name: String, icon: String),
        quizPoints: Int
    ) -> String {
        let nextName = BadgeLadder.displayName(next.name, for: loc.language)
        return loc.pick(
            String(format: "%.1f 小时 / 下一枚「%@」需要 %.0f 小时 · 考试得分 %d", hours, nextName, next.hours, quizPoints),
            String(format: "%.1f hrs / next badge \"%@\" needs %.0f hrs · Quiz score %d", hours, nextName, next.hours, quizPoints)
        )
    }
}
