import SwiftUI
import GameCore
import Businesses
import Simulation

/// The "Ways to sell" rows (platform, memberships, on-call service, add-ons) inside Marketing: an icon, the name and the engine's
/// fee, commission and set-up line, and a switch. Read from `engine.waysToSell`; switching goes through `setWayToSell`.
struct CompanyWaysToSell: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        let rows = engine.waysToSell(companyID: company.id)
        if !rows.isEmpty {
            let onCount: Int = rows.filter { $0.isOn }.count
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Text("WAYS TO SELL").capsLabel()
                    Spacer()
                    Text("\(onCount) on").font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint)
                }
                ForEach(rows, id: \.kind) { r in
                    wayRow(r)
                }
                Text("Platforms take a commission on the customers they bring, memberships cost perks, and some add-ons have a set-up fee the first time.")
                    .font(.system(size: 11)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func wayRow(_ r: SalesWays.Row) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        let binding = Binding<Bool>(get: { r.isOn }, set: { _ in toggle(r) })
        return HStack(spacing: 12) {
            IconCircle(glyph: Glyph.market, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name.tidyText).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.ivory)
                if !r.detail.isEmpty {
                    Text(r.detail.tidyMoney).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if r.canSwitch {
                Toggle("", isOn: binding).labelsHidden().tint(Theme.gold)
            } else {
                Chip(text: r.isOn ? "On" : "Automatic", tint: r.isOn ? Theme.gain : Theme.ivoryMuted)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.surface))
        .overlay(shape.strokeBorder(r.isOn ? Theme.gold : Theme.border, lineWidth: 1))
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
