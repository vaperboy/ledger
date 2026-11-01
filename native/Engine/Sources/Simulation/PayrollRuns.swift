import Foundation
import GameCore
import Countries
import Employees
import Finance
import Businesses

/// Payroll runs as records (Stage 2). Written by `Payday.runPayroll` (the existing payment engine: the cash leaves through it, nothing here moves money).
/// A run keeps its period, the payslip lines of everyone paid, what was paid and what was short. One run per period: a late completion of the same
/// period updates that run, it never makes a second one (duplicate-period prevention).
/// Lines are built from the contracts with the one employer-cost rule (`EmployerCost`). The cash paid is what payroll had accrued for the period
/// (weekly accrual, commission and bonus included), so `paid` can differ a little from `linesTotal`; both are shown.
public enum PayrollRuns {
    public static let keep = 36

    static func record(_ s: inout GameState, companyIndex i: Int, payMonth: Int, paid: Double, short: Double, how: String, today: Int, data: GameData, serviceFee: Double = 0) {
        let co = s.companies[i]
        let country = World(state: s, data: data).country(co)
        var lines: [JSONValue] = []
        func line(_ id: Int, _ name: String, _ role: String, _ kind: String, _ b: EmployerCost.Breakdown) -> JSONValue {
            .object(["id": .number(Double(id)), "n": .string(name), "r": .string(role), "k": .string(kind), "gross": .number(b.grossMonthlyWage), "ec": .number(b.employerTaxesAndContributions),
                     "ins": .number(b.insurance), "lv": .number(b.paidLeaveCover), "itx": .number(EmployerCost.deductions(wage: b.grossMonthlyWage, country: country).incomeTax), "esoc": .number(EmployerCost.deductions(wage: b.grossMonthlyWage, country: country).employeeSocial), "hrs": .number(b.expectedHoursPerMonth), "tot": .number(b.totalMonthly)])
        }
        for m in co.staff { lines.append(line(m.id, s.people[m.id]?.name ?? "Employee", m.role, "staff", EmployerCost.monthly(m, country: country))) }
        if let mid = co.managerID { lines.append(line(mid, s.people[mid]?.name ?? "Manager", "manager", "manager", EmployerCost.monthly(wage: co.managerMonthlyWage, country: country))) }
        if Payday.ownerOnPayroll(co) { lines.append(line(0, "You (owner)", "owner", "owner", EmployerCost.monthly(wage: co.ownerMonthlySalary, country: country))) }
        var runs = co.value("prun").array
        let total = lines.reduce(0) { $0 + $1["tot"].double }
        let acct = Payday.responsibility(co, state: s, data: data)
        if let k = runs.lastIndex(where: { $0["mi"].int == payMonth }) {
            runs[k]["paid"] = .number(runs[k]["paid"].double + paid)
            runs[k]["short"] = .number(short)
            if serviceFee > 0 { runs[k]["fee"] = .number(runs[k]["fee"].double + serviceFee) }
            runs[k]["w"] = .number(Double(s.week))
        } else {
            guard paid > 0 || short > 0 else { return }
            let n = co.int("prunN") + 1
            s.companies[i].set("prunN", n)
            runs.append(.object(["id": .number(Double(n)), "mi": .number(Double(payMonth)), "w": .number(Double(s.week)), "paid": .number(paid), "short": .number(short),
                                 "how": .string(how), "by": .string(acct.name), "fee": .number(serviceFee), "ln": .array(lines), "tot": .number(total)]))
        }
        if runs.count > keep { runs.removeFirst(runs.count - keep) }
        s.companies[i].set("prun", .array(runs))
    }
}
