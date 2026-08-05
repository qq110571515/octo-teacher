import Foundation
import Observation

/// 成长积分结算建议装配器：把本地各 mock 数据源投影成结算建议输入草稿。
///
/// 这是 B28 桥接在 iOS 的「输入侧」：纯逻辑、确定性。它消费
/// `MobileOfflineReplayReport`、`LocalFamilyStore`、`SchoolFamilyStore`、`MockScreenTimeController`，
/// 产出 `MobileCreditSettlementProposalInput`，交给 `MobileCreditSettlementEngine` 裁决。
///
/// 装配器**只读**这些数据源，绝不调用任何会发成长积分/解锁设备/改作业终态的写方法。
/// 由于部分来源没有内在成长积分金额（亲友鼓励、学校作业），这里使用脱敏「建议积分」常量，
/// 仅作展示，最终是否发放仍由家长流程与真实账本决定。
struct MobileCreditSettlementAssembler {

    /// 本地账户脱敏 seed：保证装配出的建议都匹配同一账户（不制造假的跨账户不匹配）。
    static let accountChildSeed = "settlement-account-child"
    static let accountFamilySeed = "settlement-account-family"

    var account: MobileCreditSettlementAccount {
        MobileCreditSettlementAccount(childSeed: Self.accountChildSeed, familySeed: Self.accountFamilySeed)
    }

    func makeInputs(
        offlineReport: MobileOfflineReplayReport,
        family: LocalFamilyStore,
        schoolFamily: SchoolFamilyStore,
        screenTime: MockScreenTimeController
    ) -> [MobileCreditSettlementProposalInput] {
        var inputs: [MobileCreditSettlementProposalInput] = []
        inputs.append(contentsOf: offlineInputs(offlineReport))
        inputs.append(contentsOf: assignmentInputs(family))
        inputs.append(contentsOf: homeworkInputs(schoolFamily))
        inputs.append(contentsOf: deviceInputs(screenTime))
        return inputs
    }

    // MARK: - 离线重放结果 → 结算建议

    private func offlineInputs(_ report: MobileOfflineReplayReport) -> [MobileCreditSettlementProposalInput] {
        report.results.compactMap { result in
            guard let mapped = Self.kindAndSource(for: result.kind) else { return nil }
            let probe = [result.message, result.nextStep, result.kindLabel, result.actorLabel]
            return MobileCreditSettlementProposalInput(
                proposalSeed: result.clientMutationRef,
                kind: mapped.kind,
                source: mapped.source,
                childSeed: Self.accountChildSeed,
                familySeed: Self.accountFamilySeed,
                amount: Self.suggestedAmount(for: result.kind),
                scopeLabel: "需家长批准",
                idempotencyKey: result.clientMutationRef,
                actorRole: Self.actorRole(for: result.actorRole),
                relatedHoldPresent: true,
                offlineReplayed: result.status == .conflict && result.conflictReason == .duplicateReplay,
                offlineConflict: result.status == .conflict && result.conflictReason != .duplicateReplay,
                offlineRolledBack: result.status == .rolledBack,
                redactionProbe: probe
            )
        }
    }

    /// 离线动作类型 → 结算类型/来源。审批草稿不移动成长积分，返回 nil（不生成结算建议）。
    private static func kindAndSource(
        for kind: MobileOfflineMutationKind
    ) -> (kind: MobileCreditSettlementKind, source: MobileCreditSettlementSource)? {
        switch kind {
        case .childTaskSubmission:
            return (.earn, .offlineAction)
        case .schoolHomeworkSubmission:
            return (.earn, .offlineAction)
        case .rewardRequest:
            return (.hold, .rewardRequest)
        case .relativeComment:
            return (.earn, .relativeEncouragement)
        case .deviceReceipt:
            return (.release, .deviceRewardLifecycle)
        case .guardianApproval:
            return nil
        }
    }

    /// 各来源的脱敏「建议积分」常量（仅展示，不代表已发放）。
    private static func suggestedAmount(for kind: MobileOfflineMutationKind) -> Int {
        switch kind {
        case .childTaskSubmission: return 15
        case .schoolHomeworkSubmission: return 10
        case .rewardRequest: return 30
        case .relativeComment: return 5
        case .deviceReceipt: return 15
        case .guardianApproval: return 0
        }
    }

    private static func actorRole(for role: MobileOfflineActorRole) -> MobileCreditSettlementActorRole {
        switch role {
        case .child: return .child
        case .guardian: return .guardian
        case .teacher: return .teacher
        case .relative: return .relative
        case .device: return .system
        }
    }

    // MARK: - 任务包已提交 → 赚取建议

    private func assignmentInputs(_ family: LocalFamilyStore) -> [MobileCreditSettlementProposalInput] {
        family.assignments
            .filter { $0.status == .submitted }
            .map { assignment in
                MobileCreditSettlementProposalInput(
                    proposalSeed: "assignment:\(assignment.id.uuidString)",
                    kind: .earn,
                    source: .offlineAction,
                    childSeed: Self.accountChildSeed,
                    familySeed: Self.accountFamilySeed,
                    amount: max(1, assignment.task.rewardMinutes),
                    scopeLabel: "完成证明待家长验证",
                    idempotencyKey: "assignment-\(assignment.id.uuidString)",
                    actorRole: .child,
                    redactionProbe: [assignment.task.category.rawValue]
                )
            }
    }

    // MARK: - 学校作业已提交 → 赚取建议

    private func homeworkInputs(_ schoolFamily: SchoolFamilyStore) -> [MobileCreditSettlementProposalInput] {
        schoolFamily.homeworks
            .filter { $0.status == .submitted }
            .map { homework in
                MobileCreditSettlementProposalInput(
                    proposalSeed: "homework:\(homework.id.uuidString)",
                    kind: .earn,
                    source: .schoolHomeworkMobileFlow,
                    childSeed: Self.accountChildSeed,
                    familySeed: Self.accountFamilySeed,
                    amount: 10,
                    scopeLabel: "等待老师/家长验证",
                    idempotencyKey: "homework-\(homework.id.uuidString)",
                    actorRole: .child,
                    redactionProbe: [homework.subject.rawValue]
                )
            }
    }

    // MARK: - 设备奖励会话 → 冻结 / 释放建议

    private func deviceInputs(_ screenTime: MockScreenTimeController) -> [MobileCreditSettlementProposalInput] {
        var inputs: [MobileCreditSettlementProposalInput] = []

        // 进行中会话：建议为奖励预留成长积分（冻结），不真正锁定余额。
        if screenTime.sessionStatus == .active && screenTime.activeMinutes > 0 {
            inputs.append(
                MobileCreditSettlementProposalInput(
                    proposalSeed: "active-session",
                    kind: .hold,
                    source: .deviceRewardLifecycle,
                    childSeed: Self.accountChildSeed,
                    familySeed: Self.accountFamilySeed,
                    amount: screenTime.activeMinutes,
                    scopeLabel: "奖励会话进行中（未真实解锁设备）",
                    idempotencyKey: "active-session",
                    actorRole: .system
                )
            )
        }

        // 最近一条收据若有未用分钟（家长提前结束）：建议把未用冻结释放回余额。
        if let receipt = screenTime.latestReceipt, receipt.unusedMinutes > 0 {
            inputs.append(
                MobileCreditSettlementProposalInput(
                    proposalSeed: "receipt:\(receipt.id.uuidString)",
                    kind: .release,
                    source: .deviceRewardLifecycle,
                    childSeed: Self.accountChildSeed,
                    familySeed: Self.accountFamilySeed,
                    amount: receipt.unusedMinutes,
                    scopeLabel: "未用完时长建议释放",
                    idempotencyKey: "receipt-\(receipt.id.uuidString)",
                    actorRole: .system,
                    relatedHoldPresent: true
                )
            )
        }
        return inputs
    }
}

// MARK: - 结算建议协调 store（@Observable，供 UI 持有）

/// 把装配器 + 引擎包成可观察 store：持有最近一次结算报告，供首页/奖励/家长端展示。
///
/// 与离线重放层平行：本 store **只读** 各数据源并产出脱敏、账本中立的结算建议，
/// 绝不写成长积分、不解锁设备、不改作业终态、不发动态/通知。
@Observable
final class MobileCreditSettlementStore {
    private(set) var report: MobileCreditSettlementReport
    @ObservationIgnored private let engine = MobileCreditSettlementEngine()
    @ObservationIgnored private let assembler = MobileCreditSettlementAssembler()

    init(report: MobileCreditSettlementReport = .empty) {
        self.report = report
    }

    var hasBuilt: Bool { !report.isEmpty }

    /// 重新装配并裁决结算建议。给定相同数据源恒定输出。
    @discardableResult
    func refresh(
        offlineReport: MobileOfflineReplayReport,
        family: LocalFamilyStore,
        schoolFamily: SchoolFamilyStore,
        screenTime: MockScreenTimeController
    ) -> MobileCreditSettlementReport {
        let inputs = assembler.makeInputs(
            offlineReport: offlineReport,
            family: family,
            schoolFamily: schoolFamily,
            screenTime: screenTime
        )
        let report = engine.build(account: assembler.account, proposals: inputs)
        self.report = report
        return report
    }

    func reset() {
        report = .empty
    }
}
