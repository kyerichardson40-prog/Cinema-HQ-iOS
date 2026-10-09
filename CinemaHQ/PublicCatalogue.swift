import Foundation
import SwiftUI

struct PublicCataloguePage: Decodable {
    let metas: [PublicCatalogueTitle]
}

struct PublicCatalogueTitle: Codable {
    let id: String
    let name: String
    let type: String
    let description: String?
    let poster: String?
    let genres: [String]?
    let releaseInfo: String?
    let runtime: String?
    let adult: Bool?
    var media: MediaItem? {
        guard id.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil,
              ["movie", "series"].contains(type), adult != true,
              !(genres ?? []).contains("Adult") else { return nil }
        let isTV = type == "series"
        let posterURL = poster.flatMap { raw -> URL? in
            guard let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
            return url
        }
        return MediaItem(id: "imdb-\(type)-\(id)", title: name,
            synopsis: description ?? "Choose Find video sources to see available providers.",
            kind: isTV ? "TV Shows" : "Movies", genre: genres?.first ?? "Other",
            year: releaseInfo ?? "", duration: runtime ?? (isTV ? "TV series" : "Movie"),
            symbol: isTV ? "tv" : "film", tint: isTV ? .teal : .indigo,
            posterURL: posterURL)
    }
}

enum PublicCatalogueAPI {
    static func url(type: String, query: String) -> URL {
        let base = URL(string: "https://v3-cinemeta.strem.io/catalog")!
            .appendingPathComponent(type).appendingPathComponent(query.isEmpty ? "top.json" : "top")
        if query.isEmpty { return base }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: base.absoluteString + "/search=" + encoded + ".json")!
    }
    static func fetch(type: String, query: String) async throws -> [PublicCatalogueTitle] {
        var request = URLRequest(url: url(type: type, query: query))
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 5_000_000
        else { throw URLError(.badServerResponse) }
        return Array(try JSONDecoder().decode(PublicCataloguePage.self, from: data).metas.prefix(200))
    }
}
