import SwiftUI
import GameCore
import Events
import Simulation

/// The Rich list phone app, drawn as a leaderboard: a podium for the top three with big serif ranks, then ranked rows with net worth,
/// your row highlighted and pinned at the bottom of the screen. The engine gives the movement only for you (rank since last month), so
/// other rows show their source of wealth instead of a made-up change. Below the list: the yearly business awards.
/// Original: RICH57.page and V.awards56.
struct RichListView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine {
            let st = RichList.standing(e.state, data: e.data, context: e.context)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header(e, st)
                    podium(st)
                    ladder(st)
                    if let r = st.rank, r > 100 {
                        NoteCard(text: "Number 100 has \(store.short(st.hundredth)). \(store.short(max(0, st.hundredth - st.netWorth))) to go.", glyph: Glyph.richList)
                    } else if st.rank == nil {
                        NoteCard(text: "You need a positive net worth to be placed on the list.", glyph: Glyph.richList)
                    }
                    awards(e.state)
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 24)
                .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .outsideScreen()
            .safeAreaInset(edge: .bottom, spacing: 0) { pinned(e, st) }
            .accessibilityIdentifier("richlist-app")
        }
    }

    // MARK: Header and podium

    private func header(_ e: GameEngine, _ st: RichList.Standing) -> some View {
        HStack(spacing: 12) {
            OutsideBack()
            VStack(alignment: .leading, spacing: 1) {
                Text("The Rich List").font(.serifTitle(28)).foregroundStyle(Theme.ivory).accessibilityAddTraits(.isHeader)
                Text("The richest people of \(e.homeCountry.name)").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private func podium(_ st: RichList.Standing) -> some View {
        let top: [RichList.Person] = st.top.sorted { $0.rank < $1.rank }
        let first: RichList.Person? = top.first(where: { $0.rank == 1 })
        let second: RichList.Person? = top.first(where: { $0.rank == 2 })
        let third: RichList.Person? = top.first(where: { $0.rank == 3 })
        return HStack(alignment: .bottom, spacing: 8) {
            step(second, height: 118)
            step(first, height: 150)
            step(third, height: 96)
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func step(_ p: RichList.Person?, height: CGFloat) -> some View {
        if let p {
            VStack(spacing: 4) {
                Text("\(p.rank)").font(.serifTitle(p.rank == 1 ? 54 : 40)).foregroundStyle(p.rank == 1 ? Theme.gold : Theme.ivory)
                Text(p.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.isYou ? Theme.gold : Theme.ivory)
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                Text(store.short(max(0, p.wealth))).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.ivoryMuted)
                Text(p.isYou ? "You" : p.source).font(.system(size: 10.5)).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
            }
            .padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .top)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(p.rank == 1 ? Theme.goldWash : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(p.rank == 1 ? Theme.gold : Theme.border, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Number \(p.rank), \(p.name), \(store.short(max(0, p.wealth)))")
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: height)
        }
    }

    // MARK: Ranked rows

    private func ladder(_ st: RichList.Standing) -> some View {
        let head: [RichList.Person] = st.top.sorted { $0.rank < $1.rank }.filter { $0.rank > 3 }
        let shown: Set<Int> = Set(st.top.map { $0.rank })
        let near: [RichList.Person] = st.around.filter { !shown.contains($0.rank) }
        let gap: Bool = !near.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(head) { (p: RichList.Person) in
                row(p, st)
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            if gap {
                Text(st.rank.map { $0 <= 100 ? "AROUND YOU" : "THE WAY IN" } ?? "THE WAY IN")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(Theme.ivoryFaint).padding(.vertical, 10)
                ForEach(near) { (p: RichList.Person) in
                    row(p, st)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
            }
        }
    }

    private func row(_ p: RichList.Person, _ st: RichList.Standing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(p.isYou && p.rank == 0 ? "·" : "\(p.rank)").font(.serifTitle(20)).monospacedDigit()
                .foregroundStyle(p.isYou ? Theme.gold : Theme.ivoryMuted).frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.name).font(.system(size: 14.5, weight: p.isYou ? .semibold : .regular)).foregroundStyle(p.isYou ? Theme.gold : Theme.ivory)
                Text(p.isYou ? "You" + movementWords(st) : p.source).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            }
            Spacer(minLength: 8)
            Text(store.short(max(0, p.wealth))).font(.system(size: 14.5).monospacedDigit()).foregroundStyle(Theme.ivory)
        }
        .padding(.vertical, 10).padding(.horizontal, p.isYou ? 10 : 0)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(p.isYou ? Theme.goldWash : Color.clear))
        .accessibilityElement(children: .combine)
    }

    // MARK: Your row, pinned

    private func movementWords(_ st: RichList.Standing) -> String {
        guard let r = st.rank, let p = st.previous, p != r else { return "" }
        return p > r ? " · ▲ up \(p - r) since last month" : " · ▼ down \(r - p) since last month"
    }

    private func pinned(_ e: GameEngine, _ st: RichList.Standing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(st.rank.map { "#\($0.formatted())" } ?? "–").font(.serifTitle(26)).foregroundStyle(st.rank == nil ? Theme.ivoryMuted : Theme.gold)
                .frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.state.player.name).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.ivory).lineLimit(1)
                Text((st.rank == nil ? "Not placed" : "You") + movementWords(st) + (st.best.map { " · best #\($0)" } ?? ""))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(store.short(max(0, st.netWorth))).font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.ivory)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Theme.surface)
        .overlay(alignment: .top) { Rectangle().fill(Theme.gold.opacity(0.6)).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("richlist-you")
    }

    // MARK: Awards

    @ViewBuilder private func awards(_ s: GameState) -> some View {
        let years = Awards.years(s).reversed()
        CardSection(title: "Business awards", trailing: { Text("\(Awards.wonCount(s)) won").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint) }) {
            if years.isEmpty {
                Text("The first business awards are held at the end of the year, once you have been in business for half a year.").font(.system(size: 13)).foregroundStyle(Theme.ivoryMuted)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(Array(years.prefix(4)), id: \.year) { y in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(y.year)").capsLabel(Theme.ivoryFaint).padding(.bottom, 4)
                            ForEach(Array(y.results.enumerated()), id: \.offset) { i, r in
                                if i > 0 { CardLine() }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(Awards.name(r.kind)).font(.system(size: 14.5)).foregroundStyle(r.won ? Theme.gold : Theme.ivory)
                                        Spacer()
                                        Text(r.won ? "Won" : "Not this time").font(.caption).foregroundStyle(r.won ? Theme.gain : Theme.ivoryFaint)
                                    }
                                    Text(r.won ? "\(r.company): \(r.why)" : "Won by \(r.other). You were in the running.").font(.caption).foregroundStyle(Theme.ivoryFaint)
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
    }
}
