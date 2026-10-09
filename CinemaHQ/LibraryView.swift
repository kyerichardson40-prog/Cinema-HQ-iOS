import SwiftUI
import AVKit
import Security

struct MediaItem: Identifiable {
    let id: String
    let title: String
    let synopsis: String
    let kind: String
    let genre: String
    let year: String
    let duration: String
    let symbol: String
    let tint: Color
    var posterURL: URL? = nil
}

struct LibraryView: View {
    @StateObject private var catalogue = TMDBCatalogue()
    @State private var showingConnection = false
    @State private var query = ""
    @State private var category = "All"
    @State private var genre = "All genres"
    @State private var savedOnly = false
    @State private var selected: MediaItem?
    @State private var showingVideo = false
    @State private var showingTorrentTest = false
    @State private var showingAPKSources = false
    @AppStorage("cinemaHQ.watchlist") private var savedIDs = ""
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 16)]

    private var watchlist: Set<String> {
        Set(savedIDs.split(separator: ",").map(String.init))
    }

    private var results: [MediaItem] {
        (savedOnly ? catalogue.cachedItems : catalogue.items).filter {
            (category == "All" || $0.kind == category) &&
            (genre == "All genres" || $0.genre == genre) &&
            (!savedOnly || watchlist.contains($0.id)) &&
            (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             "\($0.title) \($0.genre) \($0.synopsis)".localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Button { showingTorrentTest = true } label: {
                        Label("Torrent connection test", systemImage: "arrow.down.circle")
                    }.buttonStyle(.bordered)
                    Button { showingAPKSources = true } label: {
                        Label("Find video sources", systemImage: "play.rectangle.on.rectangle")
                    }.buttonStyle(.bordered)
                    HStack {
                        Label(catalogue.connected ? "TMDB catalogue" : "Cinemeta catalogue", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(results.count) titles").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Category", selection: $category) {
                        ForEach(["All", "Movies", "TV Shows"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented)

                    HStack {
                        Menu {
                            ForEach(["All genres"] + Set(catalogue.items.map(\.genre)).sorted(), id: \.self) { value in
                                Button(value) { genre = value }
                            }
                        } label: {
                            Label(genre, systemImage: "line.3.horizontal.decrease")
                        }
                        Spacer()
                        Button {
                            savedOnly.toggle()
                        } label: {
                            Label("My List", systemImage: savedOnly ? "bookmark.fill" : "bookmark")
                        }.tint(savedOnly ? .orange : .primary)
                    }.font(.subheadline)

                    if query.isEmpty && category == "All" && genre == "All genres" && !savedOnly,
                       let featured = catalogue.items.first {
                        Button { selected = featured } label: {
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(LinearGradient(colors: [featured.tint, .black], startPoint: .topTrailing, endPoint: .bottomLeading))
                                Image(systemName: featured.symbol)
                                    .font(.system(size: 100))
                                    .foregroundStyle(.white.opacity(0.18))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                    .padding(24)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(featured.id.hasPrefix("free-") ? "FEATURED FREE FILM" : "FEATURED TITLE").font(.caption.weight(.bold)).tracking(2)
                                    Text(featured.title).font(.largeTitle.bold())
                                    Text("\(featured.genre) • \(featured.year)").font(.subheadline)
                                    Label("Explore title", systemImage: "arrow.right.circle.fill")
                                        .font(.subheadline.bold()).padding(.top, 6)
                                }.padding(24)
                            }.frame(height: 230).foregroundStyle(.white)
                        }.buttonStyle(.plain)
                    }

                    if catalogue.loading { ProgressView("Loading catalogue…") }
                    if let message = catalogue.error {
                        Text(message).foregroundStyle(.secondary)
                        Button("Retry") { Task { await catalogue.load(query: query) } }
                    }
                    Text(savedOnly ? "My List" : "Browse library").font(.title2.bold())
                    if results.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: savedOnly ? "bookmark" : "magnifyingglass").font(.largeTitle)
                            Text(savedOnly ? "No saved titles match" : "No titles found").font(.headline)
                            Text("Try another search or change the filters.").foregroundStyle(.secondary)
                            Button("Reset filters") {
                                query = ""; category = "All"; genre = "All genres"; savedOnly = false
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(results) { item in
                                Button { selected = item } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        PosterView(item: item)
                                            .overlay(alignment: .topTrailing) {
                                                if watchlist.contains(item.id) {
                                                    Image(systemName: "bookmark.fill")
                                                        .padding(10).foregroundStyle(.white)
                                                }
                                            }
                                        Text(item.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                        Text("\(item.year) • \(item.genre)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Text(catalogue.connected ? "Catalogue information and posters from TMDB. Tap Play on a title to check the APK providers." : "Catalogue information and posters from Cinemeta. Choose Find video sources on a title to check the APK providers. No catalogue account needed.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                }.padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Cinema HQ")
            .searchable(text: $query, prompt: "Search titles or genres")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingConnection = true } label: {
                        Label("Catalogue settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingVideo = true } label: {
                        Label("Open Video", systemImage: "play.circle")
                    }
                }
            }
            .sheet(item: $selected) { item in
                TitleDetailView(item: item, isSaved: watchlist.contains(item.id)) {
                    var ids = watchlist
                    if ids.contains(item.id) { ids.remove(item.id) } else { ids.insert(item.id) }
                    savedIDs = ids.sorted().joined(separator: ",")
                }
            }
            .sheet(isPresented: $showingVideo) { OpenVideoView() }
            .sheet(isPresented: $showingTorrentTest) { TorrentPrototypeView() }
            .sheet(isPresented: $showingAPKSources) { APKSourceView(item: nil) }
            .sheet(isPresented: $showingConnection) { TMDBConnectionView(catalogue: catalogue) }
            .task(id: query + String(catalogue.connected)) {
                do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
                await catalogue.load(query: query)
            }
            .refreshable { await catalogue.load(query: query) }
        }
    }
}

struct PosterView: View {
    let item: MediaItem
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [item.tint, item.tint.opacity(0.35), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 18) {
                Image(systemName: item.symbol).font(.system(size: 48)).foregroundStyle(.white.opacity(0.8))
                Text(item.title.uppercased()).font(.title3.bold()).tracking(2)
                    .multilineTextAlignment(.center).foregroundStyle(.white)
            }.padding(16)
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .overlay {
            if let url = item.posterURL {
                GeometryReader { geometry in
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: { Color.clear }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                }.clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .accessibilityHidden(true)
    }
}

struct TitleDetailView: View {
    let item: MediaItem
    let isSaved: Bool
    let toggleSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var source: FreeMovieSource?
    @State private var showingAPKSources = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PosterView(item: item).frame(maxWidth: 220).frame(maxWidth: .infinity)
                    Text(item.title).font(.largeTitle.bold())
                    Text("\(item.kind) • \(item.year) • \(item.duration)").foregroundStyle(.secondary)
                    Text(item.genre).font(.caption.bold()).padding(8)
                        .background(item.tint.opacity(0.2), in: Capsule())
                    Text(item.synopsis).font(.body)
                    Button(action: toggleSaved) {
                        Label(isSaved ? "Remove from My List" : "Add to My List", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                    Button { showingAPKSources = true } label: {
                        Label(FreeMovieProvider.source(for: item) == nil ? "Play" : "Find video sources", systemImage: "play.rectangle").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                    if let available = FreeMovieProvider.source(for: item) {
                        Button { source = available } label: {
                            Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Text("Free film • WebTorrent").font(.headline)
                        Text("Watch while about \(available.sizeMB) MB arrives from peers. Keep the app open while watching.")
                            .foregroundStyle(.secondary)
                        Link("Blender Foundation • Film credits and licence", destination: available.creditURL)
                    } else {
                        Text("Catalogue information").font(.headline)
                        Text("Tap Play to check the APK providers for this title.")
                            .foregroundStyle(.secondary)
                    }
                }.padding(24)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $source) { TorrentPrototypeView(source: $0, libraryPlayback: true) }
            .sheet(isPresented: $showingAPKSources) { APKSourceView(item: item) }
        }
    }
}

struct OpenVideoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var error: String?
    @State private var playback: PlaybackLink?

    var body: some View {
        NavigationStack {
            Form {
                Section("Video link") {
                    TextField("HTTPS video URL", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(openVideo)
                    Button("Play video", action: openVideo)
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Text("Enter a direct HLS or video link you have permission to play.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Open Video")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $playback) { link in
                NavigationStack {
                    StreamPlayerView(url: link.url)
                        .navigationTitle("Your video")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { playback = nil } } }
                }
            }
        }
    }

    private func openVideo() {
        guard let components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else {
            error = "Enter a valid HTTPS video URL."
            return
        }
        error = nil
        playback = PlaybackLink(url: url)
    }
}

struct PlaybackLink: Identifiable {
    let id = UUID()
    let url: URL
}

enum CatalogueCredential {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.cinemahq.tmdb",
        kSecAttrAccount as String: "read-token"
    ]
    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var request = query
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(request as CFDictionary, nil) == errSecSuccess
    }
    static func remove() { SecItemDelete(query as CFDictionary) }
}

private struct TMDBPage: Decodable { let results: [TMDBTitle] }
private struct TMDBTitle: Codable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let poster_path: String?
    let release_date: String?
    let first_air_date: String?
    let genre_ids: [Int]?
    let adult: Bool?
    var isTV: Bool { name != nil && title == nil }
    var media: MediaItem {
        let genres = [28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
                      99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
                      27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance",
                      878: "Sci-Fi", 53: "Thriller", 10752: "War", 37: "Western",
                      10759: "Action & Adventure", 10765: "Sci-Fi & Fantasy", 10762: "Kids",
                      10763: "News", 10764: "Reality", 10766: "Soap", 10767: "Talk", 10768: "War & Politics"]
        return MediaItem(id: "tmdb-\(isTV ? "tv" : "movie")-\(id)",
                         title: title ?? name ?? "Untitled",
                         synopsis: overview?.isEmpty == false ? overview! : "No synopsis available.",
                         kind: isTV ? "TV Shows" : "Movies",
                         genre: genre_ids?.first.flatMap { genres[$0] } ?? "Other",
                         year: String((release_date ?? first_air_date ?? "").prefix(4)),
                         duration: isTV ? "TV series" : "Movie",
                         symbol: isTV ? "tv" : "film", tint: isTV ? .teal : .indigo,
                         posterURL: poster_path.flatMap { URL(string: "https://image.tmdb.org/t/p/w500" + $0) })
    }
}

@MainActor
final class TMDBCatalogue: ObservableObject {
    @Published var items = FreeMovieProvider.items
    @Published var connected = CatalogueCredential.read() != nil
    @Published var loading = false
    @Published var error: String?
    @Published private var known: [TMDBTitle] = []
    @Published private var publicKnown: [PublicCatalogueTitle] = []
    private var generation = UUID()
    var cachedItems: [MediaItem] { FreeMovieProvider.items + known.map(\.media) + publicKnown.compactMap(\.media) }

    init() {
        if let data = UserDefaults.standard.data(forKey: "cinemaHQ.publicTitles"),
           let saved = try? JSONDecoder().decode([PublicCatalogueTitle].self, from: data) { publicKnown = saved }
        if let data = UserDefaults.standard.data(forKey: "cinemaHQ.tmdbTitles"),
           let saved = try? JSONDecoder().decode([TMDBTitle].self, from: data) { known = saved }
    }

    private func request(_ path: String, query: String, token: String) async throws -> TMDBPage {
        var components = URLComponents(string: "https://api.themoviedb.org/3/" + path)!
        components.queryItems = [URLQueryItem(name: "language", value: "en-GB"),
                                 URLQueryItem(name: "include_adult", value: "false")]
        if !query.isEmpty { components.queryItems?.append(URLQueryItem(name: "query", value: query)) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard response.statusCode == 200 else {
            throw NSError(domain: "TMDB", code: response.statusCode)
        }
        return try JSONDecoder().decode(TMDBPage.self, from: data)
    }

    func connect(_ token: String) async -> Bool {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await request("movie/popular", query: "", token: token)
            guard CatalogueCredential.save(token) else {
                error = "The token could not be saved securely. Please try again."
                return false
            }
            connected = true
            return true
        } catch {
            self.error = "Could not connect. Check your API Read Access Token and internet connection."
            return false
        }
    }

    func disconnect() {
        generation = UUID()
        CatalogueCredential.remove()
        connected = false
        loading = false
        error = nil
        items = FreeMovieProvider.items
    }

    private func loadPublic(query: String) async {
        let current = UUID()
        generation = current
        loading = true
        error = nil
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            async let movies = PublicCatalogueAPI.fetch(type: "movie", query: query)
            async let shows = PublicCatalogueAPI.fetch(type: "series", query: query)
            let (movieTitles, showTitles) = try await (movies, shows)
            let fetched = movieTitles + showTitles
            try Task.checkCancellation()
            guard current == generation else { return }
            let titles = fetched.filter { $0.media != nil && !["tt1254207", "tt1727587"].contains($0.id) }
            items = FreeMovieProvider.items + titles.compactMap(\.media)
            var indexed = Dictionary(publicKnown.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for title in titles { indexed[title.id] = title }
            publicKnown = Array(indexed.values)
            if let data = try? JSONEncoder().encode(publicKnown) {
                UserDefaults.standard.set(data, forKey: "cinemaHQ.publicTitles")
            }
            loading = false
        } catch {
            guard current == generation else { return }
            loading = false
            if Task.isCancelled { return }
            items = FreeMovieProvider.items
            self.error = "Could not load the catalogue. The free films are still available; tap Retry to reconnect."
        }
    }

    func load(query: String) async {
        guard let token = CatalogueCredential.read() else {
            await loadPublic(query: query)
            return
        }
        let current = UUID()
        generation = current
        loading = true
        error = nil
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let movies = try await request(query.isEmpty ? "movie/popular" : "search/movie", query: query, token: token)
            let shows = try await request(query.isEmpty ? "tv/popular" : "search/tv", query: query, token: token)
            try Task.checkCancellation()
            guard current == generation else { return }
            let fetched = (movies.results + shows.results).filter { $0.adult != true }
            items = FreeMovieProvider.items + fetched.map(\.media)
            var indexed = Dictionary(known.map { ($0.media.id, $0) }, uniquingKeysWith: { _, new in new })
            for title in fetched { indexed[title.media.id] = title }
            known = Array(indexed.values)
            if let data = try? JSONEncoder().encode(known) {
                UserDefaults.standard.set(data, forKey: "cinemaHQ.tmdbTitles")
            }
            loading = false
        } catch {
            guard current == generation else { return }
            loading = false
            if Task.isCancelled { return }
            items = FreeMovieProvider.items
            self.error = (error as NSError).code == 401 ?
                "TMDB rejected the token. Open catalogue settings to reconnect." :
                "Could not load TMDB. Check your connection and tap Retry."
        }
    }
}

struct TMDBConnectionView: View {
    @ObservedObject var catalogue: TMDBCatalogue
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var connecting = false
    var body: some View {
        NavigationStack {
            Form {
                Section("TMDB catalogue") {
                    Text("Connect the movie and TV information service referenced by the Android app.")
                    if catalogue.connected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                        Button("Disconnect", role: .destructive) { catalogue.disconnect() }
                    }
                    SecureField("API Read Access Token", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(connecting ? "Connecting…" : "Connect") {
                        connecting = true
                        Task {
                            if await catalogue.connect(token) { token = ""; dismiss() }
                            connecting = false
                        }
                    }.disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connecting)
                    if let error = catalogue.error { Text(error).foregroundStyle(.red) }
                    Link("Get your token from TMDB", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                    Text("Use your API Read Access Token, not your password. It is stored in your iPhone’s Keychain.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("About the catalogue") {
                    Link("TMDB • The Movie Database", destination: URL(string: "https://www.themoviedb.org")!)
                    Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    Link("Cinemeta • Public movie and TV catalogue", destination: URL(string: "https://v3-cinemeta.strem.io/manifest.json")!)
                    Text("Cinemeta supplies a public catalogue without an account. Connecting TMDB switches the catalogue to TMDB. Video sources are checked separately; My List stays on this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Catalogue")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .interactiveDismissDisabled(connecting)
        }
    }
}

