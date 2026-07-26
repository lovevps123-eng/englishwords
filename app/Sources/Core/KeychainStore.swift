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

    /// 落盘 access/refresh 两个条目；只要有一个写入失败（SecItemAdd 返回非 errSecSuccess）就整体判失败，
    /// 调用方（AuthStore.login）需要据此提示用户而不是误判为已登录。
    @discardableResult
    func saveTokens(access: String, refresh: String) -> Bool {
        let savedAccess = save(access, account: accessAccount)
        let savedRefresh = save(refresh, account: refreshAccount)
        return savedAccess && savedRefresh
    }

    func loadTokens() -> AuthTokens? {
        guard let access = load(account: accessAccount),
              let refresh = load(account: refreshAccount) else {
            return nil
        }
        return AuthTokens(access: access, refresh: refresh)
    }

    @discardableResult
    func clear() -> Bool {
        let deletedAccess = delete(account: accessAccount)
        let deletedRefresh = delete(account: refreshAccount)
        return deletedAccess && deletedRefresh
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// 返回 SecItemAdd 是否成功。先删除旧条目再插入，所以正常路径不会撞见 errSecDuplicateItem；
    /// 如果仍然出现非 errSecSuccess（包括 duplicate），一律视为失败，不再假装写入成功。
    @discardableResult
    private func save(_ value: String, account: String) -> Bool {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
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

    /// 返回 SecItemDelete 是否成功；条目本就不存在（errSecItemNotFound）也算成功，因为最终状态符合预期。
    @discardableResult
    private func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
