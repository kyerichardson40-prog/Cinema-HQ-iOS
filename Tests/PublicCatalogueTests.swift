import XCTest
@testable import CinemaHQ

final class PublicCatalogueTests: XCTestCase {
    func testSearchCannotChangeCataloguePath() {
        XCTAssertEqual(PublicCatalogueAPI.url(type: "series", query: "").absoluteString,
                       "https://v3-cinemeta.strem.io/catalog/series/top.json")
        XCTAssertEqual(PublicCatalogueAPI.url(type: "movie", query: "A/B & C").absoluteString,
                       "https://v3-cinemeta.strem.io/catalog/movie/top/search=A%2FB%20%26%20C.json")
    }

    func testDecodedTitleRetainsIMDbIdentityForSources() async throws {
        let json = Data(#"{"metas":[{"id":"tt1254207","name":"Big Buck Bunny","type":"movie","description":"A rabbit meets woodland bullies.","poster":"https://example.com/poster.jpg","genres":["Animation"],"releaseInfo":"2008","runtime":"10 min"}]}"#.utf8)
        let title = try JSONDecoder().decode(PublicCataloguePage.self, from: json).metas[0]
        let media = try XCTUnwrap(title.media)
        XCTAssertEqual(media.id, "imdb-movie-tt1254207")
        XCTAssertEqual(media.kind, "Movies")
        let sourceID = try await ProviderAPI.imdbID(for: media)
        XCTAssertEqual(sourceID, "tt1254207")
    }

    func testInvalidCatalogueIDsAreNotDisplayed() throws {
        let json = Data(#"{"metas":[{"id":"../wrong","name":"Unrelated","type":"movie"}]}"#.utf8)
        let title = try JSONDecoder().decode(PublicCataloguePage.self, from: json).metas[0]
        XCTAssertNil(title.media)
    }
}
