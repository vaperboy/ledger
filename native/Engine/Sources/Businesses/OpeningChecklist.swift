import Foundation
import GameCore
import Countries
import Finance

public enum OpeningChecklist {
    public struct Item: Equatable, Identifiable {
        public var id: String
        public var title: String
        public var isDone: Bool
        public var detail: String
        public var cost: Double = 0
    }

    static func equipmentCost(_ e: EquipmentSpec, _ co: Company, _ bd: Trade, _ w: World) -> (price: Double, financed: Bool) {
        if let model = e.vehicleModels?.first { return ((w.catalog.tables.vehicles[model]?.price ?? 300000) * w.inflationIndex * 0.2, true) }
        let unit = CompanySetup.equipmentPrice(e, company: co, w)
        return EquipmentMarket.canFinance(e, tradeID: bd.id, total: unit, company: co, w, tables: w.catalog.tables) ? (unit * 0.2, true) : (unit, false)
    }

    static func cheapestPremisesCost(_ co: Company, _ bd: Trade, _ w: World) -> Double? {
        let costs = CompanySetup.listings(for: co, bd, w).compactMap { l in CompanySetup.premisesTerms(co, l, catalog: w.catalog, world: w).map { $0.deposit + $0.fitOut } }
        return costs.min()
    }

    public static func missingCash(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        max(0, items(co, bd, w).filter { !$0.isDone }.reduce(0) { $0 + $1.cost } - max(0, co.cash))
    }

    public static func initialStockCost(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        guard let stock = bd.trait("stock"), stock != 0 else { return 0 }
        let city = w.city(co)
        let dem = city?.demand ?? 1, price = city?.price ?? 1
        let weekly = (bd.normalDemand == 0 ? 1 : bd.normalDemand) * bd.ticket * max(0.05, bd.costOfSales == 0 ? 0.3 : bd.costOfSales) * min(1, dem + 0.1) * price
        return jsRound(weekly * stock / 7 * max(0.5, co.size) * 0.6)
    }

    public static func openingStockShare(_ co: Company) -> Double {
        let v = co.value("flags")["stockShare"]
        return v.isNull ? 1 : clamp(v.double, 0, 1)
    }
    public static func openingStockCost(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        if bd.id == CarDealer.tradeID { return 0 }
        return jsRound(initialStockCost(co, bd, w) * openingStockShare(co))
    }

    public static func items(_ co: Company, _ bd: Trade, _ w: World) -> [Item] {
        var out: [Item] = []
        let country = w.country(co)
        for d in Documents.needed(co, bd, w) where d != "vat_not_applicable" {
            guard let dd = Documents.definition(d, country: country, tables: w.catalog.tables) else { continue }
            let st = co.value("docs")[d]
            let ok = st["st"].string == "ok"
            let fee = Documents.cost(d, company: co, bd, w)
            out.append(Item(id: "doc:\(d)", title: dd.name, isDone: ok,
                            detail: st["st"].string == "applied" ? "In progress" : (fee > 0 ? "Fee \(w.currency(co).display(fee))" : "Free"), cost: st["st"].string == "ok" || st["st"].string == "applied" ? 0 : fee))
        }
        if !["rent", "fin", "energy"].contains(bd.family) {
            if let kind = bd.premisesKind, kind != "none", kind != "home" {
                let m2 = co.value("prem")["m2"].double
                let cheapest = m2 > 0 ? nil : cheapestPremisesCost(co, bd, w)
                out.append(Item(id: "prem", title: "Premises", isDone: m2 > 0, detail: m2 > 0 ? "\(Int(m2)) m²" : (cheapest.map { "From \(w.currency(co).display($0)) up front" } ?? "Not chosen"), cost: cheapest ?? 0))
            }
            for e in bd.equipment where e.isRequired {
                let done = CapacityModel.equipmentCount(co, e) >= 1
                let (price, financed) = done ? (0.0, false) : equipmentCost(e, co, bd, w)
                let how = financed ? "Down payment \(w.currency(co).display(price)), the rest financed" : "From \(w.currency(co).display(price))"
                out.append(Item(id: "eq:\(e.id)", title: e.name, isDone: done, detail: done ? "" : how, cost: price))
            }
        }
        out += RentalFinance.checklist(co, bd, w)
        out += SpecialFamilies.checklist(co, bd, w)
        let stock = openingStockCost(co, bd, w)
        if stock > 0 {
            let ok = co.cash >= stock
            out.append(Item(id: "stockcash", title: "Cash for opening stock", isDone: ok,
                            detail: ok ? "Ready" : "Needs \(w.currency(co).display(stock)) in the company", cost: ok ? 0 : stock))
        }
        return out
    }

    public enum OpenResult: Equatable { case ok, missing, needsStockCash(Double) }

    @discardableResult
    public static func open(_ s: inout GameState, companyIndex i: Int, data: GameData) -> OpenResult {
        let co = s.companies[i]
        guard let bd = data.catalog[co.type] else { return .missing }
        let w = World(state: s, data: data)
        if items(co, bd, w).contains(where: { !$0.isDone }) { return .missing }
        if bd.family == "venue" && bd.hasTrait("sub") {
            var fm = co.value("fm"); fm["memb"] = .number(bd.normalDemand * 0.18 * (w.city(co)?.demand ?? 1)); s.companies[i].set("fm", fm)
        }
        let stock = openingStockCost(co, bd, w)
        if stock > 0 {
            if co.cash < stock { return .needsStockCash(stock) }
            Payments.companyPays(&s, companyID: co.id, amount: stock, category: nil, label: "Opening stock")
            s.companies[i].inventory += stock
        }
        s.companies[i].status = .open
        s.companies[i].openedWeek = s.week
        s.note("\(s.companies[i].name) is open for business.", tone: "good", companyID: co.id)
        return .ok
    }

    @discardableResult
    public static func tryAutoOpen(_ s: inout GameState, companyIndex i: Int, data: GameData) -> Bool {
        guard s.companies[i].status == .setup, let bd = data.catalog[s.companies[i].type] else { return false }
        let w = World(state: s, data: data)
        if items(s.companies[i], bd, w).contains(where: { !$0.isDone }) { return false }
        return open(&s, companyIndex: i, data: data) == .ok
    }
}
