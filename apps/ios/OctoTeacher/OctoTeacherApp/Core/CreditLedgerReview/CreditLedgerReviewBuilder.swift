import Foundation

/// 成长积分账本复核台构建器（纯逻辑、无副作用、无网络、无随机、无时钟）。
///
/// 输入：查看角色、`MobileCreditSettlementReport`（B28 本地结算建议投影）与一份只读余额快照。
/// 输出：脱敏、角色门控、账本中立的 `CreditLedgerReviewConsole`。给定相同输入恒定输出。
///
/// 安全保证：
/// - 绝不写账本、发/扣成长积分、退款、释放冻结、解锁设备或发通知（输出护栏标记恒为 false）。
/// - 非家长角色看不到金额、原因、幂等/来源等内部复核信息，只看到安全状态文案。
/// - 上游若已泄露敏感标识，或本层输出未通过脱敏检查，整体降级为安全阻断态。
struct CreditLedgerReviewBuilder {
    private let generatedAt: String
    private let redactionSalt: String

    init(
        generatedAt: String = "2026-06-24T10:00:00Z",
        redactionSalt: String = "credit-ledger-review-ios-v1"
    ) {
        self.generatedAt = generatedAt
        self.redactionSalt = redactionSalt
    }

    func build(
        viewerRole: CreditLedgerReviewViewerRole,
        report: MobileCreditSettlementReport,
        balance: CreditLedgerBalanceSnapshot = .empty
    ) -> CreditLedgerReviewConsole {
        let visibility = CreditLedgerReviewVisibility.forRole(viewerRole)

        // 上游脱敏闸门：结算报告本身泄露或不安全 → 安全降级。
        if MobileCreditSettlementEngine.reportLeaks(report) || hasUnsafeInput(report: report, balance: balance) {
            return safeFallback(viewerRole: viewerRole, visibility: visibility, code: .upstreamLeak,
                                message: "上游成长积分结算投影未通过脱敏检查，复核台已降级为安全阻断态。")
        }

        let groups = buildSections(report: report, visibility: visibility)
        let findings = buildFindings(viewerRole: viewerRole, groups: groups)
        let status = statusFor(groups: groups, findings: findings)
        let summary = buildSummary(
            viewerRole: viewerRole,
            status: status,
            groups: groups,
            visibility: visibility,
            findings: findings
        )
        let console = CreditLedgerReviewConsole(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            visibility: visibility,
            balance: visibility.canSeeBalance ? balance : nil,
            sections: groups,
            findings: findings,
            summary: summary
        )

        // 本层输出脱敏自检：任何残留敏感标识 → 安全降级。
        return redacts(console) ? console : safeFallback(
            viewerRole: viewerRole,
            visibility: visibility,
            code: .publicSummaryLeak,
            message: "成长积分复核台公开投影未通过脱敏检查，已降级为安全阻断态。"
        )
    }

    // MARK: - 分组构建

    private func buildSections(
        report: MobileCreditSettlementReport,
        visibility: CreditLedgerReviewVisibility
    ) -> [CreditLedgerReviewSectionGroup] {
        // 先把每条结算建议归并到复核分组。
        var bucket: [CreditLedgerReviewSection: [CreditLedgerReviewItem]] = [:]
        if visibility.viewerRole.canReviewInternals {
            for (index, proposal) in report.proposals.enumerated() {
                let section = CreditLedgerReviewSection.from(status: proposal.status, kind: proposal.kind)
                bucket[section, default: []].append(guardianItem(proposal, section: section, order: index))
            }
        } else {
            // 非家长：每个非空分组只产出一条安全状态项，绝不暴露逐条建议或金额。
            for section in CreditLedgerReviewSection.displayOrder {
                let present = report.proposals.contains {
                    CreditLedgerReviewSection.from(status: $0.status, kind: $0.kind) == section
                }
                if present {
                    bucket[section, default: []].append(safeItem(section: section))
                }
            }
        }

        return CreditLedgerReviewSection.displayOrder.compactMap { section in
            guard let items = bucket[section], !items.isEmpty else { return nil }
            return CreditLedgerReviewSectionGroup(section: section, items: items)
        }
    }

    /// 家长复核项：携带金额、原因、来源与只读标签。
    private func guardianItem(
        _ proposal: MobileCreditSettlementProposal,
        section: CreditLedgerReviewSection,
        order: Int
    ) -> CreditLedgerReviewItem {
        CreditLedgerReviewItem(
            publicReviewRef: publicRef("review", "\(section.rawValue):\(proposal.publicProposalRef):\(order)"),
            section: section,
            kindLabel: proposal.kindLabel,
            statusLabel: proposal.statusLabel,
            childSafeStatus: section.childSafeStatus,
            reason: proposal.reason,
            amountMinutes: proposal.amount,
            sourceLabel: proposal.sourceLabel,
            originTags: originTags(for: proposal),
            actionRequired: proposal.actionRequired
        )
    }

    /// 非家长安全项：仅安全状态文案，金额/原因/来源全部隐藏。
    private func safeItem(section: CreditLedgerReviewSection) -> CreditLedgerReviewItem {
        CreditLedgerReviewItem(
            publicReviewRef: publicRef("review-safe", section.rawValue),
            section: section,
            kindLabel: section.label,
            statusLabel: section.label,
            childSafeStatus: section.childSafeStatus,
            reason: nil,
            amountMinutes: nil,
            sourceLabel: nil,
            originTags: [],
            actionRequired: false
        )
    }

    /// 只读来源标签（仅家长）：以「事实标签」呈现幂等/离线/设备/学校来源，绝不含键值、ID 或路径。
    private func originTags(for proposal: MobileCreditSettlementProposal) -> [String] {
        var tags: [String] = ["幂等已校验"]
        switch proposal.source {
        case .offlineAction:
            tags.append("离线动作")
        case .deviceRewardLifecycle:
            tags.append("设备奖励会话")
        case .schoolHomeworkMobileFlow:
            tags.append("学校作业")
        case .relativeEncouragement:
            tags.append("亲友鼓励")
        case .rewardRequest:
            tags.append("成长积分兑换请求")
        case .familyApproval:
            tags.append("家长审批")
        }
        switch proposal.status {
        case .duplicate:
            tags.append("重复/离线重放")
        case .expired:
            tags.append("冻结已过期")
        case .conflict:
            tags.append("离线/结论冲突")
        case .blocked:
            tags.append("已阻断")
        case .reviewRequired, .proposed:
            break
        }
        return tags
    }

    // MARK: - 发现项 / 状态 / 摘要

    private func buildFindings(
        viewerRole: CreditLedgerReviewViewerRole,
        groups: [CreditLedgerReviewSectionGroup]
    ) -> [CreditLedgerReviewFinding] {
        var result: [CreditLedgerReviewFinding] = []
        func push(_ code: CreditLedgerReviewFindingCode, _ severity: CreditLedgerReviewSeverity, _ message: String) {
            result.append(CreditLedgerReviewFinding(
                code: code,
                severity: severity,
                message: message,
                publicRef: publicRef("find", "\(viewerRole.rawValue):\(code.rawValue):\(result.count)")
            ))
        }

        if !viewerRole.canReviewInternals {
            push(.nonGuardianDetailHidden, .info, "已对非家长视角隐藏复核原因、金额与来源详情。")
        }
        if has(groups, .conflict) {
            push(.conflictReviewRequired, .warning, "存在结论或离线冲突，需家长复核后再定。")
        }
        if has(groups, .reviewRequired) {
            push(.reviewRequiredPresent, .warning, "存在待审核的成长积分建议，需家长复核。")
        }
        if has(groups, .blockedOrIgnored) {
            push(.blockedPresent, .warning, "存在已阻断/重复/过期的建议，不能结算为可用成长积分。")
        }
        push(.roleVisibilityApplied, .info, "已按 \(viewerRole.label) 视角应用可见性规则。")
        if !result.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            push(.consoleOK, .ok, "成长积分账本复核台只读、脱敏且无副作用。")
        }
        return result
    }

    private func statusFor(
        groups: [CreditLedgerReviewSectionGroup],
        findings: [CreditLedgerReviewFinding]
    ) -> CreditLedgerReviewStatus {
        if findings.contains(where: { $0.severity == .blocker }) { return .blocked }
        if has(groups, .conflict) { return .conflict }
        if has(groups, .reviewRequired) || has(groups, .blockedOrIgnored) { return .reviewRequired }
        if groups.allSatisfy({ $0.items.isEmpty }) || groups.isEmpty { return .empty }
        return .ready
    }

    private func buildSummary(
        viewerRole: CreditLedgerReviewViewerRole,
        status: CreditLedgerReviewStatus,
        groups: [CreditLedgerReviewSectionGroup],
        visibility: CreditLedgerReviewVisibility,
        findings: [CreditLedgerReviewFinding]
    ) -> CreditLedgerReviewSummary {
        let visibleItems = groups.flatMap { $0.items }
        let proposable = count(groups, .proposable)
        let totalMinutes = visibility.canSeeAmounts
            ? groups.first { $0.section == .proposable }?.items.reduce(0) { $0 + ($1.amountMinutes ?? 0) } ?? 0
            : 0
        return CreditLedgerReviewSummary(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: status,
            visibleItemCount: visibleItems.count,
            proposableCount: proposable,
            reviewRequiredCount: count(groups, .reviewRequired),
            frozenCount: count(groups, .frozen),
            conflictCount: count(groups, .conflict),
            refundOrRollbackCount: count(groups, .refundOrRollback),
            blockedOrIgnoredCount: count(groups, .blockedOrIgnored),
            totalProposableMinutes: totalMinutes,
            findingCodes: findings.map(\.code)
        )
    }

    // MARK: - 脱敏

    private func hasUnsafeInput(
        report: MobileCreditSettlementReport,
        balance: CreditLedgerBalanceSnapshot
    ) -> Bool {
        var values: [String] = [report.headline, balance.asOf]
        values.append(contentsOf: report.proposals.flatMap {
            [$0.reason, $0.scopeLabel, $0.kindLabel, $0.statusLabel, $0.sourceLabel]
        })
        values.append(contentsOf: report.findings.map(\.message))
        return hasUnsafeDisplayValues(values)
    }

    func redacts(_ console: CreditLedgerReviewConsole) -> Bool {
        !hasUnsafeDisplayValues(displayValues(console))
    }

    private func displayValues(_ console: CreditLedgerReviewConsole) -> [String] {
        var values = [console.generatedAt, console.headline, console.balance?.asOf ?? ""]
        values.append(contentsOf: console.sections.flatMap { group in
            group.items.flatMap { item in
                [
                    item.publicReviewRef,
                    item.kindLabel,
                    item.statusLabel,
                    item.childSafeStatus,
                    item.reason ?? "",
                    item.sourceLabel ?? ""
                ] + item.originTags
            }
        })
        values.append(contentsOf: console.findings.flatMap { [$0.publicRef, $0.message] })
        return values
    }

    private func hasUnsafeDisplayValues(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let rawPatterns = [
            "(?i)\\b(child|family|school|teacher|relative|device|ledger|proof|ref|event):[a-z0-9_-]+",
            "(?i)\\b(taskId|claimId|server-secret|device-token)\\b"
        ]
        return values.contains { value in
            rawPatterns.contains { value.range(of: $0, options: .regularExpression) != nil }
        }
    }

    private func safeFallback(
        viewerRole: CreditLedgerReviewViewerRole,
        visibility: CreditLedgerReviewVisibility,
        code: CreditLedgerReviewFindingCode,
        message: String
    ) -> CreditLedgerReviewConsole {
        let finding = CreditLedgerReviewFinding(
            code: code,
            severity: .blocker,
            message: message,
            publicRef: publicRef("find", "fallback:\(code.rawValue)")
        )
        return CreditLedgerReviewConsole(
            generatedAt: generatedAt,
            viewerRole: viewerRole,
            status: .blocked,
            visibility: visibility,
            balance: nil,
            sections: [],
            findings: [finding],
            summary: CreditLedgerReviewSummary(
                generatedAt: generatedAt,
                viewerRole: viewerRole,
                status: .blocked,
                visibleItemCount: 0,
                proposableCount: 0,
                reviewRequiredCount: 0,
                frozenCount: 0,
                conflictCount: 0,
                refundOrRollbackCount: 0,
                blockedOrIgnoredCount: 0,
                totalProposableMinutes: 0,
                findingCodes: [code]
            )
        )
    }

    // MARK: - Helpers

    private func has(_ groups: [CreditLedgerReviewSectionGroup], _ section: CreditLedgerReviewSection) -> Bool {
        count(groups, section) > 0
    }

    private func count(_ groups: [CreditLedgerReviewSectionGroup], _ section: CreditLedgerReviewSection) -> Int {
        groups.first { $0.section == section }?.items.count ?? 0
    }

    private func publicRef(_ prefix: String, _ source: String) -> String {
        var hash = 5381
        for scalar in "\(redactionSalt):\(source)".unicodeScalars {
            hash = ((hash << 5) &+ hash) ^ Int(scalar.value)
        }
        return "\(prefix)-\(String(UInt(bitPattern: hash), radix: 36))"
    }
}
