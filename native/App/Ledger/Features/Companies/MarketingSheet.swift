import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Marketing as a popup: one compact list of channels, each with a live weekly-budget slider, an on/off switch and what that budget is
/// expected to do (`Marketing.estimate`), so a budget is never set blind.
struct MarketingSheet: View {
    @EnvironmentObject var store: GameStore
    let companyID: Int
    /// Budget being dragged, per channel; absent = the running budget.
    @State private var draft: [String: Double] = [:]

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            content(e, co)
        } else {
            EmptyState(glyph: Glyph.opsMega, title: "This company no longer exists")
        }
    }

    private func content(_ e: GameEngine, _ co: Company) -> some View {
        let cur: Currency = e.currency(for: co)
        let mkt: JSONValue = co.value("mkt")
        let channels: [MarketingChannel] = e.marketingChannels(companyID: companyID)
        let total: Double = channels.reduce(0) { $0 + spend($1, mkt: mkt) }
        let active: Int = channels.filter { spend($0, mkt: mkt) > 0 }.count
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            header(active: active, total: total, cur: cur)
            if channels.isEmpty {
                EmptyState(glyph: Glyph.opsMega, title: "No marketing channels are open yet", centered: false)
            } else {
                channelList(e, channels, cur: cur, mkt: mkt)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// The total weekly budget as the one figure, and how many channels run.
    private func header(active: Int, total: Double, cur: Currency) -> some View {
        let sub: String = active == 0 ? "No campaigns running: switch a channel on" : "\(active.countText("channel")) running"
        return VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(cur.tidyDisplay(total) + " a week").popupText(.figure)
            Text(sub).popupText(active > 0 ? .effect : .subtitle)
        }
        .padding(.bottom, Theme.Space.s)
    }

    private func channelList(_ e: GameEngine, _ channels: [MarketingChannel], cur: Currency, mkt: JSONValue) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(channels.enumerated()), id: \.element.id) { (n: Int, ch: MarketingChannel) in
                if n > 0 { Hairline() }
                row(e, ch, cur: cur, mkt: mkt)
            }
        }
    }

    private func running(_ ch: MarketingChannel, mkt: JSONValue) -> Double {
        let r: JSONValue = mkt[ch.id]
        return r.isNull ? 0 : r["b"].double
    }

    private func spend(_ ch: MarketingChannel, mkt: JSONValue) -> Double { draft[ch.id] ?? running(ch, mkt: mkt) }

    private func row(_ e: GameEngine, _ ch: MarketingChannel, cur: Currency, mkt: JSONValue) -> some View {
        let budgets: [Double] = ch.budgets(in: cur).filter { $0 > 0 }
        let top: Double = budgets.max() ?? 1
        let first: Double = budgets.min() ?? top
        let value: Double = spend(ch, mkt: mkt)
        let plan: CampaignPlan? = e.campaignPlan(companyID: companyID, channel: ch.id, weeklyBudget: 1, weeks: nil)
        let blockedText: String? = plan?.blocked.map { $0.prefix(1).uppercased() + $0.dropFirst() + "." }
        let reason: String? = plan?.runByChain == true ? "Run by the chain." : blockedText
        let on = Binding<Bool>(get: { value > 0 }, set: { (v: Bool) in commit(ch, v ? first : 0, cur: cur) })
        let amount = Binding<Double>(get: { value }, set: { (v: Double) in draft[ch.id] = v })
        // An off channel is one compact row with its switch; the budget slider and its effect show once it runs (or while dragged).
        let live: Bool = running(ch, mkt: mkt) > 0 || draft[ch.id] != nil
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.xs) {
                Text(ch.name).popupText(.rowValue)
                    .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                InfoPopoverButton(title: ch.name, text: ch.note.tidyMoney)
                Spacer(minLength: Theme.Space.xs)
                if reason == nil && live {
                    Text(cur.tidyDisplay(value) + " a week").popupText(.effect).lineLimit(1).minimumScaleFactor(0.8)
                }
                LedgerSwitch(isOn: on).disabled(reason != nil)
            }
            .frame(minHeight: 44)
            if let why = reason {
                Text(why).popupText(.risk).padding(.bottom, Theme.Space.xs)
            } else if live {
                if value > 0, let line = effectLine(e, ch, budget: value, cur: cur) {
                    Text(line.text).textStyle(.caption, tint: line.tint, numeric: true).fixedSize(horizontal: false, vertical: true)
                }
                // Snaps to the engine's own budget levels (and 0, which stops the channel).
                LedgerSlider(value: amount, in: 0...top, onEditingChanged: { (editing: Bool) in
                    if !editing { commit(ch, draft[ch.id] ?? value, cur: cur) }
                })
                .detents([0] + budgets)
                .accessibilityIdentifier("marketing-budget-" + ch.id)
            }
        }
        .padding(.vertical, Theme.Space.xxs)
    }

    /// What this budget is expected to do once the name has settled: more customers and the weekly profit after the budget, or that the
    /// place has no room for them. Follows the slider while it is dragged.
    private func effectLine(_ e: GameEngine, _ ch: MarketingChannel, budget: Double, cur: Currency) -> (text: String, tint: Color)? {
        guard let co = e.state.company(companyID),
              let est = Marketing.estimate(co, channel: ch.id, weeklyBudget: budget, state: e.state, data: e.data, tables: e.marketing) else { return nil }
        let customers: String = String(format: "\u{2248} %+.0f%% customers", est.demandLift * 100)
        if est.atCapacity { return (customers + " \u{00B7} no room to serve them", Theme.warn) }
        let net: String = (est.netPerWeek >= 0 ? "+" : "\u{2212}") + cur.tidyShort(abs(est.netPerWeek)) + " a week after its cost"
        let payback: String = est.paybackWeeks.map { $0 > 0 ? " \u{00B7} pays back in \($0.weeksText)" : "" } ?? " \u{00B7} never pays back"
        return (customers + " \u{00B7} " + net + payback, est.netPerWeek >= 0 ? Theme.gain : Theme.loss)
    }

    /// Applies the budget (0 stops it); a refusal (lock, chain) is shown and the slider snaps back, a change is confirmed.
    private func commit(_ ch: MarketingChannel, _ budget: Double, cur: Currency) {
        let r = store.act { $0.setCampaign(companyID: companyID, channel: ch.id, weeklyBudget: budget, weeks: nil) }
        draft[ch.id] = nil
        if case .refused(let why)? = r { Haptics.warning(); store.show(why.prefix(1).uppercased() + why.dropFirst(), tone: "warn") }
        else if r != nil { store.saved(budget > 0 ? ch.name + " at " + cur.tidyDisplay(budget) + " a week" : ch.name + " stopped") }
    }
}
