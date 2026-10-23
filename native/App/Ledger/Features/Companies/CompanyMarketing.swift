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
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Awareness").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(company.awareness.rounded()))%").font(.hero(34))
                        Spacer()
                        let spend = mkt.object.values.reduce(0) { $0 + $1["b"].double }
                        Chip(text: spend > 0 ? cur.short(spend) + " a week" : "No campaigns", tint: spend > 0 ? Theme.gold : Theme.ivoryMuted, symbol: "megaphone.fill")
                    }
                    Meter(label: "People who know about you", value: company.awareness)
                    Text("Marketing builds awareness, which fades every week. Results vary: some channels pay off well, some do little.").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                }
            }
            CompanyWaysToSell(engine: engine, company: company)
            ForEach(channels, id: \.id) { ch in
                let running = mkt[ch.id]
                let budget = running.isNull ? 0 : running["b"].double
                Card {
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
                        Text(ch.note).font(.caption).foregroundStyle(Theme.ivoryMuted)
                        if budget > 0, !running["lock"].isNull, Double(engine.state.week) < running["lock"].double {
                            Text("Committed for \(Int(running["lock"].double) - engine.state.week) more weeks").font(.caption2).foregroundStyle(Theme.ivoryFaint)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                Button("Off") { set(ch.id, 0) }.buttonStyle(QuietButtonStyle(tint: budget == 0 ? Theme.gold : Theme.ivoryFaint))
                                ForEach(ch.budgets(in: cur), id: \.self) { b in
                                    Button(cur.short(b) + "/wk") { set(ch.id, b) }.buttonStyle(QuietButtonStyle(tint: budget == b ? Theme.gold : Theme.ivoryMuted))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func symbol(_ id: String) -> String {
        ["flyer": "doc.richtext.fill", "google": "magnifyingglass", "meta": "person.2.wave.2.fill", "tiktok": "play.rectangle.fill", "local": "radio.fill",
         "bill": "rectangle.on.rectangle", "seo": "globe", "mail": "envelope.fill", "b2b": "briefcase.fill", "fair": "flag.fill", "ref": "person.line.dotted.person.fill"][id] ?? "megaphone.fill"
    }

    private func set(_ channel: String, _ budget: Double) {
        let r = store.act { $0.setCampaign(companyID: company.id, channel: channel, weeklyBudget: budget) }
        if case .refused(let why)? = r { Haptics.warning(); store.show(why.prefix(1).uppercased() + why.dropFirst(), tone: "warn") } else { Haptics.tap() }
    }
}
