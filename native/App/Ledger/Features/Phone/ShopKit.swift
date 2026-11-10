import SwiftUI
import GameCore
#if canImport(UIKit)
import UIKit
#endif

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

enum ShopMetrics {
    static let maxWidth: CGFloat = 480
}

struct ShopBand<Trailing: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var glyph: String
    var color: Color
    var onBack: (() -> Void)? = nil
    var backLabel = "Back"
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let onBack {
                Button {
                    Haptics.tap()
                    onBack()
                } label: {
                    LedgerGlyph(glyph: Glyph.back, size: Theme.Icon.medium, tint: P.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(backLabel)
                .accessibilityIdentifier("back-button")
            }
            HStack(spacing: Theme.Space.s) {
                LedgerGlyph(glyph: glyph, size: Theme.Icon.medium, tint: color)
                Text(title)
                    .textStyle(.headline, tint: P.ink, weight: .semibold)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.s)
            trailing()
        }
        .padding(.leading, onBack == nil ? Theme.Space.l : Theme.Space.xs).padding(.trailing, Theme.Space.s)
        .frame(minHeight: 48)
        .frame(maxWidth: .infinity)
        .background(P.page.ignoresSafeArea(edges: .top))
    }
}

extension ShopBand where Trailing == EmptyView {
    init(title: String, glyph: String, color: Color, onBack: (() -> Void)? = nil, backLabel: String = "Back") {
        self.init(title: title, glyph: glyph, color: color, onBack: onBack, backLabel: backLabel, trailing: { EmptyView() })
    }
}

struct ShopTabs<T: Hashable>: View {
    @Environment(\.outsidePalette) private var P
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    var identifier: (T) -> String
    var badges: ((T) -> Bool)? = nil

    var body: some View {
        SegmentTrack(items: items, title: title, selection: $selection, identifier: identifier, badges: badges)
            .padding(.horizontal, Theme.Space.page).padding(.bottom, Theme.Space.s)
            .frame(maxWidth: ShopMetrics.maxWidth).frame(maxWidth: .infinity)
            .background(P.page)
    }
}

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

struct ShopPage<Content: View>: View {
    var spacing: CGFloat = 28
    @ViewBuilder var content: () -> Content

    var body: some View {
        ShopScroll {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.xxl)
        }
    }
}

struct ShopHero<Action: View>: View {
    @Environment(\.outsidePalette) private var P
    var label: String = ""
    var value: String
    var note: String = ""
    var noteTint: Color? = nil
    var valueTint: Color? = nil
    @ViewBuilder var action: () -> Action
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if !label.isEmpty { Text(label.tidyText).capsLabel(P.inkFaint).lineLimit(1) }
            Text(value.tidyText)
                .font(.system(size: heroSize, weight: .medium, design: .serif).monospacedDigit())
                .foregroundStyle(valueTint ?? P.ink)
                .lineLimit(2).minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !note.isEmpty {
                Text(note.tidyText).textStyle(.body, tint: noteTint ?? P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            action().padding(.top, Theme.Space.m)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ShopHero where Action == EmptyView {
    init(label: String = "", value: String, note: String = "", noteTint: Color? = nil, valueTint: Color? = nil) {
        self.init(label: label, value: value, note: note, noteTint: noteTint, valueTint: valueTint, action: { EmptyView() })
    }
}

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

struct ShopHeading: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var trailing: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(text.tidyText).capsLabel(P.inkFaint).accessibilityAddTraits(.isHeader).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.s)
            if !trailing.isEmpty { Text(trailing.tidyText).textStyle(.caption, tint: P.inkFaint).lineLimit(1) }
        }
    }
}

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

struct ShopNote: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var text: String
    var actionTitle: String? = nil
    var identifier = ""
    var action: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(title.tidyText).textStyle(.headline)
            Text(text.tidyText).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(actionTitle) { Haptics.tap(); action() }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .modifier(OptionalIdentifier(identifier: identifier))
                    .padding(.leading, -Theme.Space.s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .accessibilityIdentifier("shop-empty-action")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, buttonTitle == nil ? 0 : Theme.Space.l)
    }
}

struct ShopPhoto: View {
    @Environment(\.outsidePalette) private var P
    var name: String
    var glyph: String
    var height: CGFloat = 150
    var cornerRadius: CGFloat = Theme.Radius.large
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
        } else if let ui = ArtAsset.uiImage(name) {
            Color.clear.overlay { Image(uiImage: ui).resizable().scaledToFill() }
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

struct ShopThumb: View {
    var photo: String = ""
    var glyph: String
    var item: String = ""
    var size: CGFloat = 48

    var body: some View {
        ShopPhoto(name: photo, glyph: glyph, height: size, cornerRadius: Theme.Radius.small, item: item)
            .frame(width: size, height: size)
    }
}

struct ShopProductCard: View {
    @Environment(\.outsidePalette) private var P
    var photo: String = ""
    var glyph: String
    var item: String = ""
    var photoHeight: CGFloat = 120
    var title: String
    var lines: [String] = []
    var price: String = ""
    var priceUnit: String = ""
    var priceTint: Color? = nil
    var deal: Int = 0
    var note: String = ""
    var noteTint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            ShopPhoto(name: photo, glyph: glyph, height: photoHeight, cornerRadius: Theme.Radius.medium, item: item)
                .overlay(alignment: .topLeading) {
                    if deal > 0 {
                        Text("-\(deal)%").textStyle(.caption, weight: .semibold).containerInk(Color.white)
                            .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xxs)
                            .background(Capsule().fill(P.loss))
                            .padding(Theme.Space.s)
                    }
                }
                .padding(.bottom, Theme.Space.s)
            Text(title.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
            ForEach(Array(lines.enumerated()), id: \.offset) { (_: Int, line: String) in
                Text(line.tidyText).textStyle(.caption).lineLimit(2).multilineTextAlignment(.leading)
            }
            if !price.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                    Text(price.tidyText).textStyle(.headline, tint: priceTint, numeric: true, weight: .semibold).lineLimit(1).minimumScaleFactor(0.7)
                    if !priceUnit.isEmpty { Text(priceUnit.tidyText).textStyle(.caption).lineLimit(1) }
                }
                .padding(.top, Theme.Space.xxs)
            }
            if !note.isEmpty {
                Text(note.tidyText).textStyle(.caption, tint: noteTint ?? P.inkFaint, weight: .medium).lineLimit(2).multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

struct ShopGrid<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.l), GridItem(.flexible(), spacing: Theme.Space.l)],
                  alignment: .leading, spacing: Theme.Space.xl, content: content)
    }
}

struct ShopFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle(fullWidth: true).makeBody(configuration: configuration)
    }
}

struct ShopChip: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var glyph: String? = nil
    var selected: Bool
    var action: () -> Void

    var body: some View {
        let ink: Color = selected ? P.page : P.ink
        Button {
            Haptics.choose()
            action()
        } label: {
            HStack(spacing: Theme.Space.xs) {
                if let glyph { LedgerGlyph(glyph: glyph, size: Theme.Icon.small, tint: selected ? P.page : P.inkSoft) }
                Text(title.tidyText).textStyle(.body, tint: ink, weight: .medium).lineLimit(1)
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 34)
            .environment(\.containerInk, selected ? P.page : nil)
            .background(Capsule().fill(selected ? P.ink : P.inset))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ShopChipRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.s) { content() }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct ShopMenuLabel: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var glyph: String = Glyph.sort

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            LedgerGlyph(glyph: glyph, size: Theme.Icon.small, tint: P.accent)
            Text(text.tidyText).textStyle(.body, tint: P.accent, weight: .medium).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct ShopMoreMenu<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    var label = "More actions"
    var identifier = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(P.inkSoft)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

struct ShopSearchField: View {
    @Environment(\.outsidePalette) private var P
    var prompt: String
    @Binding var text: String
    var identifier: String

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            LedgerGlyph(glyph: Glyph.search, size: Theme.Icon.small, tint: P.ink)
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
        .padding(.leading, Theme.Space.l)
        .frame(minHeight: 48)
        .background(Capsule().fill(P.surface))
        .overlay(Capsule().strokeBorder(P.line, lineWidth: 1))
    }
}

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
                    Text(title.tidyText).textStyle(.headline, weight: selected ? .semibold : .medium).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if !subtitle.isEmpty {
                        Text(subtitle.tidyText).textStyle(.caption).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Space.s)
                if !trailing.isEmpty { Text(trailing.tidyText).textStyle(.headline, numeric: true).lineLimit(1) }
            }
            .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(selected ? P.accentWash : Color.clear))
            .opacity(enabled ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

struct ShopCompanyMenu: View {
    @Environment(\.outsidePalette) private var P
    struct Choice: Identifiable { var id: Int; var name: String; var detail: String }
    var caption: String
    var choices: [Choice]
    var selected: Int
    var identifier: String
    var idPrefix: String
    var onPick: (Int) -> Void

    var body: some View {
        let chosen: Choice? = choices.first { (c: Choice) -> Bool in c.id == selected } ?? choices.first
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(caption.tidyText).capsLabel(P.inkFaint)
            if choices.count > 1 {
                Menu {
                    ForEach(choices) { (c: Choice) in
                        Button { Haptics.choose(); onPick(c.id) } label: {
                            if c.id == chosen?.id { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                        }
                        .accessibilityIdentifier("\(idPrefix)-\(c.id)")
                    }
                } label: { nameLine(chosen, chevron: true) }
                .accessibilityIdentifier(identifier)
            } else {
                nameLine(chosen, chevron: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nameLine(_ c: Choice?, chevron: Bool) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.xs) {
            Text((c?.name ?? "").tidyText).textStyle(.headline, weight: .semibold).lineLimit(1)
            if chevron { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint).rotationEffect(.degrees(90)) }
            if let d = c?.detail, !d.isEmpty { Text(d.tidyText).textStyle(.caption).lineLimit(1) }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }
}

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
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .combine)
    }
}

struct ShopFacts: View {
    var facts: [(label: String, value: String)]
    var total: (label: String, value: String)? = nil
    var tints: [Int: Color] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
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

struct ShopReceiptPicker: View {
    var companies: [Company]
    @Binding var selection: Int
    var idPrefix: String

    var body: some View {
        if companies.count > 1 {
            ShopSection(title: "Receipt goes to") {
                VStack(spacing: Theme.Space.xxs) {
                    ForEach(companies, id: \.id) { (c: Company) in
                        ShopChoiceRow(title: c.name, selected: selection == c.id, identifier: "\(idPrefix)-receipt-\(c.id)") { selection = c.id }
                    }
                }
            }
        }
    }
}

struct ShopPriceTag: View {
    var value: String
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(value.tidyText).textStyle(.figure).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption.tidyText).textStyle(.caption).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

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
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40

    var body: some View {
        ShopPage {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                LedgerGlyph(glyph: Glyph.check, size: Theme.Icon.large, tint: Color.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(P.gain))
                    .padding(.bottom, Theme.Space.s)
                Text(title.tidyText)
                    .font(.system(size: heroSize, weight: .medium, design: .serif))
                    .foregroundStyle(P.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(message.tidyText).textStyle(.body, tint: P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .background(P.page.ignoresSafeArea(edges: [.horizontal, .bottom]))
        .overlay(alignment: .top) { Hairline() }
    }
}

struct ShopBottomAction<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: Theme.Space.xs) { content() }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.s)
            .frame(maxWidth: ShopMetrics.maxWidth)
            .frame(maxWidth: .infinity)
            .background(P.page.ignoresSafeArea(edges: [.horizontal, .bottom]))
            .overlay(alignment: .top) { Hairline() }
    }
}

struct ShopCount: View {
    @Environment(\.outsidePalette) private var P
    var count: Int
    var color: Color
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : String(count))
                .textStyle(.caption, numeric: true, weight: .semibold)
                .containerInk(P.onAccent)
                .padding(.horizontal, Theme.Space.xs).frame(minWidth: 18, minHeight: 18)
                .background(Capsule().fill(color))
                .accessibilityHidden(true)
        }
    }
}
