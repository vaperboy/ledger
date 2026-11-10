import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

public extension GameEngine {

    func adviserOffers(companyID: Int, kind: Advisers.Kind) -> [JSONValue] {
        var s = state
        return Advisers.pool(&s, companyID: companyID, kind: kind, data: data)
    }
    func ownAdviserFirms(companyID: Int, kind: Advisers.Kind) -> [Company] { Advisers.ownFirms(state, for: companyID, kind: kind) }

    @discardableResult
    mutating func chooseAdviser(companyID: Int, kind: Advisers.Kind, providerID: Int) -> Advisers.Result {
        var r = Advisers.Result.unknown
        update { s, d, _ in r = Advisers.pick(&s, companyID: companyID, kind: kind, providerID: providerID, data: d) }
        return r
    }
    @discardableResult
    mutating func chooseOwnAdviser(companyID: Int, kind: Advisers.Kind, firmID: Int) -> Advisers.Result {
        var r = Advisers.Result.unknown
        update { s, d, _ in r = Advisers.pickOwn(&s, companyID: companyID, kind: kind, firmID: firmID, data: d) }
        return r
    }
    @discardableResult
    mutating func toggleInsurancePolicy(companyID: Int, product: String) -> Advisers.Result {
        var r = Advisers.Result.unknown
        update { s, _, _ in r = Advisers.togglePolicy(&s, companyID: companyID, product: product) }
        return r
    }

    func abroadOptions(companyID: Int) -> [Abroad.Option] { Abroad.options(state, companyID: companyID, data: data) }

    @discardableResult
    mutating func expandAbroad(companyID: Int, countryCode: String, cityID: String? = nil) -> Result<Int, Abroad.Failure> {
        var r: Result<Int, Abroad.Failure> = .failure(.notOpen)
        guard levelOpen(.abroad) else { return r }
        update { s, d, ctx in r = Abroad.expand(&s, companyID: companyID, country: countryCode, cityID: cityID, data: d, context: ctx) }
        return r
    }

    func complaints(companyID: Int) -> [Complaints.Item] { Complaints.list(state, companyID: companyID, data: data) }

    @discardableResult
    mutating func answerComplaint(companyID: Int, complaintID: Int, answer: Satisfaction.Answer) -> Bool? {
        var r: Bool?
        update { s, d, _ in r = Complaints.answer(&s, companyID: companyID, complaintID: complaintID, answer: answer, data: d) }
        return r
    }

    func staffProfile(companyID: Int, staffID: Int) -> StaffProfile.Profile? { StaffProfile.profile(state, companyID: companyID, staffID: staffID, data: data) }
    func layoffPreview(companyID: Int, count: Int) -> (names: [String], savesPerMonth: Double, severance: Double) {
        StaffProfile.layoffPreview(state, companyID: companyID, count: count, data: data)
    }

    @discardableResult
    mutating func sendOnCourse(companyID: Int, staffID: Int?, courseID: String) -> StaffProfile.CourseResult {
        var r = StaffProfile.CourseResult.none
        update { s, d, _ in r = StaffProfile.takeCourse(&s, companyID: companyID, staffID: staffID, courseID: courseID, data: d) }
        return r
    }
    @discardableResult mutating func talkToStaff(companyID: Int, staffID: Int) -> Bool? {
        var r: Bool?
        update { s, _, _ in r = StaffProfile.talk(&s, companyID: companyID, staffID: staffID) }
        return r
    }
    @discardableResult mutating func warnStaff(companyID: Int, staffID: Int) -> Bool? {
        var r: Bool?
        update { s, _, _ in r = StaffProfile.warn(&s, companyID: companyID, staffID: staffID) }
        return r
    }
    @discardableResult mutating func dismissStaff(companyID: Int, staffID: Int) -> StaffProfile.DismissResult? {
        var r: StaffProfile.DismissResult?
        update { s, d, _ in r = StaffProfile.dismiss(&s, companyID: companyID, staffID: staffID, data: d) }
        return r
    }
    @discardableResult mutating func layOffStaff(companyID: Int, count: Int) -> [Int] {
        var r: [Int] = []
        update { s, d, _ in r = StaffProfile.layOff(&s, companyID: companyID, count: count, data: d) }
        return r
    }
}
