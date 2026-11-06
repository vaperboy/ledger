import SwiftUI

// The rule set of every popup. Content never picks its own font, size or colour: it names a ROLE.
// A popup that does something more important (an expensive or irreversible confirmation, a report, a reward) names a VARIANT, and only
// the exceptions declared here apply. One card (`CenterSheetFrame` / `GamePopup`), one header (title left, x right), one footer
// (Cancel | Apply, `PopupFooter`).

/// The text roles of a popup.
enum PopupRole {
    /// Header title (drawn by the frame, serif 16 semibold).
    case title
    /// A second line under a heading: 12.5 soft.
    case subtitle
    /// Running text: 14.
    case body
    /// Small explanation or note: 12 soft.
    case caption
    /// A key amount or number: 22 serif, monospaced digits.
    case figure
    /// The one big amount a step is about (a loan maximum or chosen amount): 34 serif, one line.
    case hero
    /// Left side of a row: 13 soft.
    case rowLabel
    /// Right side of a row: 13.5 medium, monospaced digits.
    case rowValue
    /// What an option does to the numbers (a consequence line): 12, gold.
    case effect
    /// A risk or validation line: 12.5, warning colour.
    case risk
    /// A button label in the footer: 14 medium.
    case button
    /// Pasted or generated text the player does not read as prose (a save text): 12 monospaced.
    case code
}

/// The declared exceptions. Anything else is `.standard`.
enum PopupVariant {
    case standard
    /// Red alert over everything (a company about to be force-sold): white text.
    case alert
    /// A spend: gold foil footer, the amount in the label.
    case expensive
    /// Irreversible: red footer and a red risk line.
    case destructive
    /// A week, month or year report: larger figure.
    case report
    /// A reward or milestone: larger gold figure.
    case reward

    var figureSize: CGFloat {
        switch self {
        case .report: return 28
        case .reward: return 30
        default: return 22
        }
    }

    /// The figure font alone (for a counting figure that keeps its own gain or loss colour).
    var figureFont: Font { Font.system(size: figureSize, weight: .medium, design: .serif).monospacedDigit() }
    /// The value font alone (a secondary amount beside a figure).
    var valueFont: Font { Font.system(size: 13.5, weight: .medium).monospacedDigit() }

    var risksAreRed: Bool { self == .destructive }
    var footerTone: PopupFooter.Tone {
        switch self {
        case .expensive: return .expensive
        case .destructive: return .destructive
        default: return .normal
        }
    }
}

/// One spacing scale for the inside of every popup.
enum PopupSpace {
    static let tight: CGFloat = 4
    static let row: CGFloat = 8
    static let block: CGFloat = 12
    static let card: CGFloat = 16
}

private struct InsidePopupKey: EnvironmentKey { static let defaultValue: Bool = false }

extension EnvironmentValues {
    /// True inside a popup card: a `Card` there draws flat (padding and a hairline, no fill or border) so it never forms a box inside the box.
    var insidePopup: Bool {
        get { self[InsidePopupKey.self] }
        set { self[InsidePopupKey.self] = newValue }
    }
}

/// One corner-radius set for everything inside a popup: the card, a control (button, field), and an inner block (signature box, photo).
enum PopupRadius {
    static let card: CGFloat = Theme.Radius.hero
    static let control: CGFloat = Theme.Radius.table
    static let inner: CGFloat = Theme.Radius.row
}

/// The champagne gold of an action that is meant to stand out, readable on the dark card and on a light outside palette.
enum PopupInk {
    /// Dark ink on a gold fill.
    static let onGold = Color(red: 0.09, green: 0.075, blue: 0.055)
}

private struct PopupTextStyle: ViewModifier {
    @Environment(\.outsidePalette) private var P
    var role: PopupRole
    var variant: PopupVariant

    private var ink: Color { variant == .alert ? Color.white : P.ink }
    private var soft: Color { variant == .alert ? Color.white.opacity(0.9) : P.inkSoft }

    func body(content: Content) -> some View {
        switch role {
        case .title:
            content.font(.system(size: 16, weight: .semibold, design: .serif)).foregroundStyle(ink)
        case .subtitle:
            content.font(.system(size: 12.5)).foregroundStyle(soft).fixedSize(horizontal: false, vertical: true)
        case .body:
            content.font(.system(size: 14)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
        case .caption:
            content.font(.system(size: 12)).foregroundStyle(soft).fixedSize(horizontal: false, vertical: true)
        case .figure:
            content.font(.system(size: variant.figureSize, weight: .medium, design: .serif).monospacedDigit())
                .foregroundStyle(variant == .reward ? Theme.gold : ink)
        case .hero:
            content.font(.hero(34)).foregroundStyle(ink).minimumScaleFactor(0.6).lineLimit(1)
        case .rowLabel:
            content.font(.system(size: 13)).foregroundStyle(soft)
        case .rowValue:
            content.font(.system(size: 13.5, weight: .medium).monospacedDigit()).foregroundStyle(ink)
        case .effect:
            content.font(.system(size: 12)).foregroundStyle(Theme.gold).fixedSize(horizontal: false, vertical: true)
        case .risk:
            content.font(.system(size: 12.5)).foregroundStyle(variant.risksAreRed ? P.loss : P.caution).fixedSize(horizontal: false, vertical: true)
        case .button:
            content.font(.system(size: 14, weight: .medium)).foregroundStyle(ink)
        case .code:
            content.font(.system(size: 12, design: .monospaced)).foregroundStyle(ink)
        }
    }
}

extension View {
    /// Gives this text the font and colour of a popup role (and, for a declared variant, its exceptions).
    func popupText(_ role: PopupRole, variant: PopupVariant = .standard) -> some View {
        modifier(PopupTextStyle(role: role, variant: variant))
    }
}

private struct PopupFieldStyle: ViewModifier {
    @Environment(\.outsidePalette) private var P

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(P.ink)
            .padding(.horizontal, PopupSpace.block)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: PopupRadius.control, style: .continuous).fill(P.cardDeep))
            .overlay(RoundedRectangle(cornerRadius: PopupRadius.control, style: .continuous).strokeBorder(P.line, lineWidth: 1))
    }
}

extension View {
    /// The one text field of a popup: 15, ink, 44pt high, the card's deep fill and a hairline. Apply it to a `TextField` and nothing else.
    func popupField() -> some View { modifier(PopupFieldStyle()) }
}

/// The one row of a popup: the label left, the value right.
struct PopupRow: View {
    var label: String
    var value: String
    var variant: PopupVariant = .standard

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PopupSpace.row) {
            Text(label).popupText(.rowLabel, variant: variant)
            Spacer(minLength: PopupSpace.row)
            Text(value).popupText(.rowValue, variant: variant).multilineTextAlignment(.trailing)
        }
    }
}

/// The vertical stack every popup body is built in.
struct PopupBody<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: PopupSpace.block) { content() }
    }
}

extension HireFeedback {
    /// The popup role of a negotiation answer: an agreement is an effect line, any other answer (a no, a counter, gone) a caution line.
    var popupRole: PopupRole { isHired ? .effect : .risk }
}

/// A flat group inside a popup: an optional small heading, then rows separated by hairlines. No fill, no border, so it never forms a card
/// inside the popup card. Put each row as a direct child; the hairline is drawn between them.
struct PopupSection<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: PopupSpace.row) {
            if !title.isEmpty { Text(title).popupText(.caption).textCase(.uppercase) }
            VStack(alignment: .leading, spacing: PopupSpace.row) { content() }
                .padding(.top, PopupSpace.row)
                .overlay(alignment: .top) { Rectangle().fill(P.line).frame(height: 1) }
        }
    }
}
