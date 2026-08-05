import Foundation

enum GrowthCreditCopy {
    static func label(points: Int) -> String {
        "\(max(0, points)) 成长积分"
    }

    static func label(points: Int, language: AppInterfaceLanguage) -> String {
        language == .english ? "\(max(0, points)) Growth Points" : label(points: points)
    }
}

enum ScreenTimeRewardCopy {
    static func buttonTitle(cost: Int) -> String {
        buttonTitle(cost: cost, language: .chinese)
    }

    static func buttonTitle(cost: Int, language: AppInterfaceLanguage) -> String {
        language.pick(
            "🎮 用 \(GrowthCreditCopy.label(points: cost, language: language)) 兑换一次屏幕时间",
            "🎮 Spend \(GrowthCreditCopy.label(points: cost, language: language)) for one screen time session"
        )
    }

    static func speakText(cost: Int) -> String {
        speakText(cost: cost, language: .chinese)
    }

    static func speakText(cost: Int, language: AppInterfaceLanguage) -> String {
        language.pick(
            "花 \(GrowthCreditCopy.label(points: cost, language: language))，可以兑换一次屏幕时间。具体多久，由大人设置的规则决定。",
            "Spend \(GrowthCreditCopy.label(points: cost, language: language)) for one screen time session. How long it lasts follows the rules a grown-up set."
        )
    }

    static let statusButtonTitle = "用成长积分兑换一次屏幕时间"
    static let offlineRequestTitle = "提交屏幕时间请求（待家长开启）"
    static let offlineSuccessText = "已加入离线队列，等家长开启屏幕时间"

    static func statusButtonTitle(for language: AppInterfaceLanguage) -> String {
        language.pick(statusButtonTitle, "Exchange Growth Points for screen time")
    }

    static func offlineRequestTitle(for language: AppInterfaceLanguage) -> String {
        language.pick(offlineRequestTitle, "Submit screen time request (parent opens it)")
    }

    static func offlineSuccessText(for language: AppInterfaceLanguage) -> String {
        language.pick(offlineSuccessText, "Added to the offline queue; a parent opens screen time")
    }
}

enum ScreenTimeRedemptionResultCopy {
    static func title(for result: StartRewardSessionResult) -> String {
        title(for: result, language: .chinese)
    }

    static func title(for result: StartRewardSessionResult, language: AppInterfaceLanguage) -> String {
        switch result {
        case .started: return language.pick("兑换成功", "Exchange successful")
        case .insufficientBalance: return language.pick("成长积分不够", "Not enough Growth Points")
        case .alreadyActive: return language.pick("已有会话", "Session already running")
        case .invalidMinutes: return language.pick("兑换无效", "Invalid exchange")
        case .dailyLimitExceeded: return language.pick("已到每日上限", "Daily limit reached")
        case .deviceFailureRolledBack: return language.pick("设备未打开", "Device did not open")
        }
    }

    static func message(for result: StartRewardSessionResult, minutes: Int, cost: Int) -> String {
        message(for: result, minutes: minutes, cost: cost, language: .chinese)
    }

    static func message(
        for result: StartRewardSessionResult,
        minutes: Int,
        cost: Int,
        language: AppInterfaceLanguage
    ) -> String {
        switch result {
        case .started:
            return language.pick(
                "已使用 \(GrowthCreditCopy.label(points: cost))，屏幕时间已打开 \(minutes) 分钟。",
                "Spent \(GrowthCreditCopy.label(points: cost, language: language)); screen time is open for \(minutes) minutes."
            )
        case .insufficientBalance:
            return language.pick(
                "成长积分不够，这次没有扣成长积分，也没有打开屏幕时间。",
                "Not enough Growth Points — nothing was deducted and screen time did not open."
            )
        case .alreadyActive:
            return language.pick(
                "已经有屏幕时间在进行中，没有叠加时间；成长积分已保护。",
                "A screen time session is already running; no extra time was added and your points are protected."
            )
        case .invalidMinutes:
            return language.pick(
                "这次兑换无效，没有扣成长积分。",
                "This exchange was invalid; no Growth Points were deducted."
            )
        case let .dailyLimitExceeded(remainingMinutes):
            return language.pick(
                "这次会超过家长设置的每日上限。今天还可以兑换 \(remainingMinutes) 分钟，没有扣成长积分。",
                "This would exceed the parent-set daily limit. \(remainingMinutes) minutes remain today, and no Growth Points were deducted."
            )
        case .deviceFailureRolledBack:
            return language.pick(
                "设备没有打开成功，刚才扣掉的成长积分已退回。",
                "The device did not open, so the deducted Growth Points were refunded."
            )
        }
    }

    static func icon(for result: StartRewardSessionResult) -> String {
        switch result {
        case .started: return "checkmark.seal.fill"
        case .insufficientBalance: return "leaf"
        case .alreadyActive: return "timer"
        case .invalidMinutes: return "exclamationmark.triangle"
        case .dailyLimitExceeded: return "clock.badge.exclamationmark"
        case .deviceFailureRolledBack: return "iphone.slash"
        }
    }

    static func accessibilitySuffix(for result: StartRewardSessionResult) -> String {
        switch result {
        case .started: return "started"
        case .insufficientBalance: return "insufficient"
        case .alreadyActive: return "already-active"
        case .invalidMinutes: return "invalid"
        case .dailyLimitExceeded: return "daily-limit"
        case .deviceFailureRolledBack: return "device-failure"
        }
    }
}
