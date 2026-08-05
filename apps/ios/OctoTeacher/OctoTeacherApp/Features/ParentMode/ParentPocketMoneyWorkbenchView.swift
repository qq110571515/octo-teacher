import SwiftUI

enum ParentWishListCopy {
    static func isInProgress(_ wish: WishListItem) -> Bool {
        wish.status != .rejected && wish.status != .fulfilled
    }

    static func statusLine(for wish: WishListItem, availablePoints: Int? = nil) -> String {
        switch wish.status {
        case .proposed:
            return "现在需要你定成长积分价格；定价后孩子端才会显示还差多少。"
        case .priced:
            let price = wish.pricePoints ?? 0
            let priceText = GrowthCreditCopy.label(points: price)
            guard let availablePoints else {
                return "已定价 \(priceText)；孩子端会显示还差多少。"
            }
            let missingPoints = max(0, price - availablePoints)
            if missingPoints == 0 {
                return "已定价 \(priceText)；孩子现在积分够，可以在孩子端兑换。"
            }
            return "已定价 \(priceText)；孩子当前还差 \(GrowthCreditCopy.label(points: missingPoints))。"
        case .redeemed:
            let price = wish.pricePoints ?? 0
            return "孩子已用 \(GrowthCreditCopy.label(points: price)) 兑换，等你线下兑现。"
        case .fulfilled:
            return "愿望已实现。"
        case .rejected:
            return "已驳回。"
        }
    }

    static func nextStepLine(for wish: WishListItem, availablePoints: Int? = nil) -> String {
        switch wish.status {
        case .proposed:
            return "先定一个孩子能理解的成长积分价格；定价前孩子不能兑换。"
        case .priced:
            let price = wish.pricePoints ?? 0
            guard let availablePoints else {
                return "孩子端会按当前成长积分显示差额；本页不扣分、不兑现。"
            }
            let missingPoints = max(0, price - availablePoints)
            if missingPoints == 0 {
                return "提醒孩子到孩子端点「兑换愿望」；兑换后你再线下兑现。"
            }
            return "继续引导孩子完成任务攒成长积分，还差 \(GrowthCreditCopy.label(points: missingPoints))。"
        case .redeemed:
            return "把实物、活动或特权兑现给孩子后，点「已兑现」完成闭环。"
        case .fulfilled:
            return "这个愿望已经闭环。"
        case .rejected:
            return "这个愿望已经结束。"
        }
    }
}

/// 家长端零花钱工作台：批兑换申请、划账发放、手动调整、看流水。
/// App 只记账，真实现金/转账由家长线下完成。
struct ParentPocketMoneyWorkbenchView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(MockScreenTimeController.self) private var screenTimeController

    @State private var adjustAmount = 5
    @State private var adjustNote = ""
    @State private var feedback: String?

    /// 家长视角的奖励出口快照：只读展示，不替代下方审批/发放按钮。
    private var pathwaySnapshot: RewardPathwaySnapshot {
        RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTimeController,
            viewerRole: .guardian
        )
    }

    private var awaiting: [MoneyLedgerEntry] {
        store.moneyLedger.filter { $0.status == .awaitingApproval }
    }
    private var pendingPayout: [MoneyLedgerEntry] {
        store.moneyLedger.filter { $0.status == .pendingPayout }
    }

    @State private var wishPrices: [UUID: Int] = [:]

    var body: some View {
        List {
            pathwaySection(pathwaySnapshot)
            summarySection
            wishSection
            awaitingSection
            payoutSection
            adjustSection
            ledgerSection
        }
        .navigationTitle("零花钱工作台")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 奖励出口总览：只读展示屏幕时间/零花钱/愿望清单三条出口与待处理项，
    /// 家长只看 guardianExplanation，不显示 childExplanation，也不提供任何可执行按钮。
    private func pathwaySection(_ snapshot: RewardPathwaySnapshot) -> some View {
        Section {
            pendingBreakdownRow(snapshot.publicSummary.pendingBreakdown)
            ForEach(snapshot.outlets) { outlet in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(outlet.title)
                            .font(.subheadline.weight(.semibold))
                        Text(outlet.status)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .accessibilityIdentifier("parent-pocket-pathway-status-\(outlet.kind.rawValue)")
                    }
                    Text(outlet.visibleMetric)
                        .font(.caption)
                        .accessibilityIdentifier("parent-pocket-pathway-metric-\(outlet.kind.rawValue)")
                    Text("下一步：\(outlet.nextStep)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(outlet.guardianExplanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("parent-pocket-pathway-\(outlet.kind.rawValue)")
            }
        } header: {
            Text("奖励出口总览")
        } footer: {
            Text("\(snapshot.headline)\n零花钱和愿望由家长线下兑现，屏幕时间由既有兑换会话处理；本页只读，不接任何支付。真正的审批和发放请用下方按钮。")
        }
    }

    /// 待处理分项：只读文案，告诉家长具体该做什么；真正处理仍走下方既有列表。
    private func pendingBreakdownRow(_ breakdown: RewardPathwayPendingBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("待处理 \(breakdown.total) 项")
                .font(.subheadline.weight(.semibold))
            if breakdown.total == 0 {
                Text("暂时没有等你处理的奖励项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("待定价愿望 \(breakdown.pricingWishCount) · 待兑现愿望 \(breakdown.fulfillmentWishCount) · 待确认零花钱 \(breakdown.pocketMoneyConfirmCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("parent-pocket-pathway-pending-breakdown")
                Text("在下方「愿望清单」「等待确认」列表里处理。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var summarySection: some View {
        Section("每个孩子 · 本月总览") {
            ForEach(store.children) { member in
                let policy = store.policy(for: member.id)
                let summary = store.pocketMoneySummary(for: member.id)
                let monthly = store.monthlySpendingSummary(for: member.id)
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name)
                        .font(.headline)
                    Text("\(GrowthCreditCopy.label(points: member.rewardBalanceMinutes)) · 待发放 \(policy.currencySymbol)\(summary.pendingPayout) · 已发放 \(policy.currencySymbol)\(summary.paidTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("本月：成长积分兑换 \(policy.currencySymbol)\(monthly.exchangedMoney) · 基础零花钱 \(policy.currencySymbol)\(monthly.baseAllowance) · 调整 \(policy.currencySymbol)\(monthly.adjustments) · 愿望消费 \(GrowthCreditCopy.label(points: monthly.wishPointsSpent))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("底薪 \(policy.currencySymbol)\(policy.baseMonthlyAllowance)/\(policy.resolvedCycle.label) · \(GrowthCreditCopy.label(points: policy.pointsPerCurrencyUnit))=\(policy.currencySymbol)1 · \(policy.screenRateLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var openWishes: [WishListItem] {
        store.wishes.filter { ParentWishListCopy.isInProgress($0) }
    }

    private func availableGrowthCredits(for childId: UUID) -> Int? {
        guard store.children.contains(where: { $0.id == childId }) else { return nil }
        return store.creditBalance(for: childId).availableMinutes
    }

    private var wishSection: some View {
        Section {
            if openWishes.isEmpty {
                Text("没有待处理的愿望。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(openWishes) { wish in
                    let availablePoints = availableGrowthCredits(for: wish.childId)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(store.childName(for: wish.childId))：\(wish.title)")
                            .font(.subheadline)
                        Text(ParentWishListCopy.statusLine(for: wish, availablePoints: availablePoints))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(ParentWishListCopy.nextStepLine(for: wish, availablePoints: availablePoints))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if wish.status == .proposed {
                            HStack {
                                Stepper(
                                    "定价 \(GrowthCreditCopy.label(points: wishPrices[wish.id] ?? 50))",
                                    value: Binding(
                                        get: { wishPrices[wish.id] ?? 50 },
                                        set: { wishPrices[wish.id] = $0 }
                                    ),
                                    in: 1...1_000_000,
                                    step: 1
                                )
                                .font(.caption)
                            }
                            HStack {
                                Button("定价") {
                                    _ = store.priceWish(wish.id, points: wishPrices[wish.id] ?? 50)
                                }
                                .buttonStyle(.borderedProminent)
                                Button("驳回") {
                                    _ = store.rejectWish(wish.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        } else if wish.status == .priced {
                            HStack {
                                Text("孩子端会显示价格、当前差额和兑换按钮；本页不扣分、不兑现。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("驳回") {
                                    _ = store.rejectWish(wish.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        } else if wish.status == .redeemed {
                            HStack {
                                Text("孩子已用 \(GrowthCreditCopy.label(points: wish.pricePoints ?? 0)) 兑换")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("已兑现") {
                                    _ = store.markWishFulfilled(wish.id)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("愿望清单（\(openWishes.count) 个进行中）")
        } footer: {
            Text("孩子提愿望 → 你定成长积分价格 → 孩子端显示还差多少 → 孩子攒够积分后兑换 → 你兑现后点「已兑现」。")
        }
    }

    private var awaitingSection: some View {
        Section {
            if awaiting.isEmpty {
                Text("没有等待确认的兑换申请。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(awaiting) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(store.childName(for: entry.childId))：\(entry.note) → \(store.policy(for: entry.childId).currencySymbol)\(entry.amount)")
                            .font(.subheadline)
                        HStack {
                            Button("批准") {
                                _ = store.approvePocketMoney(entry.id)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("pocket-money-approve-\(entry.id)")
                            Button("驳回并退回成长积分") {
                                _ = store.rejectPocketMoney(entry.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        } header: {
            Text("等待确认（\(awaiting.count)）")
        }
    }

    private var payoutSection: some View {
        Section {
            if pendingPayout.isEmpty {
                Text("没有待发放的零花钱。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pendingPayout) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(store.childName(for: entry.childId)) · \(entry.kind.label)")
                                .font(.subheadline)
                            Text(entry.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(store.policy(for: entry.childId).currencySymbol)\(entry.amount)")
                            .font(.subheadline.weight(.semibold))
                        Button("已给") {
                            _ = store.markPocketMoneyPaid(entry.id)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("pocket-money-paid-\(entry.id)")
                    }
                }
            }
        } header: {
            Text("待发放（\(pendingPayout.count)）")
        } footer: {
            Text("把现金/转账给孩子后点「已给」划账；App 不接任何真实支付。")
        }
    }

    private var adjustSection: some View {
        Section {
            Stepper("金额：\(adjustAmount >= 0 ? "+" : "")\(adjustAmount)", value: $adjustAmount, in: -100...100, step: 5)
            TextField("原因（必填，例如：主动帮忙搬东西）", text: $adjustNote)
            Button("给\(store.child.name)记一笔") {
                if store.adjustPocketMoney(childId: store.activeChildId, amount: adjustAmount, note: adjustNote) != nil {
                    feedback = "已记账。"
                    adjustNote = ""
                } else {
                    feedback = "失败：金额不能为 0，原因必填。"
                }
            }
            .disabled(adjustNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || adjustAmount == 0)
        } header: {
            Text("手动调整（当前：\(store.child.name)）")
        } footer: {
            if let feedback {
                Text(feedback)
            }
        }
    }

    private var ledgerSection: some View {
        Section("最近流水") {
            ForEach(store.moneyLedger.prefix(15)) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(store.childName(for: entry.childId)) · \(entry.kind.label)")
                            .font(.caption)
                        Text(entry.note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(entry.amount >= 0 ? "+" : "")\(store.policy(for: entry.childId).currencySymbol)\(entry.amount) · \(entry.status.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
