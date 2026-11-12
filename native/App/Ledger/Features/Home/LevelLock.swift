import SwiftUI
import GameCore
import Businesses
import Simulation

extension GameStore {
    func levelOpen(_ f: LevelFeature) -> Bool { engine.map { (e: GameEngine) -> Bool in LevelGates.isOpen(f, e.state) } ?? true }
}

struct LevelLockCard: View {
    @EnvironmentObject var store: GameStore
    var feature: LevelFeature

    var body: some View {
        if let e = store.engine {
            let p: LevelGates.Progress = LevelGates.progress(feature, e.state)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    LedgerGlyph(glyph: Glyph.lock, size: Theme.Icon.medium, tint: Theme.gold)
                    Text(LevelGates.title(feature)).textStyle(.headline)
                }
                Text(LevelGates.lockLine(feature)).textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
                ProgressLine(fraction: p.fraction, tint: Theme.gold, height: 4)
                Text("Lets you " + LevelGates.gives(feature) + ". \(p.xpToGo) XP to go.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("level-lock-\(feature.rawValue)")
        }
    }
}

struct LevelLockScreen: View {
    var feature: LevelFeature
    var back: (() -> Void)? = nil

    var body: some View {
        PhonePageScroll(spacing: Theme.Space.l) {
            if let back {
                Button { Haptics.tap(); back() } label: { Text("Back") }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
            }
            LevelLockCard(feature: feature)
        }
        .appScreen(title: LevelGates.title(feature), subtitle: "Not open yet")
    }
}

struct LevelGuard<Content: View>: View {
    @EnvironmentObject var store: GameStore
    var feature: LevelFeature
    @ViewBuilder var content: () -> Content

    var body: some View {
        if store.levelOpen(feature) { content() } else { LevelLockScreen(feature: feature) }
    }
}

struct LevelLockRow: View {
    @EnvironmentObject var store: GameStore
    var feature: LevelFeature

    var body: some View {
        if let e = store.engine {
            let p: LevelGates.Progress = LevelGates.progress(feature, e.state)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: Theme.Space.s) {
                    LedgerGlyph(glyph: Glyph.lock, size: Theme.Icon.small, tint: Theme.inkFaint)
                    Text(LevelGates.title(feature)).textStyle(.body, tint: Theme.inkSoft)
                }
                Text(LevelGates.lockLine(feature)).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                ProgressLine(fraction: p.fraction, tint: Theme.gold, height: 3)
            }
            .padding(.vertical, Theme.Space.s)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("level-lock-row-\(feature.rawValue)")
        }
    }
}

struct HomeNextUnlock: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        if let f = LevelGates.nextLocked(engine.state) {
            let p: LevelGates.Progress = LevelGates.progress(f, engine.state)
            line("Level \(LevelGates.level(f)) unlocks \(LevelGates.title(f))", fraction: p.fraction, detail: "\(p.xpToGo) XP to go")
        }
    }

    private func line(_ title: String, fraction: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack(spacing: Theme.Space.s) {
                LedgerGlyph(glyph: Glyph.lock, size: Theme.Icon.small, tint: Theme.inkFaint)
                Text(title).textStyle(.caption, tint: Theme.inkSoft).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: Theme.Space.xs)
                if !detail.isEmpty { Text(detail).textStyle(.caption, numeric: true).lineLimit(1).minimumScaleFactor(0.8) }
            }
            ProgressLine(fraction: fraction, tint: Theme.gold, height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home-next-unlock")
    }
}
