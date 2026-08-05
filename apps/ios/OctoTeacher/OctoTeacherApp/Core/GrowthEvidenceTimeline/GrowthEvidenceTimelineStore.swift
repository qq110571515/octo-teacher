import Foundation
import Observation

/// 证据时间线装配器：把本地各 mock 数据源投影成一条确定性、脱敏的证据案件输入草稿。
///
/// 这是 B30 契约在 iOS 的「输入侧」：纯逻辑、确定性、只读。它产出一条覆盖全部九类事件
/// （孩子提交 / 老师验证 / 家长确认 / 亲友鼓励 / 成长积分建议 / 申诉发起 / 申诉裁决 / 撤销 / 时间线展示）
/// 与全部关键边界（缺 hash、prevHash 断链、重复证明、跨孩子复用、亲友越权、老师家长冲突、申诉中、
/// 撤销未传播、重复幂等、公开可见性）的脱敏案件，并**只读**折入 `LocalFamilyStore` 的已提交任务、
/// `SchoolFamilyStore` 的已提交作业与 `GrowthPackRuntimeStore` 的可建议结算计数作为额外节点。
///
/// 装配器绝不调用任何会写账本 / 改作业终态 / 发布时间线 / 通知亲友 / 保存原始媒体 / 解锁设备的写方法。
struct GrowthEvidenceTimelineAssembler {

    static let accountChildSeed = "growth-evidence-account-child"
    static let accountFamilySeed = "growth-evidence-account-family"
    static let caseSeed = "growth-evidence-weekly-case"
    static let caseTitle = "本周成长证据链"
    static let caseSummary = "孩子提交、老师验证、家长确认、亲友鼓励、成长积分建议、申诉、撤销与公开时间线的脱敏证据链投影。"

    /// 故意制造链异常以演示阻断分支。
    private enum Fault {
        case none
        case missingHash
        case breakPrev
    }

    private struct Draft {
        var seed: String
        var kind: GrowthEvidenceTimelineEventKind
        var role: GrowthEvidenceTimelineActorRole
        var title: String
        var proofSeed: String?
        var appealSeed: String?
        var creditSuggestionSeed: String?
        var decision: GrowthEvidenceTimelineDecision?
        var teacherConclusion: GrowthEvidenceTimelineDecision?
        var guardianConclusion: GrowthEvidenceTimelineDecision?
        var guardianReview: GrowthEvidenceTimelineGuardianReview?
        var visibility: GrowthEvidenceTimelineVisibility?
        var creditAmount: Int = 0
        var idempotencyKey: String?
        var revocation: GrowthEvidenceTimelineRevocation?
        var childSeedOverride: String?
        var redactionProbe: [String] = []
        var fault: Fault = .none
    }

    func makeCase(
        family: LocalFamilyStore,
        schoolFamily: SchoolFamilyStore,
        growthRuntime: GrowthEvidenceTimelineRuntimeContext
    ) -> GrowthEvidenceTimelineCaseInput {
        var drafts = baselineDrafts()
        drafts.append(contentsOf: foldedDrafts(family: family, schoolFamily: schoolFamily, runtime: growthRuntime))

        let events = linkChain(drafts)
        return GrowthEvidenceTimelineCaseInput(
            familySeed: Self.accountFamilySeed,
            childSeed: Self.accountChildSeed,
            caseSeed: Self.caseSeed,
            existingProofSeeds: ["history-proof-shared"],
            existingIdempotencyKeys: ["replayed-credit-key"],
            events: events
        )
    }

    // MARK: - 内置确定性 mock：九类事件 × 关键边界

    private func baselineDrafts() -> [Draft] {
        return [
            // 孩子提交：已记录。
            Draft(seed: "submit-1", kind: .childSubmitted, role: .child, title: "提交：朗读练习证明", proofSeed: "proof-read"),
            // 老师验证：已记录（验证不重复登记证明引用，避免误判重复证明）。
            Draft(seed: "teacher-verify", kind: .teacherVerified, role: .teacher, title: "老师验证：朗读达标"),
            // 家长确认：已记录。
            Draft(seed: "guardian-confirm", kind: .guardianConfirmed, role: .guardian, title: "家长确认：朗读完成"),
            // 成长积分建议（结论一致）：可释放。
            Draft(seed: "credit-aligned", kind: .creditSuggested, role: .system, title: "成长积分建议：朗读达标",
                  creditSuggestionSeed: "credit-read", teacherConclusion: .approved, guardianConclusion: .approved, creditAmount: 10),
            // 成长积分建议（仅老师结论，家长未确认）：冻结（结论未对齐，区别于冲突）。
            Draft(seed: "credit-frozen", kind: .creditSuggested, role: .system, title: "成长积分建议：待家长确认",
                  creditSuggestionSeed: "credit-pending", teacherConclusion: .approved, creditAmount: 8),
            // 亲友鼓励（家长已复核）：进入时间线。
            Draft(seed: "relative-ok", kind: .relativeEncouraged, role: .relative, title: "亲友鼓励：继续加油",
                  guardianReview: .approved, visibility: .family),
            // 亲友鼓励（家长未复核）：待复核，不进公开。
            Draft(seed: "relative-pending", kind: .relativeEncouraged, role: .relative, title: "亲友鼓励：待家长复核",
                  guardianReview: .pending),
            // 亲友越权（亲友试图做老师验证）：阻断。
            Draft(seed: "relative-overreach", kind: .teacherVerified, role: .relative, title: "亲友越权：试图验证作业"),
            // 老师/家长结论冲突：冲突待裁。
            Draft(seed: "conflict-1", kind: .guardianConfirmed, role: .guardian, title: "结论冲突：老师通过家长退回",
                  teacherConclusion: .approved, guardianConclusion: .returned),
            // 发起申诉：成长积分冻结。
            Draft(seed: "appeal-open", kind: .appealOpened, role: .guardian, title: "家长发起申诉",
                  appealSeed: "appeal-1", creditAmount: 8),
            // 申诉裁决（恢复）：成长积分可释放。
            Draft(seed: "appeal-restore", kind: .appealResolved, role: .guardian, title: "申诉裁决：恢复",
                  appealSeed: "appeal-1", decision: .restored, creditAmount: 8),
            // 缺 hash：阻断。
            Draft(seed: "missing-hash", kind: .childSubmitted, role: .child, title: "提交：缺哈希证据", fault: .missingHash),
            // prevHash 断链：阻断。
            Draft(seed: "broken-prev", kind: .childSubmitted, role: .child, title: "提交：链断裂证据", fault: .breakPrev),
            // 重复证明（与历史 history-proof-shared 同引用）：阻断。
            Draft(seed: "dup-proof", kind: .childSubmitted, role: .child, title: "提交：重复证明", proofSeed: "history-proof-shared"),
            // 重复幂等键（与历史重放键相同）：重放忽略。
            Draft(seed: "replay", kind: .creditSuggested, role: .system, title: "成长积分建议：重放",
                  creditSuggestionSeed: "credit-replay", teacherConclusion: .approved, guardianConclusion: .approved,
                  creditAmount: 5, idempotencyKey: "replayed-credit-key"),
            // 跨孩子复用：阻断。
            Draft(seed: "cross-child", kind: .childSubmitted, role: .child, title: "提交：跨孩子证据",
                  childSeedOverride: "other-child-seed"),
            // 撤销（未传播）：撤销待传播。
            Draft(seed: "revoke-partial", kind: .revoked, role: .guardian, title: "撤销：未完全传播",
                  proofSeed: "proof-revoke",
                  revocation: GrowthEvidenceTimelineRevocation(timelineHidden: true, creditBlocked: true,
                                                               feedWithdrawn: false, homeworkMarkedRevoked: false,
                                                               relativeVisibilityRevoked: false)),
            // 撤销（已传播）：已撤销。
            Draft(seed: "revoke-full", kind: .revoked, role: .guardian, title: "撤销：已完全传播",
                  proofSeed: "proof-revoke-2",
                  revocation: GrowthEvidenceTimelineRevocation(timelineHidden: true, creditBlocked: true,
                                                               feedWithdrawn: true, homeworkMarkedRevoked: true,
                                                               relativeVisibilityRevoked: true)),
            // 公开成长时间线展示：公开可见。
            Draft(seed: "publish", kind: .timelinePublished, role: .guardian, title: "成长时间线展示",
                  visibility: .public)
        ]
    }

    // MARK: - 只读折入：本地已提交任务 / 作业 / 运行结算可建议计数

    private func foldedDrafts(
        family: LocalFamilyStore,
        schoolFamily: SchoolFamilyStore,
        runtime: GrowthEvidenceTimelineRuntimeContext
    ) -> [Draft] {
        var drafts: [Draft] = []

        let submittedAssignments = family.assignments.filter { $0.status == .submitted }
        for (index, assignment) in submittedAssignments.enumerated() {
            drafts.append(Draft(
                seed: "fold-assignment-\(index)",
                kind: .childSubmitted,
                role: .child,
                title: "本地任务待复核提交 \(index + 1)",
                proofSeed: "fold-assignment-proof-\(index)",
                redactionProbe: [assignment.task.category.rawValue]
            ))
        }

        let submittedHomeworks = schoolFamily.homeworks.filter { $0.status == .submitted }
        for (index, homework) in submittedHomeworks.enumerated() {
            drafts.append(Draft(
                seed: "fold-homework-\(index)",
                kind: .childSubmitted,
                role: .child,
                title: "学校作业待复核提交 \(index + 1)",
                proofSeed: "fold-homework-proof-\(index)",
                redactionProbe: [homework.subject.rawValue]
            ))
        }

        // 运行结算可建议计数 → 一条冻结成长积分建议（仍只是建议，待家长流程审核）。
        if runtime.proposableCount > 0 {
            drafts.append(Draft(
                seed: "fold-runtime-credit",
                kind: .creditSuggested,
                role: .system,
                title: "运行结算可建议 \(runtime.proposableCount) 项（待家长审核）",
                creditSuggestionSeed: "fold-runtime-credit-seed",
                teacherConclusion: .approved,
                creditAmount: max(1, runtime.totalSuggestedCredit)
            ))
        }

        return drafts
    }

    // MARK: - 链接：按草稿顺序赋递增时间与 hash/prevHash

    private func linkChain(_ drafts: [Draft]) -> [GrowthEvidenceTimelineEventInput] {
        // 先算每条事件的 hash（缺 hash 故障为 nil）。
        let hashes: [String?] = drafts.enumerated().map { index, draft in
            draft.fault == .missingHash ? nil : "evhash-\(index)"
        }

        return drafts.enumerated().map { index, draft in
            let occurredAt = String(format: "2026-06-20T08:%02d:00Z", index)
            let prevHash: String?
            if index == 0 {
                prevHash = nil
            } else if draft.fault == .breakPrev {
                prevHash = "evhash-broken"
            } else {
                prevHash = hashes[index - 1]
            }

            return GrowthEvidenceTimelineEventInput(
                eventSeed: draft.seed,
                kind: draft.kind,
                occurredAt: occurredAt,
                familySeed: Self.accountFamilySeed,
                childSeed: draft.childSeedOverride ?? Self.accountChildSeed,
                actorRole: draft.role,
                actorSeed: "actor-\(draft.role.rawValue)",
                title: draft.title,
                proofSeed: draft.proofSeed,
                appealSeed: draft.appealSeed,
                creditSuggestionSeed: draft.creditSuggestionSeed,
                hash: hashes[index],
                prevHash: prevHash,
                decision: draft.decision,
                teacherConclusion: draft.teacherConclusion,
                guardianConclusion: draft.guardianConclusion,
                guardianReview: draft.guardianReview,
                visibility: draft.visibility,
                creditAmount: draft.creditAmount,
                idempotencyKey: draft.idempotencyKey,
                revocation: draft.revocation,
                redactionProbe: draft.redactionProbe
            )
        }
    }
}

/// 来自成长包运行结算层的只读上下文（解耦，避免直接依赖具体 store 类型）。
struct GrowthEvidenceTimelineRuntimeContext: Equatable {
    var proposableCount: Int
    var totalSuggestedCredit: Int

    static let none = GrowthEvidenceTimelineRuntimeContext(proposableCount: 0, totalSuggestedCredit: 0)

    /// 从成长包运行结算报告抽取只读计数。
    init(proposableCount: Int, totalSuggestedCredit: Int) {
        self.proposableCount = proposableCount
        self.totalSuggestedCredit = totalSuggestedCredit
    }

    init(report: GrowthRuntimeSettlementReport) {
        self.proposableCount = report.steps(in: .proposable).count
        self.totalSuggestedCredit = report.publicSummary.totalSuggestedCredit
    }
}

// MARK: - 证据时间线协调 store（@Observable，供 UI 持有）

/// 把装配器 + 引擎包成可观察 store：持有最近一次证据链申诉时间线报告，供孩子 / 家长端展示。
///
/// 与运行结算 / 成长积分结算 / 离线重放层平行：本 store **只读** 各数据源并产出脱敏、账本中立的证据时间线
/// 投影，绝不写账本、不改作业终态、不发布时间线、不通知亲友、不保存原始媒体、不解锁设备。
@Observable
final class GrowthEvidenceTimelineStore {
    private(set) var report: GrowthEvidenceTimelineReport
    @ObservationIgnored private let engine = GrowthEvidenceTimelineEngine()
    @ObservationIgnored private let assembler = GrowthEvidenceTimelineAssembler()

    init(report: GrowthEvidenceTimelineReport = .empty) {
        self.report = report
    }

    var hasBuilt: Bool { !report.isEmpty }

    /// 重新装配并裁决证据时间线投影。给定相同数据源恒定输出。
    @discardableResult
    func refresh(
        family: LocalFamilyStore,
        schoolFamily: SchoolFamilyStore,
        runtime: GrowthEvidenceTimelineRuntimeContext = .none
    ) -> GrowthEvidenceTimelineReport {
        let input = assembler.makeCase(family: family, schoolFamily: schoolFamily, growthRuntime: runtime)
        let report = engine.build(
            input,
            caseTitle: GrowthEvidenceTimelineAssembler.caseTitle,
            caseSummary: GrowthEvidenceTimelineAssembler.caseSummary
        )
        self.report = report
        return report
    }

    func reset() {
        report = .empty
    }
}
