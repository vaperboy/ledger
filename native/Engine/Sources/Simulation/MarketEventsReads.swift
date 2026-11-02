import Foundation
import GameCore
import Businesses

/// Reads for the app's market animations; the log itself is written by `MarketEvents` hooks in the weekly code.
public extension GameEngine {
    /// The latest market events, newest first.
    func marketEvents(limit: Int) -> [MarketEvent] { MarketEvents.events(state, limit: limit) }

    /// The single largest customer payment booked today (one company, or all when nil), or nil when none was booked today.
    func largestPaymentToday(companyID: Int?) -> (amount: Double, from: String, companyID: Int)? { MarketEvents.largestPayment(state, companyID: companyID) }

    /// The trade's market price index over the last 30 days.
    func marketTrend(companyID: Int) -> MarketTrend { MarketEvents.trend(state, companyID: companyID) }

    /// Thank the person a recognition event is about: a small, logged lift in mood and loyalty (13 weeks of good mood). Ignoring the event does nothing.
    @discardableResult
    mutating func acknowledgeRecognition(eventID: Int) -> SettingResult {
        var why: String?
        update { s, _, _ in why = MarketEvents.acknowledgeRecognition(&s, eventID: eventID) }
        return why.map { .refused($0) } ?? .applied
    }

    /// 0 to 100: what the company's name is worth (reputation, years trading, outlets under the name, awards).
    func brandValue(companyID: Int) -> Double { state.company(companyID).map { BrandValues.company(state, $0).score } ?? 0 }

    /// The whole group's brand with its parts (points: they add up to the score).
    func groupBrandValue() -> BrandValue { BrandValues.group(state) }

    /// The reports the company can buy now; a market advisor halves cost and weeks.
    func researchOptions(companyID: Int) -> [ResearchOption] { MarketResearch.options(state, companyID: companyID, data: data) }

    /// Order a report. The cost is paid now; the report arrives after its weeks and an inbox message says so.
    @discardableResult
    mutating func buyResearch(companyID: Int, optionID: String) -> SettingResult {
        let data = self.data
        return applySetting(refuse: { MarketResearch.refusal($0, companyID: companyID, optionID: optionID, data: data) }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            MarketResearch.buy(&s, companyID: companyID, optionID: optionID, data: d)
        }
    }

    /// Delivered reports, oldest first.
    func research(companyID: Int) -> [ResearchReport] { state.company(companyID).map(MarketResearch.reports) ?? [] }
}
