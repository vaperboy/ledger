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
            let alert: PayrollAlertInfo? = engine.payrollAlertInfos().first { $0.companyID == company.id }
            TeamGroup(title: "Payroll", trailing: { Text(modeName(o.mode)).font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
                if let alert { warning(alert, o, cur) }
                Card(padding: 14, radius: Theme.Radius.hero) {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        HStack(spacing: 12) {
                            IconCircle(glyph: Glyph.bank)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Payroll run").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                                Text(o.hasPayroll ? "Next pay day \(o.nextPayText)" : "No one is on the payroll yet").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                            }
                            Spacer(minLength: 0)
                        }
                        if !o.hasPayroll {
                            Text("There is nothing to run. This appears once you hire someone.")
                                .font(.bodyText).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                        } else {
                            status(o, cur)
                            if o.isLate { late(o, cur) }
                            else if o.needsApproval && alert == nil {
                                TeamAction(title: "Approve this month's payroll") { approve(o, cur) }
                            }
                        }
                    }
                }
                Card(padding: 14, radius: Theme.Radius.card) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("Who runs payroll").capsLabel(Theme.ivoryFaint)
                        if o.modeIsFixed {
                            Text("This kind of company runs its own payroll in-house. Nothing to choose.").font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint)
                        } else {
                            ForEach(o.choices) { c in
                                let fee: String = c.monthlyFee > 0 ? cur.tidyShort(c.monthlyFee) + " a month" : "No fee"
                                let sub: String = c.unavailable ?? describe(c.mode, c.monthlyFee, cur)
                                ChoiceCard(title: modeName(c.mode), subtitle: sub, trailing: fee, selected: c.isCurrent) { choose(c, o, cur) }
                                    .opacity(c.unavailable != nil ? 0.5 : 1).disabled(c.unavailable != nil)
                            }
                            Text("A change applies from the next pay day. The accountant's fee is per payslip; the manager's payroll software has a monthly fee and now and then misses a step, paying a day or two late.")
                                .font(.caption2).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .confirmAction($pending)
        }
    }

    /// Nobody approves this payroll: the owner has to, or staff are not paid on pay day. Same engine step as the Inbox decision.
    private func warning(_ alert: PayrollAlertInfo, _ o: PayrollOverview, _ cur: Currency) -> some View {
        let amount: String = cur.tidyShort(alert.amount)
        return Card(padding: 14, radius: Theme.Radius.hero, stroke: Theme.alert.opacity(0.7)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    IconCircle(glyph: Glyph.warning, tint: Theme.alert)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("No one approves this payroll").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                        Text("About \(amount) on \(alert.dateText)").font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted)
                    }
                    Spacer(minLength: 0)
                }
                Text("There is no manager or accountant to approve it. Unless you approve it, or hand payroll to one of them below, staff are not paid on pay day.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
                if o.needsApproval && !o.isLate {
                    TeamAction(title: "Approve this month's payroll", tint: Theme.gold) { approve(o, cur) }
                }
            }
        }
    }

    private func late(_ o: PayrollOverview, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Wages are late", systemImage: "exclamationmark.triangle.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.loss)
                Spacer(minLength: 8)
                if o.wageShortfall > 0 {
                    Text("\(cur.tidyShort(o.wageShortfall)) unpaid").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.loss)
                }
            }
            Text(o.lateReason + " Staff are waiting; unpaid wages lead to resignations and a wage claim.").font(.system(size: 13)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
            if o.companyCash < max(o.wageShortfall, o.wagesOwed) {
                Text("Company cash is \(cur.tidyShort(o.companyCash)): put money in first or only part can be paid. See You and owners.").font(.system(size: 12)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
            }
            TeamAction(title: "Run payroll now", tint: Theme.loss) { runNow(o, cur) }
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
        if store.settle(store.act { $0.setPayrollMode(companyID: id, mode: mode) }, "Payroll is now run by: \(name.lowercased()), from the next pay day." + (c.monthlyFee > 0 ? " About \(cur.tidyShort(c.monthlyFee)) a month." : ""), same: "Payroll is already run that way.", tone: "good") { Haptics.success() }
    }

    private func approve(_ o: PayrollOverview, _ cur: Currency) {
        let id = company.id
        switch store.act({ $0.approvePayroll(companyID: id) }) {
        case .approved?: Haptics.success(); store.show("Payroll approved: about \(cur.tidyShort(o.estimate)) goes out on \(o.nextPayText).", tone: "good")
        case .alreadyApproved?: store.show("Already approved.", tone: "n")
        case .notNeeded(let why)?: Haptics.warning(); store.show(why, tone: "warn")
        case nil: break
        }
    }

    private func runNow(_ o: PayrollOverview, _ cur: Currency) {
        let id = company.id
        let owed = max(o.wageShortfall, o.wagesOwed)
        pending = PendingAction(title: "Run payroll now?", message: "Everyone is paid today from company cash (\(cur.tidyShort(o.companyCash))). Still unpaid: about \(cur.tidyShort(owed)). " + (o.companyCash < owed ? "The cash does not cover it, so part stays unpaid." : "Leaves about \(cur.tidyShort(o.companyCash - owed)) in the company."), button: "Run payroll", amount: owed, currency: cur) {
            if let r = store.act({ $0.runLatePayrollNow(companyID: id) }) ?? nil {
                if r.short > 0 { Haptics.warning(); store.show("Paid \(cur.tidyShort(r.paid)); still short by \(cur.tidyShort(r.short)). Put money into the company.", tone: "bad") }
                else { Haptics.success(); store.show("Payroll run: \(cur.tidyShort(r.paid)) paid.", tone: "good") }
            } else { Haptics.warning(); store.show("Nothing is late any more.", tone: "n") }
        }
    }
}
