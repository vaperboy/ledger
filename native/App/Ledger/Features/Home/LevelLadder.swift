import SwiftUI
import GameCore
import Businesses
import Simulation

struct LevelLadderView: View {
    var engine: GameEngine

    var body: some View {
        let info: PlayerLevel.Info = engine.playerLevel
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                header(info)
                next(info)
                ForEach(LevelGates.ladder()) { (rung: LevelGates.Rung) in row(rung, info) }
                Text("Levels keep counting after the last unlock. XP comes from \(PlayerLevel.ladderXP) for each step of the ladder, \(PlayerLevel.dailyXP) for the daily goal and \(PlayerLevel.weekXP) for every week you play.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, Theme.Space.l)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("level-ladder")
    }

    private func header(_ info: PlayerLevel.Info) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Level \(info.level)").textStyle(.title, numeric: true)
                Spacer(minLength: Theme.Space.s)
                Text("\(info.xp.formatted()) XP").textStyle(.body, tint: Theme.inkSoft, numeric: true)
            }
            ProgressLine(fraction: info.progress, tint: Theme.gold, height: 4)
            Text("\(info.xpIntoLevel.formatted()) of \(info.xpForNext.formatted()) XP to level \(info.level + 1)").textStyle(.caption, numeric: true)
        }
        .padding(.horizontal, Theme.Space.xs)
    }

    @ViewBuilder private func next(_ info: PlayerLevel.Info) -> some View {
        if !Gates.ladderOn(engine.state) {
            note("Everything on this ladder is already open in this save.")
        } else if let f = LevelGates.nextLocked(engine.state) {
            let p: LevelGates.Progress = LevelGates.progress(f, engine.state)
            let names: String = LevelGates.opensWith(f).map { (x: LevelFeature) -> String in LevelGates.title(x) }.joined(separator: ", ")
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("Next unlock").textStyle(.label, tint: Theme.gold)
                Text("Level \(LevelGates.level(f)): \(names)").textStyle(.headline).fixedSize(horizontal: false, vertical: true)
                ProgressLine(fraction: p.fraction, tint: Theme.gold, height: 4)
                Text("\(p.xpToGo.formatted()) XP to go").textStyle(.caption, numeric: true)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(raised: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("level-next-unlock")
        } else {
            note("Every unlock on the ladder is open.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).textStyle(.body, tint: Theme.inkSoft)
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
    }

    private func row(_ rung: LevelGates.Rung, _ info: PlayerLevel.Info) -> some View {
        let reached: Bool = info.level >= rung.level
        let current: Bool = info.level == rung.level
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text("Level \(rung.level)").textStyle(.headline, tint: reached ? Theme.ink : Theme.inkSoft, numeric: true)
                if current { StoreTag(text: "You are here") }
                Spacer(minLength: Theme.Space.s)
                Text(rung.level == 1 ? "Start" : "\(rung.xpRequired.formatted()) XP").textStyle(.caption, tint: Theme.inkSoft, numeric: true)
            }
            if rung.unlocks.isEmpty {
                Text(rung.level == 1 ? "Where every game starts." : "No new unlock at this level.").textStyle(.caption)
            } else {
                ForEach(rung.unlocks) { (u: LevelGates.Entry) in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        LedgerGlyph(glyph: reached ? Glyph.check : Glyph.lock, size: 12, tint: reached ? Theme.gain : Theme.inkFaint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(u.title).textStyle(.body, tint: reached ? Theme.ink : Theme.inkSoft, weight: .medium)
                            Text(u.gives.prefix(1).uppercased() + u.gives.dropFirst()).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if rung.level > 1 && !reached {
                Text("\(rung.xpFromPrevious.formatted()) XP more than level \(rung.level - 1)").textStyle(.caption, tint: Theme.inkFaint, numeric: true)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(raised: current)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(current ? Theme.gold : Color.clear, lineWidth: 1.5))
        .opacity(reached && !current ? 0.8 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("level-rung-\(rung.level)")
    }
}

extension View {
    func levelLadderPopup(isPresented: Binding<Bool>, engine: GameEngine) -> some View {
        centerSheet(isPresented: isPresented, title: "Levels", size: .tall, category: .detail, tone: .info) { LevelLadderView(engine: engine) }
    }
}
