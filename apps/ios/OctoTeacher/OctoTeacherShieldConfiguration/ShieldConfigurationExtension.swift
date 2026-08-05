import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration()
    }

    private func configuration() -> ShieldConfiguration {
        let defaults = UserDefaults(suiteName: ScreenTimeSharedContract.appGroupIdentifier)
        let schoolIsActive = defaults?.bool(forKey: ScreenTimeSharedContract.schoolModeActiveKey) == true
        let isEnglish = ScreenTimeSharedContract.resolvedChildInterfaceLanguageRawValue(
            defaults: defaults
        ) == "english"
        let title = schoolIsActive
            ? (isEnglish ? "It's Focus Time" : "现在是专注时间")
            : (isEnglish ? "Ready for Play Time?" : "想玩一会儿？")
        let subtitle: String
        let primary: String
        if schoolIsActive {
            subtitle = isEnglish
                ? "Ask a parent if you need urgent access."
                : "有急事可以请家长帮忙。"
            primary = isEnglish ? "Ask for Help" : "紧急申请"
        } else {
            subtitle = isEnglish
                ? "Use Growth Points. It closes when time is up."
                : "用成长积分开启，时间到会自动休息。"
            primary = isEnglish ? "Use Points" : "用成长积分"
        }
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: UIColor.systemBackground,
            icon: UIImage(systemName: schoolIsActive ? "graduationcap.fill" : "hourglass.circle.fill"),
            title: .init(text: title, color: .label),
            subtitle: .init(text: subtitle, color: .secondaryLabel),
            primaryButtonLabel: .init(text: primary, color: .white),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: .init(
                text: isEnglish ? "Parent Help" : "请家长帮忙",
                color: .systemBlue
            )
        )
    }
}
