import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct TechProOwnedView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    var onBuy: (String) -> Void

    var body: some View {
        ShopPage {
            if let e = store.engine, let co = e.state.company(companyID) {
                content(e, co)
            }
        }
        .accessibilityIdentifier("tp-owned")
    }

    @ViewBuilder private func content(_ e: GameEngine, _ co: Company) -> some View {
        let list: [EquipmentMarket.Owned] = e.ownedEquipment(companyID: companyID)
        hero(e, list)
        missingSection(e)
        if list.isEmpty {
            ShopEmptyNote(text: "Nothing bought yet. Browse the store and add items to your basket.", glyph: Glyph.cart)
        } else {
            ShopSection(title: "What you own", trailing: "\(list.count)") {
                LedgerRow(leading: .glyph(Glyph.settings), leadingTint: P.inkSoft, title: "See your equipment",
                          subtitle: "Condition, repairs and selling are on each item", identifier: "tp-open-equipment") {
                    store.openCompany(companyID, section: .operations, part: OpsPart.equipment.rawValue)
                }
            }
        }
    }

    private func hero(_ e: GameEngine, _ list: [EquipmentMarket.Owned]) -> some View {
        let units: Int = list.reduce(0) { (s: Int, o: EquipmentMarket.Owned) -> Int in s + o.units.count + o.vehicles.count }
        let repairs: Int = list.reduce(0) { (s: Int, o: EquipmentMarket.Owned) -> Int in
            s + o.units.filter { (u: EquipmentMarket.UnitRow) -> Bool in u.daysInRepair > 0 }.count + o.vehicles.filter { (v: EquipmentMarket.VehicleRow) -> Bool in v.daysInRepair > 0 }.count
        }
        let h: Double? = e.equipmentHealth(companyID: companyID)
        let note: String = (units == 1 ? "1 unit" : "\(units) units") + (repairs > 0 ? " \u{00B7} \(repairs) in repair" : "") + " \u{00B7} old kit breaks more often"
        return ShopHero(label: "Condition", value: h.map { (x: Double) -> String in Words.level(x * 100, scale: .condition) } ?? "\u{2013}", note: note,
                        noteTint: repairs > 0 ? P.loss : nil, valueTint: h.map { (x: Double) -> Color in tint(x) == P.inkSoft ? P.ink : tint(x) })
    }

    @ViewBuilder private func missingSection(_ e: GameEngine) -> some View {
        let missing: [EquipmentMarket.Need] = e.equipmentNeeds(companyID: companyID).filter { (n: EquipmentMarket.Need) -> Bool in n.need > 0 && n.have + n.leased < n.need }
        if !missing.isEmpty {
            ShopSection(title: "Still needed", trailing: "\(missing.count)") {
                VStack(spacing: 0) {
                    ForEach(Array(missing.enumerated()), id: \.element.id) { (i: Int, n: EquipmentMarket.Need) in
                        if i > 0 { Hairline() }
                        LedgerRow(leading: .glyph(TechCategory.of(n).glyph), leadingTint: n.required ? P.loss : P.caution, title: n.name,
                                  subtitle: "\(Int(saturating: (n.have + n.leased).rounded())) of \(Int(n.need))" + (n.required ? " \u{00B7} required to trade" : ""),
                                  value: "Shop", valueTint: P.accent) { onBuy(n.equipmentID) }
                    }
                }
            }
        }
    }

    private func tint(_ c: Double) -> Color { c >= 0.8 ? P.gain : c >= 0.48 ? P.inkSoft : P.loss }
}
