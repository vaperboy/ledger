import Foundation
import GameCore
import Countries
import Finance

public enum OwnListings {
    static let kindsBySeller: [String: Set<String>] = [
        "webdev": ["soft", "svc"], "gamestudio": ["soft", "svc"], "startup": ["soft", "svc"], "mktg": ["svc"],
        "furniture": ["furn"], "factory": ["mach", "tool"], "hardware": ["tool"], "electrician": ["tool"], "plumber": ["tool"], "handy": ["tool"],
    ]

    static func fills(_ s: GameState, buyer b: Company, seller sp: Company, data: GameData) -> [EquipmentMarket.Need] {
        guard let kinds = kindsBySeller[sp.type] else { return [] }
        return EquipmentMarket.needs(s, companyID: b.id, data: data)
            .filter { kinds.contains($0.kind) && !$0.isVehicle && !$0.subscription && $0.have + $0.leased < max($0.need, 1) }
            .sorted { ($0.need - $0.have) != ($1.need - $1.have) ? ($0.need - $0.have) > ($1.need - $1.have) : $0.equipmentID < $1.equipmentID }
    }

    static func spareSlots(_ s: GameState, seller sp: Company, _ sbd: Trade, _ w: World) -> Double {
        let lw = sp.value("lastW")
        let cap = lw["cap"].isNull ? CapacityModel.compute(sp, sbd, w).capacity : lw["cap"].double
        let used = lw["units"].double
        let sup = sp.value("ownSup")
        let already = (!sup.isNull && sup["w"].int == s.week) ? sup["n"].double : 0
        return max(0, cap - used - already)
    }

    static func slotsPerUnit(price: Double, seller sp: Company, _ sbd: Trade, _ w: World) -> Double {
        max(1e-6, price / max(0.01, Pricing.ticket(sp, sbd, w)))
    }

    public static func spareUnits(_ s: GameState, seller sp: Company, _ sbd: Trade, price: Double, _ w: World) -> Int {
        let n = spareSlots(s, seller: sp, sbd, w) / slotsPerUnit(price: price, seller: sp, sbd, w)
        return n.isFinite ? Int(saturating: min(n, Double(Int32.max)).rounded(.down)) : 0
    }

    public static func listings(_ s: GameState, buyer companyID: Int, data: GameData) -> [OwnListing] {
        guard let b = s.company(companyID), b.status == .open else { return [] }
        var out: [OwnListing] = []
        for sp in s.companies where sp.id != b.id && sp.status == .open && sp.countryCode == b.countryCode {
            guard let bd = data.catalog[sp.type] else { continue }
            let listed = SalesItems.items(sp, bd).filter { $0.listedForGroup }
            guard !listed.isEmpty, let need = fills(s, buyer: b, seller: sp, data: data).first else { continue }
            let rows = SalesItems.rows(s, companyID: sp.id, data: data)
            let w = World(state: s, data: data)
            for it in listed {
                guard let r = rows.first(where: { $0.id == it.id }) else { continue }
                let price = r.price * (1 - r.discountPercent / 100)
                out.append(OwnListing(sellerID: sp.id, sellerName: sp.name, itemID: it.id, itemName: it.name,
                                      price: price, equipmentID: need.equipmentID, equipmentName: need.name,
                                      available: spareUnits(s, seller: sp, bd, price: price, w)))
            }
        }
        return out
    }

    public static func buy(_ s: inout GameState, buyer: Int, seller: Int, itemID: String, quantity: Int, data: GameData) -> String? {
        guard quantity >= 1 else { return "Choose at least one." }
        guard let bi = s.companyIndex(buyer), let si = s.companyIndex(seller), buyer != seller else { return "That company no longer exists." }
        guard let listing = listings(s, buyer: buyer, data: data).first(where: { $0.sellerID == seller && $0.itemID == itemID }) else { return "That item is not for sale to this company." }
        let b = s.companies[bi], sp = s.companies[si]
        guard let bbd = data.catalog[b.type], let e = bbd.allEquipment.first(where: { $0.id == listing.equipmentID }), let sbd = data.catalog[sp.type] else { return "That item is not for sale to this company." }
        let w = World(state: s, data: data)
        let k = EquipmentMarket.kind(e, tradeID: bbd.id, tables: w.catalog.tables)
        let one = k == "soft" || k == "svc"
        let room = listing.available
        guard room >= 1 else { return "\(sp.name) has no spare capacity this week." }
        let q = min(one ? 1 : quantity, room)
        let total = (listing.price * Double(q)).rounded()
        let vatDue = w.country(sp).usesSalesTax ? 0 : Double(jsRound(total * Vat.rate(sp, sbd, w)))
        guard b.cash >= total + vatDue else { return "Not enough cash in \(b.name)." }
        Payments.companyPays(&s, companyID: buyer, amount: total, category: nil, label: "\(listing.itemName) from \(sp.name)")
        Payments.companyReceives(&s, companyID: seller, amount: total, category: "rev", label: "Sale to \(b.name): \(listing.itemName)")
        Payments.companyPays(&s, companyID: seller, amount: total * IntercompanySupply.varRatio(sp, data: data), category: "cogs", label: nil)
        IntercompanySupply.transferVat(&s, supplier: s.companies[si], buyerIndex: bi, net: total, data: data, w, cashNow: true)
        CompanySetup.addEquipment(&s, companyIndex: bi, e, tradeID: bbd.id, quantity: Double(q), totalPrice: total * IntercompanySupply.varRatio(sp, data: data), brand: nil, used: nil, data: data)
        let sup = s.companies[si].value("ownSup")
        let before = (!sup.isNull && sup["w"].int == s.week) ? sup["n"].double : 0
        s.companies[si].set("ownSup", .object(["w": .number(Double(s.week)), "n": .number(before + Double(q) * slotsPerUnit(price: listing.price, seller: sp, sbd, w))]))
        if !one && q < quantity { s.note("\(sp.name) could only supply \(q) of the \(quantity) \(listing.itemName) asked for; the rest was not ordered.", tone: "n", companyID: buyer) }
        if one {
            var eq = s.companies[bi].value("eq")
            eq[e.id]["soft"] = .string(k == "svc" ? "svc" : "once")
            eq[e.id]["ver"] = .number(Double(s.week)); eq[e.id]["upd"] = .number(0); eq[e.id]["cond"] = 1
            s.companies[bi].set("eq", eq)
        }
        return nil
    }
}
