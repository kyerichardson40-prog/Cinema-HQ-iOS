import XCTest
import SwiftTorrent
@testable import CinemaHQ

final class FreeMovieProviderTests: XCTestCase {
    func testEachLibraryTitleHasItsOwnVerifiedSource() {
        XCTAssertEqual(Set(FreeMovieProvider.items.map(\.id)).count, 3)
        for item in FreeMovieProvider.items {
            let source = FreeMovieProvider.source(for: item)
            XCTAssertEqual(source?.title, item.title)
            XCTAssertEqual(source?.metadataSHA256.count, 64)
            XCTAssertTrue(source?.videoPath.hasSuffix(".mp4") == true)
        }
    }

    func testMatchingTitleDoesNotResolveUnrelatedCatalogueID() {
        let item = MediaItem(id: "tmdb-movie-unrelated", title: "Sintel", synopsis: "",
                             kind: "Movies", genre: "Animation", year: "", duration: "",
                             symbol: "film", tint: .blue)
        XCTAssertNil(FreeMovieProvider.source(for: item))
    }

    func testSourceValidationRequiresTheSelectedVideoPath() throws {
        let info = try TorrentInfo.parse(from: Data("d4:infod5:filesld6:lengthi1e4:pathl10:Sintel.mp4eee4:name6:Sintel12:piece lengthi1e6:pieces20:00000000000000000000ee".utf8))
        let root = URL(fileURLWithPath: "/tmp/test-provider")
        XCTAssertNoThrow(try TorrentPrototype.validate(info: info, root: root, videoPath: "Sintel/Sintel.mp4"))
        XCTAssertThrowsError(try TorrentPrototype.validate(info: info, root: root, videoPath: "Cosmos Laundromat/Cosmos Laundromat.mp4"))
    }
}
