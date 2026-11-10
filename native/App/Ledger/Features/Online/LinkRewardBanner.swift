import SwiftUI

struct LinkRewardBanner: View {
    @Environment(OnlineSession.self) private var online
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let P: OutsidePalette = .passport

    var body: some View {
        Group {
            if let r = online.linkReward {
                Button { Haptics.tap(); online.dismissLinkReward() } label: {
                    HStack(spacing: Theme.Space.m) {
                        ZStack {
                            Circle().fill(P.accent.opacity(0.18))
                            LedgerGlyph(glyph: Glyph.achievements, size: Theme.Icon.medium, tint: P.accent)
                        }
                        .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.gold) gold added").textStyle(.headline, tint: P.ink)
                            Text("Your one-time reward for linking an account.").textStyle(.caption, tint: P.inkSoft)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Space.m)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.accent.opacity(0.5), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.35), radius: 14, y: 6)
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s)
                    .frame(maxWidth: 520)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(r.gold) gold added. Your one-time reward for linking an account.")
                .accessibilityHint("Dismiss")
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .task(id: r.gold) {
                    try? await Task.sleep(nanoseconds: 7_000_000_000)
                    if !Task.isCancelled { online.dismissLinkReward() }
                }
            }
        }
        .animation(Motion.arrive(reduceMotion), value: online.linkReward)
        .frame(maxWidth: .infinity)
    }
}
