import Foundation

enum BuildEnvironment: Sendable {
    case debug
    case release

    static var current: Self {
        #if DEBUG
        .debug
        #else
        .release
        #endif
    }
}

enum ConfigurationError: Error, LocalizedError, Equatable {
    case invalidURL
    case httpsRequired
    case credentialsNotAllowed
    case queryOrFragmentNotAllowed

    var errorDescription: String? {
        switch self {
        case .invalidURL: "服务器地址无效"
        case .httpsRequired: "服务器必须使用 HTTPS（本机调试除外）"
        case .credentialsNotAllowed: "服务器地址不能包含用户名或密码"
        case .queryOrFragmentNotAllowed: "服务器地址不能包含查询参数或片段"
        }
    }
}

struct AppConfiguration {
    static let productionBaseURL = URL(string: "https://senior.dafang-edu.com")!
    static let serverOverrideKey = "serverBaseURL"

    let defaults: UserDefaults
    let environment: BuildEnvironment

    init(defaults: UserDefaults = .standard, environment: BuildEnvironment = .current) {
        self.defaults = defaults
        self.environment = environment
    }

    var storedOverride: String? {
        defaults.string(forKey: Self.serverOverrideKey)
    }

    var baseURL: URL {
        guard environment == .debug, let rawValue = storedOverride,
              let url = try? validateServerOverride(rawValue) else {
            return Self.productionBaseURL
        }
        return url
    }

    func validateServerOverride(_ rawValue: String) throws -> URL {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty else {
            throw ConfigurationError.invalidURL
        }

        if components.user != nil || components.password != nil {
            throw ConfigurationError.credentialsNotAllowed
        }
        if components.query != nil || components.fragment != nil {
            throw ConfigurationError.queryOrFragmentNotAllowed
        }

        let comparisonHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        switch scheme {
        case "https":
            break
        case "http" where ["localhost", "127.0.0.1", "::1"].contains(comparisonHost):
            break
        default:
            throw ConfigurationError.httpsRequired
        }

        components.scheme = scheme
        components.host = host
        if components.path == "/" {
            components.path = ""
        } else {
            while components.path.count > 1, components.path.hasSuffix("/") {
                components.path.removeLast()
            }
        }
        guard let url = components.url else {
            throw ConfigurationError.invalidURL
        }
        return url
    }

    func applyServerOverride(_ rawValue: String) throws {
        let url = try validateServerOverride(rawValue)
        defaults.set(url.absoluteString, forKey: Self.serverOverrideKey)
    }

    func resetServerOverride() {
        defaults.removeObject(forKey: Self.serverOverrideKey)
    }
}
