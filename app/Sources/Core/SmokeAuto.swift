// SmokeAuto.swift — DEBUG-only 冒烟自动化开关。
// 仅当 SMOKE_AUTO、SMOKE_PHONE、SMOKE_PASSWORD 均由运行环境显式提供时，
// App 才会执行登录 → 切换 Tab → 背 3 词 → 打开阅读文章的生产冒烟流程。
// Release/TestFlight/App Store 构建不包含这段代码。
#if DEBUG
import Foundation

struct SmokeCredentials: Equatable {
    let phone: String
    let password: String
}

enum SmokeAuto {
    static var credentials: SmokeCredentials? {
        credentials(environment: ProcessInfo.processInfo.environment)
    }

    static var isEnabled: Bool {
        credentials != nil
    }

    static func credentials(environment: [String: String]) -> SmokeCredentials? {
        guard environment["SMOKE_AUTO"] == "1",
              let phone = environment["SMOKE_PHONE"], !phone.isEmpty,
              let password = environment["SMOKE_PASSWORD"], !password.isEmpty else {
            return nil
        }
        return SmokeCredentials(phone: phone, password: password)
    }

    /// 把当前步骤名写入 App 沙盒 Documents/smoke_marker.txt。外部截图脚本轮询这个文件的内容，
    /// 看到目标步骤名才截图——用真实数据/网络就绪来同步截图时机，而不是猜一个固定睡眠时长。
    static func writeMarker(_ step: String) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("smoke_marker.txt")
        try? step.write(to: url, atomically: true, encoding: .utf8)
    }
}

extension Notification.Name {
    /// RootView 的冒烟编排器在切到“阅读”Tab 并等列表加载后，用这个通知让 ReadingListView
    /// 自动 push 第一篇文章的详情页，模拟“点列表进详情”这一步。
    static let smokeOpenFirstArticle = Notification.Name("smokeOpenFirstArticle")
}
#endif
