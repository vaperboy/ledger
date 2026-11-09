import Foundation
import GameCore
import Countries
import Finance
import Businesses

// Where the government models meet the player's books. Every money move is a pair: the player or company pays through `Payments` (so the
// ledger stays balanced) and the same whole amount is posted to the treasury, or the treasury pays and the player is credited the same.
// The world is kept in `rest["gov"]` and does not exist until something creates it, so a game that never uses it is unchanged.

public struct GovernmentWorld: Codable, Equatable, Sendable {
    /// The account the player acts as, and the name shown on ballots and the watchlist.
    public var account = "me"
    public var name = "You"
    public var countries: [String: Government] = [:]
    public var justice = Justice()
    public var routes = RouteBook()
    var lastWeek = -1
    var newsSeen: [String: Int] = [:]

    public init() {}
}

public extension GameState {
    var governmentWorld: GovernmentWorld? {
        get {
            guard let v = rest["gov"], let d = try? JSONEncoder().encode(v) else { return nil }
            return try? JSONDecoder().decode(GovernmentWorld.self, from: d)
        }
        set {
            guard let n = newValue, let d = try? JSONEncoder().encode(n), let v = try? JSONDecoder().decode(JSONValue.self, from: d) else { rest["gov"] = nil; return }
            rest["gov"] = v
        }
    }
}

public enum GovernmentBridge {
    // MARK: Access

    public static func world(_ s: GameState) -> GovernmentWorld { s.governmentWorld ?? GovernmentWorld() }

    /// Creates the country's government when it does not exist yet. `admins` come from the server.
    /// A government nobody has used yet (no printing, no money in the treasury, no donations) takes the given supply; a used one keeps its own.
    /// The administrator list follows the server's: the accounts given are added.
    public static func ensure(_ s: inout GameState, country: String, admins: Set<String>, startingSupply: Double) {
        var w = world(s)
        if var g = w.countries[country] {
            if g.supply.mints.isEmpty, g.treasury.entries.isEmpty, g.donations.isEmpty, g.supply.base != max(1, startingSupply) { g.supply = GovMoneySupply(base: startingSupply) }
            g.admins.formUnion(admins)
            w.countries[country] = g
        } else {
            w.countries[country] = Government(country: country, admins: admins, startingSupply: startingSupply)
        }
        s.governmentWorld = w
    }

    /// The home country's government at game start: the supply is a billion in the reference economy, scaled to the country's money, and
    /// `admins` are the account ids the server lists as administrators (empty when there are none). `account` and `name` say who the player is
    /// on ballots and in the audit log; nil keeps what is there.
    public static func ensureHome(_ s: inout GameState, admins: Set<String>, account: String? = nil, name: String? = nil, context: FinanceContext) {
        let cc: String = s.homeCountryCode
        let supply: Double = max(1, context.currency(cc, s).scaledPrice(1_000_000_000))
        ensure(&s, country: cc, admins: admins, startingSupply: supply)
        var w = world(s)
        if let account, !account.isEmpty { w.account = account }
        if let name, !name.isEmpty { w.name = name }
        s.governmentWorld = w
    }

    /// Every government runs on the game's last rules snapshot, else the defaults.
    static func syncRules(_ w: inout GovernmentWorld, _ s: GameState) {
        let r: WorldRules = s.worldRules
        for cc in Array(w.countries.keys) { w.countries[cc]?.activeRules = r }
    }

    public static func citizen(_ s: GameState, _ w: GovernmentWorld) -> GovCitizen {
        GovCitizen(account: w.account, country: s.homeCountryCode, name: w.name, ageWeeks: s.week,
                   barredFromVoting: w.justice.barred(w.account, .vote, week: s.week),
                   barredFromOffice: w.justice.barred(w.account, .office, week: s.week))
    }

    /// Runs a change on one government that needs no money from the player. The closure gets the player's account and the week.
    @discardableResult
    public static func act<T>(_ s: inout GameState, country: String, _ body: (inout Government, String, Int) throws -> T) throws -> T {
        var w = world(s)
        syncRules(&w, s)
        guard var g = w.countries[country] else { throw GovError.notFound }
        let r = try body(&g, w.account, s.week)
        w.countries[country] = g
        flushNews(&s, &w)
        s.governmentWorld = w
        return r
    }

    /// New public news lines of every government go to the player's news.
    static func flushNews(_ s: inout GameState, _ w: inout GovernmentWorld) {
        for cc in w.countries.keys.sorted() {
            guard let g = w.countries[cc] else { continue }
            let seen = w.newsSeen[cc] ?? 0
            for n in g.news.reversed() where n.id > seen { s.news(n.text, tone: n.tone) }
            if let top = g.news.map({ $0.id }).max() { w.newsSeen[cc] = max(seen, top) }
        }
    }

    // MARK: Money moves

    /// A gift to the treasury, in whole units, from the player's own cash.
    public static func donate(_ s: inout GameState, country: String, amount: Double) throws {
        var w = world(s)
        guard var g = w.countries[country] else { throw GovError.notFound }
        let a = jsRound(amount)
        guard a >= 1 else { throw GovError.badAmount("A donation must be at least 1.") }
        guard s.cash >= a else { throw GovError.cannotAfford("You do not have that much cash.") }
        try g.donate(account: w.account, name: w.name, amount: a, week: s.week)
        Payments.playerPays(&s, a, label: "Donation to the treasury")
        w.countries[country] = g
        flushNews(&s, &w)
        s.governmentWorld = w
    }

    /// What standing for president costs here, in whole units of the country's money.
    public static func candidacyFee(_ s: GameState, country: String, context: FinanceContext) -> Double {
        jsRound(context.currency(country, s).scaledPrice(Politics.candidacyFeeReference))
    }

    /// Stands for president: checks everything, takes the fee from the player's cash, enters the candidate. The fee is never returned.
    public static func stand(_ s: inout GameState, country: String, manifesto: String, promises: [CampaignPromise], context: FinanceContext) throws {
        var w = world(s)
        guard var g = w.countries[country] else { throw GovError.notFound }
        let c = citizen(s, w)
        try g.validateStand(c, promises: promises, week: s.week)
        let fee = candidacyFee(s, country: country, context: context)
        guard s.cash >= fee else { throw GovError.cannotAfford("Standing costs \(context.currency(country, s).display(fee)) and it is not refunded.") }
        Payments.playerPays(&s, fee, label: "Candidacy fee")
        try g.stand(c, manifesto: manifesto, promises: promises, fee: fee, week: s.week)
        w.countries[country] = g
        flushNews(&s, &w)
        s.governmentWorld = w
    }

    public static func vote(_ s: inout GameState, country: String, for candidate: String) throws {
        var w = world(s)
        guard var g = w.countries[country] else { throw GovError.notFound }
        try g.castBallot(citizen(s, w), for: candidate, week: s.week)
        w.countries[country] = g
        s.governmentWorld = w
    }

    /// An administrator overturns a conviction of the player: the bans end and the fine comes back out of the treasury.
    public static func quash(_ s: inout GameState, country: String, convictionID: Int) throws {
        var w = world(s)
        guard var g = w.countries[country] else { throw GovError.notFound }
        guard g.isAdmin(w.account) else { throw GovError.notAdmin }
        guard let c = w.justice.convictions.first(where: { $0.id == convictionID && !$0.quashed && $0.account == w.account }) else { throw GovError.notFound }
        if c.fine > 0 { try g.payOut(c.fine, kind: "conviction_refund", ref: String(c.id), week: s.week) }
        _ = w.justice.quash(c.id)
        g.log(w.account, "quash", "conviction \(c.id)", week: s.week)
        if c.fine > 0 { Payments.playerReceives(&s, c.fine, label: "Fine returned: conviction quashed") }
        w.countries[country] = g
        s.governmentWorld = w
    }

    // MARK: Illegal routes and dirty tricks

    public static func routeWarning(_ s: inout GameState, route: IllegalRoute, companyID: Int) -> RouteWarning {
        var w = world(s)
        let r = w.routes.warn(act: "route:\(route.rawValue)", title: route.title, companyID: companyID, week: s.week)
        s.governmentWorld = w
        return r
    }

    public static func beginRoute(_ s: inout GameState, route: IllegalRoute, companyID: Int, token: Int, confirmed: Bool) throws {
        var w = world(s)
        guard let co = s.company(companyID), co.status == .open else { throw GovError.notOpen }
        guard !w.justice.barred(w.account, .trade, week: s.week) else { throw GovError.notEligible("You are banned from trading.") }
        try w.routes.begin(route, companyID: companyID, token: token, confirmed: confirmed, week: s.week)
        s.governmentWorld = w
    }

    public static func stopRoute(_ s: inout GameState, route: IllegalRoute, companyID: Int) {
        var w = world(s)
        w.routes.stop(route, companyID: companyID)
        s.governmentWorld = w
    }

    public static func trickWarning(_ s: inout GameState, kind: DirtyTrick, companyID: Int) -> RouteWarning {
        var w = world(s)
        let r = w.routes.warn(act: "trick:\(kind.rawValue)", title: kind.title, companyID: companyID, week: s.week)
        s.governmentWorld = w
        return r
    }

    public static func trickCost(_ s: GameState, kind: DirtyTrick, companyID: Int, context: FinanceContext) -> Double {
        guard let co = s.company(companyID) else { return 0 }
        return jsRound(context.currency(co.countryCode, s).scaledPrice(kind.costReference))
    }

    /// A capped dirty trick by one of your companies against `target` (a name or id). If the target is a company in this game it loses the
    /// reputation. If the trick is traced back it costs a fine and a short trading ban.
    @discardableResult
    public static func trick(_ s: inout GameState, kind: DirtyTrick, companyID: Int, target: String, token: Int, confirmed: Bool, context: FinanceContext) throws -> TrickOutcome {
        let clean: String = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("rival:"), let id = Int(clean.dropFirst(6)) {
            return try trick(&s, kind: kind, companyID: companyID, rivalID: id, token: token, confirmed: confirmed, context: context)
        }
        return try run(&s, kind: kind, companyID: companyID, targetKey: clean, rivalID: nil, token: token, confirmed: confirmed, context: context)
    }

    /// A dirty trick against a rival business, by the id its rival card carries (`MarketOpportunity.rivalID`, `MarketRivalRow.id`). The rival's
    /// health and its mood towards you fall; a rival that is not on any market is refused before anything is paid.
    @discardableResult
    public static func trick(_ s: inout GameState, kind: DirtyTrick, companyID: Int, rivalID: Int, token: Int, confirmed: Bool, context: FinanceContext) throws -> TrickOutcome {
        guard Rivals.marketKey(ofRival: rivalID, in: s) != nil else { throw GovError.notFound }
        return try run(&s, kind: kind, companyID: companyID, targetKey: "rival:\(rivalID)", rivalID: rivalID, token: token, confirmed: confirmed, context: context)
    }

    private static func run(_ s: inout GameState, kind: DirtyTrick, companyID: Int, targetKey target: String, rivalID: Int?, token: Int, confirmed: Bool,
                            context: FinanceContext) throws -> TrickOutcome {
        var w = world(s)
        guard let i = s.companyIndex(companyID), s.companies[i].status == .open else { throw GovError.notOpen }
        guard !w.justice.barred(w.account, .trade, week: s.week) else { throw GovError.notEligible("You are banned from trading.") }
        guard !target.isEmpty else { throw GovError.badAmount("Name the target.") }
        // Your own companies are never the target: a trick is against someone else.
        if let own = Int(target), s.companyIndex(own) != nil { throw GovError.notEligible("A trick must be against someone else, not one of your own companies.") }
        let cost = trickCost(s, kind: kind, companyID: companyID, context: context)
        guard s.companies[i].cash >= cost else { throw GovError.cannotAfford("The company cannot pay for it.") }
        let out = try w.routes.useTrick(kind, account: w.account, companyID: companyID, target: target, token: token, confirmed: confirmed, week: s.week)
        _ = Payments.companyPays(&s, companyID: companyID, amount: cost, category: "oth", label: kind.title)
        if let rid = rivalID { _ = Rivals.hurt(&s, rivalID: rid, points: out.effect) }
        if out.detected {
            let cc = s.companies[i].countryCode
            let want = jsRound(cost * DirtyTrick.fineMultiple)
            let cash0 = s.companies[i].cash
            _ = Payments.companyPays(&s, companyID: companyID, amount: want, category: "fine", label: "Fine: \(kind.title)")
            let paid = max(0, cash0 - s.companies[i].cash)
            var g = w.countries[cc] ?? Government(country: cc, admins: [], startingSupply: 1_000_000_000)
            g.receive(paid, kind: "conviction_fine", ref: kind.rawValue, week: s.week)
            _ = w.justice.record(account: w.account, name: w.name, kind: kind.convictionKind, summary: "\(kind.title) traced back to you", fine: paid,
                                 country: cc, week: s.week, tradeBanWeeks: DirtyTrick.banWeeks, grave: false)
            w.countries[cc] = g
            s.addMessage(from: "Authorities", title: "Dirty trick traced", body: "\(kind.title) was traced back to \(s.companies[i].name). Fine \(context.currency(cc, s).display(paid)) and a \(DirtyTrick.banWeeks)-week trading ban.",
                         companyID: companyID, tone: "bad")
        }
        s.governmentWorld = w
        return out
    }

    // MARK: The weekly turn

    /// Once a week: elections and terms, the lagged price effect of printing, price support paid to companies, route earnings and audits.
    public static func weekly(_ s: inout GameState, data: GameData, context: FinanceContext) {
        guard var w = s.governmentWorld, s.week > w.lastWeek else { return }
        w.lastWeek = s.week
        syncRules(&w, s)
        let week = s.week
        for cc in w.countries.keys.sorted() {
            guard var g = w.countries[cc] else { continue }
            let justice = w.justice
            g.advance(week: week, canStand: { !justice.barred($0, .office, week: week) }, hasCitizens: cc == s.homeCountryCode)
            if cc == s.homeCountryCode {
                let r = GovInflation.rate(g.supply, week: week)
                if r > 0 { s.economy.inflationIndex *= 1 + r }
            }
            for i in s.companies.indices where s.companies[i].status == .open && s.companies[i].countryCode == cc {
                let rev = s.companies[i].books.week["rev"] ?? 0
                let amt = g.supportPayout(account: w.account, tradeID: s.companies[i].type, weekRevenue: rev, week: week)
                if amt > 0 { Payments.companyReceives(&s, companyID: s.companies[i].id, amount: amt, category: "rev", label: "Price support") }
            }
            w.countries[cc] = g
        }
        for risk in w.routes.risks {
            guard let i = s.companyIndex(risk.companyID), s.companies[i].status.isLive else { w.routes.drop(companyID: risk.companyID); continue }
            let base = s.companies[i].books.week["rev"] ?? 0
            let res = w.routes.step(companyID: risk.companyID, week: week, base: base, open: s.companies[i].status == .open)
            if res.gain > 0 { Payments.companyReceives(&s, companyID: risk.companyID, amount: res.gain, category: "rev", label: "Takings") }
            if let a = res.audit { settle(&s, &w, audit: a, companyIndex: i, data: data, context: context) }
        }
        flushNews(&s, &w)
        s.governmentWorld = w
    }

    /// An audit: the gains handed back and a fine to the treasury, then by level a suspension, or a seizure of the company's cash and
    /// closure with no pay-out to the owner, a conviction and, at the top, the public watchlist.
    static func settle(_ s: inout GameState, _ w: inout GovernmentWorld, audit a: RouteAudit, companyIndex i: Int, data: GameData, context: FinanceContext) {
        let id = s.companies[i].id, name = s.companies[i].name, cc = s.companies[i].countryCode, week = s.week
        let cur = context.currency(cc, s)
        var g = w.countries[cc] ?? Government(country: cc, admins: [], startingSupply: 1_000_000_000)
        let owed = jsRound(a.liability * (RouteRules.backMultiple + RouteRules.fineMultiple(level: a.level)))
        let cash0 = s.companies[i].cash
        _ = Payments.companyPays(&s, companyID: id, amount: owed, category: "fine", label: "Audit: illegal takings")
        var paid = max(0, cash0 - s.companies[i].cash)
        var body = "An audit of \(name) found \(a.route.title.lowercased()). It must hand back and pay \(cur.display(paid))."
        if a.suspends, s.companies[i].status == .open {
            s.companies[i].status = .closed
            s.companies[i].set("closeW", RouteRules.suspensionWeeks); s.companies[i].set("closeTot", RouteRules.suspensionWeeks); s.companies[i].set("idle", 0)
            body += " It is shut for \(RouteRules.suspensionWeeks) weeks."
        }
        if a.closes {
            let seize = max(0, s.companies[i].cash)
            let c1 = s.companies[i].cash
            if seize >= 1 { _ = Payments.companyPays(&s, companyID: id, amount: seize, category: nil, label: "Assets seized") }
            paid += max(0, c1 - s.companies[i].cash)
            // Closed with no pay-out: the owner's share is held at zero while the failure rules settle debts and staff.
            let own = s.companies[i].ownership
            s.companies[i].ownership = 0
            Failure.bankrupt(&s, companyIndex: i, reason: "closed", data: data, context: context, announce: false)
            s.companies[i].ownership = own
            s.credit = clamp(s.credit - RouteRules.closureCreditLoss, 0, 100)
            let pf = jsRound(a.liability * RouteRules.convictionFineMultiple(level: a.level))
            if pf >= 1 { Payments.playerPays(&s, pf, label: "Fine: conviction") }
            let grave = a.grave
            let conv = w.justice.record(account: w.account, name: w.name, kind: a.route.convictionKind, summary: "\(a.route.title) at \(name)", fine: pf, country: cc, week: week,
                                        tradeBanWeeks: RouteRules.tradeBanWeeks(grave: grave), officeBanWeeks: RouteRules.officeBanWeeks(grave: grave), voteBanWeeks: RouteRules.voteBanWeeks(grave: grave), grave: grave)
            g.receive(pf, kind: "conviction_fine", ref: String(conv.id), week: week)
            g.removeFromOffice(account: w.account, reason: "convicted", week: week)
            if grave { g.publish("\(w.name) is on the watchlist: \(conv.summary).", tone: "bad", week: week) }
            s.news("\(name) was shut down by the authorities.", tone: "bad", companyID: id)
            body += " The company is closed and its cash seized, with nothing paid out to you. You are convicted and banned from trading and from office."
            w.routes.drop(companyID: id)
        }
        g.receive(paid, kind: "audit_fine", ref: String(id), week: week)
        g.log("system", "audit", "\(name): level \(a.level)", week: week)
        w.countries[cc] = g
        s.addMessage(from: "Authorities", title: "Audit at \(name)", body: body, companyID: id, tone: "bad")
        s.note("Audit at \(name): \(cur.display(paid)) paid.", tone: "bad", companyID: id)
    }
}
