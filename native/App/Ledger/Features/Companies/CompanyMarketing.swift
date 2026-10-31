import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct CompanyMarketing: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    /// The length chosen per channel, in weeks; absent or 0 = until you stop it.
    @State private var length: [String: Int] = [:]
    @State private var pending: PendingAction?
    @State private var open: OpenChannel?

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        let mkt: JSONValue = company.value("mkt")
        let channels: [MarketingChannel] = engine.marketingChannels(companyID: company.id)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            header(cur: cur, mkt: mkt, channels: channels)
            if channels.isEmpty {
                Text("No marketing channels are open to this business yet.").font(.caption).foregroundStyle(Theme.ivoryMuted)
            } else {
                channelTable(channels, cur: cur, mkt: mkt)
            }
            CompanyWaysToSell(engine: engine, company: company)
        }
        .sheet(item: $open) { (o: OpenChannel) in channelSheet(o.id, cur: cur) }
    }

    /// A campaign channel opened in its sheet.
    struct OpenChannel: Identifiable { var id: String }

    /// One row per channel with what it runs at now; a tap opens the small sheet to start, change or stop the campaign.
    private func channelTable(_ channels: [MarketingChannel], cur: Currency, mkt: JSONValue) -> some View {
        SettingsTable(heading: "Campaigns") {
            ForEach(channels, id: \.id) { (ch: MarketingChannel) in
                let budget: Double = mkt[ch.id].isNull ? 0 : mkt[ch.id]["b"].double
                let note: String = ch.isHighVariance ? "Hit or miss" : "Steady"
                SettingsTableRow(title: ch.name, note: note, value: budget > 0 ? cur.tidyShort(budget) + " a week" : "Off",
                                 valueTint: budget > 0 ? Theme.gold : Theme.ivoryMuted, opens: .sheet) { open = OpenChannel(id: ch.id) }
            }
        }
    }

    @ViewBuilder private func channelSheet(_ id: String, cur: Currency) -> some View {
        let mkt: JSONValue = company.value("mkt")
        if let ch = engine.marketingChannels(companyID: company.id).first(where: { $0.id == id }) {
            PeopleSheet(title: ch.name) { channelCard(ch, cur: cur, mkt: mkt) }
                .confirmAction($pending)
                .presentationDetents([.medium, .large])
        }
    }

    private func header(cur: Currency, mkt: JSONValue, channels: [MarketingChannel]) -> some View {
        let spend: Double = mkt.object.values.reduce(0) { $0 + $1["b"].double }
        let running: Int = channels.filter { (c: MarketingChannel) -> Bool in
            let m: JSONValue = mkt[c.id]
            return !m.isNull && m["b"].double > 0
        }.count
        let spendText: String = spend > 0 ? cur.tidyShort(spend) + " a week" : "No campaigns"
        let plural: String = running == 1 ? "" : "s"
        return VStack(alignment: .leading, spacing: 6) {
            Text("AWARENESS").capsLabel()
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(company.awareness.rounded()))%").font(.hero(34)).foregroundStyle(Theme.ivory)
                        Spacer()
                        Chip(text: spendText, tint: spend > 0 ? Theme.gold : Theme.ivoryMuted)
                    }
                    Text("People who know about you. \(running) campaign\(plural) running.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    Text("Marketing builds awareness, which fades every week. Results vary: some channels pay off well, some do little.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
        }
    }

    private func channelCard(_ ch: MarketingChannel, cur: Currency, mkt: JSONValue) -> some View {
        let running: JSONValue = mkt[ch.id]
        let budget: Double = running.isNull ? 0 : running["b"].double
        let plan: CampaignPlan? = engine.campaignPlan(companyID: company.id, channel: ch.id, weeklyBudget: 1, weeks: nil)
        return Card {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.m) {
                    IconCircle(glyph: glyph(ch.id), size: 36, tint: budget > 0 ? Theme.gold : Theme.ivoryMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ch.name).font(.bodyText.weight(.semibold))
                        HStack(spacing: 6) {
                            if budget > 0 { Chip(text: "Running", tint: Theme.gain) }
                            if ch.isHighVariance { Chip(text: "Hit or miss", tint: Theme.caution) }
                        }
                    }
                    Spacer()
                }
                Text(ch.note.tidyMoney).font(.caption).foregroundStyle(Theme.ivoryMuted)
                if budget > 0 { runningNotes(ch, running: running) }
                if plan?.runByChain == true {
                    Text("Run by the chain: it sets this channel's budget for the store.").font(.caption2).foregroundStyle(Theme.caution)
                } else if let why = plan?.blocked {
                    Text(why.prefix(1).uppercased() + why.dropFirst() + ".").font(.caption2).foregroundStyle(Theme.caution)
                } else {
                    controls(ch, cur: cur, budget: budget)
                }
            }
        }
    }

    @ViewBuilder private func runningNotes(_ ch: MarketingChannel, running: JSONValue) -> some View {
        if !running["lock"].isNull, Double(engine.state.week) < running["lock"].double {
            Text("Committed for \(Int(running["lock"].double) - engine.state.week) more weeks").font(.caption2).foregroundStyle(Theme.ivoryFaint)
        }
        let end: JSONValue = company.value("mktEnd")[ch.id]
        let endText: String = end.isNull ? "No end date: it runs until you stop it." : "Ends in \(max(0, Int(end.double) - engine.state.week)) weeks."
        Text(endText).font(.caption2).foregroundStyle(Theme.ivoryFaint)
    }

    @ViewBuilder private func controls(_ ch: MarketingChannel, cur: Currency, budget: Double) -> some View {
        let lengths: [Int] = Marketing.lengthChoices(ch).filter { $0 > 0 } + [0]
        let budgets: [Double] = ch.budgets(in: cur).filter { $0 > 0 }
        Text("Length").font(.caption).foregroundStyle(Theme.ivoryMuted)
        WrapRow {
            Group {
                ForEach(lengths, id: \.self) { (w: Int) in
                    OptionPill(title: w == 0 ? "Until I stop it" : "\(w) weeks", on: (length[ch.id] ?? 0) == w) { length[ch.id] = w }
                }
            }
        }
        Text("Weekly budget (tap to start; a confirmation shows the total)").font(.caption).foregroundStyle(Theme.ivoryMuted)
        WrapRow {
            Group {
                OptionPill(title: "Off", on: budget == 0) { ask(ch, 0, cur) }
                ForEach(budgets, id: \.self) { (b: Double) in
                    OptionPill(title: cur.tidyShort(b) + "/wk", on: budget == b) { ask(ch, b, cur) }
                }
            }
        }
    }

    /// Stopping a campaign is immediate; starting or changing one asks first, with what it commits you to and the odds.
    private func ask(_ ch: MarketingChannel, _ budget: Double, _ cur: Currency) {
        if budget <= 0 { set(ch.id, 0, nil); return }
        let weeks = length[ch.id] ?? 0
        guard let plan = engine.campaignPlan(companyID: company.id, channel: ch.id, weeklyBudget: budget, weeks: weeks) else { return }
        var lines = ["\(cur.tidyShort(budget)) a week, paid in advance each week."]
        if let total = plan.totalCost, let w = plan.weeks { lines.append("\(w) weeks, \(cur.tidyShort(total)) in all.") } else { lines.append("No end date: it keeps costing until you stop it.") }
        if plan.lockedWeeks > 0 { lines.append("You cannot cut it for the first \(plan.lockedWeeks) weeks.") }
        if plan.nearCapacity { lines.append("You are near your limit: more awareness will not become more sales.") }
        lines.append(ch.isHighVariance ? "Hit or miss: it can do much less than it costs." : "Results vary: it raises awareness, it does not promise customers.")
        pending = PendingAction(title: "Run \(ch.name)?", message: lines.joined(separator: "\n"), button: "Start campaign") { set(ch.id, budget, weeks) }
    }

    private func glyph(_ id: String) -> String {
        let map: [String: String] = ["flyer": Glyph.reports, "google": Glyph.stats, "meta": Glyph.team, "tiktok": Glyph.ventures, "local": Glyph.news,
                                    "bill": Glyph.news, "seo": Glyph.world, "mail": Glyph.inbox, "b2b": Glyph.bank, "fair": Glyph.goals, "ref": Glyph.person, "primetime": Glyph.luxury]
        return map[id] ?? Glyph.market
    }

    private func set(_ channel: String, _ budget: Double, _ weeks: Int?) {
        let r = store.act { $0.setCampaign(companyID: company.id, channel: channel, weeklyBudget: budget, weeks: weeks) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why.prefix(1).uppercased() + why.dropFirst(), tone: "warn") }
        else if r != nil {
            Haptics.tap()
            let cur = engine.currency(for: company)
            store.show(budget <= 0 ? "Campaign stopped." : "Campaign running at \(cur.tidyShort(budget)) a week.", tone: budget <= 0 ? "n" : "good")
        }
    }
}

/// A short outlined choice (a campaign length or budget): the chosen one is washed and outlined in champagne.
private struct OptionPill: View {
    var title: String
    var on: Bool
    var action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous)
        Button {
            Haptics.choose()
            action()
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Theme.ivory : Theme.ivoryMuted)
                .padding(.horizontal, 12).frame(minHeight: 34)
                .background(shape.fill(on ? Theme.goldSelected : Color.clear))
                .overlay(shape.strokeBorder(on ? Theme.gold : Theme.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
