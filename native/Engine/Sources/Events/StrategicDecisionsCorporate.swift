import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// The last 13 strategic decisions of round 27e (features/world/business_events.js): someone wants to buy your company, a good site in another
/// city, a franchise inquiry, a rival proposes a merger, a rival in distress, a bank proposes listing your holding, private equity wants control,
/// a hostile bid for your listed holding, the competition authority, an activist investor, an auction of a stake in a foreign group, and the two
/// country events (a successor-less Japanese rival, American venture capital). They use the rivals in `rest["mk"][key].riv`, the groups in
/// `rest["g27"]`, holders in the company's `holders` and the listing/PE/stake code of `Funding`, `GroupDeals` and `Shareholders`.
///
/// Not faithful: market share for the competition authority is your sales against the local market's size (what `WorldWeek.competitors` measures)
/// rather than the original's market map; a foreign group for the auction must already exist in `rest["g27"]` (the original creates the country's
/// groups on demand); without individual rivals or groups in the game (the Competition port) s_acqoffer, e_merger, e_distress, c_JP_succ, t_hostile
/// and t_auction simply do not come up.
extension StrategicDecisions {
    static let localFamilies: Set<String> = ["svc", "venue", "retail", "prod", "logi", "project"]

    static func isLocalTrade(_ co: Company, _ data: GameData) -> Bool { localFamilies.contains(data.catalog[co.type]?.family ?? "") }
    static func marketKey(_ co: Company) -> String { co.type + "|" + co.cityID }
    static func rivals(_ s: GameState, _ co: Company) -> [JSONValue] { s.rest["mk"]?[marketKey(co)]["riv"].array ?? [] }
    /// A rival that belongs to no group (the original's `!r.g27`).
    static func independent(_ r: JSONValue) -> Bool { let g = r["g27"]; return g.isNull || g.string == "0" || g.string.isEmpty || g.string == "false" }
    static func scaled(_ s: GameState, _ co: Company, _ data: GameData, _ v: Double) -> Double {
        Currency(country: data.countries.resolve(co.countryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values)).scaledPrice(v)
    }
    static func scaledHome(_ s: GameState, _ data: GameData, _ v: Double) -> Double {
        Currency(country: data.countries.resolve(s.homeCountryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values)).scaledPrice(v)
    }
    static func editRival(_ s: inout GameState, _ key: String, _ id: Int, _ body: (inout JSONValue) -> Void) {
        guard var mk = s.rest["mk"], var arr = Optional(mk[key]["riv"].array), let k = arr.firstIndex(where: { $0["id"].int == id }) else { return }
        body(&arr[k]); mk[key]["riv"] = .array(arr); s.rest["mk"] = mk
    }
    static func holdingsOpen(_ s: GameState) -> [Company] { s.companies.filter { $0.type == "hold" && $0.status == .open } }
    static func isTycoon(_ s: GameState, _ data: GameData) -> Bool {
        s.companies.contains { $0.type == "hold" && $0.status.isLive } || liveCompanies(s, data).count >= 5
    }

    /// Your share of a local market (the sales of your companies in it against what the market holds), as the weekly competitor model measures it.
    static func marketShares(_ s: GameState, data: GameData) -> [(key: String, companyID: Int, name: String, share: Double)] {
        var by: [String: [Company]] = [:]
        for c in s.companies where c.status == .open && c.type != "club" && c.type != "hold" && isLocalTrade(c, data) { by[marketKey(c), default: []].append(c) }
        return by.keys.sorted().compactMap { key in
            guard let cs = by[key], let first = cs.first, let bd = data.catalog[first.type], let m = Optional(s.rest["mk"]?[key] ?? .null), !m.isNull else { return nil }
            let city = data.countries.city(first.cityID, preferring: first.countryCode)?.city
            let marketRev = max(1, (bd.normalDemand == 0 ? 1 : bd.normalDemand) * bd.ticket * (city?.demand ?? 1) * (m["n"].double + 1))
            return (key, first.id, first.name, cs.reduce(0) { $0 + $1.lastWeekRevenue } / marketRev)
        }
    }

    static func hostile(_ s: inout GameState, h: Company, d: JSONValue, p: Double, x: X) {
        if s.random.chance(p) {
            if let i = s.companyIndex(h.id), let g = GroupStakes.group(s, id: d["g"].string) {
                let price = jsRound(value(s.companies[i], s, x.data) * 1.2)
                if GroupDeals.sellToGroup(&s, companyIndex: i, groupID: d["g"].string, price: price, data: x.data, context: x.fc) {
                    s.addMessage(from: "Shareholders of \(h.name)", title: "\(d["gn"].string) took control of \(h.name)", body: "Enough shareholders sold to \(d["gn"].string). Your stake was bought at the offer price.", tone: "bad")
                }
                _ = g
            }
        } else { s.note("The takeover attempt on \(h.name) failed.", tone: "good") }
    }

    static func mergeIn(_ s: inout GameState, _ x: X, pct: Double) {
        let co = s.companies[x.i], key = marketKey(co), rid = x.d["r"].int
        guard var mk = s.rest["mk"], let r = mk[key]["riv"].array.first(where: { $0["id"].int == rid }) else { return }
        mk[key]["riv"] = .array(mk[key]["riv"].array.filter { $0["id"].int != rid })
        mk[key]["n"] = .number(max(1, mk[key]["n"].double - 1))
        s.rest["mk"] = mk
        let maxSize = x.data.catalog[co.type]?.maxSize ?? 3
        s.companies[x.i].size = min(maxSize, co.size + (r["size"].isNull ? 1 : r["size"].double) * 0.6)
        s.companies[x.i].awareness = min(100, co.awareness + 10)
        dem(&s, x, 1.15, 52)
        Funding.addHolder(&s, x.i, name: x.d["o"].string, pct: pct * co.ownership / 100, paid: 0, extra: ["sat": 65])
        s.companies[x.i].ownership = co.ownership * (1 - pct / 100)
        s.note("\(co.name) merged with \(x.d["n"].string). \(x.d["o"].string) now owns \(Int(pct))%.", tone: "good", companyID: co.id)
        if let sh = marketShares(s, data: x.data).first(where: { $0.key == key }), sh.share > 0.3 { later(&s, 8, "e_merger_review", x.i, .object(["s": .number(sh.share)])) }
    }

    /// The follow-ups of these decisions. Original: `FOLLOW.g_location_neg`, `e_merger_review`.
    static func followUpCorporate(_ s: inout GameState, id: String, index k: Int, d: JSONValue, data: GameData, context fc: FinanceContext) {
        switch id {
        case "g_location_neg":
            if s.random.chance(0.5), let def = byID["g_location"] {
                var d2 = d; d2["disc"] = .number(d["disc"].double + 10)
                _ = fire(&s, def, companyIndex: k, data: data, context: fc, given: d2)
            } else { s.note("The site in \(d["cn"].string) went to someone else.", tone: "n", companyID: s.companies[k].id) }
        case "e_merger_review":
            if s.random.chance(0.4), let def = byID["t_antitrust"] { _ = fire(&s, def, companyIndex: k, data: data, context: fc) }
        default: break
        }
    }

    static func corporateDecisions() -> [Def] {
        var L: [Def] = []

        // Someone wants to buy your company: a group makes a bid (answered as the original's g27bid).
        L.append(Def(id: "s_acqoffer", cls: "opp", stages: ["start", "grow", "est"], w: 2,
                     cond: { s, co, data in ebit12(co, s) > 0 && value(co, s, data) > scaled(s, co, data, 500_000) && s.week - (co.openedWeek ?? co.foundedWeek) > 40 && !(co.num("bid27") > Double(s.week)) },
                     make: { s, i, data, fc in
                         s.companies[i].set("bid27", s.week + 40)
                         let co = s.companies[i]
                         guard let g = GroupStakes.groups(s, country: co.countryCode).first(where: { $0["dist"].int == 0 && $0["types"].array.contains { $0.string == co.type } }) else { return nil }
                         let v0 = value(co, s, data)
                         GroupDeals.bidFor(&s, companyIndex: i, groupID: g["id"].string, price: (v0 * s.random.range(1.05, 1.3) / 1000).rounded() * 1000, value: v0, context: fc)
                         return .object([:]) },
                     silent: true,
                     title: { co, _, _ in "Someone wants to buy \(co.name)" }))

        // A good site in another city.
        L.append(Def(id: "g_location", cls: "opp", stages: ["grow", "est"], w: 3, def: 2,
                     cond: { s, co, data in ebit12(co, s) > 0 && isLocalTrade(co, data) && (data.countries[co.countryCode]?.cities.count ?? 0) > 1 },
                     make: { s, i, data, _ in
                         let co = s.companies[i]
                         let cs = (data.countries[co.countryCode]?.cities ?? []).filter { $0.id != co.cityID && $0.id != "small" }
                         guard !cs.isEmpty else { return nil }
                         let c = cs[s.random.int(0, cs.count - 1)]
                         return .object(["city": .string(c.id), "cn": .string(c.name), "disc": .number(Double(s.random.int(10, 25)))]) },
                     title: { co, d, _ in "A good site for a second \(co.name) in \(d["cn"].string)" },
                     body: { co, d, _ in "A landlord in \(d["cn"].string) offers a site \(d["disc"].int)% below normal rent for the first two years if you sign soon. A second \(co.name) would share your brand, but it ties up money and management time." },
                     opts: [
                        Opt(label: "Sign now", detail: "A new company is registered there; you set it up like any new business.") { s, x in
                            let co = s.companies[x.i], nm = "\(co.name) \(x.d["cn"].string)"
                            switch CompanySetup.create(&s, tradeID: co.type, cityID: x.d["city"].string, form: .limited, name: nm, countryCode: co.countryCode, data: x.data, context: x.fc) {
                            case .success(let id):
                                if let n = s.companyIndex(id) {
                                    var f = s.companies[n].value("flags"); f["rent27"] = .object(["m": .number(1 - x.d["disc"].double / 100), "until": .number(Double(s.week + 104))]); s.companies[n].set("flags", f)
                                    s.companies[n].set("branch", .object(["of": .number(Double(co.id))]))
                                    s.note("\(nm) is registered. Set it up in Companies.", tone: "good", companyID: id)
                                }
                            case .failure: s.note("Could not start \(nm): the money or the permits are not there.", tone: "bad", companyID: co.id)
                            } },
                        Opt(label: "Negotiate an even better rent", detail: "They may give more, or rent it to someone else.") { s, x in later(&s, 3, "g_location_neg", x.i, x.d) },
                        Opt(label: "Wait until you have more cash", detail: "The site goes to someone else, maybe a rival.") { _, _ in }]))

        // A franchise inquiry (the franchise system itself is the company's Grow tab).
        L.append(Def(id: "g_franinq", cls: "opp", stages: ["grow", "est"], w: 1, def: 2,
                     cond: { s, co, data in !co.value("fr")["on"].bool && co.reputation > 60 && isLocalTrade(co, data) && ebit12(co, s) > 0 },
                     title: { co, _, _ in "An investor wants to run a \(co.name) of their own" },
                     body: { _, _, _ in "They would pay a fee and royalties to use your name and recipe in another city. Faster growth with their money, but less control over quality." },
                     opts: [Opt(label: "Look at franchising", detail: "Set up a franchise system in the company's Grow tab.") { _, _ in },
                            Opt(label: "Open your own branches instead", detail: "More control, your money.") { _, _ in },
                            Opt(label: "Not yet", detail: "Standardise first.") { _, _ in }]))

        // A rival proposes a merger.
        L.append(Def(id: "e_merger", cls: "opp", stages: ["est", "grow"], w: 1, def: 2,
                     cond: { s, co, data in isLocalTrade(co, data) && rivals(s, co).contains { independent($0) && $0["size"].double < co.size * 1.4 } },
                     make: { s, i, _, _ in
                         guard let r = rivals(s, s.companies[i]).filter({ independent($0) }).max(by: { $0["size"].double < $1["size"].double }) else { return nil }
                         return .object(["r": r["id"], "n": r["name"], "o": r["owner"]]) },
                     title: { _, d, _ in "\(d["n"].string) proposes a merger" },
                     body: { co, d, _ in "\(d["o"].string), who owns \(d["n"].string), suggests putting the two businesses together: no cash changes hands, \(d["o"].string.split(separator: " ").first.map(String.init) ?? "they") gets a share of \(co.name). Bigger and stronger together, but you share ownership, and the competition authority may look at it." },
                     opts: [Opt(label: "Merge: they get 30% of the company", detail: "You take over their customers and sites.") { s, x in mergeIn(&s, x, pct: 30) },
                            Opt(label: "Negotiate: offer 20%", detail: "They may accept, or walk.") { s, x in
                                if s.random.chance(0.5) { mergeIn(&s, x, pct: 20) } else { s.note("\(x.d["o"].string) turned down 20%.", tone: "n", companyID: s.companies[x.i].id) } },
                            Opt(label: "Decline", detail: "") { _, _ in }]))

        // A rival is in trouble and for sale.
        L.append(Def(id: "e_distress", cls: "opp", stages: ["grow", "est"], w: 2, tone: "good",
                     cond: { s, co, data in isLocalTrade(co, data) && rivals(s, co).contains { independent($0) && !$0["listed"].bool } },
                     make: { s, i, _, _ in
                         guard let r = rivals(s, s.companies[i]).first(where: { independent($0) && !$0["listed"].bool }) else { return nil }
                         return .object(["r": r["id"], "n": r["name"]]) },
                     title: { _, d, _ in "\(d["n"].string) is in trouble and for sale" },
                     body: { _, d, _ in "\(d["n"].string) is behind on its bills and the owner wants out. It could be bought well below its normal price, or you could wait for it to close. A buyer may find surprises in the books." },
                     auto: { s, x in
                         let key = marketKey(s.companies[x.i]), wk = Double(s.week)
                         editRival(&s, key, x.d["r"].int) { $0["listed"] = true; $0["dist27"] = .number(wk) } }))

        // A bank proposes listing your holding.
        L.append(Def(id: "t_ipo", cls: "corp", w: 2, def: 1, global: true,
                     cond: { s, co, data in holdingsOpen(s).contains { !$0.flag("listed") && value($0, s, data) > scaledHome(s, data, 30e6) } },
                     make: { s, _, data, _ in
                         guard let h = holdingsOpen(s).first(where: { !$0.flag("listed") && value($0, s, data) > scaledHome(s, data, 30e6) }) else { return nil }
                         return .object(["h": .number(Double(h.id)), "n": .string(h.name)]) },
                     title: { _, d, _ in "A bank proposes listing \(d["n"].string)" },
                     body: { _, _, _ in "An investment bank thinks the market would value your group well. A listing raises money and makes shares easy to sell, but you report every quarter and outsiders get a say. Private equity would invest without a listing, for a big stake and a seat at the table." },
                     opts: [
                        Opt(label: "Go public", detail: "A bank listing fee of about 1.5 million (in your currency).") { s, x in
                            guard let hi = s.companyIndex(x.d["h"].int) else { return }
                            let fee = x.fc.homeCurrency(s).scaledPrice(Funding.listingFee)
                            Payments.transferFromSavings(&s, need: fee)
                            Payments.playerPays(&s, fee, label: "Stock exchange listing")
                            s.companies[hi].set("listed", 1)
                            s.note("\(s.companies[hi].name) is listed on the stock exchange.", tone: "good", companyID: s.companies[hi].id) },
                        Opt(label: "Wait for better numbers", detail: "") { _, _ in },
                        Opt(label: "Take private equity instead", detail: "They buy 25% in new shares.") { s, x in
                            guard let hi = s.companyIndex(x.d["h"].int) else { return }
                            if case .ok = Funding.sellShares(&s, companyID: x.d["h"].int, pct: 25, mode: "primary", data: x.data, context: x.fc) {
                                var list = s.companies[hi].value("holders").array
                                if !list.isEmpty {
                                    list[list.count - 1]["name"] = .string(Funding.fundName(&s, countryCode: s.companies[hi].countryCode, data: x.data, suffix: "Partners"))
                                    list[list.count - 1]["k27"] = "exit"; list[list.count - 1]["sat"] = 60
                                    s.companies[hi].set("holders", .array(list))
                                }
                            } }]))

        // Private equity wants control of one of your companies.
        L.append(Def(id: "t_pe", cls: "corp", w: 2, def: 2, global: true,
                     cond: { s, _, data in peTarget(s, data) != nil },
                     make: { s, _, data, _ in
                         guard let c = peTarget(s, data) else { return nil }
                         return .object(["c": .number(Double(c.id)), "n": .string(c.name), "v": .number((value(c, s, data) * 1.2 / 1000).rounded() * 1000)]) },
                     title: { _, d, _ in "Private equity wants control of \(d["n"].string)" },
                     body: { _, d, cur in "A private equity firm values \(d["n"].string) at \(cur.display(d["v"].double)) and wants 60%. You would cash in now and keep 40%, but they would run it their way and sell within five years." },
                     opts: [
                        Opt(label: "Sell them 60%", detail: "") { s, x in
                            guard let ci = s.companyIndex(x.d["c"].int) else { return }
                            let c = s.companies[ci], amt = jsRound(x.d["v"].double * 0.6 * c.ownership / 100)
                            Payments.ownerReceivesSale(&s, from: c, amount: amt, gain: amt * 0.7, label: "Sold 60% of \(c.name) to private equity")
                            let who = Funding.fundName(&s, countryCode: c.countryCode, data: x.data, suffix: "Equity")
                            Funding.addHolder(&s, ci, name: who, pct: 60, paid: amt, extra: ["k27": "exit", "sat": 65])
                            s.companies[ci].ownership = c.ownership * 0.4
                            Funding.addBoardSeats(&s, ci, 2) },
                        Opt(label: "Offer them 25% instead", detail: "They may accept a minority stake.") { s, x in
                            guard let ci = s.companyIndex(x.d["c"].int), s.random.chance(0.5) else { s.note("They only wanted control.", tone: "n"); return }
                            let c = s.companies[ci], amt = jsRound(x.d["v"].double * 0.25 * c.ownership / 100)
                            Payments.ownerReceivesSale(&s, from: c, amount: amt, gain: amt * 0.7, label: "Sold 25% of \(c.name)")
                            let who = Funding.fundName(&s, countryCode: c.countryCode, data: x.data, suffix: "Equity")
                            Funding.addHolder(&s, ci, name: who, pct: 25, paid: amt, extra: ["k27": "growth", "sat": 60])
                            s.companies[ci].ownership = c.ownership * 0.75
                            Funding.addBoardSeats(&s, ci, 1) },
                        Opt(label: "Say no", detail: "") { _, _ in }]))

        // A group buys up shares of your listed holding.
        L.append(Def(id: "t_hostile", cls: "corp", w: 3, tone: "bad", def: 3, global: true,
                     cond: { s, _, _ in holdingsOpen(s).contains { $0.flag("listed") && $0.ownership < 60 } },
                     make: { s, _, _, _ in
                         guard let h = holdingsOpen(s).first(where: { $0.flag("listed") && $0.ownership < 60 }),
                               let g = GroupStakes.groups(s, country: s.homeCountryCode).filter({ $0["dist"].int == 0 }).max(by: { $0["cash"].double < $1["cash"].double }) else { return nil }
                         return .object(["h": .number(Double(h.id)), "n": .string(h.name), "g": g["id"], "gn": g["name"]]) },
                     title: { _, d, _ in "\(d["gn"].string) is buying up shares in \(d["n"].string)" },
                     body: { _, d, _ in "\(d["gn"].string) has quietly built up a stake in \(d["n"].string) and wants seats on the board. If it gets more than half, it can replace the board, and you." },
                     opts: [
                        Opt(label: "Buy shares back", detail: "Costs you cash; lifts your stake.") { s, x in
                            guard let hi = s.companyIndex(x.d["h"].int) else { return }
                            let h = s.companies[hi], add = min(100 - h.ownership, 10), c = jsRound(value(h, s, x.data) * add / 100 * 1.15)
                            if Payments.liquid(s) < c { s.note("Not enough cash to buy back shares.", tone: "bad"); hostile(&s, h: h, d: x.d, p: 0.6, x: x); return }
                            Payments.transferFromSavings(&s, need: c)
                            Payments.playerPays(&s, c, label: "Share buyback in \(h.name)")
                            s.companies[hi].ownership = h.ownership + add
                            hostile(&s, h: s.companies[hi], d: x.d, p: 0.25, x: x) },
                        Opt(label: "Find a friendly investor", detail: "A \"white knight\" takes a stake and votes with you.") { s, x in
                            if let h = s.company(x.d["h"].int) { hostile(&s, h: h, d: x.d, p: 0.3, x: x) } },
                        Opt(label: "Negotiate a sale", detail: "Sell to them at a good price.") { s, x in
                            if let hi = s.companyIndex(x.d["h"].int) { _ = GroupDeals.sellToGroup(&s, companyIndex: hi, groupID: x.d["g"].string, price: jsRound(value(s.companies[hi], s, x.data) * 1.3), data: x.data, context: x.fc) } },
                        Opt(label: "Defend your strategy in public", detail: "Convince the other shareholders.") { s, x in
                            if let h = s.company(x.d["h"].int) { hostile(&s, h: h, d: x.d, p: 0.5, x: x) } }]))

        // The competition authority.
        L.append(Def(id: "t_antitrust", cls: "crisis", w: 2, tone: "bad", from: "Competition authority", def: 1, global: true,
                     cond: { s, _, data in marketShares(s, data: data).contains { $0.share > 0.35 } },
                     make: { s, _, data, _ in
                         guard let m = marketShares(s, data: data).first(where: { $0.share > 0.35 }) else { return nil }
                         return .object(["k": .string(m.key), "c": .number(Double(m.companyID)), "n": .string(m.name), "s": .number(m.share)]) },
                     pre: { s, x in
                         let a = scaled(s, s.companies[x.i], x.data, 60000)
                         _ = Payments.companyPays(&s, companyID: x.d["c"].int, amount: a, category: "oth", label: "Lawyers: competition case") },
                     title: { _, d, _ in "The competition authority investigates \(d["n"].string)" },
                     body: { _, d, _ in "You hold about \(Int((d["s"].double * 100).rounded()))% of the market. The authority wants to know whether you use that position against customers and rivals. Legal costs have started." },
                     opts: [
                        Opt(label: "Offer to sell part of the business", detail: "Sell this company to end the case.") { s, x in
                            if let ci = s.companyIndex(x.d["c"].int), s.companies[ci].status == .open {
                                _ = CompanySale.complete(&s, companyIndex: ci, buyer: "Competitor", price: jsRound(value(s.companies[ci], s, x.data) * s.random.range(0.92, 1.08)), data: x.data, context: x.fc)
                            } },
                        Opt(label: "Accept conditions", detail: "No price cuts or acquisitions in this market for a year.") { s, x in
                            if let ci = s.companyIndex(x.d["c"].int) {
                                var f = s.companies[ci].value("flags"); f["ac27"] = .number(Double(s.week + 52)); s.companies[ci].set("flags", f)
                                if s.companies[ci].priceLevel < 0 { s.companies[ci].priceLevel = 0 }
                            } },
                        Opt(label: "Fight it", detail: "More legal costs; a fine of several percent of sales if you lose.") { s, x in
                            guard let ci = s.companyIndex(x.d["c"].int) else { return }
                            let c = s.companies[ci]
                            _ = Payments.companyPays(&s, companyID: c.id, amount: scaled(s, c, x.data, 150000), category: "oth", label: "Lawyers: competition case")
                            if s.random.chance(0.45) {
                                let k = x.fc.country(of: c, s)
                                let wk = EventEngine.context(for: c, data: x.data, employerFactor: k.employerCostFactor, costIndex: k.costIndex).wk
                                _ = Payments.companyPays(&s, companyID: c.id, amount: wk * 52 * 0.04, category: "fine", label: "Competition fine")
                            } else { s.note("The authority closed the case against \(c.name).", tone: "good", companyID: c.id) } }]))

        // An activist investor.
        L.append(Def(id: "t_activist", cls: "corp", w: 2, def: 1, global: true,
                     cond: { s, _, data in activistTarget(s, data) != nil },
                     make: { s, _, data, _ in
                         guard let c = activistTarget(s, data), let h = c.value("holders").array.filter({ $0["pct"].double >= 10 }).max(by: { $0["pct"].double < $1["pct"].double }) else { return nil }
                         return .object(["c": .number(Double(c.id)), "n": .string(c.name), "h": h["name"], "p": h["pct"]]) },
                     title: { _, d, _ in "\(d["h"].string) pushes for changes at \(d["n"].string)" },
                     body: { _, d, _ in "\(d["h"].string) (\(String(format: "%.1f", d["p"].double))%) wants higher dividends and lower costs, and says so to the other owners." },
                     opts: [
                        Opt(label: "Adopt their plan", detail: "50% of profit as dividends, and a cost review.") { s, x in
                            guard let ci = s.companyIndex(x.d["c"].int) else { return }
                            s.companies[ci].set("dp27", "mid"); addMod(&s, ci, "cogsup", 0.98, 26); mood(&s, ci, -5); satisfy(&s, ci, 12) },
                        Opt(label: "Meet them halfway", detail: "25% as dividends.") { s, x in
                            guard let ci = s.companyIndex(x.d["c"].int) else { return }
                            s.companies[ci].set("dp27", "low"); satisfy(&s, ci, 5) },
                        Opt(label: "Oppose them", detail: "What happens depends on how many shares they can rally.") { s, x in
                            guard let ci = s.companyIndex(x.d["c"].int) else { return }
                            satisfy(&s, ci, -10)
                            if Shareholders.outside(s.companies[ci]) > 50 { s.companies[ci].set("dp27", "mid"); s.note("The other owners outvoted you: \(s.companies[ci].name) now pays out half its profit.", tone: "bad", companyID: s.companies[ci].id) } }]))

        // An auction of a stake in a foreign group.
        L.append(Def(id: "t_auction", cls: "opp", w: 1, def: 2, global: true,
                     cond: { s, _, data in isTycoon(s, data) && s.cash > scaledHome(s, data, 20e6) && !auctionGroups(s).isEmpty },
                     make: { s, _, _, _ in
                         let gs = auctionGroups(s)
                         guard !gs.isEmpty else { return nil }
                         let ccs = Array(Set(gs.map { $0["cc"].string })).sorted()
                         let cc = ccs[s.random.int(0, ccs.count - 1)]
                         guard let g = gs.filter({ $0["cc"].string == cc }).max(by: { $0["rev"].double < $1["rev"].double }) else { return nil }
                         return .object(["g": g["id"], "n": g["name"], "cc": .string(cc), "v": .number((GroupStakes.value(of: g, s) * 0.3 / 1000).rounded() * 1000)]) },
                     title: { _, d, _ in "A 30% stake in \(d["n"].string) is up for auction" },
                     body: { _, d, cur in "The founding family of \(d["n"].string) (\(d["cc"].string)) is selling 30%. Fair value is about \(cur.display(d["v"].double)). Others are bidding: to win you probably have to pay more, and overpaying destroys value even if your group gets bigger." },
                     opts: [Opt(label: "Bid aggressively", detail: "About 30% above fair value. You probably win.") { s, x in _ = GroupDeals.buyStake(&s, groupID: x.d["g"].string, fraction: 0.3, multiplier: 1.3, chance: 0.8, context: x.fc) },
                            Opt(label: "Partner with another investor", detail: "15% each, at a fair price. You may lose out.") { s, x in _ = GroupDeals.buyStake(&s, groupID: x.d["g"].string, fraction: 0.15, multiplier: 1.1, chance: 0.55, context: x.fc) },
                            Opt(label: "Walk away", detail: "") { _, _ in }]))

        // Japan: a rival with no successor.
        L.append(Def(id: "c_JP_succ", cls: "cty", cc: CountryEvents.country(ofDecision: "JP_succ"), w: 2, tone: "good",
                     cond: { s, co, data in isLocalTrade(co, data) && rivals(s, co).contains { independent($0) && !$0["listed"].bool } },
                     make: { s, i, _, _ in
                         guard let r = rivals(s, s.companies[i]).first(where: { independent($0) && !$0["listed"].bool }) else { return nil }
                         return .object(["r": r["id"], "n": r["name"]]) },
                     title: { _, d, _ in "\(d["n"].string) has no successor" },
                     body: { _, d, _ in "The owner of \(d["n"].string) is retiring and has no one to take over. It is profitable and for sale at a fair price." },
                     auto: { s, x in
                         let key = marketKey(s.companies[x.i]), wk = Double(s.week)
                         editRival(&s, key, x.d["r"].int) { $0["listed"] = true; $0["dist27"] = .number(wk); $0["succ27"] = 1 } }))

        // USA: venture capital wants in.
        L.append(Def(id: "c_US_vc", cls: "cty", cc: CountryEvents.country(ofDecision: "US_vc"), w: 2, def: 2,
                     cond: { s, co, data in
                         let k = Currency(country: data.countries.resolve(co.countryCode, orHome: s.homeCountryCode), rates: ExchangeRates(drift: s.exchangeRates.values))
                         let c = data.countries.resolve(co.countryCode, orHome: s.homeCountryCode)
                         let wk = EventEngine.context(for: co, data: data, employerFactor: c.employerCostFactor, costIndex: c.costIndex).wk
                         return co.form == .limited && co.ownership > 80 && s.week - co.foundedWeek < 156 && wk * 52 > k.scaledPrice(2e6) },
                     make: { s, i, data, _ in .object(["v": .number((value(s.companies[i], s, data) * 1.6 / 1000).rounded() * 1000)]) },
                     title: { co, _, _ in "Venture capital wants to invest in \(co.name)" },
                     body: { co, d, cur in "A fund values \(co.name) at \(cur.display(d["v"].double)) and wants 20% in new shares. Money to grow fast, a board seat for them, and less of the company for you." },
                     opts: [
                        Opt(label: "Take the money", detail: "") { s, x in
                            let c = s.companies[x.i], amt = jsRound(x.d["v"].double * 0.2 / 0.8)
                            Payments.companyReceives(&s, companyID: c.id, amount: amt, category: nil, label: "Venture capital")
                            let who = Funding.fundName(&s, countryCode: c.countryCode, data: x.data, suffix: "Ventures")
                            Funding.addHolder(&s, x.i, name: who, pct: 20 * c.ownership / 100, paid: amt, extra: ["k27": "growth", "sat": 65])
                            s.companies[x.i].ownership = c.ownership * 0.8
                            Funding.addBoardSeats(&s, x.i, 1) },
                        Opt(label: "Borrow instead", detail: "Keep the shares, take on debt.") { s, x in
                            let c = s.companies[x.i], k = x.fc.country(of: c, s)
                            let wk = EventEngine.context(for: c, data: x.data, employerFactor: k.employerCostFactor, costIndex: k.costIndex).wk
                            let nw = Valuation.netWorth(s, trades: x.data.catalog).total
                            _ = Banking.take(kind: "biz", amount: (wk * 52 * 0.2 / 1000).rounded() * 1000, termMonths: 60, company: c, state: &s, netWorth: nw, context: x.fc) },
                        Opt(label: "Grow on your own profits", detail: "") { _, _ in }]))
        return L
    }

    // MARK: Who the corporate decisions are about

    static func peTarget(_ s: GameState, _ data: GameData) -> Company? {
        liveCompanies(s, data).map { s.companies[$0] }.filter { $0.form == .limited && ebit12($0, s) > scaled(s, $0, data, 1e6) && $0.ownership >= 90 }
            .max { value($0, s, data) < value($1, s, data) }
    }
    static func activistTarget(_ s: GameState, _ data: GameData) -> Company? {
        liveCompanies(s, data).map { s.companies[$0] }.first { $0.value("holders").array.contains { $0["pct"].double >= 10 } }
    }
    /// Groups of other countries that you could buy a stake in.
    static func auctionGroups(_ s: GameState) -> [JSONValue] {
        (s.rest["g27"]?["g"].object ?? [:]).sorted { $0.key < $1.key }.map { $0.value }.filter { !$0["gone"].bool && $0["dist"].int == 0 && $0["cc"].string != s.homeCountryCode }
    }
    static func satisfy(_ s: inout GameState, _ i: Int, _ d: Double) {
        var list = s.companies[i].value("holders").array
        for k in list.indices { list[k]["sat"] = .number(clamp((list[k]["sat"].isNull ? 60 : list[k]["sat"].double) + d, 0, 100)) }
        s.companies[i].set("holders", .array(list))
    }
}
