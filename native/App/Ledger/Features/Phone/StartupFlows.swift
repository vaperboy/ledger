import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

/// Shared by the four startup popups: dismissing and the one question every action asks first, "If you do this, this will happen".
private struct StartupPopup {
    /// The popup that asks before anything is done: what it costs, what you own afterwards, the lock-up, the tax and what happens if the startup fails.
    static func ask(title: String, lines: [String], button: String, risk: String, run: @escaping () -> Void) -> PendingAction {
        PendingAction(title: title, message: (["If you do this, this will happen:"] + lines.map { "\u{2022} " + $0 }).joined(separator: "\n"), button: button,
                      alwaysAsk: true, risk: risk, tone: .investment, icon: "chart.pie", run: run)
    }
}

// MARK: Founding

/// Open a startup that other players can fund. The cost comes first: the entry cost, the founder's own money and the registration.
struct FoundCrowdStartupSheet: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market = StartupMarketStore.shared
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    @State private var sectorID = StartupProducts.sectors.first?.id ?? ""
    @State private var seed = 1.0
    @State private var factor = 3.0
    @State private var pitch = ""
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let sec = StartupProducts.sector(sectorID) { content(e, sec) }
        }
        .confirmAction($pending)
        .centerSheetTitle("Open a startup")
    }

    @ViewBuilder private func content(_ e: GameEngine, _ sec: StartupProducts.Sector) -> some View {
        let cur: Currency = e.homeCurrency
        let weeks: Int = StartupMarketStore.accountWeeks(e)
        let quote: CrowdStartups.FoundQuote? = CrowdStartups.foundQuote(e.state, sector: sec.id, who: "c2", seedMultiple: seed, planFactor: factor, context: e.context)
        VStack(alignment: .leading, spacing: PopupSpace.card) {
            if let q = quote {
                CardSection("What it costs first") {
                    VStack(alignment: .leading, spacing: PopupSpace.row) {
                        PopupRow(label: "Entry cost (not refunded)", value: cur.tidyShort(q.entryCost))
                        PopupRow(label: "Your own money into the startup", value: cur.tidyShort(q.founderPutIn))
                        PopupRow(label: "Registration", value: cur.tidyShort(q.registration))
                        PopupRow(label: "Leaves your cash now", value: cur.tidyShort(q.total))
                        Text("Opening a startup costs far more than opening a normal company, so it cannot be done for free. You must put in at least a third of the plan yourself.").popupText(.caption)
                    }
                }
            }
            CardSection("Sector") {
                Picker("Sector", selection: $sectorID) { ForEach(StartupProducts.sectors) { (s: StartupProducts.Sector) in Text(s.name).tag(s.id) } }.pickerStyle(.menu)
                SegmentedPill(items: [1.0, 2.0, 4.0], title: { (v: Double) -> String in v == 1.0 ? "Lean" : v == 2.0 ? "Double" : "Four times" }, selection: $seed)
            }
            CardSection("How big the plan is") {
                SegmentedPill(items: CrowdStartupRules.planFactors, title: { (v: Double) -> String in v == 3.0 ? "You fund a third" : v == 2.0 ? "You fund half" : "You fund two thirds" }, selection: $factor)
                if let q = quote {
                    PopupRow(label: "Plan cost", value: cur.tidyShort(q.plan.cost))
                    PopupRow(label: "Investors are asked for", value: cur.tidyShort(q.plan.investorTarget))
                    Text("Raised in three stages: " + CrowdStartupRules.stageNames.joined(separator: ", ").lowercased() + ". Each stage is released from escrow when its milestone is reached. The price of shares comes from a fixed rule, not from you.").popupText(.caption)
                }
            }
            if let q = quote {
                let enough: Bool = Payments.liquid(e.state) >= q.total
                let gate: CrowdStartupRules.FoundGate = CrowdStartupRules.foundGate(accountWeeks: weeks, level: PlayerLevel.info(e.state).level)
                let blocked: String? = !gate.allowed ? gate.reasons.joined(separator: " ") : (enough ? nil : "You need \(cur.tidyShort(q.total - Payments.liquid(e.state))) more in cash.")
                if let b = blocked { Text(b).popupText(.risk) }
                Button("Open it for \(cur.tidyShort(q.total))") { ask(e, sec, q, cur) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true)).disabled(blocked != nil).accessibilityIdentifier("startup-found-go")
            }
        }
    }

    private func ask(_ e: GameEngine, _ sec: StartupProducts.Sector, _ q: CrowdStartups.FoundQuote, _ cur: Currency) {
        let product: String = sec.products.first?.id ?? ""
        let model: String = sec.models.first?.id ?? ""
        let sid = sec.id, seedNow = seed, factorNow = factor
        pending = StartupPopup.ask(title: "Open a \(sec.name) startup?", lines: [
            "\(cur.tidyDisplay(q.total)) leaves your cash now; \(cur.tidyShort(q.entryCost)) of it is the entry cost and is gone for good.",
            "Investors are asked for \(cur.tidyShort(q.plan.investorTarget)) in three stages, held in escrow until the milestones; their shares make yours smaller.",
            "Shares are priced by a fixed rule; you cannot name the price.",
            "If the startup fails, the money already released is lost and escrow goes back to the investors.",
            "Only accounts at least \(CrowdStartupRules.minAccountWeeks) game weeks old and at player level \(CrowdStartupRules.minFounderLevel) can open one.",
        ], button: "Open it for \(cur.tidyShort(q.total))", risk: "Most startups fail and your own money is lost.") {
            let weeks: Int = StartupMarketStore.accountWeeks(e)
            let today: Int = StartupMarketStore.today(e)
            var out: CrowdStartups.FoundOutcome?
            _ = store.act { (eng: inout GameEngine) -> Bool in
                eng.update { s, d, c in
                    out = CrowdStartups.found(&s, name: nil, sector: sid, product: product, model: model, who: "c2", seedMultiple: seedNow, planFactor: factorNow,
                                              pitch: pitch, accountWeeks: weeks, level: PlayerLevel.info(s).level, today: today, data: d, context: c)
                }
                return true
            }
            switch out {
            case .ok(let st)?:
                market.service.list(st)
                Haptics.success()
                store.tell("\(st.name) is open", "Your startup is listed. Investors can fund \(CrowdStartupRules.stageNames[0].lowercased()) now; the money is released when it opens.", tone: "good")
                dismiss()
            case .refused(let why)?:
                store.tell("Not opened", why, tone: "warn")
            case nil:
                break
            }
        }
    }
}

// MARK: Investing

/// Put money into the open stage of a startup. The price is the rule's; the popup before confirming states the cost, the share, the lock-up and the risk.
struct InvestStartupSheet: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market = StartupMarketStore.shared
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var startupID: String
    @State private var amount = 0.0
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let st = market.service.startup(startupID) { content(e, st) } else { Text("This startup is gone.").popupText(.body) }
        }
        .confirmAction($pending)
        .centerSheetTitle("Invest")
    }

    @ViewBuilder private func content(_ e: GameEngine, _ st: CrowdStartup) -> some View {
        let cur: Currency = e.homeCurrency
        let today: Int = StartupMarketStore.today(e)
        let weeks: Int = StartupMarketStore.accountWeeks(e)
        let keys: Set<String> = market.service.myLinkKeys
        let stage: Int = st.openStage ?? 0
        let room: Double = CrowdStartupRules.stageTarget(st.plan, stage: stage) - st.raised(stage: stage)
        let mineRoom: Double = CrowdStartupRules.perInvestorCap(st.plan) - st.invested(by: CrowdStartups.me)
        let cash: Double = Payments.liquid(e.state)
        let hi: Double = max(0, min(room, mineRoom, cash)).rounded(.down)
        let lo: Double = min(hi, CrowdStartupRules.minTicket(st.plan, stage: stage).rounded(.up))
        let shown = Binding<Double>(get: { min(max(amount, lo), max(lo, hi)) }, set: { (v: Double) in amount = v })
        let amt: Double = hi > lo ? shown.wrappedValue : lo
        let check: CrowdStartupRules.InvestResult = CrowdStartupRules.investCheck(st, investorID: CrowdStartups.me, linkKeys: keys, accountWeeks: weeks, amount: max(amt, 1), today: today)
        VStack(alignment: .leading, spacing: PopupSpace.card) {
            Text(st.name).popupText(.figure)
            PlanRows(startup: st, cur: cur)
            switch check {
            case .refused(let r):
                Text(r.message).popupText(.risk)
            case .ok(let q):
                if hi > lo { LedgerSlider(value: shown, in: lo...hi, step: max(100, ((hi - lo) / 100).rounded()), valueText: "Put in " + cur.tidyShort(amt)) }
                CardSection("What you get") {
                    VStack(alignment: .leading, spacing: PopupSpace.row) {
                        PopupRow(label: "You pay", value: cur.tidyShort(amt))
                        PopupRow(label: "You own", value: String(format: "%.2f%% of the startup", q.percent))
                        PopupRow(label: "Held in escrow until", value: q.releasedAtMilestone.lowercased())
                        PopupRow(label: "You cannot resell for", value: StartupText.lockWords(CrowdStartupRules.lockWeeks))
                        PopupRow(label: "Your cash after", value: cur.tidyShort(cash - amt))
                    }
                }
                Button("Invest \(cur.tidyShort(amt))") { ask(e, st, q, cur) }.buttonStyle(PrimaryButtonStyle(fullWidth: true)).accessibilityIdentifier("startup-invest-go")
            }
        }
    }

    private func ask(_ e: GameEngine, _ st: CrowdStartup, _ q: CrowdStartupRules.Quote, _ cur: Currency) {
        let amt: Double = q.amount
        let total: Double = st.invested(by: CrowdStartups.me) + amt
        pending = StartupPopup.ask(title: "Invest in \(st.name)?", lines: [
            "\(cur.tidyDisplay(amt)) leaves your cash now and waits in escrow until \(q.releasedAtMilestone.lowercased()).",
            String(format: "You own %.2f%% of the startup afterwards, bought at the fixed price of %@ for each 1%%.", q.percent, cur.tidyShort(q.pricePerPercent)),
            "You cannot resell for \(CrowdStartupRules.lockWeeks) game weeks. A sale must then be near the real value, and costs a transfer tax of \(Int(CrowdStartupRules.transferTax * 100))% paid by the buyer and tax on any gain.",
            "If the startup fails before the milestone, the escrow comes back to you. If it fails after, that money is lost.",
        ], button: "Invest \(cur.tidyShort(amt))", risk: "In total you would have \(cur.tidyShort(total)) in this startup, the most one investor may put in is \(cur.tidyShort(CrowdStartupRules.perInvestorCap(st.plan))).") {
            var st2: CrowdStartup = market.service.startup(st.id) ?? st
            let weeks: Int = StartupMarketStore.accountWeeks(e), today: Int = StartupMarketStore.today(e)
            let keys: Set<String> = market.service.myLinkKeys
            var out: CrowdStartups.InvestOutcome?
            _ = store.act { (eng: inout GameEngine) -> Bool in
                eng.update { s, _, _ in out = CrowdStartups.invest(&s, startup: &st2, linkKeys: keys, accountWeeks: weeks, amount: amt, today: today) }
                return true
            }
            switch out {
            case .ok(let quote, let holding)?:
                market.service.commitInvestment(st2, holding: holding)
                Haptics.success()
                store.tell("You invested in \(st.name)", String(format: "%@ is in escrow for %.2f%% of the startup. It is released when %@. You cannot resell for %d game weeks.", cur.tidyShort(amt), quote.percent, quote.releasedAtMilestone.lowercased(), CrowdStartupRules.lockWeeks), tone: "good")
                dismiss()
            case .refused(let why)?:
                store.tell("Not invested", why, tone: "warn")
            case nil:
                break
            }
        }
    }
}

// MARK: Second-hand shares

/// Buy shares another player offers. The price is inside the band around real value; the transfer tax comes on top.
struct BuySharesSheet: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market = StartupMarketStore.shared
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var offerID: String
    @State private var pending: PendingAction?

    private var offer: StartupShareOffer? {
        for s in market.service.startups() { if let o = market.service.offers(startupID: s.id).first(where: { $0.id == offerID }) { return o } }
        return nil
    }

    var body: some View {
        Group {
            if let e = store.engine, let o = offer, let st = market.service.startup(o.startupID) { content(e, o, st) } else { Text("These shares are no longer for sale.").popupText(.body) }
        }
        .confirmAction($pending)
        .centerSheetTitle("Buy shares")
    }

    @ViewBuilder private func content(_ e: GameEngine, _ o: StartupShareOffer, _ st: CrowdStartup) -> some View {
        let cur: Currency = e.homeCurrency
        let rate: Double = market.gainsRate(e)
        let res = CrowdStartupRules.saleCheck(st, holding: o.holding, percent: o.percent, price: o.price, buyerID: CrowdStartups.me, buyerLinkKeys: market.service.myLinkKeys,
                                              buyerAccountWeeks: StartupMarketStore.accountWeeks(e), gainsRate: rate, today: StartupMarketStore.today(e))
        VStack(alignment: .leading, spacing: PopupSpace.card) {
            Text(st.name).popupText(.figure)
            PopupRow(label: "Shares", value: String(format: "%.1f%% from %@", o.percent, o.sellerName))
            PopupRow(label: "Real value of these shares", value: cur.tidyShort(CrowdStartupRules.fairPrice(st, percent: o.percent)))
            switch res {
            case .refused(let r): Text(r.message).popupText(.risk)
            case .ok(let q):
                PopupRow(label: "Price", value: cur.tidyShort(q.price))
                PopupRow(label: "Transfer tax, on top", value: cur.tidyShort(q.transferTax))
                PopupRow(label: "You pay", value: cur.tidyShort(q.buyerPays))
                PopupRow(label: "Your cash after", value: cur.tidyShort(Payments.liquid(e.state) - q.buyerPays))
                Button("Buy for \(cur.tidyShort(q.buyerPays))") { ask(e, o, st, q, cur, rate) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
            }
        }
    }

    private func ask(_ e: GameEngine, _ o: StartupShareOffer, _ st: CrowdStartup, _ q: CrowdStartupRules.SaleQuote, _ cur: Currency, _ rate: Double) {
        pending = StartupPopup.ask(title: "Buy \(String(format: "%.1f%%", o.percent)) of \(st.name)?", lines: [
            "\(cur.tidyDisplay(q.buyerPays)) leaves your cash now: \(cur.tidyShort(q.price)) to the seller and \(cur.tidyShort(q.transferTax)) transfer tax.",
            String(format: "You own %.1f%% of the startup afterwards.", o.percent),
            "You cannot resell for \(CrowdStartupRules.lockWeeks) game weeks, and a later sale must be near the real value, with tax on any gain.",
            "If the startup fails, these shares are worth nothing.",
        ], button: "Buy for \(cur.tidyShort(q.buyerPays))", risk: "Buying and selling back loses the taxes each time.") {
            let weeks: Int = StartupMarketStore.accountWeeks(e), today: Int = StartupMarketStore.today(e)
            let keys: Set<String> = market.service.myLinkKeys
            var out: Result<(CrowdStartupRules.SaleQuote, CrowdHolding), CrowdStartups.SaleFailure>?
            _ = store.act { (eng: inout GameEngine) -> Bool in
                eng.update { s, _, _ in out = CrowdStartups.buy(&s, startup: st, from: o.holding, percent: o.percent, price: o.price, accountWeeks: weeks, linkKeys: keys, gainsRate: rate, today: today) }
                return true
            }
            switch out {
            case .success(let r)?:
                market.service.commitPurchase(offerID: o.id, startup: st, holding: r.1)
                Haptics.success()
                store.tell("You bought shares in \(st.name)", String(format: "%@ paid for %.1f%%, including %@ transfer tax. They are locked for %d game weeks.", cur.tidyShort(r.0.buyerPays), o.percent, cur.tidyShort(r.0.transferTax), CrowdStartupRules.lockWeeks), tone: "good")
                dismiss()
            case .failure(let f)?:
                store.tell("Not bought", f.message, tone: "warn")
            case nil:
                break
            }
        }
    }
}

/// Sell part or all of a holding to a buyer. The price must lie in the band around real value; the buyer pays the transfer tax, you pay tax on a gain.
struct SellSharesSheet: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market = StartupMarketStore.shared
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var startupID: String
    @State private var share = 1.0
    @State private var position = 1.0
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let st = market.service.startup(startupID), let h = market.service.myHoldings().first(where: { $0.startupID == startupID }) { content(e, st, h) }
            else { Text("You hold no shares here.").popupText(.body) }
        }
        .confirmAction($pending)
        .centerSheetTitle("Sell shares")
    }

    @ViewBuilder private func content(_ e: GameEngine, _ st: CrowdStartup, _ h: CrowdHolding) -> some View {
        let cur: Currency = e.homeCurrency
        let pct: Double = h.percent * share
        let fair: Double = CrowdStartupRules.fairPrice(st, percent: pct)
        let band = CrowdStartupRules.band(st, percent: pct)
        let price: Double = (fair * position).rounded()
        let rate: Double = market.gainsRate(e)
        let buyer: StartupBuyer? = market.service.buyer(startupID: st.id)
        VStack(alignment: .leading, spacing: PopupSpace.card) {
            Text(st.name).popupText(.figure)
            SegmentedPill(items: [0.25, 0.5, 1.0], title: { (v: Double) -> String in v == 1.0 ? "All" : "\(Int(v * 100))%" }, selection: $share)
            SegmentedPill(items: [CrowdStartupRules.bandLow, 1.0, CrowdStartupRules.bandHigh], title: { (v: Double) -> String in v < 1 ? "Low" : v == 1 ? "Fair" : "High" }, selection: $position)
            PopupRow(label: "Real value of these shares", value: cur.tidyShort(fair))
            PopupRow(label: "A sale must be between", value: cur.tidyShort(band.low) + " and " + cur.tidyShort(band.high))
            if let b = buyer {
                switch CrowdStartupRules.saleCheck(st, holding: h, percent: pct, price: price, buyerID: b.id, buyerLinkKeys: [b.linkKey], buyerAccountWeeks: b.accountWeeks, gainsRate: rate, today: StartupMarketStore.today(e)) {
                case .refused(let r): Text(r.message).popupText(.risk)
                case .ok(let q):
                    PopupRow(label: "Price from \(b.name)", value: cur.tidyShort(q.price))
                    PopupRow(label: "Tax on your gain", value: cur.tidyShort(q.gainsTax))
                    PopupRow(label: "You receive", value: cur.tidyShort(q.sellerReceives))
                    Text("The buyer pays a transfer tax of \(cur.tidyShort(q.transferTax)) on top.").popupText(.caption)
                    Button("Sell for \(cur.tidyShort(q.price))") { ask(e, st, h, b, pct, q, cur, rate) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                }
            } else {
                Text("Nobody is buying shares in this startup now.").popupText(.risk)
            }
        }
    }

    private func ask(_ e: GameEngine, _ st: CrowdStartup, _ h: CrowdHolding, _ b: StartupBuyer, _ pct: Double, _ q: CrowdStartupRules.SaleQuote, _ cur: Currency, _ rate: Double) {
        let after: Double = h.percent - pct
        pending = StartupPopup.ask(title: "Sell \(String(format: "%.1f%%", pct)) of \(st.name)?", lines: [
            "\(cur.tidyDisplay(q.price)) comes into your cash, less \(cur.tidyShort(q.gainsTax)) tax on the gain: you receive \(cur.tidyShort(q.sellerReceives)).",
            after > 0.0001 ? String(format: "You keep %.1f%% of the startup.", after) : "You own nothing in this startup afterwards.",
            "This cannot be undone. If the startup does well later, you do not share in it.",
        ], button: "Sell for \(cur.tidyShort(q.price))", risk: "A loss gets no tax back.") {
            var mine: CrowdHolding = h
            let today: Int = StartupMarketStore.today(e)
            var out: Result<CrowdStartupRules.SaleQuote, CrowdStartups.SaleFailure>?
            _ = store.act { (eng: inout GameEngine) -> Bool in
                eng.update { s, _, _ in
                    out = CrowdStartups.sell(&s, startup: st, holding: &mine, percent: pct, price: q.price, buyerID: b.id, buyerLinkKeys: [b.linkKey], buyerAccountWeeks: b.accountWeeks, gainsRate: rate, today: today)
                }
                return true
            }
            switch out {
            case .success(let r)?:
                market.service.commitSale(startupID: st.id, remaining: mine)
                Haptics.success()
                store.tell("Shares sold", "You received \(cur.tidyShort(r.sellerReceives)) after \(cur.tidyShort(r.gainsTax)) tax on the gain.", tone: "good")
                dismiss()
            case .failure(let f)?:
                store.tell("Not sold", f.message, tone: "warn")
            case nil:
                break
            }
        }
    }
}
