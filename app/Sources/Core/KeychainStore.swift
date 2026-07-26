// KeychainStore.swift — access/refresh token 的 Keychain 持久化
import Foundation
import Security

struct AuthTokens: Equatable {
    let access: String
    let refresh: String
}

final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "com.masf.englishwords.auth"
    private let accessAccount = "accessToken"
    private let refreshAccount = "refreshToken"

    private init() {}

    func saveTokens(access: String, refresh: String) {
        save(access, account: accessAccount)
        save(refresh, account: refreshAccount)
    }

    func loadTokens() -> AuthTokens? {
        guard let access = load(account: accessAccount),
              let refresh = load(account: refreshAccount) else {
            return nil
        }
        return AuthTokens(access: access, refresh: refresh)
    }

    func clear() {
        delete(account: accessAccount)
        delete(account: refreshAccount)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func save(_ value: String, account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
