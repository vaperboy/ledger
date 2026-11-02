import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The shared pieces of the three shopping and insurance Phone apps (AirStay, TechPro Store, Atlas Insurance). Each app has its own palette
/// (`OutsidePalette.airStay`, `.techPro`, `.atlas`) and draws its own coloured band; the pieces below take their colours from the
/// `\.outsidePalette` environment, which `outsideScreen(_:)` sets. They are laid out at real iPhone width (content at most 480 pt wide, centred).
extension Glyph {
    static let airStay = "M3 11 L12 4 L21 11 M5.5 9.5 V20 H18.5 V9.5 M9.5 20 V14 H14.5 V20"
    static let techPro = "M5 8 H19 L18 21 H6 Z M9 8 V6.5 A3 3 0 0 1 15 6.5 V8 M9.5 13 H14.5"
    static let atlas = "M12 3 L19 6 V12 C19 16 16 19 12 21 C8 19 5 16 5 12 V6 Z M12 8.5 A3.5 3.5 0 1 0 12 15.5 A3.5 3.5 0 1 0 12 8.5 M8.5 12 H15.5"
    static let cart = "M3 4 H6 L8 15 H18 L20 7 H7 M9.5 19 A1.2 1.2 0 1 0 9.5 21.4 A1.2 1.2 0 1 0 9.5 19 M17 19 A1.2 1.2 0 1 0 17 21.4 A1.2 1.2 0 1 0 17 19"
    static let software = "M4 5 H20 V17 H4 Z M8 21 H16 M12 17 V21 M7 9 H13"
    static let hardware = "M6 6 H18 V15 H6 Z M3 19 H21"
    static let vehicle = "M3 14 L5.5 8 H18.5 L21 14 V18 H3 Z M3 14 H21 M7.5 18 V20 M16.5 18 V20"
    static let pin = "M12 21 C7 15 5 12 5 9 A7 7 0 0 1 19 9 C19 12 17 15 12 21 M12 7 A2 2 0 1 0 12 11 A2 2 0 1 0 12 7"
}

/// The coloured band at the top of an app: round outlined back button, the app's mark and name, and a trailing control.
struct ShopBand<Trailing: View>: View {
    var title: String
    var glyph: String
    var color: Color
    var onBack: (() -> Void)? = nil
    var backLabel = "Back"
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let onBack {
                Button {
                    Haptics.tap()
                    onBack()
                } label: {
                    GlyphView(glyph: Glyph.back, size: 16, weight: 2, tint: Color.white)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(backLabel)
                .accessibilityIdentifier("back-button")
            }
            GlyphView(glyph: glyph, size: 24, weight: 1.6, tint: Color.white)
            Text(title)
                .font(.system(size: 21, weight: .bold)).foregroundStyle(Color.white)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(color.ignoresSafeArea(edges: .top))
    }
}

extension ShopBand where Trailing == EmptyView {
    init(title: String, glyph: String, color: Color, onBack: (() -> Void)? = nil, backLabel: String = "Back") {
        self.init(title: title, glyph: glyph, color: color, onBack: onBack, backLabel: backLabel, trailing: { EmptyView() })
    }
}

/// A scrolling page at phone width.
struct ShopScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// A photo from the asset catalogue (the premises and vehicle pictures), or a quiet tile with an icon while it is missing.
struct ShopPhoto: View {
    @Environment(\.outsidePalette) private var P
    var name: String
    var glyph: String
    var height: CGFloat = 150
    var cornerRadius: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        picture
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .clipShape(shape)
            .overlay(shape.strokeBorder(P.line, lineWidth: 1))
            .accessibilityHidden(true)
    }

    @ViewBuilder private var picture: some View {
        #if canImport(UIKit)
        if UIImage(named: name) != nil {
            Image(name).resizable().scaledToFill()
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        ZStack {
            P.cardDeep
            GlyphView(glyph: glyph, size: 34, weight: 1.4, tint: P.inkDim)
        }
    }
}

/// The one filled button of an app, in the app's own colour. Compact in height, full width of its container (as in the apps it imitates).
struct ShopFilledButtonStyle: ButtonStyle {
    @Environment(\.outsidePalette) private var P
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return configuration.label
            .font(.system(size: 16, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(P.onAccent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(shape.fill(P.accent.opacity(isEnabled ? 1 : 0.35)))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// A chip of a row of choices (Offices, Shops, Retail; Software, Hardware ...).
struct ShopChip: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var glyph: String? = nil
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.choose()
            action()
        } label: {
            HStack(spacing: 6) {
                if let glyph { GlyphView(glyph: glyph, size: 16, weight: 1.6, tint: selected ? P.onAccent : P.inkSoft) }
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? P.onAccent : P.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .background(Capsule().fill(selected ? P.accent : P.card))
            .overlay(Capsule().strokeBorder(selected ? P.accent : P.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row of a list the player chooses one from: a radio mark, a title, a grey line and a trailing text.
struct ShopChoiceRow: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var subtitle: String = ""
    var trailing: String = ""
    var selected: Bool
    var enabled = true
    var identifier = ""
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.choose()
            action()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                GlyphView(glyph: selected ? Glyph.check : Glyph.ring, size: 20, weight: 1.8, tint: selected ? P.accent : P.inkDim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(P.ink).multilineTextAlignment(.leading)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 12.5)).foregroundStyle(P.inkFaint).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if !trailing.isEmpty { Text(trailing).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(P.ink) }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? P.accent.opacity(0.08) : P.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? P.accent : P.line, lineWidth: selected ? 1.5 : 1))
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// A label and a value on one line (a fact, a price line, a total).
struct ShopFact: View {
    @Environment(\.outsidePalette) private var P
    var label: String
    var value: String
    var strong = false
    var tint: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(.system(size: strong ? 16 : 14, weight: strong ? .semibold : .regular)).foregroundStyle(strong ? P.ink : P.inkSoft)
            Spacer(minLength: 8)
            Text(value).font(.system(size: strong ? 17 : 14, weight: strong ? .bold : .medium).monospacedDigit()).foregroundStyle(tint ?? P.ink)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A title above a block ("Recommended for you", "Delivery method").
struct ShopHeading: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var trailing: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.system(size: 19, weight: .bold)).foregroundStyle(P.ink).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if !trailing.isEmpty { Text(trailing).font(.system(size: 13)).foregroundStyle(P.inkFaint) }
        }
    }
}

/// The big tick screen at the end of a flow (Rent confirmed, Order placed, Insurance activated): a check, a title, a line, facts and two buttons.
struct ShopSuccess<Extra: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var message: String
    var facts: [(label: String, value: String)]
    var primary: String
    var secondary: String
    var onPrimary: () -> Void
    var onSecondary: () -> Void
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        ShopScroll {
            VStack(spacing: 18) {
                GlyphView(glyph: Glyph.check, size: 44, weight: 2.2, tint: P.gain)
                    .frame(width: 88, height: 88)
                    .background(Circle().fill(P.gain.opacity(0.14)))
                    .padding(.top, 18)
                VStack(spacing: 6) {
                    Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(P.ink).multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(message).font(.system(size: 15)).foregroundStyle(P.inkSoft).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                extra()
                Card(padding: 14) {
                    VStack(spacing: 10) {
                        ForEach(Array(facts.enumerated()), id: \.offset) { _, f in ShopFact(label: f.label, value: f.value) }
                    }
                }
                VStack(spacing: 6) {
                    Button(primary, action: onPrimary).buttonStyle(ShopFilledButtonStyle()).accessibilityIdentifier("shop-primary")
                    Button(secondary, action: onSecondary).buttonStyle(PlainTextButtonStyle(tint: P.accent)).accessibilityIdentifier("shop-secondary")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
    }
}

extension ShopSuccess where Extra == EmptyView {
    init(title: String, message: String, facts: [(label: String, value: String)], primary: String, secondary: String,
         onPrimary: @escaping () -> Void, onSecondary: @escaping () -> Void) {
        self.init(title: title, message: message, facts: facts, primary: primary, secondary: secondary, onPrimary: onPrimary, onSecondary: onSecondary, extra: { EmptyView() })
    }
}

/// The strip pinned under a page with a figure on the left and the page's one action on the right.
struct ShopActionBar<Left: View, Action: View>: View {
    @Environment(\.outsidePalette) private var P
    @ViewBuilder var left: () -> Left
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(spacing: 14) {
            left()
            Spacer(minLength: 4)
            action().frame(maxWidth: 190)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(P.card.ignoresSafeArea(edges: .horizontal))
        .overlay(alignment: .top) { Rectangle().fill(P.line).frame(height: 1) }
    }
}

/// A small round count on the cart.
struct ShopCount: View {
    var count: Int
    var color: Color
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : String(count))
                .font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white)
                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(color))
                .accessibilityHidden(true)
        }
    }
}
