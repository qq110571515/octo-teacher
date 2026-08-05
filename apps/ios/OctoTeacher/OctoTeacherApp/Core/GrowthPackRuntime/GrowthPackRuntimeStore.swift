import Foundation
import Observation

/// 成长包运行步骤装配器：把本地各 mock 数据源投影成运行步骤输入草稿。
///
/// 这是 B29 结算契约在 iOS 的「输入侧」：纯逻辑、确定性。它产出一份覆盖全部七类活动
/// （基础习惯、学校作业、测验、媒体学习、运动外部证明、创作上传、综合成长包）、跨全部阶段
/// （planned/submitted/verified/credited/appealed/voided）的脱敏运行步骤，并**只读**折入
/// `LocalFamilyStore` 的已提交任务与 `SchoolFamilyStore` 的已提交作业作为额外「待复核」步骤。
///
/// 装配器绝不调用任何会发成长积分/授徽章/改任务终态/写作业终态/解锁设备的写方法。
struct GrowthPackRuntimeAssembler {

    /// 本地账户脱敏 seed（与成长积分结算层平行，保证步骤都匹配同一账户）。
    static let accountChildSeed = "growth-runtime-account-child"
    static let accountFamilySeed = "growth-runtime-account-family"
    static let packTitle = "本周综合成长包"
    static let packSummary = "覆盖基础习惯、学校作业、测验、媒体学习、运动证明、创作上传与综合包的运行详情与脱敏结算预览。"

    var account: GrowthRuntimeAccount {
        GrowthRuntimeAccount(childSeed: Self.accountChildSeed, familySeed: Self.accountFamilySeed)
    }

    func makeSteps(
        family: LocalFamilyStore,
        schoolFamily: SchoolFamilyStore
    ) -> [GrowthRuntimeStepInput] {
        var steps = baselineSteps()
        steps.append(contentsOf: assignmentSteps(family, startOrder: steps.count + 1))
        steps.append(contentsOf: homeworkSteps(schoolFamily, startOrder: steps.count + 1))
        return steps
    }

    // MARK: - 内置确定性 mock：七类活动 × 多阶段

    /// 这些步骤覆盖运行状态机的全部分支，保证孩子端能看到每类活动的各种状态，
    /// 家长端能看到待审核/可建议/已阻断/申诉中四类。全部脱敏，数据结构贴合未来真实运行计划。
    private func baselineSteps() -> [GrowthRuntimeStepInput] {
        let child = Self.accountChildSeed
        let family = Self.accountFamilySeed
        func step(
            _ seed: String,
            _ title: String,
            _ order: Int,
            _ kind: GrowthRuntimeActivityKind,
            _ stage: GrowthRuntimeStage,
            credit: Int = 10,
            requiredProofCount: Int = 1,
            submittedProofCount: Int = 1,
            proofStatus: GrowthRuntimeProofStatus = .approved,
            verificationOutcome: GrowthRuntimeVerificationOutcome = .approved,
            quizPassed: Bool? = nil,
            teacherReview: GrowthRuntimeVerificationOutcome? = nil,
            moderationStatus: GrowthRuntimeContentReviewStatus = .notRequired,
            ageAppropriate: Bool = true,
            appealOpen: Bool = false
        ) -> GrowthRuntimeStepInput {
            GrowthRuntimeStepInput(
                stepSeed: seed,
                packSeed: "weekly-composite-pack",
                childSeed: child,
                familySeed: family,
                title: title,
                order: order,
                kind: kind,
                stage: stage,
                requiredProofCount: requiredProofCount,
                submittedProofCount: submittedProofCount,
                proofStatus: proofStatus,
                verificationOutcome: verificationOutcome,
                suggestedCredit: credit,
                idempotencyKey: "baseline-\(seed)",
                quizPassed: quizPassed,
                teacherReview: teacherReview,
                moderationStatus: moderationStatus,
                ageAppropriate: ageAppropriate,
                appealOpen: appealOpen
            )
        }

        return [
            // 基础习惯：已结算（已发放过）。
            step("habit-credited", "每日整理书桌", 1, .basicHabit, .credited, credit: 5),
            // 学校作业：老师退回 → 阻断。
            step("homework-returned", "数学练习册第 3 单元", 2, .schoolHomework, .verified, credit: 15,
                 teacherReview: .returned),
            // 测验：未通过 → 阻断。
            step("quiz-failed", "英语单词小测", 3, .quiz, .verified, credit: 10, quizPassed: false),
            // 测验：通过且验证 → 可建议。
            step("quiz-passed", "科学概念小测", 4, .quiz, .verified, credit: 10, quizPassed: true),
            // 媒体学习：内容待审 → 待复核。
            step("media-pending", "纪录片：海洋生态", 5, .mediaLearning, .verified, credit: 8,
                 moderationStatus: .pending),
            // 运动外部证明：已验证、证明齐备 → 可建议。
            step("exercise-verified", "户外跑步 20 分钟", 6, .exerciseExternalProof, .verified, credit: 12),
            // 创作上传：缺证明 → 阻断。
            step("creative-missing", "绘画作品上传", 7, .creativeUpload, .verified, credit: 14,
                 submittedProofCount: 0, proofStatus: .missing),
            // 创作上传：申诉中 → 申诉中（家长端单列）。
            step("creative-appeal", "手工作品上传", 8, .creativeUpload, .appealed, credit: 14, appealOpen: true),
            // 综合成长包：已排期 → 待开始。
            step("composite-planned", "周末家庭项目", 9, .compositeGrowthPack, .planned, credit: 20),
            // 基础习惯：已提交待验证 → 待复核。
            step("habit-submitted", "睡前阅读打卡", 10, .basicHabit, .submitted, credit: 5)
        ]
    }

    // MARK: - 只读折入：本地已提交任务 → 待复核步骤

    private func assignmentSteps(_ family: LocalFamilyStore, startOrder: Int) -> [GrowthRuntimeStepInput] {
        family.assignments
            .filter { $0.status == .submitted }
            .enumerated()
            .map { index, assignment in
                GrowthRuntimeStepInput(
                    stepSeed: "assignment:\(assignment.id.uuidString)",
                    packSeed: "weekly-composite-pack",
                    childSeed: Self.accountChildSeed,
                    familySeed: Self.accountFamilySeed,
                    title: "任务：\(assignment.task.title)",
                    order: startOrder + index,
                    kind: .basicHabit,
                    stage: .submitted,
                    proofStatus: .pendingReview,
                    verificationOutcome: .pending,
                    suggestedCredit: max(1, assignment.task.rewardMinutes),
                    scopeLabel: "完成证明待家长验证",
                    idempotencyKey: "assignment-\(assignment.id.uuidString)",
                    redactionProbe: [assignment.task.category.rawValue]
                )
            }
    }

    // MARK: - 只读折入：本地已提交学校作业 → 待复核步骤

    private func homeworkSteps(_ schoolFamily: SchoolFamilyStore, startOrder: Int) -> [GrowthRuntimeStepInput] {
        schoolFamily.homeworks
            .filter { $0.status == .submitted }
            .enumerated()
            .map { index, homework in
                GrowthRuntimeStepInput(
                    stepSeed: "homework:\(homework.id.uuidString)",
                    packSeed: "weekly-composite-pack",
                    childSeed: Self.accountChildSeed,
                    familySeed: Self.accountFamilySeed,
                    title: "作业：\(homework.subject.label)",
                    order: startOrder + index,
                    kind: .schoolHomework,
                    stage: .submitted,
                    proofStatus: .pendingReview,
                    verificationOutcome: .pending,
                    suggestedCredit: 15,
                    scopeLabel: "等待老师/家长验证",
                    idempotencyKey: "homework-\(homework.id.uuidString)",
                    redactionProbe: [homework.subject.rawValue]
                )
            }
    }
}

// MARK: - 运行结算协调 store（@Observable，供 UI 持有）

/// 把装配器 + 引擎包成可观察 store：持有最近一次成长包运行结算报告，供孩子/家长端展示。
///
/// 与成长积分结算/离线重放层平行：本 store **只读** 各数据源并产出脱敏、账本中立的运行投影与
/// 结算预览，绝不写成长积分、不授徽章、不改任务终态、不写作业终态、不发动态/通知/解锁设备。
@Observable
final class GrowthPackRuntimeStore {
    private(set) var report: GrowthRuntimeSettlementReport
    @ObservationIgnored private let engine = GrowthPackRuntimeSettlementEngine()
    @ObservationIgnored private let assembler = GrowthPackRuntimeAssembler()

    init(report: GrowthRuntimeSettlementReport = .empty) {
        self.report = report
    }

    var hasBuilt: Bool { !report.isEmpty }

    /// 重新装配并裁决运行结算投影。给定相同数据源恒定输出。
    @discardableResult
    func refresh(
        family: LocalFamilyStore,
        schoolFamily: SchoolFamilyStore
    ) -> GrowthRuntimeSettlementReport {
        let steps = assembler.makeSteps(family: family, schoolFamily: schoolFamily)
        let report = engine.build(
            account: assembler.account,
            packTitle: GrowthPackRuntimeAssembler.packTitle,
            packSummary: GrowthPackRuntimeAssembler.packSummary,
            steps: steps
        )
        self.report = report
        return report
    }

    func reset() {
        report = .empty
    }
}
