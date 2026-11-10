import Foundation
import GameCore
import Countries
import Finance

public enum PremisesExtras {

    public static func isHomeTrade(_ bd: Trade) -> Bool { bd.premisesKind == "home" }
    public static func placeKind(_ bd: Trade) -> String { bd.raw["prem45"].isNull ? "office" : bd.raw["prem45"][0].string }
    public static func placeWord(_ bd: Trade) -> String { ["office": "office", "industrial": "workshop", "warehouse": "warehouse", "retail": "shop", "clinic": "clinic"][placeKind(bd)] ?? "place" }
    public static func heads(_ co: Company) -> Int { co.staff.count + (co.managerID != nil ? 1 : 0) + (co.managerID == nil && co.ownerHours > 0 ? 1 : 0) }
    public static func onSiteHeads(_ co: Company) -> Int {
        co.staff.filter { Workplaces.needsPlace(role: $0.role) }.count + (co.managerID != nil ? 1 : 0) + (co.managerID == nil && co.ownerHours > 0 ? 1 : 0)
    }
    public static func wantedSquareMetres(_ co: Company, _ bd: Trade) -> Double {
        let o = max(20, (Double(max(3, onSiteHeads(co) + 1)) * 9 / 5).rounded() * 5)
        if !bd.raw["prem45"].isNull && bd.raw["prem45"][0].string != "office" {
            return max(o, (bd.raw["prem45"][1].double * max(0.3, min(1, co.size)) * 0.6 / 5).rounded() * 5)
        }
        return o
    }
    public static func isAtHome(_ co: Company, _ bd: Trade) -> Bool { isHomeTrade(bd) && !(co.value("prem")["m2"].double > 0) }
    public static func hasOutgrownHome(_ co: Company, _ bd: Trade) -> Bool { isAtHome(co, bd) && onSiteHeads(co) >= 4 }

    static func listings(_ co: Company, _ bd: Trade, _ w: World) -> [CompanySetup.Listing] {
        let want = wantedSquareMetres(co, bd)
        var r = HashedRandom("\(w.state.seed):pl37:\(co.type):\(co.cityID):\(Int(want)):\(w.week / 26)")
        let country = w.country(co)
        let tiers = w.catalog.tables.raw["PL_TIERS"].array
        let tiersB = w.catalog.tables.raw["PL_TIERS_B"].array
        let starts = country.companyNameStarts.isEmpty ? ["Nova"] : country.companyNameStarts
        return tiers.enumerated().map { (i, t) in
            let m2 = max(15, jsRound(want * t[1].double * (0.92 + r.next() * 0.16) / 5) * 5)
            let rentF = t[2].double * (0.94 + r.next() * 0.12)
            let landlord = starts[min(starts.count - 1, Int(r.next() * Double(starts.count)))]
            let word = CompanySetup.premisesWords[min(CompanySetup.premisesWords.count - 1, Int(r.next() * Double(CompanySetup.premisesWords.count)))]
            return CompanySetup.Listing(index: i, name: tiersB[i].string, squareMetres: m2, rentFactor: rentF, location: t[3].double, landlord: landlord + " " + word)
        }
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        for i in s.companies.indices where s.companies[i].status == .open {
            guard let bd = data.catalog[s.companies[i].type], hasOutgrownHome(s.companies[i], bd) else { continue }
            let k = onSiteHeads(s.companies[i]) >= 6 ? 2.0 : 1.0
            s.companies[i].set("mood", max(25, (s.companies[i].value("mood").isNull ? 60 : s.companies[i].num("mood")) - k))
            s.companies[i].quality = max(35, s.companies[i].quality - 0.3 * k)
        }
    }

    public struct FreeSpace: Equatable, Sendable { public var companyID: Int; public var propertyID: Int; public var name: String; public var freeSquareMetres: Double }

    public static func freeSpace(_ s: GameState, cityID: String, squareMetres m2: Double) -> [FreeSpace] {
        var out: [FreeSpace] = []
        for c in s.companies where c.status == .open && c.type == "comrent" {
            for p in c.properties where p.kind == "com" && p.raw["city"]?.string == cityID && p.units - p.leasedUnits >= m2 {
                out.append(FreeSpace(companyID: c.id, propertyID: p.id, name: p.name, freeSquareMetres: p.units - p.leasedUnits))
            }
        }
        return out
    }

    static func leaseNote(_ s: inout GameState, tenantIndex i: Int) {
        let lo = s.companies[i].value("landlord")
        guard !lo.isNull, !s.companies[i].value("prem")["leased"].bool, s.companies[i].value("prem")["m2"].double > 0,
              let li = s.companyIndex(lo["co"].int), let k = s.companies[li].properties.firstIndex(where: { $0.id == lo["pid"].int }) else { return }
        let m2 = s.companies[i].value("prem")["m2"].double
        var props = s.companies[li].properties
        props[k].leasedUnits += m2
        var l = Lease(raw: [:]); l.companyID = s.companies[i].id; l.squareMetres = m2; l.name = s.companies[i].name
        props[k].leases.append(l)
        s.companies[li].properties = props
        var prem = s.companies[i].value("prem"); prem["leased"] = 1; s.companies[i].set("prem", prem)
    }

    static func rentToLandlord(_ s: inout GameState, tenantIndex i: Int, rent r: Double) {
        let lo = s.companies[i].value("landlord")
        guard !lo.isNull else { return }
        leaseNote(&s, tenantIndex: i)
    }

    public static func payLandlord(_ s: inout GameState, tenantIndex i: Int, paid: Double) {
        let lo = s.companies[i].value("landlord")
        guard !lo.isNull, paid > 0, let l = s.company(lo["co"].int), l.status == .open else { return }
        Payments.companyReceives(&s, companyID: l.id, amount: paid * 0.97, category: "rev", label: "Rent from \(s.companies[i].name)")
    }

    static func cleanLeases(_ s: inout GameState, landlordIndex i: Int) {
        var props = s.companies[i].properties
        var changed = false
        for k in props.indices {
            let current = props[k].leases
            let keep = current.filter { l in
                guard l.companyID != 0 else { return true }
                if let t = s.company(l.companyID), t.status.isLive { return true }
                props[k].leasedUnits = max(0, props[k].leasedUnits - l.squareMetres)
                changed = true
                return false
            }
            if keep.count != current.count { props[k].leases = keep }
        }
        if changed { s.companies[i].properties = props }
    }
}
