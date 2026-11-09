import Foundation
import GameCore
import Businesses

/// The rivals of one company's market, for the Rivals page.
public struct RivalMarket: Identifiable, Equatable, Sendable {
    public var companyID: Int
    public var title: String
    public var cards: [RivalStories.Card]
    public var id: Int { companyID }
}

/// What the Rivals, Weekly plan and Desk pages read and do (rules in Businesses/RivalStories.swift, WeeklyFocus.swift and Desk.swift).
public extension GameEngine {
    // MARK: Rivals

    /// The Rivals page has opened (a few weeks in, after the first steps).
    var rivalsOpen: Bool { Unlocks.isOpen(state, "rivals") }

    /// The markets the player trades in: one open company per trade and city, with its rivals told as cards.
    func rivalMarkets() -> [RivalMarket] {
        var seen = Set<String>()
        var out: [RivalMarket] = []
        for co in state.companies where co.status == .open && co.type != "hold" && co.type != "club" {
            guard seen.insert(Rivals.key(co)).inserted else { continue }
            let cards = RivalStories.cards(state, companyID: co.id, data: data)
            if !cards.isEmpty { out.append(RivalMarket(companyID: co.id, title: co.name, cards: cards)) }
        }
        return out
    }

    /// Recent moves of the rivals in one company's market, newest first.
    func rivalMoves(companyID: Int, limit: Int = 12) -> [RivalStories.Move] { RivalStories.timeline(state, companyID: companyID, limit: limit) }

    // MARK: Weekly plan

    var weeklyPlanOpen: Bool { Unlocks.isOpen(state, "focus") }
    var weeklyPlan: WeeklyFocus.Summary { WeeklyFocus.summary(state) }
    /// How the last plans went, newest first.
    var weeklyPlanResults: [WeeklyFocus.Result] { WeeklyFocus.results(state) }

    // MARK: Desk

    var deskOpen: Bool { DeskStories.isOpen(state) }
    /// `realDay` is the player's calendar day number (see `PlayStreak`).
    func deskWaiting(realDay: Int) -> Bool { DeskStories.waiting(state, realDay: realDay) }
    func deskToday(realDay: Int) -> DeskStories.Today? { DeskStories.today(state, realDay: realDay) }
    /// Put today's situation on the desk (once per real day).
    @discardableResult
    mutating func deskOpenToday(realDay: Int) -> DeskStories.Today? {
        var t: DeskStories.Today?
        update { s, d, _ in t = DeskStories.open(&s, realDay: realDay, data: d) }
        return t
    }
    @discardableResult
    mutating func deskChoose(option: Int, realDay: Int) -> DeskStories.Choice? {
        var c: DeskStories.Choice?
        update { s, d, _ in c = DeskStories.choose(&s, option: option, realDay: realDay, data: d) }
        return c
    }
    func deskPages() -> [DeskStories.ChapterPage] { DeskStories.pages(state) }
    func deskCovers() -> [String] { DeskStories.covers(state) }
    var deskDaysPlayed: Int { DeskStories.daysPlayed(state) }
    var deskPlayingOut: [String] { DeskStories.playingOut(state) }
}
