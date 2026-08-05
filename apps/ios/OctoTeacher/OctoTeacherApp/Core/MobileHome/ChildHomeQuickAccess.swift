import Foundation

/// 孩子首页的本地快捷入口。
///
/// 这里只描述入口顺序和展示标签，不触发导航目标里的任何业务动作。
enum ChildHomeQuickAccess: String, CaseIterable, Equatable {
    case creditWallet
    case basicHabitChore
    case growthDiaryVlog
    case reportsPreview
    case appSelectionPreview
    case onboardingGuide

    static let ordered: [ChildHomeQuickAccess] = [
        .creditWallet,
        .basicHabitChore,
        .growthDiaryVlog,
        .reportsPreview,
        .appSelectionPreview,
        .onboardingGuide
    ]

    var label: String {
        switch self {
        case .creditWallet: return "成长积分钱包与屏幕时间"
        case .basicHabitChore: return "个人独立性与家务打卡"
        case .growthDiaryVlog: return "成长日记与 VLOG"
        case .reportsPreview: return "成长报告预览"
        case .appSelectionPreview: return "娱乐 App 预览"
        case .onboardingGuide: return "章鱼老师 入门"
        }
    }

    func label(for language: AppInterfaceLanguage) -> String {
        guard language == .english else { return label }
        switch self {
        case .creditWallet: return "Growth Point Wallet & Screen Time"
        case .basicHabitChore: return "Independence & Chore Check-ins"
        case .growthDiaryVlog: return "Growth Diary & VLOG"
        case .reportsPreview: return "Growth Report Preview"
        case .appSelectionPreview: return "Fun App Preview"
        case .onboardingGuide: return "Octo Teacher Guide"
        }
    }

    var systemImage: String {
        switch self {
        case .creditWallet: return "wallet.pass"
        case .basicHabitChore: return "sun.max"
        case .growthDiaryVlog: return "book"
        case .reportsPreview: return "doc.text"
        case .appSelectionPreview: return "gamecontroller"
        case .onboardingGuide: return "sparkles"
        }
    }
}
