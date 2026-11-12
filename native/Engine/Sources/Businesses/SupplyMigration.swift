import Foundation
import GameCore
import Countries

// Brings saves from before the one supply map onto it: old line ids move to the new lines, and made-up
// vendors (V-cc-n) and market choices become the matching player supplier company of that line.
public enum SupplyMigration {
    static let flag = "supmap"
    public static let version = 1

    public static func needed(_ s: GameState) -> Bool { (s.rest[flag] ?? .null).int < version }

    // The line an old line id lives on for a trade now; nil when the line was folded into stock or overhead.
    public static func newLine(_ old: String, trade: String) -> String? {
        switch old {
        case "goods", "mat": return SupplyMap.stockLine(trade)?.line
        case "repair": return SupplyMap.needs(trade).first { ["upkeep", "machines", "carserv"].contains($0.line) }?.line
        case "pack", "supplies", "parts", "software", "power": return nil
        default: return SupplyMap.need(trade, line: old) != nil ? old : nil
        }
    }

    // The player supplier that stands where an old vendor stood: same price tier, same line. nil means the line's standard supplier.
    public static func supplierFor(vendor id: String, seed: Int, countryCode cc: String, line: String, buyer: String, countries: CountryBook, nouns: JSONValue) -> String? {
        let p = id.split(separator: "-").map(String.init)
        guard p.count == 3, p[0] == "V", let n = Int(p[2]) else { return nil }
        let pool = EquipmentMarket.vendorPool(seed: seed, countryCode: p[1], countries: countries, nouns: nouns)
        let q = pool.indices.contains(n) ? pool[n].vendor.quality : 0
        let slot = q < -0.12 ? 1 : q > 0.12 ? 2 : 0
        let trades = SupplyMap.suppliers(line: line, buyer: buyer).filter { $0 != buyer }
        guard slot > 0, !trades.isEmpty else { return nil }
        return SupplyPlayers.id(countryCode: cc, line: line, trade: trades[slot % trades.count], slot: slot)
    }

    @discardableResult
    public static func run(_ s: inout GameState, countries: CountryBook, nouns: JSONValue) -> Int {
        guard needed(s) else { return 0 }
        var changed = 0
        let seed = s.seed
        var relationCopies: [(from: String, to: String)] = []
        for i in s.companies.indices {
            let co = s.companies[i]
            let trade = co.type
            let cc = co.countryCode
            let stock = SupplyMap.stockLine(trade)?.line
            let upkeep = SupplyMap.needs(trade).first { $0.line == "upkeep" || $0.line == "machines" }?.line
            func mapped(_ id: String, line: String?) -> String? {
                guard let line, id.hasPrefix("V-") else { return nil }
                let to = supplierFor(vendor: id, seed: seed, countryCode: cc, line: line, buyer: trade, countries: countries, nouns: nouns)
                if let to { relationCopies.append((id, to)) }
                return to
            }
            // Line choices: old ids move to their new line, made-up vendors become player suppliers, the market choice is the standard supplier.
            let sc = co.value("sc").object
            if !sc.isEmpty {
                var next: [String: JSONValue] = [:]
                for (old, v) in sc {
                    guard let line = newLine(old, trade: trade) else { continue }
                    let id = v.string
                    if id.hasPrefix("P:") { next[line] = v }
                    else if id.hasPrefix("V-"), let to = mapped(id, line: line) { next[line] = .string(to) }
                }
                s.companies[i].set("sc", .object(next)); changed += 1
            }
            var src = co.value("src")
            if !src.isNull, src["v"].string.hasPrefix("V-") {
                let to: String = mapped(src["v"].string, line: stock) ?? "auto"
                src["v"] = .string(to); s.companies[i].set("src", src); changed += 1
            }
            let fix = co.value("fixv")
            if !fix.isNull, fix.string.hasPrefix("V-") {
                let to: String = mapped(fix.string, line: upkeep) ?? "auto"
                s.companies[i].set("fixv", .string(to)); changed += 1
            }
            var items = co.value("itemsv2").object
            var itemsChanged = false
            for (k, r) in items where r["v"].string.hasPrefix("V-") {
                var x = r
                if let to = mapped(r["v"].string, line: stock) { x["v"] = .string(to) }
                else if let first = stock.map({ SupplyPlayers.id(countryCode: cc, line: $0, trade: SupplyMap.suppliers(line: $0, buyer: trade).first ?? "wholesale", slot: 0) }) { x["v"] = .string(first) }
                items[k] = x; itemsChanged = true
            }
            if itemsChanged { s.companies[i].set("itemsv2", .object(items)); changed += 1 }
            var sdl = co.value("sdl")
            if !sdl.isNull {
                for (scope, line) in [("goods", stock), ("fix", upkeep)] where sdl[scope]["v"].string.hasPrefix("V-") {
                    if let to = mapped(sdl[scope]["v"].string, line: line) { sdl[scope]["v"] = .string(to) } else { var o = sdl.object; o.removeValue(forKey: scope); sdl = .object(o) }
                }
                let cool = sdl["cool"].object
                if !cool.isEmpty {
                    var next: [String: JSONValue] = [:]
                    for (k, v) in cool { if k.hasPrefix("V-") { if let to = mapped(k, line: stock) { next[to] = v } } else { next[k] = v } }
                    sdl["cool"] = .object(next)
                }
                s.companies[i].set("sdl", sdl)
            }
            let snx = co.value("snx").object
            if !snx.isEmpty {
                var next: [String: JSONValue] = [:]
                for (k, v) in snx { if k.hasPrefix("V-") { if let to = mapped(k, line: stock) { next[to] = v } } else { next[k] = v } }
                s.companies[i].set("snx", .object(next))
            }
            var fr = co.value("franchise")
            if fr["fran"].bool {
                for (input, line) in [("goods", stock), ("repair", upkeep)] where fr["supStd"][input]["id"].string.hasPrefix("V-") {
                    fr["supStd"][input]["id"] = .string(mapped(fr["supStd"][input]["id"].string, line: line) ?? "auto")
                }
                s.companies[i].set("franchise", fr)
            }
            if !co.value("scw").isNull { s.companies[i].set("scw", .null) }
        }
        // Relationships carry over to the company that took the vendor's place.
        if var vr = s.rest["vr"], !vr.isNull {
            for c in relationCopies where vr[c.to].isNull && !vr[c.from].isNull { vr[c.to] = vr[c.from] }
            s.rest["vr"] = vr
        }
        // Board agreements and chain rules named a vendor that served many trades; each line now has its own suppliers.
        if var a = s.rest["agree"] {
            for scope in ["goods", "fix"] where a[scope].string.hasPrefix("V-") { a[scope] = .null }
            s.rest["agree"] = a
        }
        if let chains = s.rest["chains"]?.array {
            s.rest["chains"] = .array(chains.map { (ch: JSONValue) -> JSONValue in
                var c = ch
                var sup = c["rules"]["sup"].object
                for (k, v) in sup where v["id"].string.hasPrefix("V-") { sup.removeValue(forKey: k) }
                if !c["rules"]["sup"].isNull { c["rules"]["sup"] = .object(sup) }
                return c
            })
        }
        // Business customers no longer act as suppliers.
        if !(s.rest["l39"] ?? .null).isNull { s.rest["l39"] = .array([]) }
        // Player contracts and own listings move to the new line ids; folded lines end.
        if var rec = s.rest["psup"] {
            rec["c"] = .array(rec["c"].array.compactMap { (c: JSONValue) -> JSONValue? in
                guard let co = s.company(c["b"].int), let line = newLine(c["ln"].string, trade: co.type) else { return nil }
                var x = c; x["ln"] = .string(line); return x
            })
            rec["l"] = .array(rec["l"].array.map { (l: JSONValue) -> JSONValue in
                var x = l
                let supplied = SupplyMap.linesSupplied(by: l["td"].string)
                if !supplied.contains(l["ln"].string) {
                    if l["ln"].string == "goods", let first = supplied.first { x["ln"] = .string(first); x["lnm"] = .string(SupplyMap.line(first)?.name ?? first) }
                    else { x["st"] = .bool(true) }
                }
                return x
            })
            s.rest["psup"] = rec
        }
        s.rest[flag] = .number(Double(version))
        return changed
    }
}
