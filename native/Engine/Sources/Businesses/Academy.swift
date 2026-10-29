import Foundation
import GameCore
import Countries
import Employees
import Finance

/// The academy: send a worker (or yourself) on one of the trade's courses. Results are uncertain, and a worker who did very well
/// may be poached by a competitor. Original: `takeCourse` (engine/people/people.js), the academy screen (features/screens/restyled_screens.js)
/// and the `crs` list of each trade (courses.json, taken from engine/businesses/*.js).
public enum Academy {
    static let book: JSONValue = {
        guard let url = Bundle.module.url(forResource: "courses", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return .null }
        return json
    }()

    public struct Course: Identifiable, Equatable, Sendable {
        public var id: String
        public var name: String
        /// In the reference economy; scale with `Currency.scaledPrice`.
        public var baseCost: Double
        public var days: Int
        /// Skill points a good result adds.
        public var gain: Double
    }

    public static func courses(forTrade id: String) -> [Course] {
        book[id].array.map { Course(id: $0[0].string, name: $0[1].string, baseCost: $0[2].double, days: $0[3].int, gain: $0[4].double) }
    }

    public static func cost(_ c: Course, company co: Company, data: GameData, state s: GameState) -> Double {
        World(state: s, data: data).currency(co).scaledPrice(c.baseCost)
    }

    public enum Outcome: Equatable, Sendable {
        case notEnoughCash
        case unavailable
        case done(message: String, gain: Double, poached: Bool)
    }

    /// `staffID` 0 sends the owner. Original: `takeCourse`.
    public static func send(_ s: inout GameState, companyID: Int, staffID: Int, course cid: String, data: GameData) -> Outcome {
        guard let ci = s.companyIndex(companyID), let c = courses(forTrade: s.companies[ci].type).first(where: { $0.id == cid }) else { return .unavailable }
        let co = s.companies[ci]
        if staffID != 0 && !co.staff.contains(where: { $0.id == staffID }) { return .unavailable }
        if staffID == 0 && co.managerID != nil { return .unavailable }
        let cost = Academy.cost(c, company: co, data: data, state: s)
        guard co.cash >= cost || Payments.liquid(s) >= cost else { return .notEnoughCash }
        Payments.companyPays(&s, companyID: companyID, amount: cost, category: "oth", label: "Course: \(c.name)")
        let roll = s.random.next()
        var gain = 0.0
        var msg = "No noticeable change"
        if roll < 0.18 { msg = "Nothing sticks. Wasted money." }
        else if roll < 0.34 { gain = c.gain * 0.4; msg = "Small gain" }
        else if roll < 0.9 { gain = c.gain; msg = "Solid gain" }
        else { gain = c.gain * 1.8; msg = "Great result" }
        let name = staffID == 0 ? s.player.name : (s.people[staffID]?.name ?? "A worker")
        // A very good result makes the person attractive to a competitor.
        let poach = staffID != 0 && roll > 0.9 && s.random.chance(0.3)
        if staffID == 0 {
            s.companies[ci].ownerSkill = clamp(s.companies[ci].ownerSkill + gain, 0, 100)
        } else if let k = s.companies[ci].staff.firstIndex(where: { $0.id == staffID }) {
            s.companies[ci].staff[k].skillGain = clamp(s.companies[ci].staff[k].skillGain + gain, -10, 70)
        }
        s.note("\(name) attended \"\(c.name)\" at \(co.name): \(msg).", tone: gain > 0 ? "good" : "n", companyID: companyID)
        if poach {
            s.note("\(name) was poached by a competitor after the course.", tone: "bad", companyID: companyID)
            Dismissal.dismiss(&s, companyID: companyID, staffID: staffID, reason: .resignation, data: data)
        }
        return .done(message: msg, gain: gain, poached: poach)
    }
}
