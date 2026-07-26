// ReadingDetailView.swift — 阅读详情页：默认只显英文段落，点段落展开中文对照；
// 英文正文按词切分可点，点词直接触发"加入生词本" → POST /api/vocab/collect（404 时 toast 提示）。
//
// 两种点词交互取一的说明（brief：整段长按弹菜单 vs 按词切分可点）：本实现选择"按词切分可点"——
// 每个词是独立的可点 Text，用自定义 FlowLayout 自动换行排布。理由：长按弹菜单依赖系统文本选择，
// 在自由拼接的纯文本段落上精确选中单个词、且不影响下面"点段落展开中文"的点按手势，实现复杂度更高；
// 逐词切分后每个词有明确、独立的点击目标，两种手势（点词收藏 / 点段落空白处展开中文）天然不冲突。
import SwiftUI

struct ReadingDetailView: View {
    let articleId: String

    @Environment(ReadingStore.self) private var store

    @State private var article: ArticleDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var expandedParagraphs: Set<Int> = []
    @State private var toastMessage: String?

    var body: some View {
        content
            .navigationTitle(article?.title ?? "文章")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    Text(toastMessage)
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("正在加载文章…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            errorView(errorMessage)
        } else if let article {
            articleBody(article)
        }
    }

    private func articleBody(_ article: ArticleDetail) -> some View {
        let enParagraphs = article.content.components(separatedBy: "\n\n")
        let cnParagraphs = article.contentCn?.components(separatedBy: "\n\n") ?? []

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(article)

                ForEach(Array(enParagraphs.enumerated()), id: \.offset) { index, paragraph in
                    paragraphView(
                        index: index,
                        english: paragraph,
                        chinese: index < cnParagraphs.count ? cnParagraphs[index] : nil
                    )
                }
            }
            .padding()
        }
    }

    private func header(_ article: ArticleDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(article.title)
                .font(.title2.bold())
            if let titleCn = article.titleCn {
                Text(titleCn)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(article.source)
                Text("·")
                Text(DifficultyText.label(for: article.difficulty))
                Text("·")
                Text("\(article.wordCount) 词")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Divider()
        }
    }

    private func paragraphView(index: Int, english: String, chinese: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TappableParagraph(text: english) { word in
                Task { await collect(word: word) }
            }

            if expandedParagraphs.contains(index), let chinese {
                Text(chinese)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard chinese != nil else { return }
            withAnimation {
                if expandedParagraphs.contains(index) {
                    expandedParagraphs.remove(index)
                } else {
                    expandedParagraphs.insert(index)
                }
            }
        }
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
            article = try await store.fetchArticleDetail(id: articleId)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func collect(word: String) async {
        guard !word.isEmpty else { return }
        let outcome = await store.collectWord(word)
        let message: String
        switch outcome {
        case .collected: message = "已加入生词本：\(word)"
        case .alreadyCollected: message = "已在生词本中：\(word)"
        case .notFound: message = "词典中没有这个词"
        case .failed(let reason): message = reason
        }
        showToast(message)
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toastMessage = nil }
        }
    }
}

/// 英文段落按词切分渲染：每个词是独立可点的 Text，用 FlowLayout 自动换行排布，点词触发收藏回调。
private struct TappableParagraph: View {
    let text: String
    let onTapWord: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(tokenizeArticleParagraph(text)) { token in
                Text(token.display)
                    .font(.body)
                    .onTapGesture {
                        guard !token.normalized.isEmpty else { return }
                        onTapWord(token.normalized)
                    }
            }
        }
    }
}

/// 简单换行流式布局：子视图按顺序摆放，超出可用宽度时换行。用于 TappableParagraph 逐词排布。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + bounds.width {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    NavigationStack {
        ReadingDetailView(articleId: "preview")
            .environment(ReadingStore())
    }
}
