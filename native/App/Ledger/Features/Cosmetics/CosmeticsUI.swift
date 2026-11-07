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
        Text("\(Int(value.rounded()))%").monospacedDigit()
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
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview(accent: accent)
                    themeSection(pro: pro)
                    badgeSection(pro: pro)
                    Text("Badges you earn in your career are yours to wear for ever. Extra badges and colours come with Ledger Pro. Looks only: nothing here changes your game.")
                        .popupText(.caption)
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            if !(badgeOK && themeOK) { unlockBar }
        }
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
        return Card(padding: 14, radius: Theme.Radius.hero) {
            HStack(spacing: 14) {
                ZStack {
                    AccentRing(progress: progress, tint: accent, size: 64)
                    CosmeticBadgeView(badge: badge, tint: accent, size: 38)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview").capsLabel()
                    Text(rank).popupText(.figure)
                    HStack(spacing: 6) {
                        Capsule().fill(accent).frame(width: 26, height: 4)
                        Text(Cosmetics.theme(previewTheme).title + " · " + badge.title)
                            .popupText(.caption)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .animation(Motion.quick(reduceMotion), value: previewTheme)
        .animation(Motion.quick(reduceMotion), value: previewBadge)
    }

    private func themeSection(pro: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Colour").capsLabel()
            HStack(spacing: 10) {
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
                if !open { Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.black.opacity(0.65)) }
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
            Text("Logo badge").capsLabel()
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
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(shape.fill(on ? Theme.goldSelected : Theme.surface))
            .overlay(shape.strokeBorder(on ? accent : Theme.border, lineWidth: 1))
            .opacity(open ? 1 : 0.7)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(b.title + (open ? "" : (b.premium ? ", needs Ledger Pro" : ", not earned yet")))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Shown while the previewed look is locked.
    private var unlockBar: some View {
        let lockedByPro: Bool = (Cosmetics.badge(previewBadge).premium && !ent.isPro) || (Cosmetics.theme(previewTheme).premium && !ent.isPro)
        return VStack(spacing: 6) {
            if lockedByPro {
                QuietButton(title: "Unlock with Ledger Pro", fullWidth: true) {
                    popupClose?()
                    ent.paywall = PaywallRequest(title: "Wardrobe")
                }
            } else {
                Text("This badge is won in your career. Keep playing to earn it.")
                    .popupText(.caption)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Theme.page)
    }
}
