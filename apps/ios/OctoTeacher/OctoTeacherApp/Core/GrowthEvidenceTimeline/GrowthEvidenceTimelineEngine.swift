import Foundation

/// 成长证据链申诉时间线引擎（纯逻辑、无副作用、无网络、无随机、无时钟）。
///
/// 给定相同输入恒定输出。它把一条证据案件的事件按时间排序，逐条按与 B30 一致的优先级裁决链状态，
/// 投影成节点 / 公开时间线 / 成长积分控制 / 申诉裁决 / 公开摘要，并保证输出脱敏、账本中立。
///
/// 任何「不该进入可信成长积分 / 公开时间线」的情形（缺 hash、不安全负载、角色越权、老师家长冲突、
/// prevHash 不匹配、跨孩子或重复证明、重复幂等键、撤销未传播）都阻断或停留复核，绝不释放成长积分。
struct GrowthEvidenceTimelineEngine {

    private static let defaultNow = "2026-06-24T03:00:00Z"
    private static let defaultSalt = "growth-evidence-appeal-timeline-ios-v1"

    func build(
        _ input: GrowthEvidenceTimelineCaseInput,
        caseTitle: String,
        caseSummary: String,
        generatedAt: String = GrowthEvidenceTimelineEngine.defaultNow,
        salt: String = GrowthEvidenceTimelineEngine.defaultSalt
    ) -> GrowthEvidenceTimelineReport {
        let events = sortEvents(input.events)
        var seenKeys = Set(input.existingIdempotencyKeys)
        let proofIssues = proofIssueRefs(input)

        var nodes: [GrowthEvidenceTimelineNode] = []
        var publicTimeline: [GrowthEvidenceTimelinePublicItem] = []
        var creditControls: [GrowthEvidenceTimelineCreditControl] = []
        var appealDecisions: [GrowthEvidenceTimelineAppealDecision] = []
        var findings: [GrowthEvidenceTimelineFinding] = proofSubjectFindings(input, salt: salt)

        for (index, event) in events.enumerated() {
            let previous = index > 0 ? events[index - 1] : nil
            var evaluated = statusForEvent(event)

            // prevHash 链校验：与上一节点 hash 不匹配即阻断。
            if let previous, event.prevHash != previous.hash {
                evaluated.status = .blocked
                evaluated.reason = "时间线 prevHash 与上一节点 hash 不匹配，链已断，阻断复核。"
                evaluated.nextStep = "请核对证据链顺序后重建。"
                evaluated.actionRequired = true
                evaluated.hiddenFromPublic = true
                findings.append(finding(.prevHashMismatch, .blocker, evaluated.reason, seed: event.eventSeed, salt: salt))
            }

            // 重复幂等键：按重放处理，不进新投影。
            if let key = event.idempotencyKey, seenKeys.contains(key) {
                evaluated.status = .duplicate
                evaluated.reason = "重复幂等键按重放处理，不作为新的证据事件。"
                evaluated.nextStep = "无需重复提交。"
                evaluated.actionRequired = false
                evaluated.hiddenFromPublic = true
                evaluated.finding = nil
                findings.append(finding(.duplicateIdempotency, .warning, evaluated.reason, seed: event.eventSeed, salt: salt))
            } else if let key = event.idempotencyKey {
                seenKeys.insert(key)
            }

            // 单事件裁决产生的发现项（在重复重放覆盖后再追加，避免重复事件仍带原发现）。
            if let code = evaluated.finding {
                findings.append(finding(code, code.severity, evaluated.reason, seed: event.eventSeed, salt: salt))
            }

            // 跨孩子 / 跨家庭：超出案件范围即阻断。
            if event.familySeed != input.familySeed || event.childSeed != input.childSeed {
                evaluated.status = .blocked
                evaluated.reason = "时间线事件超出当前孩子或家庭范围，阻断复核。"
                evaluated.nextStep = "请核对账户范围。"
                evaluated.actionRequired = true
                evaluated.hiddenFromPublic = true
                findings.append(finding(.crossChildProofReuse, .blocker, evaluated.reason, seed: event.eventSeed, salt: salt))
            }

            // 证明跨孩子复用 / 重复：阻断。
            if let proofSeed = event.proofSeed, proofIssues.crossSubject.contains(proofSeed) {
                evaluated.status = .blocked
                evaluated.reason = "证明引用被跨孩子或跨家庭复用，不能进入时间线。"
                evaluated.nextStep = "请使用本人独立证明。"
                evaluated.actionRequired = true
                evaluated.hiddenFromPublic = true
            } else if let proofSeed = event.proofSeed, proofIssues.duplicate.contains(proofSeed) {
                evaluated.status = .blocked
                evaluated.reason = "重复证明引用在复核前不能进入时间线、成长积分或申诉投影。"
                evaluated.nextStep = "请先复核重复证明。"
                evaluated.actionRequired = true
                evaluated.hiddenFromPublic = true
            }

            let node = makeNode(input, event: event, sequence: index + 1, evaluated: evaluated, previous: previous, salt: salt)
            nodes.append(node)

            if let item = makeTimelineItem(input, node: node, event: event, salt: salt) {
                publicTimeline.append(item)
            }
            if let control = makeCreditControl(input, event: event, node: node, salt: salt) {
                creditControls.append(control)
            }
            if let decision = makeAppealDecision(input, event: event, node: node, salt: salt) {
                appealDecisions.append(decision)
            }
        }

        findings = dedupeFindings(findings)
        if !findings.contains(where: { $0.severity == .blocker }) {
            findings.append(finding(
                .chainOk,
                .info,
                "证据哈希、角色边界、申诉、成长积分控制、撤销与公开脱敏均一致。",
                seed: input.caseSeed,
                salt: salt
            ))
        }

        var report = GrowthEvidenceTimelineReport(
            generatedAt: generatedAt,
            caseTitle: caseTitle,
            caseSummary: caseSummary,
            nodes: nodes,
            publicTimeline: publicTimeline,
            creditControls: creditControls,
            appealDecisions: appealDecisions,
            findings: findings,
            publicSummary: makeSummary(
                input,
                generatedAt: generatedAt,
                salt: salt,
                nodes: nodes,
                publicTimeline: publicTimeline,
                creditControls: creditControls,
                appealDecisions: appealDecisions,
                findings: findings
            )
        )

        // 脱敏兜底：万一输出仍泄露敏感标识，整体降级为单条「已阻断」复核投影。
        if Self.reportLeaks(report, input: input) {
            report = Self.redactedFallback(input, generatedAt: generatedAt, salt: salt)
        }
        return report
    }

    // MARK: - 单事件裁决（优先级与 B30 statusForEvent 对齐）

    private struct Evaluation {
        var status: GrowthEvidenceTimelineNodeStatus
        var reason: String
        var nextStep: String
        var actionRequired: Bool
        var hiddenFromPublic: Bool
        var finding: GrowthEvidenceTimelineFindingCode?
    }

    private func statusForEvent(_ event: GrowthEvidenceTimelineEventInput) -> Evaluation {
        // 缺 hash：不可信审计证据。
        if event.hash == nil || event.hash?.isEmpty == true {
            return Evaluation(status: .blocked,
                              reason: "时间线事件缺少 hash，不能作为可信审计证据。",
                              nextStep: "补全证据 hash 后重建链。",
                              actionRequired: true, hiddenFromPublic: true, finding: .missingHash)
        }
        // 不安全负载。
        if Self.hasUnsafeProbe(event.redactionProbe) {
            return Evaluation(status: .blocked,
                              reason: "事件负载含不安全的本地、密钥、原始媒体或网络数据。",
                              nextStep: "清理敏感内容后重新提交。",
                              actionRequired: true, hiddenFromPublic: true, finding: .unsafePayload)
        }
        // 角色越权：申诉不绕过家长 / 老师边界，亲友不能审批 / 发成长积分。
        if roleBoundaryViolation(event) {
            let isRelative = event.actorRole == .relative
            return Evaluation(status: .blocked,
                              reason: isRelative
                                ? "亲友不能执行该证据时间线操作（审批 / 发成长积分 / 撤销越权）。"
                                : "该角色不能执行此证据时间线操作。",
                              nextStep: "请由有权限的家长 / 老师处理。",
                              actionRequired: true,
                              hiddenFromPublic: event.actorRole != .child,
                              finding: isRelative ? .relativePermissionBlocked : .roleBoundaryViolation)
        }
        // 老师 / 家长结论冲突。
        if teacherGuardianConflict(event) {
            return Evaluation(status: .conflict,
                              reason: "老师与家长结论冲突，时间线停留成人复核。",
                              nextStep: "请家长与老师对齐结论后再裁决。",
                              actionRequired: true, hiddenFromPublic: true, finding: .teacherGuardianConflict)
        }
        // 亲友鼓励待家长复核。
        if event.kind == .relativeEncouraged && event.guardianReview != .approved {
            return Evaluation(status: .reviewRequired,
                              reason: "亲友鼓励需家长复核通过后才对孩子或公开可见。",
                              nextStep: "等待家长复核亲友鼓励。",
                              actionRequired: true, hiddenFromPublic: true, finding: .relativeReviewRequired)
        }
        // 成长积分建议：结论一致才可释放（仍只是建议），否则冻结。
        if event.kind == .creditSuggested {
            if event.teacherConclusion == .approved && event.guardianConclusion == .approved {
                return Evaluation(status: .released,
                                  reason: "老师与家长结论一致，可作为账本中立的成长积分释放建议。",
                                  nextStep: "交家长流程审核后再决定是否结算。",
                                  actionRequired: false, hiddenFromPublic: true, finding: .creditReleaseAllowed)
            }
            return Evaluation(status: .frozen,
                              reason: "成长积分建议在申诉与成人验证完成前保持冻结。",
                              nextStep: "等待老师 / 家长结论对齐。",
                              actionRequired: true, hiddenFromPublic: true, finding: .creditFreezeRequired)
        }
        // 发起申诉：相关成长积分冻结。
        if event.kind == .appealOpened {
            return Evaluation(status: .frozen,
                              reason: "申诉已发起，相关成长积分冻结，等待家长或老师复核。",
                              nextStep: "等待申诉复核结果。",
                              actionRequired: true, hiddenFromPublic: false, finding: .creditFreezeRequired)
        }
        // 申诉裁决：恢复或驳回。
        if event.kind == .appealResolved {
            if event.decision == .restored || event.decision == .approved {
                return Evaluation(status: .restored,
                                  reason: "申诉恢复，成长积分可作为后续账本中立结算建议释放。",
                                  nextStep: "交家长流程审核后再结算。",
                                  actionRequired: false, hiddenFromPublic: false, finding: .appealRestored)
            }
            return Evaluation(status: .rejected,
                              reason: "申诉被驳回，成长积分保持阻断。",
                              nextStep: "可按反馈重做后重新提交证据。",
                              actionRequired: false, hiddenFromPublic: false, finding: .appealRejected)
        }
        // 撤销：必须传播到全部下游面。
        if event.kind == .revoked {
            let propagated = event.revocation?.isFullyPropagated ?? false
            return Evaluation(status: .revoked,
                              reason: propagated
                                ? "证据撤销已投影，全部下游展示均收回。"
                                : "证据撤销未传播到全部下游面，仍需收回时间线 / 成长积分 / 动态 / 作业 / 亲友可见。",
                              nextStep: propagated ? "无需进一步操作。" : "请收回全部下游展示后再确认。",
                              actionRequired: !propagated, hiddenFromPublic: true,
                              finding: propagated ? nil : .revocationNotPropagated)
        }
        // 默认：已接受的只读审计投影。
        return Evaluation(status: .accepted,
                          reason: "证据时间线事件作为只读审计投影记录。",
                          nextStep: "继续推进成长证据链。",
                          actionRequired: false, hiddenFromPublic: false, finding: nil)
    }

    /// 角色 → 允许事件类型（与 B30 allowedByRole 对齐）。
    private func roleBoundaryViolation(_ event: GrowthEvidenceTimelineEventInput) -> Bool {
        let allowed: [GrowthEvidenceTimelineActorRole: [GrowthEvidenceTimelineEventKind]] = [
            .child: [.childSubmitted, .appealOpened],
            .guardian: [.guardianConfirmed, .appealOpened, .appealResolved, .revoked, .timelinePublished, .creditSuggested],
            .teacher: [.teacherVerified],
            .relative: [.relativeEncouraged],
            .system: [.creditSuggested, .revoked, .timelinePublished]
        ]
        return !(allowed[event.actorRole]?.contains(event.kind) ?? false)
    }

    private func teacherGuardianConflict(_ event: GrowthEvidenceTimelineEventInput) -> Bool {
        guard let teacher = event.teacherConclusion, let guardian = event.guardianConclusion else { return false }
        return teacher != guardian
    }

    // MARK: - 构建节点与投影

    private func makeNode(
        _ input: GrowthEvidenceTimelineCaseInput,
        event: GrowthEvidenceTimelineEventInput,
        sequence: Int,
        evaluated: Evaluation,
        previous: GrowthEvidenceTimelineEventInput?,
        salt: String
    ) -> GrowthEvidenceTimelineNode {
        GrowthEvidenceTimelineNode(
            publicEventRef: publicRef(input, prefix: "timeline-event", source: event.eventSeed, salt: salt),
            prevPublicEventRef: previous.map { publicRef(input, prefix: "timeline-event", source: $0.eventSeed, salt: salt) },
            sequence: sequence,
            kind: event.kind,
            actorRole: event.actorRole,
            occurredAt: event.occurredAt,
            status: evaluated.status,
            childPublicRef: publicRef(input, prefix: "kid", source: event.childSeed, salt: salt),
            proofPublicRef: event.proofSeed.map { publicRef(input, prefix: "pf", source: $0, salt: salt) },
            appealPublicRef: event.appealSeed.map { publicRef(input, prefix: "apl", source: $0, salt: salt) },
            title: event.title,
            hashPresent: !(event.hash ?? "").isEmpty,
            actionRequired: evaluated.actionRequired,
            hiddenFromPublic: evaluated.hiddenFromPublic,
            reason: evaluated.reason,
            nextStep: evaluated.nextStep
        )
    }

    private func makeTimelineItem(
        _ input: GrowthEvidenceTimelineCaseInput,
        node: GrowthEvidenceTimelineNode,
        event: GrowthEvidenceTimelineEventInput,
        salt: String
    ) -> GrowthEvidenceTimelinePublicItem? {
        if node.hiddenFromPublic || node.status == .blocked || node.status == .conflict || node.status == .duplicate {
            return nil
        }
        if event.kind == .relativeEncouraged && event.guardianReview != .approved { return nil }
        let visibility = event.visibility ?? (event.kind == .timelinePublished ? .family : .private)
        return GrowthEvidenceTimelinePublicItem(
            publicItemRef: publicRef(input, prefix: "growth-timeline-item", source: "\(event.eventSeed):\(node.status.rawValue)", salt: salt),
            sourceEventPublicRef: node.publicEventRef,
            sequence: node.sequence,
            kind: node.kind,
            occurredAt: node.occurredAt,
            status: node.status,
            summary: summaryForNode(node),
            visibility: visibility
        )
    }

    private func summaryForNode(_ node: GrowthEvidenceTimelineNode) -> String {
        switch node.kind {
        case .childSubmitted: return "孩子提交了证据等待复核。"
        case .teacherVerified: return "已记录老师验证。"
        case .guardianConfirmed: return "已记录家长确认。"
        case .relativeEncouraged: return "亲友鼓励经家长复核后进入成长时间线。"
        case .creditSuggested: return node.status == .released ? "成长积分建议待后续结算复核。" : "成长积分建议已冻结。"
        case .appealOpened: return "已发起申诉，证据保留。"
        case .appealResolved: return node.status == .restored ? "申诉恢复了证据结论。" : "申诉驳回了证据结论。"
        case .revoked: return "证据已从公开成长展示收回。"
        case .timelinePublished: return "成长时间线展示已投影（未真实发布）。"
        }
    }

    private func makeCreditControl(
        _ input: GrowthEvidenceTimelineCaseInput,
        event: GrowthEvidenceTimelineEventInput,
        node: GrowthEvidenceTimelineNode,
        salt: String
    ) -> GrowthEvidenceTimelineCreditControl? {
        if node.status == .duplicate { return nil }
        let amount = max(0, event.creditAmount)

        if node.status == .blocked &&
            (event.kind == .appealOpened || event.kind == .appealResolved
                || event.kind == .creditSuggested || event.kind == .revoked) {
            return control(input, source: event.appealSeed ?? event.creditSuggestionSeed ?? event.proofSeed ?? event.eventSeed,
                           node: node, state: .blocked, amount: amount,
                           reason: "已阻断证据不能释放或冻结可信成长积分建议。", salt: salt)
        }
        switch event.kind {
        case .appealOpened:
            return control(input, source: event.appealSeed ?? event.eventSeed, node: node, state: .frozen, amount: amount,
                           reason: "申诉发起冻结相关成长积分建议，直到人工复核完成。", salt: salt)
        case .appealResolved:
            let restored = event.decision == .restored || event.decision == .approved
            return control(input, source: event.appealSeed ?? event.eventSeed, node: node,
                           state: restored ? .released : .blocked, amount: amount,
                           reason: restored ? "申诉裁决可释放后续成长积分结算建议。" : "申诉驳回保持成长积分阻断。", salt: salt)
        case .creditSuggested:
            return control(input, source: event.creditSuggestionSeed ?? event.eventSeed, node: node,
                           state: node.status == .released ? .released : .frozen, amount: amount,
                           reason: node.status == .released
                            ? "成长积分建议作为只读结算输入释放。" : "成长积分建议在成人结论对齐前保持冻结。", salt: salt)
        case .revoked:
            return control(input, source: event.proofSeed ?? event.eventSeed, node: node, state: .blocked, amount: amount,
                           reason: "撤销证据阻断下游成长积分结算建议。", salt: salt)
        default:
            return nil
        }
    }

    private func control(
        _ input: GrowthEvidenceTimelineCaseInput,
        source: String,
        node: GrowthEvidenceTimelineNode,
        state: GrowthEvidenceTimelineCreditControl.State,
        amount: Int,
        reason: String,
        salt: String
    ) -> GrowthEvidenceTimelineCreditControl {
        GrowthEvidenceTimelineCreditControl(
            publicCreditRef: publicRef(input, prefix: "credit-control", source: source, salt: salt),
            sourceEventPublicRef: node.publicEventRef,
            state: state,
            amount: amount,
            reason: reason
        )
    }

    private func makeAppealDecision(
        _ input: GrowthEvidenceTimelineCaseInput,
        event: GrowthEvidenceTimelineEventInput,
        node: GrowthEvidenceTimelineNode,
        salt: String
    ) -> GrowthEvidenceTimelineAppealDecision? {
        guard event.kind == .appealOpened || event.kind == .appealResolved else { return nil }
        if node.status == .blocked || node.status == .duplicate { return nil }
        let restored = event.kind == .appealResolved && (event.decision == .restored || event.decision == .approved)
        let rejected = event.kind == .appealResolved && !restored
        let state: GrowthEvidenceTimelineAppealDecision.State = restored ? .restored : (rejected ? .rejected : .open)
        let creditState: GrowthEvidenceTimelineCreditControl.State = restored ? .released : (rejected ? .blocked : .frozen)
        return GrowthEvidenceTimelineAppealDecision(
            publicAppealRef: publicRef(input, prefix: "apl", source: event.appealSeed ?? event.eventSeed, salt: salt),
            sourceEventPublicRef: node.publicEventRef,
            state: state,
            creditState: creditState,
            actionRequired: event.kind == .appealOpened
        )
    }

    // MARK: - 证明重复 / 跨孩子检测

    private func proofIssueRefs(_ input: GrowthEvidenceTimelineCaseInput) -> (duplicate: Set<String>, crossSubject: Set<String>) {
        var owners: [String: Set<String>] = [:]
        var counts: [String: Int] = [:]
        let baseSubject = "\(input.familySeed):\(input.childSeed)"

        for proof in input.existingProofSeeds {
            owners[proof, default: []].insert(baseSubject)
            counts[proof, default: 0] += 1
        }
        for event in input.events {
            guard let proof = event.proofSeed else { continue }
            owners[proof, default: []].insert("\(event.familySeed):\(event.childSeed)")
            counts[proof, default: 0] += 1
        }

        let duplicate = Set(counts.filter { $0.value > 1 }.map { $0.key })
        let crossSubject = Set(owners.filter { $0.value.count > 1 }.map { $0.key })
        return (duplicate, crossSubject)
    }

    private func proofSubjectFindings(_ input: GrowthEvidenceTimelineCaseInput, salt: String) -> [GrowthEvidenceTimelineFinding] {
        let issues = proofIssueRefs(input)
        var findings: [GrowthEvidenceTimelineFinding] = []
        for proof in issues.duplicate.sorted() {
            findings.append(finding(.duplicateProof, .blocker,
                                    "同一证明引用出现多次，奖励或时间线使用前必须复核。", seed: proof, salt: salt))
        }
        for proof in issues.crossSubject.sorted() {
            findings.append(finding(.crossChildProofReuse, .blocker,
                                    "同一证明引用被跨孩子或跨家庭复用。", seed: proof, salt: salt))
        }
        return findings
    }

    // MARK: - 摘要

    private func makeSummary(
        _ input: GrowthEvidenceTimelineCaseInput,
        generatedAt: String,
        salt: String,
        nodes: [GrowthEvidenceTimelineNode],
        publicTimeline: [GrowthEvidenceTimelinePublicItem],
        creditControls: [GrowthEvidenceTimelineCreditControl],
        appealDecisions: [GrowthEvidenceTimelineAppealDecision],
        findings: [GrowthEvidenceTimelineFinding]
    ) -> GrowthEvidenceTimelinePublicSummary {
        GrowthEvidenceTimelinePublicSummary(
            generatedAt: generatedAt,
            publicCaseRef: publicRef(input, prefix: "growth-case", source: input.caseSeed, salt: salt),
            childPublicRef: publicRef(input, prefix: "kid", source: input.childSeed, salt: salt),
            eventCount: nodes.count,
            publicTimelineCount: publicTimeline.count,
            appealCount: appealDecisions.count,
            creditFrozenCount: creditControls.filter { $0.state == .frozen }.count,
            creditReleasedCount: creditControls.filter { $0.state == .released }.count,
            creditBlockedCount: creditControls.filter { $0.state == .blocked }.count,
            findingCodes: findings.map { $0.code }
        )
    }

    // MARK: - 脱敏引用 / 发现项

    private func publicRef(_ input: GrowthEvidenceTimelineCaseInput, prefix: String, source: String, salt: String) -> String {
        Self.stablePublicRef(prefix: prefix, source: "\(input.caseSeed):\(input.familySeed):\(input.childSeed):\(source)", salt: salt)
    }

    private func finding(
        _ code: GrowthEvidenceTimelineFindingCode,
        _ severity: GrowthEvidenceTimelineSeverity,
        _ message: String,
        seed: String,
        salt: String
    ) -> GrowthEvidenceTimelineFinding {
        GrowthEvidenceTimelineFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: Self.stablePublicRef(prefix: "timeline-finding", source: "\(code.rawValue):\(seed)", salt: salt)
        )
    }

    private func dedupeFindings(_ findings: [GrowthEvidenceTimelineFinding]) -> [GrowthEvidenceTimelineFinding] {
        var seen = Set<String>()
        var result: [GrowthEvidenceTimelineFinding] = []
        for item in findings where seen.insert(item.id).inserted {
            result.append(item)
        }
        return result
    }

    private func sortEvents(_ events: [GrowthEvidenceTimelineEventInput]) -> [GrowthEvidenceTimelineEventInput] {
        // ISO8601 UTC 字符串按字典序即等于时间序，避免引入时钟 / 日期解析。
        events.sorted { left, right in
            if left.occurredAt != right.occurredAt { return left.occurredAt < right.occurredAt }
            return left.eventSeed < right.eventSeed
        }
    }

    // MARK: - 脱敏守卫

    /// 输出可展示文本里是否仍带敏感标识（本地路径 / token / 局域网地址，或裸内部引用前缀 / 原始输入 seed）。
    static func reportLeaks(_ report: GrowthEvidenceTimelineReport, input: GrowthEvidenceTimelineCaseInput? = nil) -> Bool {
        var values: [String] = [
            report.caseTitle, report.caseSummary, report.childHeadline, report.parentHeadline,
            report.publicSummary.publicCaseRef, report.publicSummary.childPublicRef
        ]
        for node in report.nodes {
            values.append(contentsOf: [node.title, node.reason, node.nextStep, node.kindLabel,
                                       node.actorLabel, node.statusLabel, node.publicEventRef,
                                       node.prevPublicEventRef ?? "", node.childPublicRef,
                                       node.proofPublicRef ?? "", node.appealPublicRef ?? ""])
        }
        for item in report.publicTimeline {
            values.append(contentsOf: [item.summary, item.publicItemRef, item.sourceEventPublicRef, item.visibilityLabel])
        }
        for control in report.creditControls {
            values.append(contentsOf: [control.reason, control.publicCreditRef, control.sourceEventPublicRef])
        }
        for decision in report.appealDecisions {
            values.append(contentsOf: [decision.publicAppealRef, decision.sourceEventPublicRef])
        }
        for finding in report.findings {
            values.append(contentsOf: [finding.message, finding.publicRef])
        }

        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let rawPatterns = [
            "(?i)\\bfamily-[a-z0-9_-]+",
            "(?i)\\bchild-[a-z0-9_-]+",
            "(?i)\\bschool-[a-z0-9_-]+",
            "(?i)\\bteacher-[a-z0-9_-]+",
            "(?i)\\brelative-[a-z0-9_-]+",
            "(?i)\\bguardian-[a-z0-9_-]+",
            "(?i)\\bhomework-[a-z0-9_-]+",
            "(?i)\\bproof-[a-z0-9_-]+",
            "(?i)\\bmedia-[a-z0-9_-]+",
            "(?i)\\bledger-[a-z0-9_-]+",
            "(?i)\\b(?:child|family|school|teacher|relative|guardian|homework|proof|media|ledger|ref|token|path):[a-z0-9_-]+",
            "(?i)\\b(?:taskId|claimId)\\b"
        ]
        for value in values {
            for pattern in rawPatterns where value.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        // 原始输入 seed 不应原样出现在输出里。
        if let input {
            let serialized = values.joined(separator: " ")
            for sensitive in collectSensitiveValues(input) where serialized.contains(sensitive) {
                return true
            }
        }
        return false
    }

    private static func collectSensitiveValues(_ input: GrowthEvidenceTimelineCaseInput) -> [String] {
        var values: [String] = [input.familySeed, input.childSeed, input.caseSeed]
        values.append(contentsOf: input.existingProofSeeds)
        values.append(contentsOf: input.existingIdempotencyKeys)
        for event in input.events {
            values.append(contentsOf: [event.eventSeed, event.familySeed, event.childSeed, event.actorSeed,
                                       event.proofSeed ?? "", event.appealSeed ?? "",
                                       event.creditSuggestionSeed ?? "", event.idempotencyKey ?? ""])
        }
        return values.filter { $0.count >= 5 }
    }

    private static func hasUnsafeProbe(_ probe: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(probe) { return true }
        return probe.contains { value in
            value.range(of: "(?i)\\b(taskId|claimId)\\b", options: .regularExpression) != nil
        }
    }

    private static func redactedFallback(
        _ input: GrowthEvidenceTimelineCaseInput,
        generatedAt: String,
        salt: String
    ) -> GrowthEvidenceTimelineReport {
        let caseRef = stablePublicRef(prefix: "growth-case", source: "public-summary-leak", salt: salt)
        let kid = stablePublicRef(prefix: "kid", source: "redacted-child", salt: salt)
        let node = GrowthEvidenceTimelineNode(
            publicEventRef: stablePublicRef(prefix: "timeline-event", source: "public-summary-leak", salt: salt),
            prevPublicEventRef: nil,
            sequence: 1,
            kind: .timelinePublished,
            actorRole: .system,
            occurredAt: generatedAt,
            status: .blocked,
            childPublicRef: kid,
            proofPublicRef: nil,
            appealPublicRef: nil,
            title: "成长证据时间线",
            hashPresent: false,
            actionRequired: true,
            hiddenFromPublic: true,
            reason: "公开证据时间线投影未通过脱敏检查，已强制阻断复核。",
            nextStep: "请联系家长复核。"
        )
        let finding = GrowthEvidenceTimelineFinding(
            code: .publicSummaryLeak,
            severity: .blocker,
            message: "公开证据时间线摘要未通过脱敏检查，已强制阻断复核。",
            publicRef: stablePublicRef(prefix: "timeline-finding", source: "public-summary-leak", salt: salt)
        )
        return GrowthEvidenceTimelineReport(
            generatedAt: generatedAt,
            caseTitle: "成长证据时间线",
            caseSummary: "公开投影已脱敏阻断。",
            nodes: [node],
            publicTimeline: [],
            creditControls: [],
            appealDecisions: [],
            findings: [finding],
            publicSummary: GrowthEvidenceTimelinePublicSummary(
                generatedAt: generatedAt,
                publicCaseRef: caseRef,
                childPublicRef: kid,
                eventCount: 1,
                publicTimelineCount: 0,
                appealCount: 0,
                creditFrozenCount: 0,
                creditReleasedCount: 0,
                creditBlockedCount: 0,
                findingCodes: [.publicSummaryLeak]
            )
        )
    }

    /// 稳定脱敏引用（djb2，与离线 / 成长积分结算 / 运行结算层同风格）。
    static func stablePublicRef(prefix: String, source: String, salt: String = defaultSalt) -> String {
        var hash = 5381
        for scalar in "\(salt):\(source)".unicodeScalars {
            hash = ((hash << 5) &+ hash) ^ Int(scalar.value)
        }
        let value = String(UInt(bitPattern: hash), radix: 36)
        return "\(prefix):\(value)"
    }
}
