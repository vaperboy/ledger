import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

/// The smaller company tabs as engine calls: advisers and insurance, expanding abroad, complaints, the staff profile.
/// Originals: `ACT.provpick`, `ownpick`, `toggleins`, `abrset`/`abrgo`, `complres`, `warnstaff`, `firestaff`, `logo`, `talkstaff`,
/// `docourse`, `setpay`, `setrate`.
public extension GameEngine {
    // MARK: Advisers (accountant, law firm, insurer) and insurance policies

    func adviserOffers(companyID: Int, kind: Advisers.Kind) -> [JSONValue] {
        var s = state
        return Advisers.pool(&s, companyID: companyID, kind: kind, data: data)
    }
    func ownAdviserFirms(companyID: Int, kind: Advisers.Kind) -> [Company] { Advisers.ownFirms(state, for: companyID, kind: kind) }
    func ownAdviserOffer(companyID: Int, kind: Advisers.Kind, firmID: Int) -> JSONValue? {
        state.company(firmID).map { Advisers.ownProvider(state, kind: kind, firm: $0, data: data) }
    }
    func currentAdviser(companyID: Int, kind: Advisers.Kind) -> JSONValue { state.company(companyID).map { Advisers.current($0, kind) } ?? .null }

    /// Hire a provider. For a law firm or insurer, providerID 0 removes the current one.
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
    /// Switch an insurance policy on or off (needs an insurer first).
    @discardableResult
    mutating func toggleInsurancePolicy(companyID: Int, product: String) -> Advisers.Result {
        var r = Advisers.Result.unknown
        update { s, _, _ in r = Advisers.togglePolicy(&s, companyID: companyID, product: product) }
        return r
    }

    // MARK: Abroad

    func abroadOptions(companyID: Int) -> [Abroad.Option] { Abroad.options(state, companyID: companyID, data: data) }

    /// Open a subsidiary in another country. Registration fees and share capital come from your personal cash.
    @discardableResult
    mutating func expandAbroad(companyID: Int, countryCode: String, cityID: String? = nil) -> Result<Int, Abroad.Failure> {
        var r: Result<Int, Abroad.Failure> = .failure(.notOpen)
        update { s, d, ctx in r = Abroad.expand(&s, companyID: companyID, country: countryCode, cityID: cityID, data: d, context: ctx) }
        return r
    }

    // MARK: Complaints

    func complaints(companyID: Int) -> [Complaints.Item] { Complaints.list(state, companyID: companyID, data: data) }

    /// Refund, apologise or ignore an open complaint. Returns whether the customer is satisfied (nil: no such open complaint).
    @discardableResult
    mutating func answerComplaint(companyID: Int, complaintID: Int, answer: Satisfaction.Answer) -> Bool? {
        var r: Bool?
        update { s, d, _ in r = Complaints.answer(&s, companyID: companyID, complaintID: complaintID, answer: answer, data: d) }
        return r
    }

    // MARK: Staff profile

    func staffProfile(companyID: Int, staffID: Int) -> StaffProfile.Profile? { StaffProfile.profile(state, companyID: companyID, staffID: staffID, data: data) }
    func courseOffers(companyID: Int) -> [StaffProfile.Course] { state.company(companyID).map { StaffProfile.courses($0, data: data) } ?? [] }
    func layoffPreview(companyID: Int, count: Int) -> (names: [String], savesPerMonth: Double, severance: Double) {
        StaffProfile.layoffPreview(state, companyID: companyID, count: count, data: data)
    }

    /// Send a team member (staffID nil: yourself) on a course.
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
    @discardableResult mutating func setPayModel(companyID: Int, staffID: Int, mode: String) -> StaffProfile.PayResult {
        var r = StaffProfile.PayResult.unknown
        update { s, d, _ in r = StaffProfile.setPayModel(&s, companyID: companyID, staffID: staffID, mode: mode, data: d) }
        return r
    }
    @discardableResult mutating func setCommissionRate(companyID: Int, staffID: Int, rate: Double) -> Bool {
        var r = false
        update { s, _, _ in r = StaffProfile.setCommissionRate(&s, companyID: companyID, staffID: staffID, rate: rate) }
        return r
    }
}
