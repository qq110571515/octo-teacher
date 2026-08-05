import Foundation

/// 成长积分结算建议引擎（纯逻辑、无副作用、无网络、无随机、无时钟）。
///
/// 给定相同输入恒定输出。逐条按与 B28 一致的优先级裁决状态，并保证输出脱敏、账本中立。
/// 任何会让「不该结算为可用成长积分」的情形（冲突 / 亲友鼓励 / 设备失败 / 离线回滚 / 撤权 /
/// 缺关联 hold / 不安全负载 / 账户不匹配）都不会得到 `proposed`。
struct MobileCreditSettlementEngine {

    private static let defaultNow = "2026-06-24T00:05:00Z"
    private static let defaultSalt = "mobile-credit-settlement-ios-v1"

    func build(
        account: MobileCreditSettlementAccount,
        proposals inputs: [MobileCreditSettlementProposalInput],
        generatedAt: String = MobileCreditSettlementEngine.defaultNow,
        salt: String = MobileCreditSettlementEngine.defaultSalt
    ) -> MobileCreditSettlementReport {
        var seenKeys = Set<String>()
        var proposals: [MobileCreditSettlementProposal] = []
        var findings: [MobileCreditSettlementFinding] = []

        for input in inputs {
            let evaluated = evaluate(input, account: account, seenKeys: &seenKeys, now: generatedAt)
            proposals.append(makeProposal(input, account: account, status: evaluated.status, message: evaluated.message, salt: salt))
            if let code = evaluated.finding {
                findings.append(
                    MobileCreditSettlementFinding(
                        code: code,
                        severity: code.severity,
                        message: evaluated.message,
                        publicRef: Self.stablePublicRef(prefix: "settlement-finding", source: "\(code.rawValue):\(input.proposalSeed)", salt: salt)
                    )
                )
            }
        }

        var report = MobileCreditSettlementReport(
            generatedAt: generatedAt,
            proposals: proposals,
            findings: findings,
            publicSummary: makeSummary(account: account, generatedAt: generatedAt, salt: salt, proposals: proposals, findings: findings)
        )

        // 脱敏兜底：万一输出仍泄露敏感标识，整体降级为单条「已阻断」复核建议。
        if Self.reportLeaks(report) {
            report = Self.redactedFallback(account: account, generatedAt: generatedAt, salt: salt)
        }
        return report
    }

    // MARK: - 单条裁决（优先级与 B28 对齐）

    private struct Evaluation {
        var status: MobileCreditSettlementStatus
        var finding: MobileCreditSettlementFindingCode?
        var message: String
    }

    private func evaluate(
        _ input: MobileCreditSettlementProposalInput,
        account: MobileCreditSettlementAccount,
        seenKeys: inout Set<String>,
        now: String
    ) -> Evaluation {
        if input.childSeed != account.childSeed || input.familySeed != account.familySeed {
            return Evaluation(status: .blocked, finding: .crossChildFamilyMismatch, message: "结算建议与当前账户的孩子或家庭不匹配，已阻断。")
        }
        if input.amount <= 0 {
            return Evaluation(status: .blocked, finding: .invalidAmount, message: "结算金额必须为正，已阻断。")
        }
        if Self.hasUnsafeProbe(input.redactionProbe) {
            return Evaluation(status: .blocked, finding: .unsafePayload, message: "检测到不安全负载，已在投影前阻断。")
        }
        if seenKeys.contains(input.idempotencyKey) {
            return Evaluation(status: .duplicate, finding: .duplicateIdempotency, message: "相同幂等键按重放处理，不再生成新结算。")
        }
        seenKeys.insert(input.idempotencyKey)

        if input.sessionState == .revoked {
            return Evaluation(status: .blocked, finding: .revokedActionBlocked, message: "撤权会话不能产生结算建议，已阻断。")
        }
        if input.kind == .hold && input.holdExpired {
            return Evaluation(status: .expired, finding: .expiredHold, message: "冻结已过期，只投影为复核项，不激活。")
        }
        if input.offlineReplayed {
            return Evaluation(status: .duplicate, finding: .offlineReplayBlocked, message: "离线重放不能再生成可用结算。")
        }
        if input.offlineRolledBack {
            return Evaluation(status: .blocked, finding: .rollbackRequired, message: "需回滚的离线动作不能结算为可用成长积分，已阻断。")
        }
        if let teacher = input.teacherConclusion,
           let guardian = input.guardianConclusion,
           teacher != guardian {
            return Evaluation(status: .conflict, finding: .teacherGuardianConflict, message: "老师与家长结论不一致，结算需成人复核。")
        }
        if input.offlineConflict {
            return Evaluation(status: .conflict, finding: .offlineConflictReview, message: "离线同步出现冲突，结算需复核后再定。")
        }
        if input.source == .relativeEncouragement {
            return Evaluation(status: .reviewRequired, finding: .relativeEncouragementReviewRequired, message: "亲友鼓励只能成为待审核建议，不直接发成长积分。")
        }
        if input.deviceFailed {
            return Evaluation(status: .reviewRequired, finding: .deviceFailureRefundReview, message: "设备失败只投影为退款待审核建议。")
        }
        if [.spend, .release, .refund].contains(input.kind) && !input.relatedHoldPresent {
            return Evaluation(status: .blocked, finding: .missingRelatedHold, message: "消费/释放/退款建议需要已存在的冻结成长积分引用，已阻断。")
        }
        return Evaluation(status: .proposed, finding: nil, message: proposedReason(input.kind))
    }

    private func proposedReason(_ kind: MobileCreditSettlementKind) -> String {
        switch kind {
        case .earn: return "完成证明已收到，可交家长审核后再发放成长积分。"
        case .hold: return "可审核后再为奖励会话预留成长积分（暂不锁定余额）。"
        case .spend: return "可在冻结使用证据核验后审核扣减。"
        case .release: return "可在未用完冻结对账后审核释放。"
        case .refund: return "可在失败或冲销证据核验后审核退款。"
        case .reverse: return "可对照原交易证据审核冲销。"
        }
    }

    // MARK: - 构建输出

    private func makeProposal(
        _ input: MobileCreditSettlementProposalInput,
        account: MobileCreditSettlementAccount,
        status: MobileCreditSettlementStatus,
        message: String,
        salt: String
    ) -> MobileCreditSettlementProposal {
        MobileCreditSettlementProposal(
            publicProposalRef: Self.stablePublicRef(prefix: "settlement", source: "\(account.familySeed):\(input.proposalSeed)", salt: salt),
            kind: input.kind,
            status: status,
            source: input.source,
            childPublicRef: Self.stablePublicRef(prefix: "kid", source: "\(account.familySeed):\(input.childSeed)", salt: salt),
            accountPublicRef: Self.stablePublicRef(prefix: "acct", source: "\(account.familySeed):\(account.childSeed)", salt: salt),
            amount: input.amount,
            scopeLabel: input.scopeLabel,
            requestedAt: input.requestedAt,
            reason: status == .proposed ? proposedReason(input.kind) : message,
            actionRequired: status != .duplicate && status != .blocked,
            retryable: status == .expired || status == .conflict || status == .reviewRequired
        )
    }

    private func makeSummary(
        account: MobileCreditSettlementAccount,
        generatedAt: String,
        salt: String,
        proposals: [MobileCreditSettlementProposal],
        findings: [MobileCreditSettlementFinding]
    ) -> MobileCreditSettlementPublicSummary {
        let proposed = proposals.filter { $0.status == .proposed }
        return MobileCreditSettlementPublicSummary(
            generatedAt: generatedAt,
            accountPublicRef: Self.stablePublicRef(prefix: "acct", source: "\(account.familySeed):\(account.childSeed)", salt: salt),
            childPublicRef: Self.stablePublicRef(prefix: "kid", source: "\(account.familySeed):\(account.childSeed)", salt: salt),
            proposalCount: proposals.count,
            proposedCount: proposed.count,
            blockedCount: proposals.filter { $0.status == .blocked }.count,
            reviewRequiredCount: proposals.filter { $0.status == .reviewRequired }.count,
            duplicateCount: proposals.filter { $0.status == .duplicate }.count,
            expiredCount: proposals.filter { $0.status == .expired }.count,
            conflictCount: proposals.filter { $0.status == .conflict }.count,
            totalProposedAmount: proposed.reduce(0) { $0 + $1.amount },
            findingCodes: findings.map { $0.code }
        )
    }

    // MARK: - 脱敏

    /// 输出可展示文本里是否仍带敏感标识（本地路径/token/局域网地址，或裸内部引用前缀）。
    static func reportLeaks(_ report: MobileCreditSettlementReport) -> Bool {
        var values: [String] = [report.headline, report.publicSummary.accountPublicRef, report.publicSummary.childPublicRef]
        for proposal in report.proposals {
            values.append(contentsOf: [proposal.reason, proposal.scopeLabel, proposal.kindLabel, proposal.statusLabel, proposal.sourceLabel])
        }
        for finding in report.findings {
            values.append(finding.message)
        }
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        // 裸内部引用前缀（哈希输出用 `prefix:token` 不会命中这些带 `-` 的原始模式）。
        let rawPatterns = [
            "(?i)\\bfamily-[a-z0-9_-]+",
            "(?i)\\bchild-[a-z0-9_-]+",
            "(?i)\\bschool-[a-z0-9_-]+",
            "(?i)\\bteacher-[a-z0-9_-]+",
            "(?i)\\bdevice-[a-z0-9_-]+",
            "(?i)\\bledger-[a-z0-9_-]+",
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
        account: MobileCreditSettlementAccount,
        generatedAt: String,
        salt: String
    ) -> MobileCreditSettlementReport {
        let acct = stablePublicRef(prefix: "acct", source: "redacted-account", salt: salt)
        let kid = stablePublicRef(prefix: "kid", source: "redacted-child", salt: salt)
        let proposal = MobileCreditSettlementProposal(
            publicProposalRef: stablePublicRef(prefix: "settlement", source: "public-summary-leak", salt: salt),
            kind: .reverse,
            status: .blocked,
            source: .familyApproval,
            childPublicRef: kid,
            accountPublicRef: acct,
            amount: 0,
            scopeLabel: "需家长批准",
            requestedAt: generatedAt,
            reason: "公开投影未通过脱敏检查，已强制阻断复核。",
            actionRequired: true,
            retryable: false
        )
        let finding = MobileCreditSettlementFinding(
            code: .publicSummaryLeak,
            severity: .blocker,
            message: "公开结算摘要未通过脱敏检查，已强制阻断复核。",
            publicRef: stablePublicRef(prefix: "settlement-finding", source: "public-summary-leak", salt: salt)
        )
        return MobileCreditSettlementReport(
            generatedAt: generatedAt,
            proposals: [proposal],
            findings: [finding],
            publicSummary: MobileCreditSettlementPublicSummary(
                generatedAt: generatedAt,
                accountPublicRef: acct,
                childPublicRef: kid,
                proposalCount: 1,
                proposedCount: 0,
                blockedCount: 1,
                reviewRequiredCount: 0,
                duplicateCount: 0,
                expiredCount: 0,
                conflictCount: 0,
                totalProposedAmount: 0,
                findingCodes: [.publicSummaryLeak]
            )
        )
    }

    /// 稳定脱敏引用（djb2，与离线层同风格）。
    static func stablePublicRef(prefix: String, source: String, salt: String = defaultSalt) -> String {
        var hash = 5381
        for scalar in "\(salt):\(source)".unicodeScalars {
            hash = ((hash << 5) &+ hash) ^ Int(scalar.value)
        }
        let value = String(UInt(bitPattern: hash), radix: 36)
        return "\(prefix):\(value)"
    }
}
