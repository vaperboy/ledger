import Foundation
import GameCore
import Countries
import Finance

/// What a bought rival becomes, a new site beside a rival, a loan from your own bank for a purchase, and the answers to a rival's price cut.
/// Originals: `absorb`, `ACT.rivhow` (features/people/worker_roles_and_promotions.js, section 3), `ACT.branchgo`, the weekly step
/// `R7.afterCoWeek` (features/world/rivals_holdings_software.js), `bankRoom`, `ACT.rivfin27` (features/company/intercompany_supply.js)
/// and `ACT.rm27` with the week step that ends a matched price (features/world/rival_groups.js).
/// Buying a rival as its own company stays `Rivals.acquire` (`rivclose` with `how: own`). Everything here is an extension of that, so the
/// price, the group's cut and hidden bills are the same.
public enum RivalAbsorb {
    public enum How: String, Sendable, CaseIterable { case merge, shut, branch, franchiseOldOwner = "frold", franchiseNewOwner = "frnew" }

    public enum Outcome: Equatable, Sendable {
        /// Done: the text is what happened, `companyID` the new company (for a branch), `fine` what the competition authority charged.
        case ok(message: String, companyID: Int?, fine: Double)
        case notEnoughCash
        case failed(String)
    }

    /// What each choice needs in the current account on top of the price (the original option buttons).
    public static func extraCost(_ how: How, price: Double) -> Double {
        switch how {
        case .merge: return Rivals.roundTo(price * 0.08, 1000)
        case .shut: return Rivals.roundTo(price * 0.12, 1000)
        default: return 0
        }
    }

    static func rivalOf(_ s: GameState, _ co: Company, _ rivalID: Int) -> Rivals.Rival? { Rivals.rivals(s, for: co).first { $0.id == rivalID } }

    /// The group behind a rival gets the price. Same lines as `Rivals.acquire`.
    static func paySellingGroup(_ s: inout GameState, rival r: Rivals.Rival, price: Double) {
        guard let gid = r.groupID, s.rest["g27"]?["g"][gid] != nil else { return }
        var g = s.rest["g27"]!["g"][gid]
        g["cash"] = .number(g["cash"].double + price)
        g["br"] = .number(Double(max(1, g["br"].int - 1)))
        if g["dist"].double != 0 { g["debt"] = .number(max(0, g["debt"].double - price * 0.8)) }
        RivalGroups.logMove(&g, week: s.week, "Sold \(r.name) to you")
        s.rest["g27"]!["g"][gid] = g
    }

    /// Buy a rival and merge it into your company, close it down, make it your branch, or run it as a franchise office. Original: `ACT.rivhow`.
    public static func absorb(_ s: inout GameState, companyID: Int, rivalID: Int, price: Double, how: How, data: GameData, context fc: FinanceContext) -> Outcome {
        guard let co = s.company(companyID), co.status == .open, let r = rivalOf(s, co, rivalID) else { return .failed("That rival is gone.") }
        switch how {
        case .merge, .shut: return merge(&s, co: co, rival: r, price: price, closing: how == .shut, data: data)
        case .branch:
            switch Rivals.acquire(&s, companyID: companyID, rivalID: rivalID, price: price, data: data, context: fc) {
            case .notEnoughCash: return .notEnoughCash
            case .failed(let m): return .failed(m)
            case .ok(let id):
                let k = s.companies.filter { !$0.value("branch").isNull && $0.value("branch")["of"].int == companyID }.count + 2
                guard let i = s.companyIndex(id) else { return .failed("The new company could not be found.") }
                s.companies[i].name = "\(co.name) \(k)"
                s.companies[i].set("branch", .object(["of": .number(Double(companyID))]))
                s.companies[i].awareness = max(s.companies[i].awareness, co.awareness * 0.9)
                s.companies[i].reputation = max(s.companies[i].reputation, co.reputation * 0.95)
                return .ok(message: "\(r.name) is now \(s.companies[i].name).", companyID: id, fine: 0)
            }
        case .franchiseOldOwner, .franchiseNewOwner:
            return franchiseOffice(&s, co: co, rival: r, price: price, oldOwner: how == .franchiseOldOwner, data: data)
        }
    }

    private static func merge(_ s: inout GameState, co: Company, rival r: Rivals.Rival, price: Double, closing: Bool, data: GameData) -> Outcome {
        let extra = extraCost(closing ? .shut : .merge, price: price)
        guard s.cash >= price + extra, let ci = s.companyIndex(co.id) else { return .notEnoughCash }
        Payments.playerPays(&s, price, label: "Bought \(r.name)", companyID: co.id)
        Payments.playerPays(&s, extra, label: closing ? "Closing \(r.name)" : "Merging \(r.name) into \(co.name)", companyID: co.id)
        paySellingGroup(&s, rival: r, price: price)
        Rivals.removeRival(&s, key: Rivals.key(co), id: r.id)
        let sz = r.size
        if !closing {
            s.companies[ci].awareness = min(100, s.companies[ci].awareness + 6 + sz * 8)
            s.companies[ci].set("wom", s.companies[ci].num("wom") + 6)
            s.companies[ci].reputation = min(100, s.companies[ci].reputation + 1)
            let roles = (data.catalog[co.type]?.standardStaff ?? []).map { $0.role }.filter { data.catalog.tables.roles[$0] != nil }
            let owner = s.companies[ci]
            var came = 0
            if !roles.isEmpty {
                for n in 0..<max(1, Int(jsRound(sz * 2))) {
                    let cand = Hiring.generateCandidate(role: roles[n % roles.count], company: owner, faces: false, state: &s, data: data)
                    if Hiring.hire(cand.id, into: co.id, monthlyWage: cand.askingMonthlyWage, state: &s, data: data) == .ok { came += 1 }
                }
            }
            let text = "\(r.name) is now part of \(co.name). Their customers come over" + (came > 0 ? ", and \(came) of their staff \(came == 1 ? "joins" : "join") you" : "") + "."
            s.note(text, tone: "good", companyID: co.id)
            return .ok(message: text, companyID: nil, fine: 0)
        }
        s.companies[ci].awareness = min(100, s.companies[ci].awareness + 2 + sz * 4)
        // closing a rival when you already hold most of the market draws the competition authority
        var fine = 0.0
        if let m = MarketMap.market(of: s.companies[ci], s, data: data) {
            let share = MarketMap.truth(s, m, data: data).share
            if share > 0.35, s.random.chance(min(0.8, 0.25 + (share - 0.35))) {
                let cur = World(state: s, data: data).currency(s.companies[ci])
                fine = Rivals.roundTo(max(cur.scaledPrice(100000), s.companies[ci].lastWeekRevenue * 52 * 0.03), 1000)
                Payments.companyPays(&s, companyID: co.id, amount: fine, category: "fine", label: "Competition authority: closing \(r.name)")
                s.companies[ci].reputation = max(0, s.companies[ci].reputation - 4)
                s.news("The competition authority fines \(co.name) for buying and closing \(r.name).", tone: "bad")
            }
        }
        let share = MarketMap.market(of: s.companies[ci], s, data: data).map { MarketMap.truth(s, $0, data: data).share } ?? 0
        let text = "\(r.name) has closed. \(co.name) has one competitor less" + (fine > 0 ? ", but the competition authority fined you: you hold \(Int((share * 100).rounded()))% of the market." : ".")
        s.note(text, tone: fine > 0 ? "bad" : "good", companyID: co.id)
        return .ok(message: text, companyID: nil, fine: fine)
    }

    private static func franchiseOffice(_ s: inout GameState, co: Company, rival r: Rivals.Rival, price: Double, oldOwner old: Bool, data: GameData) -> Outcome {
        let f0 = co.value("fr")
        guard f0["on"].bool, let ci = s.companyIndex(co.id), let country = data.countries[co.countryCode] else { return .failed("Franchise offices need your franchise system first.") }
        let back = old ? 0 : Rivals.roundTo(price * s.random.range(0.45, 0.6), 1000)
        guard s.cash >= price - back else { return .notEnoughCash }
        Payments.playerPays(&s, price, label: "Bought \(r.name)", companyID: co.id)
        if back > 0 { Payments.playerReceives(&s, back, label: "Franchisee takes over \(r.name)", companyID: co.id) }
        paySellingGroup(&s, rival: r, price: price)
        Rivals.removeRival(&s, key: Rivals.key(co), id: r.id)
        let nm = old ? (r.owner.isEmpty ? Hiring.personName(country, &s.random) : r.owner) : Hiring.personName(country, &s.random)
        let skill = Double(old ? s.random.int(60, 82) : s.random.int(40, 80))
        let term = f0["term"].isNull ? 10.0 : f0["term"].double
        let unit: JSONValue = .object(["id": .number(Double(s.makeID())), "name": .string(nm), "city": .string(co.cityID), "w0": .number(Double(s.week - 40)), "skill": .number(skill),
                                       "rev": 0, "prof": 0, "neg": 0, "setup": 0, "end": .number(Double(s.week) + term * 52), "owed": 0, "late": 0, "term": .number(term),
                                       "q": .number(clamp(skill + Double(s.random.int(-10, 10)), 20, 95)), "loc": .number(s.random.gauss() * 0.045), "from": .string(r.name)])
        var f = s.companies[ci].value("fr")
        var units = f["units"].array; units.append(unit); f["units"] = .array(units)
        f["brand"] = .number(min(100, f["brand"].double + 2))
        s.companies[ci].set("fr", f)
        Payments.companyReceives(&s, companyID: co.id, amount: (f["fee"].double * (old ? 0.5 : 1)).rounded(), category: "rev", label: "Franchise fee: \(nm)")
        s.companies[ci].awareness = min(100, s.companies[ci].awareness + 3)
        let text = "\(r.name) now runs as a \(co.name) franchise office, led by \(nm)."
        s.note(text, tone: "good", companyID: co.id)
        return .ok(message: text, companyID: nil, fine: 0)
    }

    // MARK: A new site next to a rival

    public enum BranchResult: Equatable, Sendable { case ok(companyID: Int), needsFranchisePapers, notEnoughCash, failed(String) }

    /// Register a second site beside a rival. It starts in set-up like any new company, knows your name from day one and takes customers from
    /// that rival every week it is open (`weekly`). Original: `ACT.branchgo`.
    public static func openBranchNextToRival(_ s: inout GameState, companyID: Int, rivalID: Int, data: GameData, context fc: FinanceContext) -> BranchResult {
        guard let co = s.company(companyID), co.status == .open, rivalOf(s, co, rivalID) != nil else { return .failed("That rival is gone.") }
        guard co.value("docs")["fran"]["st"].string == "ok" else { return .needsFranchisePapers }
        let n0 = s.companies.filter { $0.type == co.type && $0.name.hasPrefix(co.name) }.count
        switch CompanySetup.create(&s, tradeID: co.type, cityID: co.cityID, form: co.form, name: "\(co.name) \(n0 + 1)", countryCode: co.countryCode, data: data, context: fc) {
        case .failure(.notEnoughCash): return .notEnoughCash
        case .failure(let e): return .failed("Could not start the site: \(e)")
        case .success(let id):
            guard let i = s.companyIndex(id) else { return .failed("The new company could not be found.") }
            s.companies[i].set("branch", .object(["of": .number(Double(companyID)), "r": .number(Double(rivalID))]))
            s.companies[i].awareness = max(s.companies[i].awareness, co.awareness * 0.6)
            s.companies[i].reputation = max(s.companies[i].reputation, co.reputation * 0.9)
            var docs = s.companies[i].value("docs"); docs["fran"] = co.value("docs")["fran"]; s.companies[i].set("docs", docs)
            return .ok(companyID: id)
        }
    }

    // MARK: A purchase paid with a loan from your own bank

    /// How much your own bank may lend its owner for a purchase: a quarter of its capital less what it already lent you, no more than 80%
    /// of its cash, and only while its capital ratio is above the minimum. Original: `bankRoom`.
    public static func bankRoom(_ s: GameState, bankID: Int, data: GameData) -> Double {
        guard let b = s.company(bankID), b.status == .open, b.type == "bank" else { return 0 }
        let fm = b.value("fm")
        guard !fm.isNull else { return 0 }
        let eq = max(0, fm["equity"].isNull ? b.cash + fm["book"].double - fm["dep"].double : fm["equity"].double)
        let used = s.loans.filter { $0.bankCompanyID == b.id }.reduce(0) { $0 + $1.balance }
        let req = data.catalog[b.type]?.trait("capitalReq") ?? 0.16
        guard fm["cr"].double >= req else { return 0 }
        return max(0, min(eq * 0.25 - used, b.cash * 0.8))
    }

    /// Your own bank, if you have an open one.
    public static func ownBank(_ s: GameState) -> Company? { s.companies.first { $0.type == "bank" && $0.status == .open } }

    public enum FinanceResult: Equatable { case ok(Rivals.AcquireResult), bankCannotLend }

    /// Borrow `amount` from your own bank (96 months, at the policy rate plus your credit margin and a point) and buy the rival with it.
    /// If the purchase is refused the loan is undone. Original: `ACT.rivfin27` then `ACT.rivclose`.
    public static func buyWithOwnBank(_ s: inout GameState, companyID: Int, rivalID: Int, price: Double, amount: Double, data: GameData, context fc: FinanceContext) -> FinanceResult {
        guard let bank = ownBank(s), amount <= bankRoom(s, bankID: bank.id, data: data) + 1, amount > 0, let bi = s.companyIndex(bank.id) else { return .bankCannotLend }
        let backup = s
        var l = Loan(raw: [:])
        l.id = s.makeID(); l.kind = "biz"; l.name = "Acquisition loan from \(bank.name)"
        l.balance = amount; l.originalAmount = amount
        l.margin = Banking.creditMargin(s.credit) + 0.01
        l.termMonths = 96; l.companyID = 0; l.startWeek = s.week; l.isGuaranteed = false; l.bankCompanyID = bank.id
        l.monthlyPayment = Loans.annuity(principal: amount, yearlyRate: s.economy.policyRate + l.margin, months: 96)
        Ledger.moveRaw(&s, .company(bank.id), -amount)
        var fm = s.companies[bi].value("fm"); fm["gb"] = .number(fm["gb"].double + amount); s.companies[bi].set("fm", fm)
        s.loans.append(l)
        Payments.playerReceives(&s, amount, label: "Acquisition loan from \(bank.name)")
        let r = Rivals.acquire(&s, companyID: companyID, rivalID: rivalID, price: price, data: data, context: fc)
        if case .ok = r { Ambitions.countEvent(&s, "buy"); Ambitions.countEvent(&s, "bankfin") } else { s = backup }
        return .ok(r)
    }

    // MARK: Answering a rival's price cut

    public enum Counter: String, Sendable, CaseIterable { case match, quality, brand }
    public enum CounterResult: Equatable, Sendable { case done(String), alreadyLowest, notEnoughCash, newCompany(Int), failed(String) }

    /// The running price cut of a rival against you, if it is still on and unanswered.
    public static func priceCut(_ s: GameState, companyID: Int, rivalID: Int) -> (pct: Int, end: Int, answered: String?)? {
        guard let co = s.company(companyID), let raw = s.rest["mk"]?[Rivals.key(co)]["riv"].array.first(where: { $0["id"].int == rivalID }), !raw["uc27"].isNull else { return nil }
        let u = raw["uc27"]
        return (u["pct"].int, u["end"].int, u["resp"].isNull ? nil : u["resp"].string)
    }

    /// Match their price, hold prices and sell quality, or add a cheap second brand. Original: `ACT.rm27`.
    public static func answerPriceCut(_ s: inout GameState, companyID: Int, rivalID: Int, answer k: Counter, data: GameData, context fc: FinanceContext) -> CounterResult {
        guard let ci = s.companyIndex(companyID), let cut = priceCut(s, companyID: companyID, rivalID: rivalID), cut.answered == nil else { return .failed("This has passed.") }
        let co = s.companies[ci], key = Rivals.key(co), left = max(1, cut.end - s.week)
        let wanted = 1 - Double(cut.pct) / 300   // the demand effect the cut put on your company (`RivalGroups` "undercut")
        func soften(_ s: inout GameState, to f: (Double) -> Double) {
            var mods = s.companies[ci].value("mods").array
            if let m = mods.firstIndex(where: { $0["k"].string == "dem" && abs($0["m"].double - wanted) < 1e-9 }) { mods[m]["m"] = .number(f(mods[m]["m"].double)) }
            s.companies[ci].set("mods", .array(mods))
        }
        func answered(_ s: inout GameState, _ text: String) { Rivals.mutate(&s, key: key, id: rivalID) { $0["uc27"]["resp"] = .string(text) } }
        switch k {
        case .match:
            guard co.priceLevel > -3 else { return .alreadyLowest }
            var f = co.value("flags"); f["match27"] = .object(["prev": .number(co.priceLevel), "end": .number(Double(cut.end))]); s.companies[ci].set("flags", f)
            s.companies[ci].priceLevel = co.priceLevel - 1
            soften(&s) { _ in 1 }
            answered(&s, "matched their price")
            return .done("Prices lowered at \(co.name) until the cut ends.")
        case .quality:
            let q = Rivals.roundTo(co.lastWeekRevenue * 0.03 * Double(min(6, left)), 1)
            guard co.cash >= q else { return .notEnoughCash }
            Payments.companyPays(&s, companyID: companyID, amount: q, category: "mkt", label: "Campaign: why we are better")
            soften(&s) { 1 - (1 - $0) * 0.5 }
            s.companies[ci].reputation = min(100, s.companies[ci].reputation + 2)
            answered(&s, "held prices and sold quality")
            return .done("Campaign running.")
        case .brand:
            guard let bd = data.catalog[co.type] else { return .failed("Unknown trade.") }
            let first = co.name.split(separator: " ").first.map(String.init) ?? co.name
            switch CompanySetup.create(&s, tradeID: co.type, cityID: co.cityID, form: .limited, size: max(bd.minSize, min(bd.maxSize, 0.5)), name: "\(first) Express", countryCode: co.countryCode, data: data, context: fc) {
            case .failure(.notEnoughCash): return .notEnoughCash
            case .failure(let e): return .failed("Could not start the second brand: \(e)")
            case .success(let id):
                if let i = s.companyIndex(id) {
                    s.companies[i].priceLevel = -2
                    var f = s.companies[i].value("flags"); f["brand27"] = .number(Double(companyID)); s.companies[i].set("flags", f)
                }
                answered(&s, "started a cheap second brand")
                return .newCompany(id)
            }
        }
    }

    // MARK: Weekly

    /// A matched price returns to normal when the rival's cut ends; a site beside a rival takes customers from it. Original: `rival_groups.js` week step
    /// (`match27`) and `R7.afterCoWeek`.
    static func weekly(_ s: inout GameState) {
        for i in s.companies.indices where s.companies[i].status.isLive {
            let flags = s.companies[i].value("flags")
            if !flags["match27"].isNull, Double(s.week) >= flags["match27"]["end"].double {
                s.companies[i].priceLevel = flags["match27"]["prev"].double
                var f = flags; f["match27"] = .null; s.companies[i].set("flags", f)
                s.note("\(s.companies[i].name) is back at its normal prices.", companyID: s.companies[i].id)
            }
            let br = s.companies[i].value("branch")
            if s.companies[i].status == .open, !br["r"].isNull {
                let co = s.companies[i]
                if Rivals.rivals(s, for: co).contains(where: { $0.id == br["r"].int }) {
                    Rivals.mutate(&s, key: Rivals.key(co), id: br["r"].int) { $0["size"] = .number(max(0.3, jsRound(($0["size"].double - 0.006) * 1000) / 1000)) }
                    s.companies[i].awareness = min(100, s.companies[i].awareness + 0.2)
                }
            }
        }
    }
}
