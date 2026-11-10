import Foundation
import GameCore
import Finance

public struct AssociationStanding: Equatable, Sendable {
    public var reputation: Double
    public var weeksNegative: Int
    public var wageShortfall: Double
    public var taxDue: Bool
    public init(reputation: Double, weeksNegative: Int, wageShortfall: Double, taxDue: Bool) {
        self.reputation = reputation; self.weeksNegative = weeksNegative; self.wageShortfall = wageShortfall; self.taxDue = taxDue
    }
    public init(_ co: Company) {
        self.init(reputation: co.reputation, weeksNegative: co.weeksNegative, wageShortfall: co.wageShortfall, taxDue: co.taxDue)
    }
}

public enum AssociationStandard: String, Codable, CaseIterable, Sendable {
    case goodName, staffPaid, outOfTheRed, taxCurrent

    public var rule: String {
        switch self {
        case .goodName: return "Keep your reputation at \(Int(AssociationStandards.minReputation)) or above."
        case .staffPaid: return "Pay staff in full and on time."
        case .outOfTheRed: return "Do not let the account stay overdrawn for more than \(AssociationStandards.maxRedWeeks) weeks running."
        case .taxCurrent: return "Pay tax when it falls due."
        }
    }

    public func isMet(_ x: AssociationStanding) -> Bool {
        switch self {
        case .goodName: return x.reputation >= AssociationStandards.minReputation
        case .staffPaid: return x.wageShortfall <= 0
        case .outOfTheRed: return x.weeksNegative <= AssociationStandards.maxRedWeeks
        case .taxCurrent: return !x.taxDue
        }
    }
}

public enum AssociationStandards {
    public static let minReputation = 45.0
    public static let maxRedWeeks = 3

    public static func breaches(_ club: AssociationClub, _ x: AssociationStanding) -> [AssociationStandard] {
        club.standards.filter { !$0.isMet(x) }
    }
}

public struct AssociationClub: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var tradeName: String?
    public var region: String?
    public var monthlyFee: Double
    public var discountCap: Double
    public var standards: [AssociationStandard]
}

public enum AssociationCatalogue {
    public static let tradeFee = 40.0, tradeCap = 0.06

    static func slug(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }) }

    public static func tradeClub(tradeName: String, region: String) -> AssociationClub {
        AssociationClub(id: "tr.\(slug(tradeName)).\(region.lowercased())", name: "\(region) \(tradeName) Association", tradeName: tradeName, region: region,
                        monthlyFee: tradeFee, discountCap: tradeCap, standards: [.goodName, .staffPaid, .outOfTheRed, .taxCurrent])
    }

    public static let crossTrade: [AssociationClub] = [
        AssociationClub(id: "x.circle", name: "Independent Business Circle", tradeName: nil, region: nil, monthlyFee: 25, discountCap: 0.03, standards: [.staffPaid, .taxCurrent]),
        AssociationClub(id: "x.employers", name: "Good Employers Alliance", tradeName: nil, region: nil, monthlyFee: 30, discountCap: 0.04, standards: [.goodName, .staffPaid]),
        AssociationClub(id: "x.steady", name: "Steady Traders Club", tradeName: nil, region: nil, monthlyFee: 28, discountCap: 0.03, standards: [.outOfTheRed, .taxCurrent]),
    ]

    public static func clubs(tradeName: String, region: String) -> [AssociationClub] { [tradeClub(tradeName: tradeName, region: region)] + crossTrade }

    public static func club(id: String, tradeName: String, region: String) -> AssociationClub? { clubs(tradeName: tradeName, region: region).first { $0.id == id } }
}

public enum GroupPurchasing {
    public static let baseRate = 0.01, perMember = 0.001
    public static let hardCap = 0.08

    public static func rate(members: Int, cap: Double) -> Double {
        guard members > 0 else { return 0 }
        return min(cap, hardCap, baseRate + perMember * Double(members))
    }

    public static func saving(spend: Double, rate: Double) -> Double {
        guard spend > 0, rate > 0 else { return 0 }
        return (spend * min(rate, hardCap) * 100).rounded() / 100
    }

    public static func words(members: Int, rate: Double, cap: Double) -> String {
        let pct = (rate * 1000).rounded() / 10
        let p = pct == pct.rounded() ? String(Int(pct)) : String(pct)
        if members <= 0 { return "No pooled volume yet, so no discount." }
        let reach = rate >= min(cap, hardCap) ? "the most this club can give" : "grows as more members join"
        return "\(members) members buy together, so suppliers give \(p) percent off catalogue supply lines. That is \(reach)."
    }
}

public struct AssociationMembership: Codable, Equatable, Sendable {
    public var club: AssociationClub
    public var joinedWeek: Int
    public var strikes: Int
    public var members: Int
    public var saved: Double
    public var feesPaid: Double
    public var checkedWeek: Int
}

public enum AssociationEnforcement {
    public enum Action: Equatable, Sendable { case clear, warn, fine, remove }

    public static func next(strikes: Int, breaches: [AssociationStandard]) -> (strikes: Int, action: Action) {
        if breaches.isEmpty { return (0, .clear) }
        switch strikes {
        case 0: return (1, .warn)
        case 1: return (2, .fine)
        default: return (3, .remove)
        }
    }

    public static func fine(_ club: AssociationClub) -> Double { club.monthlyFee }

    public static let banWeeks = 13
    public static let cycleWeeks = 4
    public static func isDue(joined: Int, week: Int) -> Bool { week > joined && (week - joined) % cycleWeeks == 0 }
}

public enum JoinResult: Equatable, Sendable {
    case joined
    case refused(String)
}

public enum TradeAssociations {

    public static func membership(_ s: GameState, companyID: Int) -> AssociationMembership? {
        let v = s.rest["assoc"]?["m"]["\(companyID)"] ?? .null
        guard !v.isNull, let d = try? JSONEncoder().encode(v) else { return nil }
        return try? JSONDecoder().decode(AssociationMembership.self, from: d)
    }

    static func store(_ s: inout GameState, companyID: Int, _ m: AssociationMembership?) {
        var root = s.rest["assoc"] ?? .object([:])
        var table = root["m"].object
        if let m, let d = try? JSONEncoder().encode(m), let v = try? JSONDecoder().decode(JSONValue.self, from: d) { table["\(companyID)"] = v } else { table["\(companyID)"] = nil }
        root["m"] = .object(table)
        s.rest["assoc"] = root
    }

    static func bannedUntil(_ s: GameState, companyID: Int, clubID: String) -> Int? {
        let v = s.rest["assoc"]?["ban"]["\(companyID):\(clubID)"] ?? .null
        return v.isNull ? nil : Int(v.double)
    }

    static func ban(_ s: inout GameState, companyID: Int, clubID: String, until: Int) {
        var root = s.rest["assoc"] ?? .object([:])
        var bans = root["ban"].object
        bans["\(companyID):\(clubID)"] = .number(Double(until))
        root["ban"] = .object(bans)
        s.rest["assoc"] = root
    }

    public static func joinPreview(_ club: AssociationClub, members: Int, standing: AssociationStanding) -> [String] {
        let rate = GroupPurchasing.rate(members: members, cap: club.discountCap)
        var lines = ["The first monthly fee is taken now, then every fourth week: \(Int(club.monthlyFee)) a month.",
                     GroupPurchasing.words(members: members, rate: rate, cap: club.discountCap),
                     "Each month the club checks your company against its standards. A miss brings a warning, then a fine of one more month's fee, then removal."]
        let failing = AssociationStandards.breaches(club, standing)
        if !failing.isEmpty { lines.append("You do not meet these today: " + failing.map { $0.rule }.joined(separator: " ")) }
        return lines
    }

    public static func leavePreview(_ m: AssociationMembership) -> [String] {
        ["The discount on supply lines stops at once.",
         "Fees already paid are not refunded.",
         "You can join again later."]
    }

    @discardableResult
    public static func join(_ s: inout GameState, companyID: Int, club: AssociationClub, members: Int, tradeName: String) -> JoinResult {
        guard let co = s.company(companyID), co.status == .open else { return .refused("The company is not open.") }
        if membership(s, companyID: companyID) != nil { return .refused("This company already belongs to a club. Leave it first.") }
        if let t = club.tradeName, AssociationCatalogue.slug(t) != AssociationCatalogue.slug(tradeName) { return .refused("This club is for \(t).") }
        if let r = club.region, r != co.countryCode { return .refused("This club is for members in \(r).") }
        if let until = bannedUntil(s, companyID: companyID, clubID: club.id), s.week < until { return .refused("The club removed this company recently. It can apply again in \(until - s.week) weeks.") }
        _ = Payments.companyPays(&s, companyID: companyID, amount: club.monthlyFee, category: "oth", label: "Association fee: \(club.name)")
        store(&s, companyID: companyID, AssociationMembership(club: club, joinedWeek: s.week, strikes: 0, members: members, saved: 0, feesPaid: club.monthlyFee, checkedWeek: s.week))
        return .joined
    }

    public static func leave(_ s: inout GameState, companyID: Int) { store(&s, companyID: companyID, nil) }

    public static func setMembers(_ s: inout GameState, companyID: Int, members: Int) {
        let count = max(1, members)
        guard var m = membership(s, companyID: companyID), m.members != count else { return }
        m.members = count
        store(&s, companyID: companyID, m)
    }

    public static func weekly(_ s: inout GameState, data: GameData) {
        guard let table = s.rest["assoc"]?["m"].object, !table.isEmpty else { return }
        for key in table.keys.sorted() {
            guard let id = Int(key), var m = membership(s, companyID: id) else { continue }
            guard let co = s.company(id), co.status.isLive else {
                store(&s, companyID: id, nil)
                continue
            }
            guard co.status == .open else { continue }
            if let bd = data.catalog[co.type] {
                let spend = SupplyCatalogue.lines(co, bd).reduce(0.0) { $0 + (SupplyCatalogue.weeklySpend(co, line: $1.id)?.now ?? 0) }
                let saving = GroupPurchasing.saving(spend: spend, rate: GroupPurchasing.rate(members: m.members, cap: m.club.discountCap))
                if saving > 0 {
                    SupplyMarketBooks.bookPurchaseDifference(&s, buyerCompanyID: id, saving: saving)
                    m.saved += saving
                }
            }
            if AssociationEnforcement.isDue(joined: m.joinedWeek, week: s.week) {
                _ = Payments.companyPays(&s, companyID: id, amount: m.club.monthlyFee, category: "oth", label: "Association fee: \(m.club.name)")
                m.feesPaid += m.club.monthlyFee
                let result = AssociationEnforcement.next(strikes: m.strikes, breaches: AssociationStandards.breaches(m.club, AssociationStanding(co)))
                m.strikes = result.strikes
                m.checkedWeek = s.week
                switch result.action {
                case .clear: break
                case .warn:
                    s.addMessage(from: m.club.name, title: "Warning from \(m.club.name)", body: "\(co.name) does not meet the club's standards. Put it right before the next check or a fine follows.", companyID: id, tone: "bad")
                case .fine:
                    let fine = AssociationEnforcement.fine(m.club)
                    _ = Payments.companyPays(&s, companyID: id, amount: fine, category: "oth", label: "Association fine: \(m.club.name)")
                    m.feesPaid += fine
                    s.addMessage(from: m.club.name, title: "Fine from \(m.club.name)", body: "\(co.name) still misses the club's standards. One more month's fee was charged. Another miss means removal.", companyID: id, tone: "bad")
                case .remove:
                    store(&s, companyID: id, nil)
                    ban(&s, companyID: id, clubID: m.club.id, until: s.week + AssociationEnforcement.banWeeks)
                    s.addMessage(from: m.club.name, title: "Removed from \(m.club.name)", body: "\(co.name) was removed for repeatedly missing the standards. The discount has ended, and it cannot rejoin for \(AssociationEnforcement.banWeeks) weeks.", companyID: id, tone: "bad")
                    continue
                }
            }
            store(&s, companyID: id, m)
        }
    }
}
