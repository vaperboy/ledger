import SwiftUI
import GameCore
import Businesses
import Simulation

struct LevelLadderView: View {
    var engine: GameEngine

    var body: some View {
        let info: PlayerLevel.Info = engine.playerLevel
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    header(info)
                    next(info)
                    nextIcon(info)
                    LazyVStack(spacing: Theme.Space.s) {
                        ForEach(1...PlayerLevel.maxLevel, id: \.self) { (level: Int) in row(level, info).id(level) }
                    }
                    Text("The highest level is \(PlayerLevel.maxLevel). XP comes from \(PlayerLevel.ladderXP) for each step of the ladder, \(PlayerLevel.dailyXP) for the daily goal and \(PlayerLevel.weekXP) for every week you play. Level icons belong to your account and cannot be traded.")
                        .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, Theme.Space.l)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo(max(1, info.level - 1), anchor: .top) }
            }
        }
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
            if info.level >= PlayerLevel.maxLevel {
                Text("You reached the highest level.").textStyle(.caption)
            } else {
                Text("\(info.xpIntoLevel.formatted()) of \(info.xpForNext.formatted()) XP to level \(info.level + 1)").textStyle(.caption, numeric: true)
            }
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

    @ViewBuilder private func nextIcon(_ info: PlayerLevel.Info) -> some View {
        if let r = LevelRewards.all.first(where: { (x: LevelRewards.Reward) -> Bool in x.level > info.level && x.icon != nil }), let id = r.icon {
            HStack(spacing: Theme.Space.m) {
                ItemArt(avatar: id, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next icon").textStyle(.label, tint: Theme.gold)
                    Text("Level \(r.level): " + (AvatarCatalog.def(id)?.title ?? "Icon")).textStyle(.body, weight: .medium)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
            .accessibilityElement(children: .combine)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).textStyle(.body, tint: Theme.inkSoft)
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
    }

    private func row(_ level: Int, _ info: PlayerLevel.Info) -> some View {
        let reached: Bool = info.level >= level
        let current: Bool = info.level == level
        let unlocks: [LevelGates.Entry] = LevelGates.unlocks(atLevel: level)
        let reward: LevelRewards.Reward? = LevelRewards.reward(at: level)
        let icon: String? = reward?.icon
        let notable: Bool = !unlocks.isEmpty || icon != nil
        return HStack(alignment: .top, spacing: Theme.Space.m) {
            Text("\(level)").textStyle(.headline, tint: reached ? Theme.ink : Theme.inkSoft, numeric: true)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(unlocks) { (u: LevelGates.Entry) in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        LedgerGlyph(glyph: reached ? Glyph.check : Glyph.lock, size: 12, tint: reached ? Theme.gain : Theme.inkFaint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(u.title).textStyle(.body, tint: reached ? Theme.ink : Theme.inkSoft, weight: .medium)
                            Text(u.gives.prefix(1).uppercased() + u.gives.dropFirst()).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let icon {
                    HStack(spacing: Theme.Space.s) {
                        ItemArt(avatar: icon, size: 28)
                        Text((AvatarCatalog.def(icon)?.title ?? "Icon") + " icon").textStyle(.caption, tint: reached ? Theme.ink : Theme.inkSoft)
                    }
                }
                if let reward {
                    Text("+\(reward.gold) gold").textStyle(.caption, tint: reached ? Theme.gain : Theme.inkFaint, numeric: true)
                } else if level == 1 {
                    Text("Where every game starts.").textStyle(.caption)
                }
            }
            Spacer(minLength: 0)
            if current { StoreTag(text: "You are here") }
        }
        .padding(notable || current ? Theme.Space.m : Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(raised: current)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).strokeBorder(current ? Theme.gold : Color.clear, lineWidth: 1.5))
        .opacity(reached && !current ? 0.75 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("level-rung-\(level)")
    }
}

extension View {
    func levelLadderPopup(isPresented: Binding<Bool>, engine: GameEngine) -> some View {
        centerSheet(isPresented: isPresented, title: "Level map", size: .tall, category: .detail, tone: .info) { LevelLadderView(engine: engine) }
    }
}
