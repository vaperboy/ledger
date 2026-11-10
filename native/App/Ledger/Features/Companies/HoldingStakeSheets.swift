import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum HoldingStakeSheet: Identifiable, Hashable {
    case sell(Int), sellRival(Int), board(Int), merge(Int), division(Int), talk(Int), buy(String)

    var id: String {
        switch self {
        case .sell(let n): return "sell-\(n)"
        case .sellRival(let n): return "sellr-\(n)"
        case .board(let n): return "board-\(n)"
        case .merge(let n): return "merge-\(n)"
        case .division(let n): return "division-\(n)"
        case .talk(let n): return "talk-\(n)"
        case .buy(let s): return "buy-\(s)"
        }
    }
}

struct HoldingSellSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.popupClose) private var popupClose
    var holdingID: Int
    var companyID: Int?
    var rivalID: Int?
    @State private var percent = 0.0
    @State private var buyer: HoldingStakes.Buyer = .market
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let h = e.state.company(holdingID) {
                content(e, h)
            } else {
                Text("This holding is not available.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Sell some shares")
    }

    private func close() { popupClose?() }

    private func facts(_ e: GameEngine) -> (name: String, owned: Double, value: Double)? {
        if let cid = companyID, let c = e.state.company(cid) {
            let line: Double = e.holdingStakes(holdingID: holdingID).first { (s: (company: Company, percent: Double, tier: HoldingStakes.Tier)) -> Bool in s.company.id == cid }?.percent ?? 0
            let v: Double = e.holdingOverview(companyID: holdingID)?.subsidiaries.first { (k: HoldingModel.Subsidiary) -> Bool in k.id == cid }?.value ?? 0
            return (c.name, line, v)
        }
        if let rid = rivalID, let r = e.holdingRivalStakes(holdingID: holdingID).first(where: { (x: HoldingStakes.RivalStake) -> Bool in x.id == rid }) {
            return (r.name, r.percent, r.value)
        }
        return nil
    }

    @ViewBuilder private func content(_ e: GameEngine, _ h: Company) -> some View {
        let cur: Currency = e.currency(for: h)
        if let f = facts(e) {
            let lo: Double = HoldingStakes.minimumPercent
            let hi: Double = max(lo, f.owned)
            let shown = Binding<Double>(get: { min(max(percent == 0 ? min(hi, 10) : percent, lo), hi) }, set: { (v: Double) in percent = v })
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(f.name).popupText(.figure)
                PopupRow(label: "The holding owns", value: holdingPct(f.owned))
                if companyID != nil {
                    SegmentedChoice(items: [HoldingStakes.Buyer.market, HoldingStakes.Buyer.owner], title: { (b: HoldingStakes.Buyer) -> String in b == .market ? "To the market" : "To you" }, selection: $buyer)
                    Text(buyer == .market ? "Market investors pay less for a small stake than for a controlling one." : "You buy the shares yourself from your personal account, at fair value.")
                        .popupText(.caption).fixedSize(horizontal: false, vertical: true)
                }
                if hi > lo {
                    LedgerSlider(value: shown, in: lo...hi, step: 0.5, valueText: "Sell " + holdingPct(shown.wrappedValue))
                        .accessibilityIdentifier("holding-sell-percent")
                }
                quoteView(e, cur, f, shown.wrappedValue)
            }
        } else {
            Text("The holding no longer owns this stake.").popupText(.body)
        }
    }

    @ViewBuilder private func quoteView(_ e: GameEngine, _ cur: Currency, _ f: (name: String, owned: Double, value: Double), _ pct: Double) -> some View {
        if let cid = companyID {
            switch e.holdingSellStakeQuote(holdingID: holdingID, companyID: cid, percent: pct, to: buyer) {
            case .success(let q):
                summary(cur, f.name, q.percent, q.price, q.heldAfter, q.tierAfter, q.priceFactor, bought: q.boughtPercent, moved: q.movedPercent)
            case .failure(let fail):
                Text(fail.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
                if buyer == .owner {
                    Button("Sell to the market instead") { Haptics.tap(); buyer = .market }
                        .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                        .accessibilityIdentifier("holding-sell-market")
                }
            }
        } else {
            let factor: Double = HoldingStakes.sellFactor(beforePercent: f.owned)
            let left: Double = max(0, f.owned - pct)
            summary(cur, f.name, pct, (f.value * pct / 100 * factor).rounded(), left, HoldingStakes.tier(forPercent: left), factor)
        }
    }

    private func summary(_ cur: Currency, _ name: String, _ pct: Double, _ price: Double, _ left: Double, _ tier: HoldingStakes.Tier, _ factor: Double,
                         bought: Double = 0, moved: Double = 0) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            splitLine(bought, moved)
            PopupRow(label: buyer == .owner && companyID != nil ? "You pay the holding" : "The holding receives", value: cur.tidyShort(price))
            if factor < 0.9999 { Text("Sold at \(Int(saturating: (factor * 100).rounded()))% of fair value.").popupText(.caption) }
            HoldingTierNote(tier: tier, percent: left)
            Button("Sell \(holdingPct(pct)) for \(cur.tidyShort(price))") { askSell(name, pct, price, cur) }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .accessibilityIdentifier("holding-sell-go")
        }
    }

    @ViewBuilder private func splitLine(_ bought: Double, _ moved: Double) -> some View {
        if bought > 0 && moved > 0 {
            Text("\(holdingPct(bought)) were bought by the holding, \(holdingPct(moved)) are your own shares moved under it.").popupText(.caption).fixedSize(horizontal: false, vertical: true)
        } else if moved > 0 {
            Text("These are your own shares moved under the holding. Only the market can buy them; the money goes to the holding.").popupText(.caption).fixedSize(horizontal: false, vertical: true)
        } else if bought > 0 {
            Text("These shares were bought by the holding.").popupText(.caption)
        }
    }

    private func askSell(_ name: String, _ pct: Double, _ price: Double, _ cur: Currency) {
        let who: HoldingStakes.Buyer = buyer
        pending = PendingAction(title: "Sell \(holdingPct(pct)) of \(name)?", message: "The holding gives up these shares for \(cur.tidyShort(price)). Selling lowers its stake and may lower its tier.",
                                button: "Sell", destructive: true, amount: price, currency: cur) {
            let r: Result<HoldingStakes.Deal, HoldingStakes.Failure>? = store.act { (e: inout GameEngine) -> Result<HoldingStakes.Deal, HoldingStakes.Failure> in
                if let cid = companyID { return e.holdingSellStake(holdingID: holdingID, companyID: cid, percent: pct, to: who) }
                return e.holdingSellRivalStake(holdingID: holdingID, rivalID: rivalID ?? 0, percent: pct)
            }
            switch r {
            case .success(let d)?:
                Haptics.success()
                let split: String = d.boughtPercent > 0 && d.movedPercent > 0 ? " (\(holdingPct(d.boughtPercent)) bought, \(holdingPct(d.movedPercent)) moved)" : ""
                store.show("Sold \(holdingPct(d.percent)) of \(name)\(split) for \(cur.tidyShort(d.amount)).", tone: "good"); close()
            case .failure(let f)?:
                Haptics.warning(); store.show(f.reason, tone: "warn")
            case nil:
                store.show("It could not be sold now.", tone: "warn")
            }
        }
    }
}

struct HoldingMergeSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.popupClose) private var popupClose
    var holdingID: Int
    var companyID: Int
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let h = e.state.company(holdingID), let c = e.state.company(companyID) {
                content(e, h, c)
            } else {
                Text("This company is not available.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Buy out the other owners and merge")
    }

    @ViewBuilder private func content(_ e: GameEngine, _ h: Company, _ c: Company) -> some View {
        let cur: Currency = e.currency(for: h)
        let t: HoldingStakes.MergeTerms = e.holdingMergeTerms(holdingID: holdingID, companyID: companyID)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(c.name).popupText(.figure)
            Text(t.allowed ? t.summary : t.reason).popupText(t.allowed ? .body : .risk).fixedSize(horizontal: false, vertical: true)
            if t.allowed {
                PopupRow(label: "The holding owns now", value: holdingPct(t.heldPercent))
                PopupRow(label: "Cost to buy the rest", value: cur.tidyShort(t.cost))
                if t.paidToYou > 0 { PopupRow(label: "Paid to you personally", value: cur.tidyShort(t.paidToYou)) }
                Text("Afterwards the holding owns every share. This cannot be undone.").popupText(.caption)
                HoldingCashNeed(holdingCash: h.cash, needed: t.cost, cur: cur) { (short: Double) in
                    pending = holdingInjectAction(store: store, holdingID: holdingID, holdingName: h.name, amount: short, cur: cur)
                }
                Button("Merge for \(cur.tidyShort(t.cost))") { askMerge(c.name, t, cur) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(h.cash < t.cost)
                    .accessibilityIdentifier("holding-merge-go")
            }
        }
    }

    private func askMerge(_ name: String, _ t: HoldingStakes.MergeTerms, _ cur: Currency) {
        pending = PendingAction(title: "Merge \(name) into the holding?", message: t.summary, button: "Merge", destructive: true, amount: t.cost, currency: cur,
                                risk: "It cannot be undone.") {
            let r: Result<Double, HoldingStakes.Failure>? = store.act { (e: inout GameEngine) -> Result<Double, HoldingStakes.Failure> in
                e.holdingMergeStake(holdingID: holdingID, companyID: companyID)
            }
            switch r {
            case .success(let paid)?:
                Haptics.success(); store.show("\(name) is now wholly owned. The holding paid \(cur.tidyShort(paid)).", tone: "good"); popupClose?()
            case .failure(let f)?:
                Haptics.warning(); store.show(f.reason, tone: "warn")
            case nil:
                store.show("It could not be merged now.", tone: "warn")
            }
        }
    }
}

struct HoldingBoardSheet: View {
    @EnvironmentObject var store: GameStore
    var holdingID: Int
    var companyID: Int
    @State private var kind: String?

    var body: some View {
        let name: String = store.engine?.state.company(companyID)?.name ?? "Board"
        Group {
            if let e = store.engine {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let k = kind {
                        voteView(e, k)
                    } else {
                        roundView(e)
                    }
                }
            }
        }
        .centerSheetTitle("Board of \(name)")
    }

    @ViewBuilder private func voteView(_ e: GameEngine, _ k: String) -> some View {
        switch e.holdingBoardVote(holdingID: holdingID, companyID: companyID, kind: k) {
        case .success(let v):
            BoardVoteLines(vote: v, kind: k)
        case .failure(let f):
            Text(f.reason).popupText(.risk)
        }
        Button("Back") { Haptics.tap(); kind = nil }.buttonStyle(TertiaryButtonStyle(fullWidth: true))
    }

    @ViewBuilder private func roundView(_ e: GameEngine) -> some View {
        switch e.holdingBoardRound(holdingID: holdingID, companyID: companyID) {
        case .success(let lines):
            if lines.isEmpty {
                Text("Nobody sits at this table yet.").popupText(.body)
            }
            ForEach(lines) { (l: OwnerMeetings.RoundLine) in
                DialogueQuote(speaker: "\(l.name) \u{00B7} \(l.title)", lines: [l.text])
            }
            Text("Ask the board").popupText(.subtitle).padding(.top, Theme.Space.xs)
            VStack(spacing: 0) {
                PopupChoiceRow(title: "Should we sell it?", identifier: "holding-board-sell") { kind = "sell" }
                PopupChoiceRow(title: "Should we close it?", identifier: "holding-board-close") { kind = "close" }
                PopupChoiceRow(title: "Should we take a loan?", identifier: "holding-board-loan") { kind = "loan" }
            }
            Text("The holding's shares vote with yours.").popupText(.caption)
        case .failure(let f):
            Text(f.reason).popupText(.risk).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HoldingMoveSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.popupClose) private var popupClose
    var holdingID: Int
    @State private var picked: [Int: Double] = [:]
    @State private var pending: PendingAction?

    var body: some View {
        Group {
            if let e = store.engine, let h = e.state.company(holdingID) {
                content(e, h)
            } else {
                Text("This holding is not available.").popupText(.body)
            }
        }
        .confirmAction($pending)
        .centerSheetTitle("Put companies under it")
    }

    @ViewBuilder private func content(_ e: GameEngine, _ h: Company) -> some View {
        let free: [Company] = e.companiesForHolding
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if free.isEmpty {
                Text("No limited company of yours is free to put under a holding.").popupText(.body)
            }
            ForEach(free) { (c: Company) in row(c) }
            if !free.isEmpty {
                Text("Only limited companies can be held. What you keep stays yours personally.").popupText(.caption).fixedSize(horizontal: false, vertical: true)
                Button(picked.isEmpty ? "Choose companies" : "Put \(picked.count) under \(h.name)") { askMove(e, free, h.name) }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(picked.isEmpty)
                    .accessibilityIdentifier("holding-move-go")
            }
        }
    }

    private func row(_ c: Company) -> some View {
        let on: Bool = picked[c.id] != nil
        let share = Binding<Double>(get: { picked[c.id] ?? 100 }, set: { (v: Double) in picked[c.id] = v })
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            Button {
                Haptics.choose()
                if on { picked[c.id] = nil } else { picked[c.id] = 100 }
            } label: {
                HStack {
                    Text(c.name).popupText(.button)
                    Spacer()
                    Text("you own \(holdingPct(c.ownership))").popupText(.caption)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.gold : Theme.ivoryFaint)
                }
                .padding(.vertical, Theme.Space.s).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityValue(on ? "Selected" : "Not selected")
            .accessibilityIdentifier("holding-pick-\(c.id)")
            if on {
                LedgerSlider(value: share, in: 10...100, step: 5, valueText: share.wrappedValue >= 99.9 ? "All of your stake" : "\(Int(share.wrappedValue))% of your stake")
                if share.wrappedValue < 99.9 {
                    let part: Double = c.ownership * share.wrappedValue / 100
                    Text("\(holdingPct((part * 10).rounded() / 10)) of the company goes in; you keep \(holdingPct(((c.ownership - part) * 10).rounded() / 10)).")
                        .popupText(.caption)
                }
            }
        }
    }

    private func askMove(_ e: GameEngine, _ free: [Company], _ holdingName: String) {
        let chosen: [(id: Int, name: String, own: Double, share: Double)] = free.compactMap { (c: Company) -> (id: Int, name: String, own: Double, share: Double)? in
            guard let s = picked[c.id] else { return nil }
            return (c.id, c.name, c.ownership, s)
        }
        guard !chosen.isEmpty else { return }
        let names: String = chosen.map { (x: (id: Int, name: String, own: Double, share: Double)) -> String in x.name }.joined(separator: ", ")
        pending = PendingAction(title: "Put \(chosen.count == 1 ? chosen[0].name : "\(chosen.count) companies") under \(holdingName)?",
                                message: "\(names): the holding takes over the shares you choose. Dividends on them then flow into the holding at the lower rate. You can take bought shares back later with Release.",
                                button: "Put under holding", alwaysAsk: true) {
            let fails: [String] = store.act { (eng: inout GameEngine) -> [String] in
                var out: [String] = []
                for x in chosen {
                    if x.share >= 99.9 {
                        if !eng.moveToHolding(companyID: x.id, holdingID: holdingID) { out.append("\(x.name) could not be moved under the holding.") }
                    } else {
                        let pct: Double = max(HoldingStakes.minimumPercent, x.own * x.share / 100)
                        if case .failure(let f) = eng.moveToHolding(companyID: x.id, holdingID: holdingID, percent: pct) { out.append(f.reason) }
                    }
                }
                return out
            } ?? ["Nothing could be moved now."]
            if fails.isEmpty {
                Haptics.success(); store.show(chosen.count == 1 ? "\(chosen[0].name) is now held by \(holdingName)." : "\(chosen.count) companies are now held by \(holdingName).", tone: "good")
                popupClose?()
            } else {
                Haptics.warning(); store.show(fails[0], tone: "warn")
                picked = [:]
            }
        }
    }
}
