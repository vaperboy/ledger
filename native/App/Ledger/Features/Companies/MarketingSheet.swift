import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Marketing as a popup: one compact list of channels, each with a live weekly-budget slider and an on/off switch.
struct MarketingSheet: View {
    @EnvironmentObject var store: GameStore
    let companyID: Int
    /// Budget being dragged, per channel; absent = the running budget.
    @State private var draft: [String: Double] = [:]

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            content(e, co)
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func content(_ e: GameEngine, _ co: Company) -> some View {
        let cur: Currency = e.currency(for: co)
        let mkt: JSONValue = co.value("mkt")
        let channels: [MarketingChannel] = e.marketingChannels(companyID: companyID)
        let total: Double = channels.reduce(0) { $0 + spend($1, mkt: mkt) }
        let active: Int = channels.filter { spend($0, mkt: mkt) > 0 }.count
        return VStack(alignment: .leading, spacing: 8) {
            header(active: active, total: total, cur: cur)
            if channels.isEmpty {
                Text("No marketing channels are open yet.").font(.caption).foregroundStyle(Theme.ivoryMuted)
            } else if channels.count > 8 {
                ScrollView { channelList(e, channels, cur: cur, mkt: mkt) }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 520)
            } else {
                channelList(e, channels, cur: cur, mkt: mkt)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .ledgerBackground()
    }

    /// "Marketing", how many campaigns run and the total weekly budget; the popup's x sits at the right of this row.
    private func header(active: Int, total: Double, cur: Currency) -> some View {
        let sub: String = active == 0 ? "No campaigns" : "\(active) active \u{00B7} " + cur.tidyDisplay(total) + " a week"
        return VStack(alignment: .leading, spacing: 1) {
            Text("Marketing").font(.serifTitle(20)).foregroundStyle(Theme.ivory).accessibilityAddTraits(.isHeader)
            Text(sub).font(.system(size: 12.5, weight: .medium)).foregroundStyle(active > 0 ? Theme.gold : Theme.ivoryMuted)
        }
        .padding(.trailing, 44)
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
        let on = Binding<Bool>(get: { value > 0 }, set: { (v: Bool) in commit(ch, v ? first : 0) })
        let amount = Binding<Double>(get: { value }, set: { (v: Double) in draft[ch.id] = v })
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(ch.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ivory)
                    .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                InfoPopoverButton(title: ch.name, text: ch.note.tidyMoney)
                Spacer(minLength: 4)
                if reason == nil {
                    Text(cur.tidyDisplay(value) + " a week").font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(value > 0 ? Theme.gold : Theme.ivoryMuted).lineLimit(1).minimumScaleFactor(0.8)
                }
                LedgerSwitch(isOn: on).hitHeight(28).disabled(reason != nil)
            }
            .frame(minHeight: 28)
            if let why = reason {
                Text(why).font(.caption2).foregroundStyle(Theme.caution).padding(.bottom, 6)
            } else {
                LedgerSlider(value: amount, in: 0...top, onEditingChanged: { (editing: Bool) in
                    if !editing { commit(ch, draft[ch.id] ?? value) }
                })
                .hitHeight(30)
            }
        }
        .padding(.vertical, 2)
    }

    /// Applies the budget (0 stops it); a refusal (lock, chain) is shown and the slider snaps back.
    private func commit(_ ch: MarketingChannel, _ budget: Double) {
        let r = store.act { $0.setCampaign(companyID: companyID, channel: ch.id, weeklyBudget: budget, weeks: nil) }
        draft[ch.id] = nil
        if case .refused(let why)? = r { Haptics.warning(); store.show(why.prefix(1).uppercased() + why.dropFirst(), tone: "warn") }
    }
}
