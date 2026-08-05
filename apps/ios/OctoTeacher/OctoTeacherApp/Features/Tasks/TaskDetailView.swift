import PhotosUI
import SwiftUI

/// 任务详情：孩子看说明、准备证明、提交给大人确认。
struct TaskDetailView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @Environment(FamilyCloudSessionStore.self) private var familyCloud
    @Environment(\.dismiss) private var dismiss
    let assignment: TaskAssignment
    @State private var stableAssignmentID: UUID
    @State private var assignmentSnapshot: TaskAssignment
    @State private var submissionText = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoFileName: String?
    @State private var photoLoadFailed = false
    @State private var offlineHint: String?
    @State private var offlineEnqueueSucceeded: Bool?
    @State private var offlineMutationStatus: MobileOfflineMutationStatus?
    @State private var offlineConflictReason: MobileOfflineConflictReason?
    @State private var audioRecorder = ProofAudioRecorder()
    @State private var isTranscribing = false
    @State private var voiceHint: String?
    @State private var proofAudioFileName: String?
    @State private var showCamera = false
    @State private var showAICompanion = false
    @State private var taskControlHint: String?
    @State private var readingHelpExpanded = false
    @State private var isRefreshingBook = false
    @State private var taskOptionsExpanded = false

    private let composer = MobileOfflineActionComposer()
    private let workbenchBuilder = MobileTodayTaskPackageWorkbenchBuilder()

    init(assignment: TaskAssignment) {
        self.assignment = assignment
        _stableAssignmentID = State(initialValue: assignment.id)
        _assignmentSnapshot = State(initialValue: assignment)
    }

    /// 当前孩子的界面语言：本页所有孩子可见文案与小喇叭 speech 统一从这里取。
    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    var currentAssignment: TaskAssignment {
        store.assignments.first(where: { $0.id == stableAssignmentID }) ?? assignmentSnapshot
    }

    private var workbench: MobileTodayTaskPackageWorkbench {
        workbenchBuilder.build(store: store, offlineStatus: offlineOutbox.publicStatus)
    }

    private var currentCard: MobileTodayTaskCard? {
        guard let step = store.growthPack.steps.first(where: { $0.assignmentId == currentAssignment.id }) else {
            return nil
        }
        return workbench.cards.first { $0.order == step.order }
    }

    private var requiredProof: ProofKind {
        currentAssignment.task.requiredProof
    }

    private var linkedReadingBook: FamilyBook? {
        store.book(for: currentAssignment.task.reading)
    }

    private var linkedReadingBookIsReady: Bool {
        guard let book = linkedReadingBook else { return false }
        return BookFileStore.shared.url(fileName: book.fileName) != nil
    }

    private var requiresSyncedElectronicBook: Bool {
        currentAssignment.task.reading?.importedBookId != nil
    }

    private var canSubmit: Bool {
        guard currentAssignment.status == .open || currentAssignment.status == .rejected else {
            return false
        }
        switch requiredProof {
        case .text:
            return !submissionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || proofAudioFileName != nil
        case .photoPlaceholder, .photo:
            // 旧的 photoPlaceholder 任务对孩子来说就是照片证明：必须拍照或选图。
            return photoFileName != nil
        }
    }

    var body: some View {
        Form {
            if isReadingTask {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(loc.pick("阅读任务", "Reading task"), systemImage: "book.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.blue)
                            Spacer()
                            taskRewardBadge
                        }
                        Text(currentAssignment.task.reading?.bookTitle
                            ?? currentAssignment.task.displayTitle(for: childSurfaceLanguage))
                            .font(.title3.bold())
                            .accessibilityIdentifier("task-detail-title")
                        if let reading = currentAssignment.task.reading,
                           !reading.chapterPlanText.isEmpty {
                            Text(loc.pick("这次读：\(reading.chapterPlanText)", "Read now: \(reading.chapterPlanText)"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let spent = currentAssignment.readingSecondsSpent, spent > 0 {
                            Label(loc.pick("已读 \(spent / 60) 分钟", "Read for \(spent / 60) minutes"), systemImage: "clock.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                        if canEditProof, !requiresSyncedElectronicBook || linkedReadingBookIsReady {
                            NavigationLink {
                                ChildReadingView(assignment: currentAssignment)
                            } label: {
                                Label(
                                    loc.pick(
                                        (currentAssignment.readingSecondsSpent ?? 0) > 0 ? "继续阅读" : "开始阅读",
                                        (currentAssignment.readingSecondsSpent ?? 0) > 0 ? "Continue reading" : "Start reading"
                                    ),
                                    systemImage: "book.pages.fill"
                                )
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("task-detail-start-reading")
                        } else if canEditProof, requiresSyncedElectronicBook {
                            missingElectronicBookCard
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                readingHelpExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Label(loc.pick("任务说明与帮助", "Instructions & help"), systemImage: "info.circle")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: readingHelpExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("task-detail-reading-help")
                        Button {
                            showAICompanion = true
                        } label: {
                            Label(
                                loc.pick("问 AI 章鱼老师", "Ask AI Octo Teacher"),
                                systemImage: "sparkles"
                            )
                            .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("task-detail-ask-ai-companion")
                        if readingHelpExpanded {
                            VStack(alignment: .leading, spacing: 10) {
                                let childInstructions = currentAssignment.task.displayInstructions(for: childSurfaceLanguage)
                                if !childInstructions.isEmpty {
                                    Text(childInstructions)
                                        .font(.subheadline)
                                }
                                if currentAssignment.task.needsAdultSupervision {
                                    Label(
                                        loc.pick("要请大人陪着一起做", "Do this together with a grown-up"),
                                        systemImage: "figure.and.child.holdinghands"
                                    )
                                    .foregroundStyle(.orange)
                                }
                                if let verification = currentAssignment.task.verification {
                                    learningVerificationCard(verification)
                                }
                                if let currentCard {
                                    Label(
                                        currentCard.state.label(for: childSurfaceLanguage),
                                        systemImage: currentCard.state.systemImage
                                    )
                                    .foregroundStyle(tint(for: currentCard.state))
                                }
                                if let reason = currentAssignment.rejectionReason {
                                    Label(
                                        loc.pick("再试一次：\(reason.label)", "Try again: \(reason.label(for: .english))"),
                                        systemImage: "arrow.uturn.backward"
                                    )
                                    .foregroundStyle(.red)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if !isReadingTask {
                Section(loc.pick("任务", "Task")) {
                HStack {
                    Text(currentAssignment.task.displayTitle(for: childSurfaceLanguage))
                        .font(.headline)
                        .accessibilityIdentifier("task-detail-title")
                    Spacer()
                    SpeakButton(text: taskSpeechText)
                }
                let childInstructions = currentAssignment.task.displayInstructions(for: childSurfaceLanguage)
                if !childInstructions.isEmpty {
                    Text(childInstructions)
                }
                taskRewardBadge
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        showAICompanion = true
                    } label: {
                        HStack {
                            Label(loc.pick("问 AI 章鱼老师", "Ask AI Octo Teacher"), systemImage: "sparkles")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("task-detail-ask-ai-companion")

                    Text(loc.pick("卡住时，我只给提示，不直接给答案。", "Stuck? I give hints, not final answers."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("task-detail-ai-companion-hint")
                }
                .padding(.vertical, 2)
                if currentAssignment.task.needsAdultSupervision {
                    Label(loc.pick("要请大人陪着一起做", "Do this together with a grown-up"), systemImage: "figure.and.child.holdinghands")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("task-detail-adult-supervision")
                }
                if let creative = currentAssignment.task.creative {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(creative.kind.label(for: loc.language), systemImage: creative.kind.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.purple)
                        if !creative.creativePrompt.isEmpty {
                            Text(creative.creativePrompt)
                                .font(.caption)
                        }
                        if !creative.materials.isEmpty {
                            Text(loc.pick(
                                "准备：\(creative.materials.joined(separator: "、"))",
                                "Prepare: \(creative.materials.joined(separator: ", "))"
                            ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(loc.pick(
                            "建议用时约 \(creative.estimatedMinutes) 分钟。作品可以拍照，再用语音说说自己的想法。",
                            "About \(creative.estimatedMinutes) minutes suggested. Photograph your work, then talk about your ideas."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("task-detail-creative-spec")
                }
                if let video = currentAssignment.task.video {
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink {
                            ChildVideoPlayerView(video: video)
                        } label: {
                            Label(
                                loc.pick("在这里看视频（\(video.platformLabel)）", "Watch the video here (\(video.platformLabel))"),
                                systemImage: "play.rectangle.fill"
                            )
                        }
                        Text(loc.pick(
                            "视频就在 章鱼老师 里看，不用打开别的 App；至少认真看 \(video.minWatchMinutes) 分钟。",
                            "Watch right inside Octo Teacher — no other apps needed; watch carefully for at least \(video.minWatchMinutes) minutes."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("task-detail-video-spec")
                }
                if let verification = currentAssignment.task.verification {
                    learningVerificationCard(verification)
                }
                if let currentCard {
                    Label(currentCard.state.label(for: childSurfaceLanguage), systemImage: currentCard.state.systemImage)
                        .foregroundStyle(tint(for: currentCard.state))
                    Text(currentCard.nextStep)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let reason = currentAssignment.rejectionReason {
                    Label(
                        loc.pick("再试一次：\(reason.label)", "Try again: \(reason.label(for: .english))"),
                        systemImage: "arrow.uturn.backward"
                    )
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if currentAssignment.status == .approved,
                   let subject = LearningSubject.from(task: currentAssignment.task),
                   aiProvider.isReadyForAIComposer,
                   currentAssignment.task.verification == nil,
                   !store.hasTakenQuiz(for: currentAssignment.id) {
                    NavigationLink {
                        ChildQuizView(assignment: currentAssignment, subject: subject)
                    } label: {
                        HStack {
                            Label(
                                loc.pick("考一考，赢成长积分和徽章！", "Take a quiz to win Growth Points and badges!"),
                                systemImage: "brain.head.profile"
                            )
                                .font(.headline)
                                .foregroundStyle(.purple)
                            Spacer()
                            SpeakButton(text: loc.pick(
                                "学完了来考一考，答对就能赢成长积分和\(subject.label)徽章！",
                                "After learning, take a quiz — answer right to win Growth Points and a \(subject.label) badge!"
                            ))
                        }
                    }
                    .accessibilityIdentifier("task-detail-quiz")
                }
                }
            }

            Section {
                if !canEditProof {
                    submissionReadiness
                } else {
                    proofGuide
                    if shouldShowEditableSubmissionReadiness {
                        submissionReadiness
                    }
                    proofInput

                    HStack(spacing: 10) {
                        Button {
                            submitForApproval()
                        } label: {
                            Label(
                                loc.pick("完成啦", "I'm Done"),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(store.isPreReaderActive ? .title3.bold() : .headline)
                            .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("task-detail-submit-for-approval")

                        SpeakButton(text: loc.pick(
                            "做完了就点完成啦，大人确认后会得到成长积分。",
                            "When you're done, tap I'm Done. You get Growth Points after a grown-up checks it."
                        ))
                    }
                }
                if !canEditProof {
                    proofInput
                }

                if let offlineHint {
                    Label(
                        offlineHint,
                        systemImage: offlineEnqueueSucceeded == false ? "exclamationmark.triangle.fill" : "paperplane"
                    )
                        .font(.caption)
                        .foregroundStyle(offlineEnqueueSucceeded == false ? .orange : .secondary)
                        .accessibilityIdentifier("task-detail-offline-hint")
                }
            } header: {
                Text(loc.pick("完成啦？", "All Done?"))
            }

            taskControlSection
        }
        .navigationTitle(loc.pick("任务详情", "Task Details"))
        .navigationDestination(isPresented: $showAICompanion) {
            ChildAICompanionView(focusedAssignmentID: currentAssignment.id)
        }
        .onAppear {
            submissionText = currentAssignment.proof.text
            photoFileName = currentAssignment.proof.photoFileName
            proofAudioFileName = currentAssignment.proof.audioFileName
            refreshSubmissionOutboxStateIfNeeded()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await loadPhoto(from: newItem)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCaptureView { image in
                savePhoto(image)
            }
            .ignoresSafeArea()
        }
        .onChange(of: audioRecorder.state) { _, newState in
            // 录音一结束就保存（状态监听比 onAppear 可靠）。
            if case .finished(let fileURL) = newState {
                keepRecording(fileURL: fileURL)
            }
        }
    }

    private var isReadingTask: Bool {
        if currentAssignment.task.reading != nil { return true }
        let title = currentAssignment.task.title.lowercased()
        return title.contains("阅读")
            || title.contains("读书")
            || title.contains("read")
            || title.contains("book")
    }

    private var taskRewardBadge: some View {
        Label(
            GrowthCreditCopy.label(points: currentAssignment.task.rewardMinutes, language: loc.language),
            systemImage: "leaf.fill"
        )
        .font(.caption.weight(.bold))
        .foregroundStyle(.green)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.green.opacity(0.12), in: Capsule())
        .accessibilityIdentifier("task-detail-reward-badge")
    }

    private var missingElectronicBookCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                loc.pick("书还在同步", "The book is still syncing"),
                systemImage: "icloud.and.arrow.down"
            )
            .font(.subheadline.weight(.semibold))
            Text(loc.pick(
                "这是一项电子书任务。书文件到达这台手机后，阅读按钮才会出现。",
                "This is an ebook task. The reading button appears after the book file reaches this phone."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            if familyCloud.isChildDevice {
                Button {
                    Task { await refreshMissingBook() }
                } label: {
                    if isRefreshingBook {
                        ProgressView()
                    } else {
                        Label(loc.pick("重新同步", "Sync again"), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingBook)
                .accessibilityIdentifier("task-detail-sync-missing-book")
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("task-detail-book-not-ready")
    }

    private func refreshMissingBook() async {
        guard !isRefreshingBook else { return }
        isRefreshingBook = true
        defer { isRefreshingBook = false }
        try? await familyCloud.refreshChildSurface(into: store)
    }

    @ViewBuilder
    private func learningVerificationCard(_ verification: TaskVerificationSpec) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                loc.pick("学习验收：\(verification.mode.label)", "Learning check: \(verification.mode.label)"),
                systemImage: "checkmark.seal.fill"
            )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
            Text(verificationHelpText(verification))
                .font(.caption)
                .foregroundStyle(.secondary)

            if verification.usesChoiceQuestions,
               canEditProof,
               let subject = LearningSubject.from(task: currentAssignment.task),
               aiProvider.isReadyForAIComposer,
               !store.hasTakenQuiz(for: currentAssignment.id) {
                NavigationLink {
                    ChildQuizView(
                        assignment: currentAssignment,
                        subject: subject,
                        awardsProgressOnFinish: false
                    )
                } label: {
                    Label(
                        loc.pick("先做 \(verification.resolvedQuestionCount) 道小测", "Take the \(verification.resolvedQuestionCount)-question quiz first"),
                        systemImage: "brain.head.profile"
                    )
                        .font(.headline)
                }
                .accessibilityIdentifier("task-detail-verification-quiz")
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("task-detail-learning-verification")
    }

    private var childActionPlanSection: some View {
        Section(loc.pick("三步做完", "Three Steps to Done")) {
            VStack(alignment: .leading, spacing: 10) {
                childActionPlanRow(
                    title: loc.pick("先开始", "Start"),
                    detail: childFirstActionText,
                    systemImage: "1.circle.fill",
                    tint: .blue
                )
                .accessibilityIdentifier("task-detail-child-plan-step-1")

                childActionPlanRow(
                    title: loc.pick("再交证明", "Hand in proof"),
                    detail: proofRequirementShortHint,
                    systemImage: "2.circle.fill",
                    tint: .orange
                )
                .accessibilityIdentifier("task-detail-child-plan-step-2")

                childActionPlanRow(
                    title: loc.pick("等大人确认", "Wait for the check"),
                    detail: childApprovalRewardText,
                    systemImage: "3.circle.fill",
                    tint: .green
                )
                .accessibilityIdentifier("task-detail-child-plan-step-3")
            }
            .padding(.vertical, 2)
            .accessibilityIdentifier("task-detail-child-plan")
        }
    }

    private func childActionPlanRow(title: String, detail: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var taskControlSection: some View {
        if currentAssignment.status == .cancelled {
            Section(loc.pick("任务状态", "Task Status")) {
                Label(
                    loc.pick("这个任务已经撤销，不会再计入今天的待办。", "This task was withdrawn and no longer counts toward today."),
                    systemImage: "xmark.circle.fill"
                )
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("task-detail-cancelled-status")
            }
        } else if currentAssignment.status == .submitted || canEditProof {
            Section {
                DisclosureGroup(isExpanded: $taskOptionsExpanded) {
                    if currentAssignment.status == .submitted {
                        Button {
                            withdrawSubmission()
                        } label: {
                            Label(
                                loc.pick("撤回后重新补证明", "Take it back and redo the proof"),
                                systemImage: "arrow.uturn.backward.circle"
                            )
                        }
                        .accessibilityIdentifier("task-detail-withdraw-submission")

                        Text(loc.pick(
                            "只在大人确认前可以撤回。",
                            "You can take it back only before a grown-up checks it."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Button(role: .destructive) {
                            cancelTask()
                        } label: {
                            Label(
                                loc.pick("今天先不做这项", "Skip this task for today"),
                                systemImage: "xmark.circle"
                            )
                        }
                        .accessibilityIdentifier("task-detail-child-cancel-task")

                        Text(loc.pick(
                            "它会移出今天的计划，不会获得成长积分；需要时让大人重新布置。",
                            "It leaves today's plan and earns no Growth Points; ask a grown-up to assign it again if needed."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } label: {
                    Label(loc.pick("任务选项", "Task options"), systemImage: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("task-detail-options")
            }
        }

        if let taskControlHint {
            Section {
                Label(taskControlHint, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("task-detail-control-hint")
            }
        }
    }

    private var childFirstActionText: String {
        if let reading = currentAssignment.task.reading {
            return loc.pick(
                "点“开始阅读”，按这次范围读《\(reading.bookTitle)》。",
                "Tap Start Reading and read \(reading.bookTitle) for this session."
            )
        }
        if let video = currentAssignment.task.video {
            return loc.pick(
                "点“在这里看视频”，认真看满 \(video.minWatchMinutes) 分钟。",
                "Tap Watch the video here and watch carefully for \(video.minWatchMinutes) minutes."
            )
        }
        if currentAssignment.task.needsAdultSupervision {
            return loc.pick(
                "先请大人陪着，再按任务说明做第一步。",
                "Ask a grown-up to join you first, then follow the task steps."
            )
        }
        return loc.pick(
            "按上面的任务说明，把这件事做完。",
            "Follow the task instructions above and get it done."
        )
    }

    private var childApprovalRewardText: String {
        let reward = currentAssignment.task.rewardMinutes
        if reward > 0 {
            return loc.pick(
                "确认后获得 \(GrowthCreditCopy.label(points: reward))。",
                "After the check you get \(GrowthCreditCopy.label(points: reward, language: .english))."
            )
        }
        return loc.pick(
            "确认后，这一步会记进你的成长记录。",
            "After the check, this step goes into your growth record."
        )
    }

    private var proofRequirementShortHint: String {
        switch requiredProof {
        case .text:
            return loc.pick(
                "写一句，或录一段你完成了什么。",
                "Write one sentence or record what you did."
            )
        case .photoPlaceholder, .photo:
            return loc.pick(
                "拍一张照片，或从相册选一张给大人看。",
                "Take a photo or pick one from your album to show a grown-up."
            )
        }
    }

    /// 证明输入区：按任务要求展示文字输入或照片选择；已提交后转为只读。
    @ViewBuilder
    private var proofInput: some View {
        switch requiredProof {
        case .text:
            if canEditProof {
                TextField(loc.pick("写一句你完成了什么", "Write one sentence about what you did"), text: $submissionText, axis: .vertical)
                    .accessibilityIdentifier("task-detail-proof-text")
                    .lineLimit(2...3)
                voiceProofInput
                optionalPhotoInput
            } else {
                Text(currentAssignment.proof.text)
                    .foregroundStyle(.secondary)
            }
        case .photoPlaceholder, .photo:
            requiredPhotoInput
        }
    }

    /// 必填照片证明：拍照或从相册选图；旧 photoPlaceholder 任务同样按照片证明处理。
    @ViewBuilder
    private var requiredPhotoInput: some View {
        if let photoFileName,
           let image = ProofPhotoStore.shared.loadImage(fileName: photoFileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(loc.pick("已选择的证明照片", "Selected proof photo"))
        }

        // 提交后照片进入只读状态；被驳回或还没提交时才能选/换照片，
        // 避免替换掉家长正在审核的证明文件。
        if canEditProof {
            let hasPhoto = photoFileName != nil
            let photoPickerLabel = hasPhoto
                ? loc.pick("换相册照片", "Change photo")
                : loc.pick("选照片", "Choose photo")
            HStack(spacing: 10) {
                if CameraCaptureView.isCameraAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        ProofCaptureLabel(
                            title: hasPhoto ? loc.pick("重拍", "Retake") : loc.pick("拍照", "Camera"),
                            systemImage: "camera.fill",
                            tint: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("task-detail-camera")
                }
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    ProofCaptureLabel(title: photoPickerLabel, systemImage: "photo.fill", tint: .purple)
                }
                .accessibilityIdentifier("task-detail-pick-photo")
            }
            .accessibilityIdentifier("task-detail-pick-photo")

            if photoLoadFailed {
                Text(loc.pick("照片没有读出来，再选一次试试。", "The photo didn't load — try picking it again."))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            TextField(loc.pick("想补充一句话也可以（选填）", "Add a sentence if you like (optional)"), text: $submissionText, axis: .vertical)
                .lineLimit(2...4)
            voiceProofInput
        }

        // 旧数据兼容：早期占位证明已提交时，用中性文案展示，不出现「占位」字样。
        if !canEditProof && photoFileName == nil && currentAssignment.proof.photoPlaceholderName != nil {
            Label(loc.pick("已提交照片证明记录", "Photo proof record submitted"), systemImage: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 孩子端先解释「要交什么」，再展示输入控件，避免按钮置灰时不知道下一步。
    private var proofGuide: some View {
        HStack(spacing: 10) {
            Label(proofRequirementTitle, systemImage: proofRequirementSystemImage)
                .font(.subheadline.weight(.semibold))
            Spacer()
            SpeakButton(text: proofRequirementHint)
        }
        .accessibilityIdentifier("task-detail-proof-guide")
    }

    @ViewBuilder
    private var submissionReadiness: some View {
        if currentAssignment.status == .approved {
            Label(
                loc.pick("大人已经确认，成长积分已到账。", "A grown-up confirmed it — your Growth Points arrived."),
                systemImage: "checkmark.seal.fill"
            )
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityIdentifier("task-detail-approved-status")
        } else if offlineMutationStatus == .conflict || offlineMutationStatus == .rolledBack {
            submissionOutboxAttention
        } else if offlineEnqueueSucceeded == false {
            submissionSyncWarning
        } else if offlineEnqueueSucceeded == true || currentAssignment.status == .submitted {
            submittedStatusCard
        } else if canEditProof && !canSubmit {
            Label(submitBlockerText, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("task-detail-submit-disabled-reason")
        } else if canSubmit {
            Label(
                loc.pick("证明准备好了，可以交给大人确认。", "Your proof is ready — hand it in for a grown-up to check."),
                systemImage: "checkmark.circle"
            )
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityIdentifier("task-detail-submit-ready")
        }
    }

    private var submittedStatusCard: some View {
        let encouragement = ChildProofSubmissionEncouragement.make(
            task: currentAssignment.task,
            proof: currentAssignment.proof,
            rewardMinutes: currentAssignment.task.rewardMinutes,
            language: loc.language
        )
        return VStack(alignment: .leading, spacing: 6) {
            Label(loc.pick("提交成功，等大人确认", "Handed in — waiting for a grown-up's check"), systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            Text(loc.pick(
                "这一步你已经完成了；大人确认后会获得 \(GrowthCreditCopy.label(points: currentAssignment.task.rewardMinutes))，不用重复提交。",
                "You finished this step; after the check you'll get \(GrowthCreditCopy.label(points: currentAssignment.task.rewardMinutes, language: .english)) — no need to hand it in again."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                let companionFeedback = currentAssignment.aiReview?.childFeedback
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        companionFeedback == nil ? encouragement.title : loc.pick("小伙伴的作品点评", "Your buddy's feedback"),
                        systemImage: "sparkles"
                    )
                        .font(.caption.weight(.semibold))
                    Spacer()
                    SpeakButton(text: companionFeedback ?? encouragement.speakText)
                }
                Text(companionFeedback ?? encouragement.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showAICompanion = true
                } label: {
                    Label(encouragement.nextAction, systemImage: "message.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("task-detail-submitted-ai-encouragement")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(loc.pick(
            "提交成功，等大人确认。这一步你已经完成了；大人确认后会获得 \(GrowthCreditCopy.label(points: currentAssignment.task.rewardMinutes))，不用重复提交。\(encouragement.speakText)",
            "Handed in — waiting for a grown-up's check. You finished this step; after the check you'll get \(GrowthCreditCopy.label(points: currentAssignment.task.rewardMinutes, language: .english)) — no need to hand it in again. \(encouragement.speakText)"
        ))
        .accessibilityIdentifier("task-detail-submitted-status")
    }

    private var submissionOutboxAttention: some View {
        let rolledBack = offlineMutationStatus == .rolledBack
        let detail = TaskSubmissionOutboxAttentionCopy.detail(reason: offlineConflictReason)
        return VStack(alignment: .leading, spacing: 6) {
            Label(
                rolledBack
                    ? loc.pick("同步已回滚，先看大人处理", "Sync was rolled back — let a grown-up handle it first")
                    : loc.pick("同步有冲突，先别重复提交", "Sync hit a conflict — don't hand it in again yet"),
                systemImage: rolledBack ? "arrow.uturn.backward.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(loc.pick(
            "\(rolledBack ? "同步已回滚" : "同步有冲突")。\(detail)",
            "\(rolledBack ? "Sync was rolled back" : "Sync hit a conflict"). \(detail)"
        ))
        .accessibilityIdentifier("task-detail-outbox-attention-status")
    }

    private var submissionSyncWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(loc.pick("本机已保存，等大人确认", "Saved on this device — waiting for the check"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(loc.pick(
                "大人确认后会获得 \(GrowthCreditCopy.label(points: currentAssignment.task.rewardMinutes))，不用重复提交；跨设备同步未排队成功，稍后请重新进入任务查看。",
                "After the check you'll get \(GrowthCreditCopy.label(points: currentAssignment.task.rewardMinutes, language: .english)) — no need to hand it in again. Cross-device sync didn't queue; reopen this task later to check."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(loc.pick(
            "本机已保存，等大人确认。大人确认后会获得 \(GrowthCreditCopy.label(points: currentAssignment.task.rewardMinutes))，不用重复提交；跨设备同步未排队成功，稍后请重新进入任务查看。",
            "Saved on this device — waiting for the check. After the check you'll get \(GrowthCreditCopy.label(points: currentAssignment.task.rewardMinutes, language: .english)); cross-device sync didn't queue, so reopen this task later."
        ))
        .accessibilityIdentifier("task-detail-submitted-status")
    }

    /// 语音证明入口：人人可用，不依赖 AI 配置。
    /// 孩子录音 → 音频保存进证明（家长审核时可回放）；
    /// 家长配置了转写服务时，额外自动把语音变成文字附上。
    @ViewBuilder
    private var voiceProofInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fileName = proofAudioFileName {
                HStack(spacing: 12) {
                    Text("🎤")
                        .font(.title2)
                    Text(loc.pick("已录好语音", "Voice note recorded"))
                        .font(.subheadline.weight(.semibold))
                    Button {
                        if let url = ProofVoiceStore.shared.url(fileName: fileName) {
                            VoicePlayer.shared.play(url: url)
                        }
                    } label: {
                        Label(loc.pick("听一听", "Play it"), systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    Button(loc.pick("重录", "Redo"), role: .destructive) {
                        ProofVoiceStore.shared.delete(fileName: fileName)
                        proofAudioFileName = nil
                        audioRecorder.discard()
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                switch audioRecorder.state {
                case .idle:
                    Button {
                        audioRecorder.startRecording()
                    } label: {
                        ProofCaptureLabel(
                            title: loc.pick("说一说", "Talk"),
                            systemImage: "mic.fill",
                            tint: .orange
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("task-detail-voice-start")
                case .denied:
                    Label(
                        loc.pick("没有麦克风权限，请大人在系统设置里打开。", "No microphone permission — ask a grown-up to enable it in Settings."),
                        systemImage: "mic.slash"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .recording:
                    Button {
                        audioRecorder.stopRecording()
                    } label: {
                        ProofCaptureLabel(
                            title: loc.pick("说完了", "I'm done"),
                            systemImage: "stop.circle.fill",
                            tint: .red
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("task-detail-voice-stop")
                case .finished:
                    Label(loc.pick("保存中……", "Saving…"), systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if isTranscribing {
                Label(loc.pick("AI 正在帮你把话变成文字……", "AI is turning your words into text…"), systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let voiceHint {
                Text(voiceHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 选填照片：任何任务都可以拍照给大人看（家务成果/作品/运动现场/书页/作业本）。
    @ViewBuilder
    private var optionalPhotoInput: some View {
        let photoPickerTitle = loc.pick("选照片", "Photos")
        if let photoFileName,
           let image = ProofPhotoStore.shared.loadImage(fileName: photoFileName) {
            HStack(spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(loc.pick("照片已附上", "Photo attached"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(loc.pick("换一张", "Swap"), role: .destructive) {
                    ProofPhotoStore.shared.delete(fileName: photoFileName)
                    self.photoFileName = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        } else {
            HStack(spacing: 10) {
                if CameraCaptureView.isCameraAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        ProofCaptureLabel(
                            title: loc.pick("拍照", "Camera"),
                            systemImage: "camera.fill",
                            tint: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("task-detail-optional-camera")
                }
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    ProofCaptureLabel(
                        title: photoPickerTitle,
                        systemImage: "photo.fill",
                        tint: .purple
                    )
                }
                .accessibilityIdentifier("task-detail-optional-photo")
            }
            .accessibilityIdentifier("task-detail-optional-photo")
        }
    }

    /// 录音结束：先把音频永久保存进证明（无论是否有 AI），
    /// 再在可用时后台转写补充文字。
    private func keepRecording(fileURL: URL) {
        guard let fileName = ProofVoiceStore.shared.save(fromTemporary: fileURL) else {
            voiceHint = loc.pick("没保存上，再录一次试试。", "It didn't save — try recording again.")
            audioRecorder.discard()
            return
        }
        proofAudioFileName = fileName
        audioRecorder.discard()
        voiceHint = loc.pick("录好啦！大人可以直接听你的话。", "Recorded! A grown-up can listen to your words.")

        // 有转写服务时附加文字（复制一份临时文件去转写，永久音频保留）。
        if aiProvider.isVoiceTranscriptionReady,
           let permanentURL = ProofVoiceStore.shared.url(fileName: fileName) {
            let tmpCopy = FileManager.default.temporaryDirectory
                .appendingPathComponent("transcribe-\(UUID().uuidString).m4a")
            try? FileManager.default.copyItem(at: permanentURL, to: tmpCopy)
            Task {
                isTranscribing = true
                defer { isTranscribing = false }
                if let text = try? await aiProvider.transcribeChildProofAudio(
                    at: tmpCopy,
                    using: OpenAIStyleTranscriptionClient()
                ) {
                    let trimmed = submissionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    submissionText = trimmed.isEmpty ? text : trimmed + "\n" + text
                    voiceHint = loc.pick(
                        "AI 把你的话变成了文字，一起交给大人。",
                        "AI turned your words into text to hand in together."
                    )
                }
            }
        }
    }

    /// 提交后异步请求 AI 初评（学习类任务且 AI 就绪时）；失败静默，家长照常人工审。
    private func requestAIReviewIfPossible() {
        let assignmentId = currentAssignment.id
        let task = currentAssignment.task
        let childText = submissionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard aiProvider.isReadyForAIComposer,
              AIProofReviewer.supportsReview(task),
              !childText.isEmpty else { return }
        Task {
            guard let raw = try? await aiProvider.completeDraftJSON(
                system: AIProofReviewer.systemPrompt(childLanguage: store.activeChildInterfaceLanguage),
                user: AIProofReviewer.userPrompt(
                    task: task,
                    childText: childText,
                    contentExcerpt: learningContentExcerpt(for: task)
                ),
                using: OpenAIStyleChatClient()
            ), let review = AIProofReviewer.parse(raw) else { return }
            store.attachAIReview(review, to: assignmentId)
        }
    }

    private func learningContentExcerpt(for task: TaskTemplate) -> String? {
        if let summary = task.verification?.parentApprovedSummary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        if let summary = task.video?.contentSummary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        guard let reading = task.reading else { return nil }
        if let book = store.book(for: reading),
           let excerpt = BookFileStore.shared.readingExcerpt(book: book, reading: reading) {
            return excerpt
        }
        return reading.inAppContent.map { String($0.prefix(4_000)) }
    }

    private func verificationHelpText(_ verification: TaskVerificationSpec) -> String {
        switch verification.mode {
        case .choiceQuiz:
            return loc.pick(
                "读完或看完后先做小测，AI 会按真实内容出题；结果给大人参考。",
                "After reading or watching, take a short quiz; AI writes questions from the real content, and the result goes to a grown-up."
            )
        case .learningDrill:
            return loc.pick(
                "这是识字、字母或数学类练习，题目会围绕学习内容生成。",
                "This is a reading, letters, or math drill; questions come from the learning content."
            )
        case .voiceRetell:
            let seconds = verification.resolvedMinimumRetellSeconds
            return loc.pick(
                "说一说你刚才学到了什么，建议讲到 \(seconds / 60) 分钟以内；AI 只做初评，大人最后确认。",
                "Talk about what you just learned, ideally within \(seconds / 60) minutes; AI only pre-reviews and a grown-up confirms."
            )
        }
    }

    /// 朗读用的任务全文：标题+要求+奖励，跟随当前孩子界面语言。
    private var taskSpeechText: String {
        var parts = [currentAssignment.task.displayTitle(for: loc.language)]
        let childInstructions = currentAssignment.task.displayInstructions(for: loc.language)
        if !childInstructions.isEmpty {
            parts.append(childInstructions)
        }
        if let reading = currentAssignment.task.reading {
            parts.append(loc.pick(
                "这次读《\(reading.bookTitle)》\(reading.chapterPlanText)",
                "This time read \(reading.bookTitle) \(reading.chapterPlanText)"
            ))
        }
        parts.append(loc.pick(
            "做完可以获得 \(GrowthCreditCopy.label(points: currentAssignment.task.rewardMinutes, language: loc.language))",
            "Finish it to earn \(GrowthCreditCopy.label(points: currentAssignment.task.rewardMinutes, language: loc.language))"
        ))
        return parts.joined(separator: loc.pick("。", ". ")) + loc.pick("。", ".")
    }

    private func withdrawSubmission() {
        if store.withdrawSubmittedAssignment(currentAssignment.id) {
            taskControlHint = loc.pick("已经撤回，可以重新补证明。", "Taken back — you can redo the proof.")
            offlineEnqueueSucceeded = nil
            refreshSubmissionOutboxStateIfNeeded()
            Task {
                await familyCloud.withdrawChildTask(localAssignmentId: currentAssignment.id)
            }
        } else {
            taskControlHint = loc.pick("现在不能撤回，可能大人已经处理过了。", "Can't take it back now — a grown-up may have handled it.")
        }
    }

    private func cancelTask() {
        if store.cancelAssignment(currentAssignment.id, actor: .child) {
            taskControlHint = loc.pick("已经撤销，这项任务不会再计入今天。", "Withdrawn — this task no longer counts toward today.")
            dismiss()
        } else {
            taskControlHint = loc.pick("现在不能撤销，可能大人已经确认过了。", "Can't withdraw now — a grown-up may have confirmed it.")
        }
    }

    /// 是否还允许修改证明内容：已提交/已完成的任务只读。
    private var canEditProof: Bool {
        currentAssignment.status == .open || currentAssignment.status == .rejected
    }

    private var shouldShowEditableSubmissionReadiness: Bool {
        offlineEnqueueSucceeded == nil && canEditProof
    }

    /// 相机拍摄的照片压缩保存到本机；替换时清理旧文件。
    private func savePhoto(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9),
              let fileName = ProofPhotoStore.shared.save(imageData: data) else {
            photoLoadFailed = true
            return
        }
        if let previous = photoFileName, previous != fileName {
            ProofPhotoStore.shared.delete(fileName: previous)
        }
        photoFileName = fileName
        photoLoadFailed = false
    }

    /// 读取所选照片并压缩保存到本机；替换时清理旧文件。
    private func loadPhoto(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let fileName = ProofPhotoStore.shared.save(imageData: data) else {
            photoLoadFailed = true
            return
        }
        if let previous = photoFileName, previous != fileName {
            ProofPhotoStore.shared.delete(fileName: previous)
        }
        photoFileName = fileName
        photoLoadFailed = false
    }

    /// 本地提交：先走任务包本地闭环，再把同一动作脱敏排进离线 outbox。
    /// 离线 outbox 只入队、不落定，联网后仍由家长/老师验证才发奖励。
    private func submitForApproval() {
        let proof = buildProof()
        guard store.submit(currentAssignment, proof: proof) else {
            offlineEnqueueSucceeded = false
            offlineHint = loc.pick(
                "证明还没有准备好，请按上面的方式补充后再提交。",
                "Your proof is not ready yet. Add what is requested above, then hand it in again."
            )
            return
        }
        Task {
            await familyCloud.submitChildTask(
                localAssignmentId: currentAssignment.id,
                evidenceSummary: proof.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : proof.text
            )
        }
        requestAIReviewIfPossible()
        let enqueueResult = offlineOutbox.enqueue(taskSubmissionRequest)
        switch enqueueResult {
        case .success(let mutation):
            offlineEnqueueSucceeded = true
            offlineMutationStatus = mutation.status
            offlineConflictReason = mutation.conflictReason
            offlineHint = MobileOfflineEnqueueFeedback.message(
                for: enqueueResult,
                successText: loc.pick("已提交，等大人确认", "Handed in — waiting for a grown-up's check")
            )
        case .failure(let error):
            offlineEnqueueSucceeded = false
            offlineMutationStatus = nil
            offlineConflictReason = nil
            offlineHint = error.localizedHint
        }
    }

    private var taskSubmissionRequest: MobileOfflineMutationRequest {
        composer.childTaskSubmission(
            taskSeed: currentAssignment.id.uuidString,
            proofKindLabel: proofKindLabel
        )
    }

    private func refreshSubmissionOutboxStateIfNeeded() {
        guard currentAssignment.status == .submitted else { return }
        guard offlineEnqueueSucceeded == nil else { return }

        switch offlineOutbox.existingEnqueueResult(for: taskSubmissionRequest) {
        case .success(let mutation):
            offlineMutationStatus = mutation.status
            offlineConflictReason = mutation.conflictReason
            switch mutation.status {
            case .pending:
                offlineEnqueueSucceeded = true
                offlineHint = nil
            case .conflict, .rolledBack:
                offlineEnqueueSucceeded = false
                offlineHint = nil
            }
        case .failure(let error):
            offlineEnqueueSucceeded = false
            offlineMutationStatus = nil
            offlineConflictReason = nil
            offlineHint = error.localizedHint
        case nil:
            offlineEnqueueSucceeded = false
            offlineMutationStatus = nil
            offlineConflictReason = nil
            offlineHint = loc.pick("这条提交尚未加入离线同步队列", "This submission is not in the offline sync queue yet")
        }
    }

    private var proofKindLabel: String {
        switch requiredProof {
        case .text: return "文字证明"
        case .photoPlaceholder, .photo: return "照片证明"
        }
    }

    private var proofRequirementTitle: String {
        switch requiredProof {
        case .text: return loc.pick("说一说或写一句", "Talk or write")
        case .photoPlaceholder, .photo: return loc.pick("拍一张就好", "Take one photo")
        }
    }

    private var proofRequirementHint: String {
        switch requiredProof {
        case .text:
            return loc.pick(
                "说一句你做了什么，也可以写下来。",
                "Say what you did, or write it down."
            )
        case .photoPlaceholder, .photo:
            return loc.pick(
                "拍一张照片，或者从相册选一张。",
                "Take a photo, or choose one from your album."
            )
        }
    }

    private var submitBlockerText: String {
        switch requiredProof {
        case .text:
            return loc.pick(
                "先说一句或写一句。",
                "Talk or write first."
            )
        case .photoPlaceholder, .photo:
            return loc.pick(
                "先拍一张或选一张照片。",
                "Take or choose a photo first."
            )
        }
    }

    private var proofRequirementSystemImage: String {
        switch requiredProof {
        case .text: return "text.bubble.fill"
        case .photoPlaceholder: return "photo.on.rectangle"
        case .photo: return "camera.fill"
        }
    }

    private func buildProof() -> ProofDraft {
        switch requiredProof {
        case .text:
            return ProofDraft(
                kind: .text,
                text: submissionText,
                photoPlaceholderName: nil,
                photoFileName: photoFileName,
                audioFileName: proofAudioFileName,
                status: .submitted
            )
        case .photoPlaceholder:
            // 新提交必须带真实照片；photoPlaceholderName 仅存在于旧数据，不再生成。
            return ProofDraft(
                kind: .photoPlaceholder,
                text: submissionText,
                photoPlaceholderName: nil,
                photoFileName: photoFileName,
                audioFileName: proofAudioFileName,
                status: .submitted
            )
        case .photo:
            return ProofDraft(
                kind: .photo,
                text: submissionText,
                photoPlaceholderName: nil,
                photoFileName: photoFileName,
                audioFileName: proofAudioFileName,
                status: .submitted
            )
        }
    }

    private func tint(for state: MobileTodayTaskCardState) -> Color {
        switch state {
        case .locked: return .secondary
        case .active: return .blue
        case .waitingCheck: return .orange
        case .done: return .green
        case .redo: return .red
        }
    }
}

private struct ProofCaptureLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
}

enum TaskSubmissionOutboxAttentionCopy {
    static func detail(reason: MobileOfflineConflictReason?) -> String {
        let reasonText: String
        if let reason {
            reasonText = "\(reason.hint)。\(reason.nextStep)"
        } else {
            reasonText = "同步遇到小问题。请让大人稍后检查同步状态"
        }
        return "\(reasonText)。任务证明本机仍保留，大人确认前不会发放成长积分。"
    }
}
