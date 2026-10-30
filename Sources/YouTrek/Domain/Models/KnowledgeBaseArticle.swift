import Foundation

struct KnowledgeBaseArticle: Identifiable, Hashable, Sendable {
    let id: String
    let readableID: String
    let summary: String
    let content: String?
    let updatedAt: Date?
    let projectID: String?
    let parentID: String?
    let hasChildren: Bool

    func withContent(_ content: String?) -> KnowledgeBaseArticle {
        KnowledgeBaseArticle(
            id: id,
            readableID: readableID,
            summary: summary,
            content: content,
            updatedAt: updatedAt,
            projectID: projectID,
            parentID: parentID,
            hasChildren: hasChildren
        )
    }
}

struct KnowledgeBaseTreeRow: Identifiable, Hashable, Sendable {
    let article: KnowledgeBaseArticle
    let depth: Int
    var id: String { article.id }
}

enum KnowledgeBaseTree {
    /// Flattens articles into depth-annotated rows, parents before children, siblings sorted by title.
    /// Articles whose parent is outside the given set are treated as roots.
    static func rows(from articles: [KnowledgeBaseArticle]) -> [KnowledgeBaseTreeRow] {
        let ids = Set(articles.map(\.id))
        let children = Dictionary(grouping: articles) { article -> String? in
            guard let parentID = article.parentID, ids.contains(parentID) else { return nil }
            return parentID
        }
        var rows: [KnowledgeBaseTreeRow] = []
        var visited = Set<String>()

        func append(parent: String?, depth: Int) {
            let siblings = (children[parent] ?? []).sorted {
                $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending
            }
            for article in siblings where visited.insert(article.id).inserted {
                rows.append(KnowledgeBaseTreeRow(article: article, depth: depth))
                append(parent: article.id, depth: depth + 1)
            }
        }
        append(parent: nil, depth: 0)
        return rows
    }
}
