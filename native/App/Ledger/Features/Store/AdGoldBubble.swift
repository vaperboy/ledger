import SwiftUI
import Simulation

/// The small floating "watch an ad for gold" button, on Home and the Store tab only.
/// Hidden while a popup or sheet is open, while an ad runs, for administrators and where no ad can be shown.
struct AdGoldBubble: View {
    @Environment(\.popupHost) private var host
    @StateObject private var spare = PopupHost()

    var body: some View {
        AdGoldBubbleBody(host: host ?? spare)
    }
}

private struct AdGoldBubbleBody: View {
    @ObservedObject var host: PopupHost
    @EnvironmentObject private var store: GameStore
    @Environment(AdCoordinator.self) private var ads
    private let session = StoreSession.shared
    @State private var busy = false
    @State private var paid: Int?
    @State private var waitUntil: Date?

    private var hidden: Bool {
        !ads.available || ads.isShowing || session.isAdmin || store.popupOpen || !host.gathered().isEmpty
    }

    var body: some View {
        if !hidden {
            TimelineView(.periodic(from: .now, by: 1)) { tl in
                bubble(now: tl.date)
            }
            .transition(.opacity)
        }
    }

    /// When the next ad can pay: the server's time, or a wait the server just named.
    private func nextAt(_ now: Date) -> Date? {
        let server: Date? = session.adTerms?.nextAt.map { (t: Double) -> Date in Date(timeIntervalSince1970: t) }
        let skew: TimeInterval = TrustedClock.now().timeIntervalSince(now)
        let local: Date? = server.map { (d: Date) -> Date in d.addingTimeInterval(-skew) }
        let soonest: Date? = [local, waitUntil].compactMap { $0 }.max()
        guard let s = soonest, s > now else { return nil }
        return s
    }

    @ViewBuilder private func bubble(now: Date) -> some View {
        let terms: ServerStoreInfo.AdTerms? = session.adTerms
        let left: Int = terms?.left ?? 1
        let gold: Int = terms?.gold ?? 1
        let next: Date? = nextAt(now)
        let ready: Bool = left > 0 && next == nil && !busy && (session.canSpend || !session.isServerBacked)
        Button { watch() } label: {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let paid {
                    Text("+\(paid)").font(.system(size: 15, weight: .heavy)).monospacedDigit()
                    StoreCoin(size: 18)
                } else if left == 0 {
                    Image(systemName: "moon.zzz.fill").font(.system(size: 13, weight: .bold))
                    Text("Tomorrow").font(.system(size: 13, weight: .bold))
                } else if let next {
                    Image(systemName: "hourglass").font(.system(size: 13, weight: .bold))
                    Text(Self.clock(next.timeIntervalSince(now))).font(.system(size: 14, weight: .bold)).monospacedDigit()
                } else {
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .black))
                    Text("+\(gold)").font(.system(size: 15, weight: .heavy)).monospacedDigit()
                    StoreCoin(size: 18)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(Capsule().fill(ready || paid != nil ? StoreColors.purple : StoreColors.purple.opacity(0.55)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.25), radius: 6, y: 2)
        }
        .buttonStyle(PressableStyle())
        .disabled(!ready)
        .accessibilityLabel(label(left: left, gold: gold, next: next, now: now))
        .accessibilityIdentifier("ad-gold-bubble")
    }

    private func label(left: Int, gold: Int, next: Date?, now: Date) -> String {
        if left == 0 { return "Ad gold: back tomorrow" }
        if let next { return "Next ad for gold in " + Self.clock(next.timeIntervalSince(now)) }
        return "Watch an ad for \(StoreText.gold(gold)). \(left) left today."
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s: Int = max(0, Int(seconds.rounded(.up)))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }

    private func watch() {
        Haptics.tap()
        busy = true
        Task {
            guard await ads.watchForGold() else { busy = false; return }
            let out: StoreSession.AdGold = await session.claimAdGold()
            busy = false
            switch out {
            case .paid(let n):
                Haptics.success()
                paid = n
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                paid = nil
            case .wait(let s):
                waitUntil = Date().addingTimeInterval(TimeInterval(s))
            case .doneToday, .failed:
                break
            }
        }
    }
}
