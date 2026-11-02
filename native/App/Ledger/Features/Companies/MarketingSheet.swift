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
    /// Channel whose note is open (the small i button).
    @State private var noteFor: String?

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
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Marketing").font(.headline).foregroundStyle(Theme.ivory)
                Spacer()
                Text(total > 0 ? "Total " + cur.tidyDisplay(total) + " a week" : "No campaigns").font(.subheadline.weight(.semibold)).foregroundStyle(total > 0 ? Theme.gold : Theme.ivoryMuted)
            }
            if channels.isEmpty {
                Text("No marketing channels are open yet.").font(.caption).foregroundStyle(Theme.ivoryMuted)
            } else {
                if channels.count > 8 {
                    ScrollView { channelList(e, channels, cur: cur, mkt: mkt) }
                        .scrollBounceBehavior(.basedOnSize)
                } else {
                    channelList(e, channels, cur: cur, mkt: mkt)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .ledgerBackground()
    }

    private func channelList(_ e: GameEngine, _ channels: [MarketingChannel], cur: Currency, mkt: JSONValue) -> some View {
        VStack(spacing: 6) {
            ForEach(channels, id: \.id) { (ch: MarketingChannel) in row(e, ch, cur: cur, mkt: mkt) }
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
        return Card(padding: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(ch.name).font(.bodyText.weight(.semibold)).foregroundStyle(Theme.ivory).lineLimit(1).minimumScaleFactor(0.8)
                    Button { noteFor = (noteFor == ch.id) ? nil : ch.id } label: {
                        Text("i").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ivoryMuted)
                            .frame(width: 20, height: 20).overlay(Circle().strokeBorder(Theme.ivoryMuted, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle()).accessibilityLabel("About " + ch.name)
                    Spacer(minLength: 4)
                    if reason == nil {
                        Text(cur.tidyDisplay(value) + " a week").font(.caption.weight(.semibold)).foregroundStyle(value > 0 ? Theme.gold : Theme.ivoryMuted).lineLimit(1)
                    }
                    Toggle("", isOn: on).labelsHidden().disabled(reason != nil)
                }
                if noteFor == ch.id {
                    Text(ch.note.tidyMoney).font(.caption).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                }
                if let why = reason {
                    Text(why).font(.caption2).foregroundStyle(Theme.caution)
                } else {
                    Slider(value: amount, in: 0...top, onEditingChanged: { (editing: Bool) in
                        if !editing { commit(ch, draft[ch.id] ?? value) }
                    })
                    .tint(Theme.gold)
                }
            }
        }
    }

    /// Applies the budget (0 stops it); a refusal (lock, chain) is shown and the slider snaps back.
    private func commit(_ ch: MarketingChannel, _ budget: Double) {
        let r = store.act { $0.setCampaign(companyID: companyID, channel: ch.id, weeklyBudget: budget, weeks: nil) }
        draft[ch.id] = nil
        if case .refused(let why)? = r { Haptics.warning(); store.show(why.prefix(1).uppercased() + why.dropFirst(), tone: "warn") }
    }
}
