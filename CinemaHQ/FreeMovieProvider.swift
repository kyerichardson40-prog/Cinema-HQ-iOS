import SwiftUI

struct FreeMovieSource: Identifiable {
    let id: String
    let title: String
    let metadataURL: URL
    let metadataSHA256: String
    let videoPath: String
    let sizeMB: Int
    let creditURL: URL
}

enum FreeMovieProvider {
    static let sources: [FreeMovieSource] = [
        .init(id: "free-bunny", title: "Big Buck Bunny",
              metadataURL: URL(string: "https://webtorrent.io/torrents/big-buck-bunny.torrent")!,
              metadataSHA256: "13b4241c2fc4c2be3806287895566c0f596b9716643f2e679fd1482bcc7ed449",
              videoPath: "Big Buck Bunny/Big Buck Bunny.mp4", sizeMB: 277,
              creditURL: URL(string: "https://peach.blender.org/about/")!),
        .init(id: "free-sintel", title: "Sintel",
              metadataURL: URL(string: "https://webtorrent.io/torrents/sintel.torrent")!,
              metadataSHA256: "4c8fdad0414b4767546a0f92fe3d660a66edc32471874e7a1cfa97120317b84a",
              videoPath: "Sintel/Sintel.mp4", sizeMB: 130,
              creditURL: URL(string: "https://durian.blender.org/sharing/")!),
        .init(id: "free-cosmos", title: "Cosmos Laundromat",
              metadataURL: URL(string: "https://webtorrent.io/torrents/cosmos-laundromat.torrent")!,
              metadataSHA256: "ea0de7ae6edd064180765585a2ade72689a0cce0354ca244c054112c2f30741e",
              videoPath: "Cosmos Laundromat/Cosmos Laundromat.mp4", sizeMB: 221,
              creditURL: URL(string: "https://studio.blender.org/projects/cosmos-laundromat/")!)
    ]
    static func source(for item: MediaItem) -> FreeMovieSource? {
        // Resolve stable provider IDs only; never guess a source from a title.
        sources.first { $0.id == item.id }
    }
    static let items: [MediaItem] = [
        .init(id: "free-bunny", title: "Big Buck Bunny",
              synopsis: "A gentle rabbit stands up to three mischievous woodland bullies. A freely licensed short film by the Blender Foundation.",
              kind: "Movies", genre: "Animation", year: "2008", duration: "10 min",
              symbol: "hare.fill", tint: .green),
        .init(id: "free-sintel", title: "Sintel",
              synopsis: "A young traveller searches for the dragon she once rescued. A freely licensed fantasy short film by the Blender Foundation.",
              kind: "Movies", genre: "Fantasy", year: "2010", duration: "15 min",
              symbol: "flame.fill", tint: .orange),
        .init(id: "free-cosmos", title: "Cosmos Laundromat",
              synopsis: "A mysterious visitor offers a sheep on a remote island a chance at a different life. First Cycle, a freely licensed short film by the Blender Foundation.",
              kind: "Movies", genre: "Animation", year: "2015", duration: "12 min",
              symbol: "cloud.rain.fill", tint: .purple)
    ]
}
