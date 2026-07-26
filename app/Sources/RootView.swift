// RootView.swift — 五 Tab 根视图：今日/单词/跟读/阅读/我的
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            PlaceholderView(text: "今日页面，敬请期待")
                .tabItem { Label("今日", systemImage: "sun.max") }

            PlaceholderView(text: "单词页面，敬请期待")
                .tabItem { Label("单词", systemImage: "rectangle.stack") }

            PlaceholderView(text: "跟读页面，敬请期待")
                .tabItem { Label("跟读", systemImage: "mic") }

            PlaceholderView(text: "阅读页面，敬请期待")
                .tabItem { Label("阅读", systemImage: "book") }

            PlaceholderView(text: "我的页面，敬请期待")
                .tabItem { Label("我的", systemImage: "person") }
        }
    }
}

/// 占位页：仅显示一段中文说明文字
private struct PlaceholderView: View {
    let text: String

    var body: some View {
        VStack {
            Text(text)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    RootView()
}
