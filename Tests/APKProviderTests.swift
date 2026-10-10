import XCTest
import SwiftTorrent
@testable import CinemaHQ

final class APKProviderTests: XCTestCase {
    func testMovieAndEpisodeRequestsUseAPKProviderEndpoints() throws {
        XCTAssertEqual(try ProviderAPI.streamURL(provider: .torrentio, imdbID: "tt1254207",
            series: false, season: 1, episode: 1).absoluteString,
            "https://torrentio.strem.fun/sort=seeders/stream/movie/tt1254207.json")
        XCTAssertEqual(try ProviderAPI.streamURL(provider: .torrentclaw, imdbID: "tt1234567",
            series: true, season: 2, episode: 4).absoluteString,
            "https://torrentclaw.com/api/stremio/stream/series/tt1234567:2:4.json")
        XCTAssertThrowsError(try ProviderAPI.streamURL(provider: .torrentio,
            imdbID: "../other", series: false, season: 1, episode: 1))
    }

    func testTorrentAndDirectResponsesAreValidated() throws {
        let sample = Data(#"{"name":"Torrentio","infoHash":"DD8255ECDC7CA55FB0BBF81323D87062DB1F6D1C","fileIdx":1,"sources":["tracker:udp://tracker.opentrackr.org:1337/announce","tracker:file:///tmp/x"]}"#.utf8)
        let stream = try JSONDecoder().decode(ProviderStream.self, from: sample)
        XCTAssertEqual(stream.validHash, "dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c")
        XCTAssertFalse(stream.trackers.contains("file:///tmp/x"))
        let invalid = try JSONDecoder().decode(ProviderStream.self,
            from: Data(#"{"infoHash":"not-a-hash","url":"http://example.com/video.mp4"}"#.utf8))
        XCTAssertNil(invalid.validHash)
        XCTAssertNil(invalid.directURL)
    }

    private func metadata(file: String) throws -> TorrentInfo {
        let text = "d4:infod5:filesld6:lengthi1e4:pathl\(file.utf8.count):\(file)eee4:name4:Film12:piece lengthi1e6:pieces20:00000000000000000000ee"
        return try TorrentInfo.parse(from: Data(text.utf8))
    }

    func testSelectsExactProviderFileAndRejectsUnsupportedFormats() throws {
        let mp4 = try metadata(file: "video.mp4")
        XCTAssertEqual(try TorrentPrototype.selectedVideo(info: mp4, fileIndex: 0), "Film/video.mp4")
        XCTAssertThrowsError(try TorrentPrototype.selectedVideo(info: mp4, fileIndex: 1))
        XCTAssertEqual(try TorrentPrototype.selectedVideo(info: metadata(file: "video.mkv"), fileIndex: nil), "Film/video.mkv")
        XCTAssertThrowsError(try TorrentPrototype.selectedVideo(info: metadata(file: "video.txt"), fileIndex: nil))
        let escaping = try metadata(file: "../video.mp4")
        XCTAssertThrowsError(try TorrentPrototype.validate(info: escaping,
            root: URL(fileURLWithPath: "/tmp/provider"),
            videoPath: "Film/../video.mp4", maximumSize: 16_000_000_000))
    }
}

