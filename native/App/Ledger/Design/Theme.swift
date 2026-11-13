import SwiftUI
import UIKit

enum Theme {
    static let page = Color(hex: 0x0F1011)
    static let pageLift = Color(hex: 0x1A1813)
    static let surface = Color(hex: 0x151617)
    static let surfaceRaised = Color(hex: 0x1A1B1D)
    static let inset = Color(hex: 0xF1EBDD, opacity: 0.05)
    static let line = Color(red: 0.937, green: 0.914, blue: 0.875).opacity(0.09)
    static let lineStrong = Color(hex: 0x3A3B3D)
    static let ink = Color(hex: 0xF1EBDD)
    static let inkSoft = Color(hex: 0xA19B8F)
    static let inkFaint = Color(hex: 0x8A857C)
    static let accent = Color(hex: 0xD6B889)
    static let accentInk = Color(red: 0.09, green: 0.075, blue: 0.055)
    static let accentWash = Color(hex: 0xD6B889, opacity: 0.14)
    static let gain = Color(hex: 0x7FC79B)
    static let loss = Color(hex: 0xE58B78)
    static let warn = Color(hex: 0xE0B064)
    static let alert = Color(hex: 0xE5584B)
    static let focus = Color(hex: 0xD6B889)
    static let scrim = Color.black.opacity(0.55)
    static let slateBlue = Color(red: 0.322, green: 0.451, blue: 0.682)
    static let roseGold = Color(red: 0.851, green: 0.682, blue: 0.384)

    static let walnut = page
    static let leather = page
    static let walnutRaised = surfaceRaised
    static let surfaceTable = surface
    static let glass = surfaceRaised
    static let pill = inset
    static let pillOn = accentWash
    static let hairline = line
    static let border = line
    static let divider = line
    static let tableLine = line
    static let borderStrong = lineStrong
    static let ivory = ink
    static let cream = ink
    static let ivoryMuted = inkSoft
    static let ivoryFaint = inkFaint
    static let ivoryDim = inkFaint
    static let gold = accent
    static let goldDeep = Color(red: 0.722, green: 0.600, blue: 0.427)
    static let goldLight = Color(red: 0.863, green: 0.753, blue: 0.592)
    static let onGold = accentInk
    static let caution = warn
    static let goldWash = accentWash
    static let goldSelected = accentWash
    static let goldGradient = LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom)
    static let background = LinearGradient(colors: [page, page], startPoint: .top, endPoint: .bottom)

    enum Space {
        static let xxs: CGFloat = 2, xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
        static let page: CGFloat = 20
        static let margin: CGFloat = 20
    }
    enum Radius {
        static let small: CGFloat = 9, medium: CGFloat = 13, large: CGFloat = 17
        static let s: CGFloat = 9, m: CGFloat = 9, l: CGFloat = 13
        static let hero: CGFloat = 17, card: CGFloat = 14, row: CGFloat = 13, table: CGFloat = 9, appIcon: CGFloat = 15
    }
    enum Icon {
        static let small: CGFloat = 16, medium: CGFloat = 20, large: CGFloat = 28
        static let stroke: CGFloat = 1.5
    }

    enum Elevation { case flat, raised }
    enum Shadow { static let color = Color.black.opacity(0.32); static let radius: CGFloat = 16; static let y: CGFloat = 8 }

    static func tone(_ name: String) -> Color {
        switch name { case "good": return gain; case "bad": return loss; case "warn": return warn; default: return inkSoft }
    }
    static func change(_ v: Double) -> Color { v > 0.0000001 ? gain : v < -0.0000001 ? loss : inkSoft }

    static var windowInsets: UIEdgeInsets {
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene: UIWindowScene? = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets ?? .zero
    }
}

extension Color {
    func inPalette(_ p: OutsidePalette) -> Color {
        if self == Theme.ivory { return p.ink }
        if self == Theme.ivoryMuted { return p.inkSoft }
        if self == Theme.ivoryFaint { return p.inkFaint }
        if self == Theme.ivoryDim { return p.inkDim }
        if self == Theme.gold { return p.accent }
        if self == Theme.gain { return p.gain }
        if self == Theme.loss { return p.loss }
        if self == Theme.caution { return p.caution }
        if self == Theme.line { return p.hairline }
        if self == Theme.lineStrong { return p.lineStrong }
        return self
    }

    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

enum TextStep {
    case display
    case title
    case figure
    case headline
    case body
    case caption
    case label

    var size: CGFloat {
        switch self {
        case .display: return 34
        case .title: return 24
        case .figure: return 20
        case .headline: return 15
        case .body: return 14
        case .caption: return 12
        case .label: return 11
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .display: return .largeTitle
        case .title: return .title2
        case .figure: return .title3
        case .headline: return .subheadline
        case .body: return .body
        case .caption: return .caption
        case .label: return .caption2
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .title, .figure, .headline: return .medium
        case .body, .caption: return .regular
        case .label: return .semibold
        }
    }

    var design: Font.Design {
        switch self {
        case .display, .title, .figure: return .serif
        default: return .default
        }
    }

    var isNumeric: Bool { self == .display || self == .figure }
    var tracking: CGFloat { self == .label ? 1.2 : 0 }

    func ink(_ p: OutsidePalette) -> Color {
        switch self {
        case .caption: return p.inkSoft
        case .label: return p.accent
        default: return p.ink
        }
    }

    var fixedFont: Font { font(size: size, numeric: isNumeric, weight: nil) }

    func font(size s: CGFloat, numeric: Bool, weight w: Font.Weight?) -> Font {
        let base: Font = Font.system(size: max(11, s), weight: w ?? weight, design: design)
        return (numeric || isNumeric) ? base.monospacedDigit() : base
    }
}

extension TextStep {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .display: return .largeTitle
        case .title: return .title2
        case .figure: return .title3
        case .headline: return .subheadline
        case .body: return .body
        case .caption: return .caption1
        case .label: return .caption2
        }
    }

    func scaledSize(_ dynamicType: DynamicTypeSize? = nil) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: uiTextStyle)
        guard let dynamicType else { return metrics.scaledValue(for: size) }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicType))
        return metrics.scaledValue(for: size, compatibleWith: traits)
    }

    func scaledFont(_ dynamicType: DynamicTypeSize? = nil, numeric: Bool = false, weight: Font.Weight? = nil) -> Font {
        font(size: scaledSize(dynamicType), numeric: numeric, weight: weight)
    }
}

extension Font {
    static func step(_ step: TextStep, dynamicType: DynamicTypeSize? = nil, numeric: Bool = false, weight: Font.Weight? = nil) -> Font {
        step.scaledFont(dynamicType, numeric: numeric, weight: weight)
    }
}

struct TextStepStyle: ViewModifier {
    var step: TextStep
    var tint: Color?
    var numeric: Bool
    var weight: Font.Weight?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.outsidePalette) private var P
    @Environment(\.containerInk) private var containerInk

    init(step: TextStep, tint: Color? = nil, numeric: Bool = false, weight: Font.Weight? = nil) {
        self.step = step
        self.tint = tint
        self.numeric = numeric
        self.weight = weight
    }

    func body(content: Content) -> some View {
        let color: Color = containerInk ?? tint.map { (c: Color) -> Color in c.inPalette(P) } ?? step.ink(P)
        return content
            .font(step.font(size: TextStepSizes.size(step, typeSize), numeric: numeric, weight: weight))
            .tracking(step.tracking)
            .textCase(step == .label ? Text.Case.uppercase : nil)
            .foregroundStyle(color)
    }
}

enum TextStepSizes {
    private struct Key: Hashable { var step: TextStep; var size: DynamicTypeSize }
    private static var table: [Key: CGFloat] = [:]

    static func size(_ step: TextStep, _ typeSize: DynamicTypeSize) -> CGFloat {
        let k = Key(step: step, size: typeSize)
        if let v = table[k] { return v }
        let v: CGFloat = step.scaledSize(typeSize)
        table[k] = v
        return v
    }
}

private struct ContainerInkKey: EnvironmentKey { static let defaultValue: Color? = nil }
extension EnvironmentValues {
    var containerInk: Color? {
        get { self[ContainerInkKey.self] }
        set { self[ContainerInkKey.self] = newValue }
    }
}

extension View {
    func textStyle(_ step: TextStep, tint: Color? = nil, numeric: Bool = false, weight: Font.Weight? = nil) -> some View {
        modifier(TextStepStyle(step: step, tint: tint, numeric: numeric, weight: weight))
    }

    func containerInk(_ ink: Color) -> some View {
        environment(\.containerInk, ink).foregroundStyle(ink)
    }

    /// Raised surfaces are drawn flat: a soft shadow over a whole card is an offscreen pass on every frame.
    /// Surfaces already separate from the page by their fill and hairline.
    func elevation(_ level: Theme.Elevation) -> some View { self }
}

extension Font {
    static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .default).monospacedDigit() }
    static func hero(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif).monospacedDigit() }
    static func serifTitle(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }
    static let heading = TextStep.headline.fixedFont
    static let label = Font.system(size: 12, weight: .medium)
    static let bodyText = Font.system(.subheadline, design: .default)
    static let caps = Font.system(size: 11, weight: .semibold)
}

extension View {
    func capsLabel(_ tint: Color? = nil) -> some View {
        modifier(CapsLabelStyle(tint: tint))
    }
}

struct CapsLabelStyle: ViewModifier {
    var tint: Color?
    func body(content: Content) -> some View {
        content.textStyle(.label, tint: tint)
    }
}

struct Hairline: View {
    @Environment(\.outsidePalette) private var palette
    var body: some View { Rectangle().fill(palette.hairline).frame(height: 0.5) }
}
