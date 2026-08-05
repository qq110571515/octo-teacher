import Foundation
import Security

/// AI 服务商密钥存取端口。
/// 密钥只允许进 Keychain（真实实现）或测试内存（mock），
/// 绝不写入 octoteacher-family.json、UserDefaults、日志或事件流。
protocol AIProviderKeyStoring {
    func saveKey(_ key: String, for provider: AIProviderKind) -> Bool
    func loadKey(for provider: AIProviderKind) -> String?
    func deleteKey(for provider: AIProviderKind)
    func hasKey(for provider: AIProviderKind) -> Bool
}

extension AIProviderKeyStoring {
    func hasKey(for provider: AIProviderKind) -> Bool {
        loadKey(for: provider) != nil
    }
}

/// 真实 Keychain 实现：kSecClassGenericPassword，
/// service 固定为 App 自己的命名空间，account 为服务商标识。
final class KeychainAIProviderKeyStore: AIProviderKeyStoring {
    private let service = "com.octoteacher.aiprovider.byok"

    func saveKey(_ key: String, for provider: AIProviderKind) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }

        deleteKey(for: provider)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    func loadKey(for provider: AIProviderKind) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteKey(for provider: AIProviderKind) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// 测试与预览用内存实现，保证确定性、不碰真实 Keychain。
final class InMemoryAIProviderKeyStore: AIProviderKeyStoring {
    private var keys: [AIProviderKind: String] = [:]

    func saveKey(_ key: String, for provider: AIProviderKind) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        keys[provider] = trimmed
        return true
    }

    func loadKey(for provider: AIProviderKind) -> String? {
        keys[provider]
    }

    func deleteKey(for provider: AIProviderKind) {
        keys[provider] = nil
    }
}
