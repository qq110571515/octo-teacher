import Foundation

enum BrandIdentity {
    static let chineseName = "章鱼老师"
    static let englishName = "Octo Teacher"
    static let chineseTagline = "AI陪伴成长，让每一步更有方向。"
    static let englishTagline = "AI guidance for every step of growing up."
    static let logoAssetName = "OctoTeacherLogo"

    static var systemLanguage: AppInterfaceLanguage {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english
    }

    static var systemName: String { name(for: systemLanguage) }
    static var systemTagline: String { tagline(for: systemLanguage) }

    static func name(for language: AppInterfaceLanguage) -> String {
        language == .english ? englishName : chineseName
    }

    static func tagline(for language: AppInterfaceLanguage) -> String {
        language == .english ? englishTagline : chineseTagline
    }
}
