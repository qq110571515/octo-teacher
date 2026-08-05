import Foundation

/// iOS 首次进入 / 角色引导的纯本地只读投影。
///
/// 只展示 章鱼老师 已准备好的入口、角色边界和隐私护栏；不登录、不创建家庭、
/// 不申请 Apple 权限、不联网、不写任何业务状态。
enum OnboardingViewerRole: String, CaseIterable, Equatable {
    case child
    case guardian

    var label: String {
        switch self {
        case .child: return "孩子"
        case .guardian: return "家长"
        }
    }
}

enum OnboardingStepKind: String, Equatable {
    case role
    case tasks
    case school
    case credit
    case reports
    case privacy

    var title: String {
        switch self {
        case .role: return "角色"
        case .tasks: return "任务"
        case .school: return "学校"
        case .credit: return "成长积分"
        case .reports: return "报告"
        case .privacy: return "隐私"
        }
    }
}

struct OnboardingStep: Identifiable, Equatable {
    var id: String
    var kind: OnboardingStepKind
    var title: String
    var detail: String
    var ready: Bool
    var visibleToChild: Bool

    let startsLogin = false
    let createsAccount = false
    let requestsApplePermission = false
    let callsNetwork = false
    let writesFamily = false
    let writesLedger = false
    let unlocksDevice = false

    var displayValues: [String] {
        [id, kind.rawValue, kind.title, title, detail]
    }
}

struct OnboardingBoundary: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var visibleToChild: Bool

    var displayValues: [String] { [id, title, detail] }
}

struct OnboardingPublicSummary: Equatable {
    var role: OnboardingViewerRole
    var visibleStepCount: Int
    var readyStepCount: Int
    var boundaryCount: Int

    let startsLogin = false
    let createsAccount = false
    let requestsApplePermission = false
    let callsNetwork = false
    let writesFamily = false
    let writesLedger = false
    let unlocksDevice = false
    let sendsNotification = false

    var hasTriggeredSideEffect: Bool {
        startsLogin || createsAccount || requestsApplePermission || callsNetwork || writesFamily
            || writesLedger || unlocksDevice || sendsNotification
    }
}

struct OnboardingWorkbench: Equatable {
    var role: OnboardingViewerRole
    var title: String
    var subtitle: String
    var steps: [OnboardingStep]
    var boundaries: [OnboardingBoundary]
    var publicSummary: OnboardingPublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle]
            + steps.flatMap(\.displayValues)
            + boundaries.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        OnboardingWorkbenchBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct OnboardingWorkbenchBuilder {
    private static let sensitiveMarkers = [
        "child:", "family:", "guardian:", "teacher:", "school:",
        "token", "secret", "api_key", "apikey", "http://", "https://",
        "file://", "/users/", "/volumes/", "192.168.", "bundle"
    ]

    func build(
        role: OnboardingViewerRole,
        unsafePayload: [String] = []
    ) -> OnboardingWorkbench {
        if Self.hasUnsafeDisplayPayload(unsafePayload) {
            return blockedShell(role: role)
        }

        let visibleSteps = steps.filter { role == .guardian || $0.visibleToChild }
        let visibleBoundaries = boundaries.filter { role == .guardian || $0.visibleToChild }
        let workbench = OnboardingWorkbench(
            role: role,
            title: BrandIdentity.systemName,
            subtitle: role == .child ? "今天从一个小任务开始" : "先确认家庭成长平台的边界",
            steps: visibleSteps,
            boundaries: visibleBoundaries,
            publicSummary: OnboardingPublicSummary(
                role: role,
                visibleStepCount: visibleSteps.count,
                readyStepCount: visibleSteps.filter(\.ready).count,
                boundaryCount: visibleBoundaries.count
            )
        )
        return workbench.hasUnsafeDisplayPayload ? blockedShell(role: role) : workbench
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        if MobileSyncPayloadGuard.isUnsafe(values) { return true }
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private var steps: [OnboardingStep] {
        [
            step("role", .role, "选择视角", "孩子看任务与成长，家长看配置与复核。", true, true),
            step("tasks", .tasks, "今日任务", "基础习惯、家务、学校作业和成长包会汇总在首页。", true, true),
            step("school", .school, "学校作业", "作业引导只给提示和自检，不直接给答案。", true, true),
            step("credit", .credit, "成长积分", "完成任务后等待家长确认，确认后进入兑换窗口，不在这里直接解锁。", true, true),
            step("reports", .reports, "成长报告", "报告只读预览，分享和导出需要后续授权。", true, false),
            step("privacy", .privacy, "隐私护栏", "亲友、学校、设备和报告都有独立可见边界。", true, false)
        ]
    }

    private var boundaries: [OnboardingBoundary] {
        [
            OnboardingBoundary(id: "local-only", title: "本地预览", detail: "当前引导不联网、不登录、不创建家庭。", visibleToChild: true),
            OnboardingBoundary(id: "no-permission", title: "权限稍后处理", detail: "设备、学校和通知权限不会在这里申请。", visibleToChild: false),
            OnboardingBoundary(id: "no-credit", title: "不发放成长积分", detail: "引导页不写成长积分账本、不发放成长积分、不解锁设备。", visibleToChild: true),
            OnboardingBoundary(id: "role-crop", title: "角色裁剪", detail: "孩子只看适合孩子的入口，成人复核内容留在家长视角。", visibleToChild: true)
        ]
    }

    private func step(
        _ id: String,
        _ kind: OnboardingStepKind,
        _ title: String,
        _ detail: String,
        _ ready: Bool,
        _ visibleToChild: Bool
    ) -> OnboardingStep {
        OnboardingStep(
            id: id,
            kind: kind,
            title: title,
            detail: detail,
            ready: ready,
            visibleToChild: visibleToChild
        )
    }

    private func blockedShell(role: OnboardingViewerRole) -> OnboardingWorkbench {
        OnboardingWorkbench(
            role: role,
            title: BrandIdentity.systemName,
            subtitle: "输入已被安全壳阻断",
            steps: [],
            boundaries: [
                OnboardingBoundary(
                    id: "unsafe",
                    title: "引导内容被拦截",
                    detail: "发现不适合展示的内部信息，已隐藏引导草稿。",
                    visibleToChild: role == .child
                )
            ],
            publicSummary: OnboardingPublicSummary(
                role: role,
                visibleStepCount: 0,
                readyStepCount: 0,
                boundaryCount: 1
            )
        )
    }
}
