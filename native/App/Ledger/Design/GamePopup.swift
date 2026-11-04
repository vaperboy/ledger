import SwiftUI
import Countries

/// The one in-game popup frame: a dimmed backdrop (tap outside to close) and a themed card with a title and, optionally, the small x.
/// The "Are you sure" question and the Perks list both use it, so every popup in the game looks and closes the same way. It takes the
/// palette of the screen that opened it (an outside app keeps its own colours).
struct GamePopup<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var title: String
    var showsClose = true
    /// False: only the popup's own button closes it (the daily report, so a player cannot tap through it).
    var dismissOnBackdrop = true
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var shown = false

    var body: some View {
        GeometryReader { (geo: GeometryProxy) in
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { if dismissOnBackdrop { onClose() } }
                    .accessibilityIdentifier("popup-backdrop")
                card(room: geo.size.height * PopupMetrics.roomFraction)
                    .frame(maxWidth: PopupMetrics.maxWidth)
                    .padding(.horizontal, PopupMetrics.margin)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.95)
                    .opacity(shown ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { Motion.animate(Motion.arrive(reduceMotion)) { shown = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// Same card as `CenterSheetFrame`: 44pt header row (title, optional x), content hugging its height, at most 80% of the screen,
    /// scrolling only when taller.
    private func card(room: CGFloat) -> some View {
        let bodyRoom: CGFloat = max(120, room - PopupMetrics.header - 1)
        return VStack(spacing: 0) {
            PopupHeaderRow(title: title, showsClose: showsClose, onClose: onClose)
            FitScroll(maxHeight: bodyRoom) {
                VStack(alignment: .leading, spacing: PopupSpace.block) { content() }.padding(PopupSpace.card)
            }
        }
        .foregroundStyle(P.ink)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(P.card))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
    }
}

