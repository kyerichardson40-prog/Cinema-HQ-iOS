import XCTest
import SwiftTorrent
@testable import CinemaHQ

final class TorrentPrototypeTests: XCTestCase {
    private func metadata(name: String = "Big Buck Bunny", length: Int = 1) throws -> TorrentInfo {
        let string = "d4:infod5:filesld6:lengthi\(length)e4:pathl18:Big Buck Bunny.mp4eee4:name\(name.utf8.count):\(name)12:piece lengthi1e6:pieces20:00000000000000000000ee"
        return try TorrentInfo.parse(from: Data(string.utf8))
    }

    func testAcceptsContainedVideoPath() throws {
        let info = try metadata()
        XCTAssertNoThrow(try TorrentPrototype.validate(info: info, root: URL(fileURLWithPath: "/tmp/test-root")))
    }

    func testRejectsTraversal() throws {
        let info = try metadata(name: "../Big Buck Bunny")
        XCTAssertThrowsError(try TorrentPrototype.validate(info: info, root: URL(fileURLWithPath: "/tmp/test-root")))
    }

    func testRejectsInconsistentPieceCount() throws {
        let info = try metadata(length: 2)
        XCTAssertThrowsError(try TorrentPrototype.validate(info: info, root: URL(fileURLWithPath: "/tmp/test-root")))
    }

    func testPreallocatedFileIsNotAcceptedAsDownloadedVideo() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("Big Buck Bunny")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0]).write(to: directory.appendingPathComponent("Big Buck Bunny.mp4"))
        XCTAssertThrowsError(try TorrentPrototype.verifyFiles(info: metadata(), root: root))
    }
}
