import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Item page blocks for made goods with a bill of materials, projects and bids, titles with a sales curve, subscriptions and the fish cycle (salmon,
/// furniture, factory, start-up, game studio, web agency). Draws nothing for an item that is not one of these.
struct IndustrialItemBlocks: View {
    var engine: GameEngine
    var companyID: Int
    var itemID: String
    var currency: Currency

    var body: some View {
        if let f = IndustrialItems.facts(engine.state, companyID: companyID, itemID: itemID, data: engine.data) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if !f.lines.isEmpty { costBlock(f) }
                switch f.kind {
                case .stock, .order: productionBlock(f)
                case .project: projectBlock(f)
                case .title: titleBlock(f)
                case .subscription: subscriptionBlock(f)
                case .fish: fishBlock(f)
                case .service: serviceBlock(f)
                }
            }
        }
    }

    private func hoursText(_ minutes: Int) -> String {
        minutes >= 120 ? String(format: "%.1f hours", Double(minutes) / 60) : "\(minutes) min"
    }

    private func costBlock(_ f: IndustrialItems.Facts) -> some View {
        TeamGroup("What it is made of") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    ForEach(Array(f.lines.enumerated()), id: \.offset) { n, line in
                        FlatRow(label: line.name, value: itemAmount(line.amount, currency), sub: "each \(f.unitLabel)", rule: n > 0)
                    }
                    if f.scrapCost > 0 { FlatRow(label: "Scrap and waste", value: itemAmount(f.scrapCost, currency), sub: String(format: "%.0f%% of units", f.scrap * 100)) }
                    FlatRow(label: "Cost each", value: itemAmount(f.unitCost, currency))
                }
            }
        }
    }

    private func productionBlock(_ f: IndustrialItems.Facts) -> some View {
        let made: String = f.kind == .order ? "Made to order" : "Made for stock"
        let load: String = f.maxPerWeek > 0 ? String(format: "%.0f of %.0f a week", f.weeklyUnits, f.maxPerWeek) : String(format: "%.0f a week", f.weeklyUnits)
        let labour: String = f.labourMinutes > 0 ? hoursText(f.labourMinutes) : "not available"
        return TeamGroup("Production") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: made, value: "\(f.leadDays) days", sub: "from order to ready", rule: false)
                    FlatRow(label: "Labour", value: labour, sub: f.labourCost > 0 ? itemAmount(f.labourCost, currency) + " at your pay" : "")
                    if f.batch > 1 { FlatRow(label: "Batch", value: "\(f.batch)", sub: "made together") }
                    if f.minQty > 0 { FlatRow(label: "Minimum order", value: "\(f.minQty)") }
                    if f.paymentTermsWeeks > 0 { FlatRow(label: "Customers pay after", value: "\(f.paymentTermsWeeks) weeks") }
                    FlatRow(label: "Selling", value: load, sub: f.maxPerWeek > 0 ? String(format: "%.0f%% of your capacity", f.utilisation * 100) : "")
                    if f.kind == .stock {
                        let cover: String = f.weeksOfCover.map { (v: Double) -> String in String(format: "%.1f weeks", v) } ?? "no sales yet"
                        FlatRow(label: "In stock", value: "\(f.stock)", sub: f.onOrder > 0 ? "\(f.onOrder) being made" : "")
                        FlatRow(label: "Cover", value: cover)
                    }
                }
            }
        }
    }

    private func projectBlock(_ f: IndustrialItems.Facts) -> some View {
        let atBid: String = (f.marginAtBid >= 0 ? "profit " : "loss ") + itemAmount(abs(f.marginAtBid), currency)
        let over: String = (f.marginIfOverrun >= 0 ? "profit " : "loss ") + itemAmount(abs(f.marginIfOverrun), currency)
        return TeamGroup("The bid") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Scope", value: String(format: "%.0f hours", f.hours), rule: false)
                    FlatRow(label: "Bid", value: itemAmount(f.bid, currency))
                    FlatRow(label: "Your people's time", value: itemAmount(f.bidLabour, currency))
                    FlatRow(label: "At the bid", value: atBid, tint: f.marginAtBid >= 0 ? Theme.gain : Theme.loss)
                    FlatRow(label: "If it overruns", value: over, sub: String(format: "%.0f%% more hours", f.overrunRisk * 100), tint: f.marginIfOverrun >= 0 ? Theme.gain : Theme.loss)
                    if f.milestones > 0 { FlatRow(label: "Milestones", value: "\(f.milestones)", sub: "paid as each is accepted") }
                }
            }
        }
    }

    private func titleBlock(_ f: IndustrialItems.Facts) -> some View {
        let payback: String = f.paybackWeeks.map { (v: Double) -> String in String(format: "%.0f weeks of sales like now", v) } ?? "no sales yet"
        return TeamGroup("Development and sales curve") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Development", value: String(format: "%.0f hours", f.devHours), sub: itemAmount(f.devCost, currency) + " at your pay", rule: false)
                    FlatRow(label: "Sales halve every", value: String(format: "%.0f weeks", f.halfLifeWeeks), sub: "sold per \(f.unitLabel)")
                    FlatRow(label: "Selling now", value: String(format: "%.1f a week", f.weeklyUnits))
                    FlatRow(label: "Still to earn", value: itemAmount(f.remainingProfit, currency), sub: "profit if sales fade on this curve")
                    FlatRow(label: "Pays back", value: payback)
                }
            }
        }
    }

    private func subscriptionBlock(_ f: IndustrialItems.Facts) -> some View {
        let per: String = f.periodWeeks == 52 ? "a year" : "every \(f.periodWeeks) weeks"
        return TeamGroup("Subscribers") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Subscribers", value: String(format: "%.0f", f.subscribers), rule: false)
                    FlatRow(label: "Monthly recurring revenue", value: itemAmount(f.mrr, currency))
                    FlatRow(label: "Leaving", value: String(format: "%.1f", f.leavingPerPeriod), sub: String(format: "%.1f%% ", f.churnPerPeriod * 100) + per)
                    FlatRow(label: "Cost to serve", value: itemAmount(f.unitCost, currency), sub: "each \(per.replacingOccurrences(of: "every ", with: ""))")
                    FlatRow(label: "Worth over their stay", value: itemAmount(f.lifetimeValue, currency), sub: "margin before they leave")
                    if f.isContract && f.minQty > 0 { FlatRow(label: "Minimum call-off", value: "\(f.minQty)") }
                }
            }
        }
    }

    private func fishBlock(_ f: IndustrialItems.Facts) -> some View {
        let harvest: String = f.weeksToHarvest.map { (v: Double) -> String in String(format: "%.0f weeks", v) } ?? "nothing in the water"
        return TeamGroup("From the pens") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Cycle", value: String(format: "%.0f weeks", f.cycleWeeks), sub: "smolt to harvest", rule: false)
                    FlatRow(label: "In the water", value: String(format: "%.0f tonnes", f.tonnesInWater), sub: String(format: "%.0f fish, %.1f kg each", f.fishInWater, f.averageKilos))
                    FlatRow(label: "Next harvest", value: harvest)
                    FlatRow(label: "Losses", value: String(format: "%.2f%% a week", f.mortalityPerWeek * 100), sub: "feed and density change it")
                    FlatRow(label: "Product from a tonne of fish", value: String(format: "%.0f%%", f.yieldRatio * 100))
                    FlatRow(label: "Selling", value: String(format: "%.1f tonnes a week", f.weeklyUnits), sub: "of this product")
                }
            }
        }
    }

    private func serviceBlock(_ f: IndustrialItems.Facts) -> some View {
        TeamGroup("The job") {
            Card(padding: 14, radius: Theme.Radius.row) {
                VStack(spacing: 0) {
                    FlatRow(label: "Takes", value: f.labourMinutes > 0 ? hoursText(f.labourMinutes) : "by the hour", sub: f.labourCost > 0 ? itemAmount(f.labourCost, currency) + " at your pay" : "", rule: false)
                    FlatRow(label: "Materials and direct cost", value: itemAmount(f.unitCost, currency))
                    FlatRow(label: "Booked", value: String(format: "%.0f a week", f.weeklyUnits))
                }
            }
        }
    }
}
