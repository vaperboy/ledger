import Foundation
import GameCore
import Countries

public struct LabourRules: Equatable, Sendable {
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
    public var leaveDays = 0.0
    public var leaveCalendarDays = false
    public var leaveWeeks: Double { leaveDays / (leaveCalendarDays ? 7 : 5) }
    public var probationWeeks = 0.0
    public var probationNoticeWeeks = 0.0
    public var atWill = false
    public var noticeBands: [Band] = []
    public var severanceTiers: [Band] = []
    public var severanceBaseWeeks = 0.0
    public var severancePremiumPerYear = 0.0
    public var severanceMaxYears = 0.0
    public var severanceReasons: Set<String> = [TerminationReason.redundancy.rawValue, TerminationReason.unjustified.rawValue]
    public var noticeReasons: Set<String> = [TerminationReason.redundancy.rawValue, TerminationReason.unjustified.rawValue]
    public var fundRate = 0.0
    public var fundFineRate = 0.0
    public var fundFineReasons: Set<String> = [TerminationReason.redundancy.rawValue, TerminationReason.unjustified.rawValue]
    public var massLayoffNoticeWeeks = 0.0
    public var fixedTermNoticeWeeks = 0.0
    public var fixedTermMaxWeeks = 0.0
    public var fixedTermMaxRenewals = 0.0

    public var sickWaitingDays = 0.0
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

    public func employerSickPay(weeklyWage: Double, days: Double = 5, rate: Double = 1, capScale: Double = 1) -> Double {
        let paidDays = max(0, min(days - sickWaitingDays, sickEmployerDays))
        guard paidDays > 0 else { return 0 }
        var perWeek = weeklyWage * sickEmployerShare
        if sickWeeklyCap > 0 { perWeek = min(perWeek, sickWeeklyCap * rate * capScale) }
        return perWeek * paidDays / 5
    }

    public init(country: Country) { self.init(code: country.code) }

    public var hasMinimum: Bool { minMonthly > 0 }

    public func minimumMonthly(hours: Double, rate: Double, inflationIndex: Double) -> Double {
        guard hasMinimum else { return 0 }
        return minMonthly * rate * inflationIndex * max(0, hours) / stdHours
    }

    public func overtimeThreshold(contracted: Double) -> Double { max(stdHours, min(contracted, StaffModel.fullWeekHours)) }

    public func overtimeHours(worked: Double, contracted: Double) -> Double { max(0, worked - overtimeThreshold(contracted: contracted)) }

    public func overtimePay(monthlyWage: Double, contracted: Double, worked: Double) -> Double {
        let h = max(1, contracted)
        return monthlyWage * 12 / 52 / h * overtimeHours(worked: worked, contracted: contracted) * (1 + overtimePremium)
    }

    public func tirednessThreshold(contracted: Double) -> Double { min(40, overtimeThreshold(contracted: contracted)) }

    public enum TerminationReason: String, Sendable { case redundancy, unjustified, forCause, resignation
        case expiry }

    public struct Termination: Equatable, Sendable {
        public var noticeWeeks: Double
        public var severanceWeeks: Double
        public var fundFineMonths = 0.0
        public var weeks: Double { noticeWeeks + severanceWeeks }

        public init(noticeWeeks: Double, severanceWeeks: Double, fundFineMonths: Double = 0) {
            self.noticeWeeks = noticeWeeks; self.severanceWeeks = severanceWeeks; self.fundFineMonths = fundFineMonths
        }

        public func payments(monthlyWage: Double, employerSocial: Double) -> (notice: Double, severance: Double, fine: Double) {
            (monthlyWage * 12 / 52 * noticeWeeks * (1 + employerSocial), monthlyWage * 12 / 52 * severanceWeeks, monthlyWage * fundFineMonths)
        }

        public func cost(monthlyWage: Double, employerSocial: Double) -> Double {
            let p = payments(monthlyWage: monthlyWage, employerSocial: employerSocial)
            return p.notice + p.severance + p.fine
        }
    }

    public func termination(tenureWeeks: Double, withCause: Bool = false, onNotice: Bool = false, reason: TerminationReason? = nil,
                            massLayoff: Bool = false) -> Termination {
        let why = reason ?? (withCause ? .forCause : .redundancy)
        if onNotice { return Termination(noticeWeeks: 0, severanceWeeks: 0) }
        let years = max(0, tenureWeeks) / 52
        let inProbation = tenureWeeks < probationWeeks
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
                part = severancePerYear * y
            }
            sev = max(severanceMin, severanceBaseWeeks + part + severancePremiumPerYear * y)
            if severanceMax > 0 { sev = min(sev, severanceMax) }
        }
        var fine = 0.0
        if fundFineRate > 0 && fundRate > 0 && fundFineReasons.contains(why.rawValue) { fine = fundFineRate * fundRate * max(0, tenureWeeks) * 12 / 52 }
        return Termination(noticeWeeks: notice, severanceWeeks: sev, fundFineMonths: fine)
    }

    public func canClaimUnfairDismissal(tenureWeeks: Double) -> Bool { !atWill && tenureWeeks >= probationWeeks }

    public func summary(currency: Currency) -> [(label: String, value: String)] {
        func w(_ x: Double) -> String { x == x.rounded() ? "\(Int(x))" : String(format: "%.1f", x) }
        var out: [(label: String, value: String)] = []
        out.append(("Minimum wage", hasMinimum ? "\(currency.country.currencySymbol) \(Int(saturating: minMonthly.rounded())) a month" + (statutory ? "" : " (agreements)") : "None"))
        out.append(("Standard week", "\(w(stdHours)) h"))
        out.append(("Overtime", overtimePremium > 0 ? "+\(Int(saturating: (overtimePremium * 100).rounded()))%" : "Basic rate"))
        out.append(("Notice", !noticeBands.isEmpty ? "\(w(noticeBands.first?.value ?? 0)) to \(w(noticeBands.last?.value ?? 0)) weeks by service" : noticeWeeks > 0 || noticePerYear > 0 ? "\(w(noticeWeeks)) weeks, +\(w(noticePerYear)) a year" : "None"))
        out.append(("Severance", !severanceTiers.isEmpty || severanceBaseWeeks > 0 ? "By service, only if not for cause" : severancePerYear > 0 ? "\(w(severancePerYear)) weeks a year" + (severanceAfterYears > 0 ? " after \(w(severanceAfterYears)) years" : "") : severanceMin > 0 ? "\(w(severanceMin)) weeks" : "None"))
        out.append(("Paid leave", leaveDays > 0 ? "\(w(leaveDays)) \(leaveCalendarDays ? "calendar" : "working") days" : "None"))
        out.append(("Sick pay", sickEmployerShare > 0 && sickEmployerDays > 0
                    ? "Employer pays \(Int(saturating: (sickEmployerShare * 100).rounded()))% from day \(Int(sickWaitingDays) + 1)" + (sickWeeklyCap > 0 ? ", flat weekly rate" : "")
                    : sickStateShare > 0 ? "State insurance only" : "None"))
        out.append(("Probation", atWill ? "At will" : probationWeeks > 0 ? "\(w(probationWeeks)) weeks" : "None"))
        return out
    }
}
