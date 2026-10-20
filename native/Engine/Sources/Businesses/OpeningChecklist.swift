import Foundation
import GameCore
import Countries
import Finance

/// What a new company needs before it can open. Original: `openChecklist`, `openCompany`, `tryAutoOpen`.
public enum OpeningChecklist {
    public struct Item: Equatable, Identifiable {
        public var id: String
        public var title: String
        public var isDone: Bool
        public var detail: String
    }

    /// Cash needed for the first stock. Original: `initialStockCost`.
    public static func initialStockCost(_ co: Company, _ bd: Trade, _ w: World) -> Double {
        guard let stock = bd.trait("stock"), stock != 0 else { return 0 }
        let city = w.city(co)
        let dem = city?.demand ?? 1, price = city?.price ?? 1
        let weekly = (bd.normalDemand == 0 ? 1 : bd.normalDemand) * bd.ticket * max(0.05, bd.costOfSales == 0 ? 0.3 : bd.costOfSales) * min(1, dem + 0.1) * price
        return jsRound(weekly * stock / 7 * max(0.5, co.size) * 0.6)
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
                            detail: st["st"].string == "applied" ? "In progress" : (fee > 0 ? "Fee \(w.currency(co).display(fee))" : "Free")))
        }
        if !["rent", "fin", "energy"].contains(bd.family) {
            if let kind = bd.premisesKind, kind != "none", kind != "home" {
                let m2 = co.value("prem")["m2"].double
                out.append(Item(id: "prem", title: "Premises", isDone: m2 > 0, detail: m2 > 0 ? "\(Int(m2)) m²" : "Not chosen"))
            }
            for e in bd.equipment where e.isRequired {
                out.append(Item(id: "eq:\(e.id)", title: e.name, isDone: CapacityModel.equipmentAvailable(co, e) >= 1, detail: ""))
            }
        }
        out += RentalFinance.checklist(co, bd, w)
        out += SpecialFamilies.checklist(co, bd, w)
        let stock = initialStockCost(co, bd, w)
        if stock > 0 {
            let ok = co.cash >= stock
            out.append(Item(id: "stockcash", title: "Cash for opening stock", isDone: ok,
                            detail: ok ? "Ready" : "Needs \(w.currency(co).display(stock)) in the company"))
        }
        return out
    }

    public enum OpenResult: Equatable { case ok, missing, needsStockCash(Double) }

    /// Open the company if everything is in place. Original: `openCompany`.
    @discardableResult
    public static func open(_ s: inout GameState, companyIndex i: Int, data: GameData) -> OpenResult {
        let co = s.companies[i]
        guard let bd = data.catalog[co.type] else { return .missing }
        let w = World(state: s, data: data)
        if items(co, bd, w).contains(where: { !$0.isDone }) { return .missing }
        if bd.family == "venue" && bd.hasTrait("sub") {
            var fm = co.value("fm"); fm["memb"] = .number(bd.normalDemand * 0.18 * (w.city(co)?.demand ?? 1)); s.companies[i].set("fm", fm)
        }
        let stock = initialStockCost(co, bd, w)
        if stock > 0 {
            if co.cash < stock { return .needsStockCash(stock) }
            Payments.companyPays(&s, companyID: co.id, amount: stock, category: nil, label: "Opening stock")
            s.companies[i].inventory += stock
        }
        s.companies[i].status = .open
        s.companies[i].openedWeek = s.week
        s.note("\(s.companies[i].name) is open for business!", tone: "good", companyID: co.id)
        return .ok
    }

    /// Open by itself as soon as the last requirement is met. Original: `tryAutoOpen`.
    @discardableResult
    public static func tryAutoOpen(_ s: inout GameState, companyIndex i: Int, data: GameData) -> Bool {
        guard s.companies[i].status == .setup, let bd = data.catalog[s.companies[i].type] else { return false }
        let w = World(state: s, data: data)
        if items(s.companies[i], bd, w).contains(where: { !$0.isDone }) { return false }
        return open(&s, companyIndex: i, data: data) == .ok
    }
}
