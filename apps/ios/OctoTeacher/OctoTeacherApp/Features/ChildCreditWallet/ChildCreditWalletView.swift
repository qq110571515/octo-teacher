import Foundation
import SwiftUI

/// 孩子端成长积分钱包与娱乐申请中心。
///
/// 本页只读汇总成长积分、今日任务包收益、娱乐会话状态与离线请求；真正兑换或离线请求
/// 仍进入既有 RewardRedemptionView，不在钱包页直接扣成长积分或解锁设备。
struct ChildCreditWalletView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(MockScreenTimeController.self) private var screenTimeController
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox
    @State private var showsDetails = false

    private let builder = MobileChildCreditWalletBuilder()

    init() {
        #if DEBUG
        _showsDetails = State(initialValue: ProcessInfo.processInfo.arguments.contains {
            $0.hasPrefix("-OctoTeacherUITest")
        })
        #endif
    }

    private var wallet: MobileChildCreditWallet {
        builder.build(
            store: store,
            screenTime: screenTimeController,
            offlineStatus: offlineOutbox.publicStatus
        )
    }

    private var pathwaySnapshot: RewardPathwaySnapshot {
        RewardPathwayBuilder().build(
            store: store,
            screenTime: screenTimeController,
            viewerRole: .child
        )
    }

    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                walletHero(wallet)
                rewardTiles(pathwaySnapshot)
                sessionBanner(wallet)
                nextActions(wallet)
                detailsPanel(wallet)
            }
            .padding(16)
        }
        .background(Color.secondary.opacity(0.06))
        .navigationTitle(loc.pick("我的奖励", "My Rewards"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func walletHero(_ wallet: MobileChildCreditWallet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.pick("我有", "I have"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(GrowthCreditCopy.label(points: wallet.balance.availableMinutes, language: loc.language))
                        .font(.system(.largeTitle, design: .rounded).bold())
                        .monospacedDigit()
                        .accessibilityIdentifier("child-credit-wallet-balance")
                }
                Spacer()
                Image(systemName: "leaf.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 14) {
                Label(
                    loc.pick(
                        "今天可赚 \(wallet.balance.todayPackageRewardMinutes) 分",
                        "\(wallet.balance.todayPackageRewardMinutes) points available today"
                    ),
                    systemImage: "sparkles"
                )
                .accessibilityIdentifier("child-credit-wallet-metric-today-package")
                if wallet.balance.pendingMinutes > 0 {
                    Label(
                        loc.pick(
                            "\(wallet.balance.pendingMinutes) 分等确认",
                            "\(wallet.balance.pendingMinutes) waiting"
                        ),
                        systemImage: "hourglass"
                    )
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.18), Color.teal.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    private func rewardTiles(_ snapshot: RewardPathwaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.pick("我想……", "I want to…"))
                .font(.title3.bold())

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(snapshot.outlets) { outlet in
                    NavigationLink {
                        pathwayDestination(for: outlet)
                    } label: {
                        rewardTile(outlet)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("child-credit-wallet-pathway-\(outlet.kind.rawValue)")
                }
            }
        }
    }

    private func rewardTile(_ outlet: RewardPathwayOutlet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: pathwayIcon(for: outlet.kind))
                .font(.title2.bold())
                .foregroundStyle(tileTint(for: outlet.kind))
            Text(childTitle(for: outlet.kind))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(childHint(for: outlet.kind))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(outlet.status)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tileTint(for: outlet.kind))
                .lineLimit(1)
                .accessibilityIdentifier("child-credit-wallet-pathway-status-\(outlet.kind.rawValue)")
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(14)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(14)
        }
    }

    private func childTitle(for kind: RewardPathwayOutletKind) -> String {
        switch kind {
        case .screenTime: return loc.pick("玩一会儿", "Play Time")
        case .pocketMoney: return loc.pick("换零花钱", "Pocket Money")
        case .wishList: return loc.pick("许个愿望", "Make a Wish")
        }
    }

    private func childHint(for kind: RewardPathwayOutletKind) -> String {
        switch kind {
        case .screenTime: return loc.pick("选 App 和时间", "Choose an app and time")
        case .pocketMoney: return loc.pick("交给大人确认", "A grown-up checks it")
        case .wishList: return loc.pick("记下想要的东西", "Save something you want")
        }
    }

    private func tileTint(for kind: RewardPathwayOutletKind) -> Color {
        switch kind {
        case .screenTime: return .blue
        case .pocketMoney: return .green
        case .wishList: return .pink
        }
    }

    @ViewBuilder
    private func sessionBanner(_ wallet: MobileChildCreditWallet) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(
                    wallet.session.state == .active
                        ? loc.pick("正在玩", "Play Time Active")
                        : loc.pick("现在没有计时", "No Timer Running"),
                    systemImage: wallet.session.state.systemImage
                )
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("child-credit-wallet-session-\(wallet.session.state.rawValue)")
                Spacer()
                if wallet.session.state == .active {
                    Text(loc.pick(
                        "\(wallet.session.remainingSeconds / 60):\(String(format: "%02d", wallet.session.remainingSeconds % 60))",
                        "\(wallet.session.remainingSeconds / 60):\(String(format: "%02d", wallet.session.remainingSeconds % 60))"
                    ))
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("child-credit-wallet-session-remaining")
                }
            }
            Text(wallet.session.latestReceiptSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("child-credit-wallet-session-receipt")
        }
        .padding(14)
        .background(Color.blue.opacity(wallet.session.state == .active ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func nextActions(_ wallet: MobileChildCreditWallet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc.pick("下一步", "Next"))
                .font(.title3.bold())
            ForEach(wallet.actions) { action in
                Group {
                    if action.kind == .openRedemption || action.kind == .viewStatus {
                        NavigationLink { destination(for: action.kind) } label: { simpleActionLabel(action) }
                    } else if action.kind == .viewSync {
                        NavigationLink { MobileOfflineSyncReviewView(perspective: .child) } label: { simpleActionLabel(action) }
                    } else {
                        simpleActionLabel(action)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("child-credit-wallet-action-\(action.kind.rawValue)")
            }
        }
    }

    private func simpleActionLabel(_ action: MobileChildCreditWalletAction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: action.systemImage)
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
            Text(action.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if action.kind == .openRedemption || action.kind == .viewStatus || action.kind == .viewSync {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detailsPanel(_ wallet: MobileChildCreditWallet) -> some View {
        DisclosureGroup(isExpanded: $showsDetails) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(wallet.findings) { finding in
                    Label(finding.message, systemImage: icon(for: finding.severity))
                        .font(.caption)
                        .foregroundStyle(color(for: finding.severity))
                        .accessibilityIdentifier("child-credit-wallet-finding-\(finding.code.rawValue)")
                }
                if wallet.offlineHint.hasPending {
                    Label(wallet.offlineHint.message, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("child-credit-wallet-offline-hint")
                }
            }
            .padding(.top, 10)
        } label: {
            Label(loc.pick("需要帮助？", "Need Help?"), systemImage: "questionmark.circle")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 4)
    }

    /// 按快照给出的只读路由建议分流：积分不够换屏幕时间时，先带孩子去今日任务赚积分，
    /// 不再进兑换页死路；积分够或已有进行中会话仍走既有兑换页。
    @ViewBuilder
    private func pathwayDestination(for outlet: RewardPathwayOutlet) -> some View {
        // 紧急 30 分钟申请不消耗成长积分，不能因为普通兑换余额不足而被隐藏。
        if outlet.kind == .screenTime {
            RewardRedemptionView()
        } else {
            switch outlet.suggestedRoute {
            case .redeemScreenTime:
                RewardRedemptionView()
            case .earnCredits:
                ChildEarnCreditsView()
            case .pocketMoneyCenter:
                ChildPocketMoneyView()
            }
        }
    }

    private func pathwayIcon(for kind: RewardPathwayOutletKind) -> String {
        switch kind {
        case .screenTime: return "tv"
        case .pocketMoney: return "banknote"
        case .wishList: return "star"
        }
    }

    @ViewBuilder
    private func destination(for kind: MobileChildCreditWalletActionKind) -> some View {
        switch kind {
        case .viewStatus:
            RewardStatusView()
        default:
            RewardRedemptionView()
        }
    }

    private func icon(for severity: MobileChildCreditWalletSeverity) -> String {
        switch severity {
        case .ok: return "checkmark.seal"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .blocker: return "xmark.octagon"
        }
    }

    private func color(for severity: MobileChildCreditWalletSeverity) -> Color {
        switch severity {
        case .ok: return .green
        case .info: return .secondary
        case .warning: return .orange
        case .blocker: return .red
        }
    }
}

/// 积分不够换屏幕时间时的「去赚积分」落地页：只读列出今日任务里现在能做的任务，
/// 点任务进入既有 TaskDetailView；本页不扣分、不发分、不解锁设备。
private struct ChildEarnCreditsView: View {
    @Environment(LocalFamilyStore.self) private var store
    @Environment(\.childSurfaceLanguage) private var childSurfaceLanguage
    @Environment(MobileOfflineOutboxStore.self) private var offlineOutbox

    private let builder = MobileTodayTaskPackageWorkbenchBuilder()

    private var loc: ChildLocalizationContext {
        ChildLocalizationContext(language: childSurfaceLanguage)
    }

    var body: some View {
        let workbench = builder.build(
            store: store,
            offlineStatus: offlineOutbox.publicStatus
        )
        let rows = taskRows(for: workbench)
        let doableRows = rows.filter { $0.card.state == .active || $0.card.state == .redo }

        List {
            Section {
                if !doableRows.isEmpty {
                    ForEach(doableRows) { row in
                        NavigationLink {
                            TaskDetailView(assignment: row.assignment)
                        } label: {
                            taskLabel(row)
                        }
                        .accessibilityIdentifier("child-earn-credits-task-\(row.card.publicTaskRef)")
                    }
                } else if rows.contains(where: { $0.card.state == .waitingCheck }) {
                    Label(
                        loc.pick("你已经提交啦，等大人确认后就能拿到成长积分。", "You handed it in — Growth Points arrive after a grown-up's check."),
                        systemImage: "hourglass"
                    )
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("child-earn-credits-waiting")
                } else {
                    Label(
                        loc.pick("今天还没有可以做的任务，等大人布置后再来。", "No tasks to do yet today — come back after a grown-up assigns some."),
                        systemImage: "moon.stars"
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("child-earn-credits-empty")
                }
            } header: {
                Text(loc.pick("先做任务，攒够成长积分再来换", "Do tasks first, then come back with enough Growth Points"))
            } footer: {
                Text(loc.pick(
                    "做完任务、大人确认后，成长积分会自动到账，再回钱包就能换屏幕时间。",
                    "After tasks are done and checked, Growth Points arrive automatically; return to the wallet to trade for screen time."
                ))
            }
        }
        .navigationTitle(loc.pick("去赚成长积分", "Earn Growth Points"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func taskLabel(_ row: TodayTaskPackageRow) -> some View {
        HStack(spacing: 10) {
            Text(TaskIconProvider.emoji(for: row.assignment.task))
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.card.title)
                        .font(.subheadline.weight(.semibold))
                    Text(row.card.state.label(for: loc.language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(row.card.state == .redo ? Color.red : Color.blue)
                }
                Text(loc.pick(
                    "做完可以获得 \(GrowthCreditCopy.label(points: row.card.rewardMinutes))",
                    "Finish it to earn \(GrowthCreditCopy.label(points: row.card.rewardMinutes, language: .english))"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            SpeakButton(text: loc.pick(
                "任务：\(row.card.title)，做完可以获得 \(GrowthCreditCopy.label(points: row.card.rewardMinutes))。",
                "Task: \(row.card.title). Finish it to earn \(GrowthCreditCopy.label(points: row.card.rewardMinutes, language: .english))."
            ))
        }
        .padding(.vertical, 4)
    }

    private func taskRows(for workbench: MobileTodayTaskPackageWorkbench) -> [TodayTaskPackageRow] {
        let orderedSteps = store.steps(for: store.activeChildId).sorted { $0.order < $1.order }
        return orderedSteps.compactMap { step in
            guard
                let assignment = store.assignment(for: step),
                let card = workbench.cards.first(where: { $0.order == step.order })
            else { return nil }
            return TodayTaskPackageRow(card: card, assignment: assignment)
        }
    }
}
