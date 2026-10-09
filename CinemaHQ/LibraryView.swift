import SwiftUI
import AVKit

struct MediaItem: Identifiable {
    let id: String
    let title: String
    let synopsis: String
    let streamURL: URL?
}

enum DemoCatalog {
    static let items = [
        MediaItem(id: "welcome", title: "Cinema HQ", synopsis: "Native iOS foundation. Licensed provider adapters will follow compatibility analysis.", streamURL: nil)
    ]
}

struct LibraryView: View {
    @State private var query = ""
    @State private var selected: MediaItem?
    @State private var streamAddress = ""
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Open a video") {
                    TextField("HTTPS video URL", text: $streamAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(openStream)
                    Button("Play video", action: openStream)
                        .disabled(streamAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let validationError {
                        Text(validationError).foregroundStyle(.red)
                    }
                    Text("Enter a direct HLS or video link you have permission to play.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Library") {
                    ForEach(DemoCatalog.items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { item in
                        Button {
                            selected = item
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.title).font(.headline)
                                Text(item.synopsis).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Cinema HQ")
            .searchable(text: $query)
            .sheet(item: $selected) { item in
                NavigationStack {
                    Group {
                        if let url = item.streamURL {
                            StreamPlayerView(url: url)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "play.slash").font(.largeTitle)
                                Text("No authorised stream").font(.headline)
                                Text("Connect a licensed provider to play this title.").foregroundStyle(.secondary)
                            }.padding()
                        }
                    }
                    .navigationTitle(item.title)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selected = nil }
                        }
                    }
                }
            }
        }
    }

    private func openStream() {
        let address = streamAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: address),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else {
            validationError = "Enter a valid HTTPS video URL."
            return
        }
        validationError = nil
        selected = MediaItem(id: UUID().uuidString, title: "Your video", synopsis: "", streamURL: url)
    }
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
