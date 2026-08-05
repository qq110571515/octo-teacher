import Foundation

/// 成长包运行结算引擎（纯逻辑、无副作用、无网络、无随机、无时钟）。
///
/// 给定相同输入恒定输出。逐步骤按与 B29 一致的优先级裁决投影状态，并保证输出脱敏、账本中立。
/// 任何会让「不该结算为可用成长积分」的情形（未提交 / 缺证明 / 证明被拒 / 待验证 / 失败测验 /
/// 老师退回 / 验证被拒 / 申诉中 / 年龄不适配 / 内容被拒 / 重复 / 作废 / 账户不匹配 / 不安全负载）
/// 都不会得到 `credit_suggested`。
struct GrowthPackRuntimeSettlementEngine {

    private static let defaultNow = "2026-06-24T02:00:00Z"
    private static let defaultSalt = "growth-pack-runtime-settlement-ios-v1"

    func build(
        account: GrowthRuntimeAccount,
        packTitle: String,
        packSummary: String,
        steps inputs: [GrowthRuntimeStepInput],
        generatedAt: String = GrowthPackRuntimeSettlementEngine.defaultNow,
        salt: String = GrowthPackRuntimeSettlementEngine.defaultSalt
    ) -> GrowthRuntimeSettlementReport {
        var seenKeys = Set<String>()
        var projections: [GrowthRuntimeStepProjection] = []
        var findings: [GrowthRuntimeFinding] = []

        for input in inputs {
            let evaluated = evaluate(input, account: account, seenKeys: &seenKeys)
            projections.append(makeProjection(input, account: account, evaluated: evaluated, salt: salt))
            if let code = evaluated.finding {
                findings.append(
                    GrowthRuntimeFinding(
                        code: code,
                        severity: code.severity,
                        message: evaluated.reason,
                        publicRef: Self.stablePublicRef(prefix: "settlement-finding", source: "\(code.rawValue):\(input.stepSeed)", salt: salt)
                    )
                )
            }
        }

        var report = GrowthRuntimeSettlementReport(
            generatedAt: generatedAt,
            packTitle: packTitle,
            packSummary: packSummary,
            steps: projections,
            findings: findings,
            publicSummary: makeSummary(account: account, generatedAt: generatedAt, salt: salt, steps: projections, findings: findings)
        )

        // 脱敏兜底：万一输出仍泄露敏感标识，整体降级为单条「已阻断」复核投影。
        if Self.reportLeaks(report) {
            report = Self.redactedFallback(account: account, generatedAt: generatedAt, salt: salt)
        }
        return report
    }

    // MARK: - 单步骤裁决（优先级与 B29 evaluateTask 对齐）

    private struct Evaluation {
        var status: GrowthRuntimeProjectionStatus
        var suggestedNextStage: GrowthRuntimeStage
        var reason: String
        var nextStep: String
        var finding: GrowthRuntimeFindingCode? = nil
        var isAppealing: Bool = false
    }

    private func evaluate(
        _ input: GrowthRuntimeStepInput,
        account: GrowthRuntimeAccount,
        seenKeys: inout Set<String>
    ) -> Evaluation {
        // 账户与安全护栏优先（与 B29 一致）。
        if !input.partOfAcceptedPlan {
            return Evaluation(status: .blocked, suggestedNextStage: input.stage,
                              reason: "该步骤不属于已接受的成长包计划，已阻断。",
                              nextStep: "等待计划接受后再运行。",
                              finding: .unknownRuntimeTask)
        }
        if input.childSeed != account.childSeed || input.familySeed != account.familySeed {
            return Evaluation(status: .blocked, suggestedNextStage: input.stage,
                              reason: "步骤与当前账户的孩子或家庭不匹配，已阻断。",
                              nextStep: "请核对账户后重试。",
                              finding: .crossChildFamilyMismatch)
        }
        if Self.hasUnsafeProbe(input.redactionProbe) {
            return Evaluation(status: .blocked, suggestedNextStage: input.stage,
                              reason: "检测到不安全负载，已在投影前阻断。",
                              nextStep: "请清理敏感内容后重新提交。",
                              finding: .unsafePayload)
        }

        // 阶段优先：planned / submitted / appealed / voided / credited。
        if input.stage == .planned {
            return Evaluation(status: .planned, suggestedNextStage: .planned,
                              reason: "已排期步骤需先提交并通过验证才能结算。",
                              nextStep: "完成该步骤并提交证明。")
        }
        if input.stage == .submitted || input.verificationOutcome == .pending || input.proofStatus == .pendingReview {
            return Evaluation(status: .reviewRequired, suggestedNextStage: .submitted,
                              reason: "已提交步骤正在等待验证复核。",
                              nextStep: "等待家长/老师验证。",
                              finding: .verificationPending)
        }
        if input.stage == .appealed || input.appealOpen || input.verificationOutcome == .appealed {
            return Evaluation(status: .reviewRequired, suggestedNextStage: .appealed,
                              reason: "申诉中的步骤必须停留复核，不能结算。",
                              nextStep: "等待申诉复核结果。",
                              finding: .appealOpen, isAppealing: true)
        }
        if input.stage == .voided {
            return Evaluation(status: .voided, suggestedNextStage: .voided,
                              reason: "已作废步骤为终态，不能产生结算。",
                              nextStep: "无需进一步操作。",
                              finding: .voidedTask)
        }
        if input.stage == .credited {
            return Evaluation(status: .alreadyCredited, suggestedNextStage: .credited,
                              reason: "步骤已结算，不再生成新的成长积分建议。",
                              nextStep: "可在成长记录中查看。",
                              finding: .alreadyCredited)
        }

        // 已验证步骤的证明 / 内容 / 验证 / 测验链路（全部阻断或复核，绝不直接放行）。
        if input.proofStatus == .missing || input.submittedProofCount == 0 || input.requiredProofCount == 0 {
            return Evaluation(status: .blocked, suggestedNextStage: input.stage,
                              reason: "已验证结算需要至少一份已复核证明。",
                              nextStep: "补交所需证明后再验证。",
                              finding: .missingProof)
        }
        if input.proofStatus == .rejected {
            return Evaluation(status: .blocked, suggestedNextStage: input.stage,
                              reason: "被拒证明不能生成成长积分建议。",
                              nextStep: "按反馈重做并重新提交证明。",
                              finding: .proofRejected)
        }
        if !input.ageAppropriate {
            return Evaluation(status: .blocked, suggestedNextStage: input.stage,
                              reason: "年龄不适配内容不能结算为已完成。",
                              nextStep: "更换为适龄内容后再运行。",
                              finding: .ageInappropriate)
        }
        if input.moderationStatus == .pending {
            return Evaluation(status: .reviewRequired, suggestedNextStage: input.stage,
                              reason: "内容审核完成前不能结算。",
                              nextStep: "等待内容审核结果。",
                              finding: .contentReviewRequired)
        }
        if input.moderationStatus == .rejected {
            return Evaluation(status: .blocked, suggestedNextStage: input.stage,
                              reason: "被拒内容不能生成成长结算。",
                              nextStep: "更换合规内容后重试。",
                              finding: .contentRejected)
        }
        if input.teacherReview == .returned || input.verificationOutcome == .returned {
            return Evaluation(status: .blocked, suggestedNextStage: input.stage,
                              reason: "老师退回的作业不能结算为已完成。",
                              nextStep: "按老师反馈修改后再交。",
                              finding: .teacherReturned)
        }
        if input.verificationOutcome == .rejected || input.teacherReview == .rejected {
            return Evaluation(status: .blocked, suggestedNextStage: input.stage,
                              reason: "被拒验证不能生成结算。",
                              nextStep: "按反馈重做后再验证。",
                              finding: .verificationRejected)
        }
        if input.kind == .quiz && input.quizPassed != true {
            return Evaluation(status: .blocked, suggestedNextStage: input.stage,
                              reason: "未通过的测验不能结算为成长积分。",
                              nextStep: "复习后重测达到通过线。",
                              finding: .failedQuiz)
        }
        if input.duplicate || seenKeys.contains(input.idempotencyKey) {
            return Evaluation(status: .duplicate, suggestedNextStage: input.stage,
                              reason: "相同幂等键不重复投影为新成长积分建议。",
                              nextStep: "无需重复提交。",
                              finding: .duplicateIdempotency)
        }
        seenKeys.insert(input.idempotencyKey)

        return Evaluation(status: .creditSuggested, suggestedNextStage: .credited,
                          reason: "已验证步骤可交家长审核后再决定是否发放成长积分/徽章/能力建议。",
                          nextStep: "交家长在控制台审核结算建议。")
    }

    // MARK: - 构建输出

    private func makeProjection(
        _ input: GrowthRuntimeStepInput,
        account: GrowthRuntimeAccount,
        evaluated: Evaluation,
        salt: String
    ) -> GrowthRuntimeStepProjection {
        let settlement: GrowthRuntimeSettlementPreview
        if evaluated.status == .creditSuggested {
            settlement = GrowthRuntimeSettlementPreview(
                suggestedCredit: max(0, input.suggestedCredit),
                scopeLabel: input.scopeLabel,
                badgeSuggestionCount: 1,
                abilitySuggestionCount: Self.abilityCount(for: input.kind)
            )
        } else {
            settlement = .none
        }

        return GrowthRuntimeStepProjection(
            publicStepRef: Self.stablePublicRef(prefix: "runstep", source: "\(account.familySeed):\(input.stepSeed)", salt: salt),
            publicPackRef: Self.stablePublicRef(prefix: "runpack", source: "\(account.familySeed):\(input.packSeed)", salt: salt),
            childPublicRef: Self.stablePublicRef(prefix: "kid", source: "\(account.familySeed):\(input.childSeed)", salt: salt),
            title: input.title,
            order: input.order,
            kind: input.kind,
            fromStage: input.stage,
            suggestedNextStage: evaluated.suggestedNextStage,
            status: evaluated.status,
            proofStatus: input.proofStatus,
            proofRequirementLabel: Self.proofRequirementLabel(input),
            reason: evaluated.reason,
            nextStep: evaluated.nextStep,
            actionRequired: evaluated.status == .creditSuggested || evaluated.status == .reviewRequired,
            retryable: evaluated.status == .reviewRequired,
            isAppealing: evaluated.isAppealing,
            settlement: settlement
        )
    }

    private static func abilityCount(for kind: GrowthRuntimeActivityKind) -> Int {
        kind == .compositeGrowthPack ? 2 : 1
    }

    private static func proofRequirementLabel(_ input: GrowthRuntimeStepInput) -> String {
        let need = max(0, input.requiredProofCount)
        let have = max(0, input.submittedProofCount)
        let kindHint: String
        switch input.kind {
        case .basicHabit: kindHint = "习惯打卡证明"
        case .schoolHomework: kindHint = "作业完成证明（需老师/家长验证）"
        case .quiz: kindHint = "测验通过记录"
        case .mediaLearning: kindHint = "学习进度证明"
        case .exerciseExternalProof: kindHint = "运动外部证明"
        case .creativeUpload: kindHint = "创作上传（需审核）"
        case .compositeGrowthPack: kindHint = "综合包各子项证明"
        }
        if need == 0 { return "\(kindHint) · 无内在证明记录" }
        return "\(kindHint) · 需 \(need) 份，已交 \(have) 份"
    }

    private func makeSummary(
        account: GrowthRuntimeAccount,
        generatedAt: String,
        salt: String,
        steps: [GrowthRuntimeStepProjection],
        findings: [GrowthRuntimeFinding]
    ) -> GrowthRuntimePublicSummary {
        func count(_ status: GrowthRuntimeProjectionStatus) -> Int { steps.filter { $0.status == status }.count }
        return GrowthRuntimePublicSummary(
            generatedAt: generatedAt,
            packPublicRef: steps.first?.publicPackRef ?? Self.stablePublicRef(prefix: "runpack", source: "redacted-pack", salt: salt),
            childPublicRef: Self.stablePublicRef(prefix: "kid", source: "\(account.familySeed):\(account.childSeed)", salt: salt),
            stepCount: steps.count,
            plannedCount: count(.planned),
            reviewRequiredCount: count(.reviewRequired),
            creditSuggestedCount: count(.creditSuggested),
            appealingCount: steps.filter { $0.isAppealing }.count,
            blockedCount: count(.blocked),
            duplicateCount: count(.duplicate),
            alreadyCreditedCount: count(.alreadyCredited),
            voidedCount: count(.voided),
            totalSuggestedCredit: steps.reduce(0) { $0 + $1.settlement.suggestedCredit },
            badgeSuggestionCount: steps.reduce(0) { $0 + $1.settlement.badgeSuggestionCount },
            abilitySuggestionCount: steps.reduce(0) { $0 + $1.settlement.abilitySuggestionCount },
            findingCodes: findings.map { $0.code }
        )
    }

    // MARK: - 脱敏

    /// 输出可展示文本里是否仍带敏感标识（本地路径/token/局域网地址，或裸内部引用前缀）。
    static func reportLeaks(_ report: GrowthRuntimeSettlementReport) -> Bool {
        var values: [String] = [report.packTitle, report.packSummary, report.childHeadline, report.parentHeadline,
                                report.publicSummary.packPublicRef, report.publicSummary.childPublicRef]
        for step in report.steps {
            values.append(contentsOf: [step.title, step.reason, step.nextStep, step.proofRequirementLabel,
                                       step.kindLabel, step.stageLabel, step.statusLabel,
                                       step.settlement.scopeLabel, step.publicStepRef, step.publicPackRef, step.childPublicRef])
        }
        for finding in report.findings {
            values.append(finding.message)
        }
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let rawPatterns = [
            "(?i)\\bfamily-[a-z0-9_-]+",
            "(?i)\\bchild-[a-z0-9_-]+",
            "(?i)\\bpack-[a-z0-9_-]+",
            "(?i)\\bproof-[a-z0-9_-]+",
            "(?i)\\bledger-[a-z0-9_-]+",
            "(?i)\\bhomework-[a-z0-9_-]+",
            "(?i)\\b(?:child|family|pack|proof|ledger|homework|task|claim):[a-z0-9_-]+",
            "(?i)\\b(?:taskId|claimId)\\b"
        ]
        for value in values {
            for pattern in rawPatterns where value.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }

    private static func hasUnsafeProbe(_ probe: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(probe) { return true }
        return probe.contains { value in
            value.range(of: "(?i)\\b(taskId|claimId)\\b", options: .regularExpression) != nil
        }
    }

    private static func redactedFallback(
        account: GrowthRuntimeAccount,
        generatedAt: String,
        salt: String
    ) -> GrowthRuntimeSettlementReport {
        let pack = stablePublicRef(prefix: "runpack", source: "redacted-pack", salt: salt)
        let kid = stablePublicRef(prefix: "kid", source: "redacted-child", salt: salt)
        let step = GrowthRuntimeStepProjection(
            publicStepRef: stablePublicRef(prefix: "runstep", source: "public-summary-leak", salt: salt),
            publicPackRef: pack,
            childPublicRef: kid,
            title: "成长包步骤",
            order: 1,
            kind: .compositeGrowthPack,
            fromStage: .verified,
            suggestedNextStage: .verified,
            status: .blocked,
            proofStatus: .pendingReview,
            proofRequirementLabel: "证明需复核",
            reason: "公开运行投影未通过脱敏检查，已强制阻断复核。",
            nextStep: "请联系家长复核。",
            actionRequired: true,
            retryable: false,
            isAppealing: false,
            settlement: .none
        )
        let finding = GrowthRuntimeFinding(
            code: .publicSummaryLeak,
            severity: .blocker,
            message: "公开运行结算摘要未通过脱敏检查，已强制阻断复核。",
            publicRef: stablePublicRef(prefix: "settlement-finding", source: "public-summary-leak", salt: salt)
        )
        return GrowthRuntimeSettlementReport(
            generatedAt: generatedAt,
            packTitle: "成长包运行",
            packSummary: "公开投影已脱敏阻断。",
            steps: [step],
            findings: [finding],
            publicSummary: GrowthRuntimePublicSummary(
                generatedAt: generatedAt,
                packPublicRef: pack,
                childPublicRef: kid,
                stepCount: 1,
                plannedCount: 0,
                reviewRequiredCount: 0,
                creditSuggestedCount: 0,
                appealingCount: 0,
                blockedCount: 1,
                duplicateCount: 0,
                alreadyCreditedCount: 0,
                voidedCount: 0,
                totalSuggestedCredit: 0,
                badgeSuggestionCount: 0,
                abilitySuggestionCount: 0,
                findingCodes: [.publicSummaryLeak]
            )
        )
    }

    /// 稳定脱敏引用（djb2，与离线/成长积分结算层同风格）。
    static func stablePublicRef(prefix: String, source: String, salt: String = defaultSalt) -> String {
        var hash = 5381
        for scalar in "\(salt):\(source)".unicodeScalars {
            hash = ((hash << 5) &+ hash) ^ Int(scalar.value)
        }
        let value = String(UInt(bitPattern: hash), radix: 36)
        return "\(prefix):\(value)"
    }
}
