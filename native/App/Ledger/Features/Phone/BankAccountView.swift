import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

/// One account (BankAccount.dc.html): the payroll alert, the tabs, the balance card with the available / overdraft / rate strip, the four
/// action tiles and the tab's content. Every money action is the engine's existing one; each reports its result in a toast.
struct BankAccountScreen: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var id: BankAccountID
    @Binding var tab: BankTab
    @State private var move: BankMoveKind?
    @State private var paying = false
    @State private var viewAll = false

    private var tabs: [BankTab] {
        switch id {
        case .personal: return [.account, .loans, .deposits, .bills, .statements]
        case .investments: return [.account, .deposits]
        case .company: return [.account, .loans, .bills, .statements]
        }
    }

    var body: some View {
        if let e = store.engine, let d = e.bankAccount(id) {
            let fmt = BankFmt.make(store, id)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let a = d.alert { alertBanner(a, fmt) }
                    tabRow(d)
                    balanceCard(d, fmt)
                    tiles(d)
                    content(e, d, fmt)
                }
                .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .sheet(item: $move) { kind in BankMoveSheet(account: id, kind: kind).presentationDetents([.medium, .large]) }
            .sheet(isPresented: $paying) { BankPaySheet(account: id).presentationDetents([.medium, .large]) }
            .sheet(isPresented: $viewAll) { BankAllMovementsSheet(account: id).presentationDetents([.large]) }
        } else {
            Text("This account is closed.").font(.system(size: 13)).foregroundStyle(P.inkSoft).padding(24)
        }
    }

    // MARK: Alert

    private func alertBanner(_ a: PayrollAlert, _ fmt: BankFmt) -> some View {
        let text: String = a.isLate ? "Payroll \(fmt.short(a.amount)) is late. \(a.reason)"
                                    : "Payroll \(fmt.short(a.amount)) on \(a.dateText) needs you. \(a.reason)"
        return HStack(alignment: .center, spacing: 10) {
            GlyphView(glyph: Glyph.warning, size: 18, weight: 1.6, tint: P.caution)
            Text(text.tidyText).font(.system(size: 12.5)).foregroundStyle(P.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                Haptics.tap()
                BankPay.resolve(store, companyID: a.companyID)
            } label: {
                Text(a.isLate ? "Pay now" : "Approve").font(.system(size: 12.5, weight: .medium)).foregroundStyle(P.ink)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(P.accent, lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.caution.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.caution.opacity(0.45), lineWidth: 1))
    }

    // MARK: Tabs

    private func tabRow(_ d: BankAccountDetail) -> some View {
        let billsDot: Bool = d.alert != nil
        return HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { t in
                let on: Bool = tab == t
                Button { tab = t; Haptics.choose() } label: {
                    Text(t.rawValue).font(.system(size: 12, weight: on ? .medium : .regular))
                        .foregroundStyle(on ? P.ink : P.inkSoft)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 9).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? P.accentSelected : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? P.accent : Color.clear, lineWidth: 1))
                        .overlay(alignment: .topTrailing) {
                            if t == .bills && billsDot { Circle().fill(Theme.alert).frame(width: 8, height: 8).offset(x: -2, y: 3) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.line, lineWidth: 1))
    }

    // MARK: Balance

    private func balanceCard(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        let label: String = id == .personal ? "Current account" : id == .investments ? "Value of what you hold" : "Company account"
        let tint: Color = d.balance < 0 ? P.loss : P.ink
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.system(size: 12)).foregroundStyle(P.accent)
                        Text(fmt.full(d.balance)).font(.hero(34)).foregroundStyle(tint).minimumScaleFactor(0.55).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let m = d.monthChange, abs(m) >= 0.5 {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text((m > 0 ? "▲ " : "▼ ") + fmt.short(abs(m))).font(.system(size: 12)).foregroundStyle(P.change(m))
                            Text("this month").font(.system(size: 12)).foregroundStyle(P.inkFaint)
                        }
                    }
                }
                if id != .investments {
                    let overdraft: String = d.overdraftUsed > 0 ? fmt.short(d.overdraftUsed) + " used" : fmt.short(d.overdraftLimit)
                    let rate: String = d.overdraftRate.map { Currency.percent($0, decimals: 2) } ?? "–"
                    StatStrip(cells: [
                        .init(label: "Available", value: fmt.short(d.available), tint: d.available <= 0 ? P.loss : P.ink),
                        .init(label: "Overdraft", value: overdraft, tint: d.overdraftUsed > 0 ? P.caution : P.ink),
                        .init(label: "Overdraft rate", value: rate),
                    ])
                }
                if let s = d.savings {
                    let r: String = d.savingsRate.map { " at " + Currency.percent($0, decimals: 2) } ?? ""
                    Text("Savings \(fmt.short(s))\(r)").font(.system(size: 12)).foregroundStyle(P.inkSoft)
                }
            }
        }
    }

    // MARK: Tiles

    @ViewBuilder private func tiles(_ d: BankAccountDetail) -> some View {
        let due: Int = d.upcoming.count
        if id == .investments {
            HStack(spacing: 8) {
                ActionTile(glyph: Glyph.invest, title: "Buy or sell") { tab = .deposits }
                ActionTile(glyph: BankGlyph.transfer, title: "Cash to invest") { move = .transfer }
            }
        } else {
            HStack(spacing: 8) {
                ActionTile(glyph: BankGlyph.transfer, title: "Transfer") { move = .transfer }
                ActionTile(glyph: BankGlyph.deposit, title: "Deposit") { move = .deposit }
                ActionTile(glyph: BankGlyph.withdraw, title: "Withdraw") { move = .withdraw }
                ActionTile(glyph: BankGlyph.bill, title: "Pay bill", badge: due > 0 && d.alert != nil ? 1 : 0) { paying = true }
            }
        }
    }

    // MARK: Content

    @ViewBuilder private func content(_ e: GameEngine, _ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        switch tab {
        case .account: accountTab(e, d, fmt)
        case .loans: BankLoansTab(account: id, loans: d.loans)
        case .deposits: BankDepositsTab(account: id, detail: d)
        case .bills: BankBillsTab(account: id, detail: d)
        case .statements: BankStatementsTab(account: id, detail: d)
        }
    }

    private func accountTab(_ e: GameEngine, _ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if id != .investments {
                comingUp(d, fmt)
            }
            recent(d, fmt)
            if let cid = id.companyID, let co = e.state.company(cid), co.form == .limited {
                BankOwnerSalary(company: co)
            }
            if id == .personal {
                NavigationLink { ActivityView() } label: {
                    HStack {
                        Text("Every movement on your account").font(.system(size: 13.5)).foregroundStyle(P.accent)
                        Spacer()
                        GlyphView(glyph: Glyph.chevron, size: 12, weight: 2, tint: P.accent)
                    }.padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private func comingUp(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("COMING UP").capsLabel()
                    Spacer()
                    Button { tab = .bills; Haptics.tap() } label: { Text("Bills ›").font(.system(size: 12)).foregroundStyle(P.accent) }.buttonStyle(.plain)
                }.padding(.bottom, 4)
                if d.upcoming.isEmpty { Text("Nothing is due.").font(.system(size: 13)).foregroundStyle(P.inkSoft).padding(.vertical, 6) }
                ForEach(Array(d.upcoming.prefix(3).enumerated()), id: \.element.id) { n, u in
                    if n > 0 { Hairline() }
                    BankObligationRow(obligation: u, fmt: fmt)
                }
            }
        }
    }

    private func recent(_ d: BankAccountDetail, _ fmt: BankFmt) -> some View {
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("RECENT").capsLabel()
                    Spacer()
                    Button { viewAll = true; Haptics.tap() } label: { Text("View all ›").font(.system(size: 12)).foregroundStyle(P.accent) }.buttonStyle(.plain)
                }.padding(.bottom, 4)
                if d.recent.isEmpty { Text("Nothing has gone through yet.").font(.system(size: 13)).foregroundStyle(P.inkSoft).padding(.vertical, 6) }
                ForEach(Array(d.recent.prefix(5).enumerated()), id: \.element.id) { n, t in
                    if n > 0 { Hairline() }
                    BankTransactionRow(transaction: t, fmt: fmt)
                }
            }
        }
    }
}

/// One coming payment: icon, title, date, amount.
struct BankObligationRow: View {
    @Environment(\.outsidePalette) private var P
    var obligation: Obligation
    var fmt: BankFmt
    var body: some View {
        let glyph: String = obligation.kind == .loan ? BankGlyph.transfer : BankGlyph.bill
        HStack(spacing: 10) {
            IconCircle(glyph: glyph, size: 30, tint: P.inkSoft)
            VStack(alignment: .leading, spacing: 1) {
                Text(obligation.title.tidyText).font(.system(size: 13.5)).foregroundStyle(P.ink).lineLimit(2)
                Text(obligation.dateText).font(.system(size: 11.5)).foregroundStyle(P.inkFaint)
            }
            Spacer(minLength: 8)
            Text(fmt.short(obligation.amount)).font(.system(size: 14).monospacedDigit()).foregroundStyle(P.ink)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// One movement: label, date, signed amount.
struct BankTransactionRow: View {
    @Environment(\.outsidePalette) private var P
    var transaction: BankTransaction
    var fmt: BankFmt
    var body: some View {
        let sign: String = transaction.amount >= 0 ? "+" : "−"
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(transaction.label.tidyText).font(.system(size: 13.5)).foregroundStyle(P.ink).lineLimit(2)
                Text(transaction.dateText).font(.system(size: 11.5)).foregroundStyle(P.inkFaint)
            }
            Spacer(minLength: 8)
            Text(sign + fmt.short(abs(transaction.amount))).font(.system(size: 14).monospacedDigit()).foregroundStyle(P.change(transaction.amount))
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// "View all": the longer list of movements.
struct BankAllMovementsSheet: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var account: BankAccountID
    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = store.engine {
                    let fmt = BankFmt.make(store, account)
                    let list: [BankTransaction] = e.bankTransactions(account, limit: 200)
                    VStack(spacing: 0) {
                        if list.isEmpty { Text("Nothing has gone through yet.").font(.system(size: 13)).foregroundStyle(P.inkSoft) }
                        ForEach(Array(list.enumerated()), id: \.element.id) { n, t in
                            if n > 0 { Hairline() }
                            BankTransactionRow(transaction: t, fmt: fmt)
                        }
                    }.padding(Theme.Space.margin)
                }
            }
            .ledgerBackground()
            .navigationTitle("Every movement").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// The owner's salary from a limited company (moved here from the company's money desk).
struct BankOwnerSalary: View {
    @Environment(\.outsidePalette) private var P
    @EnvironmentObject var store: GameStore
    var company: Company
    @State private var salary = 0.0

    var body: some View {
        if let e = store.engine {
            let cur = e.currency(for: company)
            let now: Double = e.state.company(company.id)?.ownerMonthlySalary ?? 0
            BankCard(title: "Your salary", trailing: now > 0 ? cur.tidyShort(now) + " a month" : "None") {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    AmountField(title: "Monthly salary", currency: cur, amount: $salary)
                    HStack {
                        Button("Set salary") { set(salary, cur) }.buttonStyle(QuietButtonStyle())
                        if now > 0 { Button("Stop salary") { set(0, cur) }.buttonStyle(QuietButtonStyle(tint: P.inkSoft)) }
                    }
                    Text("Paid with payroll while the company is open, with employer contributions on top; income tax is withheld. A salary is a cost to the company, a dividend is not.")
                        .font(.caption2).foregroundStyle(P.inkFaint).fixedSize(horizontal: false, vertical: true)
                }
            }
            .onAppear { salary = now }
        }
    }

    private func set(_ v: Double, _ cur: Currency) {
        let result = store.act { $0.setOwnerSalary(companyID: company.id, monthly: v) }
        let now: Double = store.engine?.state.company(company.id)?.ownerMonthlySalary ?? 0
        salary = now
        store.settle(result, now > 0 ? "Your salary is now \(cur.tidyDisplay(now)) a month." : "You no longer take a salary.", same: "Your salary is already that.")
    }
}
