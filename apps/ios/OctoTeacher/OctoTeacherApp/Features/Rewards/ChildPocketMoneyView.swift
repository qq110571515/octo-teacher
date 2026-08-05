import SwiftUI

enum ChildWishListCopy {
    static let emptyTitle = "先说一个小愿望"
    static let emptyDetail = "可以说想要的书、玩具、一次公园、一次亲子时间。大人会帮你定需要多少成长积分。"
    static let emptySpeakText = "先说一个小愿望。可以说，我想要一本恐龙书，或者我想周末去公园。大人会帮你定需要多少成长积分。"
    static let footer = "提交愿望后，大人会告诉你需要多少成长积分；攒够了就能兑换。兑换只会扣成长积分并告诉大人，不会自动花钱或购买。幼儿可以点小喇叭听说明，也可以按麦克风说愿望。"

    static func emptyTitle(for language: AppInterfaceLanguage) -> String {
        language.pick(emptyTitle, "Tell a little wish first")
    }

    static func emptyDetail(for language: AppInterfaceLanguage) -> String {
        language.pick(
            emptyDetail,
            "You can ask for a book, a toy, a park trip, or family time. A grown-up will decide how many Growth Points it needs."
        )
    }

    static func emptySpeakText(for language: AppInterfaceLanguage) -> String {
        language.pick(
            emptySpeakText,
            "Tell a little wish first. You can say, I want a dinosaur book, or I want to go to the park this weekend. A grown-up will decide how many Growth Points it needs."
        )
    }

    static func footer(for language: AppInterfaceLanguage) -> String {
        language.pick(
            footer,
            "After you send a wish, a grown-up will tell you how many Growth Points it needs. Save enough and you can redeem it! Redeeming only uses Growth Points and tells a grown-up — it never spends real money by itself. Little kids can tap the speaker to listen, or press the microphone to say a wish."
        )
    }

    static func balance(_ points: Int, language: AppInterfaceLanguage = .chinese) -> String {
        GrowthCreditCopy.label(points: points, language: language)
    }

    static func statusLine(
        for wish: WishListItem,
        availablePoints: Int,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        switch wish.status {
        case .proposed:
            return language.pick("等大人定价", "Waiting for a grown-up to set the price")
        case .priced:
            guard let price = wish.pricePoints else {
                return language.pick("可以兑换", "Ready to redeem")
            }
            if availablePoints >= price {
                return language.pick(
                    "需要 \(GrowthCreditCopy.label(points: price)) · 可以兑换啦",
                    "Needs \(GrowthCreditCopy.label(points: price, language: language)) · You can redeem it now!"
                )
            }
            return language.pick(
                "需要 \(GrowthCreditCopy.label(points: price)) · 还差 \(GrowthCreditCopy.label(points: price - availablePoints))",
                "Needs \(GrowthCreditCopy.label(points: price, language: language)) · \(GrowthCreditCopy.label(points: price - availablePoints, language: language)) to go"
            )
        case .redeemed:
            return language.pick("已经兑换，等大人兑现", "Redeemed — a grown-up will make it happen")
        case .fulfilled:
            return language.pick("愿望已实现", "Wish came true!")
        case .rejected:
            return language.pick("没通过", "Not approved")
        }
    }

    static func speakText(
        for wish: WishListItem,
        availablePoints: Int,
        language: AppInterfaceLanguage = .chinese
    ) -> String {
        language.pick(
            "愿望：\(wish.title)。\(statusLine(for: wish, availablePoints: availablePoints))。",
            "Wish: \(wish.title). \(statusLine(for: wish, availablePoints: availablePoints, language: language))."
        )
    }
}

/// 孩子端奖励中心：零花钱 + 愿望清单。
/// App 只记账和排队——真实的钱与愿望都由大人线下兑现。
struct ChildPocketMoneyView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(ParentAIProviderStore.self) private var aiProvider

    @State private var exchangePoints = 10
    @State private var feedback: String?
    @State private var newWishTitle = ""
    @State private var wishFeedback: String?
    @State private var wishRecorder = ProofAudioRecorder()
    @State private var isTranscribingWish = false

    /// 当前孩子的界面语言：本页所有可见文案与小喇叭 speech 都从这里取。
    private var loc: ChildLocalizationContext { ChildLocalizationContext(language: childSurfaceLanguage) }

    private var policy: FamilyExchangePolicy { store.policy(for: store.activeChildId) }
    private var summary: (pendingPayout: Int, paidTotal: Int, thisMonthExchanged: Int) {
        store.pocketMoneySummary(for: store.activeChildId)
    }
    private var myEntries: [MoneyLedgerEntry] {
        store.moneyLedger.filter { $0.childId == store.activeChildId }
    }
    private var wishVoiceGuideText: String {
        loc.pick(
            "如果还不太会打字，可以按这里说愿望，或者点输入框，再点键盘上的麦克风。比如：我想要一本恐龙书，或者我想周末去游乐园。",
            "If typing is hard, press here to say your wish, or tap the box and use the keyboard microphone. For example: I want a dinosaur book, or I want to go to the fun park this weekend."
        )
    }

    var body: some View {
        List {
            Section(loc.pick("我的零花钱", "My Pocket Money")) {
                HStack {
                    Text(loc.pick(
                        "💰 等大人给我：\(policy.currencySymbol)\(summary.pendingPayout)",
                        "💰 A grown-up will give me: \(policy.currencySymbol)\(summary.pendingPayout)"
                    ))
                    Spacer()
                    SpeakButton(
                        text: loc.pick(
                            "有 \(summary.pendingPayout) 块零花钱，等大人给你。",
                            "You have \(policy.currencySymbol)\(summary.pendingPayout) of pocket money waiting — a grown-up will give it to you."
                        ),
                        language: loc.language
                    )
                }
                HStack {
                    Text(loc.pick(
                        "✅ 已经拿到：\(policy.currencySymbol)\(summary.paidTotal)",
                        "✅ Already got: \(policy.currencySymbol)\(summary.paidTotal)"
                    ))
                    Spacer()
                    SpeakButton(
                        text: loc.pick(
                            "已经拿到 \(summary.paidTotal) 块零花钱啦。",
                            "You already got \(policy.currencySymbol)\(summary.paidTotal) of pocket money!"
                        ),
                        language: loc.language
                    )
                }
            }

            wishSection

            Section {
                LabeledContent(
                    loc.pick("我的成长积分", "My Growth Points"),
                    value: ChildWishListCopy.balance(store.creditBalance.availableMinutes, language: loc.language)
                )
                Stepper(
                    loc.pick(
                        "用 \(exchangePoints) 成长积分换 \(policy.currencySymbol)\(exchangePoints / policy.pointsPerCurrencyUnit)",
                        "Trade \(exchangePoints) Growth Points for \(policy.currencySymbol)\(exchangePoints / policy.pointsPerCurrencyUnit)"
                    ),
                    value: $exchangePoints,
                    in: policy.pointsPerCurrencyUnit...max(policy.pointsPerCurrencyUnit, store.creditBalance.availableMinutes),
                    step: policy.pointsPerCurrencyUnit
                )
                Button(loc.pick("🎁 换零花钱", "🎁 Get pocket money")) {
                    if let blocker = store.pocketMoneyExchangeBlocker(points: exchangePoints) {
                        feedback = pocketMoneyBlockerMessage(blocker)
                    } else if store.requestPocketMoneyExchange(points: exchangePoints) != nil {
                        feedback = policy.pocketMoneyRequiresApproval
                            ? loc.pick("已经告诉大人啦，等确认。", "We told a grown-up. Waiting for their OK.")
                            : loc.pick("换好啦，等大人把钱给你。", "Done! A grown-up will give you the money.")
                    } else {
                        feedback = loc.pick(
                            "换不了：请让大人检查家庭零花钱设置。",
                            "Can't exchange right now. Ask a grown-up to check the family pocket money settings."
                        )
                    }
                }
                .disabled(store.creditBalance.availableMinutes < policy.pointsPerCurrencyUnit)
                .accessibilityIdentifier("pocket-money-exchange")
            } header: {
                Text(loc.pick(
                    "成长积分换零花钱（\(GrowthCreditCopy.label(points: policy.pointsPerCurrencyUnit)) = \(policy.currencySymbol)1）",
                    "Points to Pocket Money (\(GrowthCreditCopy.label(points: policy.pointsPerCurrencyUnit, language: .english)) = \(policy.currencySymbol)1)"
                ))
            } footer: {
                if let feedback {
                    // 操作结果反馈配手动小喇叭：不识字的孩子点一下就能听到结果，不自动播报。
                    HStack(alignment: .top) {
                        Text(feedback)
                        Spacer()
                        SpeakButton(text: feedback, language: loc.language)
                    }
                    .accessibilityIdentifier("pocket-money-feedback")
                } else if let cap = policy.monthlyPocketMoneyCap {
                    Text(loc.pick(
                        "这个月最多能换 \(policy.currencySymbol)\(cap)，已换 \(policy.currencySymbol)\(summary.thisMonthExchanged)。",
                        "This month you can get up to \(policy.currencySymbol)\(cap); you've gotten \(policy.currencySymbol)\(summary.thisMonthExchanged) so far."
                    ))
                }
            }

            if !myEntries.isEmpty {
                Section(loc.pick("零花钱记录", "Pocket Money History")) {
                    ForEach(myEntries.prefix(20)) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.kind.label(for: loc.language))
                                    .font(.subheadline)
                                if !entry.note.isEmpty {
                                    Text(entry.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(entry.amount >= 0 ? "+" : "")\(policy.currencySymbol)\(entry.amount)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(entry.status == .rejected ? .secondary : .primary)
                                Text(entry.status.label(for: loc.language))
                                    .font(.caption2)
                                    .foregroundStyle(entry.status == .paid ? .green : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(loc.pick("零花钱和愿望", "Money & Wishes"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: wishRecorder.state) { _, newState in
            if case .finished(let fileURL) = newState {
                handleWishVoiceFinished(fileURL: fileURL)
            }
        }
    }

    /// 录音结束：转写成文字填进愿望输入框，孩子确认没错后再提交。
    private func handleWishVoiceFinished(fileURL: URL) {
        Task {
            isTranscribingWish = true
            defer {
                isTranscribingWish = false
                wishRecorder.discard()
            }
            let text = try? await aiProvider.transcribeChildProofAudio(
                at: fileURL,
                using: OpenAIStyleTranscriptionClient()
            )
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                wishFeedback = loc.pick(
                    "没听清，再说一次试试；也可以点输入框用键盘上的麦克风。",
                    "We didn't catch that. Try again, or tap the box and use the keyboard microphone."
                )
            } else {
                newWishTitle = trimmed
                wishFeedback = loc.pick(
                    "我听到你想要：\(trimmed)。没错的话点「提交」告诉大人。",
                    "I heard you want: \(trimmed). If that's right, tap Send to tell a grown-up."
                )
            }
        }
    }

    private var myWishes: [WishListItem] {
        store.wishes.filter { $0.childId == store.activeChildId && $0.status != .rejected }
    }

    private func pocketMoneyBlockerMessage(_ blocker: LocalFamilyStore.PocketMoneyExchangeBlocker) -> String {
        switch blocker {
        case .unknownChild:
            return loc.pick(
                "换不了：请让大人检查家庭成员设置。",
                "Can't exchange right now. Ask a grown-up to check the family member settings."
            )
        case .belowMinimum(let requiredPoints):
            return loc.pick(
                "还差一点：至少要 \(GrowthCreditCopy.label(points: requiredPoints)) 才能换 1 元。",
                "Almost there! You need at least \(GrowthCreditCopy.label(points: requiredPoints, language: .english)) to get \(policy.currencySymbol)1."
            )
        case .insufficientCredits(let requiredPoints, let availablePoints):
            return loc.pick(
                "成长积分还不够：还差 \(GrowthCreditCopy.label(points: max(0, requiredPoints - availablePoints)))，先去完成任务吧。",
                "Not enough Growth Points yet: \(GrowthCreditCopy.label(points: max(0, requiredPoints - availablePoints), language: .english)) to go. Go finish some tasks first!"
            )
        case .monthlyCapReached(let cap, let alreadyExchanged):
            return loc.pick(
                "这个月零花钱兑换到上限啦：最多 \(policy.currencySymbol)\(cap)，已经换了 \(policy.currencySymbol)\(alreadyExchanged)。下个月再换。",
                "You've reached this month's limit: up to \(policy.currencySymbol)\(cap), and you already got \(policy.currencySymbol)\(alreadyExchanged). Try again next month."
            )
        }
    }

    private var wishSection: some View {
        Section {
            if myWishes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ChildWishListCopy.emptyTitle(for: loc.language))
                                .font(.headline)
                            Text(ChildWishListCopy.emptyDetail(for: loc.language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        SpeakButton(text: ChildWishListCopy.emptySpeakText(for: loc.language), language: loc.language)
                    }
                }
                .accessibilityIdentifier("wish-empty-child-guide")
            }

            ForEach(myWishes.prefix(10)) { wish in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wish.title)
                            .font(.subheadline)
                        Text(ChildWishListCopy.statusLine(
                            for: wish,
                            availablePoints: store.creditBalance.availableMinutes,
                            language: loc.language
                        ))
                            .font(.caption)
                            .foregroundStyle(wish.status == .fulfilled ? .green : .secondary)
                    }
                    Spacer()
                    SpeakButton(
                        text: ChildWishListCopy.speakText(
                            for: wish,
                            availablePoints: store.creditBalance.availableMinutes,
                            language: loc.language
                        ),
                        language: loc.language
                    )
                    if wish.status == .priced, let price = wish.pricePoints {
                        let missingPoints = max(0, price - store.creditBalance.availableMinutes)
                        Button(
                            store.creditBalance.availableMinutes >= price
                                ? loc.pick("兑换愿望", "Redeem wish")
                                : loc.pick(
                                    "还差 \(GrowthCreditCopy.label(points: missingPoints))",
                                    "\(GrowthCreditCopy.label(points: missingPoints, language: .english)) to go"
                                )
                        ) {
                            if store.redeemWish(wish.id) {
                                wishFeedback = loc.pick("兑换好啦，等大人兑现！", "Redeemed! A grown-up will make it happen!")
                            } else {
                                wishFeedback = loc.pick(
                                    "这次没换成，请大人看看这个愿望。",
                                    "That didn't work. Ask a grown-up to look at this wish."
                                )
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.creditBalance.availableMinutes < price)
                    }
                }
            }
            if aiProvider.isVoiceTranscriptionReady {
                wishVoiceInput
            } else {
                HStack {
                    Button {
                        wishFeedback = wishVoiceGuideText
                    } label: {
                        Label(loc.pick("不会打字？听怎么说愿望", "Can't type yet? Hear how to say a wish"), systemImage: "mic.circle.fill")
                    }
                    Spacer()
                    SpeakButton(text: wishVoiceGuideText, language: loc.language)
                }
                .accessibilityIdentifier("wish-voice-guide")
            }
            HStack {
                TextField(loc.pick("我想要……（可以说出来）", "I want... (you can say it out loud)"), text: $newWishTitle)
                Button(loc.pick("提交", "Send")) {
                    if store.submitWish(title: newWishTitle) != nil {
                        newWishTitle = ""
                        wishFeedback = loc.pick("愿望已经告诉大人啦！", "Your wish was sent to a grown-up!")
                    } else {
                        wishFeedback = loc.pick(
                            "没提交上，请让大人检查家庭成员设置。",
                            "It didn't send. Ask a grown-up to check the family member settings."
                        )
                    }
                }
                .buttonStyle(.borderless)
                .disabled(newWishTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("wish-submit")
            }
        } header: {
            Text(loc.pick("我的愿望清单（可以说出来）", "My Wish List (you can say it out loud)"))
        } footer: {
            if let wishFeedback {
                // 操作结果反馈配手动小喇叭：不识字的孩子点一下就能听到结果，不自动播报。
                HStack(alignment: .top) {
                    Text(wishFeedback)
                    Spacer()
                    SpeakButton(text: wishFeedback, language: loc.language)
                }
                .accessibilityIdentifier("wish-feedback")
            } else {
                Text(ChildWishListCopy.footer(for: loc.language))
            }
        }
    }

    /// 家长配好语音转写时的「直接说愿望」入口：录音 → 转写 → 填入输入框等孩子确认。
    @ViewBuilder
    private var wishVoiceInput: some View {
        switch wishRecorder.state {
        case .idle:
            Button {
                wishRecorder.startRecording()
            } label: {
                HStack {
                    Text("🎤")
                        .font(store.isPreReaderActive ? .largeTitle : .title2)
                    Text(loc.pick("按这里说愿望", "Press here to say a wish"))
                        .font(store.isPreReaderActive ? .headline : .body)
                    Spacer()
                    SpeakButton(
                        text: loc.pick(
                            "按这个按钮，说出你想要的东西。比如：我想要一本恐龙书。",
                            "Press this button and say what you want. For example: I want a dinosaur book."
                        ),
                        language: loc.language
                    )
                }
            }
            .accessibilityIdentifier("wish-voice-start")
        case .denied:
            Label(
                loc.pick(
                    "没有麦克风权限，请大人在系统设置里打开。",
                    "No microphone permission. Ask a grown-up to turn it on in Settings."
                ),
                systemImage: "mic.slash"
            )
                .font(.caption)
                .foregroundStyle(.secondary)
        case .recording:
            Button {
                wishRecorder.stopRecording()
            } label: {
                Label(loc.pick("正在听……说完点这里", "Listening... tap here when you're done"), systemImage: "stop.circle.fill")
                    .foregroundStyle(.red)
            }
            .accessibilityIdentifier("wish-voice-stop")
        case .finished:
            Label(loc.pick("正在整理你的愿望……", "Getting your wish ready..."), systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if isTranscribingWish {
            Label(loc.pick("正在把你的话变成文字……", "Turning your words into text..."), systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("wish-voice-transcribing")
        }
    }
}
