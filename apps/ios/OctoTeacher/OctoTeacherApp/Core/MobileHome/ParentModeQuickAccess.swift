import Foundation

/// 家长端顶部的本地快捷入口。
///
/// 该枚举只负责入口顺序、标签和图标，不执行审批、发放成长积分、通知或设备控制。
enum ParentModeQuickAccess: String, CaseIterable, Equatable {
    case todayTaskReview
    case basicHabitChore
    case growthDiaryVlogReview
    case moduleConfigurationDraft
    case approvalInbox
    case schoolJointApproval
    case aiHomeworkCreditHandoff
    case aiLmsBoundary
    case guardianConsentPolicy
    case creatorManifestPreview
    case growthPackInstallEntitlement
    case creditLedgerReview
    case appSelectionPolicy
    case reportsPreview
    case onboardingBoundary

    static let ordered: [ParentModeQuickAccess] = [
        .todayTaskReview,
        .basicHabitChore,
        .growthDiaryVlogReview,
        .moduleConfigurationDraft,
        .approvalInbox,
        .schoolJointApproval,
        .aiHomeworkCreditHandoff,
        .aiLmsBoundary,
        .guardianConsentPolicy,
        .creatorManifestPreview,
        .growthPackInstallEntitlement,
        .creditLedgerReview,
        .appSelectionPolicy,
        .reportsPreview,
        .onboardingBoundary
    ]

    var label: String {
        label(for: .chinese)
    }

    func label(for language: AppInterfaceLanguage) -> String {
        switch self {
        case .todayTaskReview: return language.pick("今日任务审核", "Today's Reviews")
        case .basicHabitChore: return language.pick("独立与家务", "Independence & Chores")
        case .growthDiaryVlogReview: return language.pick("成长日记与作品", "Growth Diary & Projects")
        case .moduleConfigurationDraft: return language.pick("成长计划预演", "Plan Preview")
        case .approvalInbox: return language.pick("待处理事项", "Action Inbox")
        case .schoolJointApproval: return language.pick("家校联合确认", "School & Family Review")
        case .aiHomeworkCreditHandoff: return language.pick("AI 作业建议复核", "AI Homework Review")
        case .aiLmsBoundary: return language.pick("学校系统接入检查", "School System Check")
        case .guardianConsentPolicy: return language.pick("孩子数据与授权", "Child Data & Consent")
        case .creatorManifestPreview: return language.pick("成长包发布检查", "Pack Publishing Check")
        case .growthPackInstallEntitlement: return language.pick("成长包安装记录", "Pack Install Records")
        case .creditLedgerReview: return language.pick("成长积分账本", "Growth Point Ledger")
        case .appSelectionPolicy: return language.pick("娱乐 App 规则", "Entertainment App Rules")
        case .reportsPreview: return language.pick("成长报告", "Growth Reports")
        case .onboardingBoundary: return language.pick("首次使用检查", "First-use Check")
        }
    }

    var statusLabel: String {
        statusLabel(for: .chinese)
    }

    func statusLabel(for language: AppInterfaceLanguage) -> String {
        switch self {
        case .todayTaskReview, .basicHabitChore, .approvalInbox:
            return language.pick("日常", "Ready")
        case .creditLedgerReview:
            return language.pick("复核", "Review")
        case .reportsPreview:
            return language.pick("报告", "Report")
        default:
            return language.pick("规划", "Planning")
        }
    }

    var detail: String {
        detail(for: .chinese)
    }

    func detail(for language: AppInterfaceLanguage) -> String {
        switch self {
        case .todayTaskReview:
            return language.pick("集中处理孩子今天提交的任务。", "Review today's child submissions in one place.")
        case .basicHabitChore:
            return language.pick("管理睡觉、洗漱、整理和家务。", "Manage bedtime, hygiene, organization, and chores.")
        case .growthDiaryVlogReview:
            return language.pick("查看成长日记、VLOG 和作品。", "Review growth diaries, VLOGs, and projects.")
        case .moduleConfigurationDraft:
            return language.pick("预览学习、生活、运动和奖励组合。", "Preview a mix of learning, life, exercise, and rewards.")
        case .approvalInbox:
            return language.pick("查看证明、申诉、同步和奖励待办。", "See proof, appeals, sync, and reward actions.")
        case .schoolJointApproval:
            return language.pick("汇总老师验证与家长确认。", "Combine teacher verification with guardian review.")
        case .aiHomeworkCreditHandoff:
            return language.pick("检查 AI 作业引导和积分建议。", "Review AI homework guidance and point suggestions.")
        case .aiLmsBoundary:
            return language.pick("检查学校系统与家庭数据的连接规则。", "Check school-system and family-data connection rules.")
        case .guardianConsentPolicy:
            return language.pick("管理孩子数据、亲友和学校授权。", "Manage child-data, relative, and school consent.")
        case .creatorManifestPreview:
            return language.pick("发布前检查适龄、奖励和隐私。", "Check age fit, rewards, and privacy before publishing.")
        case .growthPackInstallEntitlement:
            return language.pick("查看成长包安装与使用状态。", "Review learning-pack installation and access.")
        case .creditLedgerReview:
            return language.pick("复核积分来源与异常状态。", "Review point sources and exceptions.")
        case .appSelectionPolicy:
            return language.pick("设置可兑换或限制的娱乐 App。", "Choose entertainment apps that can be earned or limited.")
        case .reportsPreview:
            return language.pick("查看周报、成长变化和建议。", "Review weekly reports, growth changes, and suggestions.")
        case .onboardingBoundary:
            return language.pick("检查首次设置与隐私说明。", "Review first-use setup and privacy guidance.")
        }
    }

    var systemImage: String {
        switch self {
        case .todayTaskReview, .creditLedgerReview: return "checklist.checked"
        case .basicHabitChore: return "sun.max"
        case .growthDiaryVlogReview: return "book.closed"
        case .moduleConfigurationDraft: return "rectangle.grid.2x2"
        case .approvalInbox: return "tray.full"
        case .schoolJointApproval: return "person.2.badge.gearshape"
        case .aiHomeworkCreditHandoff: return "arrow.triangle.branch"
        case .aiLmsBoundary: return "shield.lefthalf.filled"
        case .guardianConsentPolicy: return "person.badge.shield.checkmark"
        case .creatorManifestPreview: return "doc.text.magnifyingglass"
        case .growthPackInstallEntitlement: return "square.and.arrow.down"
        case .appSelectionPolicy: return "gamecontroller"
        case .reportsPreview: return "doc.text"
        case .onboardingBoundary: return "sparkles"
        }
    }
}
