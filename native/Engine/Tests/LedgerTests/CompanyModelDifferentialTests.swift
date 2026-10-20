import XCTest
import GameCore
import Countries
import Businesses

/// The demand, capacity and price model must give the same numbers as the original on the same companies.
/// Golden/save_uk25.json and Golden/oracle_demand_cap.json were produced by running the original game
/// (tools/ref/snippets/uk17.js).
final class CompanyModelDifferentialTests: XCTestCase {
    func world() throws -> World {
        let s = try Golden.state("save_uk25")
        return World(state: s, countries: try CountryBook.bundled(), catalog: try TradeCatalog.bundled(), balance: try Balance.bundled())
    }

    func testDemandPartsMatchOriginal() throws {
        let w = try world()
        let g = try Golden.load("oracle_demand_cap")
        let tuned = TradeTuning.tunedTradeIDs  // deliberately re-balanced trades (docs/BALANCE_REPORT.md)
        var report: [String] = []
        for (idStr, e) in g.object {
            guard let co = w.state.company(Int(idStr)!), let bd = w.trade(co), !tuned.contains(bd.id) else { continue }
            let r = DemandModel.compute(co, bd, w)
            let tag = "\(e["type"].string)#\(idStr)"
            var line = "\(tag): D swift \(String(format: "%.3f", r.customers)) vs \(String(format: "%.3f", e["D"].double))"
            var bad = false
            for (name, v) in e["parts"].object {
                guard let mine = r.part(name) ?? (name == "base" ? bd.normalDemand : nil) else {
                    if abs(v.double - 1) > 1e-9 { line += " [missing \(name)=\(v.double)]"; bad = true }
                    continue
                }
                if abs(mine - v.double) > 1e-6 * max(1, abs(v.double)) { line += " [\(name) \(String(format: "%.4f", mine)) vs \(String(format: "%.4f", v.double))]"; bad = true }
            }
            if bad || abs(r.customers - e["D"].double) > 1e-6 * max(1, e["D"].double) { report.append(line) }
        }
        XCTAssertTrue(report.isEmpty, "\n" + report.joined(separator: "\n"))
    }

    func testTicketPriceMatchesOriginal() throws {
        let w = try world()
        let g = try Golden.load("oracle_demand_cap")
        let tuned = TradeTuning.tunedTradeIDs  // deliberately re-balanced trades (docs/BALANCE_REPORT.md)
        var report: [String] = []
        for (idStr, e) in g.object {
            guard let co = w.state.company(Int(idStr)!), let bd = w.trade(co), !tuned.contains(bd.id) else { continue }
            let p = Pricing.ticket(co, bd, w)
            let tm = Pricing.ticketMultiplier(co, bd, w)
            if abs(p - e["price"].double) > 1e-6 * e["price"].double || abs(tm - e["priceMult"].double) > 1e-9 {
                report.append("\(e["type"].string): ticket \(p) vs \(e["price"].double); mult \(tm) vs \(e["priceMult"].double)")
            }
        }
        XCTAssertTrue(report.isEmpty, "\n" + report.joined(separator: "\n"))
    }
}

extension CompanyModelDifferentialTests {
    func testCapacityMatchesOriginal() throws {
        let w = try world()
        let g = try Golden.load("oracle_demand_cap")
        let tuned = TradeTuning.tunedTradeIDs  // deliberately re-balanced trades (docs/BALANCE_REPORT.md)
        var report: [String] = []
        var matched = 0
        for (idStr, e) in g.object {
            guard let co = w.state.company(Int(idStr)!), let bd = w.trade(co), !tuned.contains(bd.id) else { continue }
            let c = CapacityModel.compute(co, bd, w)
            let ok = abs(c.capacity - e["cap"].double) <= 1e-6 * max(1, e["cap"].double)
            if ok { matched += 1; continue }
            // Deliberate fix (docs/BALANCE_PARITY.md): with an empty support role the original's capacity collapsed to zero even
            // though its own step meant the team to cover it. Same parts, the original 0, ours the covered capacity: accepted.
            let sameParts = zip(c.parts, e["cparts"].array).allSatisfy { abs($0.capacity - $1["cap"].double) <= 1e-6 * max(1, $1["cap"].double) }
            if e["cap"].double == 0 && c.capacity > 0 && sameParts { matched += 1; continue }
            let mine = c.parts.map { "\($0.key)=\(String(format: "%.1f", $0.capacity))" }.joined(separator: ",")
            let theirs = e["cparts"].array.map { "\($0["k"].string)=\(String(format: "%.1f", $0["cap"].double))" }.joined(separator: ",")
            report.append("\(e["type"].string)#\(idStr): cap swift \(String(format: "%.2f", c.capacity)) vs \(String(format: "%.2f", e["cap"].double)) | swift [\(mine)] | orig [\(theirs)]")
        }
        XCTAssertTrue(report.isEmpty, "matched \(matched)/\(g.object.count)\n" + report.joined(separator: "\n"))
    }
}
