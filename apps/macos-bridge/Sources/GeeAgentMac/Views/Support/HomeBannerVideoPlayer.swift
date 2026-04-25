import AVKit
import SwiftUI

/// A full-bleed, looping, muted video layer for the Home banner.
struct HomeBannerVideoPlayer: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let player = makePlayer(url: url)
        context.coordinator.player = player

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill

        let container = LayerHostView(playerLayer: playerLayer)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        guard let host = nsView as? LayerHostView else { return }
        if coordinator.currentURL != url {
            coordinator.player?.pause()
            let player = makePlayer(url: url)
            coordinator.player = player
            coordinator.currentURL = url
            host.playerLayer.player = player
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.player = nil
    }

    private func makePlayer(url: URL) -> AVPlayer {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.play()

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        return player
    }

    final class Coordinator: NSObject {
        var player: AVPlayer?
        var currentURL: URL?
    }

    final class LayerHostView: NSView {
        let playerLayer: AVPlayerLayer

        init(playerLayer: AVPlayerLayer) {
            self.playerLayer = playerLayer
            super.init(frame: .zero)
            wantsLayer = true
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
