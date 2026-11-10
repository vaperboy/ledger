import SwiftUI

enum PopupRole {
    case title
    case subtitle
    case body
    case caption
    case figure
    case hero
    case rowLabel
    case rowValue
    case effect
    case risk
    case button
    case code
}

enum PopupVariant {
    case standard
    case alert
    case expensive
    case destructive
    case report
    case reward

    var figureSize: CGFloat {
        switch self {
        case .report, .reward: return TextStep.title.size
        default: return TextStep.figure.size
        }
    }

    var figureFont: Font { Font.system(size: figureSize, weight: .medium, design: .serif).monospacedDigit() }
    var valueFont: Font { TextStep.body.font(size: TextStep.body.size, numeric: true, weight: .medium) }

    var risksAreRed: Bool { self == .destructive }
    var footerTone: PopupFooter.Tone {
        switch self {
        case .expensive: return .expensive
        case .destructive: return .destructive
        default: return .normal
        }
    }
}

enum PopupSpace {
    static let tight: CGFloat = Theme.Space.xs
    static let row: CGFloat = Theme.Space.s
    static let block: CGFloat = Theme.Space.m
    static let card: CGFloat = Theme.Space.l
}

private struct InsidePopupKey: EnvironmentKey { static let defaultValue: Bool = false }

extension EnvironmentValues {
    var insidePopup: Bool {
        get { self[InsidePopupKey.self] }
        set { self[InsidePopupKey.self] = newValue }
    }
}

enum PopupRadius {
    static let card: CGFloat = Theme.Radius.large
    static let control: CGFloat = Theme.Radius.small
    static let inner: CGFloat = Theme.Radius.medium
}

private struct PopupTextStyle: ViewModifier {
    @Environment(\.outsidePalette) private var P
    var role: PopupRole
    var variant: PopupVariant

    private var ink: Color { variant == .alert ? Color.white : P.ink }
    private var soft: Color { variant == .alert ? Color.white.opacity(0.9) : P.inkSoft }
    private var big: Bool { variant == .report || variant == .reward }

    func body(content: Content) -> some View {
        switch role {
        case .title:
            content.textStyle(.figure, tint: ink, weight: .semibold)
        case .subtitle:
            content.textStyle(.caption, tint: soft).fixedSize(horizontal: false, vertical: true)
        case .body:
            content.textStyle(.body, tint: ink).fixedSize(horizontal: false, vertical: true)
        case .caption:
            content.textStyle(.caption, tint: soft).fixedSize(horizontal: false, vertical: true)
        case .figure:
            content.textStyle(big ? .title : .figure, tint: variant == .reward ? P.accent : ink, numeric: true)
        case .hero:
            content.textStyle(.display, tint: ink).minimumScaleFactor(0.8).lineLimit(2)
        case .rowLabel:
            content.textStyle(.body, tint: soft)
        case .rowValue:
            content.textStyle(.body, tint: ink, numeric: true, weight: .medium)
        case .effect:
            content.textStyle(.caption, tint: P.accent).fixedSize(horizontal: false, vertical: true)
        case .risk:
            content.textStyle(.caption, tint: variant.risksAreRed ? P.loss : P.warn).fixedSize(horizontal: false, vertical: true)
        case .button:
            content.textStyle(.body, tint: ink, weight: .medium)
        case .code:
            content.font(.system(size: TextStep.caption.size, design: .monospaced)).foregroundStyle(ink)
        }
    }
}

extension View {
    func popupText(_ role: PopupRole, variant: PopupVariant = .standard) -> some View {
        modifier(PopupTextStyle(role: role, variant: variant))
    }
}

private struct PopupFieldStyle: ViewModifier {
    @Environment(\.outsidePalette) private var P

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .textStyle(.headline, weight: .regular)
            .padding(.horizontal, PopupSpace.block)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: PopupRadius.control, style: .continuous).fill(P.inset))
    }
}

extension View {
    func popupField() -> some View { modifier(PopupFieldStyle()) }
}

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

struct PopupBody<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: PopupSpace.block) { content() }
    }
}

extension HireFeedback {
    var popupRole: PopupRole { isHired ? .effect : .risk }
}

struct PopupSection<Content: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: PopupSpace.row) {
            if !title.isEmpty { Text(title).textStyle(.label, tint: P.inkFaint) }
            VStack(alignment: .leading, spacing: PopupSpace.row) { content() }
                .padding(.top, PopupSpace.row)
                .overlay(alignment: .top) { Hairline() }
        }
    }
}
