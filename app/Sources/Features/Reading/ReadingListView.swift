// ReadingListView.swift — 阅读 Tab 列表页：难度 segmented 筛选（全部/中级/高级）+
// 卡片列表（标题/来源/难度徽标）。点卡片进入 ReadingDetailView。
import SwiftUI

struct ReadingListView: View {
    @Environment(ReadingStore.self) private var store

    /// rawValue 直接对应后端 difficulty 查询参数取值（article_fetcher.py 落库的
    /// "beginner"/"intermediate"/"advanced"）；"全部" 不传该参数。
    enum DifficultyFilter: String, CaseIterable, Identifiable {
        case all = ""
        case intermediate = "intermediate"
        case advanced = "advanced"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "全部"
            case .intermediate: return "中级"
            case .advanced: return "高级"
            }
        }
    }

    @State private var filter: DifficultyFilter = .all
    @State private var articles: [ArticleSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("难度", selection: $filter) {
                    ForEach(DifficultyFilter.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                content
            }
            .navigationTitle("阅读")
            .navigationDestination(for: ArticleSummary.self) { article in
                ReadingDetailView(articleId: article.id)
            }
            .task { await load() }
            .onChange(of: filter) { _, _ in
                Task { await load() }
            }
            #if DEBUG
            // 冒烟自动化：RootView 编排器切到本 Tab 并等列表加载完后广播这个通知，
            // 这里直接 push 第一篇文章，模拟"点列表进详情"，供截图脚本拍 06-reading-detail。
            .onReceive(NotificationCenter.default.publisher(for: .smokeOpenFirstArticle)) { _ in
                if let first = articles.first {
                    path.append(first)
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("正在加载文章…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            errorView(errorMessage)
        } else if articles.isEmpty {
            emptyView
        } else {
            List(articles) { article in
                NavigationLink(value: article) {
                    ArticleCardView(article: article)
                }
            }
            .listStyle(.plain)
            .refreshable { await load() }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("暂无符合条件的文章")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text("加载失败")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("重试") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await store.fetchArticles(difficulty: filter.rawValue)
            articles = response.items
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct ArticleCardView: View {
    let article: ArticleSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(article.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(article.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                difficultyBadge
            }
        }
        .padding(.vertical, 4)
    }

    private var difficultyBadge: some View {
        Text(DifficultyText.label(for: article.difficulty))
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(DifficultyText.color(for: article.difficulty).opacity(0.15))
            .foregroundStyle(DifficultyText.color(for: article.difficulty))
            .clipShape(Capsule())
    }
}

/// 难度值 → 中文文案/配色，列表卡片与详情页共用。
enum DifficultyText {
    static func label(for difficulty: String) -> String {
        switch difficulty {
        case "advanced": return "高级"
        case "intermediate": return "中级"
        case "beginner": return "初级"
        default: return difficulty
        }
    }

    static func color(for difficulty: String) -> Color {
        switch difficulty {
        case "advanced": return .red
        case "intermediate": return .orange
        case "beginner": return .green
        default: return .gray
        }
    }
}

#Preview {
    ReadingListView()
        .environment(ReadingStore())
}
