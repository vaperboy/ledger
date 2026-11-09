import Foundation
import GameCore

// Illegal routes: extra takings for a company that break the law. Starting one takes a warning and a separate confirmation. Each route builds
// a hidden "heat" per company that no screen shows; the heat sets how likely an audit is each week. An audit settles everything taken in the
// last 26 weeks and its outcome grows with how grave the route is and how hot the company is, up to forced closure and a conviction.
// Nothing here moves money: `RouteBook.step` returns what the company earned and what an audit decided, and `GovernmentBridge` books it.

public enum IllegalRoute: String, Codable, CaseIterable, Sendable {
    case cashInHand, fakeInvoices, cheapInputs, grayImports, bribedInspector, counterfeitLabels

    public var title: String {
        switch self {
        case .cashInHand: return "Cash in hand"
        case .fakeInvoices: return "False invoices"
        case .cheapInputs: return "Unsafe cheap inputs"
        case .grayImports: return "Smuggled stock"
        case .bribedInspector: return "Bribed inspector"
        case .counterfeitLabels: return "Fake brand labels"
        }
    }
    /// 1 minor, 2 serious, 3 grave.
    public var severity: Int {
        switch self {
        case .cashInHand: return 1
        case .fakeInvoices, .cheapInputs, .grayImports: return 2
        case .bribedInspector, .counterfeitLabels: return 3
        }
    }
    /// Extra takings each week, as a share of the company's week of sales.
    public var gainRate: Double {
        switch self {
        case .cashInHand: return 0.06
        case .fakeInvoices: return 0.08
        case .cheapInputs: return 0.10
        case .grayImports: return 0.12
        case .bribedInspector: return 0.12
        case .counterfeitLabels: return 0.18
        }
    }
    var heatPerWeek: Double {
        switch self {
        case .cashInHand: return 4
        case .fakeInvoices: return 5
        case .cheapInputs: return 6
        case .grayImports: return 7
        case .bribedInspector: return 9
        case .counterfeitLabels: return 10
        }
    }
    var convictionKind: PlayerConviction.Kind {
        switch self {
        case .cashInHand: return .taxEvasion
        case .fakeInvoices: return .fraud
        case .cheapInputs: return .unsafeGoods
        case .grayImports: return .smuggling
        case .bribedInspector: return .bribery
        case .counterfeitLabels: return .counterfeiting
        }
    }
}

public enum RouteRules {
    public static let maxRoutesPerCompany = 2
    public static let lookbackWeeks = 26
    public static let setupHeat = 15.0
    public static let restCooling = 1.0
    public static let heatAfterAudit = 40.0
    public static let warningValidWeeks = 1
    public static let suspensionWeeks = 6

    /// Weekly chance of an audit at this heat.
    public static func auditChance(heat: Double) -> Double { min(0.6, 0.02 + 0.5 * pow(clamp(heat, 0, 100) / 100, 2)) }

    /// What an audit of level 1 to 5 costs, as multiples of what was taken in the look-back: the gains handed back plus a fine.
    public static func fineMultiple(level: Int) -> Double { level <= 1 ? 1 : 3 }
    public static let backMultiple = 1.0

    /// The bans a conviction after a forced closure carries, in weeks; `grave` is the public-watchlist level.
    public static func tradeBanWeeks(grave: Bool) -> Int { grave ? 26 : 12 }
    public static func officeBanWeeks(grave: Bool) -> Int { grave ? 52 : 26 }
    public static func voteBanWeeks(grave: Bool) -> Int { grave ? 26 : 0 }
    /// Credit points lost when a company is closed by the authorities.
    public static let closureCreditLoss = 15.0
    /// Audit level at which a company is closed and its owner convicted, and the level at which the name goes on the public watchlist.
    public static let closureLevel = 4
    public static let watchlistLevel = 5
    /// The owner's own fine at the levels with a conviction.
    public static func convictionFineMultiple(level: Int) -> Double { level >= 5 ? 1 : (level == 4 ? 0.5 : 0) }
}

public struct RouteGain: Codable, Equatable, Sendable {
    public var route: IllegalRoute
    public var week: Int
    public var amount: Double
}

/// What the state keeps on one company. `heat` is deliberately internal: no public read.
public struct CompanyRisk: Codable, Equatable, Sendable {
    public var companyID: Int
    var heat: Double = 0
    public var active: [IllegalRoute] = []
    var gains: [RouteGain] = []
    public var offences = 0
}

public struct RouteWarning: Equatable, Sendable {
    public var act: String
    public var companyID: Int
    public var token: Int
    public var text: String
}

struct IssuedWarning: Codable, Equatable, Sendable {
    var act: String
    var companyID: Int
    var token: Int
    var week: Int
}

public struct RouteAudit: Equatable, Sendable {
    /// 1 warning and settlement, 2 fine, 3 fine and a suspension, 4 forced closure and conviction, 5 the same with a public listing.
    public var level: Int
    public var liability: Double
    public var route: IllegalRoute
    public var closes: Bool { level >= 4 }
    public var suspends: Bool { level == 3 }
    public var grave: Bool { level >= 5 }
}

public struct RouteWeek: Equatable, Sendable {
    public var gain: Double
    public var audit: RouteAudit?
}

public struct TrickUse: Codable, Equatable, Sendable {
    public var account: String
    public var target: String
    public var kind: DirtyTrick
    public var week: Int
    public var hit: Double
}

public enum DirtyTrick: String, Codable, CaseIterable, Sendable {
    case smear, fakeReviews, sabotage

    public var title: String {
        switch self { case .smear: return "Smear campaign"; case .fakeReviews: return "Fake bad reviews"; case .sabotage: return "Sabotage a delivery" }
    }
    /// Reputation points the target loses at most.
    public var hit: Double { switch self { case .smear: return 3; case .fakeReviews: return 4; case .sabotage: return 5 } }
    /// Reference price, scaled to the country by the caller.
    public var costReference: Double { switch self { case .smear: return 20_000; case .fakeReviews: return 30_000; case .sabotage: return 60_000 } }
    var heat: Double { 8 }
    var detectChance: Double { Self.traceChance }
    var convictionKind: PlayerConviction.Kind { self == .sabotage ? .sabotage : .harassment }

    /// Chance that a trick is traced back to the one who ordered it.
    public static let traceChance = 0.25
    /// When traced: the company pays this many times what the trick cost as a fine, and the owner is barred from trading for this many weeks.
    public static let fineMultiple = 5.0
    public static let banWeeks = 4

    /// What being traced costs, in plain words (the app's "If you do this" lines read this).
    public static var penaltyText: String {
        "\(Int((traceChance * 100).rounded()))% of tricks are traced back. Then the company pays a fine of \(Int(fineMultiple)) times what the trick cost, "
            + "you are barred from trading for \(banWeeks) weeks and a conviction goes on your record."
    }

    public static let perAccountPerWeek = 1
    public static let perAccountPerWindow = 4
    public static let windowWeeks = 12
    /// Total reputation any one target can lose to tricks in a window.
    public static let targetCap = 12.0
}

public struct TrickOutcome: Equatable, Sendable {
    public var effect: Double
    public var detected: Bool
}

public struct RouteBook: Codable, Equatable, Sendable {
    public private(set) var risks: [CompanyRisk] = []
    var issued: [IssuedWarning] = []
    public private(set) var tricks: [TrickUse] = []
    var nextToken = 1

    public init() {}

    public func risk(_ companyID: Int) -> CompanyRisk? { risks.first { $0.companyID == companyID } }
    public func active(_ companyID: Int) -> [IllegalRoute] { risk(companyID)?.active ?? [] }

    // MARK: Warning and confirmation

    /// The plain warning. It never says how close the company is to being found out.
    public mutating func warn(act: String, title: String, companyID: Int, week: Int) -> RouteWarning {
        issued.removeAll { $0.act == act && $0.companyID == companyID }
        let t = nextToken
        nextToken += 1
        issued.append(IssuedWarning(act: act, companyID: companyID, token: t, week: week))
        let text = "\(title) is a crime. If it comes out you can lose everything it earned and pay a heavy fine, lose the company without being paid out, "
            + "get a criminal record and be named in public. You cannot see how close you are to being found out, and it never resets."
        return RouteWarning(act: act, companyID: companyID, token: t, text: text)
    }

    /// Accepts the confirmation of a warning given within the last week. A warning can be used once.
    mutating func consume(act: String, companyID: Int, token: Int, confirmed: Bool, week: Int) throws {
        guard confirmed, let i = issued.firstIndex(where: { $0.act == act && $0.companyID == companyID && $0.token == token }),
              week - issued[i].week <= RouteRules.warningValidWeeks else { throw GovError.needsConfirmation }
        issued.remove(at: i)
    }

    // MARK: Routes

    /// Starts a route after the warning was shown and confirmed. Starting adds some heat at once, so short bursts are not free.
    public mutating func begin(_ route: IllegalRoute, companyID: Int, token: Int, confirmed: Bool, week: Int) throws {
        try consume(act: "route:\(route.rawValue)", companyID: companyID, token: token, confirmed: confirmed, week: week)
        var r = risk(companyID) ?? CompanyRisk(companyID: companyID)
        guard !r.active.contains(route) else { throw GovError.wrongState }
        guard r.active.count < RouteRules.maxRoutesPerCompany else { throw GovError.overLimit("At most two illegal routes at a company.") }
        r.active.append(route)
        r.heat = min(100, r.heat + RouteRules.setupHeat)
        store(r)
    }

    /// Stops a route. What it earned stays on the record for the look-back, and the heat only cools slowly.
    public mutating func stop(_ route: IllegalRoute, companyID: Int) {
        guard var r = risk(companyID) else { return }
        r.active.removeAll { $0 == route }
        store(r)
    }

    private mutating func store(_ r: CompanyRisk) {
        if let i = risks.firstIndex(where: { $0.companyID == r.companyID }) { risks[i] = r } else { risks.append(r) }
    }

    /// One week for one company. `base` is its week of sales; `open` is false while it is shut (nothing is earned and heat holds).
    public mutating func step(companyID: Int, week: Int, base: Double, open: Bool) -> RouteWeek {
        guard var r = risk(companyID) else { return RouteWeek(gain: 0, audit: nil) }
        var gain = 0.0
        if open, base > 0, !r.active.isEmpty {
            for route in r.active {
                let g = jsRound(base * route.gainRate)
                gain += g
                r.heat += route.heatPerWeek
                r.gains.append(RouteGain(route: route, week: week, amount: g))
            }
        } else if r.active.isEmpty {
            r.heat = max(0, r.heat - RouteRules.restCooling)
        }
        r.heat = min(100, r.heat)
        r.gains.removeAll { week - $0.week >= RouteRules.lookbackWeeks }
        let liability = r.gains.reduce(0) { $0 + $1.amount }
        var audit: RouteAudit?
        if liability > 0, HashedRandom.first("route:\(week):\(companyID)") < RouteRules.auditChance(heat: r.heat) {
            let worst = (r.gains.map { $0.route } + r.active).max { $0.severity < $1.severity } ?? .cashInHand
            var level = worst.severity + (r.offences > 0 ? 1 : 0) + (r.heat >= 80 ? 1 : 0)
            let r2 = HashedRandom.first("routeout:\(week):\(companyID)")
            level += r2 < 0.2 ? -1 : (r2 > 0.85 ? 1 : 0)
            level = max(1, min(5, level))
            audit = RouteAudit(level: level, liability: liability, route: worst)
            r.gains = []
            r.offences += 1
            r.heat = RouteRules.heatAfterAudit
            if level >= 3 { r.active = [] }
        }
        store(r)
        return RouteWeek(gain: gain, audit: audit)
    }

    // MARK: Dirty tricks

    /// A capped dirty trick against another company or player. Returns the reputation the target loses (never above the cap) and whether it
    /// was traced back. The warning and confirmation work as for a route. Heat of the acting company rises.
    public mutating func useTrick(_ kind: DirtyTrick, account: String, companyID: Int, target: String, token: Int, confirmed: Bool, week: Int) throws -> TrickOutcome {
        let mine = tricks.filter { $0.account == account && week - $0.week < DirtyTrick.windowWeeks }
        guard !mine.contains(where: { $0.week == week }) else { throw GovError.overLimit("One dirty trick a week.") }
        guard mine.count < DirtyTrick.perAccountPerWindow else { throw GovError.overLimit("No more than four dirty tricks in twelve weeks.") }
        let already = tricks.filter { $0.target == target && week - $0.week < DirtyTrick.windowWeeks }.reduce(0) { $0 + $1.hit }
        let effect = min(kind.hit, DirtyTrick.targetCap - already)
        guard effect > 0 else { throw GovError.overLimit("That target has been hurt enough already.") }
        try consume(act: "trick:\(kind.rawValue)", companyID: companyID, token: token, confirmed: confirmed, week: week)
        tricks.append(TrickUse(account: account, target: target, kind: kind, week: week, hit: effect))
        var r = risk(companyID) ?? CompanyRisk(companyID: companyID)
        r.heat = min(100, r.heat + kind.heat)
        store(r)
        let detected = HashedRandom.first("trick:\(week):\(account):\(tricks.count)") < kind.detectChance
        return TrickOutcome(effect: effect, detected: detected)
    }

    /// Forget a company that no longer exists.
    public mutating func drop(companyID: Int) { risks.removeAll { $0.companyID == companyID } }
}
