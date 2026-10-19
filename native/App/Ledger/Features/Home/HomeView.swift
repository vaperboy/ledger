import SwiftUI
import Simulation
import Finance
import Businesses

struct HomeView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            if let e = store.engine {
                ScrollView {
                    VStack(spacing: Theme.Space.l) {
                        HomeHeader(engine: e)
                        if sizeClass == .regular {
                            HStack(alignment: .top, spacing: Theme.Space.l) {
                                VStack(spacing: Theme.Space.l) { NetWorthCard(engine: e); SummaryRow(engine: e) }
                                VStack(spacing: Theme.Space.l) { SuggestionCard(engine: e); ComingUpCard(engine: e); FirstStepsCard(engine: e) }
                            }
                        } else {
                            NetWorthCard(engine: e)
                            SuggestionCard(engine: e)
                            SummaryRow(engine: e)
                            ComingUpCard(engine: e)
                            FirstStepsCard(engine: e)
                        }
                    }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.top, Theme.Space.s)
                    .padding(.bottom, 120)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .ledgerBackground()
                .safeAreaInset(edge: .bottom, spacing: 0) { AdvanceBar(engine: e) }
                .navigationBarHidden(true)
            }
        }
    }
}

// MARK: Header

struct HomeHeader: View {
    var engine: GameEngine
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.system(.title2, design: .serif).weight(.semibold)).foregroundStyle(Theme.ivory)
                Text("\(engine.date) · Week \(engine.state.week + 1)").font(.label).foregroundStyle(Theme.ivoryMuted)
            }
            Spacer()
            HStack(spacing: 6) {
                Text(engine.homeCountry.flag)
                Text(engine.homeCountry.name).font(.label).foregroundStyle(Theme.ivoryMuted)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Theme.leather.opacity(0.8)))
        }
        .padding(.top, Theme.Space.s)
    }
    private var greeting: String {
        let name = engine.state.player.name
        return name.isEmpty ? "Welcome" : "Good day, \(name)"
    }
}

// MARK: Net worth

struct NetWorthCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let nw = engine.netWorth
        let hist = engine.dayHistory
        let day = DayHistory.change(hist.netWorth, days: 1)
        let week = DayHistory.change(hist.netWorth, days: 7)
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionLabel("Net worth")
                Text(store.money(nw.total))
                    .font(.figure(40, weight: .semibold))
                    .foregroundStyle(nw.total < 0 ? Theme.loss : Theme.ivory)
                    .minimumScaleFactor(0.6).lineLimit(1)
                HStack(spacing: 8) {
                    if let day { DeltaPill(title: "Today", amount: day.amount, share: day.share, format: store.short) }
                    if let week { DeltaPill(title: "Week", amount: week.amount, share: week.share, format: store.short) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Sparkline(values: hist.netWorth, tint: Theme.gold).frame(height: 56)
                Divider().overlay(Theme.hairline)
                DebtBreakdown(nw: nw)
            }
        }
    }
}

/// Assets, debts and the result, always from the same `NetWorth` parts as the big figure, so they cannot disagree.
struct DebtBreakdown: View {
    @EnvironmentObject var store: GameStore
    var nw: NetWorth
    var body: some View {
        let owed = nw.debt + nw.pendingTax
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Stat(label: "Assets", value: store.short(nw.totalAssets))
                Spacer()
                Stat(label: nw.pendingTax > 0 ? "Debt and tax" : "Debt", value: owed > 0 ? "−" + store.short(owed) : store.short(0), tint: owed > 0 ? Theme.loss : Theme.ivoryMuted)
                Spacer()
                Stat(label: "Net", value: store.short(nw.total), tint: nw.total < 0 ? Theme.loss : Theme.ivory)
            }
            if nw.totalAssets > 0 {
                let share = min(1, owed / nw.totalAssets)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hairline)
                        Capsule().fill(share > 0.7 ? Theme.loss : share > 0.4 ? Theme.caution : Theme.roseGold).frame(width: max(4, g.size.width * share))
                    }
                }
                .frame(height: 5)
                Text(owed > 0 ? "Debt is \(Int((owed / nw.totalAssets * 100).rounded()))% of what you own" : "No debt")
                    .font(.label).foregroundStyle(Theme.ivoryFaint)
            } else if owed > 0 {
                Text("You owe more than you own right now").font(.label).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }
}

// MARK: Summary tiles

struct SummaryRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var body: some View {
        let nw = engine.netWorth
        let h = engine.dayHistory
        HStack(spacing: Theme.Space.m) {
            SummaryTile(title: "Cash", value: store.short(nw.personal), series: h.cash, change: DayHistory.change(h.cash, days: 7))
            SummaryTile(title: "Invested", value: store.short(nw.investments), series: h.invested, change: DayHistory.change(h.invested, days: 7))
            SummaryTile(title: "Companies", value: store.short(nw.companies), series: h.companies, change: DayHistory.change(h.companies, days: 7))
        }
    }
}

struct SummaryTile: View {
    @EnvironmentObject var store: GameStore
    var title: String
    var value: String
    var series: [Double]
    var change: (amount: Double, share: Double?)?
    var body: some View {
        Card(padding: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title)
                Text(value).font(.figure(18)).foregroundStyle(Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
                Sparkline(values: series, tint: Theme.change(change?.amount ?? 0) == Theme.ivoryMuted ? Theme.gold : Theme.change(change?.amount ?? 0)).frame(height: 28)
                if let change {
                    Text((change.amount >= 0 ? "▲ " : "▼ ") + store.short(abs(change.amount)) + " wk")
                        .font(.caption2.weight(.semibold)).foregroundStyle(Theme.change(change.amount))
                } else {
                    Text("—").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }
}

// MARK: Next day

struct AdvanceBar: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { d in
                    Capsule().fill(d <= engine.state.day ? Theme.gold : Theme.hairline).frame(height: 3)
                }
            }
            HStack(spacing: Theme.Space.m) {
                Button { store.isAdvancing ? store.stopAdvancing() : store.nextDay() } label: {
                    Text(store.isAdvancing ? "Stop" : engine.state.isGameOver ? "Game over" : "Next day")
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(engine.state.isGameOver)
                Button { store.untilNeeded() } label: { Image(systemName: "forward.fill") }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(store.isAdvancing || engine.state.isGameOver)
                    .accessibilityLabel("Skip ahead until something needs you")
            }
        }
        .padding(.horizontal, Theme.Space.l).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.s)
        .background(.ultraThinMaterial.opacity(0.9))
        .background(Theme.walnut.opacity(0.7))
    }
}
