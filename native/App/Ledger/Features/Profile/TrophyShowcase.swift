import SwiftUI
import GameCore
import Events
import Simulation

enum TrophyList {
    static func unlocked(_ e: GameEngine) -> [Trophies.Entry] {
        Trophies.entries(e.state).filter { $0.reachedWeek != nil }.sorted { ($0.reachedWeek ?? 0) > ($1.reachedWeek ?? 0) }
    }

    static func awards(_ e: GameEngine) -> [(year: Int, result: Awards.Result)] {
        Awards.years(e.state).flatMap { (y: Awards.Year) -> [(year: Int, result: Awards.Result)] in
            y.results.filter { $0.won }.map { (year: y.year, result: $0) }
        }
    }
}

struct TrophyShowcase: View {
    @EnvironmentObject var store: GameStore

    private let columns: [GridItem] = [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible(), spacing: Theme.Space.m)]

    var body: some View {
        Group {
            if let e = store.engine {
                let got: [Trophies.Entry] = TrophyList.unlocked(e)
                let awards: [(year: Int, result: Awards.Result)] = TrophyList.awards(e)
                if got.isEmpty && awards.isEmpty {
                    ScrollView {
                        EmptyState(glyph: Glyph.achievements, title: "Nothing in the showroom yet",
                                   message: "Firsts and milestones show up here: the first customer, the first employee, the first million.", centered: true)
                            .padding(.top, Theme.Space.xxl)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.xl) {
                            ForEach(Trophies.groups, id: \.id) { g in
                                let list: [Trophies.Entry] = got.filter { $0.group == g.id }
                                if !list.isEmpty { section(g.name, list) }
                            }
                            if !awards.isEmpty { awardsSection(awards) }
                        }
                        .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 24)
                        .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .ledgerBackground()
        .appScreen(title: "Trophies", subtitle: "Everything you have won")
    }

    private func section(_ title: String, _ list: [Trophies.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(title).capsLabel()
            LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                ForEach(list) { (t: Trophies.Entry) in plinth(t) }
            }
        }
    }

    private func plinth(_ t: Trophies.Entry) -> some View {
        VStack(spacing: Theme.Space.s) {
            ThumbnailView(kind: .trophy, key: ArtLibrary.trophyKey(id: t.id, group: t.group), size: 72, shape: .round, glyph: Glyph.achievements, tint: Theme.gold)
            Text(t.name).textStyle(.headline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if !t.text.isEmpty {
                Text(t.text.tidyMoney).textStyle(.caption).multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Text(t.before ? "Before the showroom" : GameCalendar.dateString(week: t.reachedWeek ?? 0)).textStyle(.caption, tint: Theme.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Space.m)
        .glassSurface()
        .accessibilityElement(children: .combine)
    }

    private func awardsSection(_ awards: [(year: Int, result: Awards.Result)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Business awards").capsLabel()
            LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                ForEach(Array(awards.enumerated()), id: \.offset) { (_: Int, a: (year: Int, result: Awards.Result)) in
                    VStack(spacing: Theme.Space.s) {
                        ThumbnailView(kind: .trophy, key: ArtLibrary.awardKey(a.result.kind), size: 72, shape: .round, glyph: Glyph.achievements, tint: Theme.gold)
                        Text(Awards.name(a.result.kind)).textStyle(.headline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Text(a.result.company).textStyle(.caption).multilineTextAlignment(.center).lineLimit(2)
                        Text(String(a.year)).textStyle(.caption, tint: Theme.inkFaint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Space.m)
                    .glassSurface()
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
