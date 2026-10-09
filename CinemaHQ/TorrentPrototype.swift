import SwiftUI
import SwiftTorrent
import CryptoKit

struct TorrentPrototypeView: View {
    @StateObject private var download = TorrentPrototype()
    @State private var playing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section("Big Buck Bunny") {
                    Text("Torrent playback test").font(.headline)
                    Text("Download this Creative Commons video from peers, then play it on your iPhone. About 264 MB. Keep the app open; Wi-Fi is recommended.")
                    Text(download.message).foregroundStyle(.secondary)
                    if download.running {
                        ProgressView(value: download.progress)
                        Text("\(Int(download.progress * 100))% • \(download.peers) peer connections")
                            .font(.caption).monospacedDigit()
                        Button("Cancel", role: .destructive) { download.cancel() }
                    } else if download.video != nil {
                        Button("Play downloaded video") { playing = true }
                        Button("Delete test download", role: .destructive) { download.clear() }
                    } else {
                        Button("Download test video") { download.start() }
                    }
                }
                Section("About this test") {
                    Text("This prototype downloads the complete video and verifies its pieces before playback. It does not search movie torrents or stream partially downloaded files.")
                    Text("Peers can see your IP address while connected.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("Big Buck Bunny • Blender Foundation • CC BY 3.0",
                         destination: URL(string: "https://peach.blender.org/about/")!)
                    Link("Test torrent from WebTorrent",
                         destination: URL(string: "https://webtorrent.io/free-torrents")!)
                    Link("Torrent engine: SwiftTorrent (MIT)",
                         destination: URL(string: "https://github.com/warppipe/swift-torrent")!)
                }
            }
            .navigationTitle("Torrent Test")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { download.cancel(); dismiss() }
            } }
            .sheet(isPresented: $playing) {
                if let url = download.video {
                    NavigationStack {
                        StreamPlayerView(url: url)
                            .navigationTitle("Big Buck Bunny")
                            .toolbar { ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { playing = false }
                            } }
                    }
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase != .active && download.running { download.cancel() }
            }
            .onDisappear { download.cancel() }
        }
    }
}

@MainActor
final class TorrentPrototype: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var progress = 0.0
    @Published private(set) var peers = 0
    @Published private(set) var video: URL?
    @Published private(set) var message = "Ready to test."
    private var task: Task<Void, Never>?
    private var folder: URL?
    private let metadataURL = URL(string: "https://webtorrent.io/torrents/big-buck-bunny.torrent")!
    private let metadataSHA256 = "13b4241c2fc4c2be3806287895566c0f596b9716643f2e679fd1482bcc7ed449"

    func start() {
        guard !running else { return }
        clear()
        running = true
        progress = 0
        peers = 0
        message = "Fetching test torrent…"
        task = Task { await run() }
    }

    func cancel() {
        guard running else { return }
        message = "Stopping peer connections…"
        task?.cancel()
    }

    func clear() {
        guard !running else { return }
        video = nil
        if let folder { try? FileManager.default.removeItem(at: folder) }
        folder = nil
        message = "Ready to test."
    }

    private func run() async {
        var session: SwiftTorrent.Session?
        var completedURL: URL?
        do {
            var request = URLRequest(url: metadataURL)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == metadataSHA256 else {
                throw PrototypeError.metadata
            }
            try Task.checkCancellation()
            let info = try TorrentInfo.parse(from: data)
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TorrentTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try Self.validate(info: info, root: root)
            let capacity = try root.deletingLastPathComponent().deletingLastPathComponent()
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage ?? 0
            guard capacity > info.totalSize + 50_000_000 else { throw PrototypeError.space }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            folder = root
            let engine = SwiftTorrent.Session(settings: SessionSettings(
                maxConnections: 20, maxConnectionsPerTorrent: 20,
                dhtEnabled: false, savePath: root.path
            ))
            session = engine
            let handle = try await engine.addTorrent(AddTorrentParams(
                torrentInfo: info, savePath: root.path, paused: true
            ))
            message = "Connecting to torrent peers…"
            try await handle.start()
            try Task.checkCancellation()
            var lastProgress = Date()
            var best = 0.0
            let started = Date()
            while true {
                try Task.checkCancellation()
                let status = await handle.status()
                progress = status.progress
                peers = status.numPeers
                if status.progress > best {
                    best = status.progress
                    lastProgress = Date()
                }
                message = peers == 0 ? "Waiting for peers…" : "Downloading verified pieces…"
                // Wait for the engine's completion transition, not just preallocated file size.
                if status.state == .seeding { break }
                if Date().timeIntervalSince(lastProgress) > 120 ||
                   Date().timeIntervalSince(started) > 1800 { throw PrototypeError.noProgress }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            message = "Checking the downloaded video…"
            // The library ignores disk-write failures. Verify disk contents independently.
            completedURL = try await Task.detached {
                try Self.verifyFiles(info: info, root: root)
                return root.appendingPathComponent("Big Buck Bunny/Big Buck Bunny.mp4")
            }.value
            try Task.checkCancellation()
        } catch {
            message = Task.isCancelled ? "Test cancelled." :
                ((error as? PrototypeError)?.description ?? "Test failed: " + error.localizedDescription)
        }
        if let session {
            do { try await session.shutdown() }
            catch { message = "Could not stop the torrent engine: " + error.localizedDescription; completedURL = nil }
        }
        if !Task.isCancelled, let completedURL {
            video = completedURL
            progress = 1
            message = "Download verified. Ready to play."
        } else if let folder {
            try? FileManager.default.removeItem(at: folder)
            self.folder = nil
            if Task.isCancelled { message = "Test cancelled." }
        }
        running = false
        task = nil
    }

    nonisolated static func validate(info: TorrentInfo, root: URL) throws {
        guard info.totalSize > 0, info.totalSize < 300_000_000,
              info.pieceLength > 0, info.pieceLength <= 4_194_304,
              info.pieces.count % 20 == 0,
              Int64(info.pieceCount) == (info.totalSize + Int64(info.pieceLength) - 1) / Int64(info.pieceLength)
        else { throw PrototypeError.metadata }
        let prefix = root.standardizedFileURL.path + "/"
        for file in info.files {
            guard file.length >= 0, !file.path.hasPrefix("/"),
                  !file.path.split(separator: "/").contains(".."),
                  root.appendingPathComponent(file.path).standardizedFileURL.path.hasPrefix(prefix)
            else { throw PrototypeError.metadata }
        }
        guard info.files.contains(where: { $0.path == "Big Buck Bunny/Big Buck Bunny.mp4" })
        else { throw PrototypeError.metadata }
    }

    nonisolated static func verifyFiles(info: TorrentInfo, root: URL) throws {
        var buffer = Data()
        var piece = 0
        func verifyPiece() throws {
            guard piece < info.pieceCount else { throw PrototypeError.integrity }
            let expected = info.pieces.subdata(in: piece * 20..<(piece + 1) * 20)
            guard Data(Insecure.SHA1.hash(data: buffer)) == expected else { throw PrototypeError.integrity }
            piece += 1
            buffer.removeAll(keepingCapacity: true)
        }
        for file in info.files {
            let reader = try FileHandle(forReadingFrom: root.appendingPathComponent(file.path))
            defer { try? reader.close() }
            var remaining = file.length
            while remaining > 0 {
                try Task.checkCancellation()
                let count = min(Int64(info.pieceLength - buffer.count), remaining)
                guard let bytes = try reader.read(upToCount: Int(count)), bytes.count == Int(count)
                else { throw PrototypeError.integrity }
                buffer.append(bytes)
                remaining -= count
                if buffer.count == info.pieceLength { try verifyPiece() }
            }
        }
        if !buffer.isEmpty { try verifyPiece() }
        guard piece == info.pieceCount else { throw PrototypeError.integrity }
    }
}

private enum PrototypeError: Error {
    case metadata, space, noProgress, integrity
    var description: String {
        switch self {
        case .metadata: return "The test torrent metadata could not be verified."
        case .space: return "Free at least 350 MB of storage and try again."
        case .noProgress: return "The torrent stopped making progress. Try again on another network."
        case .integrity: return "The downloaded video failed verification. Please retry."
        }
    }
}
