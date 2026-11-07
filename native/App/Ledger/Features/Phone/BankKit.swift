import SwiftUI
import Countries

// Shared pieces of the Money screens (Bank, Accounting, Stats, Settings and the rest): the hero figure that opens a screen, a group
// with no box, and the action block (one primary button, quiet text actions beside it).

/// The opening figure of a screen: a small caps label, one large serif number, one context line and a sparkline when there is history.
struct MoneyHero: View {
    @Environment(\.outsidePalette) private var P
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40
    var label: String = ""
    var value: String
    var tint: Color? = nil
    var context: String = ""
    var contextTint: Color? = nil
    var spark: [Double] = []
    var live: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if !label.isEmpty {
                Text(label.tidyText).textStyle(.label, tint: P.inkFaint).textCase(.uppercase).lineLimit(1)
            }
            valueText
            if !context.isEmpty {
                Text(context.tidyText).textStyle(.caption, tint: contextTint ?? P.inkSoft, numeric: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if spark.count >= 3 {
                Sparkline(values: spark, tint: P.accent).frame(height: 36).padding(.top, Theme.Space.xs).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var valueText: some View {
        let text = Text(value.tidyText).font(.hero(min(size, 60))).foregroundStyle(tint ?? P.ink).lineLimit(1).minimumScaleFactor(0.5)
        if let live { text.moneyFlash(live) } else { text }
    }
}

/// A group of rows on the page itself: a faint caps label (and an optional link at the right) over the rows, no box. Cards inside
/// draw flat, so older rows built on `Card` lose their box here too.
struct MoneyGroup<Content: View, Trailing: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if !title.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(title.tidyText).textStyle(.label, tint: P.inkFaint).textCase(.uppercase).lineLimit(1)
                    Spacer(minLength: Theme.Space.s)
                    trailing()
                }
                .frame(minHeight: 28)
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .environment(\.insideCard, true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MoneyGroup where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// The separator between two rows of a `MoneyGroup`: a hairline inset from the leading edge (past the row's glyph when it has one).
struct MoneyRule: View {
    var inset: CGFloat = 32
    var body: some View { Hairline().padding(.leading, inset) }
}

/// A quiet action under a hero: accent text, 44 pt tall.
struct MoneyTextAction: View {
    var title: String
    var identifier: String = ""
    var action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: { Text(title) }
            .buttonStyle(TertiaryButtonStyle())
            .modifier(OptionalIdentifier(identifier: identifier))
    }
}

extension View {
    /// Raises popups from an ivory page (Bank, Accounting) in the game's dark palette, the one the popup glass is drawn for:
    /// the popups are attached to a clear background that carries that palette. `$0.centerSheet(...)` or `$0.confirmAction(...)` inside.
    func moneyPopups<Host: View>(@ViewBuilder _ host: @escaping (Color) -> Host) -> some View {
        background {
            host(Color.clear)
                .environment(\.outsidePalette, OutsidePalette.game)
                .environment(\.colorScheme, .dark)
        }
    }
}

/// An amount typed as the screen's hero: a caps label, the currency code and a large serif field, a line under it, an optional note
/// and quick amounts as chips. `amount` is in accounting units, like `AmountField`; a chip's value is too.
struct MoneyAmountHero: View {
    struct Preset: Identifiable {
        var title: String
        var amount: Double
        var id: String { title }
    }

    @Environment(\.outsidePalette) private var P
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 44
    var label: String
    var currency: Currency
    @Binding var amount: Double
    var note: String = ""
    var presets: [Preset] = []
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(label.tidyText).textStyle(.label, tint: P.inkFaint).textCase(.uppercase).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(currency.country.currencyCode).textStyle(.headline, tint: P.inkFaint)
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .font(.hero(min(size, 60)))
                    .foregroundStyle(P.ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .onChange(of: text) { _, new in
                        let cleaned: String = new.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
                        amount = (Double(cleaned) ?? 0) * currency.rate
                    }
                // The decimal pad has no return key: Done sits beside the field while it is focused.
                if focused {
                    Button("Done") { Haptics.tap(); focused = false }
                        .textStyle(.body, tint: P.accent, weight: .semibold)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("amount-done")
                }
            }
            Rectangle().fill(focused ? P.focus : P.hairline).frame(height: focused ? 1 : 0.5)
            if !note.isEmpty {
                Text(note.tidyText).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
            if !presets.isEmpty {
                HStack(spacing: Theme.Space.s) {
                    ForEach(presets) { (p: Preset) in chip(p) }
                }
                .padding(.top, Theme.Space.xs)
            }
        }
        // Coming back to the step shows the amount already chosen.
        .onAppear { if text.isEmpty && amount > 0 { text = String(format: "%.0f", (amount / max(currency.rate, 0.000001)).rounded(.down)) } }
    }

    private func chip(_ p: Preset) -> some View {
        Button {
            Haptics.choose()
            focused = false
            amount = p.amount
            text = String(format: "%.0f", (p.amount / max(currency.rate, 0.000001)).rounded(.down))
        } label: {
            Text(p.title).textStyle(.body, tint: P.ink, weight: .medium).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(P.inset))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("amount-preset-" + p.title.lowercased())
    }
}
