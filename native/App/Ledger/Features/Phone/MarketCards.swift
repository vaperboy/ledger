import SwiftUI

struct MarketCard: View {
    @Environment(\.outsidePalette) private var P
    var photoKey: String
    var badge: String
    var title: String
    var detail: String
    var price: String
    var seller: String
    var avatar: PlayerAvatar
    var online: Bool? = nil
    var note: String = ""

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ShopPhoto(name: "", glyph: Glyph.marketplace, height: 150, cornerRadius: 0, item: photoKey)
                .overlay(alignment: .topLeading) {
                    Text(badge.tidyText).textStyle(.caption, tint: Color.white, weight: .semibold).lineLimit(1)
                        .padding(.horizontal, Theme.Space.s + 2).padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .padding(Theme.Space.s)
                }
                .overlay(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title.tidyText).textStyle(.body, tint: Color.white, weight: .semibold).lineLimit(2).multilineTextAlignment(.leading)
                        if !detail.isEmpty { Text(detail.tidyText).textStyle(.caption, tint: Color.white.opacity(0.85)).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.s).padding(.bottom, Theme.Space.s).padding(.top, Theme.Space.xl)
                    .background(LinearGradient(colors: [Color.clear, Color.black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(price.tidyText).textStyle(.figure, weight: .semibold).lineLimit(1).minimumScaleFactor(0.7)
                if !note.isEmpty { Text(note).textStyle(.caption, tint: P.caution, weight: .medium).lineLimit(1) }
                HStack(spacing: Theme.Space.xs) {
                    avatar
                        .overlay(alignment: .bottomTrailing) {
                            if let online {
                                Circle().fill(online ? P.gain : P.inkDim).frame(width: 9, height: 9)
                                    .overlay(Circle().strokeBorder(P.surface, lineWidth: 1.5))
                            }
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(seller.tidyText).textStyle(.caption, tint: P.ink, weight: .medium).lineLimit(1).minimumScaleFactor(0.8)
                        if let online { Text(online ? "Online" : "Offline").textStyle(.caption, tint: online ? P.gain : P.inkFaint).lineLimit(1) }
                    }
                    Spacer(minLength: Theme.Space.xxs)
                    LedgerGlyph(glyph: Glyph.cart, size: Theme.Icon.small, tint: P.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(P.accent.opacity(0.14)))
                }
            }
            .padding(Theme.Space.s)
        }
        .background(shape.fill(P.surface))
        .clipShape(shape)
        .overlay(shape.strokeBorder(P.line, lineWidth: 1))
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }
}

struct MarketGoldPill: View {
    @Environment(\.outsidePalette) private var P
    var gold: Int

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Circle().fill(Theme.gold).frame(width: 14, height: 14)
            Text(gold.formatted()).textStyle(.body, tint: P.ink, numeric: true, weight: .semibold).lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.m).frame(minHeight: 34)
        .background(Capsule().fill(P.surface))
        .overlay(Capsule().strokeBorder(P.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gold")
        .accessibilityValue(gold.formatted())
    }
}

struct MarketPill: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var symbol: String
    var active: Bool = false

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text(text.tidyText).textStyle(.body, tint: P.ink, weight: .medium).lineLimit(1)
        }
        .foregroundStyle(active ? P.accent : P.ink)
        .padding(.horizontal, Theme.Space.m).frame(minHeight: 40)
        .background(Capsule().fill(P.surface))
        .overlay(Capsule().strokeBorder(active ? P.accent : P.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct MarketSearchBox: View {
    @Environment(\.outsidePalette) private var P
    @Binding var text: String

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            LedgerGlyph(glyph: Glyph.search, size: Theme.Icon.small, tint: P.inkFaint)
            TextField("Search", text: $text)
                .textStyle(.body, tint: P.ink)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("mk-search")
            if !text.isEmpty {
                Button { text = "" } label: {
                    LedgerGlyph(glyph: Glyph.close, size: Theme.Icon.small, tint: P.inkFaint).frame(width: 28, height: 28)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.m).frame(minHeight: 40)
        .background(Capsule().fill(P.surface))
        .overlay(Capsule().strokeBorder(P.line, lineWidth: 1))
        .frame(minWidth: 110)
    }
}

struct MarketNewButton: View {
    @Environment(\.outsidePalette) private var P
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: Theme.Space.xs) {
                LedgerGlyph(glyph: Glyph.hire, size: Theme.Icon.small, tint: P.onAccent)
                Text("New listing").textStyle(.body, tint: P.onAccent, weight: .semibold)
            }
            .padding(.horizontal, Theme.Space.l).frame(minHeight: 48)
            .background(Capsule().fill(P.accent2))
            .shadow(color: Theme.Shadow.color, radius: 8, y: 4)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("mk-new-listing")
    }
}
