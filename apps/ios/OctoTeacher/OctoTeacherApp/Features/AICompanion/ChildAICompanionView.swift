import PhotosUI
import SwiftUI
import UIKit

enum AICompanionProfileCoachCopy {
    // 中文静态常量保留：既是中文孩子文案，也是既有单元测试的断言目标。
    static let title = "想自己定义小伙伴？"
    static let instruction = "可以直接告诉它名字、样子、声音和说话风格。不会写字也可以点小喇叭听一遍，再按麦克风说。"
    static let exampleCommand = "你以后叫闪闪，声音要更活泼，性格像小教练，你长得像一只黄色小机器人。"
    static let speakText = "\(instruction) 比如说：\(exampleCommand)"

    // 双语入口：英文孩子看英文引导；英文示例口令会按普通聊天发给 AI。
    static func title(for language: AppInterfaceLanguage) -> String {
        language.pick(title, "Want to design your buddy?")
    }

    static func instruction(for language: AppInterfaceLanguage) -> String {
        language.pick(
            instruction,
            "Just tell it a name, a look, a voice, and how to talk. Can't write yet? Tap the speaker to listen, then press the mic and say it."
        )
    }

    static func exampleCommand(for language: AppInterfaceLanguage) -> String {
        language.pick(
            exampleCommand,
            "From now on your name is Sparky, sound more lively, act like a little coach, and look like a small yellow robot."
        )
    }

    static func speakText(for language: AppInterfaceLanguage) -> String {
        language == .english
            ? "\(instruction(for: language)) For example: \(exampleCommand(for: language))"
            : speakText
    }
}

enum AICompanionMediaConsentCopy {
    // 中文静态常量保留给既有单元测试；界面取值走 imagePermissionNeeded(for:)。
    static let imagePermissionNeeded = "家长还没允许图片发给 AI；发送后我会先请你描述图片。"

    static func imagePermissionNeeded(for language: AppInterfaceLanguage) -> String {
        language.pick(
            imagePermissionNeeded,
            "A parent hasn't allowed sending pictures to the AI yet; after you send, I'll ask you to describe the picture first."
        )
    }

    static func setupExplanation(imagesEnabled: Bool, language: AppInterfaceLanguage = .chinese) -> String {
        if imagesEnabled {
            return language.pick(
                "图片和相机会先放进同一条聊天；只有点发送后，才会先做本机安全检查，再通过家长设置的 API 发给云端模型。",
                "Pictures and camera shots go into the same message first; only after you tap send do they pass a safety check on this device, then go to the cloud model through your parent's API."
            )
        }
        return language.pick(
            "图片和相机会先放进同一条聊天；家长未开启图片 AI 时，不会上传图片，我会先请你描述。",
            "Pictures and camera shots go into the same message first; if a parent hasn't turned on picture AI, nothing is uploaded and I'll ask you to describe it."
        )
    }

    static func queued(
        source: AICompanionImageAttachment.Source,
        imagesEnabled: Bool,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        let label = source == .camera
            ? language.pick("照片", "Your photo")
            : language.pick("图片", "Your picture")
        if imagesEnabled {
            return language.pick(
                "\(label)已放到输入栏；点发送后 AI 才能看图。",
                "\(label) is in the message bar; the AI can see it after you tap send."
            )
        }
        return language.pick(
            "\(label)已放到输入栏；家长未开图片 AI 权限时，我会先请你描述\(source == .camera ? "照片" : "图片")。",
            "\(label) is in the message bar; since picture AI isn't turned on yet, I'll ask you to describe it first."
        )
    }
}

enum AICompanionVoiceFallbackCopy {
    // 中文静态常量保留给既有单元测试；界面取值走带语言的方法。
    static let transcriptionFailed = "这次没有把语音变成文字，这段语音没有发送给 AI，我也不会乱猜。你可以再按一次麦克风，或者直接打字、发图片。"
    static let notEnabled = "语音转文字还没开启，这段语音没有发送给 AI。可以请大人在 AI 助手设置里开启，或者先打字、发图片。"

    static func transcriptionFailed(for language: AppInterfaceLanguage) -> String {
        language.pick(
            transcriptionFailed,
            "I couldn't turn that voice note into words, so it was not sent to the AI and I won't guess. You can press the mic again, or type or send a picture."
        )
    }

    static func notEnabled(for language: AppInterfaceLanguage) -> String {
        language.pick(
            notEnabled,
            "Voice-to-text isn't turned on, so that voice note was not sent to the AI. Ask a grown-up to turn it on in the AI settings, or type or send a picture for now."
        )
    }
}

struct ChildAICompanionView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(AICompanionSessionStore.self) private var sessionStore
    @Environment(AICompanionMemoryStore.self) private var memoryStore
    @Environment(AICompanionTranscriptStore.self) private var transcriptStore
    @Environment(GrowthMemoryStore.self) private var growthMemory
    @Environment(ParentAIProviderStore.self) private var aiProvider
    @Environment(MockScreenTimeController.self) private var screenTimeController

    private let focusedAssignmentID: UUID?

    @State private var mode: AICompanionMode = .nextStep
    @State private var messages: [AICompanionMessage] = []
    @State private var chatBubbles: [AICompanionChatBubble] = []
    @State private var draft = ""
    @State private var cloudGuide: AICompanionCloudGuide?
    @State private var cloudGuideFeedback: String?
    @State private var isRequestingCloudGuide = false
    @State private var cloudGuideRequestID = UUID()
    @State private var companionNameDraft = ""
    @State private var companionAvatarDescriptionDraft = ""
    @State private var selectedVoice: AICompanionVoiceStyle = .warm
    @State private var selectedPersonality: AICompanionPersonalityStyle = .gentleGuide
    @State private var companionSetupFeedback: String?
    @State private var audioRecorder = ProofAudioRecorder()
    @State private var isTranscribingVoice = false
    @State private var voiceFeedback: String?
    @State private var shouldReadNextReplyAloud = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showCompanionSetup = false
    @State private var mediaFeedback: String?
    @State private var pendingImages: [PendingCompanionImage] = []
    @State private var recentImageContext: AICompanionRecentImageContext?
    @State private var speakingBubbleID: UUID?
    @State private var speechPlaybackToken = UUID()
    @FocusState private var isComposeFieldFocused: Bool

    private let builder = AICompanionSnapshotBuilder()

    init(focusedAssignmentID: UUID? = nil) {
        self.focusedAssignmentID = focusedAssignmentID
    }

    private var snapshot: AICompanionSnapshot {
        builder.build(
            viewerRole: .child,
            input: AICompanionInput(
                childName: store.child.name,
                mode: mode,
                nextTaskTitle: nextTaskTitle,
                messages: messages
            ),
            language: loc.language
        )
    }

    private var companionName: String { store.child.companionDisplayName(for: loc.language) }

    /// 当前孩子的界面语言上下文：所有孩子可见文案统一从这里取语言。
    private var loc: ChildLocalizationContext { ChildLocalizationContext(language: childSurfaceLanguage) }

    private var nextTaskTitle: String? {
        nextAssignment?.task.displayTitle(for: childSurfaceLanguage)
    }

    private var nextAssignment: TaskAssignment? {
        if let focusedAssignmentID,
           let focused = store.assignments.first(where: {
               $0.id == focusedAssignmentID && $0.childId == store.activeChildId
           }) {
            return focused
        }
        return store.assignments.first {
            $0.childId == store.activeChildId && ($0.status == .open || $0.status == .rejected)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            chatTranscript(snapshot)
            Divider()
            chatComposer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(companionName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                showCompanionSetup = true
            } label: {
                Label(loc.pick("设置小伙伴", "Buddy settings"), systemImage: "person.crop.circle.badge.gearshape")
            }
            .accessibilityIdentifier("ai-companion-open-profile")
        }
        .onAppear {
            syncCompanionDraft()
            restoreTranscript()
        }
        .onChange(of: store.activeChildId) { _, _ in
            syncCompanionDraft()
            resetCloudGuide()
            messages = []
            restoreTranscript()
        }
        .onChange(of: audioRecorder.state) { _, newState in
            if case .finished(let fileURL) = newState {
                handleVoiceFinished(fileURL: fileURL)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            handlePhotoPicked(newItem)
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in
                showCamera = false
                handleCameraCaptured(image)
            }
        }
        .sheet(isPresented: $showCompanionSetup) {
            NavigationStack {
                Form {
                    identitySection
                    assuranceSection(snapshot)
                }
                .navigationTitle(loc.pick("我的小伙伴", "My Buddy"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(loc.pick("完成", "Done")) {
                            showCompanionSetup = false
                        }
                    }
                }
            }
        }
    }

    private func chatTranscript(_ snapshot: AICompanionSnapshot) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    companionStatusPill
                    if shouldShowProfileCoachCard {
                        profileCoachCard
                    }

                    ForEach(Array(chatBubbles.enumerated()), id: \.element.id) { index, bubble in
                        chatBubbleRow(bubble, index: index)
                    }

                    currentTaskChatCard
                    quickReplyChatChips(snapshot)
                    modeChatChips
                    cloudStatusPill

                    if snapshot.status == .needsTrustedAdult {
                        Label(
                            loc.pick(
                                "这类情况要找可信大人一起处理。",
                                "For things like this, find a trusted grown-up to handle it together."
                            ),
                            systemImage: "person.crop.circle.badge.exclamationmark"
                        )
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("ai-companion-chat-trusted-adult")
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("ai-companion-bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .background(Color(.systemGroupedBackground))
            .accessibilityIdentifier("ai-companion-chat-window")
            .onAppear {
                proxy.scrollTo("ai-companion-bottom", anchor: .bottom)
            }
            .onChange(of: chatBubbles.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("ai-companion-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var companionStatusPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
            Text(store.child.companionAvatarDescription(for: loc.language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
        .accessibilityIdentifier("ai-companion-profile-pill")
    }

    private var shouldShowProfileCoachCard: Bool {
        store.child.aiCompanionName == nil
            || store.child.aiCompanionVoice == nil
            || store.child.aiCompanionPersonality == nil
            || store.child.aiCompanionAvatarDescription == nil
    }

    private var profileCoachCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.purple)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(AICompanionProfileCoachCopy.title(for: loc.language))
                        .font(.subheadline.weight(.bold))
                    Text(AICompanionProfileCoachCopy.instruction(for: loc.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(loc.pick("可以说：", "You can say: "))\(AICompanionProfileCoachCopy.exampleCommand(for: loc.language))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                SpeakButton(text: AICompanionProfileCoachCopy.speakText(for: loc.language), language: loc.language)
            }

            Button {
                send(AICompanionProfileCoachCopy.exampleCommand(for: loc.language))
            } label: {
                Label(loc.pick("试一句，帮我改小伙伴", "Try it — update my buddy"), systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.14))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ai-companion-profile-example")
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("ai-companion-profile-coach-card")
    }

    @ViewBuilder
    private var currentTaskChatCard: some View {
        if let assignment = nextAssignment {
            NavigationLink {
                TaskDetailView(assignment: assignment)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(currentTaskEyebrow(for: assignment))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(assignment.status == .rejected ? .red : .orange)
                        Text(assignment.task.displayTitle(for: childSurfaceLanguage))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("ai-companion-current-task-title")
                        Text(currentTaskHint(for: assignment))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("\(currentTaskEyebrow(for: assignment))\(loc.pick("，", ", "))\(assignment.task.displayTitle(for: childSurfaceLanguage))\(loc.pick("。", ". "))\(currentTaskHint(for: assignment))")
                .accessibilityIdentifier("ai-companion-current-task")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ai-companion-open-current-task")
        } else {
            Label(
                childSurfaceLanguage.pick(
                    "今天没有待开始任务。可以先休息，或者请家长布置一个新的成长任务。",
                    "No tasks waiting to start today. Take a rest, or ask a parent to assign a new growth task."
                ),
                systemImage: "checkmark.seal"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("ai-companion-no-current-task")

            if let outlet = suggestedRewardOutletForCompanion {
                companionRewardPathwayCard(outlet)
            }
        }
    }

    private var rewardPathwaySnapshot: RewardPathwaySnapshot {
        RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTimeController,
            viewerRole: .child
        )
    }

    private var suggestedRewardOutletForCompanion: RewardPathwayOutlet? {
        let snapshot = rewardPathwaySnapshot
        return snapshot.outlets.first {
            $0.kind == .screenTime && $0.suggestedRoute == .redeemScreenTime
        } ?? snapshot.outlets.first {
            $0.kind == .wishList && snapshot.publicSummary.redeemableWishCount > 0
        } ?? snapshot.outlets.first {
            // 状态文案已按孩子语言双语生成，这里同时匹配中英文两种「积分不足」提示。
            $0.kind == .pocketMoney
                && !$0.status.contains("积分还不够")
                && !$0.status.contains("Not enough Growth Points")
        }
    }

    @ViewBuilder
    private func companionRewardPathwayCard(_ outlet: RewardPathwayOutlet) -> some View {
        NavigationLink {
            switch outlet.kind {
            case .screenTime:
                RewardRedemptionView()
            case .pocketMoney, .wishList:
                ChildPocketMoneyView()
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: rewardPathwayIcon(for: outlet.kind))
                    .foregroundStyle(.green)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 5) {
                    Text(loc.pick("可以去兑换奖励", "You can redeem a reward"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                    Text(outlet.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(outlet.status) · \(outlet.nextStep)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel("\(loc.pick("可以去兑换奖励，", "You can redeem a reward, "))\(outlet.title)\(loc.pick("，", ", "))\(outlet.status)\(loc.pick("，", ", "))\(outlet.nextStep)")
            .accessibilityIdentifier("ai-companion-reward-pathway-\(outlet.kind.rawValue)")
        }
        .buttonStyle(.plain)
    }

    private func rewardPathwayIcon(for kind: RewardPathwayOutletKind) -> String {
        switch kind {
        case .screenTime: return "gamecontroller.fill"
        case .pocketMoney: return "banknote.fill"
        case .wishList: return "gift.fill"
        }
    }

    @ViewBuilder
    private func quickReplyChatChips(_ snapshot: AICompanionSnapshot) -> some View {
        if !snapshot.quickReplies.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(loc.pick("不知道怎么说时，可以点一句。", "Not sure what to say? Tap a line."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-companion-starter-prompt-help")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(snapshot.quickReplies.enumerated()), id: \.offset) { index, reply in
                            Button {
                                send(reply)
                            } label: {
                                Label(reply, systemImage: "bubble.left")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ai-companion-quick-reply-\(index)")
                        }
                    }
                }
            }
        }
    }

    private var modeChatChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AICompanionMode.allCases, id: \.self) { item in
                    Button {
                        mode = item
                        resetConversationForCurrentMode()
                    } label: {
                        Label(item.label(for: loc.language), systemImage: item.systemImage)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(mode == item ? Color.blue.opacity(0.16) : Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(mode == item ? .blue : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ai-companion-mode-\(item.rawValue)")
                }
            }
        }
    }

    private var cloudStatusPill: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: aiProvider.isReadyForChildAICompanion ? "cloud" : "iphone")
                .foregroundStyle(aiProvider.isReadyForChildAICompanion ? .green : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(aiProvider.isReadyForChildAICompanion
                    ? loc.pick("真实 AI 小伙伴已开启", "Real AI buddy is on")
                    : loc.pick("本机陪伴模式", "On-device buddy mode"))
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier(aiProvider.isReadyForChildAICompanion ? "ai-companion-cloud-mode-ready" : "ai-companion-cloud-mode-local")
                Text(aiProvider.isReadyForChildAICompanion
                    ? (aiProvider.isReadyForChildAICompanionImages
                        ? loc.pick(
                            "文字和图片会先做本机安全检查，再交给家长设置的模型。",
                            "Words and pictures pass a safety check on this device first, then go to the model your parent set up."
                        )
                        : loc.pick(
                            "文字会先做本机安全检查；图片需要家长单独开启。",
                            "Words pass a safety check on this device first; pictures need a parent to turn them on separately."
                        ))
                    : loc.pick(
                        "家长还没开启真实 AI 时，我先用本机安全规则陪你一步一步来。",
                        "Until a parent turns on real AI, I'll use safe on-device rules to go step by step with you."
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let cloudGuideFeedback {
                    Text(cloudGuideFeedback)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("ai-companion-local-feedback")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func chatBubbleRow(_ bubble: AICompanionChatBubble, index: Int) -> some View {
        // 中英文「思考中」占位气泡都由共享策略统一排除，不出现小喇叭。
        let canReadMessage = AICompanionSpeechPolicy.canManuallyRead(
            isCompanionMessage: bubble.role == .companion,
            text: bubble.text,
            isSpeechEnabled: store.isSpeechEnabled
        )
        return HStack(alignment: .bottom, spacing: 8) {
            if bubble.role == .child {
                Spacer(minLength: 36)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !bubble.imagePreviewData.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(Array(bubble.imagePreviewData.enumerated()), id: \.offset) { itemIndex, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .accessibilityIdentifier("ai-companion-message-image-\(index)-\(itemIndex)")
                            }
                        }
                    }
                }

                if !bubble.text.isEmpty {
                    Text(bubble.text)
                        .font(.subheadline)
                        .foregroundStyle(bubble.role == .child ? .white : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bubble.role == .child ? Color.blue : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: 300, alignment: bubble.role == .child ? .trailing : .leading)
            .accessibilityIdentifier("ai-companion-message-\(bubble.role.rawValue)-\(index)")

            if bubble.role == .companion {
                if canReadMessage {
                    companionMessageSpeakButton(bubbleID: bubble.id, text: bubble.text, index: index)
                        .padding(.bottom, 4)
                }
                Spacer(minLength: 36)
            }
        }
    }

    private func companionMessageSpeakButton(bubbleID: UUID, text: String, index: Int) -> some View {
        let isSpeaking = speakingBubbleID == bubbleID
        let controlLabel = AICompanionSpeechPolicy.manualReadControlLabel(isSpeaking: isSpeaking, language: loc.language)
        return Button {
            toggleCompanionMessageSpeech(bubbleID: bubbleID, text: text)
        } label: {
            Label(
                controlLabel,
                systemImage: AICompanionSpeechPolicy.manualReadControlSystemImage(isSpeaking: isSpeaking)
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSpeaking ? .red : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background((isSpeaking ? Color.red : Color.orange).opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(controlLabel)
        .accessibilityIdentifier("ai-companion-speak-message-\(index)")
    }

    private func toggleCompanionMessageSpeech(bubbleID: UUID, text: String) {
        if speakingBubbleID == bubbleID {
            SpeechReader.shared.stop()
            speakingBubbleID = nil
            speechPlaybackToken = UUID()
            return
        }
        let playbackToken = UUID()
        speechPlaybackToken = playbackToken
        speakingBubbleID = bubbleID
        SpeechReader.shared.speak(
            AICompanionSpeechPolicy.utterance(companionName: companionName, text: text, language: loc.language),
            language: loc.language,
            voiceStyle: store.child.companionVoiceStyle,
            prefersLocalLowLatency: false
        )
        monitorCompanionSpeechPlayback(bubbleID: bubbleID, playbackToken: playbackToken)
    }

    private func monitorCompanionSpeechPlayback(bubbleID: UUID, playbackToken: UUID) {
        Task { @MainActor in
            var hasStarted = SpeechReader.shared.isSpeaking
            let startedWaitingAt = Date()
            while speakingBubbleID == bubbleID && speechPlaybackToken == playbackToken {
                if SpeechReader.shared.isSpeaking {
                    hasStarted = true
                } else if hasStarted || Date().timeIntervalSince(startedWaitingAt) > 8 {
                    speakingBubbleID = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private var chatComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingImages) { image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image.preview)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 74, height: 74)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .accessibilityIdentifier("ai-companion-pending-image")
                                Button {
                                    pendingImages.removeAll { $0.id == image.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .accessibilityLabel(loc.pick("移除这张图片", "Remove this picture"))
                                .accessibilityIdentifier("ai-companion-remove-pending-image")
                            }
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                voiceComposerButton

                TextField(loc.pick("和\(companionName)说句话", "Say something to \(companionName)"), text: $draft)
                    .focused($isComposeFieldFocused)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    .onSubmit {
                        submitDraft()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("ai-companion-free-text")

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(loc.pick("从相册选一张图", "Pick a picture from your album"))
                .accessibilityIdentifier("ai-companion-photo-input")

                if CameraCaptureView.isCameraAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Image(systemName: "camera")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(loc.pick("拍一张照片", "Take a photo"))
                    .accessibilityIdentifier("ai-companion-camera-input")
                }

                Button {
                    submitDraft()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(canSubmitChat ? Color.blue : Color.gray.opacity(0.25))
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .disabled(!canSubmitChat)
                .accessibilityLabel(loc.pick("发送", "Send"))
                .accessibilityIdentifier("ai-companion-send-free-text")
            }

            composerStatusLine
        }
    }

    private var canSubmitChat: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty
    }

    @ViewBuilder
    private var voiceComposerButton: some View {
        switch audioRecorder.state {
        case .idle:
            Button {
                audioRecorder.startRecording()
            } label: {
                Image(systemName: "mic.circle.fill")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(loc.pick("按麦克风说话", "Press the mic to talk"))
            .accessibilityIdentifier("ai-companion-voice-start")
        case .denied:
            Image(systemName: "mic.slash")
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .accessibilityLabel(loc.pick(
                    "没有麦克风权限，请大人在系统设置里打开。",
                    "No microphone permission. Ask a grown-up to turn it on in system settings."
                ))
                .accessibilityIdentifier("ai-companion-voice-denied")
        case .recording:
            Button {
                audioRecorder.stopRecording()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(loc.pick("说完了，停止录音", "Done talking — stop recording"))
            .accessibilityIdentifier("ai-companion-voice-stop")
        case .finished:
            ProgressView()
                .frame(width: 34, height: 34)
                .accessibilityLabel(loc.pick("正在整理你刚刚说的话", "Sorting out what you just said"))
                .accessibilityIdentifier("ai-companion-voice-finishing")
        }
    }

    @ViewBuilder
    private var composerStatusLine: some View {
        if isTranscribingVoice {
            Label(loc.pick("正在把语音变成文字……", "Turning your voice into words…"), systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ai-companion-voice-transcribing")
        } else if let voiceFeedback {
            Text(voiceFeedback)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ai-companion-voice-feedback")
        } else if let mediaFeedback {
            Label(mediaFeedback, systemImage: "photo.on.rectangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ai-companion-media-feedback")
        } else if !pendingImages.isEmpty && !aiProvider.isReadyForChildAICompanionImages {
            Label(AICompanionMediaConsentCopy.imagePermissionNeeded(for: loc.language), systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ai-companion-image-consent-needed")
        }
    }

    private var identitySection: some View {
        Section(loc.pick("我的小伙伴", "My Buddy")) {
            TextField(loc.pick("给小伙伴起名字", "Give your buddy a name"), text: $companionNameDraft)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("ai-companion-name-field")

            TextField(
                loc.pick("描述它的样子，比如蓝色星星小龙", "Describe its look, like a blue star dragon"),
                text: $companionAvatarDescriptionDraft,
                axis: .vertical
            )
                .lineLimit(1...3)
                .accessibilityIdentifier("ai-companion-avatar-field")

            Picker(loc.pick("声音", "Voice"), selection: $selectedVoice) {
                ForEach(AICompanionVoiceStyle.allCases, id: \.self) { voice in
                    Text(voice.label(for: loc.language)).tag(voice)
                }
            }
            .accessibilityIdentifier("ai-companion-voice-picker")

            Picker(loc.pick("风格", "Style"), selection: $selectedPersonality) {
                ForEach(AICompanionPersonalityStyle.allCases, id: \.self) { personality in
                    Text(personality.label(for: loc.language)).tag(personality)
                }
            }
            .accessibilityIdentifier("ai-companion-personality-picker")

            Text(selectedPersonality.childHint(for: loc.language))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(loc.pick("保存小伙伴", "Save my buddy")) {
                    saveCompanionProfile()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("ai-companion-save-profile")

                Button {
                    SpeechReader.shared.speak(
                        "\(companionName)\(loc.pick("：", ": "))\(selectedVoice.sampleText(for: loc.language))",
                        language: loc.language,
                        voiceStyle: selectedVoice,
                        prefersLocalLowLatency: false
                    )
                } label: {
                    Label(loc.pick("试听", "Preview"), systemImage: "speaker.wave.2.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("ai-companion-voice-preview")
            }

            if let companionSetupFeedback {
                Label(companionSetupFeedback, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-companion-profile-feedback")
            }
        }
    }

    private var interactionSection: some View {
        let photoPickerLabel = loc.pick("从相册选一张图", "Pick a picture from your album")
        return Section(loc.pick("怎么和\(companionName)说", "How to talk to \(companionName)")) {
            voiceInput

            if CameraCaptureView.isCameraAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label(loc.pick("拍照给\(companionName)看", "Take a photo for \(companionName)"), systemImage: "camera.fill")
                }
                .accessibilityIdentifier("ai-companion-camera-input")
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(photoPickerLabel, systemImage: "photo.fill")
            }
            .accessibilityIdentifier("ai-companion-photo-input")

            Text(AICompanionMediaConsentCopy.setupExplanation(
                imagesEnabled: aiProvider.isReadyForChildAICompanionImages,
                language: loc.language
            ))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let mediaFeedback {
                Label(mediaFeedback, systemImage: "photo.on.rectangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-companion-media-feedback")
            }
        }
    }

    @ViewBuilder
    private var voiceInput: some View {
        switch audioRecorder.state {
        case .idle:
            Button {
                audioRecorder.startRecording()
            } label: {
                Label(loc.pick("按这里和\(companionName)说话", "Tap here to talk to \(companionName)"), systemImage: "mic.circle.fill")
            }
            .accessibilityIdentifier("ai-companion-voice-start")
        case .denied:
            Label(
                loc.pick(
                    "没有麦克风权限，请大人在系统设置里打开。",
                    "No microphone permission. Ask a grown-up to turn it on in system settings."
                ),
                systemImage: "mic.slash"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        case .recording:
            Button {
                audioRecorder.stopRecording()
            } label: {
                Label(loc.pick("正在听……说完点这里", "Listening… tap here when you're done"), systemImage: "stop.circle.fill")
                    .foregroundStyle(.red)
            }
            .accessibilityIdentifier("ai-companion-voice-stop")
        case .finished:
            Label(loc.pick("正在整理你刚刚说的话……", "Sorting out what you just said…"), systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if isTranscribingVoice {
            Label(loc.pick("正在把语音变成文字……", "Turning your voice into words…"), systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ai-companion-voice-transcribing")
        }
        if let voiceFeedback {
            Text(voiceFeedback)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("ai-companion-voice-feedback")
        }
    }

    private var currentTaskSection: some View {
        Section(loc.pick("现在可以先做", "You can start with this")) {
            if let assignment = nextAssignment {
                NavigationLink {
                    TaskDetailView(assignment: assignment)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(currentTaskEyebrow(for: assignment))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(assignment.status == .rejected ? .red : .orange)
                            Text(assignment.task.displayTitle(for: childSurfaceLanguage))
                                .font(.headline)
                                .accessibilityIdentifier("ai-companion-current-task-title")
                            Text(currentTaskHint(for: assignment))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 4)
                    .accessibilityLabel("\(currentTaskEyebrow(for: assignment))\(loc.pick("，", ", "))\(assignment.task.displayTitle(for: childSurfaceLanguage))\(loc.pick("。", ". "))\(currentTaskHint(for: assignment))")
                    .accessibilityIdentifier("ai-companion-current-task")
                }
                .accessibilityIdentifier("ai-companion-open-current-task")
            } else {
                Label(
                childSurfaceLanguage.pick(
                    "今天没有待开始任务。可以先休息，或者请家长布置一个新的成长任务。",
                    "No tasks waiting to start today. Take a rest, or ask a parent to assign a new growth task."
                ),
                systemImage: "checkmark.seal"
            )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-companion-no-current-task")
            }
        }
    }

    private func currentTaskEyebrow(for assignment: TaskAssignment) -> String {
        let english = childSurfaceLanguage == .english
        if assignment.status == .submitted {
            return english ? "Waiting for a grown-up to check" : "这件事正在等大人确认"
        }
        if assignment.status == .approved {
            return english ? "This task is done" : "这件事已经完成"
        }
        if focusedAssignmentID == assignment.id {
            return english ? "Breaking this task into steps" : "正在帮你拆这件事"
        }
        if assignment.status == .rejected {
            return english ? "Try this task again" : "这件事要再试一次"
        }
        return english ? "Start with this task" : "先从这件事开始"
    }

    private func currentTaskHint(for assignment: TaskAssignment) -> String {
        let english = childSurfaceLanguage == .english
        if assignment.status == .submitted {
            return english
                ? "A grown-up is checking it. You can open it to review what you did."
                : "已经交给大人确认了，也可以点进去回顾自己做了什么。"
        }
        if assignment.status == .approved {
            return english
                ? "It is complete. Open it to review what worked and what to try next time."
                : "已经完成了，可以点进去复盘经验，想想下次怎么做得更好。"
        }
        if assignment.status == .rejected, let reason = assignment.rejectionReason {
            return english
                ? "It needs another try. Open it to see what to improve."
                : "上次因为“\(reason.label)”需要重做，点进去看看怎么补。"
        }
        if assignment.task.video != nil {
            return english ? "Open the video, finish it, then submit your proof." : "点进去直接看视频，完成后再提交证明。"
        }
        if assignment.task.reading != nil {
            return english ? "Open the book to read. 章鱼老师 will track your reading time." : "点进去开始阅读，章鱼老师 会帮你记录阅读时间。"
        }
        if assignment.task.needsAdultSupervision {
            return english ? "A grown-up needs to help with this task. Ask before you start." : "这件事需要大人在旁边，点进去前先喊一下家长。"
        }
        return english ? "Open the steps, finish the task, then send it for a parent to check." : "点进去看清步骤，做完后提交给家长确认。"
    }

    private var modeSection: some View {
        Section {
            ForEach(AICompanionMode.allCases, id: \.self) { item in
                Button {
                    mode = item
                    resetConversationForCurrentMode()
                } label: {
                    HStack {
                        Label(item.label, systemImage: item.systemImage)
                        Spacer()
                        if mode == item {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .accessibilityIdentifier("ai-companion-mode-\(item.rawValue)")
            }
        }
    }

    private var cloudGuideSection: some View {
        Section(loc.pick("真实 AI 状态", "Real AI status")) {
            if aiProvider.isReadyForChildAICompanion {
                Label(loc.pick("家长已开启真实 AI 小伙伴", "A parent turned on the real AI buddy"), systemImage: "cloud")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("ai-companion-cloud-mode-ready")
                Text(aiProvider.isReadyForChildAICompanionImages
                    ? loc.pick(
                        "文字和图片都会先做本机安全检查，再通过家长设置的 API 发送给云端模型。",
                        "Words and pictures pass a safety check on this device first, then go to the cloud model through your parent's API."
                    )
                    : loc.pick(
                        "文字会先做本机安全检查，再通过家长设置的 API 发送给云端模型；图片需要家长单独开启。",
                        "Words pass a safety check on this device first, then go to the cloud model through your parent's API; pictures need a parent to turn them on separately."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(loc.pick("本机陪伴模式", "On-device buddy mode"), systemImage: "iphone")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-companion-cloud-mode-local")
                Text(loc.pick(
                    "家长还没有开启真实 AI 小伙伴时，我会用本机安全规则陪你一步一步来。",
                    "Until a parent turns on the real AI buddy, I'll use safe on-device rules to go step by step with you."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isRequestingCloudGuide {
                ProgressView(loc.pick("\(companionName)正在认真想……", "\(companionName) is thinking hard…"))
                    .accessibilityIdentifier("ai-companion-cloud-loading")
            }

            if let cloudGuide {
                VStack(alignment: .leading, spacing: 8) {
                    Label(loc.pick("给你的小提示", "A little tip for you"), systemImage: "sparkles")
                        .font(.subheadline.bold())
                    Text(cloudGuide.reply)
                        .font(.subheadline)
                    ForEach(Array(cloudGuide.nextQuestions.enumerated()), id: \.offset) { index, question in
                        Text("\(loc.pick("想一想：", "Think about: "))\(question)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("ai-companion-cloud-question-\(index)")
                    }
                }
                .accessibilityIdentifier("ai-companion-cloud-guide")
            }

            if let cloudGuideFeedback {
                Label(cloudGuideFeedback, systemImage: "shield.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-companion-local-feedback")
            }

        }
    }

    private func headlineSection(_ snapshot: AICompanionSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.headline)
                    .font(.title3.bold())
                Text(snapshot.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let label = snapshot.currentIntentLabel {
                    Text("\(loc.pick("我听到的是：", "What I heard: "))\(label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func stepsSection(_ snapshot: AICompanionSnapshot) -> some View {
        if !snapshot.childSteps.isEmpty {
            Section(loc.pick("现在只做这几步", "Just these steps for now")) {
                ForEach(snapshot.childSteps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: step.systemImage)
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(step.order). \(step.title)")
                                .font(.subheadline.bold())
                            Text(step.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func quickReplySection(_ snapshot: AICompanionSnapshot) -> some View {
        if !snapshot.quickReplies.isEmpty {
            Section(loc.pick("先点一句开始", "Tap a line to start")) {
                Text(loc.pick(
                    "不知道怎么说时，可以直接点下面一句，我会帮你拆成下一小步。",
                    "Not sure what to say? Tap a line below and I'll break it into a small next step."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-companion-starter-prompt-help")
                ForEach(Array(snapshot.quickReplies.enumerated()), id: \.offset) { index, reply in
                    Button {
                        send(reply)
                    } label: {
                        Label(reply, systemImage: "bubble.left")
                    }
                    .accessibilityIdentifier("ai-companion-quick-reply-\(index)")
                }
            }
        }
    }

    private func submitDraft() {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        let readReplyAloud = shouldReadNextReplyAloud
        guard !text.isEmpty || !images.isEmpty else { return }
        if text.isEmpty {
            // 只发图片时的默认请求文案：跟随孩子语言，同时也是发给 AI 的指令。
            text = loc.pick(
                "请看看这张图片，告诉我你看到了什么，然后陪我想下一步。",
                "Please look at this picture, tell me what you see, then help me think about the next step."
            )
        }
        isComposeFieldFocused = false
        pendingImages = []
        shouldReadNextReplyAloud = false
        send(text, images: images, readReplyAloud: readReplyAloud)
        draft = ""
    }

    private func assuranceSection(_ snapshot: AICompanionSnapshot) -> some View {
        Section {
            Label(snapshot.assurance, systemImage: "shield.checkered")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func syncCompanionDraft() {
        companionNameDraft = store.child.companionDisplayName(for: loc.language)
        companionAvatarDescriptionDraft = store.child.companionAvatarDescription(for: loc.language)
        selectedVoice = store.child.companionVoiceStyle
        selectedPersonality = store.child.companionPersonalityStyle
        companionSetupFeedback = nil
        voiceFeedback = nil
        shouldReadNextReplyAloud = false
        mediaFeedback = nil
        recentImageContext = nil
    }

    /// 从本机 transcript 恢复当前孩子的聊天窗口；切换孩子时换档加载，不再直接失忆。
    private func restoreTranscript() {
        let entries = transcriptStore.recentEntries(for: store.activeChildId)
        chatBubbles = entries.map { entry in
            AICompanionChatBubble(
                id: entry.id,
                role: entry.role == .child ? .child : .companion,
                text: entry.text,
                imagePreviewData: entry.imageThumbnailData
            )
        }
        messages = entries
            .filter { $0.role == .child }
            .suffix(12)
            .map { AICompanionMessage(freeText: $0.text) }
        ensureGreetingBubble()
    }

    private func ensureGreetingBubble() {
        guard chatBubbles.isEmpty else { return }
        let greeting = AICompanionChatReply.greeting(companionName: companionName, mode: mode, language: loc.language)
        // 问候语是即时生成的引导，不写入 transcript，避免每次打开都堆积。
        chatBubbles.append(.companion("\(greeting.text)\n\(loc.pick("我的样子：", "How I look: "))\(store.child.companionAvatarDescription(for: loc.language))"))
    }

    private func resetConversationForCurrentMode() {
        messages = []
        draft = ""
        resetCloudGuide()
        // 保留历史聊天记录，只追加一条新模式的引导语（不落盘）。
        let greeting = AICompanionChatReply.greeting(companionName: companionName, mode: mode, language: loc.language)
        chatBubbles.append(.companion(greeting.text))
    }

    /// 孩子气泡：进聊天窗口的同时写入本机 transcript。
    private func appendChildBubble(
        _ text: String,
        images: [PendingCompanionImage] = [],
        origin: AICompanionTranscriptEntry.Origin = .childText
    ) {
        let thumbnails = images.map(\.thumbnailData)
        let bubble = AICompanionChatBubble.child(text, imagePreviewData: thumbnails.isEmpty ? images.map(\.data) : thumbnails)
        chatBubbles.append(bubble)
        transcriptStore.append(
            AICompanionTranscriptEntry(
                id: bubble.id,
                role: .child,
                text: text,
                imageThumbnailData: thumbnails,
                origin: origin
            ),
            childId: store.activeChildId
        )
    }

    /// 小伙伴气泡：进聊天窗口的同时写入本机 transcript。
    @discardableResult
    private func appendCompanionBubble(
        _ text: String,
        origin: AICompanionTranscriptEntry.Origin,
        fallbackReason: String? = nil
    ) -> AICompanionChatBubble {
        let bubble = AICompanionChatBubble.companion(text)
        chatBubbles.append(bubble)
        transcriptStore.append(
            AICompanionTranscriptEntry(
                id: bubble.id,
                role: .companion,
                text: text,
                origin: origin,
                fallbackReason: fallbackReason
            ),
            childId: store.activeChildId
        )
        return bubble
    }

    private func readReplyIfRequested(bubble: AICompanionChatBubble, requested: Bool) {
        guard AICompanionSpeechPolicy.shouldAutoReadReply(
            inputWasVoice: requested,
            isSpeechEnabled: store.isSpeechEnabled
        ) else { return }
        toggleCompanionMessageSpeech(bubbleID: bubble.id, text: bubble.text)
    }

    private func handleVoiceFinished(fileURL: URL) {
        if aiProvider.isVoiceTranscriptionReady {
            Task {
                isTranscribingVoice = true
                // discard() 负责删除临时录音并把录音按钮状态回到 idle，
                // 无论转写成功或失败，孩子都可以继续打字、发图片。
                defer {
                    isTranscribingVoice = false
                    audioRecorder.discard()
                }
                if let text = try? await aiProvider.transcribeChildProofAudio(
                    at: fileURL,
                    using: OpenAIStyleTranscriptionClient()
                ), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // 转写结果只并入草稿，不直接发送；
                    // 这样有待发送图片时，语音和图片会合并成同一条消息。
                    draft = AICompanionVoiceComposer.mergedDraft(existingDraft: draft, transcript: text)
                    shouldReadNextReplyAloud = true
                    voiceFeedback = AICompanionVoiceComposer.successFeedback(
                        companionName: companionName,
                        hasPendingImages: !pendingImages.isEmpty,
                        language: loc.language
                    )
                } else {
                    shouldReadNextReplyAloud = false
                    voiceFeedback = AICompanionVoiceFallbackCopy.transcriptionFailed(for: loc.language)
                }
            }
        } else {
            try? FileManager.default.removeItem(at: fileURL)
            audioRecorder.discard()
            shouldReadNextReplyAloud = false
            voiceFeedback = AICompanionVoiceFallbackCopy.notEnabled(for: loc.language)
        }
    }

    private func handlePhotoPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        selectedPhotoItem = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let pending = PendingCompanionImage.prepared(from: image, source: .photoLibrary, language: loc.language) else {
                await MainActor.run {
                    mediaFeedback = loc.pick(
                        "这张图片暂时读不出来，可以再选一次。",
                        "I couldn't read that picture — try picking it again."
                    )
                }
                return
            }
            await MainActor.run {
                pendingImages.append(pending)
                mediaFeedback = AICompanionMediaConsentCopy.queued(
                    source: .photoLibrary,
                    imagesEnabled: aiProvider.isReadyForChildAICompanionImages,
                    language: loc.language
                )
            }
        }
    }

    private func handleCameraCaptured(_ image: UIImage) {
        guard let pending = PendingCompanionImage.prepared(from: image, source: .camera, language: loc.language) else {
            mediaFeedback = loc.pick(
                "这张照片暂时处理不了，可以再拍一次。",
                "I couldn't handle that photo — try taking it again."
            )
            return
        }
        pendingImages.append(pending)
        mediaFeedback = AICompanionMediaConsentCopy.queued(
            source: .camera,
            imagesEnabled: aiProvider.isReadyForChildAICompanionImages,
            language: loc.language
        )
    }

    private func send(
        _ text: String,
        images: [PendingCompanionImage] = [],
        readReplyAloud: Bool = false
    ) {
        let message = AICompanionMessage(freeText: text)
        // 在追加本条消息前取最近上下文快照，避免云端请求里重复带上当前消息。
        let recentContextLines = transcriptStore.recentCloudContextLines(for: store.activeChildId)
        let childDisplayText = message.containsUnsafeInput
            ? loc.pick("我刚才说了一句需要保护隐私的话。", "I just said something that needs privacy protection.")
            : text
        appendChildBubble(childDisplayText, images: images)
        messages.append(message)

        if applyProfileCommandIfNeeded(text) {
            let reply = loc.pick(
                "\(companionName)记住啦。现在我的名字、样子和声音都可以按你的想法慢慢变。你还可以继续告诉我：你希望我说话更活泼、安静，还是更像小教练？",
                "\(companionName) will remember that! My name, look, and voice can keep changing the way you like. You can also tell me: should I sound more lively, quieter, or more like a little coach?"
            )
            let bubble = appendCompanionBubble(reply, origin: .companionLocal)
            readReplyIfRequested(bubble: bubble, requested: readReplyAloud)
            rememberLocally(message: message, text: text, extraSummary: "孩子用聊天更新了小伙伴人格/形象")
            return
        }

        let childSnapshot = builder.build(
            viewerRole: .child,
            input: AICompanionInput(
                childName: store.child.name,
                mode: mode,
                nextTaskTitle: nextTaskTitle,
                messages: messages
            ),
            language: loc.language
        )
        let guardianSnapshot = builder.build(
            viewerRole: .guardian,
            input: AICompanionInput(
                childName: store.child.name,
                mode: mode,
                nextTaskTitle: nextTaskTitle,
                messages: messages
            )
        )
        sessionStore.append(
            childId: store.activeChildId,
            mode: mode,
            latestMessage: message,
            guardianSnapshot: guardianSnapshot
        )
        requestCompanionChatIfAllowed(
            text: text,
            latestMessage: message,
            childSnapshot: childSnapshot,
            images: images,
            recentContextLines: recentContextLines,
            readReplyAloud: readReplyAloud
        )
    }

    private func requestCompanionChatIfAllowed(
        text: String,
        latestMessage: AICompanionMessage,
        childSnapshot: AICompanionSnapshot,
        images: [PendingCompanionImage],
        recentContextLines: [String],
        readReplyAloud: Bool = false
    ) {
        let requestID = UUID()
        cloudGuideRequestID = requestID
        cloudGuide = nil
        cloudGuideFeedback = nil
        isRequestingCloudGuide = false

        let localReply = AICompanionChatReply.make(
            companionName: companionName,
            snapshot: childSnapshot,
            latestIntent: latestMessage.intent,
            mode: mode,
            latestText: text,
            language: loc.language
        )
        let shouldUseRecentImage = images.isEmpty
            && aiProvider.isReadyForChildAICompanionImages
            && (recentImageContext?.isActive == true)
            && AICompanionRecentImageContext.referencesRecentImage(text)
        let requestImageAttachments = shouldUseRecentImage
            ? (recentImageContext?.attachments ?? [])
            : images.map(\.attachment)
        let requestAttachmentSummaries: [String]
        if shouldUseRecentImage, let recentImageContext {
            requestAttachmentSummaries = [recentImageContext.followUpSummary]
        } else {
            requestAttachmentSummaries = images.map(\.localSummary)
        }
        let requestContainsImages = !requestImageAttachments.isEmpty
        if images.isEmpty && !shouldUseRecentImage {
            recentImageContext?.consumeTurn()
        }
        if !images.isEmpty && !aiProvider.isReadyForChildAICompanionImages {
            let imageReply = AICompanionImageFallbackReply.make(
                companionName: companionName,
                latestText: text,
                latestIntent: latestMessage.intent,
                reason: .notAuthorized,
                language: loc.language
            )
            let bubble = appendCompanionBubble(imageReply.text, origin: .companionFallback, fallbackReason: "image_not_authorized")
            readReplyIfRequested(bubble: bubble, requested: readReplyAloud)
            cloudGuideFeedback = loc.pick(
                "图片没有上传；需要家长在 AI 助手设置里单独开启图片权限。",
                "The picture was not uploaded; a parent needs to turn on picture permission in the AI settings."
            )
            rememberLocally(message: latestMessage, text: text, extraSummary: "孩子尝试用图片聊天，但图片上传权限未开启")
            return
        }
        guard aiProvider.isReadyForChildAICompanion else {
            let bubble = appendCompanionBubble(localReply.text, origin: .companionLocal)
            readReplyIfRequested(bubble: bubble, requested: readReplyAloud)
            cloudGuideFeedback = loc.pick(
                "家长还没有开启真实 AI 小伙伴；我先用本机安全规则陪你，不会保存原始聊天全文。",
                "A parent hasn't turned on the real AI buddy yet; I'll stay with you using safe on-device rules, and I won't save the full chat."
            )
            rememberLocally(message: latestMessage, text: text)
            return
        }

        isRequestingCloudGuide = true
        let currentCompanionName = companionName
        // 「正在认真想 / is thinking hard」占位由 AICompanionSpeechPolicy.canManuallyRead 统一排除朗读。
        let thinkingBubble = AICompanionChatBubble.companion(
            loc.pick("\(currentCompanionName)正在认真想……", "\(currentCompanionName) is thinking hard…")
        )
        chatBubbles.append(thinkingBubble)
        let request = AICompanionChatRequest(
            childAge: store.child.age,
            responseLanguage: loc.language,
            mode: mode,
            latestText: text,
            latestIntent: latestMessage.intent,
            companionName: currentCompanionName,
            companionVoice: store.child.companionVoiceStyle,
            companionPersonality: store.child.companionPersonalityStyle,
            avatarDescription: store.child.companionAvatarDescription(for: loc.language),
            memory: activeMemoryDigest(),
            growthProfileSummary: [
                growthMemory.digest(for: store.activeChildId).promptSummary,
                store.schoolDynamicsPromptSummary(for: store.activeChildId)
            ].filter { !$0.isEmpty }.joined(separator: "\n"),
            recentContextLines: recentContextLines,
            nextTaskTitle: nextTaskTitle,
            attachmentSummaries: requestAttachmentSummaries,
            imageAttachments: requestImageAttachments
        )
        if !images.isEmpty, aiProvider.isReadyForChildAICompanionImages {
            recentImageContext = AICompanionRecentImageContext(
                attachments: images.map(\.attachment),
                visualSummary: images.map(\.localSummary).joined(separator: " ")
            )
        }
        let localMemoryUpdate = AICompanionMemoryUpdate.local(intent: latestMessage.intent, childText: text)
        Task {
            do {
                let turn = try await aiProvider.chatChildAICompanion(request: request)
                await MainActor.run {
                    guard cloudGuideRequestID == requestID else { return }
                    replaceBubble(id: thinkingBubble.id, text: turn.reply)
                    readReplyIfRequested(
                        bubble: AICompanionChatBubble(id: thinkingBubble.id, role: .companion, text: turn.reply, imagePreviewData: []),
                        requested: readReplyAloud
                    )
                    transcriptStore.append(
                        AICompanionTranscriptEntry(
                            id: thinkingBubble.id,
                            role: .companion,
                            text: turn.reply,
                            origin: .companionCloud
                        ),
                        childId: store.activeChildId
                    )
                    remember(update: turn.memoryUpdate, fallback: localMemoryUpdate)
                    if requestContainsImages {
                        if shouldUseRecentImage {
                            recentImageContext?.refresh()
                        }
                        recentImageContext?.visualSummary = turn.reply
                    }
                    cloudGuideFeedback = turn.guardianSignal == .actNow
                        ? loc.pick(
                            "这次 AI 建议马上找可信大人。",
                            "This time the AI suggests finding a trusted grown-up right away."
                        )
                        : !requestContainsImages
                            ? loc.pick(
                                "已通过家长授权的云端 AI 回复，并只把摘要写入本机记忆。",
                                "Replied through your parent-approved cloud AI; only a summary is saved to on-device memory."
                            )
                            : shouldUseRecentImage
                                ? loc.pick(
                                    "已自动带上上一张图片让视觉 AI 继续看；图片不写入长期记忆，只保存摘要。",
                                    "I brought along your last picture so the vision AI could keep looking; pictures aren't kept in long-term memory, only a summary."
                                )
                                : loc.pick(
                                    "已通过家长授权的视觉 AI 看图回复；图片不写入本机记忆，只保存摘要。",
                                    "The parent-approved vision AI looked at your picture and replied; pictures aren't saved on this device, only a summary."
                                )
                    isRequestingCloudGuide = false
                }
            } catch {
                await MainActor.run {
                    guard cloudGuideRequestID == requestID else { return }
                    cloudGuide = nil
                    let fallbackReply = !requestContainsImages
                        ? localReply
                        : AICompanionImageFallbackReply.make(
                            companionName: currentCompanionName,
                            latestText: text,
                            latestIntent: latestMessage.intent,
                            reason: .cloudUnavailable,
                            language: loc.language
                        )
                    replaceBubble(id: thinkingBubble.id, text: fallbackReply.text)
                    readReplyIfRequested(
                        bubble: AICompanionChatBubble(id: thinkingBubble.id, role: .companion, text: fallbackReply.text, imagePreviewData: []),
                        requested: readReplyAloud
                    )
                    transcriptStore.append(
                        AICompanionTranscriptEntry(
                            id: thinkingBubble.id,
                            role: .companion,
                            text: fallbackReply.text,
                            origin: !requestContainsImages ? .companionLocal : .companionFallback,
                            fallbackReason: !requestContainsImages ? nil : "image_cloud_unavailable"
                        ),
                        childId: store.activeChildId
                    )
                    remember(update: localMemoryUpdate, fallback: localMemoryUpdate)
                    cloudGuideFeedback = fallbackMessage(for: error)
                    isRequestingCloudGuide = false
                }
            }
        }
    }

    @discardableResult
    private func applyProfileCommandIfNeeded(_ text: String) -> Bool {
        guard let patch = AICompanionProfileCommandParser.parse(text) else { return false }
        if let name = patch.name {
            companionNameDraft = name
        }
        if let avatar = patch.avatarDescription {
            companionAvatarDescriptionDraft = avatar
        }
        if let voice = patch.voice {
            selectedVoice = voice
        }
        if let personality = patch.personality {
            selectedPersonality = personality
        }
        if store.setAICompanionProfile(
            name: companionNameDraft,
            voice: selectedVoice,
            personality: selectedPersonality,
            avatarDescription: companionAvatarDescriptionDraft
        ) {
            syncCompanionDraft()
            memoryStore.apply(
                AICompanionMemoryUpdate(
                    preferences: [
                        patch.name.map { "小伙伴名字：\($0)" },
                        patch.voice.map { "小伙伴声音：\($0.label)" },
                        patch.personality.map { "小伙伴人格：\($0.label)" },
                        patch.avatarDescription.map { "小伙伴形象：\($0)" }
                    ].compactMap { $0 },
                    summary: "孩子用自然语言定义了 AI 小伙伴"
                ),
                childId: store.activeChildId,
                companionName: store.child.companionDisplayName,
                avatarDescription: store.child.companionAvatarDescription,
                personalityLabel: store.child.companionPersonalityStyle.label
            )
            growthMemory.record(
                GrowthMemoryEventFactory.companionProfile(
                    childId: store.activeChildId,
                    companionName: store.child.companionDisplayName,
                    personalityLabel: store.child.companionPersonalityStyle.label
                )
            )
            return true
        }
        return false
    }

    private func activeMemoryDigest() -> AICompanionMemoryDigest {
        memoryStore.digest(
            for: store.activeChildId,
            companionName: store.child.companionDisplayName,
            avatarDescription: store.child.companionAvatarDescription,
            personalityLabel: store.child.companionPersonalityStyle.label
        )
    }

    private func rememberLocally(message: AICompanionMessage, text: String, extraSummary: String? = nil) {
        var update = AICompanionMemoryUpdate.local(intent: message.intent, childText: text)
        if let extraSummary {
            update.summary = extraSummary
        }
        remember(update: update, fallback: update)
    }

    private func remember(update: AICompanionMemoryUpdate, fallback: AICompanionMemoryUpdate) {
        let normalized = update.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && update.interests.isEmpty
            && update.preferences.isEmpty
            && update.learningNotes.isEmpty
            && update.emotionalNotes.isEmpty
            && update.homeworkGuidanceNotes.isEmpty
            ? fallback
            : update
        memoryStore.apply(
            normalized,
            childId: store.activeChildId,
            companionName: store.child.companionDisplayName,
            avatarDescription: store.child.companionAvatarDescription,
            personalityLabel: store.child.companionPersonalityStyle.label
        )
        if !normalized.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            growthMemory.record(
                GrowthMemoryEventFactory.aiChatSummary(
                    childId: store.activeChildId,
                    summary: normalized.summary
                )
            )
        }
    }

    private func replaceBubble(id: UUID, text: String) {
        guard let index = chatBubbles.firstIndex(where: { $0.id == id }) else {
            chatBubbles.append(.companion(text))
            return
        }
        chatBubbles[index].text = text
    }

    private func fallbackMessage(for error: Error) -> String {
        if let chatError = error as? AICompanionChatServiceError {
            switch chatError {
            case .notConfigured, .providerUnsupported:
                return loc.pick(
                    "真实 AI 小伙伴还没准备好，我先用本机安全步骤陪你。",
                    "The real AI buddy isn't ready yet, so I'll stay with you using safe on-device steps."
                )
            case .imageUploadNotAllowed:
                return loc.pick(
                    "图片没有发给云端 AI；需要家长先单独开启图片权限。",
                    "The picture was not sent to the cloud AI; a parent needs to turn on picture permission first."
                )
            case .badResponse, .unsafeResponse:
                return loc.pick(
                    "这次 AI 回复没有通过本机安全检查，我先不展示它。",
                    "That AI reply didn't pass the safety check on this device, so I won't show it."
                )
            case .blockedBySafetyGate:
                return loc.pick(
                    "这句话含有隐私或需要大人处理的内容，没有发给云端 AI。",
                    "That message had private things or something for a grown-up, so it was not sent to the cloud AI."
                )
            }
        }
        if let guideError = error as? AICompanionCloudGuideError {
            switch guideError {
            case .notConfigured, .providerUnsupported:
                return loc.pick(
                    "我先用本机步骤陪你，云端引导还没准备好。",
                    "I'll stay with you using on-device steps; cloud guidance isn't ready yet."
                )
            case .badResponse, .unsafeResponse:
                return loc.pick(
                    "我先不展示这次 AI 回复，继续用本机步骤更稳。",
                    "I won't show that AI reply for now; on-device steps are steadier."
                )
            case .blockedByPrivacyGateway:
                return loc.pick(
                    "这件事先不要继续发给 AI，请找可信大人一起看。",
                    "Let's not send this to the AI; please look at it with a trusted grown-up."
                )
            }
        }
        if let chatError = error as? AIChatError {
            let diagnosis = AICloudFailureDiagnosis.describe(chatError, language: loc.language)
            return loc.pick(
                "云端 AI 暂时没接上：\(diagnosis)。我先用本机安全步骤陪你。",
                "The cloud AI didn't connect: \(diagnosis). I'll stay with you using safe on-device steps."
            )
        }
        return loc.pick(
            "网络提示暂时没回来，我先用本机步骤陪你。",
            "The network reply didn't come back, so I'll use on-device steps with you."
        )
    }

    private func resetCloudGuide() {
        cloudGuideRequestID = UUID()
        cloudGuide = nil
        cloudGuideFeedback = nil
        isRequestingCloudGuide = false
    }

    private func saveCompanionProfile() {
        if store.setAICompanionProfile(
            name: companionNameDraft,
            voice: selectedVoice,
            personality: selectedPersonality,
            avatarDescription: companionAvatarDescriptionDraft
        ) {
            companionSetupFeedback = loc.pick(
                "\(store.child.companionDisplayName(for: loc.language)) 已经记住名字、声音和样子啦。",
                "\(store.child.companionDisplayName(for: loc.language)) will remember the name, voice, and look!"
            )
            memoryStore.apply(
                AICompanionMemoryUpdate(
                    preferences: [selectedVoice.label, selectedPersonality.label],
                    summary: "孩子更新了小伙伴设定"
                ),
                childId: store.activeChildId,
                companionName: store.child.companionDisplayName,
                avatarDescription: store.child.companionAvatarDescription,
                personalityLabel: store.child.companionPersonalityStyle.label
            )
            growthMemory.record(
                GrowthMemoryEventFactory.companionProfile(
                    childId: store.activeChildId,
                    companionName: store.child.companionDisplayName,
                    personalityLabel: store.child.companionPersonalityStyle.label
                )
            )
        }
    }
}

private struct AICompanionChatBubble: Identifiable, Equatable {
    enum Role: String {
        case child
        case companion
    }

    let id: UUID
    var role: Role
    var text: String
    var imagePreviewData: [Data]

    static func child(_ text: String, imagePreviewData: [Data] = []) -> AICompanionChatBubble {
        AICompanionChatBubble(id: UUID(), role: .child, text: text, imagePreviewData: imagePreviewData)
    }

    static func companion(_ text: String) -> AICompanionChatBubble {
        AICompanionChatBubble(id: UUID(), role: .companion, text: text, imagePreviewData: [])
    }
}

private struct PendingCompanionImage: Identifiable {
    enum Owner {
        case child
        case parent
    }

    let id: UUID
    var source: AICompanionImageAttachment.Source
    var data: Data
    var preview: UIImage
    var owner: Owner = .child
    /// 附件摘要发给 AI 时使用的语言：跟随入队那一刻的孩子界面语言。
    var language: AppInterfaceLanguage = .chinese

    var localSummary: String {
        if owner == .parent {
            return language.pick(
                source == .camera
                    ? "家长拍了一张照片，请 AI 结合育儿上下文分析。"
                    : "家长从相册选择了一张图片，请 AI 结合育儿上下文分析。",
                source == .camera
                    ? "The parent took a photo and asked the AI to consider it with the parenting context."
                    : "The parent selected a picture and asked the AI to consider it with the parenting context."
            )
        }
        switch source {
        case .camera:
            return language.pick(
                "孩子拍了一张照片并授权小伙伴查看。",
                "The child took a photo and allowed the buddy to view it."
            )
        case .photoLibrary:
            return language.pick(
                "孩子从相册选择了一张图片并授权小伙伴查看。",
                "The child picked a picture from the album and allowed the buddy to view it."
            )
        }
    }

    var attachment: AICompanionImageAttachment {
        AICompanionImageAttachment(
            source: source,
            mimeType: "image/jpeg",
            data: data,
            localSummary: localSummary
        )
    }

    var thumbnailData: Data {
        preview
            .normalizedForAICompanion(maxDimension: 240)
            .jpegData(compressionQuality: 0.55) ?? Data()
    }

    static func prepared(
        from image: UIImage,
        source: AICompanionImageAttachment.Source,
        language: AppInterfaceLanguage = .chinese,
        owner: Owner = .child
    ) -> PendingCompanionImage? {
        let normalized = image.normalizedForAICompanion(maxDimension: 960)
        guard let data = normalized.jpegData(compressionQuality: 0.72), !data.isEmpty else { return nil }
        return PendingCompanionImage(
            id: UUID(),
            source: source,
            data: data,
            preview: normalized,
            owner: owner,
            language: language
        )
    }
}

private extension UIImage {
    func normalizedForAICompanion(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else {
            return redrawn()
        }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    func redrawn() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private enum ParentAICenterMode: String, CaseIterable, Identifiable {
    case chat
    case family

    var id: String { rawValue }

    func label(for language: AppInterfaceLanguage) -> String {
        switch self {
        case .chat: return language.pick("聊天", "Chat")
        case .family: return language.pick("家庭 AI 中心", "Family AI")
        }
    }
}

struct ParentAICompanionOverviewView: View {
    @Environment(LocalFamilyStore.self) private var store
    @State private var mode: ParentAICenterMode = .family

    private var language: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(language.pick("AI 中心模式", "AI Center mode"), selection: $mode) {
                ForEach(ParentAICenterMode.allCases) { item in
                    Text(item.label(for: language)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .accessibilityIdentifier("parent-ai-center-mode")

            switch mode {
            case .chat:
                ParentAICompanionCoachView()
            case .family:
                ParentFamilyAICenterView()
            }
        }
        .navigationTitle(language.pick("家长 AI 中心", "Parent AI Center"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ParentFamilyAICenterView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(GrowthMemoryStore.self) private var growthMemory
    @State private var isConfirmingPlan = false
    @State private var isPresentingComposer = false

    private var language: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    private var insight: ParentFamilyAIInsight {
        ParentFamilyAIInsight.build(
            childName: store.child.name,
            assignments: store.assignments.filter { $0.childId == store.activeChildId },
            growthDigest: growthMemory.digest(for: store.activeChildId),
            creditBalance: store.creditBalance,
            language: language
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                insightCard(
                    title: language.pick("今天发生了什么", "What happened today"),
                    icon: "sun.max.fill",
                    tint: .orange,
                    lines: [insight.todaySummary]
                )
                insightCard(
                    title: language.pick("需要家长处理", "Needs your attention"),
                    icon: "checklist",
                    tint: .red,
                    lines: insight.attentionItems
                )
                insightCard(
                    title: language.pick("最近出现的模式", "Recent pattern"),
                    icon: "chart.line.uptrend.xyaxis",
                    tint: .teal,
                    lines: [insight.recentPattern]
                )
                insightCard(
                    title: language.pick("推荐沟通方式", "Suggested communication"),
                    icon: "bubble.left.and.bubble.right.fill",
                    tint: .purple,
                    lines: [insight.communicationSuggestion]
                )

                Button {
                    isConfirmingPlan = true
                } label: {
                    Label(
                        language.pick("生成计划草稿", "Generate plan draft"),
                        systemImage: "wand.and.stars"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("parent-family-ai-generate-plan")

                Text(language.pick(
                    "AI 只整理事实并生成草稿；任务内容、奖励和发布都需要家长确认。",
                    "AI organizes facts and drafts a plan; a parent must confirm the task, reward, and publishing."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .confirmationDialog(
            language.pick("为 \(store.child.name) 生成一个可编辑任务？", "Create an editable task for \(store.child.name)?"),
            isPresented: $isConfirmingPlan,
            titleVisibility: .visible
        ) {
            Button(language.pick("确认并进入任务编辑器", "Confirm and open task editor")) {
                isPresentingComposer = true
            }
            Button(language.pick("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(language.pick(
                "将根据今天的完成情况和近期成长记录预填一个最小任务，发布前仍可修改。",
                "A small task will be prefilled from today's progress and recent growth records. You can edit it before publishing."
            ))
        }
        .sheet(isPresented: $isPresentingComposer) {
            NavigationStack {
                ParentTaskComposerView(starterPreset: starterPreset(for: insight.recommendedGoal))
            }
        }
    }

    private func insightCard(title: String, icon: String, tint: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func starterPreset(for goal: ParentAIPlanGoal) -> ParentTaskStarterPreset {
        switch goal {
        case .reading: return .reading20
        case .outdoor: return .outdoorPlay
        case .tidy: return .tidyDesk
        case .sleep: return .sleepReady
        }
    }
}

private struct ParentAICompanionCoachView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(AICompanionSessionStore.self) private var sessionStore
    @Environment(AICompanionMemoryStore.self) private var memoryStore
    @Environment(AICompanionTranscriptStore.self) private var childTranscriptStore
    @Environment(ParentAICompanionCoachStore.self) private var coachStore
    @Environment(GrowthMemoryStore.self) private var growthMemory
    @Environment(ParentAIProviderStore.self) private var aiProvider

    @State private var bubbles: [ParentAICompanionCoachBubble] = []
    @State private var draft = ""
    @State private var isRequestingCloud = false
    @State private var coachFeedback: String?
    @State private var requestID = UUID()
    @State private var audioRecorder = ProofAudioRecorder()
    @State private var isTranscribingVoice = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var pendingImages: [PendingCompanionImage] = []
    @FocusState private var isComposeFieldFocused: Bool

    private let service = ParentAICompanionCoachService()

    private var language: AppInterfaceLanguage {
        store.settings.resolvedParentInterfaceLanguage
    }

    var body: some View {
        VStack(spacing: 0) {
            coachTranscript
            Divider()
            coachComposer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            restoreTranscript()
        }
        .onChange(of: store.activeChildId) { _, _ in
            restoreTranscript()
            coachFeedback = nil
        }
        .onChange(of: audioRecorder.state) { _, newState in
            if case .finished(let fileURL) = newState {
                handleParentVoiceFinished(fileURL: fileURL)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            handleParentPhotoPicked(newItem)
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in
                showCamera = false
                handleParentCameraCaptured(image)
            }
        }
    }

    private var coachTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    coachStatusCard
                    quickPromptChips

                    ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                        coachBubbleRow(bubble, index: index)
                            .id(bubble.id)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .accessibilityIdentifier("parent-ai-coach-chat-window")
            .onChange(of: bubbles.count) { _, _ in
                if let last = bubbles.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var coachStatusCard: some View {
        let childMemory = activeChildMemory()
        let growthDigest = growthMemory.digest(for: store.activeChildId)
        let parentMemory = coachStore.memory(for: store.activeChildId)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: aiProvider.isReadyForAIComposer ? "cloud" : "iphone")
                    .font(.title2)
                    .foregroundStyle(aiProvider.isReadyForAIComposer ? .green : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.pick("给 \(store.child.name) 家长的育儿教练", "Parenting coach for \(store.child.name)"))
                        .font(.headline)
                    Text(aiProvider.isReadyForAIComposer
                         ? language.pick("使用家长 BYOK 云端模型；只发送摘要，不发送孩子完整聊天。", "Uses the parent's BYOK cloud model; only summaries are sent, never the child's full chat.")
                         : language.pick("AI 服务商未就绪，当前使用本机育儿策略规则。", "The AI provider is not ready; on-device parenting rules are active."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(aiProvider.isReadyForAIComposer ? "parent-ai-coach-cloud-ready" : "parent-ai-coach-local-mode")
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(language.pick("孩子小伙伴：\(childMemory.companionName) · \(childMemory.personalityLabel)", "Child's buddy: \(childMemory.companionName) · \(childMemory.personalityLabel)"))
                    .font(.subheadline.weight(.semibold))
                Text(childMemory.latestSummary.isEmpty
                     ? language.pick("孩子 AI 小伙伴还没有形成稳定摘要。", "The child's AI buddy has not formed a stable summary yet.")
                     : language == .english
                        ? "A recent child-buddy summary is available for the coach."
                        : childMemory.latestSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(growthDigest.totalEventCount == 0
                     ? language.pick("成长记录暂时为空。", "Growth records are empty for now.")
                     : language.pick(
                        "成长事件 \(growthDigest.totalEventCount) 条：\(growthDigest.recentHighlights.prefix(2).joined(separator: "；"))",
                        "\(growthDigest.totalEventCount) growth events are available for the coach."
                     ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !parentMemory.latestSummary.isEmpty {
                    Text(language.pick(
                        "家长教练记忆：\(parentMemory.latestSummary)",
                        "A recent parenting strategy is saved locally."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                SoftwareSettingsView()
            } label: {
                Label(
                    aiProvider.isReadyForAIComposer
                        ? language.pick("管理软件与 AI 设置", "Manage app and AI settings")
                        : language.pick("去配置软件与 AI", "Set up app and AI"),
                    systemImage: "gearshape"
                )
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityIdentifier("parent-ai-coach-open-ai-settings")
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var quickPromptChips: some View {
        let prompts = language == .english
            ? [
                "How can we reduce short-video conflict tonight?",
                "How can I help my child start reading?",
                "What should I say when homework feels stuck?",
                "How should Growth Points exchange for screen time?"
            ]
            : [
                "今晚怎么减少短视频冲突？",
                "怎么让孩子愿意开始阅读？",
                "孩子作业卡住时我该怎么说？",
                "成长积分怎么换屏幕时间更合理？"
            ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(prompts, id: \.self) { prompt in
                    Button(prompt) {
                        send(prompt)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .disabled(isRequestingCloud)
                    .accessibilityIdentifier("parent-ai-coach-quick-prompt")
                }
            }
        }
    }

    private func coachBubbleRow(_ bubble: ParentAICompanionCoachBubble, index: Int) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if bubble.role == .parent {
                Spacer(minLength: 36)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !bubble.imagePreviewData.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(Array(bubble.imagePreviewData.enumerated()), id: \.offset) { itemIndex, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .accessibilityIdentifier("parent-ai-coach-message-image-\(index)-\(itemIndex)")
                            }
                        }
                    }
                }
                Text(bubble.text)
                    .font(.subheadline)
                    .foregroundStyle(bubble.role == .parent ? .white : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if bubble.role == .coach {
                    SpeakButton(
                        text: store.settings.resolvedParentInterfaceLanguage.pick(
                            "家长 AI 教练：\(bubble.text)",
                            "Parent AI Coach: \(bubble.text)"
                        ),
                        language: store.settings.resolvedParentInterfaceLanguage
                    )
                        .accessibilityIdentifier("parent-ai-coach-speak-message-\(index)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bubble.role == .parent ? Color.blue : Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: 330, alignment: bubble.role == .parent ? .trailing : .leading)
            .accessibilityIdentifier("parent-ai-coach-message-\(bubble.role.rawValue)-\(index)")

            if bubble.role == .coach {
                Spacer(minLength: 36)
            }
        }
    }

    private var coachComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingImages) { image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image.preview)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 68, height: 68)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Button {
                                    pendingImages.removeAll { $0.id == image.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.55))
                                }
                                .accessibilityLabel(language.pick("移除图片", "Remove picture"))
                            }
                        }
                    }
                }
            }
            if let coachFeedback {
                Text(coachFeedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("parent-ai-coach-feedback")
            }
            HStack(alignment: .bottom, spacing: 8) {
                parentVoiceComposerButton

                TextField(language.pick("问问怎么做一个更好的家长", "Ask how to become a better parent"), text: $draft, axis: .vertical)
                    .focused($isComposeFieldFocused)
                    .lineLimit(1...4)
                    .submitLabel(.send)
                    .onSubmit {
                        submitDraft()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("parent-ai-coach-free-text")

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(language.pick("从相册选择图片", "Choose a picture"))
                .accessibilityIdentifier("parent-ai-coach-photo-input")

                if CameraCaptureView.isCameraAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Image(systemName: "camera")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(language.pick("拍照", "Take a photo"))
                    .accessibilityIdentifier("parent-ai-coach-camera-input")
                }

                Button {
                    submitDraft()
                } label: {
                    Image(systemName: isRequestingCloud ? "hourglass" : "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(isRequestingCloud || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingImages.isEmpty))
                .accessibilityIdentifier("parent-ai-coach-send")
            }
            if isTranscribingVoice {
                Label(language.pick("正在把语音变成文字……", "Turning voice into text…"), systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var parentVoiceComposerButton: some View {
        switch audioRecorder.state {
        case .idle:
            Button {
                audioRecorder.startRecording()
            } label: {
                Image(systemName: "mic.circle.fill")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .disabled(!aiProvider.isParentVoiceTranscriptionReady)
            .accessibilityLabel(language.pick("按麦克风说话", "Press the mic to talk"))
            .accessibilityIdentifier("parent-ai-coach-voice-start")
        case .denied:
            Image(systemName: "mic.slash")
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .accessibilityLabel(language.pick("没有麦克风权限", "Microphone permission is off"))
        case .recording:
            Button {
                audioRecorder.stopRecording()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(language.pick("停止录音", "Stop recording"))
            .accessibilityIdentifier("parent-ai-coach-voice-stop")
        case .finished:
            ProgressView()
                .frame(width: 32, height: 32)
        }
    }

    private func restoreTranscript() {
        bubbles = coachStore.recentEntries(for: store.activeChildId).map {
            ParentAICompanionCoachBubble(
                id: $0.id,
                role: $0.role == .parent ? .parent : .coach,
                text: $0.text,
                imagePreviewData: []
            )
        }
        if bubbles.isEmpty {
            bubbles.append(
                .coach(language.pick(
                    "我是家长 AI 教练。我会结合 \(store.child.name) 的小伙伴记忆、成长记录、任务和奖励状态，帮你设计更好的沟通、任务、奖励和复盘方式。",
                    "I'm your parent AI coach. I use \(store.child.name)'s buddy memory, growth records, tasks, and rewards to help plan communication, routines, and reflection."
                ))
            )
        }
    }

    private func submitDraft() {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages
        guard !text.isEmpty || !images.isEmpty, !isRequestingCloud else { return }
        if text.isEmpty {
            text = language.pick(
                "请结合这张图片和孩子的成长背景，帮我分析我应该如何回应或安排下一步。",
                "Please use this picture and my child's growth context to help me decide how to respond or plan the next step."
            )
        }
        draft = ""
        pendingImages = []
        isComposeFieldFocused = false
        send(text, images: images)
    }

    private func handleParentVoiceFinished(fileURL: URL) {
        guard aiProvider.isParentVoiceTranscriptionReady else {
            try? FileManager.default.removeItem(at: fileURL)
            audioRecorder.discard()
            coachFeedback = language.pick(
                "当前 AI 服务商不支持语音转文字，可以先打字或发图片。",
                "The current AI provider does not support voice-to-text. Type or share a picture instead."
            )
            return
        }
        Task {
            isTranscribingVoice = true
            defer {
                isTranscribingVoice = false
                audioRecorder.discard()
            }
            do {
                let text = try await aiProvider.transcribeParentAIAudio(
                    at: fileURL,
                    using: OpenAIStyleTranscriptionClient()
                )
                draft = AICompanionVoiceComposer.mergedDraft(existingDraft: draft, transcript: text)
                coachFeedback = language.pick(
                    "语音已经放进输入框，确认后发送；图片会和语音问题一起交给 AI。",
                    "Your voice is in the composer. Review and send it; any pictures will go with the question."
                )
            } catch {
                coachFeedback = language.pick(
                    "这次语音没有转成文字，请再试一次。",
                    "That voice note was not turned into text. Please try again."
                )
            }
        }
    }

    private func handleParentPhotoPicked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        selectedPhotoItem = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let pending = PendingCompanionImage.prepared(
                    from: image,
                    source: .photoLibrary,
                    language: language,
                    owner: .parent
                  ) else {
                await MainActor.run {
                    coachFeedback = language.pick("这张图片暂时无法读取。", "That picture could not be read.")
                }
                return
            }
            await MainActor.run {
                pendingImages.append(pending)
                coachFeedback = language.pick(
                    "图片已加入，发送时会和当前问题一起交给家长的云端模型。",
                    "Picture added. It will be sent with the current question to the parent's cloud model."
                )
            }
        }
    }

    private func handleParentCameraCaptured(_ image: UIImage) {
        guard let pending = PendingCompanionImage.prepared(
            from: image,
            source: .camera,
            language: language,
            owner: .parent
        ) else {
            coachFeedback = language.pick("这张照片暂时无法处理。", "That photo could not be processed.")
            return
        }
        pendingImages.append(pending)
        coachFeedback = language.pick(
            "照片已加入，发送前不会上传。",
            "Photo added. It will not upload until you send."
        )
    }

    private func send(_ text: String, images: [PendingCompanionImage] = []) {
        let parentBubble = ParentAICompanionCoachBubble.parent(text, imagePreviewData: images.map(\.thumbnailData))
        bubbles.append(parentBubble)
        coachStore.append(
            ParentAICompanionCoachEntry(id: parentBubble.id, role: .parent, text: text, origin: .parentText),
            childId: store.activeChildId
        )

        let request = coachRequest(latestText: text, images: images)
        guard request.isProviderRequestAllowed else {
            appendCoachTurn(
                service.localTurn(request: request),
                origin: .coachFallback,
                feedback: language.pick(
                    "这次问题包含不适合发送给云端的内容，已改用本机育儿策略。",
                    "This request contained content that should not go to the cloud, so on-device parenting guidance was used."
                )
            )
            return
        }

        guard aiProvider.isReadyForAIComposer else {
            appendCoachTurn(
                service.localTurn(request: request),
                origin: .coachLocal,
                feedback: language.pick(
                    "AI 服务商未就绪，已用本机规则生成建议。",
                    "The AI provider is not ready, so on-device guidance was used."
                )
            )
            return
        }

        let currentRequestID = UUID()
        requestID = currentRequestID
        isRequestingCloud = true
        coachFeedback = language.pick(
            "正在结合孩子记忆和成长记录生成建议……",
            "Using the child's memory and growth records to prepare a suggestion…"
        )
        let thinking = ParentAICompanionCoachBubble.coach(language.pick(
            "我正在看孩子的记忆摘要和最近成长记录……",
            "I'm reviewing the child's memory summary and recent growth records…"
        ))
        bubbles.append(thinking)

        Task {
            do {
                let raw = try await aiProvider.completeParentMultimodalChat(
                    system: service.systemPrompt(request),
                    user: service.userPrompt(request),
                    imageAttachments: images.map(\.attachment)
                )
                let turn = try service.parseTurn(raw)
                await MainActor.run {
                    guard requestID == currentRequestID else { return }
                    replaceBubble(id: thinking.id, text: turn.reply)
                    coachStore.append(
                        ParentAICompanionCoachEntry(
                            id: thinking.id,
                            role: .coach,
                            text: turn.reply,
                            origin: .coachCloud
                        ),
                        childId: store.activeChildId
                    )
                    coachStore.apply(turn.memoryUpdate, childId: store.activeChildId)
                    coachFeedback = language.pick(
                        "已使用家长 BYOK 云端模型；只发送摘要、当前问题和家长主动选择的图片。",
                        "Used the parent's BYOK cloud model; only summaries, the current question, and parent-selected pictures were sent."
                    )
                    isRequestingCloud = false
                }
            } catch {
                await MainActor.run {
                    guard requestID == currentRequestID else { return }
                    let fallback = service.localTurn(request: request, shouldRecordStrategy: false)
                    replaceBubble(id: thinking.id, text: fallback.reply)
                    coachStore.append(
                        ParentAICompanionCoachEntry(
                            id: thinking.id,
                            role: .coach,
                            text: fallback.reply,
                            origin: .coachFallback
                        ),
                        childId: store.activeChildId
                    )
                    coachFeedback = language.pick(
                        "云端生成失败：\(AICloudFailureDiagnosis.describe(error, language: language))。已临时使用本机建议，未写入长期策略记忆。",
                        "Cloud generation failed: \(AICloudFailureDiagnosis.describe(error, language: language)). Temporary on-device guidance was used and was not written to long-term strategy memory."
                    )
                    isRequestingCloud = false
                }
            }
        }
    }

    private func appendCoachTurn(
        _ turn: ParentAICompanionCoachTurn,
        origin: ParentAICompanionCoachEntry.Origin,
        feedback: String
    ) {
        let bubble = ParentAICompanionCoachBubble.coach(turn.reply)
        bubbles.append(bubble)
        coachStore.append(
            ParentAICompanionCoachEntry(id: bubble.id, role: .coach, text: turn.reply, origin: origin),
            childId: store.activeChildId
        )
        coachStore.apply(turn.memoryUpdate, childId: store.activeChildId)
        coachFeedback = feedback
    }

    private func replaceBubble(id: UUID, text: String) {
        guard let index = bubbles.firstIndex(where: { $0.id == id }) else { return }
        bubbles[index].text = text
    }

    private func coachRequest(latestText: String, images: [PendingCompanionImage] = []) -> ParentAICompanionCoachRequest {
        ParentAICompanionCoachRequest(
            childName: store.child.name,
            childAge: store.child.age,
            latestText: latestText,
            childMemory: activeChildMemory(),
            growthProfileSummary: [
                growthMemory.digest(for: store.activeChildId).promptSummary,
                store.schoolDynamicsPromptSummary(for: store.activeChildId)
            ].filter { !$0.isEmpty }.joined(separator: "\n"),
            childRecentContextLines: childTranscriptStore.recentCloudContextLines(for: store.activeChildId),
            parentMemory: coachStore.memory(for: store.activeChildId),
            parentRecentContextLines: coachStore.recentCloudContextLines(for: store.activeChildId),
            activeTasksSummary: activeTasksSummary(),
            rewardSummary: rewardSummary(),
            attachmentSummaries: images.map(\.localSummary),
            language: language
        )
    }

    private func activeChildMemory() -> AICompanionMemoryDigest {
        memoryStore.digest(
            for: store.activeChildId,
            companionName: store.child.companionDisplayName,
            avatarDescription: store.child.companionAvatarDescription,
            personalityLabel: store.child.companionPersonalityStyle.label
        )
    }

    private func activeTasksSummary() -> String {
        let rows = store.assignments
            .filter { $0.childId == store.activeChildId && $0.status != .cancelled }
            .prefix(5)
            .map { assignment in
                "- \(assignment.task.title)：\(statusLabel(assignment.status))，\(GrowthCreditCopy.label(points: assignment.task.rewardMinutes))"
            }
        return rows.isEmpty ? "none" : rows.joined(separator: "\n")
    }

    private func rewardSummary() -> String {
        let balance = store.creditBalance(for: store.activeChildId)
        let wishes = store.wishes
            .filter { $0.childId == store.activeChildId && $0.status != .rejected }
            .prefix(4)
            .map { wish in
                "\(wish.title)(\(wish.status.label)\(wish.pricePoints.map { " \($0)分" } ?? ""))"
            }
            .joined(separator: "、")
        let wishSummary = wishes.isEmpty ? "愿望清单暂无可推进项目" : "愿望：\(wishes)"
        return "可用成长积分 \(balance.availableMinutes)，待批准 \(balance.pendingMinutes)，累计 \(balance.lifetimeEarnedMinutes)。\(wishSummary)"
    }

    private func statusLabel(_ status: TaskAssignmentStatus) -> String {
        switch status {
        case .open: return "待开始"
        case .submitted: return "待家长确认"
        case .approved: return "已完成"
        case .rejected: return "需要重做"
        case .cancelled: return "已撤销"
        }
    }
}

private struct ParentAICompanionCoachBubble: Identifiable, Equatable {
    enum Role: String {
        case parent
        case coach
    }

    let id: UUID
    var role: Role
    var text: String
    var imagePreviewData: [Data]

    static func parent(_ text: String, imagePreviewData: [Data] = []) -> ParentAICompanionCoachBubble {
        ParentAICompanionCoachBubble(id: UUID(), role: .parent, text: text, imagePreviewData: imagePreviewData)
    }

    static func coach(_ text: String) -> ParentAICompanionCoachBubble {
        ParentAICompanionCoachBubble(id: UUID(), role: .coach, text: text, imagePreviewData: [])
    }
}
