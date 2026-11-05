import SwiftUI
import GameCore
import Simulation

// Shared pieces of the Accounting app and the ivory panels of the Bank:
// a forest-green header band over warm ivory pages, compact rows with hairline separators, champagne accents, tabular figures. Everything
// reads the palette from the environment (`OutsidePalette.accounting` inside Accounting), so none of it is hard-coded to the dark game look.

extension Glyph {
    /// The Accounting app icon: a ledger page with ruled lines.
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
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                onBack()
            } label: {
                GlyphView(glyph: Glyph.back, size: 16, weight: 2, tint: FinanceColor.ivoryText)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(FinanceColor.ivoryText.opacity(0.45), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(backLabel)
            .accessibilityIdentifier("back-button")
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.serifTitle(24)).foregroundStyle(FinanceColor.ivoryText).lineLimit(1).minimumScaleFactor(0.7)
                if !subtitle.isEmpty {
                    Text(subtitle.tidyText).font(.system(size: 12.5)).foregroundStyle(FinanceColor.ivoryText.opacity(0.72)).lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Pressed feedback

/// Pressed feedback for rows and buttons: a soft wash and a slight dim, never a layout change.
struct AcctPressStyle: ButtonStyle {
    @Environment(\.outsidePalette) private var P
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? P.cardDeep : Color.clear)
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

/// A bordered ivory panel. Rows go inside, separated with `AcctDivider`.
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
    @Environment(\.outsidePalette) private var P
    var body: some View { Rectangle().fill(P.divider).frame(height: 1) }
}

/// A small label over a block (champagne caps).
struct AcctLabel: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var body: some View {
        Text(text).capsLabel(P.accent2).padding(.horizontal, 2)
    }
}

/// One row of a list. With an `action` the whole row is the button and shows a chevron; without one it is plain information.
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
    var pill: String? = nil
    var pillTone: AcctPill.Tone = .neutral
    var identifier: String = ""
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button {
                Haptics.tap()
                action()
            } label: { row(chevron: true) }
                .buttonStyle(AcctPressStyle())
                .accessibilityIdentifier(identifier.isEmpty ? title : identifier)
        } else {
            row(chevron: false)
                .accessibilityIdentifier(identifier.isEmpty ? title : identifier)
        }
    }

    private func row(chevron: Bool) -> some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title.tidyText).font(.system(size: 14.5, weight: .medium)).foregroundStyle(P.ink).lineLimit(2)
                if !subtitle.isEmpty { Text(subtitle.tidyText).font(.system(size: 12)).foregroundStyle(P.inkFaint).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if !value.isEmpty || !valueNote.isEmpty || pill != nil {
                VStack(alignment: .trailing, spacing: 3) {
                    if !value.isEmpty {
                        Text(value.tidyText).font(.system(size: 14.5, weight: .medium).monospacedDigit()).foregroundStyle(valueTint ?? P.ink).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    if let pill { AcctPill(text: pill, tone: pillTone) }
                    if !valueNote.isEmpty {
                        Text(valueNote.tidyText).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(valueNoteTint ?? P.inkFaint).lineLimit(1)
                    }
                }
            }
            if chevron { GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: P.inkDim) }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var leading: some View {
        if let glyph {
            IconCircle(glyph: glyph, size: 38, tint: P.accent2)
        } else if let initials {
            Text(initials)
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(P.onAccent)
                .frame(width: 38, height: 38)
                .background(Circle().fill(P.accent))
        }
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
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.14)))
    }
}

// MARK: Buttons

/// The one primary action of a screen: forest green, ivory text. Disabled looks disabled and does nothing.
struct AcctPrimaryButton: View {
    @Environment(\.outsidePalette) private var P
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
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(P.onAccent)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(P.accent))
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Rectangle())
        }
        .buttonStyle(AcctButtonPressStyle())
        .disabled(!enabled)
        .accessibilityIdentifier(identifier.isEmpty ? title : identifier)
    }
}

/// A quieter second action: an outline in forest green.
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
                .font(.system(size: 14.5, weight: .medium)).foregroundStyle(tint ?? P.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(tint ?? P.accent, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(AcctButtonPressStyle())
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
            HStack(alignment: .top, spacing: 12) {
                GlyphView(glyph: glyph, size: 20, weight: 1.6, tint: tint ?? P.inkFaint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.tidyText).font(.system(size: 14.5, weight: .medium)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
                    if !message.isEmpty {
                        Text(message.tidyText).font(.system(size: 13)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// What a person without access sees: the section is locked, and why.
struct AcctLocked: View {
    var section: String
    var body: some View {
        AcctNotice(glyph: Glyph.lock, title: "\(section) is locked",
                   message: "You do not have access to this part of this company's accounting. The owner gives access per company under Settings.")
            .accessibilityIdentifier("acct-locked")
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
            GlyphView(glyph: Glyph.search, size: 16, weight: 1.6, tint: P.inkFaint)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .font(.system(size: 14.5)).foregroundStyle(P.ink)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button { text = "" } label: { GlyphView(glyph: Glyph.close, size: 14, weight: 1.8, tint: P.inkFaint).frame(width: 28, height: 28) }
                    .buttonStyle(PressableStyle()).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).strokeBorder(P.line, lineWidth: 1))
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.tidyText).font(.system(size: 14.5, weight: .medium)).foregroundStyle(P.ink).multilineTextAlignment(.leading)
                    if !subtitle.isEmpty { Text(subtitle.tidyText).font(.system(size: 12)).foregroundStyle(P.inkFaint).multilineTextAlignment(.leading) }
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(selected ? P.accentSelected : P.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(selected ? P.accent : P.line, lineWidth: 1))
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
            .background(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).fill(OutsidePalette.accounting.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous).strokeBorder(OutsidePalette.accounting.line, lineWidth: 1))
    }
}
