import SwiftUI
import GameCore
import Simulation

/// Where the player's cosmetic choice is kept (per device, in UserDefaults through @AppStorage). The rules (what may be worn) live in
/// the engine (`Cosmetics`); a lapsed Pro simply resolves to the default badge and theme until Pro returns.
enum CosmeticKeys {
    static let badge: String = "cosmetics.badge"
    static let theme: String = "cosmetics.theme"
}

extension Cosmetics.Palette {
    /// The accent colour of this palette.
    var accent: Color { Color(red: red, green: green, blue: blue) }
}

/// A round logo badge: the symbol in the accent colour on a soft disc.
struct CosmeticBadgeView: View {
    var badge: Cosmetics.Badge
    var tint: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: badge.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.16)))
            .overlay(Circle().strokeBorder(tint.opacity(0.55), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// A ring that fills to `progress` (0...1) in the accent colour.
struct AccentRing: View {
    var progress: Double
    var tint: Color
    var size: CGFloat = 44

    var body: some View {
        let width: CGFloat = max(3, size * 0.085)
        let arc: Double = HomeProgress.clamp(progress)
        return ZStack {
            Circle().stroke(Theme.border, lineWidth: width)
            Circle().trim(from: 0, to: arc)
                .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A percentage that counts up when its value is animated.
struct CountUpPercent: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(saturating: value.rounded()))%").monospacedDigit()
    }
}

// MARK: Wardrobe

/// The Pro wardrobe: pick a logo badge and an accent colour, with a live preview. Career badges are free once earned; premium
/// badges and the colour themes need Ledger Pro. Locked items can be previewed, not worn.
struct WardrobeView: View {
    @EnvironmentObject var store: GameStore
    @Environment(Entitlements.self) private var ent
    @Environment(\.popupClose) private var popupClose
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CosmeticKeys.badge) private var savedBadge: String = Cosmetics.defaultBadgeID
    @AppStorage(CosmeticKeys.theme) private var savedTheme: String = Cosmetics.defaultThemeID
    @State private var previewBadge: String = Cosmetics.defaultBadgeID
    @State private var previewTheme: String = Cosmetics.defaultThemeID

    private var earned: [String] { store.engine?.careerCosmetics ?? [] }

    var body: some View {
        let pro: Bool = ent.isPro
        let badgeOK: Bool = Cosmetics.isBadgeUnlocked(previewBadge, earned: earned, pro: pro)
        let themeOK: Bool = Cosmetics.isThemeUnlocked(previewTheme, pro: pro)
        let accent: Color = Cosmetics.theme(previewTheme).accent
        let content = VStack(alignment: .leading, spacing: Theme.Space.xl) {
            preview(accent: accent)
            themeSection(pro: pro)
            badgeSection(pro: pro)
        }
        return withUnlock(content, show: !(badgeOK && themeOK))
        .onAppear {
            previewBadge = Cosmetics.resolvedBadge(savedBadge, earned: earned, pro: pro).id
            previewTheme = Cosmetics.resolvedTheme(savedTheme, pro: pro).id
        }
    }

    private func preview(accent: Color) -> some View {
        let badge: Cosmetics.Badge = Cosmetics.badge(previewBadge)
        let st: Career.RankStatus? = store.engine?.careerStatus
        let rank: String = st?.rank.title ?? "Street Vendor"
        let progress: Double = st?.progress ?? 0.4
        return VStack(spacing: Theme.Space.s) {
            ZStack {
                AccentRing(progress: progress, tint: accent, size: 92)
                CosmeticBadgeView(badge: badge, tint: accent, size: 56)
            }
            .padding(.bottom, Theme.Space.xs)
            Text(rank).popupText(.figure).multilineTextAlignment(.center)
            Text(Cosmetics.theme(previewTheme).title + " · " + badge.title).popupText(.caption).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.s)
        .accessibilityElement(children: .combine)
        .animation(Motion.quick(reduceMotion), value: previewTheme)
        .animation(Motion.quick(reduceMotion), value: previewBadge)
    }

    private func themeSection(pro: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colour").textStyle(.label, tint: Theme.inkFaint)
            HStack(spacing: Theme.Space.s) {
                ForEach(Cosmetics.themes) { (t: Cosmetics.Palette) in
                    themeDot(t, pro: pro)
                }
            }
        }
    }

    private func themeDot(_ t: Cosmetics.Palette, pro: Bool) -> some View {
        let open: Bool = Cosmetics.isThemeUnlocked(t.id, pro: pro)
        let on: Bool = previewTheme == t.id
        return Button {
            Haptics.choose()
            previewTheme = t.id
            if open { savedTheme = t.id }
        } label: {
            ZStack {
                Circle().fill(t.accent).frame(width: 34, height: 34)
                if !open { LedgerGlyph(glyph: Glyph.lock, size: 12, tint: Color.black.opacity(0.65)) }
            }
            .padding(4)
            .overlay(Circle().strokeBorder(on ? Theme.ivory : Color.clear, lineWidth: 2))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(t.title + (open ? "" : ", needs Ledger Pro"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func badgeSection(pro: Bool) -> some View {
        let accent: Color = Cosmetics.theme(previewTheme).accent
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 74), spacing: 8)]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Logo badge").textStyle(.label, tint: Theme.inkFaint)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Cosmetics.badges) { (b: Cosmetics.Badge) in
                    badgeCell(b, accent: accent, pro: pro)
                }
            }
        }
    }

    private func badgeCell(_ b: Cosmetics.Badge, accent: Color, pro: Bool) -> some View {
        let open: Bool = Cosmetics.isBadgeUnlocked(b.id, earned: earned, pro: pro)
        let on: Bool = previewBadge == b.id
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        let note: String = open ? b.title : (b.premium ? "Pro" : "Earn in Goals")
        return Button {
            Haptics.choose()
            previewBadge = b.id
            if open { savedBadge = b.id }
        } label: {
            VStack(spacing: 5) {
                CosmeticBadgeView(badge: b, tint: open ? accent : Theme.ivoryDim, size: 36)
                Text(note).textStyle(.caption, tint: open ? Theme.inkSoft : Theme.inkFaint).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 64).padding(.vertical, Theme.Space.s)
            .background(shape.fill(on ? Theme.inset : Color.clear))
            .overlay(shape.strokeBorder(on ? accent.opacity(0.8) : Color.clear, lineWidth: 1))
            .opacity(open ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(b.title + (open ? "" : (b.premium ? ", needs Ledger Pro" : ", not earned yet")))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Pins the unlock bar under the popup's body while the previewed look is locked.
    @ViewBuilder private func withUnlock<V: View>(_ v: V, show: Bool) -> some View {
        if show { v.popupFooter { unlockBar } } else { v }
    }

    /// Shown while the previewed look is locked.
    private var unlockBar: some View {
        let lockedByPro: Bool = (Cosmetics.badge(previewBadge).premium && !ent.isPro) || (Cosmetics.theme(previewTheme).premium && !ent.isPro)
        return VStack(spacing: 6) {
            if lockedByPro {
                Button("Unlock with Ledger Pro") {
                    Haptics.tap()
                    popupClose?()
                    ent.paywall = PaywallRequest(title: "Wardrobe")
                }
                .buttonStyle(PopupPrimaryCapsuleStyle(tone: .prestige))
                .accessibilityIdentifier("wardrobe-unlock")
            } else {
                Text("Earned in your career.")
                    .popupText(.caption)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
