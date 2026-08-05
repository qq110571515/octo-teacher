import Foundation

enum BuildIdentity {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown.bundle"
    }

    static var commit: String {
        Bundle.main.object(forInfoDictionaryKey: "OctoTeacherCommit") as? String ?? "local"
    }

    static var shortVersionText: String {
        "\(version) (\(build))"
    }

    static var fullIdentityText: String {
        "\(shortVersionText) · \(bundleIdentifier) · \(commit)"
    }
}
