import Foundation
import GameCore

public enum GovError: Error, Equatable, Sendable {
    case notAdmin, notPresident, notFound, notOpen, wrongState
    case notEligible(String), alreadyVoted, alreadyStanding
    case badAmount(String), overLimit(String), tooSoon(weeksLeft: Int), treasuryShort
    case unrealistic(String), needsConfirmation, alreadyPending, cannotAfford(String)
}

extension GovError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notAdmin: return "Only an administrator can do that."
        case .notPresident: return "Only the sitting president can do that."
        case .notFound: return "That does not exist."
        case .notOpen: return "That is not open right now."
        case .wrongState: return "That cannot be done in the current state."
        case .notEligible(let why): return why
        case .alreadyVoted: return "You have already voted in this election."
        case .alreadyStanding: return "You are already a candidate."
        case .badAmount(let why): return why
        case .overLimit(let why): return why
        case .tooSoon(let w): return "Too soon: wait \(w) more week\(w == 1 ? "" : "s")."
        case .treasuryShort: return "The treasury does not hold enough."
        case .unrealistic(let why): return why
        case .needsConfirmation: return "Read the warning and confirm first."
        case .alreadyPending: return "A change of that kind is already waiting for an administrator."
        case .cannotAfford(let why): return why
        }
    }
}

func govRound(_ x: Double) -> Double { (x * 100).rounded() / 100 }

public struct GovTreasuryEntry: Codable, Equatable, Sendable {
    public var id: Int
    public var week: Int
    public var amount: Double
    public var kind: String
    public var ref: String
}

public struct GovTreasury: Codable, Equatable, Sendable {
    public static let spendKinds: Set<String> = ["price_support", "conviction_refund"]
    public static let entryLimit = 400

    public private(set) var balance: Double = 0
    public private(set) var flow: Double = 0
    public private(set) var entries: [GovTreasuryEntry] = []
    private var nextEntry = 1

    public init() {}

    public mutating func post(_ amount: Double, kind: String, ref: String = "", week: Int) throws {
        let a = govRound(amount)
        guard a != 0 else { return }
        if a < 0 {
            guard Self.spendKinds.contains(kind) else { throw GovError.wrongState }
            guard balance + a >= 0 else { throw GovError.treasuryShort }
        }
        balance = govRound(balance + a)
        flow = govRound(flow + a)
        entries.insert(GovTreasuryEntry(id: nextEntry, week: week, amount: a, kind: kind, ref: ref), at: 0)
        nextEntry += 1
        if entries.count > Self.entryLimit { entries.removeLast(entries.count - Self.entryLimit) }
    }

    public var gap: Double { abs(balance - flow) < 0.011 ? 0 : balance - flow }
}

public struct GovMint: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var week: Int
    public var amount: Double
    public var reason: String
    public var admin: String
}

public struct GovMoneySupply: Codable, Equatable, Sendable {
    public var base: Double
    public private(set) var mints: [GovMint] = []
    public static let singleMintLimit = 0.05
    public static let windowWeeks = 12
    public static let windowLimit = 0.15

    public init(base: Double) { self.base = max(1, base) }

    public var total: Double { base + mints.reduce(0) { $0 + $1.amount } }
    public func total(before week: Int) -> Double { base + mints.filter { $0.week < week }.reduce(0) { $0 + $1.amount } }

    func check(_ amount: Double, week: Int, rules: WorldRules = WorldRules.defaults) throws {
        guard amount > 0, amount.isFinite else { throw GovError.badAmount("An amount above zero is needed.") }
        let t = total
        let single = Int((rules.printSingleLimit * 100).rounded()), window = Int((rules.printWindowLimit * 100).rounded())
        if amount > t * rules.printSingleLimit { throw GovError.overLimit("One addition of new money may not exceed \(single)% of the money supply.") }
        let recent = mints.filter { week - $0.week < rules.printWindowWeeks }.reduce(0) { $0 + $1.amount }
        if recent + amount > t * rules.printWindowLimit { throw GovError.overLimit("No more than \(window)% of the money supply may be added in \(rules.printWindowWeeks) weeks.") }
    }

    mutating func append(_ m: GovMint) { mints.append(m) }
}

public enum GovInflation {
    public static let lagWeeks = 6
    public static let spread = 4
    public static let sensitivity = 0.6
    public static let weeklyCap = 0.02

    public static func rate(_ supply: GovMoneySupply, week: Int) -> Double {
        var r = 0.0
        for j in 0..<spread {
            let src = week - lagWeeks - j
            guard src >= 0 else { continue }
            let minted = supply.mints.filter { $0.week == src }.reduce(0) { $0 + $1.amount }
            guard minted > 0 else { continue }
            r += sensitivity * minted / supply.total(before: src) / Double(spread)
        }
        return min(weeklyCap, r)
    }

    public static func index(_ supply: GovMoneySupply, atWeek week: Int) -> Double {
        guard week > 0, !supply.mints.isEmpty else { return 1 }
        var ix = 1.0
        for w in 1...week { ix *= 1 + rate(supply, week: w) }
        return ix
    }
}

public struct GovDonation: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var week: Int
    public var account: String
    public var name: String
    public var amount: Double
}

public struct GovAuditEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var week: Int
    public var actor: String
    public var action: String
    public var detail: String
}

public struct GovNews: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var week: Int
    public var text: String
    public var tone: String
}
