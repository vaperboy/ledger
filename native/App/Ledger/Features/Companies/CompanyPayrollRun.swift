import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Who runs the company's payroll, and the owner's part in it: approving the coming pay day and running a late payroll. Sits above the
/// pay day choice in Finances > Payroll and bills. The same approval is also asked in the Inbox; both call the same engine step.
struct CompanyPayrollRun: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var pending: PendingAction?

    var body: some View {
        if let o = engine.payrollOverview(companyID: company.id) {
            let cur = engine.currency(for: company)
            LedgerSection(title: "Payroll run", trailing: { Text(modeName(o.mode)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    if !o.hasPayroll {
                        Text("No one is on the payroll yet, so there is nothing to run. This appears once you hire someone.")
                            .font(.system(size: 13)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    } else {
                        status(o, cur)
                        if o.isLate {
                            Text(o.lateReason + " Staff are waiting; unpaid wages lead to resignations and a wage claim.").font(.system(size: 12.5)).foregroundStyle(Theme.loss).fixedSize(horizontal: false, vertical: true)
                            Button("Run payroll now") { runNow(o, cur) }.buttonStyle(QuietButtonStyle())
                        } else if o.needsApproval {
                            Button("Approve this month's payroll") { approve(o, cur) }.buttonStyle(GoldButtonStyle())
                        }
                    }
                    Hairline().padding(.vertical, 4)
                    Text("Who runs payroll").font(.caption).foregroundStyle(Theme.ivoryMuted)
                    if o.modeIsFixed {
                        Text("This kind of company runs its own payroll in-house. Nothing to choose.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                    } else {
                        ForEach(o.choices) { c in
                            Button { choose(c, o, cur) } label: {
                                ListRow(symbol: c.isCurrent ? "checkmark.circle.fill" : (c.unavailable != nil ? "lock" : "circle"),
                                        tint: c.isCurrent ? Theme.gold : Theme.ivoryMuted, title: modeName(c.mode),
                                        subtitle: c.unavailable ?? describe(c.mode, c.monthlyFee, cur),
                                        trailing: c.monthlyFee > 0 ? cur.tidyShort(c.monthlyFee) : "No fee", trailingSub: c.monthlyFee > 0 ? "a month" : "")
                            }.buttonStyle(.plain).disabled(c.unavailable != nil)
                        }
                        Text("A change applies from the next pay day. The accountant's fee is per payslip; the manager's payroll software has a monthly fee and now and then misses a step, paying a day or two late.")
                            .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .confirmAction($pending)
        }
    }

    @ViewBuilder private func status(_ o: PayrollOverview, _ cur: Currency) -> some View {
        KeyFigures(items: [
            .init(label: "Next pay day", value: o.nextPayText, sub: "\(o.payslips) \(o.payslips == 1 ? "payslip" : "payslips")"),
            .init(label: "About to pay", value: cur.tidyShort(o.estimate), tint: o.estimate > max(0, o.companyCash) ? Theme.loss : Theme.ivory, sub: "with employer costs"),
            .init(label: "Company cash", value: cur.tidyShort(o.companyCash), tint: o.companyCash < o.estimate ? Theme.caution : Theme.ivory)
        ])
        if o.mode == .manual && !o.isLate {
            if o.isApproved { Text("Approved. It goes out on pay day.").font(.system(size: 12.5)).foregroundStyle(Theme.gain) }
            else if o.autoApproves && o.companyCash >= o.estimate { Text("Your standing rule approves routine payroll the company can pay, so this goes out without asking.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryMuted) }
            else if o.needsApproval { Text("Waiting for you. If it is not approved by pay day, staff are not paid.").font(.system(size: 12.5)).foregroundStyle(Theme.caution) }
        }
    }

    private func modeName(_ m: Payday.Mode) -> String {
        switch m { case .manual: return "You approve it"; case .accountant: return "The accountant"; case .manager: return "The manager"; case .inHouse: return "In-house" }
    }

    private func describe(_ m: Payday.Mode, _ fee: Double, _ cur: Currency) -> String {
        switch m {
        case .manual: return "No fee. You approve each month; if you forget, staff are not paid on pay day."
        case .accountant: return "Paid automatically on pay day. The accountant charges per payslip."
        case .manager: return "Paid automatically on pay day by the manager with payroll software."
        case .inHouse: return "Run in-house."
        }
    }

    private func choose(_ c: PayrollModeChoice, _ o: PayrollOverview, _ cur: Currency) {
        guard !c.isCurrent else { return }
        let id = company.id, mode = c.mode, name = modeName(c.mode)
        pending = PendingAction(title: "Change who runs payroll?",
                                message: "From the next pay day: \(name.lowercased()). " + (c.monthlyFee > 0 ? "Cost about \(cur.tidyShort(c.monthlyFee)) a month. " : "No fee, but you have to approve each month. ") + describe(mode, c.monthlyFee, cur),
                                button: "Change") {
            if store.settle(store.act { $0.setPayrollMode(companyID: id, mode: mode) }, "Payroll is now run by: \(name.lowercased()).", same: "Payroll is already run that way.", tone: "good") { Haptics.success() }
        }
    }

    private func approve(_ o: PayrollOverview, _ cur: Currency) {
        let id = company.id
        pending = PendingAction(title: "Approve payroll?", message: "About \(cur.tidyShort(o.estimate)) leaves the company on \(o.nextPayText) for \(o.payslips) \(o.payslips == 1 ? "payslip" : "payslips"). Company cash is \(cur.tidyShort(o.companyCash))" + (o.companyCash < o.estimate ? ", which does not cover it: wages would be late unless you put money in." : "."), button: "Approve") {
            switch store.act({ $0.approvePayroll(companyID: id) }) {
            case .approved?: Haptics.success(); store.show("Payroll approved. It goes out on pay day.", tone: "good")
            case .alreadyApproved?: store.show("Already approved.", tone: "n")
            case .notNeeded(let why)?: store.show(why, tone: "warn")
            case nil: break
            }
        }
    }

    private func runNow(_ o: PayrollOverview, _ cur: Currency) {
        let id = company.id
        pending = PendingAction(title: "Run payroll now?", message: "Everyone is paid today from company cash (\(cur.tidyShort(o.companyCash))). Owed: about \(cur.tidyShort(o.wagesOwed)).", button: "Run payroll") {
            if let r = store.act({ $0.runLatePayrollNow(companyID: id) }) ?? nil {
                if r.short > 0 { Haptics.warning(); store.show("Paid \(cur.tidyShort(r.paid)); still short by \(cur.tidyShort(r.short)). Put money into the company.", tone: "bad") }
                else { Haptics.success(); store.show("Payroll run: \(cur.tidyShort(r.paid)) paid.", tone: "good") }
            } else { store.show("Nothing is late any more.", tone: "n") }
        }
    }
}
