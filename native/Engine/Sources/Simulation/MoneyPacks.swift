import Foundation
import GameCore
import Countries
import Finance

/// Game money sold for gold. The amount follows the one gold rate (GoldValue); bigger packs add a bonus.
public struct MoneyPack: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var gold: Int
    public var bonusPercent: Int
    /// The free pack is paid by watching an ad and costs no gold.
    public var isFree: Bool = false
}

public enum MoneyPacks {
    public static let label = "Money bought with gold"
    public static let freeLabel = "Free money pack"
    static let rememberLimit = 200

    public static let packs: [MoneyPack] = GoldPrices.table["gold"]["moneyPacks"].array.map { (e: JSONValue) -> MoneyPack in
        MoneyPack(id: e["id"].string, name: e["name"].string, gold: e["gold"].int, bonusPercent: e["bonusPercent"].int)
    }

    private static let freeEntry: JSONValue = GoldPrices.table["gold"]["freeMoneyPack"]

    /// One small pack for watching an ad. Its gold is the worth of the money, not a price.
    public static let free: MoneyPack = MoneyPack(id: freeEntry["id"].string, name: freeEntry["name"].string, gold: freeEntry["gold"].int, bonusPercent: 0, isFree: true)

    /// How many free packs a day the ad cap allows.
    public static var freePerDay: Int { freeEntry["perDay"].int }

    /// Gold one account may spend on money packs in any 7 days; the server enforces it.
    public static var weeklyGoldCap: Int { GoldPrices.table["gold"]["moneyPackWeeklyGold"].int }

    /// Gold still allowed on money packs this week, given what the server says was used.
    public static func weeklyRoom(used: Int) -> Int { max(0, weeklyGoldCap - max(0, used)) }

    /// Whether this pack fits in the weekly allowance.
    public static func fitsThisWeek(_ pack: MoneyPack, used: Int) -> Bool { pack.isFree || price(pack) <= weeklyRoom(used: used) }

    public static func pack(_ id: String) -> MoneyPack? {
        id == free.id ? free : packs.first { (p: MoneyPack) -> Bool in p.id == id }
    }

    /// Gold taken from the wallet: nothing for the free pack.
    public static func price(_ pack: MoneyPack) -> Int { pack.isFree ? 0 : pack.gold }

    /// Game money (reference NOK, what the books hold) the pack pays.
    public static func gameMoney(_ pack: MoneyPack) -> Double {
        jsRound(GoldValue.gameMoney(gold: Double(pack.gold)) * Double(100 + pack.bonusPercent) / 100)
    }

    /// The same money in a country's own currency, by the game's exchange rate.
    public static func local(_ pack: MoneyPack, currency: Currency) -> Double { gameMoney(pack) / currency.rate }

    /// Pays the pack into the player's account through the ledger. Each claim id pays once.
    @discardableResult
    public static func claim(_ s: inout GameState, pack: MoneyPack, claimID: String) -> Double? {
        guard !claimID.isEmpty else { return nil }
        var seen: [JSONValue] = (s.rest["mpk"] ?? .null).array
        if seen.contains(where: { $0.string == claimID }) { return nil }
        let cash: Double = gameMoney(pack)
        guard cash > 0 else { return nil }
        seen.append(.string(claimID))
        if seen.count > rememberLimit { seen.removeFirst(seen.count - rememberLimit) }
        s.rest["mpk"] = .array(seen)
        Ledger.move(&s, .me, cash, why: pack.isFree ? freeLabel : label)
        return cash
    }
}

public extension GameEngine {
    /// Game money paid, or nil when the pack is unknown or this claim id was already paid.
    @discardableResult
    mutating func claimMoneyPack(_ packID: String, claimID: String) -> Double? {
        guard let pack = MoneyPacks.pack(packID) else { return nil }
        var paid: Double?
        update { s, _, _ in paid = MoneyPacks.claim(&s, pack: pack, claimID: claimID) }
        return paid
    }
}
