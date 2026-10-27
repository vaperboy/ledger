import Foundation
import GameCore
import Countries
import Finance
import Businesses

/// Gifts and charity, ambitions, the business paper, weather and tourists, monthly results, the luxury extras.
/// Originals: `ACT.give28`, `found28`, `amb27pick`, `V.paper40`, `V.wx56`, `V.month30`, `ACT.lx56din`.
public extension GameEngine {
    // MARK: Giving back
    var giftOptions: [Giving.Gift] { Giving.gifts }
    var givingPlaces: [Giving.Place] { Giving.places(state, data) }
    func giftCost(_ giftID: String) -> Double { Giving.cost(of: giftID, state, data) }
    func giftDone(_ giftID: String, place: Giving.Place) -> Bool { Giving.isDone(state, giftID: giftID, placeKey: place.key) }
    var givingMarks: [(name: String, yearly: Bool, week: Int)] { Giving.marks(state) }
    var foundation: (capital: Double, given: Double)? { Giving.foundation(state) }
    @discardableResult mutating func give(giftID: String, countryCode: String, cityID: String) -> Giving.Result {
        var r = Giving.Result.unknown
        update { s, d, _ in r = Giving.give(&s, giftID: giftID, countryCode: countryCode, cityID: cityID, data: d) }
        return r
    }
    @discardableResult mutating func startFoundation(amount: Double) -> Giving.Result {
        var r = Giving.Result.unknown
        update { s, d, _ in r = Giving.startFoundation(&s, amount: amount, data: d) }
        return r
    }

    // MARK: Ambitions
    var ambitionPaths: [Ambitions.Path] { Ambitions.paths }
    var currentAmbition: String? { Ambitions.currentPath(state) }
    var legacyScore: Double { Ambitions.legacyScore(state) }
    func ambitionMilestones(path: String) -> [Ambitions.Milestone] { Ambitions.milestones(state, data, path: path, tier: Ambitions.tier(state, path)) }
    func ambitionPerk(path: String) -> String { Ambitions.perkText(path, level: max(0, Ambitions.perk(state, data, path))) }
    var legacyHistory: [(week: Int, text: String, pathName: String, points: Double)] { Ambitions.history(state) }
    @discardableResult mutating func chooseAmbition(path: String) -> Bool {
        var r = false
        update { s, d, _ in r = Ambitions.choose(&s, path: path, data: d) }
        return r
    }

    // MARK: The paper
    var paperName: String { Press.paperName(state, data: data) }
    var frontPages: [Press.FrontPage] { Press.frontPages(state) }
    var publicImage: Press.Image { Press.image(state) }
    var publicImageWord: String { Press.imageWord(state) }

    // MARK: Weather and tourists
    func weatherForecast(countryCode: String) -> (now: WeekWeather, ahead: [WeatherEvents.Forecast]) { WeatherEvents.forecast(state, data, country: countryCode) }
    func bigWeatherWarnings() -> [WeatherEvents.BigWarning] { WeatherEvents.bigWarnings(state, data) }
    func touristEvents(countryCode: String) -> [(text: String, factor: Double, from: Int, until: Int, city: String?)] { WeatherEvents.touristEvents(state, country: countryCode) }
    func weatherLine(companyID: Int) -> (weather: Double, tourists: Double, workingTime: Double, kind: String)? { WeatherEvents.companyLine(state, data, companyID: companyID) }

    // MARK: Monthly results
    func monthlyResults(companyID: Int) -> MonthView.Summary? { MonthView.summary(state, companyID: companyID) }

    // MARK: Luxury extras
    var tirednessWord: String { Luxury.tirednessWord(state) }
    @discardableResult mutating func hostYachtDinner() -> Luxury.DinnerResult {
        var r = Luxury.DinnerResult.none
        update { s, d, _ in r = Luxury.hostDinner(&s, data: d) }
        return r
    }
}
