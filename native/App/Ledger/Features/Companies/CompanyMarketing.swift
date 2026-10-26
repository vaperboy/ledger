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

    var body: some View {
        let cur: Currency = engine.currency(for: company)
        let mkt: JSONValue = company.value("mkt")
        let channels: [MarketingChannel] = engine.marketingChannels(companyID: company.id)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            header(cur: cur, mkt: mkt, channels: channels)
            CompanyWaysToSell(engine: engine, company: company)
            if channels.isEmpty {
                LedgerSection("Campaigns") { Text("No marketing channels are open to this business yet.").font(.caption).foregroundStyle(Theme.ivoryMuted) }
            }
            ForEach(channels, id: \.id) { ch in
                channelCard(ch, cur: cur, mkt: mkt)
            }
        }
        .confirmAction($pending)
    }

    private func header(cur: Currency, mkt: JSONValue, channels: [MarketingChannel]) -> some View {
        let spend: Double = mkt.object.values.reduce(0) { $0 + $1["b"].double }
        let running: Int = channels.filter { (c: MarketingChannel) -> Bool in
            let m: JSONValue = mkt[c.id]
            return !m.isNull && m["b"].double > 0
        }.count
        let spendText: String = spend > 0 ? cur.tidyShort(spend) + " a week" : "No campaigns"
        let plural: String = running == 1 ? "" : "s"
        return LedgerSection("Awareness") {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(company.awareness.rounded()))%").font(.hero(34))
                    Spacer()
                    Chip(text: spendText, tint: spend > 0 ? Theme.gold : Theme.ivoryMuted, symbol: "megaphone.fill")
                }
                Text("People who know about you. \(running) campaign\(plural) running.").font(.caption).foregroundStyle(Theme.ivoryMuted)
                Text("Marketing builds awareness, which fades every week. Results vary: some channels pay off well, some do little.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
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
                    IconBadge(symbol: symbol(ch.id), tint: budget > 0 ? Theme.gold : Theme.ivoryMuted)
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
                    Label(why.prefix(1).uppercased() + why.dropFirst() + ".", systemImage: "lock.fill").font(.caption2).foregroundStyle(Theme.caution)
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
                    Button(w == 0 ? "Until I stop it" : "\(w) weeks") { length[ch.id] = w }
                        .buttonStyle(QuietButtonStyle(tint: (length[ch.id] ?? 0) == w ? Theme.gold : Theme.ivoryMuted))
                }
            }
        }
        Text("Weekly budget (tap to start; a confirmation shows the total)").font(.caption).foregroundStyle(Theme.ivoryMuted)
        WrapRow {
            Group {
                Button("Off") { ask(ch, 0, cur) }.buttonStyle(QuietButtonStyle(tint: budget == 0 ? Theme.gold : Theme.ivoryFaint))
                ForEach(budgets, id: \.self) { (b: Double) in
                    Button(cur.tidyShort(b) + "/wk") { ask(ch, b, cur) }.buttonStyle(QuietButtonStyle(tint: budget == b ? Theme.gold : Theme.ivoryMuted))
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

    private func symbol(_ id: String) -> String {
        ["flyer": "doc.richtext.fill", "google": "magnifyingglass", "meta": "person.2.wave.2.fill", "tiktok": "play.rectangle.fill", "local": "radio.fill",
         "bill": "rectangle.on.rectangle", "seo": "globe", "mail": "envelope.fill", "b2b": "briefcase.fill", "fair": "flag.fill", "ref": "person.line.dotted.person.fill", "primetime": "tv.fill"][id] ?? "megaphone.fill"
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
