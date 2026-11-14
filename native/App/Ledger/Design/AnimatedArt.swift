import SwiftUI
import Simulation
#if canImport(UIKit)
import UIKit
import AVFoundation
#endif

extension ArtLibrary {
    /// File stem of an item's art, as the art folder names it: outfits use their avatar slot, everything else category.id.
    static func artStem(_ category: ArtCategory, _ id: String) -> String {
        if category == .outfit, let art = SeasonRewards.item(id)?.art, !art.isEmpty { return art }
        return category.rawValue + "." + id
    }

    #if canImport(UIKit)
    /// The short loop of a legendary item or box (<stem>.anim.mp4 in Content/art); nil until the clip exists.
    static func animationURL(_ category: ArtCategory, _ id: String) -> URL? {
        guard let root = Bundle.main.resourcePath else { return nil }
        let path: String = root + "/Content/art/" + artStem(category, id) + ".anim.mp4"
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    /// The opening clip of a box (box.<kind>.open.mp4); a box without one borrows the cabinet's, a card pack the basic pack's.
    static func openingURL(_ kind: BoxKind) -> URL? {
        guard let root = Bundle.main.resourcePath else { return nil }
        let shared: String = kind.isCardPack ? "cardBasic" : "cabinet"
        for name in [kind.rawValue, shared] {
            let path: String = root + "/Content/art/box." + name + ".open.mp4"
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }
    #endif
}

/// Plays an item's loop over its still where the item is shown large. Nothing is drawn (the still stays) when the clip is missing,
/// Reduce Motion is on or Low Power Mode is on.
struct AnimatedClip: View {
    var category: ArtCategory
    var id: String
    /// Fill the frame (backdrops) instead of fitting inside it.
    var fill: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        Group {
            #if canImport(UIKit)
            if !reduceMotion, !lowPower, let url = ArtLibrary.animationURL(category, id) {
                LoopingPlayer(url: url, fill: fill).allowsHitTesting(false).accessibilityHidden(true)
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { (_: Notification) in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

#if canImport(UIKit)
/// A muted, seamless AVPlayer loop on a transparent layer (clips with an alpha channel keep it).
private struct LoopingPlayer: UIViewRepresentable {
    var url: URL
    var fill: Bool

    func makeUIView(context: Context) -> PlayerView {
        let v: PlayerView = PlayerView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.start(url: url, fill: fill)
        return v
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: Void) { view.stop() }
}

private final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }

    func start(url: URL, fill: Bool) {
        let item: AVPlayerItem = AVPlayerItem(url: url)
        let queue: AVQueuePlayer = AVQueuePlayer()
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        playerLayer?.player = queue
        playerLayer?.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        queue.play()
    }

    func stop() {
        player?.pause()
        looper?.disableLooping()
        playerLayer?.player = nil
        looper = nil
        player = nil
    }
}

/// Plays a clip once, sped up or slowed down to last `duration` seconds, and holds the last frame. The clips are drawn on black,
/// so the layer is screen-blended and the black falls away over a dark background.
struct OneShotClip: UIViewRepresentable {
    var url: URL
    var duration: Double

    func makeUIView(context: Context) -> OneShotView {
        let v: OneShotView = OneShotView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.start(url: url, duration: duration)
        return v
    }

    func updateUIView(_ view: OneShotView, context: Context) {}

    static func dismantleUIView(_ view: OneShotView, coordinator: Void) { view.stop() }
}

final class OneShotView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var player: AVPlayer?

    private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }

    func start(url: URL, duration: Double) {
        let item: AVPlayerItem = AVPlayerItem(url: url)
        let p: AVPlayer = AVPlayer(playerItem: item)
        p.isMuted = true
        p.actionAtItemEnd = .pause
        p.preventsDisplaySleepDuringVideoPlayback = false
        player = p
        playerLayer?.player = p
        playerLayer?.videoGravity = .resizeAspect
        playerLayer?.compositingFilter = "screenBlendMode"
        let asset: AVAsset = item.asset
        Task { @MainActor [weak self] in
            let length: Double = (try? await asset.load(.duration).seconds) ?? 4
            let rate: Float = Float(max(0.5, min(2.5, length / max(0.5, duration))))
            self?.player?.playImmediately(atRate: rate)
        }
    }

    func stop() {
        player?.pause()
        playerLayer?.player = nil
        player = nil
    }
}
#endif
