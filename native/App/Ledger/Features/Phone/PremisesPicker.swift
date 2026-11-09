import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Simulation

/// Where the new company works: rent or buy one of the places the engine lists, with what it costs up front. Shared by starting on your own
/// and starting a unit under a brand, so the choice looks and reads the same in both.
struct PremisesPicker: View {
    @EnvironmentObject var store: GameStore
    var plan: NewCompanyPlan
    var cur: Currency
    @Binding var rentIndex: Int?
    @Binding var buying: Bool

    var body: some View {
        CardSection("Premises") {
            switch plan.premisesKind {
            case .none:
                Text("This trade needs no fixed premises, so there is no rent to pay.").popupText(.subtitle)
            case .home:
                Text("It starts at home: no rent, no deposit. Once the team reaches four people morale and quality slip every week until you move into a workshop or office. You can do that later under Operations.")
                    .popupText(.subtitle)
            case .place:
                placeChoices
            }
        }
    }

    @ViewBuilder private var placeChoices: some View {
        let chosen = rentIndex ?? plan.standardIndex
        ForEach(plan.options) { o in
            ChoiceCard(title: o.name, subtitle: "\(Int(o.squareMetres)) m² · \(cur.tidyShort(o.monthlyRent)) a month · \(o.landlord)",
                       trailing: cur.tidyShort(buying && o.index == chosen ? o.buyUpfront : o.rentUpfront) + " up front", selected: o.index == chosen, thumb: premisesThumb(o)) {
                rentIndex = o.index
                if !o.canBuy { buying = false }
            }
        }
        if let o = plan.options.first(where: { $0.index == chosen }) {
            let modes: [Bool] = o.canBuy ? [false, true] : [false]
            SegmentedPill(items: modes, title: { $0 ? "Buy" : "Rent" }, selection: Binding(get: { buying }, set: { buying = $0; if rentIndex == nil { rentIndex = chosen } }))
            Text(modeNote(o)).popupText(.caption)
            if rentIndex == nil { Text("Nothing picked: the standard middle place is rented.").popupText(.caption) }
        }
    }

    /// The picture slot of a place: the kind of premises this trade works in (office, shop, kitchen and so on).
    private func premisesThumb(_ o: NewCompanyPlan.PremisesOption) -> ThumbSpec {
        let kind: String = store.engine?.data.catalog[plan.tradeID]?.premisesKind ?? "office"
        return ThumbSpec(kind: .premisesPhoto, key: ArtLibrary.premisesKey(kind: kind, squareMetres: o.squareMetres), glyph: Glyph.home, shape: .wide)
    }

    private func modeNote(_ o: NewCompanyPlan.PremisesOption) -> String {
        if buying {
            return "Buying: \(cur.tidyShort(o.purchasePrice)). You pay \(cur.tidyShort(o.downPayment)) down and \(cur.tidyShort(o.fitOut)) to fit it out; the rest is a 15-year commercial mortgage. You own the place and pay no rent, but the money is tied up."
        }
        return "Renting: a deposit of \(cur.tidyShort(o.deposit)) (three months, returned when you leave) and \(cur.tidyShort(o.fitOut)) to fit it out. Then \(cur.tidyShort(o.monthlyRent)) a month. Moving later is possible."
    }
}
