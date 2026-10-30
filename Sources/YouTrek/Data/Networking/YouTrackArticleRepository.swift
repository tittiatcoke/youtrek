import Foundation

final class YouTrackArticleRepository: ArticleRepository, Sendable {
    private let client: YouTrackAPIClient
    private let decoder: JSONDecoder

    init(client: YouTrackAPIClient, decoder: JSONDecoder = JSONDecoder()) {
        self.client = client
        self.decoder = decoder
    }

    convenience init(
        configuration: YouTrackAPIConfiguration,
        session: URLSession = .shared,
        monitor: NetworkRequestMonitor? = nil
    ) {
        self.init(client: YouTrackAPIClient(configuration: configuration, session: session, monitor: monitor))
    }

    func fetchArticles() async throws -> [KnowledgeBaseArticle] {
        let pageSize = 200
        var skip = 0
        var articles: [KnowledgeBaseArticle] = []

        while true {
            let queryItems: [URLQueryItem] = [
                URLQueryItem(name: "fields", value: "id,idReadable,summary,updated,project(id),parentArticle(id),childArticles(id)"),
                URLQueryItem(name: "\u{24}top", value: String(pageSize)),
                URLQueryItem(name: "\u{24}skip", value: String(skip))
            ]
            let data = try await client.get(path: "articles", queryItems: queryItems)
            let page = try decoder.decode([YouTrackArticle].self, from: data)
            articles.append(contentsOf: page.map { $0.toDomain() })
            if page.count < pageSize { break }
            skip += pageSize
        }
        return articles
    }

    func searchArticleIDs(query: String) async throws -> [String] {
        let queryItems = [
            URLQueryItem(name: "fields", value: "id"),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "\u{24}top", value: "200")
        ]
        let data = try await client.get(path: "articles", queryItems: queryItems)
        return try decoder.decode([YouTrackArticle.Ref].self, from: data).map(\.id)
    }

    func fetchArticle(id: String) async throws -> KnowledgeBaseArticle {
        let queryItems = [
            URLQueryItem(name: "fields", value: "id,idReadable,summary,content,updated,project(id),parentArticle(id),childArticles(id)")
        ]
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let data = try await client.get(path: "articles/\(encodedID)", queryItems: queryItems)
        return try decoder.decode(YouTrackArticle.self, from: data).toDomain()
    }
}

private struct YouTrackArticle: Decodable {
    struct Ref: Decodable { let id: String }

    let id: String
    let idReadable: String?
    let summary: String?
    let content: String?
    let updated: Int64?
    let project: Ref?
    let parentArticle: Ref?
    let childArticles: [Ref]?

    func toDomain() -> KnowledgeBaseArticle {
        KnowledgeBaseArticle(
            id: id,
            readableID: idReadable ?? id,
            summary: summary ?? "Untitled",
            content: content,
            updatedAt: updated.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) },
            projectID: project?.id,
            parentID: parentArticle?.id,
            hasChildren: !(childArticles ?? []).isEmpty
        )
    }
}
