import XCTest
import AVFoundation
import CoreVideo
@testable import CinemaHQ

final class ProgressivePlayerTests: XCTestCase {
    @MainActor
    func testAVPlayerStartsBeforeAllVideoBytesAreAvailable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let movie = root.appendingPathComponent("generated-stream-test.mp4")
        try await Self.makeMovie(at: movie)
        let bytes = try Data(contentsOf: movie)
        XCTAssertGreaterThan(bytes.count, 256 * 1024, "The fixture must contain enough data to leave an unavailable region.")

        let source = PartialMovie(bytes: bytes)
        let server = TorrentStreamingServer(fileLength: Int64(bytes.count)) { range in
            try await source.read(range)
        }
        let url = try await server.start()
        defer { server.stop() }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 8
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        defer {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        player.play()

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let seconds = player.currentTime().seconds
            if seconds.isFinite && seconds >= 0.5 { break }
            if item.status == .failed {
                throw FixtureError("AVPlayer rejected the progressive stream: \(item.error?.localizedDescription ?? "unknown error")")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(item.status, .readyToPlay, item.error?.localizedDescription ?? "Player did not become ready.")
        XCTAssertGreaterThanOrEqual(player.currentTime().seconds, 0.5, "Playback must advance while later video data is still unavailable.")
        let served = await source.servedByteCount()
        XCTAssertGreaterThan(served, 0)
        XCTAssertLessThan(served, Int64(bytes.count), "Playback must not depend on receiving the complete movie.")
        let unavailable = await source.unavailableByteCount()
        XCTAssertGreaterThan(unavailable, 0, "The simulated torrent must still have missing video data at playback startup.")
    }

    // Generate our own movie at test time; no downloaded media or binary fixture is needed.
    private static func makeMovie(at url: URL) async throws {
        let width = 320
        let height = 180
        let frameRate: Int32 = 10
        let frameCount = 300
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_500_000,
                AVVideoExpectedSourceFrameRateKey: Int(frameRate),
                AVVideoMaxKeyFrameIntervalKey: Int(frameRate)
            ]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(input) else { throw FixtureError("Cannot configure the test movie writer.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError("Cannot start the movie writer.") }
        writer.startSession(atSourceTime: .zero)
        var random: UInt32 = 12345
        let deadline = Date().addingTimeInterval(45)
        do {
            for frame in 0..<frameCount {
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed { throw writer.error ?? FixtureError("Movie encoding failed.") }
                    guard Date() < deadline else { throw FixtureError("Movie encoding timed out.") }
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
                var buffer: CVPixelBuffer?
                let result = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
                guard result == kCVReturnSuccess, let buffer else { throw FixtureError("Cannot allocate a test frame.") }
                CVPixelBufferLockBaseAddress(buffer, [])
                guard let base = CVPixelBufferGetBaseAddress(buffer) else {
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    throw FixtureError("Cannot access a test frame.")
                }
                let pixels = base.assumingMemoryBound(to: UInt8.self)
                let stride = CVPixelBufferGetBytesPerRow(buffer)
                for row in 0..<height {
                    for column in 0..<width {
                        // Moving noise prevents the encoder from collapsing the movie into a few tiny frames.
                        let offset = row * stride + column * 4
                        for channel in 0..<3 {
                            random = random &* 1_664_525 &+ 1_013_904_223
                            pixels[offset + channel] = UInt8(truncatingIfNeeded: random >> 24)
                        }
                        pixels[offset + 3] = 255
                    }
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: frameRate)) else {
                    throw writer.error ?? FixtureError("Cannot append the test frame.")
                }
            }
            input.markAsFinished()
            await withCheckedContinuation { continuation in
                writer.finishWriting { continuation.resume() }
            }
            guard writer.status == .completed else { throw writer.error ?? FixtureError("Cannot finish the test movie.") }
        } catch {
            writer.cancelWriting()
            throw error
        }
    }

    private struct FixtureError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

private actor PartialMovie {
    private let bytes: Data
    private let prefixEnd: Int64
    private let tailStart: Int64
    private var served: [Range<Int64>] = []

    init(bytes: Data) {
        self.bytes = bytes
        prefixEnd = Int64(bytes.count / 3)
        // Allow a small end-of-file probe without making the intervening video data available.
        tailStart = Int64(bytes.count - 64 * 1024)
    }

    func read(_ range: Range<Int64>) async throws -> Data {
        guard range.lowerBound >= 0, range.upperBound <= Int64(bytes.count) else {
            throw NSError(domain: "PartialMovie", code: 1)
        }
        while range.upperBound > prefixEnd && range.lowerBound < tailStart {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try Task.checkCancellation()
        served.append(range)
        return bytes.subdata(in: Int(range.lowerBound)..<Int(range.upperBound))
    }

    func unavailableByteCount() -> Int64 { tailStart - prefixEnd }

    func servedByteCount() -> Int64 {
        var total: Int64 = 0
        var current: Range<Int64>?
        for range in served.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let previous = current {
                if range.lowerBound <= previous.upperBound {
                    current = previous.lowerBound..<max(previous.upperBound, range.upperBound)
                } else {
                    total += previous.upperBound - previous.lowerBound
                    current = range
                }
            } else {
                current = range
            }
        }
        if let current { total += current.upperBound - current.lowerBound }
        return total
    }
}
