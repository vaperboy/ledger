import SwiftUI
import GameCore
import Events
import Simulation

/// The trophy wall: firsts and milestones, in groups, with the date you reached each one. Original: V.trophies28.
struct AchievementsView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine {
            let entries = Trophies.entries(e.state)
            let got = entries.filter { $0.reachedWeek != nil }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    HeroFigure(label: "Trophies", value: "\(got.count) of \(entries.count)")
                    FigureCard(items: [
                        .init(label: "Awards won", value: "\(Awards.wonCount(e.state))"),
                        .init(label: "Latest", value: got.max { ($0.reachedWeek ?? 0) < ($1.reachedWeek ?? 0) }?.name ?? "None yet")
                    ], columns: 2)
                    ForEach(Trophies.groups, id: \.id) { g in
                        let list = entries.filter { $0.group == g.id }
                        if !list.isEmpty {
                            CardSection(title: g.name, trailing: { Text("\(list.filter { $0.reachedWeek != nil }.count) of \(list.count)").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }) {
                                shelf(list)
                                CardLine()
                                VStack(spacing: 0) {
                                    ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                                        if i > 0 { CardLine() }
                                        row(t)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .ledgerBackground()
        }
    }

    /// A shelf of medallions for one group: won trophies in champagne first, then the empty slots.
    private func shelf(_ list: [Trophies.Entry]) -> some View {
        let wonCount: Int = list.filter { $0.reachedWeek != nil }.count
        let columns: [GridItem] = Array(repeating: GridItem(.adaptive(minimum: 40, maximum: 44), spacing: 8), count: 1)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(0..<list.count, id: \.self) { i in Medallion(won: i < wonCount, size: 38) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(wonCount) of \(list.count) won")
    }

    private func row(_ t: Trophies.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            GlyphView(glyph: t.reachedWeek != nil ? Glyph.achievements : Glyph.ring, size: 18, weight: 1.5, tint: t.reachedWeek != nil ? Theme.gold : Theme.ivoryDim)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).font(.system(size: 14.5)).foregroundStyle(t.reachedWeek != nil ? Theme.ivory : Theme.ivoryMuted)
                if t.reachedWeek != nil, !t.text.isEmpty { Text(t.text.tidyMoney).font(.caption).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            Text(t.reachedWeek.map { t.before ? "Before the wall" : GameCalendar.dateString(week: $0) } ?? "Not yet")
                .font(.caption.monospacedDigit()).foregroundStyle(Theme.ivoryFaint)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

/// A short trophy section for the Stats screen: how many, the latest few, and a way into the whole wall.
struct TrophiesPreview: View {
    @EnvironmentObject var store: GameStore
    var body: some View {
        if let e = store.engine {
            let entries = Trophies.entries(e.state)
            let got = entries.filter { $0.reachedWeek != nil }.sorted { ($0.reachedWeek ?? 0) > ($1.reachedWeek ?? 0) }
            CardSection(title: "Trophies", trailing: {
                NavigationLink {
                    AchievementsView().appScreen(title: "Achievements", subtitle: PhoneApp.achievements.subtitle)
                } label: {
                    LinkLabel(text: "All \(entries.count)")
                }.buttonStyle(.plain)
            }) {
                if got.isEmpty {
                    Text("Firsts and milestones show up here: the first customer, the first employee, the first million.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(got.prefix(3).enumerated()), id: \.element.id) { i, t in
                            if i > 0 { CardLine() }
                            ValueRow(label: t.name, value: t.reachedWeek.map { GameCalendar.dateString(week: $0) } ?? "").padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }
}
