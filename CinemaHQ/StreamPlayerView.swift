import SwiftUI
import UIKit
import AVFoundation
import VLCKit

/// One decoder and drawable survive transitions between inline and full screen.
@MainActor
final class StreamPlayback: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()
    let canvas = UIView()
    @Published private(set) var paused = false
    @Published private(set) var buffering = true
    @Published private(set) var error: String?
    @Published private(set) var seconds = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var seekable = false
    private var started = false
    private var updates: Task<Void, Never>?

    init(url: URL) {
        super.init()
        canvas.backgroundColor = .black
        player.drawable = canvas
        player.delegate = self
        let media = VLCMedia(url: url)
        media?.addOption(":network-caching=1500")
        if url.pathExtension.lowercased() == "mkv" {
            // FFmpeg defers the Matroska cue index until a seek; VLC's native
            // demuxer loads it before playback, which can wait on distant pieces.
            media?.addOption(":demux=avformat")
        }
        player.media = media
    }

    func start() {
        guard !started else { return }
        started = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        updates = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                self?.refresh()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func refresh() {
        seconds = max(0, Double(player.time.intValue) / 1000)
        duration = max(duration, Double(player.media?.length.intValue ?? 0) / 1000)
        seekable = player.isSeekable
    }

    func togglePause() {
        paused.toggle()
        if paused { player.pause() } else { player.play() }
    }

    func seek(to value: Double) {
        guard seekable, duration > 0, value.isFinite else { return }
        player.position = min(1, max(0, value / duration))
    }

    func stop() {
        updates?.cancel()
        updates = nil
        player.stop()
    }

    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if newState == .error {
                self.error = "This video could not be played. Try another source."
                self.buffering = false
            }
        }
    }

    nonisolated func mediaPlayerBufferingChanged(_ progress: Float) {
        Task { @MainActor [weak self] in self?.buffering = progress < 1 }
    }

    nonisolated func mediaPlayerLengthChanged(_ length: Int64) {
        Task { @MainActor [weak self] in self?.duration = max(0, Double(length) / 1000) }
    }

    deinit { updates?.cancel(); player.stop() }
}

private struct PlaybackCanvas: UIViewRepresentable {
    let canvas: UIView
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ container: UIView, context: Context) {
        guard canvas.superview !== container else { return }
        canvas.removeFromSuperview()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}

struct StreamPlayerView: View {
    @StateObject private var playback: StreamPlayback
    @State private var localFullScreen = false
    private let externalFullScreen: Binding<Bool>?

    init(url: URL, fullScreen: Binding<Bool>? = nil) {
        _playback = StateObject(wrappedValue: StreamPlayback(url: url))
        externalFullScreen = fullScreen
    }

    init(playback: StreamPlayback, fullScreen: Binding<Bool>) {
        _playback = StateObject(wrappedValue: playback)
        externalFullScreen = fullScreen
    }

    private var fullScreen: Binding<Bool> { externalFullScreen ?? $localFullScreen }

    var body: some View {
        // Only one visible container owns the drawable at a time.
        Group {
            if fullScreen.wrappedValue { Color.black.aspectRatio(16 / 9, contentMode: .fit) }
            else { PlayerPanel(playback: playback, fullScreen: fullScreen, expanded: false) }
        }
        .fullScreenCover(isPresented: fullScreen) {
            PlayerPanel(playback: playback, fullScreen: fullScreen, expanded: true)
                .background(.black).preferredColorScheme(.dark)
        }
        .onAppear { playback.start() }
        .onDisappear { if !fullScreen.wrappedValue { playback.stop() } }
    }
}

private struct PlayerPanel: View {
    @ObservedObject var playback: StreamPlayback
    @Binding var fullScreen: Bool
    let expanded: Bool
    @State private var scrub = 0.0
    @State private var scrubbing = false
    @State private var credits = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                PlaybackCanvas(canvas: playback.canvas)
                if playback.buffering && playback.error == nil && !playback.paused {
                    ProgressView("Buffering video…").padding().background(.black.opacity(0.7))
                }
            }
            .aspectRatio(expanded ? nil : 16 / 9, contentMode: .fit)
            if let error = playback.error { Text(error).font(.footnote).padding(.horizontal) }
            HStack {
                Button { playback.togglePause() } label: {
                    Image(systemName: playback.paused ? "play.fill" : "pause.fill")
                }.accessibilityLabel(playback.paused ? "Play" : "Pause")
                Text(clock(playback.seconds)).font(.caption).monospacedDigit()
                Slider(value: Binding(get: { scrubbing ? scrub : min(playback.seconds, max(1, playback.duration)) },
                                      set: { scrub = $0 }), in: 0...max(1, playback.duration),
                       onEditingChanged: { editing in
                           scrubbing = editing
                           if !editing { playback.seek(to: scrub) }
                       })
                    .disabled(!playback.seekable || playback.duration <= 0)
                    .accessibilityLabel("Playback position")
                Text(clock(playback.duration)).font(.caption).monospacedDigit()
                Button { fullScreen.toggle() } label: {
                    Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }.accessibilityLabel(expanded ? "Exit full screen" : "Full screen")
                Button { credits = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Player credits and license")
            }.padding(12)
            if expanded { Button("Done") { fullScreen = false }.padding(.bottom) }
        }
        .foregroundStyle(.white).background(.black)
        .sheet(isPresented: $credits) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Playback uses VLCKit by VideoLAN, licensed under LGPL 2.1 or later.")
                        Link("VLCKit source and build instructions", destination: URL(string: "https://github.com/videolan/vlckit/tree/2e0868f5ed40fe59cd92f377645fdcc260c6e759")!)
                        Text(license).font(.caption).textSelection(.enabled)
                    }.padding()
                }.navigationTitle("Player credits")
                    .toolbar { Button("Done") { credits = false } }
            }
        }
    }

    private func clock(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, seconds)) : 0
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) :
            String(format: "%d:%02d", value / 60, value % 60)
    }

    private var license: String {
        guard let url = Bundle.main.url(forResource: "VLCKit-LGPL", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }
}
