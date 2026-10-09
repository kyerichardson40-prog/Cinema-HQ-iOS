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
}

private final class LocalTestSeeder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    private let infoHash: Data
    private let payload: Data
    private var bytes = Data()
    private var handshaken = false
    private var initialRequests: [(UInt32, UInt32, UInt32)] = []
    private var startedReplies = false

    init(infoHash: Data, payload: Data) {
        self.infoHash = infoHash
        self.payload = payload
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
            send(response, context: context)
        }
        while bytes.count >= 4 {
            let length = Int(bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            guard bytes.count >= 4 + length else { return }
            let message = Data(bytes.dropFirst(4).prefix(length))
            bytes.removeFirst(4 + length)
            guard let decoded = try? PeerMessage.decode(from: message) else { continue }
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
