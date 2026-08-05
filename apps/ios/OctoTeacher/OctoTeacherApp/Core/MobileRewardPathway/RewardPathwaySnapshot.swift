import Foundation

enum RewardPathwayViewerRole: String, Equatable, CaseIterable {
    case child
    case guardian
}

enum RewardPathwayOutletKind: String, Equatable, CaseIterable {
    case screenTime
    case pocketMoney
    case wishList
}

/// 出口的只读路由建议：只提示 UI 该把孩子带去哪一页，不触发扣分、解锁或审批。
enum RewardPathwaySuggestedRoute: String, Equatable, CaseIterable {
    /// 成长积分够（或已有进行中会话），去兑换页。
    case redeemScreenTime
    /// 成长积分还不够换屏幕时间，先去今日任务赚成长积分。
    case earnCredits
    /// 零花钱与愿望统一进零花钱中心。
    case pocketMoneyCenter
}

struct RewardPathwaySideEffects: Equatable {
    let writesLedger = false
    let grantsCredit = false
    let spendsCredit = false
    let unlocksDevice = false
    let paysMoney = false
    let fulfillsWish = false
    let callsNetwork = false
    let callsAI = false
}

struct RewardPathwayOutlet: Identifiable, Equatable {
    var kind: RewardPathwayOutletKind
    var title: String
    var childExplanation: String
    var guardianExplanation: String
    var status: String
    var availability: String
    var nextStep: String
    var visibleMetric: String
    var guardrails: [String]
    var speakText: String
    var suggestedRoute: RewardPathwaySuggestedRoute

    var id: RewardPathwayOutletKind { kind }
}

/// 待家长处理项的分项明细：只拆开 pendingGuardianReviewCount 供只读展示，
/// 不携带任何可执行操作。
struct RewardPathwayPendingBreakdown: Equatable {
    /// 孩子已提出、等家长定价的愿望数。
    var pricingWishCount: Int
    /// 孩子已兑换、等家长线下兑现的愿望数。
    var fulfillmentWishCount: Int
    /// 等家长确认的零花钱兑换申请数。
    var pocketMoneyConfirmCount: Int

    var total: Int {
        pricingWishCount + fulfillmentWishCount + pocketMoneyConfirmCount
    }
}

struct RewardPathwayPublicSummary: Equatable {
    var childName: String
    var availableCredits: Int
    var outletCount: Int
    var pendingGuardianReviewCount: Int
    var pendingBreakdown: RewardPathwayPendingBreakdown
    var redeemableWishCount: Int
    var hasActiveScreenSession: Bool
    var sideEffects: RewardPathwaySideEffects
}

struct RewardPathwaySnapshot: Equatable {
    var viewerRole: RewardPathwayViewerRole
    var title: String
    var headline: String
    var outlets: [RewardPathwayOutlet]
    var publicSummary: RewardPathwayPublicSummary
    var safetyNotes: [String]
}

struct RewardPathwayBuilder {
    func build(
        store: LocalFamilyStore,
        screenTime: MockScreenTimeController,
        viewerRole: RewardPathwayViewerRole
    ) -> RewardPathwaySnapshot {
        // 文案语言跟随观看者：孩子视角用当前孩子界面语言，家长视角用家长界面语言。
        let language = viewerRole == .child
            ? store.activeChildInterfaceLanguage
            : store.settings.resolvedParentInterfaceLanguage
        let childId = store.activeChildId
        let child = store.children.first(where: { $0.id == childId }) ?? store.child
        let policy = store.policy(for: childId)
        let credits = max(0, store.creditBalance.availableMinutes)
        let pocket = store.pocketMoneySummary(for: childId)
        let wishes = store.wishes.filter { $0.childId == childId && $0.status != .rejected }
        let proposedWishes = wishes.filter { $0.status == .proposed }
        let redeemedWishes = wishes.filter { $0.status == .redeemed }
        let redeemableWishes = wishes.filter { wish in
            wish.status == .priced && (wish.pricePoints ?? Int.max) <= credits
        }
        let awaitingMoney = store.moneyLedger.filter {
            $0.childId == childId && $0.status == .awaitingApproval
        }
        let pendingBreakdown = RewardPathwayPendingBreakdown(
            pricingWishCount: proposedWishes.count,
            fulfillmentWishCount: redeemedWishes.count,
            pocketMoneyConfirmCount: awaitingMoney.count
        )
        let pendingReviewCount = pendingBreakdown.total
        let hasActiveScreenSession = screenTime.sessionStatus == .active
        let summary = RewardPathwayPublicSummary(
            childName: child.name,
            availableCredits: credits,
            outletCount: RewardPathwayOutletKind.allCases.count,
            pendingGuardianReviewCount: pendingReviewCount,
            pendingBreakdown: pendingBreakdown,
            redeemableWishCount: redeemableWishes.count,
            hasActiveScreenSession: hasActiveScreenSession,
            sideEffects: RewardPathwaySideEffects()
        )
        let outlets = [
            screenTimeOutlet(
                credits: credits,
                policy: policy,
                hasActiveSession: hasActiveScreenSession,
                latestCommandReceipt: screenTime.latestDeviceCommandReceipt,
                language: language
            ),
            pocketMoneyOutlet(
                credits: credits,
                policy: policy,
                pocketSummary: pocket,
                awaitingCount: awaitingMoney.count,
                blocker: store.pocketMoneyExchangeBlocker(
                    points: policy.pointsPerCurrencyUnit,
                    childId: childId
                ),
                language: language
            ),
            wishListOutlet(
                credits: credits,
                wishes: wishes,
                proposedCount: proposedWishes.count,
                redeemedCount: redeemedWishes.count,
                redeemableCount: redeemableWishes.count,
                language: language
            )
        ]

        return RewardPathwaySnapshot(
            viewerRole: viewerRole,
            title: viewerRole == .child
                ? language.pick("我的成长积分可以做什么", "What my Growth Points can do")
                : language.pick("奖励出口总览", "Reward Outlets Overview"),
            headline: headline(for: viewerRole, childName: child.name, credits: credits, pendingReviewCount: pendingReviewCount, language: language),
            outlets: outlets,
            publicSummary: summary,
            safetyNotes: safetyNotes(for: viewerRole, language: language)
        )
    }

    private func screenTimeOutlet(
        credits: Int,
        policy: FamilyExchangePolicy,
        hasActiveSession: Bool,
        latestCommandReceipt: ScreenTimeDeviceCommandReceipt?,
        language: AppInterfaceLanguage
    ) -> RewardPathwayOutlet {
        let pointsForFifteen = policy.screenPointsRequired(forMinutes: 15)
        let canRedeem = credits >= pointsForFifteen
        let lastDeviceFailed = latestCommandReceipt?.kind == .startUnlock && latestCommandReceipt?.status == .failed
        let status = hasActiveSession
            ? language.pick("正在使用", "In use")
            : (lastDeviceFailed
                ? language.pick("上次设备未打开", "Device didn't open last time")
                : (canRedeem
                    ? language.pick("可以兑换", "Ready to redeem")
                    : language.pick("先去赚成长积分", "Earn Growth Points first")))
        let nextStep = hasActiveSession
            ? language.pick("看看还剩多少时间", "See how much time is left")
            : (canRedeem
                ? language.pick("申请一次屏幕时间", "Request one screen time session")
                : language.pick("先完成阅读、家务或运动任务", "Finish a reading, chore, or exercise task first"))
        let guardrails = [
            language.pick("只读展示", "Read-only view"),
            language.pick("兑换时再扣成长积分", "Points are deducted only at redemption"),
            language.pick("设备失败会退回成长积分", "Points are refunded on device failure"),
            language.pick("真正解锁由屏幕时间会话处理", "Real unlocking happens in the screen time session")
        ]
        return RewardPathwayOutlet(
            kind: .screenTime,
            title: language.pick("屏幕时间", "Screen Time"),
            childExplanation: language.pick(
                "成长积分够了，可以换一点娱乐时间。",
                "When you have enough Growth Points, trade some for fun time."
            ),
            guardianExplanation: language.pick(
                "沿用屏幕时间汇率、本机会话和设备执行回执；本快照只展示，不下发设备命令。",
                "Uses the screen time rate, local sessions, and device receipts; this snapshot displays only and sends no device commands."
            ),
            status: status,
            availability: canRedeem
                ? language.pick("够兑换一次屏幕时间", "Enough for one screen time session")
                : language.pick(
                    "还差 \(GrowthCreditCopy.label(points: max(0, pointsForFifteen - credits)))",
                    "\(GrowthCreditCopy.label(points: max(0, pointsForFifteen - credits), language: .english)) to go"
                ),
            nextStep: nextStep,
            visibleMetric: policy.screenRateLabel,
            guardrails: guardrails,
            speakText: lastDeviceFailed
                ? language.pick(
                    "上次设备没有打开成功，成长积分已经保护。可以请大人检查授权后再试。",
                    "The device didn't open last time and your Growth Points are protected. Ask a grown-up to check the permission and try again."
                )
                : language.pick(
                    "成长积分可以兑换屏幕时间。成长积分不够时，先完成任务再回来看看。",
                    "Growth Points can buy screen time. If you don't have enough yet, finish some tasks and come back."
                ),
            suggestedRoute: (hasActiveSession || canRedeem) ? .redeemScreenTime : .earnCredits
        )
    }

    private func pocketMoneyOutlet(
        credits: Int,
        policy: FamilyExchangePolicy,
        pocketSummary: (pendingPayout: Int, paidTotal: Int, thisMonthExchanged: Int),
        awaitingCount: Int,
        blocker: LocalFamilyStore.PocketMoneyExchangeBlocker?,
        language: AppInterfaceLanguage
    ) -> RewardPathwayOutlet {
        let minimumPoints = policy.pointsPerCurrencyUnit
        let approvalText = policy.pocketMoneyRequiresApproval
            ? language.pick("需要大人确认", "Needs a grown-up's check")
            : language.pick("确认后待发放", "Pending payout after check")
        let status: String
        let nextStep: String
        switch blocker {
        case nil:
            status = approvalText
            nextStep = language.pick("提交兑换申请", "Submit an exchange request")
        case .belowMinimum(let requiredPoints):
            status = language.pick("成长积分还不够", "Not enough Growth Points yet")
            nextStep = language.pick(
                "先攒到 \(GrowthCreditCopy.label(points: requiredPoints))",
                "Save up to \(GrowthCreditCopy.label(points: requiredPoints, language: .english)) first"
            )
        case .insufficientCredits(let requiredPoints, let availablePoints):
            status = language.pick("成长积分还不够", "Not enough Growth Points yet")
            nextStep = language.pick(
                "再攒 \(GrowthCreditCopy.label(points: max(0, requiredPoints - availablePoints)))",
                "Earn \(GrowthCreditCopy.label(points: max(0, requiredPoints - availablePoints), language: .english)) more"
            )
        case .monthlyCapReached:
            status = language.pick("本月到上限", "Monthly cap reached")
            nextStep = language.pick("下个月再换零花钱", "Exchange pocket money next month")
        case .unknownChild:
            status = language.pick("暂时不能兑换", "Exchange unavailable right now")
            nextStep = language.pick("请大人检查家庭设置", "Ask a grown-up to check family settings")
        }
        return RewardPathwayOutlet(
            kind: .pocketMoney,
            title: language.pick("零花钱", "Pocket Money"),
            childExplanation: language.pick(
                "成长积分可以换成零花钱，等大人确认。",
                "Growth Points can become pocket money after a grown-up checks."
            ),
            guardianExplanation: language.pick(
                "App 只做家庭账本与待发放清单，不接入支付；真实给钱仍由家长线下完成。",
                "The app only keeps the family ledger and payout list, with no payment integration; real money is handed over offline by parents."
            ),
            status: status,
            availability: language.pick(
                "\(GrowthCreditCopy.label(points: minimumPoints)) = \(policy.currencySymbol)1",
                "\(GrowthCreditCopy.label(points: minimumPoints, language: .english)) = \(policy.currencySymbol)1"
            ),
            nextStep: nextStep,
            visibleMetric: language.pick(
                "待发放 \(policy.currencySymbol)\(pocketSummary.pendingPayout) · 本月已换 \(policy.currencySymbol)\(pocketSummary.thisMonthExchanged)",
                "Pending \(policy.currencySymbol)\(pocketSummary.pendingPayout) · Exchanged this month \(policy.currencySymbol)\(pocketSummary.thisMonthExchanged)"
            ),
            guardrails: [
                language.pick("只读展示", "Read-only view"),
                language.pick("申请兑换时才扣成长积分", "Points are deducted only when requesting"),
                language.pick("家长线下兑现", "Parents pay offline"),
                language.pick("待家长确认 \(awaitingCount) 条", "\(awaitingCount) awaiting parent check")
            ],
            speakText: language.pick(
                "成长积分也能申请换零花钱。提交后，大人会确认，再线下给你。",
                "Growth Points can also become pocket money. After you submit, a grown-up checks and then pays you in person."
            ),
            suggestedRoute: .pocketMoneyCenter
        )
    }

    private func wishListOutlet(
        credits: Int,
        wishes: [WishListItem],
        proposedCount: Int,
        redeemedCount: Int,
        redeemableCount: Int,
        language: AppInterfaceLanguage
    ) -> RewardPathwayOutlet {
        let pricedWishes = wishes.filter { $0.status == .priced }
        let cheapest = pricedWishes.compactMap(\.pricePoints).min()
        let status: String
        let nextStep: String
        if redeemableCount > 0 {
            status = language.pick("有愿望可以兑换", "A wish is ready to redeem")
            nextStep = language.pick("挑一个愿望兑换", "Pick a wish to redeem")
        } else if proposedCount > 0 {
            status = language.pick("等大人定价", "Waiting for a grown-up to price it")
            nextStep = language.pick("等大人看看愿望", "Wait for a grown-up to review the wish")
        } else if let cheapest {
            status = language.pick("继续攒成长积分", "Keep earning Growth Points")
            nextStep = language.pick(
                "再攒 \(GrowthCreditCopy.label(points: max(0, cheapest - credits)))",
                "Earn \(GrowthCreditCopy.label(points: max(0, cheapest - credits), language: .english)) more"
            )
        } else {
            status = language.pick("可以许愿", "Ready for a wish")
            nextStep = language.pick("写下或说出一个愿望", "Write or say a wish")
        }
        return RewardPathwayOutlet(
            kind: .wishList,
            title: language.pick("愿望清单", "Wish List"),
            childExplanation: language.pick(
                "把想要的东西放进愿望清单。",
                "Put the things you want on your wish list."
            ),
            guardianExplanation: language.pick(
                "愿望由孩子提出，家长定成长积分价格并线下兑现；本快照不扣分、不兑现。",
                "Children propose wishes; parents price them in Growth Points and fulfill them offline. This snapshot never deducts points or fulfills wishes."
            ),
            status: status,
            availability: cheapest.map {
                language.pick(
                    "最低 \(GrowthCreditCopy.label(points: $0))",
                    "From \(GrowthCreditCopy.label(points: $0, language: .english))"
                )
            } ?? language.pick("还没有定价愿望", "No priced wishes yet"),
            nextStep: nextStep,
            visibleMetric: language.pick(
                "可兑换 \(redeemableCount) · 待定价 \(proposedCount) · 待兑现 \(redeemedCount)",
                "Redeemable \(redeemableCount) · Awaiting price \(proposedCount) · Awaiting fulfillment \(redeemedCount)"
            ),
            guardrails: [
                language.pick("只读展示", "Read-only view"),
                language.pick("孩子可语音提愿望", "Children can speak their wishes"),
                language.pick("家长定价后才能兑换", "Redeemable only after parents set a price"),
                language.pick("兑换后等家长兑现", "Parents fulfill after redemption")
            ],
            speakText: language.pick(
                "你可以把想要的东西放进愿望清单。大人定好成长积分后，就能努力兑换。",
                "You can put things you want on the wish list. Once a grown-up sets the Growth Point price, you can work toward it."
            ),
            suggestedRoute: .pocketMoneyCenter
        )
    }

    private func headline(
        for role: RewardPathwayViewerRole,
        childName: String,
        credits: Int,
        pendingReviewCount: Int,
        language: AppInterfaceLanguage
    ) -> String {
        switch role {
        case .child:
            return language.pick(
                "\(childName) 现在有 \(credits) 成长积分，可以看看想换什么。",
                "\(childName) has \(credits) Growth Points — take a look at what to trade them for."
            )
        case .guardian:
            return language.pick(
                "\(childName) 有 \(credits) 成长积分，\(pendingReviewCount) 个奖励项等家长处理。",
                "\(childName) has \(credits) Growth Points; \(pendingReviewCount) reward items await a parent."
            )
        }
    }

    private func safetyNotes(
        for role: RewardPathwayViewerRole,
        language: AppInterfaceLanguage
    ) -> [String] {
        switch role {
        case .child:
            return [
                language.pick("这里先帮你看选择，不会偷偷扣成长积分。", "This page only shows your choices; it never secretly spends Growth Points."),
                language.pick("真正兑换前会让你确认。", "You always confirm before a real redemption.")
            ]
        case .guardian:
            return [
                language.pick("本快照只读，不写账本、不扣成长积分、不解锁设备。", "This snapshot is read-only: no ledger writes, no point deductions, no device unlocking."),
                language.pick("零花钱与愿望都由家长线下兑现。", "Pocket money and wishes are fulfilled offline by parents.")
            ]
        }
    }
}
