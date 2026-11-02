import SwiftUI
import Charts
import GameCore
import Businesses
import Countries
import Simulation

/// The one Pricing screen of a company (a normal pushed screen under Sales): your price and margin against the rivals, a percentage change,
/// a discount campaign, a price war and "hold my prices". It replaces the -3...+3 price sheet and the Market > Pricing page.
///
/// Why it is quick: the engine reads (`priceMoves`, `rivalRows`) are made once per screen, not on every slider tick. The slider, its
/// forecast (a small simulation in the engine) and the discount choices live in cards of their own, so dragging the slider only redraws
/// that card, and the forecast is worked out once the slider has rested for a moment instead of at every step.
struct CompanyPricing: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var showWar = false

    var body: some View {
        content
            .centerSheet(isPresented: $showWar) { PriceWarSheet(engine: engine, companyID: company.id) }
    }

    @ViewBuilder private var content: some View {
        if let info = engine.priceMoves(company) {
            let cur: Currency = engine.currency(for: company)
            let hasRivals: Bool = !engine.rivalRows(company).isEmpty
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                summaryCard(info, cur)
                if let war = info.war {
                    warCard(weeksLeft: war.weeksLeft, loss: war.loss, cur)
                } else {
                    PriceChangeCard(companyID: company.id, yourTicket: info.yourTicket, currency: cur, recentCut: info.recentCut,
                                    unit: engine.tradeInfo(companyID: company.id)?.unit ?? "sale", isStore: engine.tradeInfo(companyID: company.id)?.family == "retail")
                    DiscountCard(companyID: company.id, info: info, currency: cur)
                    if hasRivals { priceWarCard }
                }
            }
        } else {
            Card(padding: 12, radius: Theme.Radius.row) {
                Text("Prices can be moved once the business is open and selling.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Your price and margin, the rivals

    private struct PriceBar: Identifiable { var id: String; var name: String; var value: Double; var text: String; var mine: Bool }

    private func summaryCard(_ info: PriceMovesInfo, _ cur: Currency) -> some View {
        let marginText: String = info.margin.map { String(format: "%.0f%%", $0 * 100) } ?? "\u{2013}"
        let items: [KeyFigures.Item] = [
            .init(label: "Your price", value: cur.tidyShort(info.yourTicket), sub: String(format: "%+.0f%% vs market", info.againstMarket * 100)),
            .init(label: "Margin", value: marginText, tint: (info.margin ?? 0) < 0 ? Theme.loss : Theme.ivory),
        ]
        return Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                FigureStrip(items: items, columns: 2)
                rivalsBar(info, cur)
            }
        }
    }

    @ViewBuilder private func rivalsBar(_ info: PriceMovesInfo, _ cur: Currency) -> some View {
        if let avg = info.rivalsAverage {
            let bars: [PriceBar] = [
                PriceBar(id: "me", name: "You", value: info.yourTicket, text: cur.tidyShort(info.yourTicket), mine: true),
                PriceBar(id: "rv", name: "Rivals", value: avg, text: cur.tidyShort(avg), mine: false),
            ]
            Chart(bars) { (b: PriceBar) in
                BarMark(x: .value("Price", b.value), y: .value("Who", b.name), height: .fixed(14))
                    .foregroundStyle(b.mine ? Theme.gold : Theme.ivoryDim).cornerRadius(3)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(b.text).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(b.mine ? Theme.gold : Theme.ivoryMuted)
                    }
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .leading) { (_: AxisValue) in AxisValueLabel().font(.system(size: 11)).foregroundStyle(Theme.ivoryMuted) } }
            .chartXScale(range: .plotDimension(endPadding: 64))
            .frame(height: 76)
        } else {
            Text("No rival prices known yet.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    // MARK: Price war

    private var priceWarCard: some View {
        PricingCard(glyph: Glyph.warning, title: "Price war") {
            Text("Undercut a rival on purpose. It costs revenue while it runs and they may answer.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint)
            Button("Start a price war\u{2026}") { showWar = true }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted))
        }
    }

    private func warCard(weeksLeft: Int, loss: Double, _ cur: Currency) -> some View {
        PricingCard(glyph: Glyph.warning, title: "Price war on") {
            Text("\(weeksLeft) wk left \u{00B7} \(cur.tidyShort(loss)) of revenue given up").font(.system(size: 13)).foregroundStyle(Theme.caution)
            Button("End the price war now") {
                store.act { $0.endPriceWar(companyID: company.id) }
                Haptics.tap()
                store.show("The price war is over. Prices go back to normal.", tone: "n")
            }.buttonStyle(TinyButtonStyle(tint: Theme.loss))
        }
    }
}

/// A bordered card with a round icon and a title, the shape of every action on the Pricing screen.
private struct PricingCard<Inner: View>: View {
    var glyph: String
    var title: String
    @ViewBuilder var inner: () -> Inner

    var body: some View {
        EntityCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    IconCircle(glyph: glyph, size: 30)
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory)
                    Spacer()
                }
                inner()
            }
        }
    }
}

// MARK: Change price

/// "Change price": a percentage slider with the engine's forecast under it. The forecast is a small simulation, so it runs once the
/// slider has rested for a quarter of a second (and a drag that moves on cancels the pending one), never on every step.
private struct PriceChangeCard: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var yourTicket: Double
    var currency: Currency
    var recentCut: Double
    var unit: String = "sale"
    /// A shop sells many different things: it sets one percentage on all its items instead of one price (owner decision, 2 Nov).
    var isStore = false
    @State private var typed = ""
    @State private var change = 0.05
    @State private var forecast: ForecastLine?

    struct ForecastLine: Equatable {
        var customers: String
        var margin: String
        var byAnalyst: Bool
    }

    var body: some View {
        let tiny: Bool = abs(change) < 0.005
        let label: String = tiny ? "Pick a change" : String(format: "Set %+.0f%% \u{00B7} %@", change * 100, currency.tidyShort(yourTicket * (1 + change)))
        return PricingCard(glyph: Glyph.invest, title: isStore ? "Markup on all items" : "Change price") {
            typedField
            HStack {
                Slider(value: $change, in: -0.2...0.2, step: 0.01).tint(Theme.gold)
                Text(String(format: "%+.0f%%", change * 100)).font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.ivory).frame(width: 48, alignment: .trailing)
            }
            Button(label) { apply() }.buttonStyle(TinyButtonStyle()).disabled(tiny)
            forecastView(tiny)
            if recentCut >= 0.06 { Text("You cut prices lately. Rivals may match you.").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }
            HoldPricesRow(companyID: companyID)
        }
        .task(id: Int((change * 100).rounded())) { @MainActor in
            if abs(change) < 0.005 { forecast = nil; return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            guard let e = store.engine, let fc = e.priceForecast(companyID: companyID, byShare: change) else { forecast = nil; return }
            forecast = ForecastLine(customers: fc.text.customers, margin: fc.text.margin, byAnalyst: fc.text.byAnalyst)
        }
    }

    /// Type the price you want per unit; the slider below is the same move in percent. The engine keeps it inside the market's range.
    @ViewBuilder private var typedField: some View {
        if !isStore, yourTicket > 0 {
            HStack {
                Text("Price per \(unit), now " + currency.tidyShort(yourTicket)).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted)
                Spacer(minLength: 8)
                TextField("New price", text: $typed).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    .font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.ivory)
                Button("Set") { applyTyped() }.buttonStyle(TinyButtonStyle()).disabled(typedShare == nil)
            }
        }
    }

    private var typedShare: Double? {
        let v: Double? = Double(typed.replacingOccurrences(of: ",", with: "."))
        guard let p = v, p > 0, yourTicket > 0, abs(p / yourTicket - 1) >= 0.005 else { return nil }
        return p / yourTicket - 1
    }

    private func applyTyped() {
        guard let share = typedShare else { return }
        if let real = store.act({ $0.changePrice(companyID: companyID, byShare: share) }) ?? nil {
            Haptics.success()
            store.show(String(format: "Prices %+.1f%%. The market keeps prices within its range.", real * 100), tone: "good")
            typed = ""
        } else {
            Haptics.warning()
            store.show("The price could not be changed.", tone: "warn")
        }
    }

    @ViewBuilder private func forecastView(_ tiny: Bool) -> some View {
        if !tiny, let f = forecast {
            HStack {
                Text("Customers: " + f.customers)
                Spacer()
                Text("Margin: " + f.margin)
            }.font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
            Text(f.byAnalyst ? "Ranges from your data analyst." : "A gut feeling. A data analyst in your office gives ranges.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
        }
    }

    /// A price change is routine and reversible (change it again), so it runs at once; the forecast above the button is the consequence.
    private func apply() {
        let share: Double = change
        if let real = store.act({ $0.changePrice(companyID: companyID, byShare: share) }) ?? nil {
            Haptics.success()
            store.show(String(format: "Prices %+.0f%%.", real * 100), tone: "good")
        } else {
            Haptics.warning()
            store.show("The price could not be changed.", tone: "warn")
        }
    }
}

// MARK: Hold my prices

/// "Hold my prices": prices stay where they were set while the market inflates, so customers see the company as cheaper over time.
/// Switching it off lets prices follow the market again and drops the edge built up so far (the engine resets it).
private struct HoldPricesRow: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var pending: PendingAction?

    var body: some View {
        let co: Company? = store.engine?.state.company(companyID)
        let held: Bool = co?.flag("inflHold") ?? false
        let edge: Double = max(0, ((co?.num("ig", 1) ?? 1) - 1) * 100)
        return VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { held }, set: { v in set(v, edge: edge) })) {
                Text("Hold my prices").font(.system(size: 13.5)).foregroundStyle(Theme.ivory)
            }.tint(Theme.gold)
            if held && edge >= 0.5 {
                Text("Customers now see you about \(Int(edge.rounded()))% cheaper than if prices had followed inflation.").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }
        }
        .confirmAction($pending)
    }

    private func set(_ on: Bool, edge: Double) {
        let id: Int = companyID
        let name: String = store.engine?.state.company(companyID)?.name ?? "The company"
        let apply = {
            guard store.act({ $0.setInflationHold(companyID: id, hold: on) }) != nil else { store.show("Could not change the price setting.", tone: "warn"); return }
            store.show(on ? "\(name) now holds its prices." : "\(name)'s prices follow inflation again.", tone: "n")
        }
        if !on && edge >= 0.5 {
            pending = PendingAction(title: "Let prices follow inflation?", message: "The edge built up while holding (about \(Int(edge.rounded()))% cheaper in customers' eyes) is dropped at once.", button: "Let go", destructive: true, run: apply)
        } else {
            apply()
        }
    }
}

// MARK: Discount campaign

/// "Discount campaign": choose a depth and a length, or see the one that runs. Its choices are its own state, so changing them does not
/// redraw the rest of the screen.
private struct DiscountCard: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var info: PriceMovesInfo
    var currency: Currency
    @State private var discount = 15
    @State private var weeks = 2

    var body: some View {
        PricingCard(glyph: Glyph.reports, title: "Discount campaign") {
            if info.discountOptions.isEmpty {
                Text("Not done in this trade.").font(.system(size: 12)).foregroundStyle(Theme.ivoryFaint)
            } else if let pct = info.discountPercent {
                running(pct)
            } else {
                choices
            }
        }
    }

    private func running(_ pct: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(pct)% off \u{00B7} \(info.discountWeeksLeft) wk left").font(.system(size: 13)).foregroundStyle(Theme.ivory)
            Button("End the discount") {
                store.act { $0.endDiscount(companyID: companyID) }
                store.show("The discount has ended.", tone: "n")
            }.buttonStyle(TinyButtonStyle(tint: Theme.ivoryMuted))
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 8) {
            WrapRow {
                Group {
                    ForEach(info.discountOptions, id: \.self) { (d: Int) in
                        Button("\(d)%") { discount = d }.buttonStyle(TinyButtonStyle(tint: discount == d ? Theme.gold : Theme.ivoryFaint))
                    }
                    ForEach([1, 2, 4, 6], id: \.self) { (w: Int) in
                        Button("\(w) wk") { weeks = w }.buttonStyle(TinyButtonStyle(tint: weeks == w ? Theme.gold : Theme.ivoryFaint))
                    }
                }
            }
            if info.raisedWeeksAgo > 0 {
                Text("You raised prices \(info.raisedWeeksAgo) wk ago. A sale measured against that price can be fined as misleading.").font(.system(size: 11.5)).foregroundStyle(Theme.caution)
            }
            Button("Start \(discount)% off for \(weeks) wk") { start() }.buttonStyle(TinyButtonStyle())
        }
    }

    /// A discount can be ended any time, so it starts at once; the note above the button says what it does to the margin.
    private func start() {
        let pct: Int = min(discount, info.discountOptions.last ?? discount)
        let wk: Int = weeks
        let r = store.act { $0.startDiscount(companyID: companyID, percent: pct, weeks: wk) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why, tone: "warn") }
        else if r != nil { Haptics.success(); store.show("\(pct)% off for \(wk) week\(wk == 1 ? "" : "s").", tone: "good") }
    }
}
