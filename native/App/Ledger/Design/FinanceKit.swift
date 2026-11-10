import SwiftUI
import GameCore
import Simulation

extension Glyph {
    static let accounting = "M5 4 H19 V20 H5 Z M8 8 H16 M8 12 H16 M8 16 H12"
}

enum FinanceColor {
    static let forest = Color(hex: 0x0F2B23)
    static let ivoryText = Color(hex: 0xF0EADA)
    static let champagne = Color(hex: 0xD1B27A)
}

struct AcctPressStyle: ButtonStyle {
    @Environment(\.outsidePalette) private var P
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? P.inset : Color.clear)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Motion.tapAnimation, value: configuration.isPressed)
    }
}

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

struct AcctLabel: View {
    @Environment(\.outsidePalette) private var P
    var text: String
    var body: some View {
        Text(text).capsLabel(P.accent2).padding(.horizontal, 2)
    }
}

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

    static func initials(_ name: String) -> String {
        let words: [Substring] = name.split(separator: " ")
        let parts: [Substring] = Array(words.prefix(2))
        let letters: [String] = parts.compactMap { (w: Substring) -> String? in w.first.map { String($0) } }
        return letters.joined().uppercased()
    }
}

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

extension BankFmt {
    func signed(_ v: Double) -> String { (v >= 0 ? "+" : "\u{2212}") + short(abs(v)) }
}

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
