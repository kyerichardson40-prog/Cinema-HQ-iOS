import XCTest
import Foundation
@testable import CinemaHQ

final class TorrentStreamingServerTests: XCTestCase {
    func testSingleRangesClampWithoutOverflowAndRejectInvalidRequests() throws {
        XCTAssertEqual(try TorrentHTTPRange(header: nil, fileLength: 100).bytes, 0..<100)
        XCTAssertEqual(try TorrentHTTPRange(header: "bytes=10-19", fileLength: 100).bytes, 10..<20)
        XCTAssertEqual(try TorrentHTTPRange(header: "bytes=90-", fileLength: 100).bytes, 90..<100)
        XCTAssertEqual(try TorrentHTTPRange(header: "bytes=-7", fileLength: 100).bytes, 93..<100)
        XCTAssertEqual(try TorrentHTTPRange(header: "bytes=-200", fileLength: 100).bytes, 0..<100)
        XCTAssertEqual(try TorrentHTTPRange(header: "bytes=95-9223372036854775807", fileLength: 100).bytes, 95..<100)
        for invalid in ["bytes=100-", "bytes=9-8", "bytes=-0", "bytes=1-2,4-5",
                        "bytes=+1-2", "bytes=1- 2", "items=0-2", "bytes=0-9223372036854775808"] {
            XCTAssertThrowsError(try TorrentHTTPRange(header: invalid, fileLength: 100), invalid)
        }
    }

    func testLiveHTTPHeadersRangesAndBoundedReads() async throws {
        let length: Int64 = 150_000
        let fixture = StreamingFixture(available: 0..<length)
        let server = TorrentStreamingServer(fileLength: length) { range in
            try await fixture.read(range)
        }
        let url = try await server.start()
        defer { server.stop() }
        let session = makeSession()
        defer { session.invalidateAndCancel() }

        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        let (headData, headResponse) = try await session.data(for: head)
        let headHTTP = try XCTUnwrap(headResponse as? HTTPURLResponse)
        XCTAssertEqual(headHTTP.statusCode, 200)
        XCTAssertTrue(headData.isEmpty)
        XCTAssertEqual(headHTTP.value(forHTTPHeaderField: "Content-Length"), String(length))
        XCTAssertEqual(headHTTP.value(forHTTPHeaderField: "Accept-Ranges"), "bytes")
        let beforeReads = await fixture.requestedRanges()
        XCTAssertTrue(beforeReads.isEmpty)

        var request = URLRequest(url: url)
        request.setValue("bytes=65520-131100", forHTTPHeaderField: "Range")
        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Range"), "bytes 65520-131100/150000")
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Length"), "65581")
        XCTAssertEqual(data, StreamingFixture.pattern(65_520..<131_101))
        let reads = await fixture.requestedRanges()
        XCTAssertEqual(reads, [65_520..<131_056, 131_056..<131_101])
        XCTAssertTrue(reads.allSatisfy { $0.upperBound - $0.lowerBound <= 65_536 })

        request.setValue("bytes=-7", forHTTPHeaderField: "Range")
        let (suffix, suffixResponse) = try await session.data(for: request)
        XCTAssertEqual((suffixResponse as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual(suffix, StreamingFixture.pattern(149_993..<150_000))

        request.setValue("bytes=150000-", forHTTPHeaderField: "Range")
        let (empty, failedResponse) = try await session.data(for: request)
        let failedHTTP = try XCTUnwrap(failedResponse as? HTTPURLResponse)
        XCTAssertEqual(failedHTTP.statusCode, 416)
        XCTAssertEqual(failedHTTP.value(forHTTPHeaderField: "Content-Range"), "bytes */150000")
        XCTAssertTrue(empty.isEmpty)

        let (_, missingResponse) = try await session.data(from: url.deletingLastPathComponent().appendingPathComponent("other.mp4"))
        XCTAssertEqual((missingResponse as? HTTPURLResponse)?.statusCode, 404)
    }

    func testMissingVerifiedBytesWaitWhileHeadSucceedsAndPlaybackRangesFinishEarly() async throws {
        let fixture = StreamingFixture(available: 0..<0)
        let server = TorrentStreamingServer(fileLength: 1_000_000) { range in
            try await fixture.read(range)
        }
        let url = try await server.start()
        defer { server.stop() }
        let session = makeSession()
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.setValue("bytes=0-32767", forHTTPHeaderField: "Range")
        let finished = CompletionFlag()
        let transfer = Task {
            let response = try await session.data(for: request)
            await finished.mark()
            return response
        }
        defer { transfer.cancel() }
        try await waitUntil { await fixture.requestedRanges().count == 1 }

        var head = URLRequest(url: url)
        head.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: head)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let completedBeforeVerification = await finished.value
        XCTAssertFalse(completedBeforeVerification)

        await fixture.grant(0..<32_768)
        let (data, playbackResponse) = try await transfer.value
        XCTAssertEqual((playbackResponse as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual(data, StreamingFixture.pattern(0..<32_768))
        // The remaining 967,232 bytes never became available.
        let available = await fixture.availableBytes()
        XCTAssertEqual(available, 32_768)
    }

    func testDisconnectedClientAndStopCancelPendingPieceReads() async throws {
        let fixture = StreamingFixture(available: 0..<0)
        let server = TorrentStreamingServer(fileLength: 1_000_000) { range in
            try await fixture.read(range)
        }
        let url = try await server.start()
        defer { server.stop() }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("bytes=0-127", forHTTPHeaderField: "Range")
        let first = Task { try await session.data(for: request) }
        try await waitUntil { await fixture.requestedRanges().count == 1 }
        first.cancel()
        do { _ = try await first.value; XCTFail("A cancelled request unexpectedly completed") }
        catch { }
        try await waitUntil { await fixture.cancelledReads() == 1 }

        request.setValue("bytes=100000-100127", forHTTPHeaderField: "Range")
        let second = Task { try await session.data(for: request) }
        try await waitUntil { await fixture.requestedRanges().count == 2 }
        server.stop()
        do { _ = try await second.value; XCTFail("A stopped server unexpectedly completed the range") }
        catch { }
        try await waitUntil { await fixture.cancelledReads() == 2 }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        return URLSession(configuration: configuration)
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !(await condition()) {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for HTTP read state")
                throw TestError.timeout
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private enum TestError: Error { case timeout }
}

private actor CompletionFlag {
    var value = false
    func mark() { value = true }
}

private actor StreamingFixture {
    private var available: Range<Int64>
    private var requests: [Range<Int64>] = []
    private var cancellations = 0

    init(available: Range<Int64>) { self.available = available }
    func grant(_ range: Range<Int64>) { available = range }
    func requestedRanges() -> [Range<Int64>] { requests }
    func availableBytes() -> Int64 { available.upperBound - available.lowerBound }
    func cancelledReads() -> Int { cancellations }

    func read(_ range: Range<Int64>) async throws -> Data {
        requests.append(range)
        do {
            while range.lowerBound < available.lowerBound || range.upperBound > available.upperBound {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            try Task.checkCancellation()
            return Self.pattern(range)
        } catch {
            if Task.isCancelled { cancellations += 1 }
            throw error
        }
    }

    nonisolated static func pattern(_ range: Range<Int64>) -> Data {
        Data(range.map { UInt8($0 % 251) })
    }
}
