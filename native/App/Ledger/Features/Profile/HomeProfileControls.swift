import SwiftUI
import GameCore
import Simulation

struct HomeProfileButton: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var local = ProfileLocal.shared
    var engine: GameEngine

    var body: some View {
        let info: PlayerLevel.Info = engine.playerLevel
        let name: String = local.name.isEmpty ? engine.state.player.name : local.name
        Button { Haptics.tap(); store.openProfile() } label: {
            VStack(spacing: 3) {
                ProfilePicture(name: name, size: 36)
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(info.level)")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accentInk)
                            .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(Theme.gold))
                            .offset(x: 5, y: 3)
                    }
                ProgressLine(fraction: info.progress, tint: Theme.gold, height: 3).frame(width: 36)
            }
            .frame(width: 44, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Profile, level \(info.level)")
        .accessibilityHint("Opens your profile")
        .accessibilityIdentifier("home-profile")
    }
}

struct HomeGoldChip: View {
    @EnvironmentObject var store: GameStore
    private let session = StoreSession.shared

    var body: some View {
        Button { Haptics.tap(); store.openApp(.store) } label: {
            HStack(spacing: Theme.Space.xs) {
                Circle().fill(Theme.gold).frame(width: 10, height: 10)
                Text(session.gold.formatted()).textStyle(.body, tint: Theme.ink, numeric: true, weight: .semibold).lineLimit(1)
                Image(systemName: "plus").font(.caption2.weight(.bold)).foregroundStyle(Theme.gold).accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Space.s)
            .frame(height: 36)
            .background(Capsule().fill(Theme.surfaceRaised))
            .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .task { await session.load() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.gold) gold")
        .accessibilityHint("Opens the Store")
        .accessibilityIdentifier("home-gold")
    }
}

struct HomeRoundButton: View {
    var glyph: String
    var label: String
    var badge: Int = 0
    var identifier: String
    var action: () -> Void

    var body: some View {
        Button { Haptics.tap(); action() } label: {
            LedgerGlyph(glyph: glyph, size: Theme.Icon.medium, tint: Theme.ink)
                .frame(width: 40, height: 40)
                .liquidGlassCircle()
                .overlay(alignment: .topTrailing) { RedBubble(count: badge, size: .small).offset(x: 6, y: -6) }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityValue(badge > 0 ? "\(badge) waiting" : "")
        .accessibilityIdentifier(identifier)
    }
}

extension GameStore {
    func openProfile() { openApp(.profile) }
    func openSeason() { openApp(.season) }
}
