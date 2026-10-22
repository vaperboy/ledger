import Foundation
import GameCore
import Countries

/// A country's labour law as the game uses it: minimum wage, standard week and overtime premium, notice and severance by tenure,
/// probation. All of it is data (`labour` in `Countries/Resources/country_traits.json`); no country is named here. A country
/// without an entry has no rules (no minimum, a 40 hour week, no notice or severance).
///
/// ```
/// "UK": { "minMonthly": 2065, "statutory": true, "stdHours": 37.5, "overtimePremium": 0,
///         "noticeWeeks": 1, "noticePerYear": 1, "noticeMax": 12,
///         "severancePerYear": 1.0, "severanceMin": 0, "severanceMax": 0, "severanceAfterYears": 2,
///         "leaveDays": 28, "probationWeeks": 104, "probationNoticeWeeks": 1, "atWill": false }
/// ```
/// `minMonthly` is in the country's own currency for a standard week (`stdHours`); `statutory` false means it is a floor set by
/// collective agreements and custom rather than by law. A max of 0 means no cap. See docs/TAX_SOURCES.md for sources.
public struct LabourRules: Equatable, Sendable {
    public var minMonthly = 0.0
    public var statutory = false
    public var stdHours = 40.0
    public var overtimePremium = 0.0
    public var noticeWeeks = 0.0
    public var noticePerYear = 0.0
    public var noticeMax = 0.0
    public var severancePerYear = 0.0
    public var severanceMin = 0.0
    public var severanceMax = 0.0
    public var severanceAfterYears = 0.0
    public var leaveDays = 0.0
    public var probationWeeks = 0.0
    public var probationNoticeWeeks = 0.0
    /// No unfair dismissal protection at all.
    public var atWill = false

    public init() {}

    public init(code: String) {
        let j = CountryTraits.labour(code)
        guard !j.isNull else { return }
        func n(_ k: String, _ d: Double = 0) -> Double { j[k].isNull ? d : j[k].double }
        minMonthly = n("minMonthly"); statutory = j["statutory"].bool; stdHours = max(1, n("stdHours", 40)); overtimePremium = n("overtimePremium")
        noticeWeeks = n("noticeWeeks"); noticePerYear = n("noticePerYear"); noticeMax = n("noticeMax")
        severancePerYear = n("severancePerYear"); severanceMin = n("severanceMin"); severanceMax = n("severanceMax"); severanceAfterYears = n("severanceAfterYears")
        leaveDays = n("leaveDays"); probationWeeks = n("probationWeeks"); probationNoticeWeeks = n("probationNoticeWeeks"); atWill = j["atWill"].bool
    }

    public init(country: Country) { self.init(code: country.code) }

    public var hasMinimum: Bool { minMonthly > 0 }

    // MARK: Minimum wage

    /// The lowest monthly pay (accounting units) for someone contracted `hours` a week. It is pro rata to a standard week and follows
    /// inflation like the market wage does. `rate` is the currency's accounting units per local unit.
    public func minimumMonthly(hours: Double, rate: Double, inflation: Double, week: Int) -> Double {
        guard hasMinimum else { return 0 }
        return minMonthly * rate * pow(1 + inflation, Double(week) / 52) * max(0, hours) / stdHours
    }

    // MARK: Overtime

    /// The hours over which overtime is paid: the standard week, or the agreed full week if that is longer. Part-timers
    /// get the premium only above the standard week.
    public func overtimeThreshold(contracted: Double) -> Double { max(stdHours, min(contracted, StaffModel.fullWeekHours)) }

    public func overtimeHours(worked: Double, contracted: Double) -> Double { max(0, worked - overtimeThreshold(contracted: contracted)) }

    /// Extra pay for a week's overtime (before employer charges): the hours at the hourly rate plus the premium.
    public func overtimePay(monthlyWage: Double, contracted: Double, worked: Double) -> Double {
        let h = max(1, contracted)
        return monthlyWage * 12 / 52 / h * overtimeHours(worked: worked, contracted: contracted) * (1 + overtimePremium)
    }

    /// Fatigue starts at the standard week (never later than 40 hours).
    public func tirednessThreshold(contracted: Double) -> Double { min(40, overtimeThreshold(contracted: contracted)) }

    // MARK: Dismissal

    public struct Termination: Equatable, Sendable {
        public var noticeWeeks: Double
        public var severanceWeeks: Double
        public var weeks: Double { noticeWeeks + severanceWeeks }
        /// What the employer pays (accounting units) for a person on `monthlyWage`, with the employer's social charge.
        public func cost(monthlyWage: Double, employerSocial: Double) -> Double { monthlyWage * 12 / 52 * weeks * (1 + employerSocial) }
    }

    /// Notice (paid in lieu) and severance for letting someone go after `tenureWeeks`. The one place the game works this out for staff,
    /// layoffs and the manager. Nothing is due for dismissal with cause or for someone already serving notice.
    public func termination(tenureWeeks: Double, withCause: Bool = false, onNotice: Bool = false) -> Termination {
        if withCause || onNotice { return Termination(noticeWeeks: 0, severanceWeeks: 0) }
        let years = max(0, tenureWeeks) / 52
        if tenureWeeks < probationWeeks { return Termination(noticeWeeks: probationNoticeWeeks, severanceWeeks: 0) }
        var notice = noticeWeeks + noticePerYear * years.rounded(.down)
        if noticeMax > 0 { notice = min(notice, noticeMax) }
        var sev = 0.0
        if (severancePerYear > 0 || severanceMin > 0) && years >= severanceAfterYears {
            sev = max(severanceMin, severancePerYear * years)
            if severanceMax > 0 { sev = min(sev, severanceMax) }
        }
        return Termination(noticeWeeks: notice, severanceWeeks: sev)
    }

    /// Whether someone let go without a documented reason can claim unfair dismissal: not in probation, not in an at-will country.
    public func canClaimUnfairDismissal(tenureWeeks: Double) -> Bool { !atWill && tenureWeeks >= probationWeeks }

    // MARK: Card text

    /// Short lines for the Team card: label and value.
    public func summary(currency: Currency) -> [(label: String, value: String)] {
        func w(_ x: Double) -> String { x == x.rounded() ? "\(Int(x))" : String(format: "%.1f", x) }
        var out: [(label: String, value: String)] = []
        out.append(("Minimum wage", hasMinimum ? "\(currency.country.currencySymbol) \(Int(minMonthly.rounded())) a month" + (statutory ? "" : " (agreements)") : "None"))
        out.append(("Standard week", "\(w(stdHours)) h"))
        out.append(("Overtime", overtimePremium > 0 ? "+\(Int((overtimePremium * 100).rounded()))%" : "Basic rate"))
        out.append(("Notice", noticeWeeks > 0 || noticePerYear > 0 ? "\(w(noticeWeeks)) weeks, +\(w(noticePerYear)) a year" : "None"))
        out.append(("Severance", severancePerYear > 0 ? "\(w(severancePerYear)) weeks a year" + (severanceAfterYears > 0 ? " after \(w(severanceAfterYears)) years" : "") : severanceMin > 0 ? "\(w(severanceMin)) weeks" : "None"))
        out.append(("Paid leave", leaveDays > 0 ? "\(w(leaveDays)) days" : "None"))
        out.append(("Probation", atWill ? "At will" : probationWeeks > 0 ? "\(w(probationWeeks)) weeks" : "None"))
        return out
    }
}
