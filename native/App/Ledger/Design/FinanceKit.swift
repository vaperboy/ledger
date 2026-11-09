import SwiftUI
import GameCore
import Simulation

// Shared pieces of the ivory panels of the Bank and the company screens:
// a forest-green header band over warm ivory pages, compact rows with hairline separators, champagne accents, tabular figures. Everything
// reads the palette from the environment (`OutsidePalette.accounting` in the Bank), so none of it is hard-coded to the dark game look.

extension Glyph {
    static let accounting = "M5 4 H19 V20 H5 Z M8 8 H16 M8 12 H16 M8 16 H12"
}

/// The forest-green header band and the champagne of the Banking and Accounting identity.
enum FinanceColor {
    static let forest = Color(hex: 0x0F2B23)
    static let ivoryText = Color(hex: 0xF0EADA)
    static let champagne = Color(hex: 0xD1B27A)
}

// MARK: Header

/// The Accounting header band: round back button, serif title, a soft subtitle, on forest green that runs up under the status bar.
struct AcctHeader: View {
    var title: String
    var subtitle: String = ""
    var backLabel: String = "Back"
    var onBack: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Button {
                Haptics.tap()
                onBack()
            } label: {
                LedgerGlyph(glyph: Glyph.back, size: Theme.Icon.medium, tint: FinanceColor.ivoryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(backLabel)
            .accessibilityIdentifier("back-button")
            .padding(.leading, -Theme.Space.m)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).textStyle(.title, tint: FinanceColor.ivoryText).lineLimit(1).minimumScaleFactor(0.7)
                if !subtitle.isEmpty {
                    Text(subtitle.tidyText).textStyle(.caption, tint: FinanceColor.ivoryText.opacity(0.72)).lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.xs).padding(.bottom, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Pressed feedback

/// Pressed feedback for rows and buttons: a soft wash and a slight dim, never a layout change.
struct AcctPressStyle: ButtonStyle {
    @Environment(\.outsidePalette) private var P
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? P.inset : Color.clear)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Motion.tapAnimation, value: configuration.isPressed)
    }
}

struct AcctButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.tapAnimation, value: configuration.isPressed)
    }
}

// MARK: Containers

/// A surface group with no padding of its own (flat inside another group). Rows go inside, separated with `AcctDivider`.
struct AcctPanel<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content
    var body: some View {
        Card(padding: padding, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: 0, content: content)
        }
    }
}

struct AcctDivider: View {
    var body: some View { Hairline() }
}

/// A small label over a block (champagne caps).
struct AcctLabel: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var body: some View {
        Text(text).capsLabel(P.accent2).padding(.horizontal, 2)
    }
}

/// One row of a list: `LedgerRow` with a 14 pt inset (the panel has no padding). With an `action` the whole row is the button and shows
/// a chevron; without one it is plain information. The identifier is the title unless one is given.
struct AcctRow: View {
    @Environment(\.outsidePalette) private var P
    var glyph: String? = nil
    var initials: String? = nil
    var title: String
    var subtitle: String = ""
    var value: String = ""
    var valueTint: Color? = nil
    var valueNote: String = ""
    var valueNoteTint: Color? = nil
    /// An arrow and amount in place of `value` (see `ArrowAmount`).
    var gain: Double? = nil
    var gainFormat: ((Double) -> String)? = nil
    var pill: String? = nil
    var pillTone: AcctPill.Tone = .neutral
    var identifier: String = ""
    var action: (() -> Void)? = nil

    var body: some View {
        LedgerRow(leading: leading, leadingTint: glyph != nil ? P.accent2 : nil, title: title, subtitle: subtitle, value: value,
                  valueTint: valueTint, valueNote: valueNote, valueNoteTint: valueNoteTint, gain: gain, gainFormat: gainFormat, pill: pill, pillTone: pillTone,
                  inset: 14, identifier: identifier.isEmpty ? title : identifier, action: action)
    }

    private var leading: LedgerRow.Leading {
        if let glyph { return .glyph(glyph) }
        if let initials { return .initials(initials) }
        return .empty
    }

    /// Two letters for a name ("Nordic Wholesale" gives "NW").
    static func initials(_ name: String) -> String {
        let words: [Substring] = name.split(separator: " ")
        let parts: [Substring] = Array(words.prefix(2))
        let letters: [String] = parts.compactMap { (w: Substring) -> String? in w.first.map { String($0) } }
        return letters.joined().uppercased()
    }
}

/// A status word: a tinted capsule. Colour always comes with the word.
struct AcctPill: View {
    enum Tone { case good, warn, bad, neutral }
    @Environment(\.outsidePalette) private var P
    var text: String
    var tone: Tone = .neutral

    private var tint: Color {
        switch tone {
        case .good: return P.gain
        case .warn: return P.caution
        case .bad: return P.loss
        case .neutral: return P.inkFaint
        }
    }

    var body: some View {
        Text(text)
            .textStyle(.caption, tint: tint, weight: .semibold).lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, Theme.Space.s).padding(.vertical, Theme.Space.xxs)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

// MARK: Buttons

/// The one primary action of a screen: the primary button at full width in the palette's accent. Disabled looks disabled and does nothing.
struct AcctPrimaryButton: View {
    var title: String
    var enabled: Bool = true
    var identifier: String = ""
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(PrimaryButtonStyle(fullWidth: true))
        .disabled(!enabled)
        .accessibilityIdentifier(identifier.isEmpty ? title : identifier)
    }
}

/// A quieter second action: the secondary button at full width, text in `tint` (the palette's accent by default).
struct AcctSecondaryButton: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var tint: Color? = nil
    var identifier: String = ""
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
        }
        .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: tint ?? P.accent))
        .accessibilityIdentifier(identifier.isEmpty ? title : identifier)
    }
}

// MARK: States

/// A real empty or explanatory state in a panel: an icon, a line in bold and the reason or what to do.
struct AcctNotice: View {
    @Environment(\.outsidePalette) private var P
    var glyph: String = Glyph.info
    var title: String
    var message: String = ""
    var tint: Color? = nil
    var body: some View {
        AcctPanel(padding: 16) {
            EmptyState(glyph: glyph, title: title, message: message, tint: tint, centered: false)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Fields

/// A search field in the Accounting look.
struct AcctSearchField: View {
    @Environment(\.outsidePalette) private var P
    @Binding var text: String
    var prompt: String
    var identifier: String = "acct-search"
    var body: some View {
        HStack(spacing: 8) {
            LedgerGlyph(glyph: Glyph.search, size: Theme.Icon.small, tint: P.inkFaint)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .textStyle(.body)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: { LedgerGlyph(glyph: Glyph.close, size: Theme.Icon.small, tint: P.inkFaint).frame(width: 44, height: 44) }
                    .buttonStyle(PressableStyle()).accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, Theme.Space.m).padding(.trailing, text.isEmpty ? Theme.Space.m : 0).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).fill(P.inset))
    }
}

/// One exclusive option with a radio mark (ivory version of `ChoiceCard`, which is dark).
struct AcctChoice: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    var subtitle: String = ""
    var selected: Bool
    var identifier: String = ""
    var action: () -> Void
    var body: some View {
        Button {
            Haptics.choose()
            action()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? P.accent : P.lineStrong, lineWidth: 1.5).frame(width: 20, height: 20)
                    if selected { Circle().fill(P.accent).frame(width: 10, height: 10) }
                }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(title.tidyText).textStyle(.headline).multilineTextAlignment(.leading)
                    if !subtitle.isEmpty { Text(subtitle.tidyText).textStyle(.caption, tint: P.inkFaint).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: Theme.Space.s)
            }
            .padding(.horizontal, 14).padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(selected ? P.accentWash : P.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(AcctButtonPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier.isEmpty ? title : identifier)
    }
}

// MARK: Money text

extension BankFmt {
    /// "+£1,240" for money in, "−£320" for money out, in the account's own currency.
    func signed(_ v: Double) -> String { (v >= 0 ? "+" : "\u{2212}") + short(abs(v)) }
}

// MARK: Ivory panel for the Bank

/// A block drawn in the warm ivory of the Banking mockup (balance, loan offer) inside the dark-green Bank app. Everything inside reads the ivory palette.
struct IvoryPanel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .environment(\.outsidePalette, .accounting)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(OutsidePalette.accounting.card))
    }
}
