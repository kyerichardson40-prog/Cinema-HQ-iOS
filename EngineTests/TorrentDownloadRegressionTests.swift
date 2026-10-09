import XCTest
import Crypto
import NIOCore
import NIOPosix
@testable import SwiftTorrent

final class TorrentDownloadRegressionTests: XCTestCase {
    func testOutOfOrderBlocksRemainBuffered() async {
        let data = Data(repeating: 0xAB, count: 32768)
        let info = makeTorrentInfo(pieceLength: data.count, totalSize: Int64(data.count),
                                   pieceHashes: Data(Insecure.SHA1.hash(data: data)))
        let manager = PieceManager(info: info)
        await manager.startPiece(0)
        await manager.addBlock(pieceIndex: 0, offset: 16384, data: Data(data.suffix(16384)))
        let premature = await manager.completePiece(0)
        XCTAssertFalse(premature)
        await manager.addBlock(pieceIndex: 0, offset: 0, data: Data(data.prefix(16384)))
        let complete = await manager.completePiece(0)
        XCTAssertTrue(complete, "A late first block must complete the preserved piece.")
    }

    func testDownloadsBeyondRequestPipelineFromLocalSeeder() async throws {
        // Eight blocks exceed the client's five-request pipeline.
        let payload = Data((0..<131072).map { UInt8($0 % 251) })
        let info = makeTorrentInfo(pieceLength: payload.count, totalSize: Int64(payload.count),
                                   pieceHashes: Data(Insecure.SHA1.hash(data: payload)))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(LocalTestSeeder(infoHash: info.infoHash.bytes, payload: payload))
            }
            .bind(host: "127.0.0.1", port: 0).get()
        let pieces = PieceManager(info: info)
        let disk = DiskIO(basePath: root.path, fileStorage: FileStorage(info: info))
        try await disk.allocateFiles()
        let manager = PeerManager(infoHash: info.infoHash.bytes, peerID: generatePeerID(), group: group, maxConnections: 1)
        await manager.configure(pieceManager: pieces, piecePicker: PiecePicker(pieceCount: 1),
                                diskIO: disk, pieceCount: 1)
        let port = UInt16(server.localAddress!.port!)
        await manager.addPeer(address: "127.0.0.1", port: port)
        var complete = false
        for _ in 0..<200 {
            complete = await pieces.isComplete()
            if complete { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        // Give the disk write following hash verification time to finish.
        try await Task.sleep(nanoseconds: 100_000_000)
        let written = try? await disk.readPiece(index: 0)
        await manager.removePeer(address: "127.0.0.1", port: port)
        try await server.close().get()
        try await group.shutdownGracefully()
        XCTAssertTrue(complete, "Client stalled before downloading all eight blocks.")
        XCTAssertEqual(written, payload, "Verified peer data must reach disk unchanged.")
    }
    func testRejectedMagnetMetadataDoesNotAllocateFiles() async throws {
        enum Rejected: Error { case metadata }
        let payload = Data(repeating: 1, count: 32768)
        let info = makeTorrentInfo(pieceLength: payload.count, totalSize: Int64(payload.count),
                                   pieceHashes: Data(Insecure.SHA1.hash(data: payload)))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let magnet = MagnetLink(uri: "magnet:?xt=urn:btih:" + info.infoHash.description)!
        let handle = TorrentHandle(params: AddTorrentParams(magnetLink: magnet, savePath: root.path,
            metadataValidator: { _ in throw Rejected.metadata }),
            settings: SessionSettings(), group: group)
        try await handle.start()
        await handle.onMetadataReceived(info: info)
        do {
            _ = try await handle.waitForMetadata(timeout: 1)
            XCTFail("Rejected metadata must fail instead of returning a torrent.")
        } catch Rejected.metadata { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        try await group.shutdownGracefully()
    }

    func testMagnetMetadataThenDownloadsFromExistingPeer() async throws {
        let payload = Data((0..<131072).map { UInt8($0 % 251) })
        var metadata = Data("d6:lengthi131072e4:name9:video.mp412:piece lengthi131072e6:pieces20:".utf8)
        metadata.append(Data(Insecure.SHA1.hash(data: payload)))
        metadata.append(Data("e".utf8))
        var torrent = Data("d4:info".utf8); torrent.append(metadata); torrent.append(Data("e".utf8))
        let info = try TorrentInfo.parse(from: torrent)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(LocalTestSeeder(infoHash: info.infoHash.bytes, payload: payload, metadata: metadata))
            }.bind(host: "127.0.0.1", port: 0).get()
        let manager = PeerManager(infoHash: info.infoHash.bytes, peerID: generatePeerID(), group: group, maxConnections: 1)
        let pieces = PieceManager(info: info)
        let disk = DiskIO(basePath: root.path, fileStorage: FileStorage(info: info))
        await manager.configureMagnet(metadataExchange: MetadataExchange(infoHash: info.infoHash))
        await manager.setOnMetadataReceived { received in
            Task {
                guard received.infoHash == info.infoHash else { return }
                try? await disk.allocateFiles()
                await manager.configure(pieceManager: pieces, piecePicker: PiecePicker(pieceCount: 1), diskIO: disk, pieceCount: 1)
                await manager.resumeRequests()
            }
        }
        let port = UInt16(server.localAddress!.port!)
        await manager.addPeer(address: "127.0.0.1", port: port)
        var complete = false
        for _ in 0..<200 {
            complete = await pieces.isComplete()
            if complete { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let written = try? await disk.readPiece(index: 0)
        await manager.removePeer(address: "127.0.0.1", port: port)
        try await server.close().get()
        try await group.shutdownGracefully()
        XCTAssertTrue(complete, "Downloading must resume after magnet metadata arrives.")
        XCTAssertEqual(written, payload)
    }

    func testVerifiedPieceReturnsTheFinalBuffer() async {
        let payload = Data(repeating: 0xAC, count: 32768)
        let info = makeTorrentInfo(pieceLength: payload.count, totalSize: Int64(payload.count),
                                   pieceHashes: Data(Insecure.SHA1.hash(data: payload)))
        let pieces = PieceManager(info: info)
        await pieces.startPiece(0)
        await pieces.addBlock(pieceIndex: 0, offset: 16384, data: Data(payload.suffix(16384)))
        let stale = await pieces.getPieceBuffer(0)
        await pieces.addBlock(pieceIndex: 0, offset: 0, data: Data(payload.prefix(16384)))
        let verified = await pieces.takeVerifiedPiece(0)
        XCTAssertEqual(verified, payload)
        XCTAssertNotEqual(stale, verified)
        let duplicate = await pieces.takeVerifiedPiece(0)
        XCTAssertNil(duplicate)
    }

    func testRepeatedPeerDownloadsReachDiskUnchanged() async throws {
        for _ in 0..<10 { try await testDownloadsBeyondRequestPipelineFromLocalSeeder() }
    }

    func testStreamsSelectedFileAcrossPiecesBeforeTorrentCompletes() async throws {
        let payload = Data((0..<98304).map { UInt8($0 % 251) })
        let files: [TorrentInfo.FileEntry] = [
            .init(path: "extras.bin", length: 10001, offset: 0),
            .init(path: "video.mp4", length: 65536, offset: 10001),
            .init(path: "after.bin", length: 22767, offset: 75537)
        ]
        try await withStreamingHandle(payload: payload, pieceLength: 16384,
                                      files: files, allowedPieces: [1, 2, 3]) { handle, _ in
            let bytes = try await handle.readVerifiedRange(fileIndex: 1, offset: 15000, length: 25000, timeout: 5)
            XCTAssertEqual(bytes, payload.subdata(in: 25001..<50001))
            let status = await handle.status()
            XCTAssertLessThan(status.progress, 1, "Playback bytes must be available before the full torrent.")
            XCTAssertEqual(status.piecesCompleted, 3)
        }
    }

    func testTailDemandSkipsUnavailableMiddlePieces() async throws {
        let payload = Data((0..<131072).map { UInt8($0 % 251) })
        try await withStreamingHandle(payload: payload, pieceLength: 32768,
                                      allowedPieces: [3]) { handle, _ in
            let tail = try await handle.readVerifiedRange(fileIndex: 0, offset: 130000, length: 1072, timeout: 5)
            XCTAssertEqual(tail, Data(payload.suffix(1072)))
            let status = await handle.status()
            XCTAssertEqual(status.piecesCompleted, 1,
                "End-of-file metadata must not wait for missing middle pieces.")
            XCTAssertLessThan(status.progress, 1)
        }
    }

    func testCorruptPeerDataCannotBecomePlaybackBytes() async throws {
        let payload = Data(repeating: 0xAC, count: 65536)
        try await withStreamingHandle(payload: payload, pieceLength: 32768,
                                      allowedPieces: [0], corruptReplies: true) { handle, _ in
            do {
                _ = try await handle.readVerifiedRange(fileIndex: 0, offset: 0, length: 100, timeout: 0.4)
                XCTFail("Corrupt or sparse-file bytes must never reach playback.")
            } catch TorrentStreamingError.timeout { }
            let status = await handle.status()
            XCTAssertEqual(status.piecesCompleted, 0)
        }
    }

    func testCorruptedDiskPieceFailsClosedAfterCacheEviction() async throws {
        let payload = Data((0..<131072).map { UInt8($0 % 251) })
        try await withStreamingHandle(payload: payload, pieceLength: 32768,
                                      allowedPieces: [0, 1, 2]) { handle, root in
            _ = try await handle.readVerifiedRange(fileIndex: 0, offset: 0, length: 100, timeout: 5)
            let writer = try FileHandle(forWritingTo: root.appendingPathComponent("video.mp4"))
            try writer.seek(toOffset: 0)
            try writer.write(contentsOf: Data([0xFF]))
            try writer.close()
            // Two other pieces evict the immutable, bounded verified-piece cache.
            _ = try await handle.readVerifiedRange(fileIndex: 0, offset: 32768, length: 100, timeout: 5)
            _ = try await handle.readVerifiedRange(fileIndex: 0, offset: 65536, length: 100, timeout: 5)
            do {
                _ = try await handle.readVerifiedRange(fileIndex: 0, offset: 0, length: 100, timeout: 5)
                XCTFail("A changed disk piece must fail its SHA-1 verification.")
            } catch TorrentStreamingError.integrity { }
            guard case .integrity? = await handle.getStreamingFailure() else {
                return XCTFail("Disk integrity failure must be visible to the playback controller.")
            }
        }
    }

    func testDiskWriteFailureCannotPublishPreallocatedZeros() async throws {
        let payload = Data(repeating: 0xAC, count: 65536)
        try await withStreamingHandle(payload: payload, pieceLength: 32768,
                                      allowedPieces: [0], beforeConnect: { root in
            let video = root.appendingPathComponent("video.mp4")
            try FileManager.default.removeItem(at: video)
            try FileManager.default.createDirectory(at: video, withIntermediateDirectories: true)
        }) { handle, _ in
            do {
                _ = try await handle.readVerifiedRange(fileIndex: 0, offset: 0, length: 100, timeout: 5)
                XCTFail("Hash-verified RAM data must not be exposed after a failed disk write.")
            } catch TorrentStreamingError.diskFailure { }
            guard case .diskFailure? = await handle.getStreamingFailure() else {
                return XCTFail("Disk write failure must be visible to the playback controller.")
            }
        }
    }

    func testRangeCancellationAndBounds() async throws {
        let payload = Data(repeating: 0xAC, count: 65536)
        try await withStreamingHandle(payload: payload, pieceLength: 32768,
                                      allowedPieces: []) { handle, _ in
            for (offset, length) in [(Int64(-1), 1), (Int64(65535), 2), (Int64(0), 1_048_577)] {
                do {
                    _ = try await handle.readVerifiedRange(fileIndex: 0, offset: offset, length: length, timeout: 1)
                    XCTFail("Invalid or unbounded byte ranges must be rejected.")
                } catch TorrentStreamingError.invalidRange { }
            }
            let reader = Task {
                try await handle.readVerifiedRange(fileIndex: 0, offset: 0, length: 100, timeout: 5)
            }
            try await Task.sleep(for: .milliseconds(100))
            reader.cancel()
            do { _ = try await reader.value; XCTFail("Cancelled range must stop waiting.") }
            catch is CancellationError { }
            // The helper owns one bootstrap token. A cancelled reader must release its token,
            // leaving space for the other thirty-one bounded priorities.
            let tokens = (0..<31).map { _ in UUID() }
            for id in tokens {
                try await handle.setStreamingPriority(id: id, fileIndex: 0, offset: 0, length: 100, lookAhead: 0)
            }
            do {
                try await handle.setStreamingPriority(id: UUID(), fileIndex: 0, offset: 0, length: 100, lookAhead: 0)
                XCTFail("Priority request count must be bounded.")
            } catch TorrentStreamingError.invalidRange { }
            await handle.removeStreamingPriority(id: tokens[0])
            try await handle.setStreamingPriority(id: UUID(), fileIndex: 0, offset: 0, length: 100, lookAhead: 0)
            await handle.pause()
            do {
                _ = try await handle.readVerifiedRange(fileIndex: 0, offset: 0, length: 100, timeout: 1)
                XCTFail("Paused streaming must not expose cached or sparse-file bytes.")
            } catch TorrentStreamingError.stopped { }
        }
    }

    func testPriorityTokenReleaseAndBounds() {
        var picker = PiecePicker(pieceCount: 4)
        let empty = Bitfield(count: 4)
        var peer = Bitfield(count: 4)
        for index in 0..<4 { peer.set(index) }
        picker.addPeerBitfield(peer)
        picker.setStreamingRanges([(first: 3, last: 3), (first: 0, last: 1)])
        XCTAssertEqual(picker.pick(have: empty, peerHas: peer), 3)
        picker.setStreamingRanges([(first: 0, last: 1)])
        XCTAssertEqual(picker.pick(have: empty, peerHas: peer), 0)
        picker.setStreamingRanges([])
        XCTAssertEqual(picker.pick(have: empty, peerHas: peer), 0)
        picker.setStreamingRanges([(first: 0, last: 0), (first: 3, last: 3)],
                                  lookAhead: [(first: 1, last: 2)])
        var headReceived = empty
        headReceived.set(0)
        XCTAssertEqual(picker.pick(have: headReceived, peerHas: peer), 3,
                       "Exact tail/seek demand must outrank another request's forward buffer.")
    }

    func testPausedMagnetIgnoresLateMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let info = makeTorrentInfo(pieceLength: 32768, totalSize: 32768)
        let magnet = MagnetLink(uri: "magnet:?xt=urn:btih:" + info.infoHash.description)!
        let handle = TorrentHandle(params: AddTorrentParams(magnetLink: magnet, savePath: root.path),
                                   settings: SessionSettings(), group: group)
        try await handle.start()
        await handle.pause()
        await handle.onMetadataReceived(info: info)
        let status = await handle.status()
        XCTAssertEqual(status.state, .paused)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path),
                       "Late metadata must not restart a cancelled playback session.")
        try await group.shutdownGracefully()
    }

    private func withStreamingHandle(payload: Data, pieceLength: Int,
                                     files: [TorrentInfo.FileEntry]? = nil,
                                     allowedPieces: Set<Int>, corruptReplies: Bool = false,
                                     beforeConnect: (URL) throws -> Void = { _ in },
                                     operation: (TorrentHandle, URL) async throws -> Void) async throws {
        var hashes = Data()
        for offset in stride(from: 0, to: payload.count, by: pieceLength) {
            hashes.append(Data(Insecure.SHA1.hash(data: payload.subdata(in: offset..<min(offset + pieceLength, payload.count)))))
        }
        let info = TorrentInfo(infoHash: InfoHash.v1(from: payload), name: "video.mp4",
            pieceLength: pieceLength, pieces: hashes, totalSize: Int64(payload.count),
            files: files ?? [.init(path: "video.mp4", length: Int64(payload.count), offset: 0)],
            isPrivate: false, comment: nil, createdBy: nil, creationDate: nil,
            announceURL: nil, announceList: [])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let server = try await ServerBootstrap(group: group)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(StreamingTestSeeder(infoHash: info.infoHash.bytes,
                    payload: payload, pieceLength: pieceLength, allowedPieces: allowedPieces,
                    corruptReplies: corruptReplies))
            }.bind(host: "127.0.0.1", port: 0).get()
        let handle = TorrentHandle(params: AddTorrentParams(torrentInfo: info, savePath: root.path),
                                   settings: SessionSettings(), group: group)
        do {
            await handle.finishInitialization()
            try await handle.start()
            try beforeConnect(root)
            // Install demand before peer discovery so withheld middle pieces cannot delay a seek.
            let bootstrap = UUID()
            let first = allowedPieces.min() ?? 0
            if files == nil {
                try await handle.setStreamingPriority(id: bootstrap, fileIndex: 0,
                    offset: Int64(first * pieceLength), length: min(pieceLength, payload.count - first * pieceLength),
                    lookAhead: 0)
            }
            await handle.addStreamingTestPeer(address: "127.0.0.1", port: UInt16(server.localAddress!.port!))
            try await operation(handle, root)
            await handle.removeStreamingPriority(id: bootstrap)
        } catch {
            await handle.pause()
            try? await server.close().get()
            try? await group.shutdownGracefully()
            throw error
        }
        await handle.pause()
        try await server.close().get()
        try await group.shutdownGracefully()
    }

}

private final class StreamingTestSeeder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    private let infoHash: Data
    private let payload: Data
    private let pieceLength: Int
    private let allowedPieces: Set<Int>
    private let corruptReplies: Bool
    private var bytes = Data()
    private var handshaken = false

    init(infoHash: Data, payload: Data, pieceLength: Int, allowedPieces: Set<Int>, corruptReplies: Bool) {
        self.infoHash = infoHash; self.payload = payload; self.pieceLength = pieceLength
        self.allowedPieces = allowedPieces; self.corruptReplies = corruptReplies
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let incoming = buffer.readBytes(length: buffer.readableBytes) { bytes.append(contentsOf: incoming) }
        if !handshaken {
            guard bytes.count >= 68 else { return }
            bytes.removeFirst(68)
            handshaken = true
            let count = (payload.count + pieceLength - 1) / pieceLength
            var bitfield = Bitfield(count: count)
            // Advertise all pieces, but withhold selected pieces to model a stalled swarm.
            for index in 0..<count { bitfield.set(index) }
            var response = Handshake(infoHash: infoHash, peerID: generatePeerID()).encode()
            response.append(PeerMessage.bitfield(bitfield.toData()).encode())
            response.append(PeerMessage.unchoke.encode())
            send(response, context: context)
        }
        while bytes.count >= 4 {
            let length = Int(bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            guard bytes.count >= 4 + length else { return }
            let encoded = Data(bytes.dropFirst(4).prefix(length))
            bytes.removeFirst(4 + length)
            guard let message = try? PeerMessage.decode(from: encoded),
                  case .request(let index, let begin, let requestedLength) = message,
                  allowedPieces.contains(Int(index)) else { continue }
            let start = Int(index) * pieceLength + Int(begin)
            let end = start + Int(requestedLength)
            guard Int(begin) + Int(requestedLength) <= pieceLength, end <= payload.count else { continue }
            var block = payload.subdata(in: start..<end)
            if corruptReplies, !block.isEmpty { block[0] ^= 0xFF }
            send(PeerMessage.piece(index: index, begin: begin, block: block).encode(), context: context)
        }
    }

    private func send(_ data: Data, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.writeAndFlush(NIOAny(buffer), promise: nil)
    }
}

private final class LocalTestSeeder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    private let infoHash: Data
    private let payload: Data
    private let metadata: Data?
    private var bytes = Data()
    private var handshaken = false
    private var initialRequests: [(UInt32, UInt32, UInt32)] = []
    private var startedReplies = false

    init(infoHash: Data, payload: Data, metadata: Data? = nil) {
        self.infoHash = infoHash
        self.payload = payload
        self.metadata = metadata
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        if let incoming = buffer.readBytes(length: buffer.readableBytes) { bytes.append(contentsOf: incoming) }
        if !handshaken {
            guard bytes.count >= 68 else { return }
            bytes.removeFirst(68)
            handshaken = true
            // Deliver initial state immediately, in the same packet as the handshake.
            var response = Handshake(infoHash: infoHash, peerID: generatePeerID()).encode()
            response.append(PeerMessage.bitfield(Data([0x80])).encode())
            response.append(PeerMessage.unchoke.encode())
            if let metadata {
                let handshake = Data("d1:md11:ut_metadatai3ee13:metadata_sizei\(metadata.count)ee".utf8)
                response.append(PeerMessage.extended(id: 0, payload: handshake).encode())
            }
            send(response, context: context)
        }
        while bytes.count >= 4 {
            let length = Int(bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            guard bytes.count >= 4 + length else { return }
            let message = Data(bytes.dropFirst(4).prefix(length))
            bytes.removeFirst(4 + length)
            guard let decoded = try? PeerMessage.decode(from: message) else { continue }
            if case .extended(let id, _) = decoded, id == 3, let metadata {
                var response = Data("d8:msg_typei1e5:piecei0e10:total_sizei\(metadata.count)ee".utf8)
                response.append(metadata)
                send(PeerMessage.extended(id: 1, payload: response).encode(), context: context)
            }
            if case .request(let index, let begin, let length) = decoded {
                if !startedReplies {
                    initialRequests.append((index, begin, length))
                    if initialRequests.count == 5 {
                        startedReplies = true
                        for request in initialRequests.reversed() { reply(request, context: context) }
                    }
                } else {
                    reply((index, begin, length), context: context)
                }
            }
        }
    }

    private func reply(_ request: (UInt32, UInt32, UInt32), context: ChannelHandlerContext) {
        let (index, begin, length) = request
        guard index == 0, Int(begin) + Int(length) <= payload.count else { return }
        let block = payload.subdata(in: Int(begin)..<Int(begin + length))
        send(PeerMessage.piece(index: index, begin: begin, block: block).encode(), context: context)
    }

    private func send(_ data: Data, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.writeAndFlush(NIOAny(buffer), promise: nil)
    }
}

