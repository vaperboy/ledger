import SwiftUI

extension Glyph {
    static let crown = "M4 18 H20 M4 18 L3 8 L8 12 L12 5 L16 12 L21 8 L20 18"
}

struct ListingPill: View {
    var text: String
    var glyph: String? = nil
    var dot: Color? = nil

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            if let glyph { LedgerGlyph(glyph: glyph, size: Theme.Icon.small, tint: Color.white) }
            Text(text.tidyText).textStyle(.caption, tint: Color.white, weight: .semibold).lineLimit(1)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }
}

struct ListingHero<Picture: View, Badge: View>: View {
    var height: CGFloat = 260
    var location: String = ""
    var locationGlyph: String = Glyph.pin
    var counter: String = "1/1"
    var shareText: String = ""
    @ViewBuilder var picture: () -> Picture
    @ViewBuilder var badge: () -> Badge

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
        picture()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(shape)
            .overlay(alignment: .topLeading) { badge().padding(Theme.Space.m) }
            .overlay(alignment: .topTrailing) {
                if !shareText.isEmpty {
                    ShareLink(item: shareText) {
                        HStack(spacing: Theme.Space.xs) {
                            LedgerGlyph(glyph: Glyph.share, size: Theme.Icon.small, tint: Color.black)
                            Text("Share").textStyle(.caption, tint: Color.black, weight: .semibold)
                        }
                        .padding(.horizontal, Theme.Space.m).frame(minHeight: 34)
                        .background(Capsule().fill(Color.white.opacity(0.92)))
                    }
                    .padding(Theme.Space.m)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !location.isEmpty { ListingPill(text: location, glyph: locationGlyph).padding(Theme.Space.m) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !counter.isEmpty { ListingPill(text: counter).padding(Theme.Space.m) }
            }
    }
}

struct ListingPanel<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(P.inset))
    }
}

struct ListingStats<Left: View, Right: View>: View {
    @Environment(\.outsidePalette) private var P
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        ListingPanel {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) { left() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(P.hairline).frame(width: 1)
                VStack(alignment: .leading, spacing: Theme.Space.xs) { right() }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ListingCountdown: View {
    @Environment(\.outsidePalette) private var P
    var seconds: Double

    var body: some View {
        let s: Int = max(0, Int(seconds.rounded(.down)))
        HStack(spacing: Theme.Space.xs) {
            unit(s / 3_600, "HRS")
            Text(":").textStyle(.headline, tint: P.inkFaint)
            unit((s % 3_600) / 60, "MIN")
            Text(":").textStyle(.headline, tint: P.inkFaint)
            unit(s % 60, "SEC")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time left")
        .accessibilityValue("\(s / 3_600) hours \((s % 3_600) / 60) minutes \(s % 60) seconds")
    }

    private func unit(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(String(format: "%02d", value)).textStyle(.headline, tint: seconds < 120 ? P.loss : P.ink, numeric: true)
            Text(label).textStyle(.caption, tint: P.inkFaint)
        }
        .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xs)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.surfaceRaised))
    }
}
