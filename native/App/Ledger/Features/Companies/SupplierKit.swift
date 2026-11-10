import SwiftUI
import Businesses

struct SupplierLogo: View {
    var logoID: String = ""
    var name: String
    var size: CGFloat = 64

    var body: some View {
        if !logoID.isEmpty && LogoCatalogue.logo(logoID) != nil {
            LogoBadge(logoID: logoID, size: size, glyph: Glyph.suppliers)
        } else {
            ThumbnailView(kind: .logo, key: name, size: size, shape: .square, glyph: Glyph.suppliers, initials: name)
        }
    }
}

struct SupplierOwnerLine: View {
    @Environment(\.outsidePalette) private var P
    var name: String
    var onOpen: (() -> Void)? = nil

    var body: some View {
        if let onOpen {
            Button {
                Haptics.tap()
                onOpen()
            } label: { line(chevron: true) }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Owner " + name + ", open profile")
        } else {
            line(chevron: false)
        }
    }

    private func line(chevron: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            PlayerAvatar(name: name, isYou: false, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Owner").textStyle(.caption, tint: P.inkFaint)
                Text(name.tidyText).textStyle(.body, tint: chevron ? P.accent : nil).lineLimit(1)
            }
            if chevron { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint) }
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SupplierFact: View {
    @Environment(\.outsidePalette) private var P
    var label: String
    var value: String
    var tint: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(label).textStyle(.caption, tint: P.inkFaint)
            Spacer(minLength: Theme.Space.s)
            Text(value.tidyText).textStyle(.body, tint: tint, numeric: true).multilineTextAlignment(.trailing).lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}
