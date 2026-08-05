import Foundation

/// AI 小伙伴接入云端模型前的本地隐私网关。
///
/// 这一层只生成「可发送草稿」，不直接联网、不读取密钥、不调用服务商。
/// 草稿只包含意图、风险标签、策略边界和极少量上下文，禁止孩子原话、姓名、
/// provider 细节、URL、密钥或本地文件路径进入云端 prompt。
struct AICompanionCloudRequestDraft: Equatable {
    var systemPrompt: String
    var userPrompt: String
    var mode: AICompanionMode
    var latestIntent: AICompanionIntent
    var riskLabels: [AICompanionRiskLabel]
    var isProviderRequestAllowed: Bool
    var blockReason: String?
    var publicSummary: AICompanionCloudRequestPublicSummary
}

struct AICompanionCloudRequestPublicSummary: Equatable {
    var wouldCallAiProvider: Bool
    var blockedBeforeProvider: Bool
    var messageCount: Int
    var riskLabelCount: Int
    var findingCodes: [AICompanionFindingCode]

    let callsNetwork = false
    let storesRawTranscript = false
    let includesChildName = false
    let includesApiKey = false
    let givesFinalAnswer = false
}

struct AICompanionPrivacyGateway {
    func makeDraft(input: AICompanionInput, snapshot: AICompanionSnapshot) -> AICompanionCloudRequestDraft {
        let latestIntent = input.messages.last?.intent ?? defaultIntent(for: input.mode)
        let riskLabels = mergedRiskLabels(snapshot: snapshot, intents: input.messages.map(\.intent))
        let shouldBlock = shouldBlockBeforeProvider(input: input, snapshot: snapshot, riskLabels: riskLabels)
        let systemPrompt = shouldBlock ? "" : systemPrompt(for: latestIntent, riskLabels: riskLabels)
        let userPrompt = shouldBlock ? "" : userPrompt(input: input, latestIntent: latestIntent, riskLabels: riskLabels)
        let promptValues = [systemPrompt, userPrompt]
        let promptIsSafe = !MobileSyncPayloadGuard.isUnsafe(promptValues)
            && !containsAny(promptValues.joined(separator: " "), [
                input.childName,
                "provider:",
                "model:",
                "api_key",
                "sk-",
                "http://",
                "https://",
                "file://",
                "孩子原话",
                "transcript"
            ])
        let isAllowed = !shouldBlock && promptIsSafe
        let findingCodes = findingCodes(
            snapshot: snapshot,
            latestIntent: latestIntent,
            riskLabels: riskLabels,
            isAllowed: isAllowed
        )

        return AICompanionCloudRequestDraft(
            systemPrompt: isAllowed ? systemPrompt : "",
            userPrompt: isAllowed ? userPrompt : "",
            mode: input.mode,
            latestIntent: latestIntent,
            riskLabels: riskLabels,
            isProviderRequestAllowed: isAllowed,
            blockReason: isAllowed ? nil : blockReason(
                snapshot: snapshot,
                latestIntent: latestIntent,
                riskLabels: riskLabels
            ),
            publicSummary: AICompanionCloudRequestPublicSummary(
                wouldCallAiProvider: isAllowed,
                blockedBeforeProvider: !isAllowed,
                messageCount: input.messages.count,
                riskLabelCount: riskLabels.count,
                findingCodes: findingCodes
            )
        )
    }

    private func systemPrompt(for latestIntent: AICompanionIntent, riskLabels: [AICompanionRiskLabel]) -> String {
        let riskLine = riskLabels.isEmpty ? "none" : riskLabels.map(\.rawValue).joined(separator: ",")
        return """
        You are OctoTeacher's child AI companion. Reply in concise zh-CN JSON.
        Safety policy: guide with questions and next steps; never provide final homework answers or ghostwrite.
        Emotional policy: validate feelings first, then suggest one small action.
        Privacy policy: do not ask for or repeat names, school, address, contact details, provider details, URLs, files, or secrets.
        Guardian policy: if the child needs a trusted adult, tell the child to find one immediately.
        Latest intent: \(latestIntent.rawValue). Risk labels: \(riskLine).
        JSON keys: reply, next_questions, guardian_signal.
        """
    }

    private func userPrompt(
        input: AICompanionInput,
        latestIntent: AICompanionIntent,
        riskLabels: [AICompanionRiskLabel]
    ) -> String {
        let taskPresence = input.nextTaskTitle == nil ? "none" : "has_one_active_task"
        let risks = riskLabels.isEmpty ? "none" : riskLabels.map(\.rawValue).joined(separator: ",")
        return """
        mode=\(input.mode.rawValue)
        latest_intent=\(latestIntent.rawValue)
        risk_labels=\(risks)
        child_message_count=\(input.messages.count)
        next_task_presence=\(taskPresence)
        request=Give one child-facing guidance reply and up to two short questions. Do not solve the work.
        """
    }

    private func shouldBlockBeforeProvider(
        input: AICompanionInput,
        snapshot: AICompanionSnapshot,
        riskLabels: [AICompanionRiskLabel]
    ) -> Bool {
        input.messages.contains(where: \.containsUnsafeInput)
            || snapshot.status == .blocked
            || riskLabels.contains(.highRisk)
            || (input.messages.last?.intent == .highRisk)
            || (input.messages.last?.intent == .askTrustedAdult)
    }

    private func blockReason(
        snapshot: AICompanionSnapshot,
        latestIntent: AICompanionIntent,
        riskLabels: [AICompanionRiskLabel]
    ) -> String {
        if riskLabels.contains(.highRisk)
            || snapshot.status == .needsTrustedAdult
            || latestIntent == .askTrustedAdult
            || latestIntent == .highRisk {
            return "需要可信大人介入，本地安全规则已阻止发送给云端模型。"
        }
        return "本地隐私网关发现敏感内容，已阻止发送给云端模型。"
    }

    private func defaultIntent(for mode: AICompanionMode) -> AICompanionIntent {
        switch mode {
        case .nextStep: return .findNextStep
        case .homework: return .homeworkStuck
        case .emotion: return .emotionalSupport
        }
    }

    private func containsAny(_ value: String, _ blocked: [String]) -> Bool {
        blocked
            .filter { !$0.isEmpty }
            .contains { value.localizedCaseInsensitiveContains($0) }
    }

    private func mergedRiskLabels(snapshot: AICompanionSnapshot, intents: [AICompanionIntent]) -> [AICompanionRiskLabel] {
        var labels = snapshot.careSummary?.riskLabels ?? []
        labels.append(contentsOf: localRiskLabels(for: intents))
        return AICompanionRiskLabel.allCases.filter { labels.contains($0) }
    }

    private func localRiskLabels(for intents: [AICompanionIntent]) -> [AICompanionRiskLabel] {
        var labels: [AICompanionRiskLabel] = []
        if intents.contains(.wantsDirectAnswer) { labels.append(.directAnswer) }
        if intents.filter({ $0 == .homeworkStuck }).count >= 2 { labels.append(.repeatedStuck) }
        if intents.contains(.emotionalSupport) { labels.append(.emotionalDistress) }
        if intents.contains(.highRisk) { labels.append(.highRisk) }
        return labels
    }

    private func findingCodes(
        snapshot: AICompanionSnapshot,
        latestIntent: AICompanionIntent,
        riskLabels: [AICompanionRiskLabel],
        isAllowed: Bool
    ) -> [AICompanionFindingCode] {
        var result = snapshot.findings
        if latestIntent == .wantsDirectAnswer && !result.contains(.directAnswerRedirected) {
            result.append(.directAnswerRedirected)
        }
        if riskLabels.contains(.highRisk) && !result.contains(.trustedAdultNeeded) {
            result.append(.trustedAdultNeeded)
        }
        if !isAllowed && !result.contains(.redactionFallback) {
            result.append(.redactionFallback)
        }
        if result.isEmpty { result.append(.ready) }
        return result
    }
}
