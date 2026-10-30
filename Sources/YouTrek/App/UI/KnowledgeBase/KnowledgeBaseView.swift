import SwiftUI

/// Middle column: the project's articles as a tree, shown where the issue list normally is.
struct KnowledgeBaseListView: View {
    @ObservedObject var container: AppContainer
    @ObservedObject var appState: AppState
    let projectID: String
    let searchQuery: String

    @State private var contentMatchIDs: Set<String> = []

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rows: [KnowledgeBaseTreeRow] {
        let articles = container.knowledgeBaseArticles(for: projectID)
        guard !trimmedQuery.isEmpty else { return KnowledgeBaseTree.rows(from: articles) }
        // While searching, show a flat list: title matches plus server-side full-text matches.
        return articles
            .filter { $0.summary.localizedCaseInsensitiveContains(trimmedQuery) || contentMatchIDs.contains($0.id) }
            .sorted { $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending }
            .map { KnowledgeBaseTreeRow(article: $0, depth: 0) }
    }

    var body: some View {
        List(selection: $appState.selectedArticleID) {
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Image(systemName: row.article.hasChildren ? "folder" : "doc.text")
                        .foregroundStyle(.secondary)
                    Text(row.article.summary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let updatedAt = row.article.updatedAt {
                        Text(updatedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, CGFloat(row.depth) * 14)
                .tag(row.article.id)
                .accessibilityIdentifier("knowledgeBase.article.\(row.article.readableID)")
            }
        }
        .listStyle(.inset)
        // Ideal size matters while the list is still empty: the window follows the hosted content's ideal size.
        .frame(minWidth: 280, idealWidth: 560, maxWidth: .infinity, minHeight: 200, idealHeight: 700, maxHeight: .infinity)
        .overlay {
            if rows.isEmpty {
                if trimmedQuery.isEmpty {
                    ContentUnavailableView("No articles", systemImage: "books.vertical")
                } else {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }
        }
        .task(id: trimmedQuery) {
            guard !trimmedQuery.isEmpty else {
                contentMatchIDs = []
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let ids = await container.searchKnowledgeBaseArticleIDs(query: trimmedQuery)
            guard !Task.isCancelled else { return }
            contentMatchIDs = Set(ids)
        }
    }
}

/// Right column: the selected article, shown where the issue details normally are.
struct KnowledgeBaseArticleDetailView: View {
    @EnvironmentObject private var container: AppContainer
    @ObservedObject var appState: AppState

    @State private var loadedArticle: KnowledgeBaseArticle?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        content
            .frame(minWidth: 280, idealWidth: 400, maxWidth: .infinity, minHeight: 200, idealHeight: 700, maxHeight: .infinity)
            .task(id: appState.selectedArticleID) { await load() }
            .environment(\.openURL, OpenURLAction { url in
                // Links to other articles stay in the app; everything else opens in the browser.
                guard let article = container.knowledgeBaseArticle(for: url) else { return .systemAction }
                container.openKnowledgeBaseArticle(article)
                return .handled
            })
    }

    @ViewBuilder
    private var content: some View {
        if let article = loadedArticle, article.id == appState.selectedArticleID {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(article.summary)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Text(article.readableID)
                        if let updatedAt = article.updatedAt {
                            Text("Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Divider()
                    if let content = article.content, !content.isEmpty {
                        MarkdownTextView(text: content)
                    } else {
                        Text("This article is empty.").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        } else if let loadError {
            ContentUnavailableView("Couldn't load article", systemImage: "exclamationmark.triangle", description: Text(loadError))
        } else if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Select an article",
                systemImage: "doc.text",
                description: Text("Choose an article from the middle column to read it.")
            )
        }
    }

    private func load() async {
        loadError = nil
        guard let id = appState.selectedArticleID else {
            loadedArticle = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let article = try await container.loadKnowledgeBaseArticle(id: id)
            guard !Task.isCancelled else { return }
            loadedArticle = article
        } catch {
            guard !Task.isCancelled else { return }
            loadedArticle = nil
            loadError = error.localizedDescription
        }
    }
}
