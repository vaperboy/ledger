import SwiftUI
import GameCore
import Businesses
import Simulation

struct CompanyMarketing: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let cur = engine.currency(for: company)
        let mkt = company.value("mkt")
        let channels = engine.marketing.channels.values.filter { $0.onlyInCountry == nil || $0.onlyInCountry == company.countryCode }.sorted { $0.name < $1.name }
        VStack(spacing: Theme.Space.l) {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Awareness")
                    Meter(label: "People who know about you", value: company.awareness)
                    Text("Marketing builds awareness, which fades every week. Results vary: some channels pay off well, some do little.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
            ForEach(channels, id: \.id) { ch in
                let running = mkt[ch.id]
                let budget = running.isNull ? 0 : running["b"].double
                Card {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack {
                            Text(ch.name).font(.system(.headline, design: .default))
                            Spacer()
                            if budget > 0 { Chip(text: "Running", tint: Theme.gain) }
                            if ch.isHighVariance { Chip(text: "Hit or miss", tint: Theme.caution) }
                        }
                        Text(ch.note).font(.caption).foregroundStyle(Theme.ivoryMuted)
                        if budget > 0, !running["lock"].isNull, Double(engine.state.week) < running["lock"].double {
                            Text("Committed for \(Int(running["lock"].double) - engine.state.week) more weeks").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                Button("Off") { set(ch.id, 0) }.buttonStyle(QuietButtonStyle(tint: budget == 0 ? Theme.gold : Theme.ivoryFaint))
                                ForEach(ch.budgetOptions, id: \.self) { b in
                                    Button(cur.short(b) + "/wk") { set(ch.id, b) }.buttonStyle(QuietButtonStyle(tint: budget == b ? Theme.gold : Theme.ivoryMuted))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func set(_ channel: String, _ budget: Double) {
        let r = store.act { $0.setCampaign(companyID: company.id, channel: channel, weeklyBudget: budget) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why.prefix(1).uppercased() + why.dropFirst(), tone: "warn") } else { Haptics.tap() }
    }
}
