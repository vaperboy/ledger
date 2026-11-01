import SwiftUI
import GameCore
import Countries
import Simulation

// Accounting > Payroll: Overview, Employees, Timesheets and Run payroll. Payroll administration lives here; the Bank holds the money and executes the
// payment, and the weekly simulation books the run. Running payroll from this screen is the existing payroll action (`runPayrollFromAccounting`),
// never a second one, so a period cannot be paid twice, and the responsible person is derived (qualified accountant, else a suitable manager, else you).

struct AcctPayroll: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            VStack(spacing: 0) {
                SectionTabs(items: AcctPayrollTab.allCases, title: { $0.rawValue }, selection: $m.payTab)
                    .padding(.top, 4)
                    .accessibilityIdentifier("acct-payroll-tabs")
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !e.canAccess(.payroll, companyID: co.id, user: m.user) {
                            AcctLocked(section: "Payroll")
                        } else {
                            tabContent(e, co)
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 40)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
                .swipeBetween(AcctPayrollTab.allCases, selection: $m.payTab)
            }
            .confirmAction($pending)
        }
    }

    @ViewBuilder private func tabContent(_ e: GameEngine, _ co: Company) -> some View {
        switch m.payTab {
        case .overview: overview(e, co)
        case .employees: employees(e, co)
        case .timesheets: timesheets(e, co)
        case .run: run(e, co)
        }
    }

    // MARK: Overview

    @ViewBuilder private func overview(_ e: GameEngine, _ co: Company) -> some View {
        let fmt = BankFmt(store: store, company: co)
        if let o = e.payrollOverview(companyID: co.id), let r = e.payrollRunReview(companyID: co.id, user: m.user) {
            if !o.hasPayroll {
                AcctNotice(glyph: Glyph.people, title: "No one is on the payroll",
                           message: "Payroll starts when you hire someone or pay yourself a salary. It is run from here.")
            } else {
                nextPayroll(o, r, fmt)
                responsibility(o)
            }
            recent(e, co, fmt)
        } else {
            AcctLocked(section: "Payroll")
        }
    }

    private func nextPayroll(_ o: PayrollOverview, _ r: PayrollRunReview, _ fmt: BankFmt) -> some View {
        let state: (String, AcctPill.Tone) = status(o, r)
        return AcctPanel(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Next payroll").font(.system(size: 14)).foregroundStyle(P.inkSoft)
                    Spacer(minLength: 8)
                    AcctPill(text: state.0, tone: state.1)
                }
                Text(r.payDateText).font(.serifTitle(24)).foregroundStyle(P.ink)
                AcctDivider()
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total cost").font(.system(size: 12)).foregroundStyle(P.inkFaint)
                        Text(fmt.full(r.totalEmployerCost)).font(.figure(24)).foregroundStyle(P.ink).minimumScaleFactor(0.6).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(r.lines.count.peopleText).font(.system(size: 13)).foregroundStyle(P.inkSoft)
                }
                AcctPrimaryButton(title: "Run payroll", identifier: "acct-payroll-run") { m.payTab = .run }
            }
        }
    }

    private func status(_ o: PayrollOverview, _ r: PayrollRunReview) -> (String, AcctPill.Tone) {
        if r.alreadyPaidForPeriod { return ("Paid", .good) }
        if o.isLate { return ("Late", .bad) }
        if o.needsApproval { return ("Needs you", .warn) }
        if o.isApproved { return ("Approved", .good) }
        return ("Ready", .good)
    }

    private func responsibility(_ o: PayrollOverview) -> some View {
        let who: String = o.responsibility?.name ?? "You"
        let why: String = o.responsibility?.reason ?? "No accountant or suitable manager: you approve each payroll yourself."
        return AcctNotice(glyph: Glyph.person, title: "Run by \(who)", message: why)
    }

    @ViewBuilder private func recent(_ e: GameEngine, _ co: Company, _ fmt: BankFmt) -> some View {
        let runs: [PayrollRunRecord] = e.payrollRuns(companyID: co.id, user: m.user) ?? []
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Recent payrolls")
            if runs.isEmpty {
                AcctNotice(glyph: Glyph.reports, title: "No payroll has been run yet", message: "Each run is recorded here with its payslips.")
            } else {
                AcctPanel {
                    ForEach(Array(runs.prefix(8).enumerated()), id: \.element.id) { n, run in
                        VStack(spacing: 0) {
                            if n > 0 { AcctDivider() }
                            runRow(run, fmt)
                        }
                    }
                }
            }
        }
    }

    private func runRow(_ run: PayrollRunRecord, _ fmt: BankFmt) -> some View {
        let isShort: Bool = run.short > 0.5
        let sub: String = run.dateText + " \u{00B7} " + run.lines.count.peopleText
        let tone: AcctPill.Tone = isShort ? .warn : .good
        return AcctRow(title: run.periodText, subtitle: sub, value: fmt.short(run.paid), pill: isShort ? "Short" : "Paid", pillTone: tone, identifier: "acct-payroll-run-row") { m.push(.payrollRun(run.id)) }
    }

    // MARK: Employees

    @ViewBuilder private func employees(_ e: GameEngine, _ co: Company) -> some View {
        let fmt = BankFmt(store: store, company: co)
        if let r = e.payrollRunReview(companyID: co.id, user: m.user) {
            if r.lines.isEmpty {
                AcctNotice(glyph: Glyph.people, title: "No employees", message: "People on the payroll are listed here with what each costs.")
            } else {
                AcctPanel {
                    ForEach(Array(r.lines.enumerated()), id: \.element.id) { n, line in
                        VStack(spacing: 0) {
                            if n > 0 { AcctDivider() }
                            employeeRow(line, fmt)
                        }
                    }
                }
                Text("Total employer cost per month: gross pay plus employer taxes and contributions, insurance and paid-leave cover.").font(.system(size: 11.5)).foregroundStyle(P.inkFaint).padding(.horizontal, 2)
            }
        } else {
            AcctLocked(section: "Payroll")
        }
    }

    private func employeeRow(_ line: PayslipLine, _ fmt: BankFmt) -> some View {
        let hours: String = String(format: "%.0f", line.hoursPerMonth)
        let sub: String = line.role.capitalized + " \u{00B7} " + hours + " h a month"
        let gross: String = "gross " + fmt.short(line.grossMonthly)
        return AcctRow(initials: AcctRow.initials(line.name), title: line.name, subtitle: sub, value: fmt.short(line.totalEmployerCost), valueNote: gross, identifier: "acct-employee-row")
    }

    // MARK: Timesheets

    @ViewBuilder private func timesheets(_ e: GameEngine, _ co: Company) -> some View {
        if let rows = e.timesheets(companyID: co.id, user: m.user) {
            if rows.isEmpty {
                AcctNotice(glyph: Glyph.calendar, title: "No timesheets", message: "Hours are tracked for employees on contracts. The owner and manager are salaried.")
            } else {
                AcctPanel {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { n, row in
                        VStack(spacing: 0) {
                            if n > 0 { AcctDivider() }
                            timesheetRow(row)
                        }
                    }
                }
                Text("This month. Hours come from the weekly simulation; sick weeks and the off-season are not counted as worked.").font(.system(size: 11.5)).foregroundStyle(P.inkFaint).padding(.horizontal, 2)
            }
        } else {
            AcctLocked(section: "Timesheets")
        }
    }

    private func timesheetRow(_ row: TimesheetRow) -> some View {
        let expected: String = String(format: "%.0f", row.expectedHoursInMonth) + " h"
        let actual: String = row.actualHoursRecorded.map { String(format: "%.0f", $0) + " h" } ?? "not yet"
        let weekly: String = String(format: "%.0f", row.contractedHoursPerWeek)
        let share: String = String(format: "%.0f", row.workingPercentage * 100)
        var sub: String = row.role.capitalized + " \u{00B7} " + weekly + " h a week, " + share + "%"
        if row.offSeason { sub += " \u{00B7} off-season" }
        if row.sickUntilWeek != nil { sub += " \u{00B7} off sick" }
        var note: String = "expected " + expected
        if row.overtimeHours > 0.4 {
            let over: String = String(format: "%.0f", row.overtimeHours)
            note += " \u{00B7} +" + over + " overtime"
        }
        return AcctRow(initials: AcctRow.initials(row.name), title: row.name, subtitle: sub, value: actual, valueNote: note, identifier: "acct-timesheet-row")
    }

    // MARK: Run payroll

    @ViewBuilder private func run(_ e: GameEngine, _ co: Company) -> some View {
        let fmt = BankFmt(store: store, company: co)
        if let o = e.payrollOverview(companyID: co.id), let r = e.payrollRunReview(companyID: co.id, user: m.user) {
            if !o.hasPayroll {
                AcctNotice(glyph: Glyph.people, title: "Nothing to run", message: "No one is on the payroll yet.")
            } else {
                reviewHeader(r)
                includedList(r, fmt)
                totals(r, fmt)
                funding(r, fmt)
                action(e, co, o, r, fmt)
            }
        } else {
            AcctLocked(section: "Payroll")
        }
    }

    private func reviewHeader(_ r: PayrollRunReview) -> some View {
        AcctPanel(padding: 14) {
            FlatRow(label: "Period", value: r.periodText, rule: false)
            FlatRow(label: "Pay date", value: r.payDateText)
            FlatRow(label: "Run by", value: r.responsibleName)
        }
    }

    private func includedList(_ r: PayrollRunReview, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Employees included (\(r.lines.count))")
            AcctPanel(padding: 14) {
                ForEach(Array(r.lines.enumerated()), id: \.element.id) { n, line in
                    FlatRow(label: line.name, value: fmt.short(line.grossMonthly), sub: line.role.capitalized, rule: n > 0)
                }
            }
        }
    }

    private func totals(_ r: PayrollRunReview, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "What it costs")
            AcctPanel(padding: 14) {
                FlatRow(label: "Gross wages", value: fmt.full(r.grossTotal), rule: false)
                FlatRow(label: "Employer taxes and contributions", value: fmt.full(r.employerContributions))
                if r.insurance > 0.5 { FlatRow(label: "Insurance", value: fmt.full(r.insurance)) }
                if r.paidLeaveCover > 0.5 { FlatRow(label: "Paid-leave cover", value: fmt.full(r.paidLeaveCover)) }
                if r.serviceFee > 0.5 { FlatRow(label: "Service fee (external accountant)", value: fmt.full(r.serviceFee), sub: "Booked as an accounting expense") }
                FlatRow(label: "Total employer cost", value: fmt.full(r.totalEmployerCost), tint: P.ink)
                Text(r.deductionsNote).font(.system(size: 11.5)).foregroundStyle(P.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
        }
    }

    private func funding(_ r: PayrollRunReview, _ fmt: BankFmt) -> some View {
        let enough: Bool = r.canCover
        return VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Payment")
            AcctPanel(padding: 14) {
                FlatRow(label: "Account charged", value: r.account, rule: false)
                FlatRow(label: "To pay on pay day", value: fmt.full(r.amountDue))
                FlatRow(label: "Available balance", value: fmt.full(r.availableBalance), tint: enough ? P.ink : P.loss)
                if !enough {
                    Text("The account does not cover this yet. Move money in through the Bank first, or part of the wages stays unpaid.").font(.system(size: 12.5)).foregroundStyle(P.caution)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                }
            }
        }
    }

    @ViewBuilder private func action(_ e: GameEngine, _ co: Company, _ o: PayrollOverview, _ r: PayrollRunReview, _ fmt: BankFmt) -> some View {
        let canRun: Bool = e.canAccess(.payroll, companyID: co.id, user: m.user)
        if r.alreadyPaidForPeriod {
            AcctNotice(glyph: Glyph.check, title: "Payroll for \(r.periodText) is already paid",
                       message: "A period is paid once. The next payroll opens after this pay day.", tint: P.gain)
            AcctPrimaryButton(title: "Already paid", enabled: false, identifier: "acct-payroll-confirm") {}
        } else if o.isLate {
            AcctNotice(glyph: Glyph.warning, title: "Payroll is late", message: o.lateReason + " Staff are waiting for their wages.", tint: P.loss)
            AcctPrimaryButton(title: "Pay late payroll now", enabled: canRun, identifier: "acct-payroll-confirm") { confirm(co, o, r, late: true) }
        } else if r.needsYourApproval {
            AcctPrimaryButton(title: "Approve payroll", enabled: canRun, identifier: "acct-payroll-confirm") { confirm(co, o, r, late: false) }
            Text("You are the one who approves it. Once approved it goes out from the account on the pay date.").font(.system(size: 12)).foregroundStyle(P.inkFaint).padding(.horizontal, 2)
        } else if o.isApproved {
            AcctNotice(glyph: Glyph.check, title: "Approved", message: "It goes out on \(r.payDateText).", tint: P.gain)
            AcctPrimaryButton(title: "Approved", enabled: false, identifier: "acct-payroll-confirm") {}
        } else {
            AcctNotice(glyph: Glyph.person, title: "Nothing to approve", message: "\(r.responsibleName) runs this payroll. It is paid automatically on \(r.payDateText).")
            AcctPrimaryButton(title: "Runs automatically", enabled: false, identifier: "acct-payroll-confirm") {}
        }
    }

    private func confirm(_ co: Company, _ o: PayrollOverview, _ r: PayrollRunReview, late: Bool) {
        let id: Int = co.id
        let fmt = BankFmt(store: store, company: co)
        let after: Double = r.availableBalance - r.amountDue
        let title: String = late ? "Pay late payroll now?" : "Approve payroll for \(r.periodText)?"
        var message: String = "\(fmt.short(r.amountDue)) is charged to \(r.account) for \(r.lines.count.peopleText) (employer cost \(fmt.short(r.totalEmployerCost)))."
        message += after >= 0 ? " About \(fmt.short(after)) is left." : " The account is short by \(fmt.short(-after)): part of the wages would stay unpaid."
        message += late ? " Paid today." : " It goes out on \(r.payDateText)."
        pending = PendingAction(title: title, message: message, button: late ? "Pay now" : "Approve", amount: r.amountDue, currency: store.engine.map { $0.currency(for: co) }) { runNow(id, r) }
    }

    private func runNow(_ id: Int, _ r: PayrollRunReview) {
        let user: String? = m.user
        let co: Company? = store.engine?.state.company(id)
        let fmt = BankFmt(store: store, company: co)
        let outcome: PayrollAlertOutcome? = store.act({ (e: inout GameEngine) -> PayrollAlertOutcome in e.runPayrollFromAccounting(companyID: id, user: user) })
        switch outcome {
        case .approved?:
            Haptics.success()
            store.show("Payroll approved: about \(fmt.short(r.amountDue)) goes out on \(r.payDateText).", tone: "good")
        case .paidLate(let paid, let short)?:
            if short > 0.5 {
                Haptics.warning()
                store.show("Paid \(fmt.short(paid)). Still short \(fmt.short(short)): put money into the company and run it again.", tone: "warn")
            } else {
                Haptics.success()
                store.show("Late payroll paid: \(fmt.short(paid)).", tone: "good")
            }
            if let run = store.engine?.payrollRuns(companyID: id, user: user)?.first { m.push(.payrollRun(run.id)) }
        case .notNeeded(let why)?:
            Haptics.warning()
            store.show(why, tone: "warn")
        case nil:
            break
        }
    }
}

// MARK: Run details

/// One payroll run as it was paid: the result, the total, the breakdown and the payslips.
struct AcctPayrollRunDetail: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel
    var runID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            let fmt = BankFmt(store: store, company: co)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let runs = e.payrollRuns(companyID: co.id, user: m.user) {
                        if let run = runs.first(where: { $0.id == runID }) {
                            result(run, fmt)
                            breakdown(run, fmt)
                            payslips(run, fmt)
                        } else {
                            AcctNotice(glyph: Glyph.info, title: "This run is no longer kept", message: "The Accounting records keep the last runs only.")
                        }
                    } else {
                        AcctLocked(section: "Payroll")
                    }
                }
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 40)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        }
    }

    private func result(_ run: PayrollRunRecord, _ fmt: BankFmt) -> some View {
        let short: Bool = run.short > 0.5
        return AcctPanel(padding: 18) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill((short ? P.caution : P.gain).opacity(0.14)).frame(width: 56, height: 56)
                    GlyphView(glyph: short ? Glyph.warning : Glyph.check, size: 26, weight: 2, tint: short ? P.caution : P.gain)
                }
                Text(short ? "Payroll part paid" : "Payroll processed").font(.serifTitle(21)).foregroundStyle(P.ink)
                Text(short ? "\(fmt.short(run.short)) is still unpaid." : "All employees have been paid.").font(.system(size: 13)).foregroundStyle(P.inkSoft)
                AcctDivider()
                FlatRow(label: "Total cost", value: fmt.full(run.linesTotal), rule: false)
                FlatRow(label: "Paid", value: fmt.full(run.paid), tint: short ? P.caution : P.ink)
                FlatRow(label: "Employees", value: "\(run.lines.count)")
                FlatRow(label: "Payment date", value: run.dateText)
                FlatRow(label: "Run by", value: run.runBy)
                AcctSecondaryButton(title: "View transaction", identifier: "acct-run-transaction") {
                    m.txSearch = "Payroll"
                    m.txKind = .all
                    m.txRange = .quarter
                    m.push(.transactions)
                }
                .padding(.top, 8)
            }
        }
    }

    private func breakdown(_ run: PayrollRunRecord, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Breakdown")
            AcctPanel(padding: 14) {
                FlatRow(label: "Salaries (gross)", value: fmt.full(run.grossTotal), rule: false)
                FlatRow(label: "Employer taxes and contributions", value: fmt.full(run.employerCostsTotal))
                if run.serviceFee > 0.5 { FlatRow(label: "Service fee", value: fmt.full(run.serviceFee)) }
            }
        }
    }

    private func payslipRow(_ line: PayslipLine, _ fmt: BankFmt) -> some View {
        let withheld: Double = line.incomeTaxWithheld + line.employeeSocialWithheld
        let gross: String = fmt.short(line.grossMonthly)
        let tax: String = fmt.short(withheld)
        let sub: String = "Gross " + gross + " \u{00B7} tax withheld " + tax
        return AcctRow(initials: AcctRow.initials(line.name), title: line.name, subtitle: sub, value: fmt.short(line.netPay), valueNote: "net pay", identifier: "acct-payslip-row")
    }

    private func payslips(_ run: PayrollRunRecord, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctLabel(text: "Payslips")
            AcctPanel {
                ForEach(Array(run.lines.enumerated()), id: \.element.id) { n, line in
                    VStack(spacing: 0) {
                        if n > 0 { AcctDivider() }
                        payslipRow(line, fmt)
                    }
                }
            }
        }
    }
}
