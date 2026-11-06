import SwiftUI
import UIKit

// Colour   Theme roles page, surface, surfaceRaised, inset, line, lineStrong, ink, inkSoft, inkFaint, accent, accentInk, gain, loss,
//          warn, alert, focus, scrim; views read them from `@Environment(\.outsidePalette)` so outside apps recolour themselves.
// Type     `.textStyle(.display / .title / .figure / .headline / .body / .caption / .label)`: scales with Dynamic Type, sets the ink role.
// Space    Theme.Space xxs 2, xs 4, s 8, m 12, l 16, xl 24, xxl 32 and one page margin `Theme.Space.page` (20). Radius small 8 (controls),
//          medium 12 (groups, tiles), large 16 (popups). Elevation: flat in a page; `.elevation(.raised)` only for what floats.
// Groups   `CardSection` / `LedgerSection` titled groups, `LedgerRow` for every row, `Hairline` between rows; a Card inside a group is flat.
// Numbers  `Figure`, `FigureRow`; charts in `ChartFrame` with `ChartPalette`; states `EmptyState`, `LoadingState`; bars `ProgressLine`.
// Buttons  `PrimaryButtonStyle` (one per screen), `SecondaryButtonStyle`, `TertiaryButtonStyle`, `.regular` or `.compact` (44 pt hit area);
//          `PrimaryAction` says why it is blocked. Choice `SegmentedPill`, navigation `SectionTabs`, input `LedgerField`, `LedgerSlider`.
// Never    gradients, glows, shimmer, a border around everything or a box inside a box: tone and hairlines carry the structure.
enum Theme {
    // MARK: Colour roles
    static let page = Color(hex: 0x0F1011)                                    // the page
    static let surface = Color(hex: 0x151617)                                 // a group or tile on the page
    static let surfaceRaised = Color(hex: 0x1A1B1D)                           // what floats: popup, tab bar, toast, menu
    static let inset = Color(hex: 0xF1EBDD, opacity: 0.05)                    // segment track, field, pressed row
    static let line = Color(red: 0.937, green: 0.914, blue: 0.875).opacity(0.09) // every separator, 0.5 pt
    static let lineStrong = Color(hex: 0x3A3B3D)                              // control outlines only
    static let ink = Color(hex: 0xF1EBDD)                                     // main text
    static let inkSoft = Color(hex: 0xA19B8F)                                 // secondary text
    static let inkFaint = Color(hex: 0x8A857C)                                // tertiary text, chevrons (4.5:1 on page)
    static let accent = Color(hex: 0xD6B889)                                  // champagne: labels, links, the one action
    static let accentInk = Color(red: 0.09, green: 0.075, blue: 0.055)       // text and icons on a filled accent
    static let accentWash = Color(hex: 0xD6B889, opacity: 0.14)               // a selected option
    static let gain = Color(hex: 0x7FC79B)
    static let loss = Color(hex: 0xE58B78)
    static let warn = Color(hex: 0xE0B064)
    /// The red notification bubble (counts on app icons and tabs). Not a loss colour: it only ever carries a number.
    static let alert = Color(hex: 0xE5584B)
    static let focus = Color(hex: 0xD6B889)                                   // focused field, keyboard focus
    static let scrim = Color.black.opacity(0.55)                              // behind a popup
    /// Chart-only second hue.
    static let slateBlue = Color(red: 0.322, green: 0.451, blue: 0.682)
    static let roseGold = Color(red: 0.851, green: 0.682, blue: 0.384)

    // MARK: Older names: each is an alias of a role above so every screen keeps compiling.
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
    /// Chart-only hues now (no gradients use them); new charts take `ChartPalette`.
    static let goldDeep = Color(red: 0.722, green: 0.600, blue: 0.427)
    static let goldLight = Color(red: 0.863, green: 0.753, blue: 0.592)
    static let onGold = accentInk
    static let caution = warn
    static let goldWash = accentWash
    static let goldSelected = accentWash
    static let goldGradient = LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom)
    static let background = LinearGradient(colors: [page, page], startPoint: .top, endPoint: .bottom)

    // MARK: Metrics
    enum Space {
        static let xxs: CGFloat = 2, xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32
        /// The one horizontal page margin.
        static let page: CGFloat = 20
        static let margin: CGFloat = 20
    }
    enum Radius {
        /// Controls (buttons, fields, segments, tables), groups and tiles, popups and sheets.
        static let small: CGFloat = 8, medium: CGFloat = 12, large: CGFloat = 16
        // Older names mapped onto the three steps.
        static let s: CGFloat = 8, m: CGFloat = 8, l: CGFloat = 12
        static let hero: CGFloat = 16, card: CGFloat = 12, row: CGFloat = 12, table: CGFloat = 8, appIcon: CGFloat = 15
    }
    /// Icon sizes of rows and controls, drawn at one stroke weight.
    enum Icon {
        static let small: CGFloat = 16, medium: CGFloat = 20, large: CGFloat = 28
        /// Rendered stroke width in points, whatever the icon size.
        static let stroke: CGFloat = 1.5
    }

    /// Two levels: flat (everything in a page) and raised (only what floats over it).
    enum Elevation { case flat, raised }
    /// The raised shadow: soft, low, black (no glow).
    enum Shadow { static let color = Color.black.opacity(0.32); static let radius: CGFloat = 16; static let y: CGFloat = 8 }

    static func tone(_ name: String) -> Color {
        switch name { case "good": return gain; case "bad": return loss; case "warn": return warn; default: return inkSoft }
    }
    static func change(_ v: Double) -> Color { v > 0.0000001 ? gain : v < -0.0000001 ? loss : inkSoft }
}

extension Color {
    /// The same colour in an outside app's palette: the game's own text, accent, line and meaning colours become the palette's, anything else stays.
    /// Under `.game` every mapping is the identity, so Company screens look exactly as before; inside the ivory Bank and Accounting it keeps shared
    /// pieces (`Stat`, `Chip`, `ListRow`, `TableRow`...) readable when a caller passes `Theme.ivory` or `Theme.loss`.
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

    /// `Color(hex: 0xD6B889)`: the mockups' hex values, used by the Theme tokens.
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// The type scale: seven steps. Serif for what is read as a figure or a title, sans for reading, caps for labels.
/// Sizes are at the default text size; `.textStyle` scales them with Dynamic Type (never below 11 pt).
enum TextStep {
    /// The one big number or name of a screen: serif 34 medium, tabular.
    case display
    /// A screen or sheet title: serif 24 medium.
    case title
    /// A key amount: serif 20 medium, tabular.
    case figure
    /// Row titles, button labels, a block's lead line: sans 15 medium.
    case headline
    /// Running text and row values: sans 14.
    case body
    /// Notes, sublines, explanations: sans 12, soft ink.
    case caption
    /// Section and figure labels: sans 11 semibold, capitals, tracked, accent.
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

    /// Steps that always use tabular digits.
    var isNumeric: Bool { self == .display || self == .figure }
    var tracking: CGFloat { self == .label ? 1.2 : 0 }

    /// The default ink of the step in a palette.
    func ink(_ p: OutsidePalette) -> Color {
        switch self {
        case .caption: return p.inkSoft
        case .label: return p.accent
        default: return p.ink
        }
    }

    /// The step at its default size, for an API that needs a `Font` value. Prefer `.textStyle`, which scales.
    var fixedFont: Font { font(size: size, numeric: isNumeric, weight: nil) }

    func font(size s: CGFloat, numeric: Bool, weight w: Font.Weight?) -> Font {
        let base: Font = Font.system(size: max(11, s), weight: w ?? weight, design: design)
        return (numeric || isNumeric) ? base.monospacedDigit() : base
    }
}

extension TextStep {
    /// The UIKit text style the step scales with (the same curve as `relativeTo`).
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

    /// The step's point size at a Dynamic Type size (nil: the system's current size).
    func scaledSize(_ dynamicType: DynamicTypeSize? = nil) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: uiTextStyle)
        guard let dynamicType else { return metrics.scaledValue(for: size) }
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicType))
        return metrics.scaledValue(for: size, compatibleWith: traits)
    }

    /// The step as a scaled `Font` for places `.textStyle` cannot reach (`Text + Text` joins, `TextField`, `Font` parameters).
    /// Font only: ink, tracking and capitals stay with the caller. Pass `@Environment(\.dynamicTypeSize)` so the view redraws on a change.
    func scaledFont(_ dynamicType: DynamicTypeSize? = nil, numeric: Bool = false, weight: Font.Weight? = nil) -> Font {
        font(size: scaledSize(dynamicType), numeric: numeric, weight: weight)
    }
}

extension Font {
    /// `Font.step(.caption)`: one step of the type scale as a Dynamic Type scaled `Font` (see `TextStep.scaledFont`).
    static func step(_ step: TextStep, dynamicType: DynamicTypeSize? = nil, numeric: Bool = false, weight: Font.Weight? = nil) -> Font {
        step.scaledFont(dynamicType, numeric: numeric, weight: weight)
    }
}

/// Applies a `TextStep`: font (scaled with Dynamic Type), tracking, capitals and the step's ink from the palette.
struct TextStepStyle: ViewModifier {
    var step: TextStep
    var tint: Color?
    var numeric: Bool
    var weight: Font.Weight?
    @ScaledMetric private var size: CGFloat
    @Environment(\.outsidePalette) private var P

    init(step: TextStep, tint: Color? = nil, numeric: Bool = false, weight: Font.Weight? = nil) {
        self.step = step
        self.tint = tint
        self.numeric = numeric
        self.weight = weight
        self._size = ScaledMetric(wrappedValue: step.size, relativeTo: step.relativeTo)
    }

    func body(content: Content) -> some View {
        let color: Color = tint.map { (c: Color) -> Color in c.inPalette(P) } ?? step.ink(P)
        return content
            .font(step.font(size: size, numeric: numeric, weight: weight))
            .tracking(step.tracking)
            .textCase(step == .label ? Text.Case.uppercase : nil)
            .foregroundStyle(color)
    }
}

extension View {
    /// Sets font, ink and tracking from one step of the type scale. `tint` overrides the ink (mapped into the outside palette),
    /// `numeric` gives tabular digits, `weight` is for the rare emphasis inside a step.
    func textStyle(_ step: TextStep, tint: Color? = nil, numeric: Bool = false, weight: Font.Weight? = nil) -> some View {
        modifier(TextStepStyle(step: step, tint: tint, numeric: numeric, weight: weight))
    }

    /// Flat (nothing) or raised (the one soft shadow) elevation. Raised is only for what floats over the page.
    @ViewBuilder func elevation(_ level: Theme.Elevation) -> some View {
        switch level {
        case .flat: self
        case .raised: self.shadow(color: Theme.Shadow.color, radius: Theme.Shadow.radius, x: 0, y: Theme.Shadow.y)
        }
    }
}

/// Older size-taking helpers. New code uses `.textStyle`; these stay so existing screens compile.
extension Font {
    static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .default).monospacedDigit() }
    /// The hero figure of a screen (net worth, group value, a company's profit).
    static func hero(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif).monospacedDigit() }
    static func serifTitle(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .serif) }
    static let heading = TextStep.headline.fixedFont
    static let label = Font.system(size: 12, weight: .medium)
    static let bodyText = Font.system(.subheadline, design: .default)
    static let caps = Font.system(size: 11, weight: .semibold)
}

extension View {
    /// A section label: the `.label` step (small caps, tracked, champagne unless tinted).
    func capsLabel(_ tint: Color? = nil) -> some View {
        modifier(CapsLabelStyle(tint: tint))
    }
}

/// `capsLabel` as a modifier so the default colour follows the outside app's palette (champagne in the game's own screens).
struct CapsLabelStyle: ViewModifier {
    var tint: Color?
    func body(content: Content) -> some View {
        content.textStyle(.label, tint: tint)
    }
}

/// A 0.5 pt line.
struct Hairline: View {
    @Environment(\.outsidePalette) private var palette
    var body: some View { Rectangle().fill(palette.hairline).frame(height: 0.5) }
}
