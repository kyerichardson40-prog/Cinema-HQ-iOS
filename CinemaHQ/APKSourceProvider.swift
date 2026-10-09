import Foundation
import SwiftUI

enum APKProvider: String, CaseIterable, Identifiable {
    case torrentio = "Torrentio"
    case torrentclaw = "TorrentClaw"
    case vadapav = "VadaPav"
    var id: String { rawValue }
    var baseURL: URL {
        switch self {
        case .torrentio: return URL(string: "https://torrentio.strem.fun/sort=seeders")!
        case .torrentclaw: return URL(string: "https://torrentclaw.com/api/stremio")!
        case .vadapav: return URL(string: "https://stremio.vadapav.mov")!
        }
    }
}

struct ProviderStream: Decodable, Identifiable {
    var id: String { [provider.rawValue, name ?? "", title ?? description ?? "", infoHash ?? url ?? "", String(fileIdx ?? -1)].joined(separator: "|") }
    let name: String?
    let title: String?
    let description: String?
    let infoHash: String?
    let fileIdx: Int?
    let url: String?
    let sources: [String]?
    var provider: APKProvider = .torrentio
    enum CodingKeys: String, CodingKey { case name, title, description, infoHash, fileIdx, url, sources }
    var label: String { name ?? provider.rawValue }
    var details: String { description ?? title ?? "Video source" }
    var directURL: URL? {
        guard let raw = url, let value = URL(string: raw), value.scheme?.lowercased() == "https",
              value.host != nil, value.user == nil, value.password == nil else { return nil }
        return value
    }
    var validHash: String? {
        guard let hash = infoHash?.lowercased(), hash.count == 40,
              hash.allSatisfy({ "0123456789abcdef".contains($0) }),
              fileIdx == nil || fileIdx! >= 0 else { return nil }
        return hash
    }
    var trackers: [String] {
        let offered = (sources ?? []).filter { $0.hasPrefix("tracker:") }.map { String($0.dropFirst(8)) }
        let defaults = ["udp://tracker.opentrackr.org:1337/announce", "udp://open.stealth.si:80/announce",
                        "https://tracker.webtorrent.io/announce"]
        var seen = Set<String>()
        let valid = offered.filter {
            guard let url = URL(string: $0), let host = url.host, !host.isEmpty else { return false }
            return ["udp", "https"].contains(url.scheme?.lowercased() ?? "") &&
                url.user == nil && url.password == nil && seen.insert($0).inserted
        }
        return (Array(valid.filter { !defaults.contains($0) }.prefix(9)) + defaults)
    }
}

struct TorrentVideoSource {
    enum Location {
        case verified(URL, String, String)
        case magnet(String, Int?, [String])
    }
    let title: String
    let providerName: String
    let sizeDescription: String
    let creditLabel: String
    let creditURL: URL
    let location: Location

    init(free: FreeMovieSource) {
        title = free.title; providerName = "WebTorrent"
        sizeDescription = "About \(free.sizeMB) MB."
        creditLabel = "\(free.title) • Blender Foundation • Film credits and licence"
        creditURL = free.creditURL
        location = .verified(free.metadataURL, free.metadataSHA256, free.videoPath)
    }
    init?(stream: ProviderStream, title: String) {
        guard let hash = stream.validHash else { return nil }
        self.title = title; providerName = stream.provider.rawValue
        sizeDescription = "File size will be checked before streaming."
        creditLabel = "Source: " + stream.provider.rawValue
        creditURL = stream.provider.baseURL
        location = .magnet(hash, stream.fileIdx, stream.trackers)
    }
}

enum ProviderError: LocalizedError {
    case invalidID, unavailable(Int), response
    var errorDescription: String? {
        switch self {
        case .invalidID: return "Enter an IMDb ID such as tt1254207."
        case .unavailable(let status): return "Provider returned HTTP \(status). Try another source."
        case .response: return "The provider returned an unreadable response."
        }
    }
}

enum ProviderAPI {
    static func streamURL(provider: APKProvider, imdbID: String, series: Bool,
                          season: Int, episode: Int) throws -> URL {
        guard imdbID.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil,
              season >= 1, season <= 100, episode >= 1, episode <= 1000 else { throw ProviderError.invalidID }
        let identifier = series ? "\(imdbID):\(season):\(episode)" : imdbID
        return provider.baseURL.appendingPathComponent("stream")
            .appendingPathComponent(series ? "series" : "movie")
            .appendingPathComponent(identifier + ".json")
    }
    static func fetch(provider: APKProvider, imdbID: String, series: Bool,
                      season: Int, episode: Int) async throws -> [ProviderStream] {
        var request = URLRequest(url: try streamURL(provider: provider, imdbID: imdbID,
                                                    series: series, season: season, episode: episode))
        request.timeoutInterval = 25
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.response }
        guard http.statusCode == 200 else { throw ProviderError.unavailable(http.statusCode) }
        guard data.count <= 5_000_000 else { throw ProviderError.response }
        struct Envelope: Decodable { let streams: [ProviderStream] }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        var seen = Set<String>()
        return envelope.streams.prefix(200).compactMap { original in
            var stream = original; stream.provider = provider
            guard stream.directURL != nil || stream.validHash != nil,
                  seen.insert(stream.id).inserted else { return nil }
            return stream
        }
    }

    static func imdbID(for item: MediaItem) async throws -> String? {
        if item.id.hasPrefix("imdb-"), let id = item.id.split(separator: "-").last {
            let value = String(id)
            if value.range(of: "^tt[0-9]{5,12}$", options: .regularExpression) != nil { return value }
        }
        let freeIDs = ["free-bunny": "tt1254207", "free-sintel": "tt1727587"]
        if let id = freeIDs[item.id] { return id }
        guard item.id.hasPrefix("tmdb-"), let token = CatalogueCredential.read(),
              let number = item.id.split(separator: "-").last else { return nil }
        let type = item.kind == "TV Shows" ? "tv" : "movie"
        var request = URLRequest(url: URL(string: "https://api.themoviedb.org/3/\(type)/\(number)/external_ids")!)
        request.timeoutInterval = 20
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ProviderError.response }
        struct IDs: Decodable { let imdb_id: String? }
        return try JSONDecoder().decode(IDs.self, from: data).imdb_id
    }
}

struct APKSourceView: View {
    let item: MediaItem?
    @Environment(\.dismiss) private var dismiss
    @State private var imdbID = ""
    @State private var series = false
    @State private var season = 1
    @State private var episode = 1
    @State private var provider = APKProvider.torrentio
    @State private var streams: [ProviderStream] = []
    @State private var loading = false
    @State private var error: String?
    @State private var playback: PlaybackLink?
    @State private var selectedTorrent: ProviderStream?
    @State private var generation = UUID()

    var body: some View {
        NavigationStack {
            Form {
                sourceControls
                sourceResults
                sourceInformation
            }
            .navigationTitle("Video sources")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $playback) { link in
                NavigationStack {
                    StreamPlayerView(url: link.url).navigationTitle(item?.title ?? "Video")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { playback = nil } } }
                }
            }
            .sheet(item: $selectedTorrent) { stream in
                if let source = TorrentVideoSource(stream: stream, title: item?.title ?? imdbID) {
                    TorrentPrototypeView(torrent: source)
                }
            }
            .onChange(of: provider) { _, _ in generation = UUID(); streams = []; error = nil; loading = false }
            .onChange(of: imdbID) { _, _ in generation = UUID(); streams = []; error = nil; loading = false }
            .onChange(of: series) { _, _ in generation = UUID(); streams = []; error = nil; loading = false }
            .onChange(of: season) { _, _ in generation = UUID(); streams = []; error = nil; loading = false }
            .onChange(of: episode) { _, _ in generation = UUID(); streams = []; error = nil; loading = false }
            .task {
                guard let item else { return }
                series = item.kind == "TV Shows"
                do { imdbID = try await ProviderAPI.imdbID(for: item) ?? "" }
                catch { self.error = "Could not look up the IMDb ID. You can enter it here." }
            }
        }
    }
    private var sourceControls: some View {
        Section(item?.title ?? "Find video sources") {
                    Picker("Provider", selection: $provider) {
                        ForEach(APKProvider.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("IMDb ID", text: $imdbID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("TV episode", isOn: $series)
                    if series {
                        Stepper("Season \(season)", value: $season, in: 1...100)
                        Stepper("Episode \(episode)", value: $episode, in: 1...1000)
                    }
                    Button(loading ? "Finding sources…" : "Find sources") { Task { await search() } }
                        .disabled(loading || imdbID.isEmpty)
                    if loading { ProgressView() }
                    if let error { Text(error).foregroundStyle(.secondary) }
                }
    }
    private var sourceResults: some View {
        Section("Available sources") {
                    ForEach(streams) { stream in
                        Button {
                            if let url = stream.directURL { playback = PlaybackLink(url: url) }
                            else { selectedTorrent = stream }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(stream.label).font(.headline)
                                Text(stream.details).font(.caption).foregroundStyle(.secondary)
                                Label("Play video", systemImage: "play.circle")
                                    .font(.caption)
                            }
                        }
                    }
                }
    }
    private var sourceInformation: some View {
        Section("About sources") {
                    Text("These providers are referenced by the Android APK. Results and availability are controlled by each provider.")
                    Text("Torrent videos play while downloading. Seeking may pause briefly while new pieces arrive. MKV, MP4, M4V and MOV files are supported, including x265/HEVC video. Use the full-screen button to expand the player.")
                    Text("Only play videos you have permission to access. Peers can see your IP address while connected.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
    }
    private func search() async {
        let requestID = UUID()
        generation = requestID
        loading = true; error = nil; streams = []
        do {
            let result = try await ProviderAPI.fetch(provider: provider,
                imdbID: imdbID.trimmingCharacters(in: .whitespacesAndNewlines),
                series: series, season: season, episode: episode)
            guard generation == requestID else { return }
            streams = result
            if result.isEmpty { error = "No sources returned. Try another provider." }
        } catch {
            guard generation == requestID else { return }
            self.error = error.localizedDescription
        }
        if generation == requestID { loading = false }
    }
}

