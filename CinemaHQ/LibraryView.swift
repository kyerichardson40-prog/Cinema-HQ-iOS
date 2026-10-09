import SwiftUI
import AVKit

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
}

enum DemoCatalog {
    // Original sample titles; replace with a connected catalogue when available.
    static let items: [MediaItem] = [
        .init(id: "orbit", title: "Beyond Orbit", synopsis: "A lone navigator follows a mysterious signal beyond the edge of the solar system.", kind: "Movies", genre: "Sci-Fi", year: "2025", duration: "1h 48m", symbol: "moon.stars.fill", tint: .indigo),
        .init(id: "coast", title: "The Quiet Coast", synopsis: "Two estranged siblings return to their childhood seaside home for one unforgettable summer.", kind: "Movies", genre: "Drama", year: "2024", duration: "1h 36m", symbol: "water.waves", tint: .teal),
        .init(id: "midnight", title: "Midnight Run", synopsis: "A courier has one night to cross the city and uncover the truth behind a missing package.", kind: "Movies", genre: "Thriller", year: "2025", duration: "1h 52m", symbol: "building.2.fill", tint: .purple),
        .init(id: "wild", title: "Into the Wild Blue", synopsis: "Discover the extraordinary creatures and hidden landscapes beneath the ocean surface.", kind: "Movies", genre: "Documentary", year: "2023", duration: "1h 22m", symbol: "fish.fill", tint: .blue),
        .init(id: "cafe", title: "Corner Café", synopsis: "An unlikely friendship starts over a terrible cup of coffee and a very good idea.", kind: "Movies", genre: "Comedy", year: "2024", duration: "1h 31m", symbol: "cup.and.saucer.fill", tint: .orange),
        .init(id: "summit", title: "The Last Summit", synopsis: "A climbing team faces its greatest challenge on a remote mountain expedition.", kind: "Movies", genre: "Adventure", year: "2025", duration: "1h 44m", symbol: "mountain.2.fill", tint: .mint),
        .init(id: "signal", title: "The Signal", synopsis: "An observatory team receives a transmission that changes everything they thought they knew.", kind: "TV Shows", genre: "Sci-Fi", year: "2025", duration: "2 seasons", symbol: "antenna.radiowaves.left.and.right", tint: .cyan),
        .init(id: "harbour", title: "Harbour Street", synopsis: "Life, love and secrets unfold in a close-knit waterfront neighbourhood.", kind: "TV Shows", genre: "Drama", year: "2024", duration: "3 seasons", symbol: "sailboat.fill", tint: .teal),
        .init(id: "case", title: "Cold Case Files", synopsis: "A small detective unit revisits the cases everyone else has forgotten.", kind: "TV Shows", genre: "Thriller", year: "2025", duration: "1 season", symbol: "fingerprint", tint: .red),
        .init(id: "weekend", title: "Weekend People", synopsis: "Four friends turn ordinary weekends into extraordinary misadventures.", kind: "TV Shows", genre: "Comedy", year: "2024", duration: "2 seasons", symbol: "sun.max.fill", tint: .pink)
    ]
}

struct LibraryView: View {
    @State private var query = ""
    @State private var category = "All"
    @State private var genre = "All genres"
    @State private var savedOnly = false
    @State private var selected: MediaItem?
    @State private var showingVideo = false
    @AppStorage("cinemaHQ.watchlist") private var savedIDs = ""
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 16)]

    private var watchlist: Set<String> {
        Set(savedIDs.split(separator: ",").map(String.init))
    }

    private var results: [MediaItem] {
        DemoCatalog.items.filter {
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
                    HStack {
                        Label("Sample catalogue", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(results.count) titles").font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Category", selection: $category) {
                        ForEach(["All", "Movies", "TV Shows"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented)

                    HStack {
                        Menu {
                            ForEach(["All genres"] + Set(DemoCatalog.items.map(\.genre)).sorted(), id: \.self) { value in
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
                       let featured = DemoCatalog.items.first {
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
                                    Text("FEATURED SAMPLE").font(.caption.weight(.bold)).tracking(2)
                                    Text(featured.title).font(.largeTitle.bold())
                                    Text("Sci-Fi • 2025 • 1h 48m").font(.subheadline)
                                    Label("Explore title", systemImage: "arrow.right.circle.fill")
                                        .font(.subheadline.bold()).padding(.top, 6)
                                }.padding(24)
                            }.frame(height: 230).foregroundStyle(.white)
                        }.buttonStyle(.plain)
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
                    Text("Sample titles are for browsing only. Use Open Video to play your own video link.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                }.padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Cinema HQ")
            .searchable(text: $query, prompt: "Search titles or genres")
            .toolbar {
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
        .accessibilityHidden(true)
    }
}

struct TitleDetailView: View {
    let item: MediaItem
    let isSaved: Bool
    let toggleSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
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
                    Text("Sample title").font(.headline)
                    Text("This is a catalogue preview. No video or episodes are connected to this title.")
                        .foregroundStyle(.secondary)
                }.padding(24)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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

struct StreamPlayerView: View {
    @State private var player: AVPlayer
    @State private var playbackError: String?

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VStack {
            VideoPlayer(player: player)
            if let playbackError {
                Text(playbackError)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .onAppear { player.play() }
        .onDisappear { player.pause() }
        .onReceive(player.publisher(for: \.status)) { status in
            if status == .failed {
                playbackError = "This video could not be played. Check the link and try again."
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            guard let item = notification.object as? AVPlayerItem,
                  item === player.currentItem else { return }
            playbackError = "Playback stopped because the video could not be loaded."
        }
    }
}
