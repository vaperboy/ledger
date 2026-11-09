import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// The president's desk: oxblood leather and old gold. The sitting president proposes rates and price support here; every proposal waits for
/// an administrator. Anyone else sees who holds the office and what is proposed, read only.
struct PresidentScreen: View {
    var e: GameEngine
    var r: CountryRead
    var back: () -> Void
    @EnvironmentObject var store: GameStore
    @State private var transfer: Double
    @State private var gains: Double
    @State private var supportTrade = ""
    @State private var supportPct = 0.05
    @State private var supportWeeks = 4.0
    @State private var budgetText = ""
    private let P: OutsidePalette = .oval

    init(e: GameEngine, r: CountryRead, back: @escaping () -> Void) {
        self.e = e
        self.r = r
        self.back = back
        _transfer = State(initialValue: r.gov.policy.transferTax)
        _gains = State(initialValue: r.gov.policy.gainsTax)
    }

    private var pol: GovPolicy { r.gov.policy }
    private var openPolicy: Bool { r.gov.pending.contains { $0.kind == .policy && $0.status == .open } }
    private var weeksToChange: Int {
        guard let last = pol.lastChangeWeek else { return 0 }
        return max(0, GovPolicy.changeGapWeeks - (r.week - last))
    }

    var body: some View {
        CivicPage(spacing: 18) {
            CivicHeader(title: "President's desk", subtitle: r.isPresident ? "You hold the office" : "Rates and price support", onBack: back)
            seat
            if r.isPresident {
                ratesDesk
                supportDesk
            }
            supports
            proposals
        }
        .outsideScreen(.oval)
        .onChange(of: r.gov.policy) { _, p in
            transfer = p.transferTax
            gains = p.gainsTax
        }
        .accessibilityIdentifier("country-president")
    }

    // MARK: The seat

    private var seat: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                GlyphView(glyph: Glyph.podium, size: 20, weight: 1.6, tint: P.accent)
                Text("The office").textStyle(.label)
            }
            if let o = r.gov.office {
                Text(r.shown(o.name, account: o.holder)).font(.system(size: 30, weight: .medium, design: .serif)).foregroundStyle(P.ink)
                Text("Term ends \(CivicWords.date(o.termEnd)), in \(CivicWords.weeks(max(0, o.termEnd - r.week)))").textStyle(.caption)
                if !o.promises.isEmpty {
                    Rectangle().fill(P.accent.opacity(0.4)).frame(height: 1)
                    Text("Promises").textStyle(.label)
                    ForEach(Array(o.promises.enumerated()), id: \.offset) { (_: Int, p: CampaignPromise) in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().strokeBorder(p.kept ? P.gain : P.lineStrong, lineWidth: 1.5)
                                if p.kept { GlyphView(glyph: Glyph.check, size: 12, weight: 2.4, tint: P.gain) }
                            }
                            .frame(width: 22, height: 22)
                            Text(CivicWords.promise(p, trades: tradeName)).textStyle(.body)
                            Spacer(minLength: 6)
                            Text(p.kept ? "Kept" : "Not yet").textStyle(.caption, tint: p.kept ? P.gain : P.inkFaint)
                        }
                    }
                }
            } else {
                Text("The office is vacant").font(.system(size: 26, weight: .medium, design: .serif)).foregroundStyle(P.ink)
                Text("When a president is in office, only they can propose rates and price support. See Election for the vote.")
                    .textStyle(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [P.card, P.cardDeep], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(P.accent.opacity(0.5), lineWidth: 1))
    }

    // MARK: Rates

    private var ratesDesk: some View {
        let tLow: Double = max(GovPolicy.transferRange.lowerBound, pol.transferTax - GovPolicy.step)
        let tHigh: Double = min(GovPolicy.transferRange.upperBound, pol.transferTax + GovPolicy.step)
        let gLow: Double = max(GovPolicy.gainsRange.lowerBound, pol.gainsTax - GovPolicy.step)
        let gHigh: Double = min(GovPolicy.gainsRange.upperBound, pol.gainsTax + GovPolicy.step)
        let changed: Bool = abs(transfer - pol.transferTax) > 1e-9 || abs(gains - pol.gainsTax) > 1e-9
        let blocked: String? = openPolicy ? "A rate change is already waiting for an administrator."
            : weeksToChange > 0 ? "Rates can change again in \(CivicWords.weeks(weeksToChange))."
            : changed ? nil : "Move a rate by one point to propose it."
        return desk("Propose new rates") {
            rateRow("Transfer tax", now: pol.transferTax, value: $transfer, range: tLow...tHigh)
            Rectangle().fill(P.hairline).frame(height: 1)
            rateRow("Gains tax", now: pol.gainsTax, value: $gains, range: gLow...gHigh)
            PrimaryAction(title: "Propose to the administrators", blockedReason: blocked, identifier: "president-propose-rates") { proposeRates() }
            Text("One point at a time, at most every \(GovPolicy.changeGapWeeks) weeks. Nothing changes until an administrator confirms.")
                .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func rateRow(_ title: String, now: Double, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.headline)
                Text("Now \(CivicWords.pct1(now))").textStyle(.caption)
            }
            Spacer(minLength: 8)
            CivicStepper(value: value, range: range, step: GovPolicy.step, format: CivicWords.pct1, tint: P.accent, ink: P.ink, fill: P.cardDeep)
        }
    }

    private func proposeRates() {
        let country: String = r.code
        let t: Double = transfer
        let g: Double = gains
        let ok: Bool = store.govRun { (s: inout GameState, _: GameData, _: FinanceContext) -> Void in
            try GovernmentBridge.act(&s, country: country) { (gov: inout Government, acct: String, wk: Int) -> Void in
                _ = try gov.proposePolicy(by: acct, transferTax: t, gainsTax: g, week: wk)
            }
        }
        if ok { Haptics.success(); store.outcome(chosen: "Proposed new rates", result: "Transfer tax \(CivicWords.pct1(t)), gains tax \(CivicWords.pct1(g)). They start when an administrator confirms.") }
    }

    // MARK: Price support

    private var supportDesk: some View {
        let trades: [Trade] = e.supportTrades()
        let maxBudget: Double = (r.gov.treasury.balance * GovPriceSupport.budgetShareOfTreasury).rounded(.down)
        let budget: Double? = CivicWords.number(budgetText)
        let open: Int = r.gov.supports.filter { $0.status == .proposed || $0.status == .active }.count
        let blocked: String? = supportTrade.isEmpty ? "Choose the trade to support."
            : open >= GovPriceSupport.maxOpen ? "At most \(GovPriceSupport.maxOpen) supports can be open at once."
            : budget == nil ? "Type the weekly budget."
            : (budget ?? 0) > maxBudget ? "The weekly budget may not exceed \(r.cur.tidyDisplay(maxBudget)), 5% of the treasury."
            : nil
        return desk("Propose price support") {
            Menu {
                ForEach(trades) { (t: Trade) in Button(t.name) { supportTrade = t.id } }
            } label: {
                HStack {
                    Text(trades.first { $0.id == supportTrade }?.name ?? "Choose a trade").textStyle(.body, tint: supportTrade.isEmpty ? P.inkFaint : P.ink)
                    Spacer(minLength: 8)
                    GlyphView(glyph: Glyph.chevronDown, size: 14, weight: 2, tint: P.inkFaint)
                }
                .padding(.horizontal, 12).frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(P.cardDeep))
            }
            HStack {
                Text("Share of sales added").textStyle(.body)
                Spacer(minLength: 8)
                CivicStepper(value: $supportPct, range: GovPriceSupport.percentRange, step: 0.01, format: CivicWords.pct, tint: P.accent, ink: P.ink, fill: P.cardDeep)
            }
            HStack {
                Text("Weeks it runs").textStyle(.body)
                Spacer(minLength: 8)
                CivicStepper(value: $supportWeeks, range: 1...Double(GovPriceSupport.maxWeeks), step: 1, format: { (v: Double) -> String in String(Int(v)) },
                             tint: P.accent, ink: P.ink, fill: P.cardDeep)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Weekly budget").textStyle(.body)
                CivicAmountField(text: $budgetText, symbol: r.cur.country.currencySymbol, ink: P.ink, soft: P.inkSoft, fill: P.cardDeep, edge: P.line)
                Text("Up to \(r.cur.tidyDisplay(maxBudget)) a week. The state pays out of the treasury, and no single account draws more than a quarter of it.")
                    .textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
            PrimaryAction(title: "Propose to the administrators", blockedReason: blocked, identifier: "president-propose-support") { proposeSupport(budget ?? 0) }
        }
    }

    private func proposeSupport(_ budget: Double) {
        let country: String = r.code
        let trade: String = supportTrade
        let pct: Double = supportPct
        let weeks: Int = Int(supportWeeks)
        let ok: Bool = store.govRun { (s: inout GameState, _: GameData, _: FinanceContext) -> Void in
            try GovernmentBridge.act(&s, country: country) { (gov: inout Government, acct: String, wk: Int) -> Void in
                _ = try gov.proposePriceSupport(by: acct, tradeID: trade, percent: pct, weeklyBudget: budget, weeks: weeks, week: wk)
            }
        }
        if ok {
            Haptics.success()
            budgetText = ""
            store.outcome(chosen: "Proposed price support", result: "\(tradeName(trade)): \(CivicWords.pct(pct)) of sales for \(CivicWords.weeks(weeks)). It starts when an administrator confirms.")
        }
    }

    // MARK: Lists

    private var supports: some View {
        let list: [GovPriceSupport] = r.gov.supports.reversed().filter { $0.status != .rejected }
        return desk("Price support") {
            if list.isEmpty {
                Text("No price support yet.").textStyle(.body)
            } else {
                ForEach(list) { (s: GovPriceSupport) in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tradeName(s.tradeID)).textStyle(.headline)
                            Text("\(CivicWords.pct(s.percent)) of sales, up to \(r.cur.tidyShort(s.weeklyBudget)) a week, \(CivicWords.weeks(s.weeks))")
                                .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
                            if s.status == .active || s.status == .ended { Text("Paid out so far: \(r.cur.tidyShort(s.spentTotal))").textStyle(.caption, tint: P.inkFaint) }
                        }
                        Spacer(minLength: 8)
                        CivicTag(text: supportStatus(s.status), tint: s.status == .active ? P.gain : s.status == .proposed ? P.caution : P.inkFaint)
                    }
                    if s.id != list.last?.id { Rectangle().fill(P.hairline).frame(height: 1) }
                }
            }
        }
    }

    private func supportStatus(_ s: GovPriceSupport.Status) -> String {
        switch s { case .proposed: return "Waiting"; case .active: return "Running"; case .ended: return "Ended"; case .rejected: return "Refused" }
    }

    private var proposals: some View {
        let list: [GovPending] = Array(r.gov.pending.filter { $0.kind == .policy || $0.kind == .priceSupport }.prefix(6))
        return desk("Proposals") {
            if list.isEmpty {
                Text("Nothing has been proposed.").textStyle(.body)
            } else {
                ForEach(list) { (p: GovPending) in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.summary).textStyle(.body).fixedSize(horizontal: false, vertical: true)
                            Text(CivicWords.date(p.week)).textStyle(.caption, tint: P.inkFaint)
                        }
                        Spacer(minLength: 8)
                        CivicTag(text: p.status == .open ? "Waiting" : p.status == .confirmed ? "Confirmed" : "Refused",
                                 tint: p.status == .open ? P.caution : p.status == .confirmed ? P.gain : P.loss)
                    }
                    if p.id != list.last?.id { Rectangle().fill(P.hairline).frame(height: 1) }
                }
            }
        }
    }

    private func tradeName(_ id: String) -> String { e.data.catalog.trades[id]?.name ?? id }

    private func desk<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).textStyle(.label)
            VStack(alignment: .leading, spacing: 14) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(P.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(P.line, lineWidth: 1))
        }
    }
}
