import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Payroll as Team shows it (Master spec 3H): who is responsible (derived from the company's accountant, manager and the owner, never chosen here)
/// and when the next pay day is, with ONE link to Accounting > Payroll, where payroll is reviewed, approved and paid. There is no payroll run and no
/// "who runs payroll" picker in Team any more: the choice was replaced by the derived rule.
struct CompanyPayrollRun: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company

    var body: some View {
        if let o = engine.payrollOverview(companyID: company.id) {
            let cur = engine.currency(for: company)
            let who: String = o.responsibility?.name ?? "You"
            let why: String = o.responsibility?.reason ?? ""
            let alert: PayrollAlertInfo? = engine.payrollAlertInfos().first { $0.companyID == company.id }
            TeamGroup(title: "Payroll", trailing: { Text(o.hasPayroll ? "Next pay day " + o.nextPayText : "No one on the payroll").font(.system(size: 11.5)).foregroundStyle(Theme.ivoryFaint) }) {
                Card(padding: 14, radius: Theme.Radius.hero) {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        HStack(spacing: 12) {
                            IconCircle(glyph: alert == nil ? Glyph.people : Glyph.warning, tint: alert == nil ? nil : Theme.alert)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Run by \(who)").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.ivory)
                                Text(why).font(.system(size: 12)).foregroundStyle(Theme.ivoryMuted).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        if o.isLate {
                            Text("Wages are late: " + cur.tidyShort(max(o.wageShortfall, o.wagesOwed)) + " unpaid. " + o.lateReason)
                                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.loss).fixedSize(horizontal: false, vertical: true)
                        } else if alert != nil {
                            Text("Nobody else approves it, so it waits for you before pay day.").font(.system(size: 12.5)).foregroundStyle(Theme.caution).fixedSize(horizontal: false, vertical: true)
                        }
                        QuietButton(title: "Open Accounting \u{203A} Payroll", fullWidth: true) { store.openAccounting(companyID: company.id, payroll: true) }
                            .accessibilityIdentifier("team-open-accounting-payroll")
                    }
                }
            }
        }
    }
}
