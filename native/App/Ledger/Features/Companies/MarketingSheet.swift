import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Marketing as a popup: one compact row per channel with its switch; a running channel also shows its weekly budget as a step control
/// over the engine's own budget levels (no slider, so a scroll or swipe never sets a budget) and what that budget is expected to do.
/// A big rise asks first; every change can be undone from its toast.
struct MarketingSheet: View {
    @EnvironmentObject var store: GameStore
    let companyID: Int
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            content(e, co).confirmAction($pending)
        } else {
            EmptyState(glyph: Glyph.opsMega, title: "This company no longer exists")
        }
    }

    private func content(_ e: GameEngine, _ co: Company) -> some View {
        let cur: Currency = e.currency(for: co)
        let mkt: JSONValue = co.value("mkt")
        let channels: [MarketingChannel] = e.marketingChannels(companyID: companyID)
        let total: Double = channels.reduce(0) { $0 + running($1, mkt: mkt) }
        let active: Int = channels.filter { running($0, mkt: mkt) > 0 }.count
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
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(cur.tidyDisplay(total) + " a week").popupText(.figure)
            Text(active == 0 ? "No campaigns running" : "\(active.countText("channel")) running").popupText(active > 0 ? .effect : .subtitle)
        }
        .padding(.bottom, Theme.Space.s)
    }

    private func channelList(_ e: GameEngine, _ channels: [MarketingChannel], cur: Currency, mkt: JSONValue) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(channels.enumerated()), id: \.element.id) { (n: Int, ch: MarketingChannel) in
                if n > 0 { Hairline() }
                row(e, ch, channels, cur: cur, mkt: mkt)
            }
        }
    }

    private func running(_ ch: MarketingChannel, mkt: JSONValue) -> Double {
        let r: JSONValue = mkt[ch.id]
        return r.isNull ? 0 : r["b"].double
    }

    private func row(_ e: GameEngine, _ ch: MarketingChannel, _ all: [MarketingChannel], cur: Currency, mkt: JSONValue) -> some View {
        let levels: [Double] = ch.budgets(in: cur).filter { $0 > 0 }.sorted()
        let first: Double = levels.first ?? 0
        let value: Double = running(ch, mkt: mkt)
        let total: Double = all.reduce(0) { $0 + running($1, mkt: mkt) }
        let plan: CampaignPlan? = e.campaignPlan(companyID: companyID, channel: ch.id, weeklyBudget: 1, weeks: nil)
        let blockedText: String? = plan?.blocked.map { $0.prefix(1).uppercased() + $0.dropFirst() + "." }
        let reason: String? = plan?.runByChain == true ? "Run by the chain." : blockedText
        let on = Binding<Bool>(get: { value > 0 }, set: { (v: Bool) in change(ch, from: value, to: v ? first : 0, total: total, cur: cur) })
        let lower: Double? = levels.last { $0 < value - 0.001 } ?? (value > 0 ? 0 : nil)
        let higher: Double? = levels.first { $0 > value + 0.001 }
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.xs) {
                Text(ch.name).popupText(.rowValue)
                    .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                InfoPopoverButton(title: ch.name, text: ch.note.tidyMoney)
                Spacer(minLength: Theme.Space.xs)
                LedgerSwitch(isOn: on).disabled(reason != nil)
            }
            .frame(minHeight: 44)
            if let why = reason {
                Text(why).popupText(.risk).padding(.bottom, Theme.Space.xs)
            } else if value > 0 {
                HStack(spacing: Theme.Space.s) {
                    stepButton("minus", enabled: lower != nil, id: "marketing-less-" + ch.id) { if let l = lower { change(ch, from: value, to: l, total: total, cur: cur) } }
                    Text(cur.tidyDisplay(value) + " a week").popupText(.effect).frame(maxWidth: .infinity)
                    stepButton("plus", enabled: higher != nil, id: "marketing-more-" + ch.id) { if let h = higher { change(ch, from: value, to: h, total: total, cur: cur) } }
                }
                if let line = effectLine(e, ch, budget: value, cur: cur) {
                    Text(line.text).textStyle(.caption, tint: line.tint, numeric: true).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, Theme.Space.xxs)
    }

    /// A round minus or plus with a 44 pt target.
    private func stepButton(_ symbol: String, enabled: Bool, id: String, _ run: @escaping () -> Void) -> some View {
        Button { Haptics.choose(); run() } label: {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(SecondaryButtonStyle(size: .compact))
        .disabled(!enabled)
        .accessibilityIdentifier(id)
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

    /// A rise to more than twice the current weekly total, or above a quarter of a normal week's revenue, asks first (it is paid every week).
    private func change(_ ch: MarketingChannel, from old: Double, to new: Double, total: Double, cur: Currency) {
        let newTotal: Double = total - old + new
        let weekRevenue: Double = store.engine?.state.company(companyID).map { (co: Company) -> Double in
            max(co.lastWeekRevenue, (co.monthlyHistory.last?.revenue ?? 0) / 4.33) } ?? 0
        let big: Bool = new > old && ((total > 0 && newTotal > total * 2) || (weekRevenue > 0 && newTotal > weekRevenue * 0.25))
        if big {
            pending = PendingAction(title: "Spend \(cur.tidyDisplay(newTotal)) a week on marketing?",
                                    message: "\(ch.name) at \(cur.tidyDisplay(new)) a week: \(cur.tidyDisplay(newTotal - total)) a week more than now, from company cash.",
                                    button: "Spend it", alwaysAsk: true, tone: .warning, icon: "megaphone") { commit(ch, new, undo: old, cur: cur) }
        } else {
            commit(ch, new, undo: old, cur: cur)
        }
    }

    /// Applies the budget (0 stops it). A refusal (lock, chain) is a toast; a change is a banner whose tap puts the old budget back.
    private func commit(_ ch: MarketingChannel, _ budget: Double, undo old: Double, cur: Currency) {
        let id: Int = companyID
        let channel: String = ch.id
        let r = store.act { $0.setCampaign(companyID: id, channel: channel, weeklyBudget: budget, weeks: nil) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why.prefix(1).uppercased() + why.dropFirst(), tone: "warn"); return }
        guard r != nil else { return }
        let text: String = budget > 0 ? ch.name + " at " + cur.tidyDisplay(budget) + " a week" : ch.name + " stopped"
        let s: GameStore = store
        s.banners.post(BannerItem(key: "mkt-undo-" + channel, source: "Marketing", title: text, body: "Tap to undo", glyph: Glyph.opsMega, severity: 1, lifetime: 6,
                                  target: .place("Undo", {
            _ = s.act { $0.setCampaign(companyID: id, channel: channel, weeklyBudget: old, weeks: nil) }
            s.show(old > 0 ? "Back to \(cur.tidyDisplay(old)) a week" : ch.name + " stopped again", tone: "n")
        })))
    }
}
