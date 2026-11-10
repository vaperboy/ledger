import Foundation

extension GameState {
    mutating func dissolveHoldings() {
        let ids = Set(companies.filter { $0.type == "hold" }.map(\.id))
        guard !ids.isEmpty else { return }
        let prices = rest["fundPx"] ?? .null
        var credit = 0.0
        for h in companies where ids.contains(h.id) {
            let fm = h.value("fm")
            credit += fm["idxU"].double * Self.legacyFundPrice(prices, "idx")
            for (sym, position) in fm["fx"].object { credit += position["q"].double * Self.legacyFundPrice(prices, sym) }
            credit += fm["rs"].array.reduce(0) { $0 + $1["val"].double * $1["pct"].double / 100 }
        }
        for i in companies.indices where !ids.contains(companies[i].id) {
            if ids.contains(companies[i].int("hold")) { companies[i].raw.removeValue(forKey: "hold") }
            let lines = companies[i].value("holders").array
            let moved = lines.filter { ids.contains($0["hid"].int) }
            guard !moved.isEmpty else { continue }
            companies[i].ownership = min(100, companies[i].ownership + moved.reduce(0) { $0 + $1["pct"].double })
            companies[i].set("holders", .array(lines.filter { !ids.contains($0["hid"].int) }))
        }
        for k in loans.indices where ids.contains(loans[k].companyID) { loans[k].companyID = 0 }
        if let records = rest["startups"]?.array {
            rest["startups"] = .array(records.map { r in
                guard ids.contains(r["hid"].int) else { return r }
                var o = r.object
                o.removeValue(forKey: "hid")
                return .object(o)
            })
        }
        companies.removeAll { ids.contains($0.id) }
        if credit > 0 {
            cash += credit
            cashFlow["me", default: 0] += credit
        }
    }

    mutating func dropFinanceManagers() {
        guard var o = rest["office"], o["staff"].array.contains(where: { $0["role"].string == "fin" }) else { return }
        for x in o["staff"].array where x["role"].string == "fin" {
            let id = x["id"].int
            if var n = people[id] { n.employerID = 0; people[id] = n }
        }
        o["staff"] = .array(o["staff"].array.filter { $0["role"].string != "fin" })
        rest["office"] = o
    }

    private static func legacyFundPrice(_ prices: JSONValue, _ symbol: String) -> Double {
        prices[symbol].isNull ? 100 : prices[symbol].double
    }
}
