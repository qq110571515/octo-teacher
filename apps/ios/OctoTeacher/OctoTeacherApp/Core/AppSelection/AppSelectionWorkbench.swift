import Foundation

/// iOS 娱乐 App 选择 / 锁定策略预览的纯本地安全投影。
///
/// 当前只展示“家长准备选择哪些娱乐 App、孩子能看到哪些可用边界”的本地壳：
/// 不调用 FamilyControls、ManagedSettings、DeviceActivity，不保存真实 bundle id，不写账本，
/// 不发成长积分，不解锁设备，也不向系统提交 shield 策略。
enum AppSelectionViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        }
    }

    var note: String {
        switch self {
        case .child:
            return "这里能看到哪些娱乐类别会进入奖励窗口；不会展示系统标识，也不会直接解锁。"
        case .guardian:
            return "只读预览娱乐 App 分组、审批原因和设备控制边界；真实选择仍需 Apple 家长授权。"
        }
    }
}

enum AppSelectionCategory: String, Equatable {
    case game
    case shortVideo
    case social
    case learning

    var label: String {
        switch self {
        case .game: return "游戏"
        case .shortVideo: return "短视频"
        case .social: return "社交"
        case .learning: return "学习"
        }
    }
}

enum AppSelectionRiskLevel: String, Equatable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }
}

enum AppSelectionApprovalState: String, Equatable {
    case ready
    case pendingGuardian
    case blocked

    var label: String {
        switch self {
        case .ready: return "可进入策略"
        case .pendingGuardian: return "待家长确认"
        case .blocked: return "已阻断"
        }
    }
}

struct AppSelectionCandidate: Identifiable, Equatable {
    var publicAppRef: String
    var displayName: String
    var category: AppSelectionCategory
    var riskLevel: AppSelectionRiskLevel
    var selectedForShield: Bool
    var guardianApproved: Bool
    var ageAllowed: Bool
    var reason: String
    var childSummary: String

    /// 仅本地测试夹具使用；Builder 输出给 UI 前必须剔除。
    var internalBundleIdentifier: String?

    let callsFamilyControls = false
    let callsManagedSettings = false
    let callsDeviceActivity = false
    let writesShieldPolicy = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false

    var id: String { publicAppRef }

    var approvalState: AppSelectionApprovalState {
        guard ageAllowed else { return .blocked }
        guard guardianApproved else { return .pendingGuardian }
        return .ready
    }

    var displayValues: [String] {
        [
            publicAppRef,
            displayName,
            category.rawValue,
            category.label,
            riskLevel.rawValue,
            riskLevel.label,
            reason,
            childSummary,
            approvalState.rawValue,
            approvalState.label
        ]
    }
}

struct AppSelectionPolicyStep: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var done: Bool

    var displayValues: [String] { [id, title, detail] }
}

struct AppSelectionFinding: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var actionRequired: Bool
    var visibleToChild: Bool

    var displayValues: [String] { [id, title, detail] }
}

struct AppSelectionPublicSummary: Equatable {
    var role: AppSelectionViewerRole
    var candidateCount: Int
    var selectedCount: Int
    var approvedSelectedCount: Int
    var pendingGuardianCount: Int
    var blockedCount: Int
    var highRiskSelectedCount: Int

    let callsFamilyControls = false
    let callsManagedSettings = false
    let callsDeviceActivity = false
    let writesShieldPolicy = false
    let readsInstalledApplications = false
    let storesBundleIdentifiers = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let callsNetwork = false

    var hasTriggeredSideEffect: Bool {
        callsFamilyControls || callsManagedSettings || callsDeviceActivity || writesShieldPolicy
            || readsInstalledApplications || storesBundleIdentifiers || writesLedger || grantsCredit
            || unlocksDevice || callsNetwork
    }
}

struct AppSelectionWorkbench: Equatable {
    var role: AppSelectionViewerRole
    var title: String
    var subtitle: String
    var note: String
    var candidates: [AppSelectionCandidate]
    var policySteps: [AppSelectionPolicyStep]
    var findings: [AppSelectionFinding]
    var publicSummary: AppSelectionPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, note]
            + candidates.flatMap(\.displayValues)
            + policySteps.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        AppSelectionWorkbenchBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct AppSelectionWorkbenchBuilder {
    private static let sensitiveMarkers = [
        "bundle", "bundleid", "applicationtoken", "familyactivityselection",
        "familycontrols", "managedsettings", "deviceactivity", "shield:",
        "app:", "device:", "ledger:", "credit:", "unlock:", "token",
        "secret", "api_key", "apikey", "http://", "https://", "file://",
        "/users/", "/volumes/", "192.168."
    ]

    func build(
        role: AppSelectionViewerRole,
        candidates inputCandidates: [AppSelectionCandidate] = Self.mockCandidates,
        unsafePayload: [String] = []
    ) -> AppSelectionWorkbench {
        if Self.hasUnsafeDisplayPayload(unsafePayload) {
            return blockedShell(role: role, hiddenCount: inputCandidates.count)
        }

        let sanitizedCandidates = inputCandidates.map { candidate in
            sanitize(candidate, role: role)
        }
        if sanitizedCandidates.contains(where: { Self.hasUnsafeDisplayPayload($0.displayValues) }) {
            return blockedShell(role: role, hiddenCount: inputCandidates.count)
        }

        let visibleCandidates = sanitizedCandidates.filter { role == .guardian || $0.selectedForShield }
        let selected = sanitizedCandidates.filter(\.selectedForShield)
        let pending = selected.filter { $0.approvalState == .pendingGuardian }
        let blocked = selected.filter { $0.approvalState == .blocked }
        let summary = AppSelectionPublicSummary(
            role: role,
            candidateCount: role == .guardian ? sanitizedCandidates.count : visibleCandidates.count,
            selectedCount: selected.count,
            approvedSelectedCount: selected.filter { $0.approvalState == .ready }.count,
            pendingGuardianCount: role == .guardian ? pending.count : 0,
            blockedCount: role == .guardian ? blocked.count : 0,
            highRiskSelectedCount: role == .guardian ? selected.filter { $0.riskLevel == .high }.count : 0
        )
        let workbench = AppSelectionWorkbench(
            role: role,
            title: "娱乐 App 选择",
            subtitle: "奖励窗口前的本地策略预览",
            note: role.note,
            candidates: visibleCandidates,
            policySteps: policySteps(selected: selected, pending: pending, blocked: blocked),
            findings: findings(role: role, selected: selected, pending: pending, blocked: blocked),
            publicSummary: summary
        )
        return workbench.hasUnsafeDisplayPayload ? blockedShell(role: role, hiddenCount: inputCandidates.count) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private func sanitize(
        _ candidate: AppSelectionCandidate,
        role: AppSelectionViewerRole
    ) -> AppSelectionCandidate {
        AppSelectionCandidate(
            publicAppRef: candidate.publicAppRef,
            displayName: candidate.displayName,
            category: candidate.category,
            riskLevel: candidate.riskLevel,
            selectedForShield: candidate.selectedForShield,
            guardianApproved: role == .guardian ? candidate.guardianApproved : candidate.guardianApproved,
            ageAllowed: candidate.ageAllowed,
            reason: role == .guardian ? candidate.reason : "\(candidate.category.label)类娱乐时间需要先完成任务",
            childSummary: candidate.childSummary,
            internalBundleIdentifier: nil
        )
    }

    private func policySteps(
        selected: [AppSelectionCandidate],
        pending: [AppSelectionCandidate],
        blocked: [AppSelectionCandidate]
    ) -> [AppSelectionPolicyStep] {
        [
            AppSelectionPolicyStep(
                id: "local-preview",
                title: "本地策略预览",
                detail: "只计算候选 App 分组和审批状态，不读取系统已安装应用。",
                done: true
            ),
            AppSelectionPolicyStep(
                id: "guardian-approval",
                title: "家长确认",
                detail: pending.isEmpty ? "已选 App 都有家长确认或被年龄门禁阻断。" : "\(pending.count) 个已选 App 仍需家长确认。",
                done: pending.isEmpty
            ),
            AppSelectionPolicyStep(
                id: "age-gate",
                title: "年龄门禁",
                detail: blocked.isEmpty ? "当前已选 App 未触发年龄门禁阻断。" : "\(blocked.count) 个已选 App 因年龄不适合被阻断。",
                done: blocked.isEmpty
            ),
            AppSelectionPolicyStep(
                id: "mock-device-boundary",
                title: "设备控制边界",
                detail: selected.isEmpty ? "未选择娱乐 App，仍保持只读。" : "已选择 \(selected.count) 个娱乐 App；这里只预览，不下发系统 shield。",
                done: true
            )
        ]
    }

    private func findings(
        role: AppSelectionViewerRole,
        selected: [AppSelectionCandidate],
        pending: [AppSelectionCandidate],
        blocked: [AppSelectionCandidate]
    ) -> [AppSelectionFinding] {
        if role == .child {
            return [
                AppSelectionFinding(
                    id: "child-no-direct-unlock",
                    title: "兑换不等于直接解锁",
                    detail: "完成任务后进入成长积分和奖励窗口流程，设备会话仍由本地设备边界保护。",
                    actionRequired: false,
                    visibleToChild: true
                )
            ]
        }

        var rows: [AppSelectionFinding] = [
            AppSelectionFinding(
                id: "no-system-selection",
                title: "未接真实系统选择器",
                detail: "当前不读取系统应用标识，不保存内部标识，也不写系统管控策略。",
                actionRequired: false,
                visibleToChild: false
            )
        ]
        if !pending.isEmpty {
            rows.append(
                AppSelectionFinding(
                    id: "guardian-approval-required",
                    title: "仍需家长确认",
                    detail: "\(pending.count) 个已选娱乐 App 不能进入策略生效队列。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if !blocked.isEmpty {
            rows.append(
                AppSelectionFinding(
                    id: "age-gate-blocked",
                    title: "年龄门禁阻断",
                    detail: "\(blocked.count) 个已选 App 不适合当前年龄段。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if selected.contains(where: { $0.riskLevel == .high }) {
            rows.append(
                AppSelectionFinding(
                    id: "high-risk-selected",
                    title: "高风险娱乐类别",
                    detail: "高风险 App 需要更短奖励窗口、明确任务来源和家长复核。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        return rows
    }

    private func blockedShell(role: AppSelectionViewerRole, hiddenCount: Int) -> AppSelectionWorkbench {
        AppSelectionWorkbench(
            role: role,
            title: "娱乐 App 选择",
            subtitle: "输入已被安全壳阻断",
            note: role.note,
            candidates: [],
            policySteps: [
                AppSelectionPolicyStep(
                    id: "blocked",
                    title: "已阻断",
                    detail: "发现不适合展示的系统标识或敏感内容，已隐藏 \(hiddenCount) 个候选项。",
                    done: false
                )
            ],
            findings: [
                AppSelectionFinding(
                    id: "unsafe",
                    title: "敏感内容被拦截",
                    detail: "请回到正式授权流程重新生成脱敏预览。",
                    actionRequired: true,
                    visibleToChild: role == .child
                )
            ],
            publicSummary: AppSelectionPublicSummary(
                role: role,
                candidateCount: 0,
                selectedCount: 0,
                approvedSelectedCount: 0,
                pendingGuardianCount: 0,
                blockedCount: hiddenCount,
                highRiskSelectedCount: 0
            )
        )
    }
}

extension AppSelectionWorkbenchBuilder {
    static let mockCandidates: [AppSelectionCandidate] = [
        AppSelectionCandidate(
            publicAppRef: "asw-game-arcade",
            displayName: "积木闯关",
            category: .game,
            riskLevel: .medium,
            selectedForShield: true,
            guardianApproved: true,
            ageAllowed: true,
            reason: "游戏类需要绑定奖励窗口，优先用短时段兑换。",
            childSummary: "完成任务后可兑换短时间游戏窗口。",
            internalBundleIdentifier: "com.example.arcade"
        ),
        AppSelectionCandidate(
            publicAppRef: "asw-video-short",
            displayName: "短视频广场",
            category: .shortVideo,
            riskLevel: .high,
            selectedForShield: true,
            guardianApproved: false,
            ageAllowed: true,
            reason: "短视频类需要家长确认和更短窗口。",
            childSummary: "这个类别还在等家长确认。",
            internalBundleIdentifier: "com.example.shortvideo"
        ),
        AppSelectionCandidate(
            publicAppRef: "asw-social-chat",
            displayName: "同学圈",
            category: .social,
            riskLevel: .medium,
            selectedForShield: true,
            guardianApproved: true,
            ageAllowed: false,
            reason: "社交类暂不适合当前年龄段。",
            childSummary: "这个类别暂时不能兑换。",
            internalBundleIdentifier: "com.example.social"
        ),
        AppSelectionCandidate(
            publicAppRef: "asw-learning-video",
            displayName: "课程视频",
            category: .learning,
            riskLevel: .low,
            selectedForShield: false,
            guardianApproved: true,
            ageAllowed: true,
            reason: "学习类不进入娱乐锁定候选。",
            childSummary: "学习内容不占用娱乐窗口。",
            internalBundleIdentifier: "com.example.learning"
        )
    ]
}
