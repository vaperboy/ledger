import SwiftUI
import GameCore
import Events
import Simulation

/// The showroom: only what has been won. Trophies stand in a two-column display, group by group with the newest group first, and the
/// yearly business awards sit below. Nothing locked or missing is shown.
struct AchievementsView: View {
    @EnvironmentObject var store: GameStore

    private let columns: [GridItem] = [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible(), spacing: Theme.Space.m)]

    var body: some View {
        if let e = store.engine {
            let entries: [Trophies.Entry] = Trophies.entries(e.state)
            let got: [Trophies.Entry] = entries.filter { $0.reachedWeek != nil }
            let awards: [(year: Int, result: Awards.Result)] = Awards.years(e.state).flatMap { (y: Awards.Year) -> [(year: Int, result: Awards.Result)] in
                y.results.filter { $0.won }.map { (year: y.year, result: $0) }
            }
            if got.isEmpty && awards.isEmpty {
                ScrollView {
                    EmptyState(glyph: Glyph.achievements, title: "Nothing in the showroom yet",
                               message: "Firsts and milestones show up here: the first customer, the first employee, the first million.", centered: true)
                        .padding(.top, Theme.Space.xxl)
                }
                .ledgerBackground()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        hero(trophies: got.count, awards: awards.count)
                        ForEach(Trophies.groups, id: \.id) { g in
                            let list: [Trophies.Entry] = got.filter { $0.group == g.id }
                                .sorted { ($0.reachedWeek ?? 0) > ($1.reachedWeek ?? 0) }
                            if !list.isEmpty { section(g.name, list) }
                        }
                        if !awards.isEmpty { awardsSection(awards) }
                    }
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 24)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .ledgerBackground()
            }
        }
    }

    private func hero(trophies: Int, awards: Int) -> some View {
        HStack(spacing: Theme.Space.l) {
            GoldRingMark(glyph: Glyph.achievements, size: 64)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("\(trophies) \(trophies == 1 ? "trophy" : "trophies")").textStyle(.title)
                if awards > 0 { Text("\(awards) business \(awards == 1 ? "award" : "awards")").textStyle(.caption, tint: Theme.accent) }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func section(_ title: String, _ list: [Trophies.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(title).capsLabel()
            LazyVGrid(columns: columns, spacing: Theme.Space.m) {
                ForEach(list) { (t: Trophies.Entry) in plinth(t) }
            }
        }
    }

    /// One trophy on its stand: the art, the name, a line on what it was for, and when it was won.
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
        .newMarker(.achievements, "t" + t.id, style: .dot, alignment: .topLeading)
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
