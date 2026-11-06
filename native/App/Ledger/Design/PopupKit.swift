import SwiftUI

/// The three popup categories of the UI quality spec:
/// 1. Short note behind an (i): `InfoPopoverButton` / `InfoSheetButton`, a compact centred popup (no system popover).
/// 2. Standard modal (sized to content, dimmed and locked background, x in the title row): `.centerSheet(isPresented:/item:)`.
/// 3. Confirmation (consequences first, destructive marked, never confirmed by a background tap): `PendingAction` with
///    `.confirmAction($pending)`, which shows `ConfirmPopup`.

/// The small round (i) button for a short note; it opens the same centred popup as `InfoSheetButton`.
struct InfoPopoverButton: View {
    var title: String
    var text: String
    var body: some View { InfoSheetButton(title: title, text: text) }
}


/// Height of the measured content of a `FitScroll` (-1 until measured, so even a measured 0 is reported).
private struct FitScrollHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = -1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A scroll area that is exactly as high as its content, up to `maxHeight`; only taller content scrolls (vertically). Unlike
/// `.frame(maxHeight:)` it never stretches to the maximum, so a popup around it never shows empty space. Content that measures almost
/// nothing (it fills space by itself) gets `maxHeight`; nothing stays hidden: after a short moment it is shown whatever the measurement.
struct FitScroll<Content: View>: View {
    var maxHeight: CGFloat
    /// Called with the measured content height whenever it changes (a popup frame picks its size class from it).
    var onMeasure: ((CGFloat) -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @State private var natural: CGFloat = -1
    @State private var forceShow = false
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reported: Bool = natural >= 0
        let usable: Bool = natural > 0.5
        let height: CGFloat = usable ? min(natural, maxHeight) : maxHeight
        ScrollView(.vertical) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { (g: GeometryProxy) in
                        Color.clear.preference(key: FitScrollHeightKey.self, value: g.size.height)
                    }
                )
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: height)
        .animation(armed ? Motion.size(reduceMotion) : nil, value: height)
        .opacity(reported || forceShow ? 1 : 0)
        .onPreferenceChange(FitScrollHeightKey.self) { (h: CGFloat) in
            natural = h
            if h > 0.5 {
                onMeasure?(h)
                if !armed { DispatchQueue.main.async { armed = true } }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            forceShow = true
        }
    }
}

// MARK: Popup buttons

/// The filled button of a popup with a SOLE action (Continue, OK, Claim): champagne, full width. Never used beside other options.
struct PopupPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14.5, weight: .semibold))
            .lineLimit(1).minimumScaleFactor(0.85)
            .foregroundStyle(Color(red: 0.09, green: 0.075, blue: 0.055))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous)
                .fill(LinearGradient(colors: [Theme.gold, Theme.goldDeep], startPoint: .top, endPoint: .bottom)))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// An option of a popup: an equal, neutral outline (same size and weight for every option, no red). A passive option
/// (Decide later, Postpone, Later, Not now, Skip, Remind me) is drawn lightly grayed.
struct PopupQuietButtonStyle: ButtonStyle {
    var passive: Bool = false
    @Environment(\.outsidePalette) private var P
    func makeBody(configuration: Configuration) -> some View {
        let edge: Color = passive ? P.lineStrong.opacity(0.5) : P.lineStrong
        let ink: Color = passive ? P.ink.opacity(0.5) : P.ink
        return configuration.label
            .font(.system(size: 14, weight: .medium))
            .lineLimit(1).minimumScaleFactor(0.85)
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 14)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(edge, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// One option button of a popup. Every option is the same equal outline; `highlighted` (filled champagne) is only for a SOLE action
/// (Continue, OK, Claim). `destructive` is kept for call sites but changes nothing: irreversible actions are explained in text.
struct PopupOptionButton: View {
    var title: String
    var highlighted: Bool = false
    var destructive: Bool = false
    var identifier: String = ""
    var action: () -> Void

    static func isPassive(_ title: String) -> Bool {
        let t: String = title.trimmingCharacters(in: .whitespaces).lowercased()
        let names: [String] = ["decide later", "postpone", "later", "not now", "skip", "remind me"]
        for n in names where t == n || t.hasPrefix(n + " ") { return true }
        return false
    }

    var body: some View {
        let go: () -> Void = { Haptics.play(.tap); action() }
        if highlighted {
            Button(action: go) { Text(title) }.buttonStyle(PopupPrimaryButtonStyle()).accessibilityIdentifier(identifier)
        } else {
            Button(action: go) { Text(title) }.buttonStyle(PopupQuietButtonStyle(passive: PopupOptionButton.isPassive(title))).accessibilityIdentifier(identifier)
        }
    }
}
