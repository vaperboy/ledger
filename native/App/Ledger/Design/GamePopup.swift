import SwiftUI
import Countries

/// The one in-game popup frame: a dimmed backdrop (tap outside to close) and a themed card with a title and, optionally, the small x.
/// The "Are you sure" question and the Perks list both use it, so every popup in the game looks and closes the same way. It takes the
/// palette of the screen that opened it (an outside app keeps its own colours). It is a `CenterSheetFrame`, so it picks its size class
/// (toast, compact, standard, tall) from its content, springs between sizes, and plays the haptic and entrance of its `variant`
/// (a `.reward` card throws confetti, an `.alert` or `.destructive` one warns).
struct GamePopup<Content: View>: View {
    var title: String
    var showsClose = true
    /// False: only the popup's own button closes it (the daily report, so a player cannot tap through it).
    var dismissOnBackdrop = true
    var variant: PopupVariant = .standard
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        CenterSheetFrame(onClose: onClose, title: title, size: .fit, showsClose: showsClose, backdropCloses: dismissOnBackdrop, variant: variant) {
            VStack(alignment: .leading, spacing: PopupSpace.block) { content() }
        }
    }
}
