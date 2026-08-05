import Foundation

/// iOS 端「今日任务包工作台」只读读取模型（孩子视角）。
///
/// 把 `LocalFamilyStore` 已有的今日任务、成长包步骤、证明要求、任务状态、待确认成长积分和
/// 可用成长积分，编排成一个孩子视角、脱敏、无副作用的任务包工作台。它只服务展示：
/// 不发成长积分、不扣成长积分、不批准/驳回任务、不解锁设备、不写账本、不上传媒体、不发通知，
/// 也不接任何真实网络/云/AI/LMS/学校系统。
///
/// 安全边界：
/// - 孩子视角文案绝不出现「家长批准」「发成长积分」「审批」等成人语义，只说「等大人看看」「成长积分」。
/// - 公开字段只暴露脱敏 `kind:hash` 引用与计数，绝不暴露真实 taskId、claimId、child/family/pack/ledger 等内部 ID。
/// - 任意展示字符串若命中敏感模式（token、文件路径、局域网地址等），整体降级为安全空壳。

// MARK: - 任务卡状态

/// 孩子视角的任务卡运行态。命名与文案都避免成人审批/发成长积分语义。
enum MobileTodayTaskCardState: String, Equatable, CaseIterable {
    /// 前面的步骤还没完成，本步暂时锁住。
    case locked
    /// 可以现在开始做。
    case active
    /// 已经交给大人看看，等待确认。
    case waitingCheck = "waiting_check"
    /// 已经完成。
    case done
    /// 需要再试一次（被退回，但不暴露成人驳回语义细节）。
    case redo

    /// 孩子友好的状态短语。
    var label: String {
        switch self {
        case .locked: return "待解锁"
        case .active: return "可以开始"
        case .waitingCheck: return "等待确认"
        case .done: return "已完成"
        case .redo: return "再试一次"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .locked: return "Locked"
        case .active: return "Ready"
        case .waitingCheck: return "Waiting for check"
        case .done: return "Done"
        case .redo: return "Try again"
        }
    }

    var systemImage: String {
        switch self {
        case .locked: return "lock.fill"
        case .active: return "circle"
        case .waitingCheck: return "hourglass"
        case .done: return "checkmark.circle.fill"
        case .redo: return "arrow.counterclockwise.circle"
        }
    }
}

/// 证明要求的孩子友好描述。照片只存本机，不上传。
enum MobileTodayTaskProofRequirement: String, Equatable {
    case text
    case photoPlaceholder = "photo_placeholder"
    case photo

    var label: String {
        switch self {
        case .text: return "写一句话"
        case .photoPlaceholder: return "拍照或相册证明"
        case .photo: return "拍一张照片"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .text: return "Say or write one sentence"
        case .photoPlaceholder, .photo: return "Take a photo"
        }
    }

    var hint: String {
        switch self {
        case .text: return "写一句话告诉大人你做了什么。"
        case .photoPlaceholder: return "拍一张照片，或从相册选一张，只保存在这台手机上。"
        case .photo: return "拍好照片后从相册选一张，只保存在这台手机上。"
        }
    }

    func hint(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return hint }
        switch self {
        case .text: return "Write one sentence telling a grown-up what you did."
        case .photoPlaceholder: return "Take a photo or pick one from your album; it stays on this phone only."
        case .photo: return "Take a photo, then pick it from your album; it stays on this phone only."
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .photoPlaceholder: return "photo"
        case .photo: return "camera"
        }
    }
}

/// 单张今日任务卡（脱敏、只读）。
struct MobileTodayTaskCard: Identifiable, Equatable {
    /// 脱敏任务引用，绝不是真实 taskId。
    var publicTaskRef: String
    var order: Int
    var title: String
    var categoryLabel: String
    var state: MobileTodayTaskCardState
    var proof: MobileTodayTaskProofRequirement
    /// 完成这一步可获得的成长积分。字段名沿用 rewardMinutes 兼容旧账本。
    var rewardMinutes: Int
    /// 下一步建议（孩子友好）。
    var nextStep: String
    /// 成长积分建议（孩子友好，不含发成长积分语义）。
    var creditHint: String

    var id: String { publicTaskRef }
}

// MARK: - 状态计数

/// 今日任务包各状态计数。
struct MobileTodayTaskPackageCounts: Equatable {
    var total: Int
    var locked: Int
    var active: Int
    var waitingCheck: Int
    var done: Int
    var redo: Int

    static let empty = MobileTodayTaskPackageCounts(
        total: 0, locked: 0, active: 0, waitingCheck: 0, done: 0, redo: 0
    )

    /// 是否所有任务都已完成。
    var allDone: Bool { total > 0 && done == total }
}

// MARK: - 成长积分摘要（孩子视角）

/// 孩子视角的成长积分摘要。只展示「可用」「等待确认」「已获得」，绝不暴露账本写入语义。
struct MobileTodayTaskCreditSummary: Equatable {
    /// 当前可用成长积分。
    var availableMinutes: Int
    /// 已交给大人、正在等待确认的成长积分。
    var pendingMinutes: Int
    /// 累计已获得的成长积分。
    var lifetimeEarnedMinutes: Int

    /// 只读读取模型恒为真：绝不写账本。
    let writesLedger = false

    var headline: String {
        if pendingMinutes > 0 {
            return "可用 \(availableMinutes) 成长积分，还有 \(pendingMinutes) 积分等待确认"
        }
        return "可用 \(availableMinutes) 成长积分"
    }

    func headline(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return headline }
        if pendingMinutes > 0 {
            return "\(availableMinutes) Growth Points available, \(pendingMinutes) waiting for check"
        }
        return "\(availableMinutes) Growth Points available"
    }
}

// MARK: - 离线安全提示

/// 离线队列安全提示（孩子友好、脱敏）。
struct MobileTodayTaskOfflineHint: Equatable {
    var pendingCount: Int
    var title: String
    var message: String

    /// 只读读取模型恒为假：绝不发通知、不解锁设备。
    let sendsNotification = false
    let unlocksDevice = false

    var hasPending: Bool { pendingCount > 0 }
}

// MARK: - 发现项

enum MobileTodayTaskFindingCode: String, Equatable {
    case workbenchOK = "TODAY_PACKAGE_OK"
    case emptyToday = "TODAY_PACKAGE_EMPTY"
    case redoNeeded = "TODAY_PACKAGE_REDO_NEEDED"
    case offlinePending = "TODAY_PACKAGE_OFFLINE_PENDING"
    case publicSummaryLeak = "TODAY_PACKAGE_PUBLIC_SUMMARY_LEAK"
}

enum MobileTodayTaskFindingSeverity: String, Equatable {
    case info
    case warning
    case ok
    case blocker
}

struct MobileTodayTaskFinding: Identifiable, Equatable {
    var code: MobileTodayTaskFindingCode
    var severity: MobileTodayTaskFindingSeverity
    var message: String
    var publicRef: String

    var id: String { "\(code.rawValue):\(publicRef)" }
}

// MARK: - 公开摘要

/// 工作台的脱敏公开摘要：只暴露计数、状态与发现码，绝不暴露条目细节或内部 ID。
struct MobileTodayTaskPackagePublicSummary: Equatable {
    var generatedAt: String
    var publicPackRef: String
    var counts: MobileTodayTaskPackageCounts
    var availableMinutes: Int
    var pendingMinutes: Int
    var offlinePendingCount: Int
    var findingCodes: [MobileTodayTaskFindingCode]

    let writesLedger = false
    let grantsCredit = false
    let approvesTask = false
    let unlocksDevice = false
    let sendsNotification = false
    let uploadsMedia = false
}

// MARK: - 工作台读取模型

/// 今日任务包工作台读取模型（孩子视角，纯只读）。
struct MobileTodayTaskPackageWorkbench: Equatable {
    var generatedAt: String
    /// 脱敏任务包引用，绝不是真实 pack id。
    var publicPackRef: String
    /// 成长包标题（展示用，已脱敏）。
    var packTitle: String
    var packSummary: String
    var cards: [MobileTodayTaskCard]
    var counts: MobileTodayTaskPackageCounts
    var credit: MobileTodayTaskCreditSummary
    var offlineHint: MobileTodayTaskOfflineHint
    var findings: [MobileTodayTaskFinding]
    var publicSummary: MobileTodayTaskPackagePublicSummary

    /// 工作台没有任何任务卡。
    var isEmpty: Bool { cards.isEmpty }
}

// MARK: - 构建器

/// 从 `LocalFamilyStore` 已有的本地快照装配工作台。绝不修改 store，绝不触发任何写操作。
struct MobileTodayTaskPackageWorkbenchBuilder {
    var generatedAt: String = "2026-06-24T03:00:00Z"
    var redactionSalt: String = "mobile-today-task-package-ios-v1"

    /// 主入口：基于本地家庭 store 当前状态装配孩子视角工作台。
    func build(
        store: LocalFamilyStore,
        offlineStatus: MobileOfflinePublicStatus = .clean
    ) -> MobileTodayTaskPackageWorkbench {
        // 孩子视角文案统一跟随当前活跃孩子的界面语言（安全空壳同样要跟语言）。
        let language = store.activeChildInterfaceLanguage
        guard !hasUnsafeSourceDisplay(store) else { return safeFallback(language: language) }
        let cards = buildCards(store: store, language: language)
        let counts = countStates(cards)
        let credit = creditSummary(store.creditBalance)
        let offlineHint = offlineHint(for: offlineStatus, language: language)
        let findings = collectFindings(cards: cards, counts: counts, offline: offlineHint, language: language)
        let publicPackRef = publicRef("bundle", store.growthPack.title.isEmpty ? "empty-pack" : store.growthPack.title)
        let publicSummary = MobileTodayTaskPackagePublicSummary(
            generatedAt: generatedAt,
            publicPackRef: publicPackRef,
            counts: counts,
            availableMinutes: credit.availableMinutes,
            pendingMinutes: credit.pendingMinutes,
            offlinePendingCount: offlineHint.pendingCount,
            findingCodes: findings.map(\.code)
        )
        let workbench = MobileTodayTaskPackageWorkbench(
            generatedAt: generatedAt,
            publicPackRef: publicPackRef,
            packTitle: displayPhrase(store.growthPack.title, language: language),
            packSummary: displayPhrase(store.growthPack.summary, language: language),
            cards: cards,
            counts: counts,
            credit: credit,
            offlineHint: offlineHint,
            findings: findings,
            publicSummary: publicSummary
        )
        return redacts(workbench) ? workbench : safeFallback()
    }

    /// 翻译后的展示值不能绕过原始成长包/任务的安全检查。
    private func hasUnsafeSourceDisplay(_ store: LocalFamilyStore) -> Bool {
        var values = [store.growthPack.title, store.growthPack.summary]
        values += store.growthPack.steps.flatMap { [$0.title, $0.detail] }
        values += store.assignments.flatMap { assignment -> [String] in
            var taskValues = [assignment.task.title, assignment.task.instructions]
            taskValues += (assignment.task.localizedContent ?? []).flatMap { [$0.title, $0.instructions] }
            return taskValues
        }
        return MobileSyncPayloadGuard.isUnsafe(values)
    }

    /// 校验工作台所有展示字符串是否脱敏、无敏感泄漏。
    func redacts(_ workbench: MobileTodayTaskPackageWorkbench) -> Bool {
        let values = publicStrings(workbench)
        if MobileSyncPayloadGuard.isUnsafe(values) { return false }
        let joined = values.joined(separator: " ")
        for marker in ["child:", "family:", "task:", "claim:", "pack:", "ledger:", "device:", "proof:", "order:", "session:", "entitlement:", "homework:"] {
            if joined.localizedCaseInsensitiveContains(marker) { return false }
        }
        return true
    }

    // MARK: - 任务卡映射

    /// 把成长包步骤（保留顺序与解锁语义）映射成孩子视角任务卡。
    private func buildCards(store: LocalFamilyStore, language: AppInterfaceLanguage) -> [MobileTodayTaskCard] {
        store.growthPack.steps
            .sorted { $0.order < $1.order }
            .compactMap { step in
                guard let assignment = store.assignment(for: step) else { return nil }
                guard assignment.childId == store.activeChildId, assignment.status != .cancelled else { return nil }
                let progress = store.progress(for: step)
                let state = cardState(progress: progress, status: assignment.status)
                let proof = proofRequirement(assignment.task.requiredProof)
                return MobileTodayTaskCard(
                    publicTaskRef: publicRef("work", step.assignmentId.uuidString),
                    order: step.order,
                    title: assignment.task.displayTitle(for: language),
                    categoryLabel: assignment.task.category.label(for: language),
                    state: state,
                    proof: proof,
                    rewardMinutes: step.rewardMinutes,
                    nextStep: nextStep(state: state, proof: proof, reason: assignment.rejectionReason, language: language),
                    creditHint: creditHint(state: state, rewardMinutes: step.rewardMinutes, language: language)
                )
            }
    }

    /// 内置短语（成长包标题/摘要）的英文映射；查不到时保留原文。
    private func displayPhrase(_ text: String, language: AppInterfaceLanguage) -> String {
        guard language == .english else { return text }
        return BuiltInTaskLocalization.englishPhrase(for: text) ?? text
    }

    /// 把成长步骤进度 + 任务状态合成孩子视角卡状态。
    private func cardState(progress: GrowthStepProgress, status: TaskAssignmentStatus) -> MobileTodayTaskCardState {
        if status == .rejected { return .redo }
        switch progress {
        case .locked: return .locked
        case .active: return .active
        case .submitted: return .waitingCheck
        case .approved: return .done
        }
    }

    private func proofRequirement(_ kind: ProofKind) -> MobileTodayTaskProofRequirement {
        switch kind {
        case .text: return .text
        case .photoPlaceholder: return .photoPlaceholder
        case .photo: return .photo
        }
    }

    private func categoryLabel(_ category: TaskCategory) -> String {
        switch category {
        case .home: return "家务"
        case .learning: return "学习"
        case .health: return "运动健康"
        case .creative: return "创造"
        case .family: return "家庭"
        case .school: return "学校任务"
        }
    }

    /// 孩子视角的下一步建议，不出现成人审批语义。
    private func nextStep(
        state: MobileTodayTaskCardState,
        proof: MobileTodayTaskProofRequirement,
        reason: RejectionReason?,
        language: AppInterfaceLanguage
    ) -> String {
        switch state {
        case .locked:
            return language.pick(
                "先完成前面的任务，这一步就会解锁。",
                "Finish the earlier tasks first and this step will unlock."
            )
        case .active:
            return proof.hint(for: language)
        case .waitingCheck:
            return language.pick(
                "已经交啦，等大人看看就好。",
                "All handed in — just wait for a grown-up to take a look."
            )
        case .done:
            return language.pick(
                "做得很棒，这一步已经完成。",
                "Great job — this step is done."
            )
        case .redo:
            if let reason {
                return language.pick(
                    "再试一次：\(reason.label)。",
                    "Try again: \(reason.label(for: .english))."
                )
            }
            return language.pick(
                "再试一次，把它做得更好。",
                "Give it another try and make it even better."
            )
        }
    }

    /// 孩子视角的积分建议。用「成长积分」描述，绝不出现「发成长积分/批准」。
    private func creditHint(
        state: MobileTodayTaskCardState,
        rewardMinutes: Int,
        language: AppInterfaceLanguage
    ) -> String {
        switch state {
        case .locked:
            return language.pick(
                "解锁后完成可获得 \(rewardMinutes) 成长积分。",
                "Unlock and finish it to earn \(rewardMinutes) Growth Points."
            )
        case .active:
            return language.pick(
                "完成后可获得 \(rewardMinutes) 成长积分。",
                "Finish it to earn \(rewardMinutes) Growth Points."
            )
        case .waitingCheck:
            return language.pick(
                "这一条的 \(rewardMinutes) 成长积分正在等待确认。",
                "The \(rewardMinutes) Growth Points for this one are waiting for check."
            )
        case .done:
            return language.pick(
                "已获得 \(rewardMinutes) 成长积分。",
                "You earned \(rewardMinutes) Growth Points."
            )
        case .redo:
            return language.pick(
                "再完成一次，仍可获得 \(rewardMinutes) 成长积分。",
                "Finish it again and you can still earn \(rewardMinutes) Growth Points."
            )
        }
    }

    // MARK: - 状态计数

    private func countStates(_ cards: [MobileTodayTaskCard]) -> MobileTodayTaskPackageCounts {
        MobileTodayTaskPackageCounts(
            total: cards.count,
            locked: cards.filter { $0.state == .locked }.count,
            active: cards.filter { $0.state == .active }.count,
            waitingCheck: cards.filter { $0.state == .waitingCheck }.count,
            done: cards.filter { $0.state == .done }.count,
            redo: cards.filter { $0.state == .redo }.count
        )
    }

    // MARK: - 成长积分摘要

    private func creditSummary(_ balance: CreditBalance) -> MobileTodayTaskCreditSummary {
        MobileTodayTaskCreditSummary(
            availableMinutes: max(0, balance.availableMinutes),
            pendingMinutes: max(0, balance.pendingMinutes),
            lifetimeEarnedMinutes: max(0, balance.lifetimeEarnedMinutes)
        )
    }

    // MARK: - 离线提示

    private func offlineHint(
        for status: MobileOfflinePublicStatus,
        language: AppInterfaceLanguage = .chinese
    ) -> MobileTodayTaskOfflineHint {
        let pending = max(0, status.pendingCount)
        if pending > 0 {
            return MobileTodayTaskOfflineHint(
                pendingCount: pending,
                title: language.pick(
                    "有 \(pending) 条记录在等待同步",
                    "\(pending) records are waiting to sync"
                ),
                message: language.pick(
                    "联网后还要等大人确认才会生效，不会自动发奖励或解锁设备。",
                    "After going online a grown-up still checks them; nothing pays out or unlocks a device automatically."
                )
            )
        }
        return MobileTodayTaskOfflineHint(
            pendingCount: 0,
            title: language.pick("记录都已同步", "All records are synced"),
            message: language.pick("你的任务记录已经安全保存。", "Your task records are safely saved.")
        )
    }

    // MARK: - 发现项

    private func collectFindings(
        cards: [MobileTodayTaskCard],
        counts: MobileTodayTaskPackageCounts,
        offline: MobileTodayTaskOfflineHint,
        language: AppInterfaceLanguage
    ) -> [MobileTodayTaskFinding] {
        var findings: [MobileTodayTaskFinding] = []
        if cards.isEmpty {
            findings.append(finding(
                .emptyToday,
                .info,
                language.pick("今天还没有任务，先好好休息。", "No tasks today — take a good rest."),
                "empty"
            ))
            return findings
        }
        if counts.redo > 0 {
            findings.append(finding(
                .redoNeeded,
                .warning,
                language.pick(
                    "有 \(counts.redo) 个任务需要再试一次。",
                    "\(counts.redo) task(s) need another try."
                ),
                "redo"
            ))
        }
        if offline.hasPending {
            findings.append(finding(
                .offlinePending,
                .info,
                language.pick(
                    "有记录在等待同步，联网后大人确认才生效。",
                    "Some records are waiting to sync; a grown-up checks them once you're online."
                ),
                "offline"
            ))
        }
        if !findings.contains(where: { $0.severity == .warning || $0.severity == .blocker }) {
            findings.append(finding(
                .workbenchOK,
                .ok,
                language.pick(
                    "今日任务包工作台已脱敏且无副作用。",
                    "Today's task pack workbench is redacted and side-effect free."
                ),
                "ok"
            ))
        }
        return unique(findings)
    }

    // MARK: - 安全降级

    private func safeFallback(language: AppInterfaceLanguage = .chinese) -> MobileTodayTaskPackageWorkbench {
        let counts = MobileTodayTaskPackageCounts.empty
        let credit = MobileTodayTaskCreditSummary(availableMinutes: 0, pendingMinutes: 0, lifetimeEarnedMinutes: 0)
        let offline = MobileTodayTaskOfflineHint(
            pendingCount: 0,
            title: language.pick("记录都已同步", "All records are synced"),
            message: language.pick("你的任务记录已经安全保存。", "Your task records are safely saved.")
        )
        let leak = finding(
            .publicSummaryLeak,
            .blocker,
            language.pick(
                "今日任务包工作台未通过脱敏检查，已进入安全空壳。",
                "Today's task pack workbench failed the redaction check and switched to the safe empty shell."
            ),
            "public-summary-leak"
        )
        let publicPackRef = publicRef("bundle", "redacted-pack")
        let publicSummary = MobileTodayTaskPackagePublicSummary(
            generatedAt: generatedAt,
            publicPackRef: publicPackRef,
            counts: counts,
            availableMinutes: 0,
            pendingMinutes: 0,
            offlinePendingCount: 0,
            findingCodes: [.publicSummaryLeak]
        )
        return MobileTodayTaskPackageWorkbench(
            generatedAt: generatedAt,
            publicPackRef: publicPackRef,
            packTitle: "今日任务包",
            packSummary: "",
            cards: [],
            counts: counts,
            credit: credit,
            offlineHint: offline,
            findings: [leak],
            publicSummary: publicSummary
        )
    }

    // MARK: - helpers

    private func publicRef(_ prefix: String, _ source: String) -> String {
        Self.stablePublicRef(prefix: prefix, source: source, salt: redactionSalt)
    }

    /// 稳定脱敏引用：同样的 salt + source 永远得到同一引用，但不可反推内部 ID。
    static func stablePublicRef(
        prefix: String,
        source: String,
        salt: String = "mobile-today-task-package-ios-v1"
    ) -> String {
        var hash: UInt32 = 5381
        for scalar in "\(salt):\(source)".unicodeScalars {
            hash = (hash &* 33) ^ UInt32(scalar.value)
        }
        let body = String(hash, radix: 36)
        let padded = body.count >= 7 ? body : String(repeating: "0", count: 7 - body.count) + body
        return "\(prefix):\(padded)"
    }

    private func finding(
        _ code: MobileTodayTaskFindingCode,
        _ severity: MobileTodayTaskFindingSeverity,
        _ message: String,
        _ seed: String
    ) -> MobileTodayTaskFinding {
        MobileTodayTaskFinding(
            code: code,
            severity: severity,
            message: message,
            publicRef: publicRef("today-finding", "\(code.rawValue):\(seed)")
        )
    }

    private func unique(_ findings: [MobileTodayTaskFinding]) -> [MobileTodayTaskFinding] {
        var seen = Set<String>()
        return findings.filter { item in
            let key = item.id
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func publicStrings(_ workbench: MobileTodayTaskPackageWorkbench) -> [String] {
        var values: [String] = [
            workbench.generatedAt,
            workbench.publicPackRef,
            workbench.packTitle,
            workbench.packSummary,
            workbench.credit.headline,
            workbench.offlineHint.title,
            workbench.offlineHint.message
        ]
        values += workbench.cards.flatMap {
            [$0.publicTaskRef, $0.title, $0.categoryLabel, $0.state.label, $0.proof.label, $0.nextStep, $0.creditHint]
        }
        values += workbench.findings.flatMap { [$0.publicRef, $0.code.rawValue, $0.message] }
        values += workbench.publicSummary.findingCodes.map(\.rawValue)
        return values
    }
}
