// SmokeAuto.swift — DEBUG-only 冒烟自动化开关。
// SMOKE_AUTO=1 时，App 启动后自动完成登录 → 依次切换 Tab → 背 3 词 → 打开一篇阅读文章，
// 用于对生产环境做全流程截图冒烟（见 app/README.md「冒烟测试」）。整个文件包在 #if DEBUG 里，
// Release/TestFlight/App Store 构建不含这段代码，不会被误触发；即便触发也需要显式设置的环境变量，
// 不影响任何普通用户路径。
#if DEBUG
import Foundation

enum SmokeAuto {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["SMOKE_AUTO"] == "1"
    }

    static var phone: String {
        ProcessInfo.processInfo.environment["SMOKE_PHONE"] ?? "<removed-smoke-phone>"
    }

    static var password: String {
        ProcessInfo.processInfo.environment["SMOKE_PASSWORD"] ?? "<removed-smoke-password>"
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
    /// RootView 的冒烟编排器在切到"阅读"Tab 并等列表加载后，用这个通知让 ReadingListView
    /// 自动 push 第一篇文章的详情页，模拟"点列表进详情"这一步。
    static let smokeOpenFirstArticle = Notification.Name("smokeOpenFirstArticle")
}
#endif
