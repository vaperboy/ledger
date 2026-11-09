import Foundation
import GameCore
import Countries
import Finance

public struct WealthLine: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    /// What it adds to (or takes from) the total, after any discount.
    public var amount: Double
    /// In words: what it is and how it was counted.
    public var words: String
}

/// Net worth as the rankings read it, with every part named. Public holdings count at the last close; private companies count at a
/// discount because they cannot be sold in a day.
public struct WealthStatement: Equatable, Sendable {
    public var lines: [WealthLine]
    public var total: Double
    /// What the discounts took off the paper value of companies.
    public var discount: Double
    /// Share (0...1) of the assets that is money or shares you could sell this week.
    public var liquidShare: Double
    public var summary: String
    /// The plain net worth the rest of the game uses (before discounts), for comparison.
    public var plain: NetWorth
}

public enum Wealth {
    /// A private company you run is counted at this much less than its value.
    public static let privateDiscount = 0.25
    /// A stake in someone else's private company, and a startup stake, is counted at this much less.
    public static let minorityDiscount = 0.35
    /// Your block of shares in your own listed company is counted at this much less than the close: a whole block cannot sell at once.
    public static let blockDiscount = 0.10

    public static func statement(_ s: GameState, trades: any TradeCatalogProviding, currency cur: Currency, forGoals: Bool = false) -> WealthStatement {
        let nw = Valuation.netWorth(s, trades: trades, forGoals: forGoals)
        let book = ExchangeBook(s)
        // Your listed holdings: your shares at the last close instead of the company's paper value.
        var listedPaper = 0.0, listedMarket = 0.0
        var listedNames: [String] = []
        for co in s.companies where co.status.isLive && co.holdingID == 0 {
            guard let inst = book.instruments["co:\(co.id)"], !inst.halted else { continue }
            let paper = (Valuation.companyValue(co, state: s, trades: trades) + HeldMoney.remaining(s, companyID: co.id)) * co.ownership / 100
            listedPaper += paper
            listedMarket += Double(CapTable.table(co).you) * inst.close * (1 - blockDiscount)
            listedNames.append(co.name)
        }
        let minority = (s.rest["stakes"]?.array ?? []).reduce(0) { $0 + $1["val"].double } + GroupStakes.stakesValue(s)
        let privatePaper = max(0, nw.companies - minority - listedPaper)
        let privateCounted = privatePaper * (1 - privateDiscount)
        let minorityCounted = minority * (1 - minorityDiscount)
        let discount = (privatePaper - privateCounted) + (minority - minorityCounted) + max(0, listedPaper - listedMarket)

        var lines: [WealthLine] = []
        func add(_ id: String, _ title: String, _ amount: Double, _ words: String) { if abs(amount) >= 0.5 { lines.append(WealthLine(id: id, title: title, amount: amount, words: words)) } }
        add("cash", "Cash and savings", nw.personal, "Money in your current account and savings. Counted in full.")
        add("market", "Shares, crypto and funds", nw.stocks + nw.crypto + nw.funds, "Counted at today's market prices, in full.")
        add("exchange", "Shares on the exchange", nw.exchange, "Shares you hold in the World Bank, the World Index and other listings, at the last closing price.")
        add("listed", "Your listed company", listedMarket, listedNames.isEmpty ? "" :
            "Your shares in \(listedNames.joined(separator: ", ")) at the last close, less \(Currency.percent(blockDiscount, decimals: 0)) because a whole block cannot be sold at once.")
        add("private", "Private companies", privateCounted, "Your share of what your companies are worth is \(cur.display(privatePaper)). A private company cannot be sold in a day, so it counts at \(Currency.percent(1 - privateDiscount, decimals: 0)) of that.")
        add("minority", "Stakes in other companies", minorityCounted, "Shares you hold in startups and other people's companies are worth \(cur.display(minority)) on paper. You do not control them, so they count at \(Currency.percent(1 - minorityDiscount, decimals: 0)).")
        add("luxury", "Things you own", nw.luxury, "Cars, watches and houses, at their current value.")
        add("debt", "Loans", -nw.debt, "Private loans you still owe. Company loans are already inside the company values.")
        add("tax", "Tax to pay", -nw.pendingTax, "Tax assessed and not yet paid.")
        let total = lines.reduce(0) { $0 + $1.amount }
        let assets = lines.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount }
        let liquid = nw.personal + nw.investments
        let share = assets > 0 ? min(1, max(0, liquid / assets)) : 0
        var summary = "You are worth \(cur.display(total))."
        if assets > 0 {
            summary += " \(Currency.percent(share, decimals: 0)) of it is money and shares you could sell this week"
            summary += share < 0.999 ? "; the rest is tied up in companies and things, counted at a discount." : "."
        }
        return WealthStatement(lines: lines, total: total, discount: discount, liquidShare: share, summary: summary, plain: nw)
    }
}

// MARK: Leaderboards

public enum LeaderboardKind: String, CaseIterable, Sendable { case netWorth, tradingResult }

/// What one player sends to the leaderboards. Amounts are in accounting units, which are the same in every country.
public struct LeaderboardSubmission: Equatable, Sendable {
    public var playerID: String
    public var name: String
    public var week: Int
    public var netWorth: Double
    public var tradingResult: Double
    public func value(_ kind: LeaderboardKind) -> Double { kind == .netWorth ? netWorth : tradingResult }
}

public struct LeaderboardEntry: Equatable, Identifiable, Sendable {
    public var id: String
    public var rank: Int
    public var name: String
    public var value: Double
    public var isYou: Bool
}

public struct LeaderboardView: Equatable, Sendable {
    public var kind: LeaderboardKind
    public var top: [LeaderboardEntry]
    /// The rows round you when you are not in the top list (empty when you are).
    public var around: [LeaderboardEntry]
    public var you: LeaderboardEntry?
    public var count: Int
}

public enum Leaderboards {
    /// What the server stores for you: net worth as the statement counts it, and the result of your exchange trades.
    public static func submission(_ s: GameState, trades: any TradeCatalogProviding, currency: Currency, playerID: String) -> LeaderboardSubmission {
        LeaderboardSubmission(playerID: playerID, name: s.player.name, week: s.week,
                              netWorth: Wealth.statement(s, trades: trades, currency: currency, forGoals: true).total, tradingResult: PublicExchange.tradingResult(s))
    }

    /// The board for one kind: everybody sorted by value (ties by name), with your own row in it.
    public static func view(_ kind: LeaderboardKind, me: LeaderboardSubmission, others: [LeaderboardSubmission], topCount: Int = 10, around: Int = 3) -> LeaderboardView {
        let all = (others.filter { $0.playerID != me.playerID } + [me]).sorted {
            $0.value(kind) != $1.value(kind) ? $0.value(kind) > $1.value(kind) : $0.name < $1.name
        }
        let entries = all.enumerated().map { LeaderboardEntry(id: $0.element.playerID, rank: $0.offset + 1, name: $0.element.name, value: $0.element.value(kind), isYou: $0.element.playerID == me.playerID) }
        let mine = entries.first { $0.isYou }
        let top = Array(entries.prefix(topCount))
        var near: [LeaderboardEntry] = []
        if let m = mine, m.rank > topCount {
            near = Array(entries[max(topCount, m.rank - 1 - around)..<min(entries.count, m.rank + around)])
        }
        return LeaderboardView(kind: kind, top: top, around: near, you: mine, count: entries.count)
    }
}
