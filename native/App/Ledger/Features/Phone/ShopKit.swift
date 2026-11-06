import SwiftUI
import GameCore
#if canImport(UIKit)
import UIKit
#endif

/// The one shop kit of the outside shopping apps (AirStay, TechPro Store, Atlas Insurance, Marketplace): band, page, sections, product card,
/// choice rows, facts, checkout pieces and the success page. Each app keeps its own palette (`OutsidePalette.airStay`, `.techPro`, `.atlas`,
/// `.marketplace`); every piece reads its colours from `\.outsidePalette` and its type, spacing and buttons from the design system.
extension Glyph {
    static let airStay = "M3 11 L12 4 L21 11 M5.5 9.5 V20 H18.5 V9.5 M9.5 20 V14 H14.5 V20"
    static let techPro = "M5 8 H19 L18 21 H6 Z M9 8 V6.5 A3 3 0 0 1 15 6.5 V8 M9.5 13 H14.5"
    static let atlas = "M12 3 L19 6 V12 C19 16 16 19 12 21 C8 19 5 16 5 12 V6 Z M12 8.5 A3.5 3.5 0 1 0 12 15.5 A3.5 3.5 0 1 0 12 8.5 M8.5 12 H15.5"
    static let marketplace = "M4 12 L12 4 H20 V12 L12 20 Z M16 8 A1 1 0 1 0 16 8.01"
    static let cart = "M3 4 H6 L8 15 H18 L20 7 H7 M9.5 19 A1.2 1.2 0 1 0 9.5 21.4 A1.2 1.2 0 1 0 9.5 19 M17 19 A1.2 1.2 0 1 0 17 21.4 A1.2 1.2 0 1 0 17 19"
    static let software = "M4 5 H20 V17 H4 Z M8 21 H16 M12 17 V21 M7 9 H13"
    static let hardware = "M6 6 H18 V15 H6 Z M3 19 H21"
    static let vehicle = "M3 14 L5.5 8 H18.5 L21 14 V18 H3 Z M3 14 H21 M7.5 18 V20 M16.5 18 V20"
    static let pin = "M12 21 C7 15 5 12 5 9 A7 7 0 0 1 19 9 C19 12 17 15 12 21 M12 7 A2 2 0 1 0 12 11 A2 2 0 1 0 12 7"
}

/// The widest a shop page gets (content centred on a larger screen).
enum ShopMetrics {
    static let maxWidth: CGFloat = 480
}

// MARK: Chrome

/// The brand band at the top of an app: back button, the app's mark and name in the brand colour, and a trailing control.
struct ShopBand<Trailing: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var glyph: String
    var color: Color
    var onBack: (() -> Void)? = nil
    var backLabel = "Back"
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let onBack {
                Button {
                    Haptics.tap()
                    onBack()
                } label: {
                    LedgerGlyph(glyph: Glyph.back, size: Theme.Icon.medium, tint: P.onAccent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(backLabel)
                .accessibilityIdentifier("back-button")
            }
            LedgerGlyph(glyph: glyph, size: Theme.Icon.medium, tint: P.onAccent)
            Text(title)
                .textStyle(.figure, tint: P.onAccent, weight: .semibold)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.s)
            trailing()
        }
        .padding(.leading, onBack == nil ? Theme.Space.l : Theme.Space.xs).padding(.trailing, Theme.Space.s)
        .padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.s)
        .frame(maxWidth: .infinity)
        .background(color.ignoresSafeArea(edges: .top))
    }
}

extension ShopBand where Trailing == EmptyView {
    init(title: String, glyph: String, color: Color, onBack: (() -> Void)? = nil, backLabel: String = "Back") {
        self.init(title: title, glyph: glyph, color: color, onBack: onBack, backLabel: backLabel, trailing: { EmptyView() })
    }
}

/// The in-app tabs under the band (Store, Products, My items ...): the one segment control, with a marker on a tab holding something new.
struct ShopTabs<T: Hashable>: View {
    @Environment(\.outsidePalette) private var P
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    var identifier: (T) -> String
    var badges: ((T) -> Bool)? = nil

    var body: some View {
        SegmentTrack(items: items, title: title, selection: $selection, identifier: identifier, badges: badges)
            .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
            .frame(maxWidth: ShopMetrics.maxWidth).frame(maxWidth: .infinity)
            .background(P.page)
    }
}

/// A scrolling page at phone width.
struct ShopScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: ShopMetrics.maxWidth)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).noSidewaysDrag()
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// A shop page: the scroll, the page margins and one rhythm between its sections.
struct ShopPage<Content: View>: View {
    var spacing: CGFloat = Theme.Space.xl
    @ViewBuilder var content: () -> Content

    var body: some View {
        ShopScroll {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xl)
        }
    }
}

// MARK: Headings and sections

/// A page title with an optional line under it (Checkout, Payment details, Choose company).
struct ShopPageTitle: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var subtitle: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title.tidyText).textStyle(.title).accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle.tidyText).textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The title above a block ("Deals this week", "Delivery method"): the caps section label, with a count or note on the right.
struct ShopHeading: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var trailing: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(text.tidyText).capsLabel().accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.s)
            if !trailing.isEmpty { Text(trailing.tidyText).textStyle(.caption, tint: P.inkFaint).lineLimit(1) }
        }
    }
}

/// A block of a shop page: heading, an optional explaining line, the content. No box: spacing and type carry it.
struct ShopSection<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String = ""
    var trailing: String = ""
    var note: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if !title.isEmpty { ShopHeading(text: title, trailing: trailing) }
            if !note.isEmpty {
                Text(note.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A short titled paragraph with an optional action under it ("Or buy it", "Space in your own building", "Condition").
struct ShopNote: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var text: String
    var actionTitle: String? = nil
    var identifier = ""
    var action: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title.tidyText).textStyle(.headline)
            Text(text.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(actionTitle) { Haptics.tap(); action() }
                    .buttonStyle(SecondaryButtonStyle(size: .compact))
                    .modifier(OptionalIdentifier(identifier: identifier))
                    .padding(.top, Theme.Space.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A visible "nothing here" state with an optional way out, for every shop list that can be empty (never a blank page).
struct ShopEmptyNote: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var glyph: String = Glyph.info
    var buttonTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            EmptyState(glyph: glyph, title: text)
            if let buttonTitle {
                Button(buttonTitle) { Haptics.tap(); action() }
                    .buttonStyle(SecondaryButtonStyle(size: .compact))
                    .accessibilityIdentifier("shop-empty-action")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, buttonTitle == nil ? 0 : Theme.Space.l)
    }
}

// MARK: Pictures and product cards

/// A photo from the asset catalogue (the premises and vehicle pictures), or a quiet tile with the icon while it is missing.
struct ShopPhoto: View {
    @Environment(\.outsidePalette) private var P
    var name: String
    var glyph: String
    var height: CGFloat = 150
    var cornerRadius: CGFloat = Theme.Radius.medium
    /// A cell key of the items sheet (`ArtLibrary.itemKey`); wins over `name` when the cell exists.
    var item: String = ""

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        picture
            .frame(maxWidth: .infinity)
            .frame(minHeight: height, maxHeight: height)
            .clipped()
            .clipShape(shape)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var picture: some View {
        #if canImport(UIKit)
        if let cell = ArtLibrary.image(.items, item) {
            Color.clear.overlay { Image(uiImage: cell).resizable().scaledToFill() }
        } else if !name.isEmpty, UIImage(named: name) != nil {
            Color.clear.overlay { Image(name).resizable().scaledToFill() }
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
            LedgerGlyph(glyph: glyph, size: Theme.Icon.large, tint: P.inkDim)
        }
    }
}

/// The one product card of the shops: picture, name, grey lines, the price (with a unit and a discount) and a status note. Grids use it
/// at a small picture height, listings at a tall one. The caller wraps it in a button.
struct ShopProductCard: View {
    @Environment(\.outsidePalette) private var P
    var photo: String = ""
    var glyph: String
    var item: String = ""
    var photoHeight: CGFloat = 96
    var title: String
    var lines: [String] = []
    var price: String = ""
    var priceUnit: String = ""
    var priceTint: Color? = nil
    var deal: Int = 0
    var note: String = ""
    var noteTint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            ShopPhoto(name: photo, glyph: glyph, height: photoHeight, cornerRadius: Theme.Radius.small, item: item)
                .padding(.bottom, Theme.Space.xs)
            Text(title.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
            ForEach(Array(lines.enumerated()), id: \.offset) { (_: Int, line: String) in
                Text(line.tidyText).textStyle(.caption).lineLimit(2).multilineTextAlignment(.leading)
            }
            if !price.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                    Text(price.tidyText).textStyle(.headline, tint: priceTint, numeric: true, weight: .semibold).lineLimit(1).minimumScaleFactor(0.7)
                    if !priceUnit.isEmpty { Text(priceUnit.tidyText).textStyle(.caption).lineLimit(1) }
                    if deal > 0 { Text("-\(deal)%").textStyle(.caption, tint: P.loss, weight: .semibold) }
                }
            }
            if !note.isEmpty {
                Text(note.tidyText).textStyle(.caption, tint: noteTint ?? P.inkFaint, weight: .medium).lineLimit(2).multilineTextAlignment(.leading)
            }
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.surface))
        .contentShape(Rectangle())
    }
}

/// Two product cards to a line.
struct ShopGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible(), spacing: Theme.Space.m)],
                  alignment: .leading, spacing: Theme.Space.m, content: content)
    }
}

// MARK: Controls

/// The one filled button of an app, in the app's own colour: the primary button at full width.
struct ShopFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle(fullWidth: true).makeBody(configuration: configuration)
    }
}

/// A chip of a row of choices (Offices, Shops, Retail; a sort order). The chosen one is filled in the app's colour.
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
            HStack(spacing: Theme.Space.xs) {
                if let glyph { LedgerGlyph(glyph: glyph, size: Theme.Icon.small, tint: selected ? P.onAccent : P.inkSoft) }
                Text(title.tidyText).textStyle(.body, tint: selected ? P.onAccent : P.ink, weight: .medium).lineLimit(1)
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 36)
            .background(Capsule().fill(selected ? P.accent : P.inset))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A sideways row of chips (filters, sort orders): a carousel, the one place a shop scrolls sideways.
struct ShopChipRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) { content() }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// The search field of a shop: a magnifier, the words, a clear button while there are words.
struct ShopSearchField: View {
    @Environment(\.outsidePalette) private var P
    var prompt: String
    @Binding var text: String
    var identifier: String

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            LedgerGlyph(glyph: Glyph.search, size: Theme.Icon.small, tint: P.inkFaint)
            TextField(prompt, text: $text)
                .textStyle(.body)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button {
                    Haptics.tap()
                    text = ""
                } label: {
                    LedgerGlyph(glyph: Glyph.close, size: Theme.Icon.small, tint: P.inkFaint).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, Theme.Space.m)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.inset))
    }
}

/// A quantity with minus and plus (44 pt each) and the number between them.
struct ShopQuantity: View {
    @Environment(\.outsidePalette) private var P
    var label: String = "Quantity"
    var value: Int
    var range: ClosedRange<Int>
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(label.tidyText).textStyle(.body, tint: P.inkSoft)
            Spacer(minLength: Theme.Space.s)
            HStack(spacing: 0) {
                Button { onChange(max(range.lowerBound, value - 1)); Haptics.choose() } label: {
                    LedgerGlyph(glyph: Glyph.minus, size: Theme.Icon.small, tint: P.accent).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(value <= range.lowerBound)
                .accessibilityLabel("Fewer")
                Text("\(value)").textStyle(.headline, numeric: true).frame(minWidth: 28)
                Button { onChange(min(range.upperBound, value + 1)); Haptics.choose() } label: {
                    LedgerGlyph(glyph: Glyph.hire, size: Theme.Icon.small, tint: P.accent).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(value >= range.upperBound)
                .accessibilityLabel("More")
            }
            .buttonStyle(PressableStyle())
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.inset))
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(value)")
    }
}

/// A row of a list the player chooses one from: a selection mark, a title, a grey line and a trailing text. Flat: the chosen row takes
/// the app's wash.
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
            HStack(alignment: .center, spacing: Theme.Space.m) {
                LedgerGlyph(glyph: selected ? Glyph.check : Glyph.ring, size: Theme.Icon.medium, tint: selected ? P.accent : P.inkDim)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title.tidyText).textStyle(.headline).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if !subtitle.isEmpty {
                        Text(subtitle.tidyText).textStyle(.caption).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                if !trailing.isEmpty { Text(trailing.tidyText).textStyle(.headline, numeric: true).lineLimit(1) }
            }
            .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(selected ? P.accentWash : P.surface))
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Who the app is working for (shopping for, insured company): the name and a line, with Change when there is more than one company.
struct ShopCompanyBar: View {
    @Environment(\.outsidePalette) private var P
    var caption: String
    var name: String
    var detail: String
    var canChange: Bool
    @Binding var open: Bool
    var identifier: String

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(caption.tidyText).capsLabel(P.inkFaint)
                Text(name.tidyText).textStyle(.headline).lineLimit(1)
                Text(detail.tidyText).textStyle(.caption).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            if canChange {
                Button(open ? "Close" : "Change") { Haptics.tap(); open.toggle() }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .accessibilityIdentifier(identifier)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: Facts and checkout

/// A label and a value on one line (a fact, a price line, a total). `strong` is the total: it gets a figure.
struct ShopFact: View {
    @Environment(\.outsidePalette) private var P
    var label: String
    var value: String
    var strong = false
    var tint: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Text(label.tidyText).textStyle(strong ? .headline : .body, tint: strong ? P.ink : P.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.s)
            if strong {
                Text(value.tidyText).textStyle(.figure, tint: tint).multilineTextAlignment(.trailing).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text(value.tidyText).textStyle(.body, tint: tint ?? P.ink, numeric: true, weight: .medium).multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Facts one under the other with hairlines between, unboxed; a strong fact (the total) sits under a hairline of its own.
struct ShopFacts: View {
    var facts: [(label: String, value: String)]
    var total: (label: String, value: String)? = nil
    var tints: [Int: Color] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(Array(facts.enumerated()), id: \.offset) { (i: Int, f: (label: String, value: String)) in
                if i > 0 { Hairline() }
                ShopFact(label: f.label, value: f.value, tint: tints[i])
            }
            if let total {
                Hairline()
                ShopFact(label: total.label, value: total.value, strong: true)
            }
        }
    }
}

/// "Receipt goes to": which company's accounting records file the receipt. Said once above the list, not on every row.
struct ShopReceiptPicker: View {
    var companies: [Company]
    @Binding var selection: Int
    var idPrefix: String

    var body: some View {
        ShopSection(title: "Receipt goes to", note: "The accounting records that file the receipt.") {
            ForEach(companies, id: \.id) { (c: Company) in
                ShopChoiceRow(title: c.name, selected: selection == c.id, identifier: "\(idPrefix)-receipt-\(c.id)") { selection = c.id }
            }
        }
    }
}

/// A price over its unit, for the left of an action bar ("2,400 / per month").
struct ShopPriceTag: View {
    var value: String
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(value.tidyText).textStyle(.figure).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption.tidyText).textStyle(.caption).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The big tick screen at the end of a flow (Rent confirmed, Order placed, Insurance active): a check, a title, a line, facts and two buttons.
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
        ShopPage {
            VStack(spacing: Theme.Space.m) {
                LedgerGlyph(glyph: Glyph.check, size: Theme.Icon.large, tint: P.gain)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(P.gain.opacity(0.14)))
                Text(title.tidyText).textStyle(.title).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message.tidyText).textStyle(.body, tint: P.inkSoft).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Space.l)
            extra()
            ShopFacts(facts: facts)
            VStack(spacing: Theme.Space.xs) {
                Button(primary) { Haptics.tap(); onPrimary() }.buttonStyle(PrimaryButtonStyle(fullWidth: true)).accessibilityIdentifier("shop-primary")
                Button(secondary) { Haptics.tap(); onSecondary() }.buttonStyle(TertiaryButtonStyle(fullWidth: true)).accessibilityIdentifier("shop-secondary")
            }
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
        HStack(spacing: Theme.Space.m) {
            left()
            Spacer(minLength: Theme.Space.xs)
            action().frame(maxWidth: 200)
        }
        .padding(.horizontal, Theme.Space.page).padding(.vertical, Theme.Space.s)
        .frame(maxWidth: ShopMetrics.maxWidth)
        .frame(maxWidth: .infinity)
        .background(P.surfaceRaised.ignoresSafeArea(edges: [.horizontal, .bottom]))
        .overlay(alignment: .top) { Hairline() }
    }
}

/// A small round count on the cart.
struct ShopCount: View {
    @Environment(\.outsidePalette) private var P
    var count: Int
    var color: Color
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : String(count))
                .textStyle(.caption, tint: P.onAccent, numeric: true, weight: .semibold)
                .padding(.horizontal, Theme.Space.xs).frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(color))
                .accessibilityHidden(true)
        }
    }
}
