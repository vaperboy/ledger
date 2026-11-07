import SwiftUI
import GameCore
import Countries
import Simulation

// Accounting > Payroll: Overview, Employees, Timesheets and Run payroll. Payroll administration lives here, pay day included; the Bank holds the
// money, executes the payment and links here, and the weekly simulation books the run. Running payroll from this screen is the existing payroll action (`runPayrollFromAccounting`),
// never a second one, so a period cannot be paid twice, and the responsible person is derived (qualified accountant, else a suitable manager, else you).

struct AcctPayroll: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            VStack(spacing: 0) {
                SectionTabs(items: AcctPayrollTab.allCases, title: { $0.rawValue }, selection: $m.payTab,
                            dots: { (t: AcctPayrollTab) -> Bool in t == .run && PhoneAlerts.payroll(engine: e).contains { (p: PayrollAlertInfo) -> Bool in p.companyID == co.id } }, urgent: true)
                    .padding(.top, 4)
                    .accessibilityIdentifier("acct-payroll-tabs")
                SegmentPager(items: AcctPayrollTab.allCases, selection: $m.payTab) { (t: AcctPayrollTab) in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.xl) {
                            if !e.canAccess(.payroll, companyID: co.id, user: m.user) {
                                AcctLocked(section: "Payroll")
                            } else {
                                tabContent(e, co, t)
                            }
                        }
                        .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xl)
                        .frame(maxWidth: 560).frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
                }
            }
            .moneyPopups { $0.confirmAction($pending) }
        }
    }

    @ViewBuilder private func tabContent(_ e: GameEngine, _ co: Company, _ t: AcctPayrollTab) -> some View {
        switch t {
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
                payday(co, o, fmt)
                AcctPayday(engine: e, company: co)
                who(co, o, fmt)
                CompanyPeopleCost(engine: e, company: co)
            }
            recent(e, co, fmt)
        } else {
            AcctLocked(section: "Payroll")
        }
    }

    /// The next payroll leads: its total cost, the date and headcount under it with the status, then Run payroll.
    private func nextPayroll(_ o: PayrollOverview, _ r: PayrollRunReview, _ fmt: BankFmt) -> some View {
        let state: (String, AcctPill.Tone) = status(o, r)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                MoneyHero(label: "Next payroll", value: fmt.full(r.totalEmployerCost), context: r.payDateText + " \u{00B7} " + r.lines.count.peopleText)
                AcctPill(text: state.0, tone: state.1)
            }
            AcctPrimaryButton(title: "Run payroll", identifier: "acct-payroll-run") { m.payTab = .run }
        }
    }

    private func status(_ o: PayrollOverview, _ r: PayrollRunReview) -> (String, AcctPill.Tone) {
        if r.alreadyPaidForPeriod { return ("Paid", .good) }
        if o.isLate { return ("Late", .bad) }
        if o.needsApproval { return ("Needs you", .warn) }
        if o.isApproved { return ("Approved", .good) }
        return ("Ready", .good)
    }

    // MARK: Pay day

    /// Cash against what pay day needs. The pay date and the total are in the panel above, so they are not repeated here.
    private func payday(_ co: Company, _ o: PayrollOverview, _ fmt: BankFmt) -> some View {
        let notCovered: Bool = o.companyCash < o.estimate
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            AcctFlat(padding: 14) {
                FlatRow(label: "Company cash", value: fmt.full(o.companyCash), sub: "Expected by pay day: " + fmt.full(o.estimate), tint: notCovered ? P.loss : P.ink, rule: false)
                FlatRow(label: "Wages owed now", value: fmt.full(o.wagesOwed), sub: "Booked, not yet paid out")
                FlatRow(label: "Approval", value: approvalText(o), sub: approvalNote(o))
            }
            paydayWarning(co, o, notCovered, fmt)
        }
    }

    @ViewBuilder private func paydayWarning(_ co: Company, _ o: PayrollOverview, _ notCovered: Bool, _ fmt: BankFmt) -> some View {
        if o.wageShortfall > 0.5 || notCovered {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                if o.wageShortfall > 0.5 {
                    AcctNotice(glyph: Glyph.warning, title: "Wages short by \(fmt.short(o.wageShortfall))",
                               message: "The last payroll could not be paid in full. Move money into the company, then pay it from Run payroll.", tint: P.loss)
                } else {
                    AcctNotice(glyph: Glyph.warning, title: "Cash does not cover the next payroll yet",
                               message: "Put in \(fmt.short(o.estimate - o.companyCash)) more before pay day, or part of the wages stays unpaid.", tint: P.caution)
                }
                Button("Move money in the Bank") { store.openBank(.company(co.id)) }
                    .buttonStyle(TertiaryButtonStyle(size: .compact))
                    .accessibilityIdentifier("acct-payroll-move-money")
            }
        }
    }

    private func approvalText(_ o: PayrollOverview) -> String {
        if o.mode != .manual { return "Run by " + (o.responsibility?.name ?? "someone else") }
        return o.autoApproves ? "Approved for you" : "You approve it"
    }

    private func approvalNote(_ o: PayrollOverview) -> String {
        if o.mode != .manual { return "Nothing to approve" }
        return o.autoApproves ? "Your standing rule covers routine payroll" : "Use Run payroll before pay day"
    }

    // MARK: Who runs payroll

    private func who(_ co: Company, _ o: PayrollOverview, _ fmt: BankFmt) -> some View {
        let name: String = o.responsibility?.name ?? "You"
        let why: String = o.responsibility?.reason ?? "No accountant or suitable manager: you approve each payroll yourself."
        return VStack(alignment: .leading, spacing: 8) {
            AcctCaps(text: "Who runs payroll")
            AcctNotice(glyph: Glyph.person, title: "Run by \(name)", message: why)
            if !o.modeIsFixed {
                AcctFlat {
                    ForEach(Array(o.choices.enumerated()), id: \.element.id) { n, c in
                        VStack(spacing: 0) {
                            if n > 0 { AcctDivider() }
                            choiceRow(co, o, c, fmt)
                        }
                    }
                }
                Text("It follows from who is on the team: an accountant first, then a manager, otherwise you.").textStyle(.caption, tint: P.inkFaint).padding(.horizontal, 2)
            }
        }
    }

    private func choiceRow(_ co: Company, _ o: PayrollOverview, _ c: PayrollModeChoice, _ fmt: BankFmt) -> some View {
        let id: Int = co.id
        let fee: String = c.monthlyFee > 0.5 ? fmt.short(c.monthlyFee) + " a month" : "No extra fee"
        var title: String = "You"
        var note: String = "You approve each payroll yourself."
        var go: (() -> Void)? = nil
        switch c.mode {
        case .manual:
            break
        case .accountant, .inHouse:
            title = "Accountant"
            note = o.responsibility?.who == .accountant ? (o.responsibility?.name ?? "") + " runs it." : "Appoint an accountant in Atlas to hand payroll over."
            go = { store.openAtlas(companyID: id) }
        case .manager:
            title = "Manager"
            note = "A manager who decides on their own runs it at no extra fee."
            go = { store.openGroupEntity(companyID: id, section: "management") }
        }
        if let why = c.unavailable { note = why }
        return AcctLine(title: title, subtitle: note, value: fee, pill: c.isCurrent ? "Now" : nil, pillTone: .good, identifier: "acct-payroll-who-" + c.mode.rawValue, action: go)
    }

    @ViewBuilder private func recent(_ e: GameEngine, _ co: Company, _ fmt: BankFmt) -> some View {
        let runs: [PayrollRunRecord] = e.payrollRuns(companyID: co.id, user: m.user) ?? []
        VStack(alignment: .leading, spacing: 8) {
            AcctCaps(text: "Recent payrolls")
            if runs.isEmpty {
                AcctNotice(glyph: Glyph.reports, title: "No payroll has been run yet", message: "Each run is recorded here with its payslips.")
            } else {
                AcctFlat {
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
        return AcctLine(title: run.periodText, subtitle: sub, value: fmt.short(run.paid), pill: isShort ? "Short" : "Paid", pillTone: tone, identifier: "acct-payroll-run-row") { m.push(.payrollRun(run.id)) }
    }

    // MARK: Employees

    @ViewBuilder private func employees(_ e: GameEngine, _ co: Company) -> some View {
        let fmt = BankFmt(store: store, company: co)
        if let r = e.payrollRunReview(companyID: co.id, user: m.user) {
            if r.lines.isEmpty {
                AcctNotice(glyph: Glyph.people, title: "No employees", message: "People on the payroll are listed here with what each costs.")
            } else {
                AcctFlat {
                    ForEach(Array(r.lines.enumerated()), id: \.element.id) { n, line in
                        VStack(spacing: 0) {
                            if n > 0 { AcctDivider() }
                            employeeRow(line, fmt)
                        }
                    }
                }
            }
        } else {
            AcctLocked(section: "Payroll")
        }
    }

    private func employeeRow(_ line: PayslipLine, _ fmt: BankFmt) -> some View {
        let hours: String = String(format: "%.0f", line.hoursPerMonth)
        let sub: String = line.role.capitalized + " \u{00B7} " + hours + " h a month"
        let gross: String = "gross " + fmt.short(line.grossMonthly)
        return AcctLine(initials: AcctRow.initials(line.name), title: line.name, subtitle: sub, value: fmt.short(line.totalEmployerCost), valueNote: gross, identifier: "acct-employee-row")
    }

    // MARK: Timesheets

    @ViewBuilder private func timesheets(_ e: GameEngine, _ co: Company) -> some View {
        if let rows = e.timesheets(companyID: co.id, user: m.user) {
            if rows.isEmpty {
                AcctNotice(glyph: Glyph.calendar, title: "No timesheets", message: "Hours are tracked for employees on contracts. The owner and manager are salaried.")
            } else {
                AcctFlat {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { n, row in
                        VStack(spacing: 0) {
                            if n > 0 { AcctDivider() }
                            timesheetRow(row)
                        }
                    }
                }
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
        return AcctLine(initials: AcctRow.initials(row.name), title: row.name, subtitle: sub, value: actual, valueNote: note, identifier: "acct-timesheet-row")
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
        AcctFlat(padding: 14) {
            FlatRow(label: "Period", value: r.periodText, rule: false)
            FlatRow(label: "Pay date", value: r.payDateText)
            FlatRow(label: "Run by", value: r.responsibleName)
        }
    }

    private func includedList(_ r: PayrollRunReview, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctCaps(text: "Employees included (\(r.lines.count))")
            AcctFlat(padding: 14) {
                ForEach(Array(r.lines.enumerated()), id: \.element.id) { n, line in
                    FlatRow(label: line.name, value: fmt.short(line.grossMonthly), sub: line.role.capitalized, rule: n > 0)
                }
            }
        }
    }

    private func totals(_ r: PayrollRunReview, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctCaps(text: "What it costs")
            AcctFlat(padding: 14) {
                FlatRow(label: "Gross wages", value: fmt.full(r.grossTotal), rule: false)
                FlatRow(label: "Employer taxes and contributions", value: fmt.full(r.employerContributions))
                if r.insurance > 0.5 { FlatRow(label: "Insurance", value: fmt.full(r.insurance)) }
                if r.paidLeaveCover > 0.5 { FlatRow(label: "Paid-leave cover", value: fmt.full(r.paidLeaveCover)) }
                if r.serviceFee > 0.5 { FlatRow(label: "Service fee (external accountant)", value: fmt.full(r.serviceFee), sub: "Booked as an accounting expense") }
                FlatRow(label: "Total employer cost", value: fmt.full(r.totalEmployerCost), tint: P.ink)
                Text(r.deductionsNote).textStyle(.caption, tint: P.inkFaint).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
        }
    }

    private func funding(_ r: PayrollRunReview, _ fmt: BankFmt) -> some View {
        let enough: Bool = r.canCover
        return VStack(alignment: .leading, spacing: 8) {
            AcctCaps(text: "Payment")
            AcctFlat(padding: 14) {
                FlatRow(label: "Account charged", value: r.account, rule: false)
                FlatRow(label: "To pay on pay day", value: fmt.full(r.amountDue))
                FlatRow(label: "Available balance", value: fmt.full(r.availableBalance), tint: enough ? P.ink : P.loss)
                if !enough {
                    Text("The account does not cover this yet. Move money in through the Bank first, or part of the wages stays unpaid.").textStyle(.caption, tint: P.caution)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                    Button("Move money in the Bank") { store.openBank(.company(m.companyID)) }
                        .buttonStyle(SecondaryButtonStyle(size: .compact)).padding(.top, Theme.Space.xs)
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
            Text("You are the one who approves it. Once approved it goes out from the account on the pay date.").textStyle(.caption, tint: P.inkFaint).padding(.horizontal, 2)
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
        pending = PendingAction(title: title, message: message, button: late ? "Pay now" : "Approve", amount: r.amountDue, currency: store.engine.map { $0.currency(for: co) }, tone: .warning, icon: "person.2") { runNow(id, r) }
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
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
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
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        }
    }

    private func result(_ run: PayrollRunRecord, _ fmt: BankFmt) -> some View {
        let short: Bool = run.short > 0.5
        return AcctFlat(padding: 18) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill((short ? P.caution : P.gain).opacity(0.14)).frame(width: 56, height: 56)
                    GlyphView(glyph: short ? Glyph.warning : Glyph.check, size: 26, weight: 2, tint: short ? P.caution : P.gain)
                }
                Text(short ? "Payroll part paid" : "Payroll processed").textStyle(.figure)
                Text(short ? "\(fmt.short(run.short)) is still unpaid." : "All employees have been paid.").textStyle(.body, tint: P.inkSoft)
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
            AcctCaps(text: "Breakdown")
            AcctFlat(padding: 14) {
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
        return AcctLine(initials: AcctRow.initials(line.name), title: line.name, subtitle: sub, value: fmt.short(line.netPay), valueNote: "net pay", identifier: "acct-payslip-row")
    }

    private func payslips(_ run: PayrollRunRecord, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctCaps(text: "Payslips")
            AcctFlat {
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

// MARK: Pay day

/// The company's pay day, set here with the rest of payroll (the Bank links to it): the choices, when staff are next paid and when rent
/// and supplier bills follow. The engine's `setPayday` applies a change now, or after this month's payroll when that is still unpaid.
struct AcctPayday: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var engine: GameEngine
    var company: Company

    var body: some View {
        if let info = engine.paydayInfo(companyID: company.id), info.hasPayroll {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(alignment: .firstTextBaseline) {
                    AcctCaps(text: "Pay day")
                    Spacer(minLength: Theme.Space.s)
                    Text(info.dayLabel).textStyle(.caption, tint: P.inkFaint)
                }
                AcctFlat {
                    ForEach(Array(info.choices.enumerated()), id: \.element.id) { (n: Int, c: PaydayChoice) in
                        VStack(spacing: 0) {
                            if n > 0 { AcctDivider() }
                            LedgerRow(title: c.label, subtitle: timing(c, info), pill: c.isCurrent ? "Current" : (c.isQueued ? "Queued" : nil), pillTone: .good,
                                      chevron: false, inset: 14, identifier: "acct-payday-\(c.day)", action: { choose(c, info) })
                        }
                    }
                }
                Text(summary(info)).textStyle(.caption, tint: info.isLate ? P.loss : (info.pendingLabel != nil ? P.caution : P.inkFaint))
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, Theme.Space.xxs)
            }
        }
    }

    private func summary(_ info: PaydayInfo) -> String {
        if info.isLate { return "Wages are late, so a change waits until they are paid." }
        if let q = info.pendingLabel { return "Changing to the \(q.lowercased()) after this month's payroll is paid. Staff need notice." }
        return "Staff are next paid on \(info.nextPayText); rent and supplier bills follow on \(info.billText). A weekend pay day is paid the Friday before."
    }

    private func timing(_ c: PaydayChoice, _ info: PaydayInfo) -> String {
        let gap: String = c.daysBeforeBills <= 0 ? "the same day as rent and bills" : "\(c.daysBeforeBills) days before rent and bills"
        return (info.changesImmediately ? "First paid " : "Then paid ") + c.firstPayText + ", " + gap
    }

    private func choose(_ c: PaydayChoice, _ info: PaydayInfo) {
        guard !c.isCurrent || info.pendingDay != nil else { return }
        let name: String = c.label.lowercased()
        let current: String = info.dayLabel.lowercased()
        let nextPay: String = info.nextPayText
        let first: String = c.firstPayText
        let id: Int = company.id
        let day: Int = c.day
        switch store.act({ $0.setPayday(companyID: id, day: day) }) {
        case .changedNow?: Haptics.success(); store.show("Pay day is now the \(name). First paid \(first).", tone: "good")
        case .queued?: Haptics.success(); store.show("Pay day moves to the \(name) after this month's payroll (\(nextPay)).", tone: "good")
        case .queueCleared?: Haptics.tap(); store.show("The waiting change was dropped. Pay day stays the \(current).", tone: "n")
        case .unchanged?: store.show("That is already the pay day.", tone: "n")
        case nil: break
        default: Haptics.warning(); store.show("The pay day could not be changed.", tone: "warn")
        }
    }
}
