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
                                VStack(spacing: Theme.Space.l) { NetWorthCard(engine: e); EmpireCard(engine: e); SummaryRow(engine: e) }
                                VStack(spacing: Theme.Space.l) { SuggestionCard(engine: e); ComingUpCard(engine: e); FirstStepsCard(engine: e) }
                            }
                        } else {
                            NetWorthCard(engine: e)
                            SuggestionCard(engine: e)
                            EmpireCard(engine: e)
                            ComingUpCard(engine: e)
                            SummaryRow(engine: e)
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
        ScreenHeader(eyebrow: "Week \(engine.state.week + 1) · \(engine.date)", title: title) {
            HStack(spacing: 6) {
                Text(engine.homeCountry.flag)
                Text(engine.homeCountry.name).font(.label).foregroundStyle(Theme.ivoryMuted)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .liquidGlassCapsule()
        }
        .padding(.top, Theme.Space.s)
    }
    private var title: String {
        let name = engine.state.player.name
        return name.isEmpty ? "You" : name
    }
}

// MARK: Net worth

struct NetWorthCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine

    var body: some View {
        let nw = engine.netWorth
        let hist = engine.dayHistory
        let week = DayHistory.change(hist.netWorth, days: 7)
        let owed = nw.debt + nw.pendingTax
        let rise = week?.share ?? 0
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Net worth").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                HStack(alignment: .firstTextBaseline) {
                    Text(store.money(nw.total))
                        .font(.figure(34, weight: .bold))
                        .foregroundStyle(nw.total < 0 ? Theme.loss : Theme.ivory)
                        .minimumScaleFactor(0.55).lineLimit(1)
                    Spacer(minLength: 6)
                    if let week, abs(week.amount) > 0 {
                        Chip(text: weekText(week), tint: Theme.change(week.amount), symbol: week.amount >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    }
                }
                HStack(spacing: 8) {
                    if week != nil {
                        Chip(text: rise > 0.003 ? "Growing wealth" : rise < -0.003 ? "Losing ground" : "Holding steady",
                             tint: rise > 0.003 ? Theme.gain : rise < -0.003 ? Theme.loss : Theme.ivoryMuted,
                             symbol: rise > 0.003 ? "checkmark.seal.fill" : rise < -0.003 ? "arrow.down.right.circle.fill" : "equal.circle.fill")
                    }
                    Spacer()
                    if owed > 0 { Chip(text: "Debt " + store.short(owed), tint: Theme.loss) }
                }
                NetWorthChart(engine: engine)
            }
        }
    }
}

extension NetWorthCard {
    fileprivate func weekText(_ week: (amount: Double, share: Double?)) -> String {
        if let share = week.share { return String(format: "%+.1f%% (7d)", share * 100) }
        return (week.amount >= 0 ? "+" : "−") + store.short(abs(week.amount)) + " (7d)"
    }
}

// MARK: Summary tiles

/// Cash, investments and companies side by side in one card, each with its own small history.
struct SummaryRow: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var body: some View {
        let nw = engine.netWorth
        let h = engine.dayHistory
        Card(padding: 0) {
            HStack(spacing: 0) {
                SummaryTile(title: "Cash", value: store.short(nw.personal), series: h.cash, tint: Theme.gold)
                Divider().overlay(Theme.hairline)
                SummaryTile(title: "Investments", value: store.short(nw.investments), series: h.invested, tint: Theme.gain)
                Divider().overlay(Theme.hairline)
                SummaryTile(title: "In companies", value: store.short(nw.companies), series: h.companies, tint: Theme.gold)
            }
        }
    }
}

struct SummaryTile: View {
    @EnvironmentObject var store: GameStore
    var title: String
    var value: String
    var series: [Double]
    var tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
            Text(value).font(.figure(17, weight: .bold)).foregroundStyle(Theme.ivory).minimumScaleFactor(0.6).lineLimit(1)
            Sparkline(values: series, tint: tint).frame(height: 26)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Your companies

/// The companies at a glance, best earners first: health, profit and cash on one line each; a tap opens the company.
struct EmpireCard: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var body: some View {
        let cos = engine.state.liveCompanies.filter { $0.type != "hold" }
        if !cos.isEmpty {
            let rows = cos.map { (co: $0, h: engine.companyHealth($0)) }.sorted { $0.h.profitTTM > $1.h.profitTTM }
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Your companies").font(.bodyText.weight(.semibold))
                        Spacer()
                        Text("Profit 12 mo · Cash").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                    }
                    ForEach(rows.prefix(4), id: \.co.id) { r in
                        Button { store.go(.openCompany(r.co.id)) } label: {
                            HStack(spacing: 10) {
                                Circle().fill(HealthChip.tint(r.h.label)).frame(width: 7, height: 7)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.co.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ivory).lineLimit(1)
                                    Text(r.h.label + (r.h.bottleneck.map { " · limited by " + $0.lowercased() } ?? "")).font(.caption2).foregroundStyle(Theme.ivoryFaint).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(store.short(r.h.profitTTM, in: r.co)).font(.subheadline.monospacedDigit()).foregroundStyle(r.h.profitTTM < 0 ? Theme.loss : Theme.ivory)
                                Text(store.short(r.co.cash, in: r.co)).font(.caption.monospacedDigit()).foregroundStyle(r.co.cash < 0 ? Theme.loss : Theme.ivoryMuted).frame(minWidth: 56, alignment: .trailing)
                            }
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if rows.count > 4 {
                        Button { store.tab = .companies } label: { Text("All \(rows.count) companies").font(.caption.weight(.semibold)).foregroundStyle(Theme.gold) }.buttonStyle(.plain)
                    }
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
                    Text(store.isAdvancing ? "Stop" : engine.state.isGameOver ? "Game over" : "Next day  ›")
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(engine.state.isGameOver)
                Button { store.untilNeeded() } label: { Image(systemName: "forward.fill") }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(store.isAdvancing || engine.state.isGameOver)
                    .accessibilityLabel("Skip ahead until something needs you")
            }
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
        .liquidGlass(cornerRadius: 28)
        .padding(.horizontal, Theme.Space.m).padding(.bottom, Theme.Space.s)
    }
}
