// SettingsStore.swift — 设置持久化：难度档/每日新词量/服务器地址。
import Foundation

@Observable
final class SettingsStore {
    enum Keys {
        static let tier = "vocabTier"
        static let dailyNewLimit = "dailyNewLimit"
        static let serverBaseURL = "serverBaseURL"
    }

    static let tierDefault = 1
    static let dailyNewLimitDefault = 50

    private let defaults: UserDefaults
    private let configuration: AppConfiguration

    /// 难度档：1 基础 / 2 拔高。
    var tier: Int {
        didSet { defaults.set(tier, forKey: Keys.tier) }
    }

    /// 每日新词量，10...100，步长 10。
    var dailyNewLimit: Int {
        didSet { defaults.set(dailyNewLimit, forKey: Keys.dailyNewLimit) }
    }

    /// 服务器地址；空字符串表示未设置，APIClient 会回退到生产默认地址。
    var serverBaseURL: String {
        configuration.storedOverride ?? ""
    }

    init(defaults: UserDefaults = .standard, configuration: AppConfiguration? = nil) {
        self.defaults = defaults
        self.configuration = configuration ?? AppConfiguration(defaults: defaults)

        // UserDefaults.integer(forKey:) 未设置时返回 0，而 0 不是合法的 tier/dailyNewLimit 值，
        // 故用 0 作哨兵值映射回各自默认值。
        let storedTier = defaults.integer(forKey: Keys.tier)
        self.tier = storedTier == 0 ? Self.tierDefault : storedTier

        let storedLimit = defaults.integer(forKey: Keys.dailyNewLimit)
        self.dailyNewLimit = storedLimit == 0 ? Self.dailyNewLimitDefault : storedLimit

    }

    func applyServerBaseURL(_ rawValue: String) throws {
        try configuration.applyServerOverride(rawValue)
    }

    func resetServerBaseURL() {
        configuration.resetServerOverride()
    }
}
