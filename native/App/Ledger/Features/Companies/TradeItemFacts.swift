import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct TradeFact: Identifiable, Equatable {
    var label: String
    var value: String
    var tint: Color? = nil
    var id: String { label }

    init(_ label: String, _ value: String, tint: Color? = nil) {
        self.label = label
        self.value = value
        self.tint = tint
    }
}

enum TradeItemFactRows {
    static let limit = 6

    static func rows(_ e: GameEngine, companyID: Int, page: ItemPageData, price: Double, cur: Currency) -> [TradeFact] {
        let own: [TradeFact] = trade(e, companyID: companyID, itemID: page.item.id, price: price, cur: cur)
        var extra: [TradeFact] = []
        if let r = page.record {
            if r.reserved > 0 { extra.append(TradeFact("Reserved", "\(r.reserved) for customers")) }
            if !r.history.isEmpty {
                let total: Double = r.history.reduce(0) { (a: Double, w: ItemModels.Week) -> Double in a + w.profit }
                extra.append(TradeFact("So far", result(total, cur) + " in \(r.history.count.weeksText)", tint: tint(total)))
            }
        }
        return Array((own.prefix(limit - extra.count) + extra).prefix(limit))
    }

    static func plans(_ page: ItemPageData) -> [String] {
        Array((page.record?.plans ?? []).prefix(2).map { (p: ItemModels.Plan) -> String in p.text })
    }

    private static func trade(_ e: GameEngine, companyID: Int, itemID: String, price: Double, cur: Currency) -> [TradeFact] {
        if let c = FoodRecipes.card(e.state, companyID: companyID, itemID: itemID, price: price, data: e.data) { return food(c, cur) }
        if let f = IndustrialItems.facts(e.state, companyID: companyID, itemID: itemID, data: e.data) { return industrial(f, cur) }
        if let u = ProfessionalServices.economics(e.state, companyID: companyID, itemID: itemID, data: e.data) { return professional(u, cur) }
        if let f = AppointmentServices.facts(e.state, companyID: companyID, itemID: itemID, data: e.data) { return appointment(f, cur) }
        if let f = JobContracts.facts(e.state, companyID: companyID, itemID: itemID, data: e.data) { return job(f, cur) }
        if let u = RentalUnits.economics(e.state, companyID: companyID, itemID: itemID, data: e.data) { return rental(u, cur) }
        if let u = VenueItems.economics(e.state, companyID: companyID, itemID: itemID, data: e.data) { return venue(u, cur) }
        if let i = TransportItems.info(e.state, companyID: companyID, itemID: itemID, data: e.data) { return transport(i, cur) }
        if let u = FinanceItems.economics(e.state, companyID: companyID, itemID: itemID, data: e.data) { return finance(u, cur) }
        return []
    }

    private static func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
    private static func count(_ v: Double) -> String { String(format: "%.0f", v) }
    private static func weeksOf(_ v: Double?) -> String { v.map { (w: Double) -> String in String(format: "%.1f weeks", w) } ?? "no sales yet" }
    private static func result(_ v: Double, _ cur: Currency) -> String { (v >= 0 ? "profit " : "loss ") + itemAmount(abs(v), cur) }
    private static func tint(_ v: Double) -> Color { v >= 0 ? Theme.gain : Theme.loss }
    private static func load(_ units: Double, _ cap: Double) -> String {
        cap > 0 ? String(format: "%.0f of %.0f a week", units, cap) : String(format: "%.0f a week", units)
    }
    private static func stockLine(_ stock: Int, _ onOrder: Int) -> String { onOrder > 0 ? "\(stock), \(onOrder) on order" : "\(stock)" }
    private static func minutesText(_ m: Int) -> String {
        if m >= 120 && m % 60 == 0 { return "\(m / 60) hours" }
        return "\(m) min"
    }
    private static func hoursText(_ h: Double) -> String { h < 10 ? String(format: "%.1f h", h) : String(format: "%.0f h", h) }
    private static func daysText(_ d: Double) -> String {
        if d < 1 { return "same day" }
        if d < 14 { return String(format: "%.0f days", d) }
        return String(format: "%.0f weeks", d / 7)
    }

    private static func food(_ c: FoodRecipes.Card, _ cur: Currency) -> [TradeFact] {
        var out: [TradeFact] = []
        let names: [String] = c.lines.map { (l: FoodRecipes.Line) -> String in l.name }
        if c.boughtIn {
            out.append(TradeFact("Bought in", c.supplierName ?? "no supplier chosen"))
        } else if !names.isEmpty {
            out.append(TradeFact("Recipe", names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3)" : "")))
        }
        out.append(TradeFact("Inputs", itemAmount(c.inputCost, cur) + (c.supplierDiscount > 0 ? ", \(pct(c.supplierDiscount)) off" : "")))
        out.append(TradeFact("Food cost", pct(c.foodCostPercent), tint: c.foodCostPercent > 0.4 ? Theme.loss : nil))
        out.append(TradeFact("Spoilage", itemAmount(c.spoilageCost, cur) + (c.shelfDays > 0 ? ", keeps \(c.shelfDays) days" : "")))
        if !c.boughtIn {
            out.append(TradeFact("Capacity", String(format: "%.0f a week, %.0f%% used", c.capacityPerWeek, c.capacityUse * 100), tint: c.capacityUse > 1 ? Theme.loss : nil))
        }
        if !c.allergens.isEmpty { out.append(TradeFact("Allergens", c.allergens)) }
        return out
    }

    private static func industrial(_ f: IndustrialItems.Facts, _ cur: Currency) -> [TradeFact] {
        var out: [TradeFact] = []
        switch f.kind {
        case .stock, .order:
            out.append(TradeFact(f.kind == .order ? "Made to order" : "Made for stock", "\(f.leadDays) days"))
            out.append(TradeFact("Selling", load(f.weeklyUnits, f.maxPerWeek) + (f.maxPerWeek > 0 ? ", " + pct(f.utilisation) : ""), tint: f.utilisation > 1 ? Theme.loss : nil))
            out.append(TradeFact("Labour", f.labourMinutes > 0 ? minutesText(f.labourMinutes) : "none"))
            if f.kind == .stock {
                out.append(TradeFact("In stock", stockLine(f.stock, f.onOrder)))
                out.append(TradeFact("Cover", weeksOf(f.weeksOfCover)))
            } else if f.paymentTermsWeeks > 0 {
                out.append(TradeFact("Customers pay after", "\(f.paymentTermsWeeks) weeks"))
            }
        case .project:
            out.append(TradeFact("Scope", String(format: "%.0f hours", f.hours)))
            out.append(TradeFact("Bid", itemAmount(f.bid, cur)))
            out.append(TradeFact("At the bid", result(f.marginAtBid, cur), tint: tint(f.marginAtBid)))
            out.append(TradeFact("If it overruns", result(f.marginIfOverrun, cur), tint: tint(f.marginIfOverrun)))
            if f.milestones > 0 { out.append(TradeFact("Milestones", "\(f.milestones)")) }
        case .title:
            out.append(TradeFact("Development", String(format: "%.0f hours", f.devHours)))
            out.append(TradeFact("Selling now", String(format: "%.1f a week", f.weeklyUnits)))
            out.append(TradeFact("Sales halve every", String(format: "%.0f weeks", f.halfLifeWeeks)))
            out.append(TradeFact("Still to earn", itemAmount(f.remainingProfit, cur)))
            out.append(TradeFact("Pays back", f.paybackWeeks.map { (w: Double) -> String in String(format: "%.0f weeks", w) } ?? "no sales yet"))
        case .subscription:
            out.append(TradeFact("Subscribers", count(f.subscribers)))
            out.append(TradeFact("Recurring revenue", itemAmount(f.mrr, cur)))
            out.append(TradeFact("Leaving", String(format: "%.1f, %.1f%% a period", f.leavingPerPeriod, f.churnPerPeriod * 100)))
            out.append(TradeFact("Worth over their stay", itemAmount(f.lifetimeValue, cur)))
        case .fish:
            out.append(TradeFact("Cycle", String(format: "%.0f weeks", f.cycleWeeks)))
            out.append(TradeFact("In the water", String(format: "%.0f tonnes", f.tonnesInWater)))
            out.append(TradeFact("Next harvest", f.weeksToHarvest.map { (w: Double) -> String in String(format: "%.0f weeks", w) } ?? "nothing in the water"))
            out.append(TradeFact("Losses", String(format: "%.2f%% a week", f.mortalityPerWeek * 100)))
            out.append(TradeFact("Selling", String(format: "%.1f tonnes a week", f.weeklyUnits)))
        case .service:
            out.append(TradeFact("Takes", f.labourMinutes > 0 ? minutesText(f.labourMinutes) : "by the hour"))
            out.append(TradeFact("Direct cost", itemAmount(f.unitCost, cur)))
            out.append(TradeFact("Booked", String(format: "%.0f a week", f.weeklyUnits)))
        }
        return out
    }

    private static func professional(_ u: ProfessionalServices.Economics, _ cur: Currency) -> [TradeFact] {
        var out: [TradeFact] = []
        if u.isGoods {
            out.append(TradeFact("In stock", stockLine(u.stock, u.onOrder)))
            out.append(TradeFact("Clients", u.clientLabel))
            return out
        }
        out.append(TradeFact("Done by", u.roleLabel))
        out.append(TradeFact("Hours sold", u.capacityHours > 0 ? String(format: "%.0f of %.0f a week", u.billedHours, u.capacityHours) : String(format: "%.0f a week", u.billedHours)))
        if let x = u.utilisation { out.append(TradeFact("Utilisation", pct(min(x, 1)))) }
        out.append(TradeFact("Booked ahead", "\(u.leadDays) days"))
        out.append(TradeFact("Break-even", itemAmount(u.breakEvenHourly, cur) + " an hour"))
        if let n = u.clients { out.append(TradeFact("Retainer clients", count(n))) }
        if u.writeOffShare > 0 { out.append(TradeFact("Written off", itemAmount(u.weeklyWriteOff, cur) + " a week", tint: Theme.loss)) }
        return out
    }

    private static func appointment(_ f: AppointmentServices.Facts, _ cur: Currency) -> [TradeFact] {
        var out: [TradeFact] = []
        if f.model == .stk {
            out.append(TradeFact("In stock", stockLine(f.stock, f.onOrder)))
            out.append(TradeFact("Cover", weeksOf(f.weeksOfCover)))
            out.append(TradeFact("Sold a week", count(f.weeklyUnits)))
            return out
        }
        out.append(TradeFact("Takes", minutesText(f.minutes) + (f.seats > 1 ? ", \(f.seats) at once" : "")))
        out.append(TradeFact("Needs", f.skill + (f.resource.isEmpty ? "" : ", " + f.resource)))
        out.append(TradeFact("Booked", load(f.weeklyUnits, f.maxPerWeek) + (f.maxPerWeek > 0 ? ", " + pct(f.utilisation) : "")))
        out.append(TradeFact("No-shows", String(format: "%.1f%%", f.noShowRate * 100) + (f.remindersOn ? ", reminders on" : ""), tint: f.noShowRate > 0.1 ? Theme.loss : nil))
        if let h = f.profitPerResourceHour { out.append(TradeFact("Per room or crew hour", result(h, cur), tint: tint(h))) }
        if f.isRecurring { out.append(TradeFact(f.isContract ? "Contracts" : "Members", count(f.members))) }
        return out
    }

    private static func job(_ f: JobContracts.Facts, _ cur: Currency) -> [TradeFact] {
        var out: [TradeFact] = []
        if f.model == .stk {
            out.append(TradeFact("In stock", stockLine(f.stock, f.onOrder)))
            out.append(TradeFact("Cover", weeksOf(f.weeksOfCover)))
            out.append(TradeFact("Sold a week", count(f.weeklyJobs)))
            return out
        }
        out.append(TradeFact("Crew", "\(f.crewSize) " + (f.crewSize == 1 ? "person" : "people") + (f.needsVehicle ? " and a vehicle" : "") + ", " + hoursText(f.hours)))
        out.append(TradeFact("Lead time", daysText(Double(f.leadDays))))
        out.append(TradeFact("Backlog ahead", String(format: "%.1f weeks", f.backlogWeeks)))
        out.append(TradeFact("Booked", load(f.weeklyJobs, f.maxPerWeek)))
        out.append(TradeFact("Each job", result(f.profit, cur), tint: tint(f.profit)))
        if f.warrantyRate > 0 { out.append(TradeFact("Callbacks", itemAmount(f.callbackCostPerWeek, cur) + " a week", tint: Theme.loss)) }
        return out
    }

    private static func rental(_ u: RentalUnits.UnitEconomics, _ cur: Currency) -> [TradeFact] {
        [
            TradeFact("Units", count(u.units)),
            TradeFact("Rented last week", String(format: "%.0f of %.0f", u.rented, u.capacity) + " per " + u.per),
            TradeFact("Occupancy", pct(u.occupancy)),
            TradeFact("Booked ahead", "\(u.booked)"),
            TradeFact("Break-even rate", itemAmount(u.breakEvenRate, cur) + " per " + u.per),
            TradeFact("This unit now", result(u.weeklyProfit, cur) + " a week", tint: tint(u.weeklyProfit)),
        ]
    }

    private static func venue(_ u: VenueItems.Economics, _ cur: Currency) -> [TradeFact] {
        var out: [TradeFact] = [TradeFact("Sold last week", count(u.sold) + " per " + u.per)]
        if u.capacity > 0 { out.append(TradeFact("Filled", pct(u.occupancy) + String(format: " of %.0f a week", u.capacity))) }
        if u.isSub { out.append(TradeFact(u.bundleDays > 0 ? "Pass holders" : "Members", count(u.holders) + ", " + pct(u.churnMonthly) + " leave a month")) }
        if u.booked > 0 { out.append(TradeFact("Booked ahead", "\(u.booked)")) }
        out.append(TradeFact("Break-even price", itemAmount(u.breakEvenPrice, cur) + " per " + u.per))
        out.append(TradeFact("This item now", result(u.weeklyProfit, cur) + " a week", tint: tint(u.weeklyProfit)))
        return out
    }

    private static func transport(_ i: TransportItems.Info, _ cur: Currency) -> [TradeFact] {
        let u: RentalUnits.UnitEconomics = i.economics
        var out: [TradeFact] = []
        if i.kind == "service" {
            out.append(TradeFact("Fleet", String(format: "%.1f vehicles, bays or aircraft", u.units)))
            out.append(TradeFact("Load factor", pct(u.occupancy) + String(format: ", %.0f of %.0f sold", u.rented, u.capacity)))
            out.append(TradeFact("Empty at a normal load", pct(i.empty)))
            out.append(TradeFact("Lead time", i.leadDays == 0 ? "on demand" : "\(i.leadDays) days"))
        }
        out.append(TradeFact("Break-even rate", itemAmount(u.breakEvenRate, cur) + " per " + u.per))
        if i.kind == "service" { out.append(TradeFact("This service now", result(u.weeklyProfit, cur) + " a week", tint: tint(u.weeklyProfit))) }
        return out
    }

    private static func finance(_ u: FinanceItems.Econ, _ cur: Currency) -> [TradeFact] {
        var out: [TradeFact] = [
            TradeFact(u.unitWord.capitalized + "s", count(u.units)),
            TradeFact(u.sizeLabel, itemAmount(u.size, cur)),
        ]
        if u.volume > 0 { out.append(TradeFact("Sold a week", count(u.volume))) }
        out.append(TradeFact("Break-even price", itemAmount(u.costPerUnit, cur) + " per " + u.unitWord))
        if u.risk > 0 { out.append(TradeFact(u.riskLabel, itemAmount(u.risk, cur) + " per " + u.unitWord)) }
        if u.reserve > 0 { out.append(TradeFact(u.reserveLabel, itemAmount(u.reserve, cur))) }
        out.append(TradeFact("This line now", result(u.weeklyProfit, cur) + " a week", tint: tint(u.weeklyProfit)))
        return out
    }
}

struct TradeItemFacts: View {
    @Environment(\.outsidePalette) private var P
    var rows: [TradeFact]
    var plans: [String]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: PopupSpace.row) {
            Button {
                Haptics.choose()
                Motion.animate(Motion.quickAnimation) { open.toggle() }
            } label: {
                HStack(alignment: .center, spacing: PopupSpace.row) {
                    Text("Details").popupText(.rowLabel)
                    Spacer(minLength: PopupSpace.row)
                    Text(open ? "Hide" : "Show").popupText(.effect)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("item-details-toggle")
            if open {
                ForEach(rows) { (r: TradeFact) in
                    HStack(alignment: .firstTextBaseline, spacing: PopupSpace.row) {
                        Text(r.label).popupText(.rowLabel)
                        Spacer(minLength: PopupSpace.row)
                        Text(r.value).popupText(.rowValue).foregroundStyle(r.tint ?? P.ink).multilineTextAlignment(.trailing)
                    }
                }
                ForEach(plans, id: \.self) { (t: String) in Text(t).popupText(.caption) }
            }
        }
    }
}
