import Foundation
import GameCore
import Countries
import Finance

public enum PlayerDeals {
    public static let offerDays: [Int] = [1, 3, 7, 14, 30]

    public static func today(_ s: GameState) -> Int { s.week * 7 + s.day }

    public static func daysText(_ days: Int) -> String { days == 1 ? "1 day" : "\(days) days" }

    public enum OpenResult: Equatable, Sendable { case ok(untilDay: Int), notFranchising, badDays }

    public static func franchiseOpenUntil(_ co: Company) -> Int? {
        let u = co.value("fr")["po"]["until"]
        return u.isNull ? nil : u.int
    }

    public static func isOpenToPlayers(_ s: GameState, companyID: Int) -> Bool {
        guard let co = s.company(companyID), let u = franchiseOpenUntil(co) else { return false }
        return u >= today(s)
    }

    @discardableResult
    public static func openFranchiseOffer(_ s: inout GameState, companyID: Int, days: Int) -> OpenResult {
        guard offerDays.contains(days) else { return .badDays }
        guard let i = s.companyIndex(companyID), s.companies[i].status.isLive, s.companies[i].value("fr")["on"].bool else { return .notFranchising }
        var f = s.companies[i].value("fr")
        let until = today(s) + days
        f["po"] = .object(["until": .number(Double(until)), "from": .number(Double(today(s)))])
        s.companies[i].set("fr", f)
        return .ok(untilDay: until)
    }

    public static func closeFranchiseOffer(_ s: inout GameState, companyID: Int) {
        guard let i = s.companyIndex(companyID) else { return }
        var f = s.companies[i].value("fr")
        guard !f["po"].isNull else { return }
        f["po"] = .null
        f["app"] = .array(f["app"].array.filter { !$0["pl"].bool })
        s.companies[i].set("fr", f)
    }

    public struct PlayerApplicant: Equatable, Sendable {
        public var name: String
        public var profileCode: String
        public var cityID: String
        public var capital: Double
        public var skill: Double
        public var experience: Int
        public var age: Int
        public init(name: String, profileCode: String, cityID: String, capital: Double, skill: Double, experience: Int = 0, age: Int = 30) {
            self.name = name; self.profileCode = profileCode; self.cityID = cityID; self.capital = capital; self.skill = skill; self.experience = experience; self.age = age
        }
    }

    @discardableResult
    public static func addPlayerApplicant(_ s: inout GameState, companyID: Int, applicant a: PlayerApplicant) -> Bool {
        guard isOpenToPlayers(s, companyID: companyID), let i = s.companyIndex(companyID), a.capital > 0, !a.name.isEmpty, !a.profileCode.isEmpty else { return false }
        var f = s.companies[i].value("fr")
        guard f["on"].bool, f["units"].array.count + f["app"].array.count < 14 else { return false }
        var apps = f["app"].array
        if apps.contains(where: { $0["pc"].string == a.profileCode }) || f["units"].array.contains(where: { $0["pc"].string == a.profileCode }) { return false }
        let pers = a.skill >= 70 ? "careful" : a.skill >= 50 ? "eager" : "tough"
        apps.append(.object(["id": .number(Double(s.makeID())), "name": .string(a.name), "city": .string(a.cityID), "capital": .number(a.capital), "skill": .number(min(95, max(20, a.skill))),
                             "exp": .number(Double(max(0, a.experience))), "pers": .string(pers), "age": .number(Double(a.age)), "w": .number(Double(s.week)),
                             "pat": .number(Franchising.patience[pers] ?? 3), "pl": .bool(true), "pc": .string(a.profileCode)]))
        f["app"] = .array(apps)
        s.companies[i].set("fr", f)
        s.addMessage(kind: "info", from: a.name, title: "A player wants a unit of \(s.companies[i].name)", body: "\(a.name) (\(a.profileCode)) applied to your franchise. Talk terms before the offer ends.",
                     companyID: companyID, tone: "good")
        return true
    }

    public struct FranchiseListing: Identifiable, Equatable, Sendable {
        public var id: String
        public var ownerID: String
        public var ownerName: String
        public var profileCode: String
        public var linkKey: String
        public var isFriend: Bool
        public var brandName: String
        public var tradeID: String
        public var countryCode: String
        public var baseFee: Double
        public var royalty: Double
        public var marketingFund: Double
        public var support: Int
        public var termYears: Int
        public var units: Int
        public var strength: Double
        public var standard: Double
        public var expiresDay: Int

        public init(id: String, ownerID: String, ownerName: String, profileCode: String, linkKey: String, isFriend: Bool = false, brandName: String, tradeID: String,
                    countryCode: String, baseFee: Double, royalty: Double, marketingFund: Double, support: Int, termYears: Int, units: Int, strength: Double, standard: Double,
                    expiresDay: Int) {
            self.id = id; self.ownerID = ownerID; self.ownerName = ownerName; self.profileCode = profileCode; self.linkKey = linkKey; self.isFriend = isFriend
            self.brandName = brandName; self.tradeID = tradeID; self.countryCode = countryCode; self.baseFee = baseFee; self.royalty = royalty; self.marketingFund = marketingFund
            self.support = support; self.termYears = termYears; self.units = units; self.strength = strength; self.standard = standard; self.expiresDay = expiresDay
        }

        public func isOpen(today: Int) -> Bool { today <= expiresDay }
    }

    public static func franchiseListing(_ s: GameState, companyID: Int, ownerID: String, ownerName: String, profileCode: String, linkKey: String, data: GameData) -> FranchiseListing? {
        guard let co = s.company(companyID), co.status.isLive, let until = franchiseOpenUntil(co), until >= today(s) else { return nil }
        let f = co.value("fr")
        guard f["on"].bool else { return nil }
        let cur = World(state: s, data: data).currency(co)
        let ref = max(0.0001, cur.scaledPrice(100_000) / 100_000)
        let units = f["units"].array.count + 1
        return FranchiseListing(id: "F\(co.id)", ownerID: ownerID, ownerName: ownerName, profileCode: profileCode, linkKey: linkKey, brandName: co.name, tradeID: co.type,
                                countryCode: co.countryCode, baseFee: f["fee"].double / ref, royalty: f["roy"].double, marketingFund: f["mkt"].isNull ? 0.02 : f["mkt"].double,
                                support: min(2, max(0, f["supp"].int)), termYears: f["term"].isNull ? 10 : f["term"].int, units: units,
                                strength: min(100, max(5, f["brand"].double)), standard: 60, expiresDay: until)
    }

    static func brand(from l: FranchiseListing) -> FranchiseBrands.Brand {
        FranchiseBrands.Brand(id: "P:" + l.id, tradeID: l.tradeID, name: l.brandName, origin: l.countryCode, tier: 1, tierName: "Run by a player", units: l.units, strength: l.strength,
                              openness: "open", royalty: l.royalty, marketingFund: l.marketingFund, support: l.support, termYears: l.termYears, failPercent: 12, standard: l.standard,
                              flex: 50, baseFee: l.baseFee, contact: l.ownerName, fitMultiplier: 1)
    }

    public struct CompanyListing: Identifiable, Equatable, Sendable {
        public var id: String
        public var ownerID: String
        public var ownerName: String
        public var profileCode: String
        public var linkKey: String
        public var isFriend: Bool
        public var companyName: String
        public var tradeID: String
        public var cityID: String
        public var countryCode: String
        public var size: Double
        public var yearlyRevenue: Double
        public var yearlyProfit: Double
        public var staff: Int
        public var reputation: Double
        public var weeksTrading: Int
        public var askPrice: Double
        public var expiresDay: Int
        /// The company's loans, which a buyer takes off the price.
        public var debt: Double = 0
        /// What the company owns less its bills, before loans; a floor under the earnings value.
        public var netAssets: Double = 0

        public init(id: String, ownerID: String, ownerName: String, profileCode: String, linkKey: String, isFriend: Bool = false, companyName: String, tradeID: String,
                    cityID: String, countryCode: String, size: Double, yearlyRevenue: Double, yearlyProfit: Double, staff: Int, reputation: Double, weeksTrading: Int,
                    askPrice: Double, expiresDay: Int) {
            self.id = id; self.ownerID = ownerID; self.ownerName = ownerName; self.profileCode = profileCode; self.linkKey = linkKey; self.isFriend = isFriend
            self.companyName = companyName; self.tradeID = tradeID; self.cityID = cityID; self.countryCode = countryCode; self.size = size; self.yearlyRevenue = yearlyRevenue
            self.yearlyProfit = yearlyProfit; self.staff = staff; self.reputation = reputation; self.weeksTrading = weeksTrading; self.askPrice = askPrice; self.expiresDay = expiresDay
        }

        public func isOpen(today: Int) -> Bool { today <= expiresDay }
    }

    /// What a buyer pays for the shares: earnings value (only for a profitable company) or net assets, whichever is higher, less the loans.
    public static func value(_ l: CompanyListing) -> Double {
        let profit = max(0, l.yearlyProfit)
        let byTakings = min(max(0, l.yearlyRevenue) * 0.3, profit * 6)
        let earnings = max(byTakings, profit * 3.5) * (0.8 + min(100, max(0, l.reputation)) / 250)
        return jsRound(max(0, max(earnings, l.netAssets) - max(0, l.debt)))
    }

    /// Fills in the loans and net assets a buyer looks at.
    public static func withBalanceSheet(_ l: CompanyListing, _ co: Company, state s: GameState) -> CompanyListing {
        var x = l
        x.debt = s.loans.filter { $0.companyID == co.id }.reduce(0) { $0 + $1.balance }
        x.netAssets = max(0, CompanyFigures.assets(co) - CompanyFigures.billsOwed(co))
        return x
    }

    public static let sellerFloor = 0.85

    public enum Reply: Equatable, Sendable {
        case accept
        case counter(Double)
        case refuse
    }

    public static func reply(to offer: Double, on l: CompanyListing, round: Int) -> Reply {
        guard offer.isFinite, offer > 0 else { return .refuse }
        let lowest = max(value(l) * sellerFloor, l.askPrice * 0.8)
        if offer >= min(l.askPrice, lowest) { return .accept }
        guard round < 3, offer >= lowest * 0.85 else { return .refuse }
        return .counter(min(l.askPrice, ((lowest + l.askPrice) / 2 / 1000).rounded(.up) * 1000))
    }

    public struct BuyPlan: Equatable, Sendable {
        public var price: Double
        public var startupMoney: Double
        public var integration: Double
        public var cashNeeded: Double
        public var affordable: Bool
        public var cash: Double
    }

    public static func buyPlan(_ s: GameState, listing l: CompanyListing, price: Double, data: GameData) -> BuyPlan? {
        guard let bd = data.catalog[l.tradeID], price > 0, price.isFinite else { return nil }
        let size = clamp(l.size * 0.8, bd.minSize, bd.maxSize)
        guard let est = CompanySetup.estimate(tradeID: l.tradeID, cityID: l.cityID, size: size, countryCode: l.countryCode, state: s, data: data) else { return nil }
        let startup = jsRound(est.total * 1.15)
        let integration = jsRound(price * Rivals.integrationShare)
        let need = price + startup + integration
        let cash = Payments.liquid(s)
        return BuyPlan(price: price, startupMoney: startup, integration: integration, cashNeeded: need, affordable: cash >= need, cash: cash)
    }

    public enum BuyResult: Equatable, Sendable { case ok(companyID: Int), notEnoughCash, notAllowed(String) }

    public static func buy(_ s: inout GameState, listing l: CompanyListing, price: Double, buyerLinkKeys: Set<String>, data: GameData, context fc: FinanceContext) -> BuyResult {
        if buyerLinkKeys.contains(l.linkKey) { return .notAllowed("Not available: linked account") }
        if !l.isOpen(today: today(s)) { return .notAllowed("This listing has ended.") }
        guard reply(to: price, on: l, round: 0) == .accept else { return .notAllowed("The seller would not take that.") }
        guard let plan = buyPlan(s, listing: l, price: price, data: data), let bd = data.catalog[l.tradeID] else { return .notAllowed("This business cannot be set up here.") }
        guard plan.affordable else { return .notEnoughCash }
        let size = clamp(l.size * 0.8, bd.minSize, bd.maxSize)
        guard case .success(let id) = CompanySetup.create(&s, tradeID: l.tradeID, cityID: l.cityID, size: size, name: l.companyName, countryCode: l.countryCode, data: data, context: fc) else {
            return .notAllowed("The new company could not be set up.")
        }
        Payments.playerPays(&s, price, label: "Purchase of \(l.companyName) from \(l.ownerName)", companyID: id)
        _ = CompanySetup.quickSetup(&s, companyID: id, data: data)
        if plan.integration > 0 { _ = Payments.companyPays(&s, companyID: id, amount: plan.integration, category: "oth", label: "Integration of \(l.companyName): merging systems and suppliers") }
        if let i = s.companyIndex(id) {
            s.companies[i].reputation = max(s.companies[i].reputation, min(80, 40 + l.reputation * 0.4))
            s.companies[i].awareness = max(s.companies[i].awareness, 30 + l.size * 15)
            PriceMoves.addModifier(&s, i, key: "dem", multiplier: 1 - Rivals.loyaltyDip, weeks: Double(Rivals.loyaltyDipWeeks))
            var flags = s.companies[i].value("flags"); flags["acq"] = .number(Double(s.week)); flags["integ"] = .number(Double(s.week)); s.companies[i].set("flags", flags)
            _ = OpeningChecklist.open(&s, companyIndex: i, data: data)
        }
        s.note("You bought \(l.companyName) from \(l.ownerName). Its customers now belong to you.", tone: "good", companyID: id)
        return .ok(companyID: id)
    }

    public static func listing(_ s: GameState, companyID: Int, ownerID: String, ownerName: String, profileCode: String, linkKey: String, askPrice: Double, data: GameData) -> CompanyListing? {
        guard let co = s.company(companyID), co.status.isLive, let until = playerListingUntil(s, companyID: companyID), until >= today(s) else { return nil }
        let rev = (co.books.year["rev"] ?? 0) > 0 ? co.books.year["rev"]! : co.lastWeekRevenue * 52
        let l = CompanyListing(id: "C\(co.id)", ownerID: ownerID, ownerName: ownerName, profileCode: profileCode, linkKey: linkKey, companyName: co.name, tradeID: co.type, cityID: co.cityID,
                               countryCode: co.countryCode, size: co.size, yearlyRevenue: rev, yearlyProfit: CompanyFigures.yearlyProfitEstimate(co, currentWeek: s.week), staff: co.staff.count,
                               reputation: co.reputation, weeksTrading: max(0, s.week - (co.openedWeek ?? s.week)), askPrice: askPrice, expiresDay: until)
        return withBalanceSheet(l, co, state: s)
    }

    public static func playerListingUntil(_ s: GameState, companyID: Int) -> Int? {
        guard let raw = (s.rest["sales"]?.array ?? []).first(where: { $0["co"].int == companyID }), !raw["pl"].isNull else { return nil }
        return raw["pl"].int
    }

    @discardableResult
    public static func showToPlayers(_ s: inout GameState, companyID: Int, days: Int) -> Bool {
        guard offerDays.contains(days) else { return false }
        var list = s.rest["sales"]?.array ?? []
        guard let k = list.firstIndex(where: { $0["co"].int == companyID }), list[k]["pct"].isNull || list[k]["pct"].int == 100 else { return false }
        list[k]["pl"] = .number(Double(today(s) + days))
        s.rest["sales"] = .array(list)
        return true
    }

    public static func hideFromPlayers(_ s: inout GameState, companyID: Int) {
        var list = s.rest["sales"]?.array ?? []
        guard let k = list.firstIndex(where: { $0["co"].int == companyID }), !list[k]["pl"].isNull else { return }
        list[k]["pl"] = .null
        list[k]["offers"] = .array(list[k]["offers"].array.filter { $0["k"].string != "player" })
        s.rest["sales"] = .array(list)
    }

    public static func weekly(_ s: inout GameState) {
        let now = today(s)
        for i in s.companies.indices {
            let co = s.companies[i]
            if let u = franchiseOpenUntil(co), u < now {
                closeFranchiseOffer(&s, companyID: co.id)
                s.addMessage(kind: "info", from: co.name, title: "Your franchise offer to players ended",
                             body: "Players who had not signed have left. Open it again to take new applicants.", companyID: co.id, tone: "n")
            }
        }
        var list = s.rest["sales"]?.array ?? []
        var changed = false
        for k in list.indices where !list[k]["pl"].isNull && list[k]["pl"].int < now {
            list[k]["pl"] = .null
            changed = true
        }
        if changed { s.rest["sales"] = .array(list) }
    }
}
