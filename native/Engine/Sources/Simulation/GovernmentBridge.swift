import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct GovernmentWorld: Codable, Equatable, Sendable {
    public var account = "me"
    public var name = "You"
    public var government: Government?
    public var justice = Justice()
    public var routes = RouteBook()
    var lastWeek = -1
    var newsSeen = 0

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

    public static func world(_ s: GameState) -> GovernmentWorld { s.governmentWorld ?? GovernmentWorld() }

    public static func ensure(_ s: inout GameState, admins: Set<String>, startingSupply: Double) {
        var w = world(s)
        if var g = w.government {
            if g.supply.mints.isEmpty, g.treasury.entries.isEmpty, g.donations.isEmpty, g.supply.base != max(1, startingSupply) { g.supply = GovMoneySupply(base: startingSupply) }
            g.admins.formUnion(admins)
            w.government = g
        } else {
            w.government = Government(admins: admins, startingSupply: startingSupply)
        }
        s.governmentWorld = w
    }

    public static func ensureHome(_ s: inout GameState, admins: Set<String>, account: String? = nil, name: String? = nil, context: FinanceContext) {
        let supply: Double = max(1, context.homeCurrency(s).scaledPrice(1_000_000_000))
        ensure(&s, admins: admins, startingSupply: supply)
        var w = world(s)
        if let account, !account.isEmpty { w.account = account }
        if let name, !name.isEmpty { w.name = name }
        s.governmentWorld = w
    }

    static func currentGovernment(_ w: GovernmentWorld, _ s: GameState, _ context: FinanceContext) -> Government {
        w.government ?? Government(admins: [], startingSupply: max(1, context.homeCurrency(s).scaledPrice(1_000_000_000)))
    }

    static func toHome(_ s: GameState, _ context: FinanceContext, _ amount: Double, from cc: String) -> Double {
        amount * context.currency(cc, s).rate / max(context.homeCurrency(s).rate, 0.000001)
    }

    static func syncRules(_ w: inout GovernmentWorld, _ s: GameState) {
        w.government?.activeRules = s.worldRules
    }

    public static func citizen(_ s: GameState, _ w: GovernmentWorld) -> GovCitizen {
        GovCitizen(account: w.account, name: w.name, ageWeeks: s.week,
                   barredFromVoting: w.justice.barred(w.account, .vote, week: s.week),
                   barredFromOffice: w.justice.barred(w.account, .office, week: s.week))
    }

    @discardableResult
    public static func act<T>(_ s: inout GameState, _ body: (inout Government, String, Int) throws -> T) throws -> T {
        var w = world(s)
        syncRules(&w, s)
        guard var g = w.government else { throw GovError.notFound }
        let r = try body(&g, w.account, s.week)
        w.government = g
        flushNews(&s, &w)
        s.governmentWorld = w
        return r
    }

    static func flushNews(_ s: inout GameState, _ w: inout GovernmentWorld) {
        guard let g = w.government else { return }
        for n in g.news.reversed() where n.id > w.newsSeen { s.news(n.text, tone: n.tone) }
        if let top = g.news.map({ $0.id }).max() { w.newsSeen = max(w.newsSeen, top) }
    }

    public static func donate(_ s: inout GameState, amount: Double) throws {
        var w = world(s)
        guard var g = w.government else { throw GovError.notFound }
        let a = jsRound(amount)
        guard a >= 1 else { throw GovError.badAmount("A donation must be at least 1.") }
        guard s.cash >= a else { throw GovError.cannotAfford("You do not have that much cash.") }
        try g.donate(account: w.account, name: w.name, amount: a, week: s.week)
        Payments.playerPays(&s, a, label: "Donation to the treasury")
        w.government = g
        flushNews(&s, &w)
        s.governmentWorld = w
    }

    public static func candidacyFee(_ s: GameState, context: FinanceContext) -> Double {
        jsRound(context.homeCurrency(s).scaledPrice(Politics.candidacyFeeReference))
    }

    public static func stand(_ s: inout GameState, manifesto: String, promises: [CampaignPromise], context: FinanceContext) throws {
        var w = world(s)
        guard var g = w.government else { throw GovError.notFound }
        let c = citizen(s, w)
        try g.validateStand(c, promises: promises, week: s.week)
        let fee = candidacyFee(s, context: context)
        guard s.cash >= fee else { throw GovError.cannotAfford("Standing costs \(context.homeCurrency(s).display(fee)) and it is not refunded.") }
        Payments.playerPays(&s, fee, label: "Candidacy fee")
        try g.stand(c, manifesto: manifesto, promises: promises, fee: fee, week: s.week)
        w.government = g
        flushNews(&s, &w)
        s.governmentWorld = w
    }

    public static func vote(_ s: inout GameState, for candidate: String) throws {
        var w = world(s)
        guard var g = w.government else { throw GovError.notFound }
        try g.castBallot(citizen(s, w), for: candidate, week: s.week)
        w.government = g
        s.governmentWorld = w
    }

    public static func quash(_ s: inout GameState, convictionID: Int) throws {
        var w = world(s)
        guard var g = w.government else { throw GovError.notFound }
        guard g.isAdmin(w.account) else { throw GovError.notAdmin }
        guard let c = w.justice.convictions.first(where: { $0.id == convictionID && !$0.quashed && $0.account == w.account }) else { throw GovError.notFound }
        if c.fine > 0 { try g.payOut(c.fine, kind: "conviction_refund", ref: String(c.id), week: s.week) }
        _ = w.justice.quash(c.id)
        g.log(w.account, "quash", "conviction \(c.id)", week: s.week)
        if c.fine > 0 { Payments.playerReceives(&s, c.fine, label: "Fine returned: conviction quashed") }
        w.government = g
        s.governmentWorld = w
    }

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

    @discardableResult
    public static func trick(_ s: inout GameState, kind: DirtyTrick, companyID: Int, target: String, token: Int, confirmed: Bool, context: FinanceContext) throws -> TrickOutcome {
        let clean: String = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("rival:"), let id = Int(clean.dropFirst(6)) {
            return try trick(&s, kind: kind, companyID: companyID, rivalID: id, token: token, confirmed: confirmed, context: context)
        }
        return try run(&s, kind: kind, companyID: companyID, targetKey: clean, rivalID: nil, token: token, confirmed: confirmed, context: context)
    }

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
            var g = currentGovernment(w, s, context)
            g.receive(toHome(s, context, paid, from: cc), kind: "conviction_fine", ref: kind.rawValue, week: s.week)
            _ = w.justice.record(account: w.account, name: w.name, kind: kind.convictionKind, summary: "\(kind.title) traced back to you", fine: paid,
                                 country: cc, week: s.week, tradeBanWeeks: DirtyTrick.banWeeks, grave: false)
            w.government = g
            s.addMessage(from: "Authorities", title: "Dirty trick traced", body: "\(kind.title) was traced back to \(s.companies[i].name). Fine \(context.currency(cc, s).display(paid)) and a \(DirtyTrick.banWeeks)-week trading ban.",
                         companyID: companyID, tone: "bad")
        }
        s.governmentWorld = w
        return out
    }

    public static func weekly(_ s: inout GameState, data: GameData, context: FinanceContext) {
        guard var w = s.governmentWorld, s.week > w.lastWeek else { return }
        w.lastWeek = s.week
        syncRules(&w, s)
        let week = s.week
        if var g = w.government {
            let justice = w.justice
            g.advance(week: week, canStand: { !justice.barred($0, .office, week: week) })
            let r = GovInflation.rate(g.supply, week: week)
            if r > 0 { s.economy.inflationIndex *= 1 + r }
            let home = context.homeCurrency(s)
            for i in s.companies.indices where s.companies[i].status == .open {
                let cc = s.companies[i].countryCode
                let rate = context.currency(cc, s).rate / max(home.rate, 0.000001)
                let rev = (s.companies[i].books.week["rev"] ?? 0) * rate
                let amt = g.supportPayout(account: w.account, tradeID: s.companies[i].type, weekRevenue: rev, week: week)
                if amt > 0 { Payments.companyReceives(&s, companyID: s.companies[i].id, amount: amt / max(rate, 0.000001), category: "rev", label: "Price support") }
            }
            w.government = g
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

    static func settle(_ s: inout GameState, _ w: inout GovernmentWorld, audit a: RouteAudit, companyIndex i: Int, data: GameData, context: FinanceContext) {
        let id = s.companies[i].id, name = s.companies[i].name, cc = s.companies[i].countryCode, week = s.week
        let cur = context.currency(cc, s)
        var g = currentGovernment(w, s, context)
        let owed = jsRound(a.liability * (RouteRules.backMultiple + RouteRules.fineMultiple(level: a.level)))
        let cash0 = s.companies[i].cash
        _ = Payments.companyPays(&s, companyID: id, amount: owed, category: "fine", label: "Audit: illegal takings")
        let paid = max(0, cash0 - s.companies[i].cash)
        var body = "An audit of \(name) found \(a.route.title.lowercased()). It must hand back and pay \(cur.display(paid))."
        if a.suspends, s.companies[i].status == .open {
            s.companies[i].status = .closed
            s.companies[i].set("closeW", RouteRules.suspensionWeeks); s.companies[i].set("closeTot", RouteRules.suspensionWeeks); s.companies[i].set("idle", 0)
            body += " It is shut for \(RouteRules.suspensionWeeks) weeks."
        }
        if a.closes {
            // The company has no cash of its own: the account also carries the owner's other companies, so only the company and its things are taken.
            let own = s.companies[i].ownership
            s.companies[i].ownership = 0
            Failure.bankrupt(&s, companyIndex: i, reason: "closed", data: data, context: context, announce: false)
            s.companies[i].ownership = own
            s.credit = clamp(s.credit - RouteRules.closureCreditLoss, 0, 100)
            // A closure is a bankruptcy for the banks too: its lenders' losses are clawed back and no new loans for two years.
            Banking.recordBankruptcy(&s)
            s.stats.bankruptcies += 1
            let claw = s.companies[i].num("clawBk")
            let pf = jsRound(a.liability * RouteRules.convictionFineMultiple(level: a.level))
            if pf >= 1 { Payments.playerPays(&s, pf, label: "Fine: conviction") }
            let grave = a.grave
            let conv = w.justice.record(account: w.account, name: w.name, kind: a.route.convictionKind, summary: "\(a.route.title) at \(name)", fine: pf, country: cc, week: week,
                                        tradeBanWeeks: RouteRules.tradeBanWeeks(grave: grave), officeBanWeeks: RouteRules.officeBanWeeks(grave: grave), voteBanWeeks: RouteRules.voteBanWeeks(grave: grave), grave: grave)
            g.receive(pf, kind: "conviction_fine", ref: String(conv.id), week: week)
            g.removeFromOffice(account: w.account, reason: "convicted", week: week)
            if grave { g.publish("\(w.name) is on the watchlist: \(conv.summary).", tone: "bad", week: week) }
            s.news("\(name) was shut down by the authorities.", tone: "bad", companyID: id)
            body += " The company is closed and everything it owns seized, with nothing paid out to you. You are convicted and banned from trading and from office."
            if claw >= 1 { body += " \(cur.display(claw)) of borrowed money it brought into your account is taken back for its lenders." }
            body += " " + Failure.banText
            w.routes.drop(companyID: id)
        }
        g.receive(toHome(s, context, paid, from: cc), kind: "audit_fine", ref: String(id), week: week)
        g.log("system", "audit", "\(name): level \(a.level)", week: week)
        w.government = g
        s.addMessage(from: "Authorities", title: "Audit at \(name)", body: body, companyID: id, tone: "bad")
        s.note("Audit at \(name): \(cur.display(paid)) paid.", tone: "bad", companyID: id)
    }
}
