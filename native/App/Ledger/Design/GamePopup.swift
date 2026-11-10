import SwiftUI
import Countries

struct GamePopup<Content: View>: View {
    var title: String
    var showsClose = true
    var dismissOnBackdrop = true
    var variant: PopupVariant = .standard
    var footer: AnyView? = nil
    var category: PopupCategory? = nil
    var tone: PopupTone? = nil
    var icon: String? = nil
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        CenterSheetFrame(onClose: onClose, title: title, size: .fit, showsClose: showsClose, backdropCloses: dismissOnBackdrop, variant: variant, pinnedFooter: footer,
                         category: category, tone: tone, icon: icon) {
            VStack(alignment: .leading, spacing: PopupSpace.block) { content() }
        }
    }
}
