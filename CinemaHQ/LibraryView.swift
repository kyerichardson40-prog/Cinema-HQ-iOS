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

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle("Cinema HQ")
            .searchable(text: $query)
            .sheet(item: $selected) { item in
                NavigationStack {
                    Group {
                        if let url = item.streamURL {
                            VideoPlayer(player: AVPlayer(url: url))
                        } else {
                            ContentUnavailableView("No authorised stream", systemImage: "play.slash", description: Text("Connect a licensed provider to play this title."))
                        }
                    }
                    .navigationTitle(item.title)
                    .navigationBarItems(trailing: Button("Done") { selected = nil })
                }
            }
        }
    }
}
