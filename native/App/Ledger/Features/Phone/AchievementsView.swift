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
                    KeyFigures(items: [
                        .init(label: "Trophies", value: "\(got.count) of \(entries.count)"),
                        .init(label: "Awards won", value: "\(Awards.wonCount(e.state))"),
                        .init(label: "Latest", value: got.max { ($0.reachedWeek ?? 0) < ($1.reachedWeek ?? 0) }?.name ?? "None yet")
                    ], columns: 3)
                    ForEach(Trophies.groups, id: \.id) { g in
                        let list = entries.filter { $0.group == g.id }
                        if !list.isEmpty {
                            LedgerSection(title: g.name, trailing: { Text("\(list.filter { $0.reachedWeek != nil }.count) of \(list.count)").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }) {
                                VStack(spacing: 0) {
                                    ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                                        if i > 0 { Hairline() }
                                        row(t)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .ledgerBackground()
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ t: Trophies.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
            Image(systemName: t.reachedWeek != nil ? "checkmark.circle" : "circle")
                .font(.system(size: 14)).foregroundStyle(t.reachedWeek != nil ? Theme.gold : Theme.ivoryFaint)
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
            LedgerSection(title: "Trophies", trailing: {
                NavigationLink { AchievementsView() } label: { Text("All \(entries.count)  →").font(.system(size: 12)).foregroundStyle(Theme.gold) }.buttonStyle(.plain)
            }) {
                if got.isEmpty {
                    Text("Firsts and milestones show up here: the first customer, the first employee, the first million.").font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(got.prefix(3).enumerated()), id: \.element.id) { i, t in
                            if i > 0 { Hairline() }
                            ValueRow(label: t.name, value: t.reachedWeek.map { GameCalendar.dateString(week: $0) } ?? "").padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }
}
