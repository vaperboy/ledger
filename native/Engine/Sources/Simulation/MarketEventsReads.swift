import Foundation
import GameCore
import Businesses

public extension GameEngine {
    func marketEvents(limit: Int) -> [MarketEvent] { MarketEvents.events(state, limit: limit) }

    func largestPaymentToday(companyID: Int?) -> (amount: Double, from: String, companyID: Int)? { MarketEvents.largestPayment(state, companyID: companyID) }

    func marketTrend(companyID: Int) -> MarketTrend { MarketEvents.trend(state, companyID: companyID) }

    @discardableResult
    mutating func acknowledgeRecognition(eventID: Int) -> SettingResult {
        var why: String?
        update { s, _, _ in why = MarketEvents.acknowledgeRecognition(&s, eventID: eventID) }
        return why.map { .refused($0) } ?? .applied
    }

    func brandValue(companyID: Int) -> Double { state.company(companyID).map { BrandValues.company(state, $0).score } ?? 0 }

    func groupBrandValue() -> BrandValue { BrandValues.group(state) }

    func researchOptions(companyID: Int) -> [ResearchOption] { MarketResearch.options(state, companyID: companyID, data: data) }

    @discardableResult
    mutating func buyResearch(companyID: Int, optionID: String) -> SettingResult {
        let data = self.data
        return applySetting(refuse: { MarketResearch.refusal($0, companyID: companyID, optionID: optionID, data: data) }, probe: { $0.companySnapshot(companyID) }) { s, d, _ in
            MarketResearch.buy(&s, companyID: companyID, optionID: optionID, data: d)
        }
    }

    func research(companyID: Int) -> [ResearchReport] { state.company(companyID).map(MarketResearch.reports) ?? [] }
}
