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
    /// Answers a decision and says what came of it in a few plain lines; only a big choice with a real cost adds one cost line.
    mutating func answerDecision(messageID: Int, option: Int) -> DecisionAnswer {
        guard let m = state.inbox.first(where: { (x: Message) -> Bool in x.id == messageID }), m.status == "open", m.options.indices.contains(option) else {
            return DecisionAnswer(applied: false, lines: [], link: nil)
        }
        let fx: JSONValue = m.options[option]["fx"]
        let ids: Set<Int> = Set(state.inbox.map { (x: Message) -> Int in x.id })
        let notes: Int = (state.rest["rep"]?["ev"].array ?? []).count
        let feed: [FeedLine] = state.feedLines
        let cashBefore: Double = state.cash
        let weekly: Double = m.companyID != 0 ? (state.company(m.companyID)?.lastWeekRevenue ?? 0) : 0
        let queued: Int = (state.rest["e27"]?["q"].array ?? []).count
        update { (s: inout GameState, _: GameData, _: FinanceContext) -> Void in s.rest[EventEngine.gambleKey] = nil }
        let link: DecisionLink? = DecisionLinks.link(m, option: option, state: state)
        guard answer(messageID: messageID, option: option) else { return DecisionAnswer(applied: false, lines: [], link: nil) }
        let worked: Bool? = state.rest[EventEngine.gambleKey].map { (v: JSONValue) -> Bool in v.bool }
        update { (s: inout GameState, _: GameData, _: FinanceContext) -> Void in s.rest[EventEngine.gambleKey] = nil }
        var cur: Currency = homeCurrency
        if let c = state.company(m.companyID) { cur = currency(for: c) }
        var lines: [String] = Self.effectLines(fx, worked: worked, currency: cur)
        let newNotes: [JSONValue] = Array((state.rest["rep"]?["ev"].array ?? []).dropFirst(notes))
        lines += newNotes.map { (n: JSONValue) -> String in n["t"].string }
        lines += Self.feedAdded(feed, state.feedLines).map { (l: FeedLine) -> String in l.text }
        lines += state.inbox.filter { (x: Message) -> Bool in !ids.contains(x.id) }.map { (x: Message) -> String in x.title }
        var seen: Set<String> = []
        lines = lines.filter { (l: String) -> Bool in !l.isEmpty && DecisionStory.isPlain(l) && seen.insert(l).inserted }
        // A story with a sequel: say when the result comes, so a quiet answer does not look like nothing happened.
        let sequel: Bool = (state.rest["e27"]?["q"].array ?? []).count > queued
        lines = Array(lines.prefix(DecisionStory.maxLines - (sequel ? 1 : 0)))
        if sequel { lines.append("More follows in the coming weeks.") }
        // One account: the money moved once, so it is told once, and only for a big choice.
        let spent: Double = cashBefore - state.cash
        if spent >= 1, DecisionStory.isBig(m, option: option, spent: spent, weeklyRevenue: weekly) {
            lines.append(DecisionStory.costLine(spent, homeCurrency))
        }
        if lines.isEmpty { lines = ["Nothing changes for now."] }
        return DecisionAnswer(applied: true, lines: lines, link: link)
    }

    /// The option's effects as they turned out, in plain words: the gamble's branch that came up, then the rest.
    static func effectLines(_ fx: JSONValue, worked: Bool?, currency cur: Currency) -> [String] {
        guard case .object(var base) = fx else { return [] }
        var out: [String] = []
        let g: JSONValue = base["gamble"] ?? .null
        base["gamble"] = nil
        if !g.isNull, let w = worked {
            out.append(w ? "It worked out." : "It did not work out.")
            out += EffectPreview.story(w ? g["ok"] : g["bad"], currency: cur)
        }
        out += EffectPreview.story(.object(base), currency: cur)
        return out
    }

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

/// How an answer's result is told: a short story, never engine numbers, and a cost line only for the big choices.
public enum DecisionStory {
    public static let maxLines = 3
    static let bigWords: Set<String> = ["fire", "dismiss", "sack", "settle", "court", "lawyer", "lawsuit", "sue", "sues", "fine", "fines",
                                        "sign", "contract", "sell"]

    /// False for a line that shows an engine number such as "+2 reputation", "−150 kr" or "demand 5%".
    public static func isPlain(_ line: String) -> Bool {
        line.range(of: #"[+−]\s?\d|(^|\s)-\d|\d\s?%"#, options: .regularExpression) == nil
    }

    /// Firing someone, a lawsuit, a fine, a signed contract, or a cost of more than two weeks of the company's sales.
    public static func isBig(_ m: Message, option: Int, spent: Double, weeklyRevenue: Double) -> Bool {
        guard m.options.indices.contains(option) else { return false }
        if DecisionConfirm.confirmation(for: m, option: option).irreversible { return true }
        let fx: JSONValue = m.options[option]["fx"]
        if fx["fine"].double != 0 { return true }
        let text: String = (m.options[option]["l"].string + " " + m.title).lowercased()
        let words: [String] = text.split { (c: Character) -> Bool in !c.isLetter }.map { (w: Substring) -> String in String(w) }
        if words.contains(where: { (w: String) -> Bool in bigWords.contains(w) }) || text.contains("let go") { return true }
        return weeklyRevenue > 0 && spent >= 2 * weeklyRevenue
    }

    public static func costLine(_ spent: Double, _ cur: Currency) -> String { "It cost you \(cur.display(spent))." }
}
