import SwiftUI
import GameCore
import Businesses
import Simulation

/// The "Ways to sell" card (platform, memberships, on-call service, add-ons) inside Marketing. Fees, commission and set-up costs are in
/// each row's detail line, read from `engine.waysToSell`; switching goes through `setWayToSell`.
struct CompanyWaysToSell: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let rows = engine.waysToSell(companyID: company.id)
        if !rows.isEmpty {
            LedgerSection(title: "Ways to sell", trailing: {
                Text("\(rows.filter { $0.isOn }.count) on").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
            }) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.kind) { n, r in
                        if n > 0 { Hairline() }
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.ivory)
                                if !r.detail.isEmpty {
                                    Text(r.detail.tidyMoney).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 8)
                            if r.canSwitch {
                                Button(r.isOn ? "Stop" : "Start") { toggle(r) }.buttonStyle(QuietButtonStyle(tint: r.isOn ? Theme.loss : Theme.gold))
                            } else {
                                Chip(text: r.isOn ? "On" : "Automatic", tint: r.isOn ? Theme.gain : Theme.ivoryMuted)
                            }
                        }.padding(.vertical, 9)
                    }
                    Text("Platforms take a commission on the customers they bring, memberships cost perks, and some add-ons have a set-up fee the first time.")
                        .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
            }
        }
    }

    private func toggle(_ r: SalesWays.Row) {
        let result = store.act { $0.setWayToSell(companyID: company.id, kind: r.kind, on: !r.isOn) }
        switch result {
        case .changed?: Haptics.success(); store.show("\(r.name): \(r.isOn ? "stopped" : "started").", tone: r.isOn ? "n" : "good")
        case .notEnoughCash(let need)?: Haptics.warning(); store.show("Needs \(store.money(need, in: company)) for the set-up.", tone: "warn")
        default: Haptics.warning(); store.show("This cannot be changed.", tone: "warn")
        }
    }
}
