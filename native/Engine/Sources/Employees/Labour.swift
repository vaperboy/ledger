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
    /// A step in a table: from this many years (or this age) the value applies.
    public struct Band: Equatable, Sendable { public var from: Double; public var value: Double }

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
    /// Statutory paid annual leave for a new hire, in the law's own days (`leaveUnit`: "working" = days of a 5 day week, "calendar" = any day).
    /// The only leave field in the data (`work.leaveWeeks` was removed).
    public var leaveDays = 0.0
    public var leaveCalendarDays = false
    /// The same leave in weeks.
    public var leaveWeeks: Double { leaveDays / (leaveCalendarDays ? 7 : 5) }
    public var probationWeeks = 0.0
    public var probationNoticeWeeks = 0.0
    /// No unfair dismissal protection at all.
    public var atWill = false
    /// Notice by service: the last band whose years are reached gives the weeks (`noticeBands`: [[fromYears, weeks]]). Empty = base plus per year.
    public var noticeBands: [Band] = []
    /// Severance in tiers of weeks per year of service (`severanceTiersMonths`: [[fromYears, monthsOfReferenceSalaryPerYear]], a month being 52/12 weeks).
    public var severanceTiers: [Band] = []
    /// Severance weeks per year by the person's age (`severanceAgeBands`: [[fromAge, weeksPerYear]]); used when the age is known.
    public var severanceAgeBands: [Band] = []
    /// A flat part of severance in weeks on top of the per-year part (an indemnity of a number of months plus days a year), and an extra per-year premium.
    public var severanceBaseWeeks = 0.0
    public var severancePremiumPerYear = 0.0
    /// Years of service counted for severance (0 = all).
    public var severanceMaxYears = 0.0
    /// The termination reasons that earn severance, and the ones that earn notice (raw values of `TerminationReason`).
    public var severanceReasons: Set<String> = [TerminationReason.redundancy.rawValue, TerminationReason.unjustified.rawValue]
    public var noticeReasons: Set<String> = [TerminationReason.redundancy.rawValue, TerminationReason.unjustified.rawValue]
    /// A mandatory termination fund (share of pay paid in during service, employer cost paid through payroll) and the fine on that balance when
    /// the employer ends the job for the `fundFineReasons`: a one-off liability, not wages.
    public var fundRate = 0.0
    public var fundFineRate = 0.0
    public var fundFineReasons: Set<String> = [TerminationReason.redundancy.rawValue, TerminationReason.unjustified.rawValue]
    /// Notice (weeks) owed in a mass layoff where the country has such a law (0 = none); only applied when the caller says it is a mass layoff.
    public var massLayoffNoticeWeeks = 0.0
    /// Weeks before a fixed term ends by which the employer must say whether it will be renewed (0 = the game's default review time applies).
    public var fixedTermNoticeWeeks = 0.0
    /// The longest a person may be kept on successive fixed terms with the same employer, in weeks (0 = no limit in the data), and the most renewals
    /// of a fixed term (0 = no limit). Past either limit the contract becomes permanent. No country lists them until a statute is sourced.
    public var fixedTermMaxWeeks = 0.0
    public var fixedTermMaxRenewals = 0.0

    /// Statutory sick pay (`sick` in the data), per spell of illness: `waitingDays` at the start that nobody pays, then for up to `employerDays`
    /// working days the employer pays `employerShare` of normal pay (at most `weeklyCap` a week, in local currency, where the law sets a flat
    /// amount, e.g. the UK's SSP). After that the state pays `stateShare` of pay (information; it is not a cost to the company).
    public var sickWaitingDays = 0.0
    /// Without data the employer keeps paying in full, as before the rules existed.
    public var sickEmployerShare = 1.0
    public var sickEmployerDays = 260.0
    public var sickWeeklyCap = 0.0
    public var sickStateShare = 0.0

    public init() {}

    public init(code: String) {
        let j = CountryTraits.labour(code)
        guard !j.isNull else { return }
        func n(_ k: String, _ d: Double = 0) -> Double { j[k].isNull ? d : j[k].double }
        minMonthly = n("minMonthly"); statutory = j["statutory"].bool; stdHours = max(1, n("stdHours", 40)); overtimePremium = n("overtimePremium")
        noticeWeeks = n("noticeWeeks"); noticePerYear = n("noticePerYear"); noticeMax = n("noticeMax")
        severancePerYear = n("severancePerYear"); severanceMin = n("severanceMin"); severanceMax = n("severanceMax"); severanceAfterYears = n("severanceAfterYears")
        leaveDays = n("leaveDays"); leaveCalendarDays = j["leaveUnit"].string == "calendar"; probationWeeks = n("probationWeeks"); probationNoticeWeeks = n("probationNoticeWeeks"); atWill = j["atWill"].bool
        noticeBands = j["noticeBands"].array.map { Band(from: $0[0].double, value: $0[1].double) }.sorted { $0.from < $1.from }
        severanceTiers = j["severanceTiersMonths"].array.map { Band(from: $0[0].double, value: $0[1].double * 52 / 12) }.sorted { $0.from < $1.from }
        severanceAgeBands = j["severanceAgeBands"].array.map { Band(from: $0[0].double, value: $0[1].double) }.sorted { $0.from < $1.from }
        severanceBaseWeeks = n("severanceBaseWeeks"); severancePremiumPerYear = n("severancePremiumPerYear"); severanceMaxYears = n("severanceMaxYears")
        if !j["severanceReasons"].isNull { severanceReasons = Set(j["severanceReasons"].array.map { $0.string }) }
        if !j["noticeReasons"].isNull { noticeReasons = Set(j["noticeReasons"].array.map { $0.string }) }
        fundRate = n("fundRate"); fundFineRate = n("fundFineRate")
        if !j["fundFineReasons"].isNull { fundFineReasons = Set(j["fundFineReasons"].array.map { $0.string }) }
        massLayoffNoticeWeeks = n("massLayoffNoticeWeeks")
        fixedTermNoticeWeeks = n("fixedTermNoticeWeeks")
        fixedTermMaxWeeks = n("fixedTermMaxWeeks"); fixedTermMaxRenewals = n("fixedTermMaxRenewals")
        let sick = j["sick"]
        if !sick.isNull {
            sickWaitingDays = sick["waitingDays"].double; sickEmployerShare = sick["employerShare"].double; sickEmployerDays = sick["employerDays"].double
            sickWeeklyCap = sick["weeklyCap"].double; sickStateShare = sick["stateShare"].double
        }
    }

    // MARK: Sick pay

    /// What the employer pays for a week in which the person was sick `days` working days (before employer charges): the days after the waiting
    /// days, up to the employer's limit, at the employer's share of normal pay, with the flat weekly cap pro rata. `weeklyWage` and the cap's
    /// conversion `rate` (accounting units per local unit, times any price drift `capScale`) are in accounting units.
    public func employerSickPay(weeklyWage: Double, days: Double = 5, rate: Double = 1, capScale: Double = 1) -> Double {
        let paidDays = max(0, min(days - sickWaitingDays, sickEmployerDays))
        guard paidDays > 0 else { return 0 }
        var perWeek = weeklyWage * sickEmployerShare
        if sickWeeklyCap > 0 { perWeek = min(perWeek, sickWeeklyCap * rate * capScale) }
        return perWeek * paidDays / 5
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

    /// Why the job ends. Notice, severance and the termination fine are owed or not by reason (`severanceReasons`, `noticeReasons`,
    /// `fundFineReasons` in the country data): a dismissal for cause or a resignation owes nothing in most countries.
    public enum TerminationReason: String, Sendable { case redundancy, unjustified, forCause, resignation
        /// A fixed-term contract running out on its date. A country owes notice or severance for it only by listing "expiry" in `noticeReasons` / `severanceReasons`.
        case expiry }

    public struct Termination: Equatable, Sendable {
        public var noticeWeeks: Double
        public var severanceWeeks: Double
        /// The termination fund fine, in months of the person's pay (fine rate x fund rate x months served).
        public var fundFineMonths = 0.0
        public var weeks: Double { noticeWeeks + severanceWeeks }

        public init(noticeWeeks: Double, severanceWeeks: Double, fundFineMonths: Double = 0) {
            self.noticeWeeks = noticeWeeks; self.severanceWeeks = severanceWeeks; self.fundFineMonths = fundFineMonths
        }

        /// The separate one-off payments for a person on `monthlyWage` (accounting units): notice paid in lieu carries the employer's
        /// social charge like wages; severance and the fund fine do not.
        public func payments(monthlyWage: Double, employerSocial: Double) -> (notice: Double, severance: Double, fine: Double) {
            (monthlyWage * 12 / 52 * noticeWeeks * (1 + employerSocial), monthlyWage * 12 / 52 * severanceWeeks, monthlyWage * fundFineMonths)
        }

        public func cost(monthlyWage: Double, employerSocial: Double) -> Double {
            let p = payments(monthlyWage: monthlyWage, employerSocial: employerSocial)
            return p.notice + p.severance + p.fine
        }
    }

    /// Notice (paid in lieu), severance and any termination fine for letting someone go after `tenureWeeks`. The one place the game works this
    /// out for staff, layoffs and the manager. Whether each is owed depends on the reason and on service (and age, where the data uses it).
    public func termination(tenureWeeks: Double, withCause: Bool = false, onNotice: Bool = false, reason: TerminationReason? = nil,
                            age: Double? = nil, massLayoff: Bool = false) -> Termination {
        let why = reason ?? (withCause ? .forCause : .redundancy)
        if onNotice { return Termination(noticeWeeks: 0, severanceWeeks: 0) }
        let years = max(0, tenureWeeks) / 52
        let inProbation = tenureWeeks < probationWeeks
        // Notice
        var notice = 0.0
        if noticeReasons.contains(why.rawValue) {
            if !noticeBands.isEmpty {
                notice = noticeBands.last { years >= $0.from }?.value ?? 0
            } else if inProbation {
                notice = probationNoticeWeeks
            } else {
                notice = noticeWeeks + noticePerYear * years.rounded(.down)
            }
            if noticeMax > 0 { notice = min(notice, noticeMax) }
            if massLayoff { notice = max(notice, massLayoffNoticeWeeks) }
        }
        // Severance
        var sev = 0.0
        let hasSeverance = severancePerYear > 0 || severanceMin > 0 || !severanceTiers.isEmpty || severanceBaseWeeks > 0 || severancePremiumPerYear > 0
        if hasSeverance && !inProbation && severanceReasons.contains(why.rawValue) && years >= severanceAfterYears {
            let y = severanceMaxYears > 0 ? min(years, severanceMaxYears) : years
            var part = 0.0
            if !severanceTiers.isEmpty {
                for (i, t) in severanceTiers.enumerated() {
                    let upper = i + 1 < severanceTiers.count ? severanceTiers[i + 1].from : Double.infinity
                    part += max(0, min(y, upper) - t.from) * t.value
                }
            } else {
                var perYear = severancePerYear
                if let age, let band = severanceAgeBands.last(where: { age >= $0.from }) { perYear = band.value }
                part = perYear * y
            }
            sev = max(severanceMin, severanceBaseWeeks + part + severancePremiumPerYear * y)
            if severanceMax > 0 { sev = min(sev, severanceMax) }
        }
        // Termination fund fine
        var fine = 0.0
        if fundFineRate > 0 && fundRate > 0 && fundFineReasons.contains(why.rawValue) { fine = fundFineRate * fundRate * max(0, tenureWeeks) * 12 / 52 }
        return Termination(noticeWeeks: notice, severanceWeeks: sev, fundFineMonths: fine)
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
        out.append(("Notice", !noticeBands.isEmpty ? "\(w(noticeBands.first?.value ?? 0)) to \(w(noticeBands.last?.value ?? 0)) weeks by service" : noticeWeeks > 0 || noticePerYear > 0 ? "\(w(noticeWeeks)) weeks, +\(w(noticePerYear)) a year" : "None"))
        out.append(("Severance", !severanceTiers.isEmpty || severanceBaseWeeks > 0 ? "By service, only if not for cause" : severancePerYear > 0 ? "\(w(severancePerYear)) weeks a year" + (severanceAfterYears > 0 ? " after \(w(severanceAfterYears)) years" : "") : severanceMin > 0 ? "\(w(severanceMin)) weeks" : "None"))
        out.append(("Paid leave", leaveDays > 0 ? "\(w(leaveDays)) \(leaveCalendarDays ? "calendar" : "working") days" : "None"))
        out.append(("Sick pay", sickEmployerShare > 0 && sickEmployerDays > 0
                    ? "Employer pays \(Int((sickEmployerShare * 100).rounded()))% from day \(Int(sickWaitingDays) + 1)" + (sickWeeklyCap > 0 ? ", flat weekly rate" : "")
                    : sickStateShare > 0 ? "State insurance only" : "None"))
        out.append(("Probation", atWill ? "At will" : probationWeeks > 0 ? "\(w(probationWeeks)) weeks" : "None"))
        return out
    }
}
