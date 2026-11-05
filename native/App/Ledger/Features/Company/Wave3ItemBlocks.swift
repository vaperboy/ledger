import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Item page blocks for made goods with recipes: the recipe with the cost of each input, food cost percent, spoilage, production and the allergen sheet.
struct Wave3RecipeBlock: View {
    var card: Wave3Recipes.Card
    var cur: Currency

    private func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            recipeGroup
            if !card.boughtIn { productionGroup }
            documentGroup
        }
    }

    private var recipeGroup: some View {
        let sub: String = card.supplierDiscount > 0 ? "after \(pct(card.supplierDiscount)) off from \(card.supplierName ?? "your supplier")" : (card.supplierName ?? "no supplier chosen")
        return TeamGroup(card.boughtIn ? "Bought in" : "Recipe, cost of one unit") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    ForEach(card.lines.indices, id: \.self) { (k: Int) in
                        FlatRow(label: card.lines[k].name, value: itemAmount(card.lines[k].cost * (1 - card.supplierDiscount), cur), sub: card.lines[k].qty, rule: k > 0)
                    }
                    FlatRow(label: "Inputs", value: itemAmount(card.inputCost, cur), sub: sub)
                    FlatRow(label: "Spoilage and write-offs", value: itemAmount(card.spoilageCost, cur), sub: card.shelfDays > 0 ? "keeps \(card.shelfDays) days" : "")
                    FlatRow(label: "Cost of one unit", value: itemAmount(card.unitCost, cur))
                    FlatRow(label: "Food cost at this price", value: pct(card.foodCostPercent), tint: card.foodCostPercent > 0.4 ? Theme.loss : nil)
                }
            }
        }
    }

    private var productionGroup: some View {
        let over: Bool = card.capacityUse > 1
        return TeamGroup("Production") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Batch", value: "\(card.batch)", sub: String(format: "%.0f a shift", card.perShift), rule: false)
                    FlatRow(label: "Work in a unit", value: String(format: "%.1f minutes", card.labourMinutes))
                    if card.leadDays > 0 { FlatRow(label: "Time to make or age", value: card.leadDays >= 14 ? "\(card.leadDays / 7) weeks" : "\(card.leadDays) days") }
                    FlatRow(label: "Capacity", value: String(format: "%.0f a week", card.capacityPerWeek), sub: String(format: "%.0f%% used", card.capacityUse * 100), tint: over ? Theme.loss : nil)
                    if !card.seasonNote.isEmpty { FlatRow(label: "Season", value: card.seasonNote) }
                }
            }
        }
    }

    @ViewBuilder private var documentGroup: some View {
        if !card.allergens.isEmpty {
            TeamGroup("Allergen sheet") {
                Card(padding: 14, radius: Theme.Radius.row) {
                    FlatRow(label: card.recipeName, value: card.allergens, rule: false)
                }
            }
        }
    }
}
