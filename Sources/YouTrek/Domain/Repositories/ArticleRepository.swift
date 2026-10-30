import Foundation

protocol ArticleRepository: Sendable {
    /// Every readable article (without body content), across all projects.
    func fetchArticles() async throws -> [KnowledgeBaseArticle]
    /// IDs of articles whose title or body match the YouTrack text query.
    func searchArticleIDs(query: String) async throws -> [String]
    func fetchArticle(id: String) async throws -> KnowledgeBaseArticle
}
