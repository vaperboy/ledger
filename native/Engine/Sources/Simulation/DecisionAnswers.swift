import Foundation
import GameCore
import Countries
import Finance
import Businesses
import Events

/// The one screen an answered decision is about, for a single "Open ..." link after answering.
public struct DecisionLink: Equatable, Sendable {
    public var title: String
    public var companyID: Int
    /// A company section key ("staff", "salesMarket", "operations"); empty when the link opens an app.
    public var section: String
    /// A phone app key ("bank") when the link opens an app instead of a company.
    public var app: String
}

/// What answering a decision actually did: the lines say what happened, not what might have.
public struct DecisionAnswer: Equatable, Sendable {
    public var applied: Bool
    public var lines: [String]
    public var link: DecisionLink?
}

public enum DecisionLinks {
    static let staffEvents: Set<String> = ["g_quit", "g_poach", "g_union", "g_sick", "c_devquit", "c_stylistLeaves", "rival_poach"]
    static let staffDecisions: Set<String> = ["s_quit", "s_burnout", "g_mgrraise", "g_teampoach", "e_execleave", "e_wages", "st_poached"]
    static let staffActions: Set<String> = ["staffx", "mgrraise", "mgrpoach", "g27poach"]
    static let priceEvents: Set<String> = ["r_priceWar", "d_price_war", "chainpwreply", "chainpwlong", "chainpwtruce", "g_rival", "w_black_friday",
                                           "m_inflation_spike", "rival_call", "d_new_competitor"]
    static let supplyEvents: Set<String> = ["g_supply", "g_supbust", "g_trial", "pr_raw", "pr_flour", "pr_wood", "p_matprice",
                                            "chainsuppnotice", "chainsuppcash", "chainsuppstop"]
    static let supplyDecisions: Set<String> = ["s_supprice"]
    static let loanEvents: Set<String> = ["f_rate_up", "f_loan_offer", "f_equipment_finance"]
    static let loanDecisions: Set<String> = ["g_loan", "e_refi"]

    /// The screen this decision is about, or nil when no single screen helps.
    public static func link(_ m: Message, option: Int, state s: GameState) -> DecisionLink? {
        guard m.companyID != 0, s.company(m.companyID) != nil else { return nil }
        let ev: String = m.str("ev")
        let def: String = m.value("data")["id"].string
        let fx: JSONValue = m.options.indices.contains(option) ? m.options[option]["fx"] : .null
        let area: String = EventPack.byID[ev]?.area ?? ""
        func company(_ title: String, _ section: String) -> DecisionLink { DecisionLink(title: title, companyID: m.companyID, section: section, app: "") }
        if loanEvents.contains(ev) || loanDecisions.contains(def) { return DecisionLink(title: "Open loans", companyID: m.companyID, section: "", app: "bank") }
        if staffActions.contains(m.actionID) || staffEvents.contains(ev) || staffDecisions.contains(def) || area == "staff"
            || fx["quit"].bool || fx["raise"].double != 0 || !fx["stay"].isNull { return company("Open the team", "staff") }
        if priceEvents.contains(ev) || fx["pr"].double != 0 { return company("Open prices", "salesMarket") }
        if supplyEvents.contains(ev) || supplyDecisions.contains(def) || area == "supply" { return company("Open suppliers", "operations") }
        return nil
    }
}

public extension GameEngine {
    /// Answers a decision and says what came of it, so every answer shows its own result.
    mutating func answerDecision(messageID: Int, option: Int) -> DecisionAnswer {
        guard let m = state.inbox.first(where: { (x: Message) -> Bool in x.id == messageID }), m.status == "open", m.options.indices.contains(option) else {
            return DecisionAnswer(applied: false, lines: [], link: nil)
        }
        let fx: JSONValue = m.options[option]["fx"]
        let ids: Set<Int> = Set(state.inbox.map { (x: Message) -> Int in x.id })
        let notes: Int = (state.rest["rep"]?["ev"].array ?? []).count
        let feed: [FeedLine] = state.feedLines
        let coCash: Double? = m.companyID != 0 ? state.company(m.companyID)?.cash : nil
        let myCash: Double = state.cash
        let queued: Int = (state.rest["e27"]?["q"].array ?? []).count
        update { (s: inout GameState, _: GameData, _: FinanceContext) -> Void in s.rest[EventEngine.gambleKey] = nil }
        let link: DecisionLink? = DecisionLinks.link(m, option: option, state: state)
        guard answer(messageID: messageID, option: option) else { return DecisionAnswer(applied: false, lines: [], link: nil) }
        let worked: Bool? = state.rest[EventEngine.gambleKey].map { (v: JSONValue) -> Bool in v.bool }
        update { (s: inout GameState, _: GameData, _: FinanceContext) -> Void in s.rest[EventEngine.gambleKey] = nil }
        var cur: Currency = homeCurrency
        if let c = state.company(m.companyID) { cur = currency(for: c) }
        var lines: [String] = Self.effectLines(fx, worked: worked, currency: cur)
        if let before = coCash, let after = state.company(m.companyID)?.cash, abs(after - before) >= 1 {
            let name: String = state.company(m.companyID)?.name ?? "The company"
            lines.append("\(name): \(Self.signedMoney(after - before, cur))")
        }
        if abs(state.cash - myCash) >= 1 { lines.append("Your own cash: \(Self.signedMoney(state.cash - myCash, homeCurrency))") }
        let newNotes: [JSONValue] = Array((state.rest["rep"]?["ev"].array ?? []).dropFirst(notes))
        lines += newNotes.map { (n: JSONValue) -> String in n["t"].string }
        lines += Self.feedAdded(feed, state.feedLines).map { (l: FeedLine) -> String in l.text }
        lines += state.inbox.filter { (x: Message) -> Bool in !ids.contains(x.id) }.map { (x: Message) -> String in x.title }
        // A story with a sequel: say when the result comes, so a quiet answer does not look like nothing happened.
        if (state.rest["e27"]?["q"].array ?? []).count > queued { lines.append("More follows in the coming weeks.") }
        var seen: Set<String> = []
        lines = lines.filter { (l: String) -> Bool in !l.isEmpty && seen.insert(l).inserted }
        if lines.isEmpty { lines = ["Nothing changes for now."] }
        return DecisionAnswer(applied: true, lines: Array(lines.prefix(6)), link: link)
    }

    /// The option's effects as they turned out: the gamble's branch that came up, without the money lines (the cash change says those).
    static func effectLines(_ fx: JSONValue, worked: Bool?, currency cur: Currency) -> [String] {
        guard case .object(var base) = fx else { return [] }
        var out: [String] = []
        let g: JSONValue = base["gamble"] ?? .null
        base["gamble"] = nil
        if !g.isNull, let w = worked {
            out.append(w ? "It worked out." : "It did not work out.")
            out += EffectPreview.lines(w ? g["ok"] : g["bad"], currency: cur)
        }
        out += EffectPreview.lines(.object(base), currency: cur)
        let money: [String] = ["Costs ", "Brings in ", "Risk of a loss", "Fine of ", "If it works", "If not", "A gamble"]
        return out.filter { (l: String) -> Bool in !money.contains { (p: String) -> Bool in l.hasPrefix(p) } }
    }

    static func signedMoney(_ v: Double, _ cur: Currency) -> String { (v >= 0 ? "+" : "\u{2212}") + cur.display(abs(v)) }

    /// Feed lines added since `before`; the list keeps only its newest lines, so match the overlap.
    static func feedAdded(_ before: [FeedLine], _ after: [FeedLine]) -> [FeedLine] {
        if before.isEmpty { return after }
        for n in 0...after.count {
            let keep: Int = after.count - n
            if keep <= before.count && Array(after.prefix(keep)) == Array(before.suffix(keep)) { return Array(after.suffix(n)) }
        }
        return []
    }
}
