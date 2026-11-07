import SwiftUI
import GameCore
import Countries
import Simulation

// Accounting > Invoices & Payments. Invoices are the company's customer invoices (Draft, Sent, Paid, Overdue); Payments are the supplier invoices the
// company owes and has paid. A draft is sent with `sendDraftInvoice`; a supplier invoice is paid with `paySupplierInvoice`, which goes through the Bank
// payment engine and books the ledger. A customer's payment is recorded by the weekly simulation when the customer pays, so there is nothing to type in.

extension InvoiceStatus {
    var label: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .paid: return "Paid"
        case .overdue: return "Overdue"
        case .writtenOff: return "Written off"
        }
    }
    var tone: AcctPill.Tone {
        switch self {
        case .paid: return .good
        case .overdue, .writtenOff: return .bad
        case .sent: return .warn
        case .draft: return .neutral
        }
    }
}

struct AcctInvoices: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel

    private var filters: [AcctInvoiceFilter] { filters(for: m.invTab) }

    private func filters(for t: AcctInvoiceTab) -> [AcctInvoiceFilter] {
        t == .invoices ? [.all, .draft, .sent, .paid, .overdue] : [.all, .sent, .paid, .overdue]
    }

    private func filterTitle(_ f: AcctInvoiceFilter, _ t: AcctInvoiceTab) -> String {
        if t == .payments && f == .sent { return "Open" }
        return f.rawValue
    }

    private var statusFilter: InvoiceStatus? {
        switch m.invFilter {
        case .all: return nil
        case .draft: return .draft
        case .sent: return .sent
        case .paid: return .paid
        case .overdue: return .overdue
        }
    }

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            let fmt = BankFmt(store: store, company: co)
            VStack(spacing: 0) {
                SectionTabs(items: AcctInvoiceTab.allCases, title: { $0.rawValue }, selection: $m.invTab)
                    .padding(.top, 4)
                    .accessibilityIdentifier("acct-invoice-tabs")
                SegmentPager(items: AcctInvoiceTab.allCases, selection: $m.invTab) { (t: AcctInvoiceTab) in
                    invoicePage(e, co, fmt, t)
                }
            }
            .onChange(of: m.invTab) { _, _ in
                if !filters.contains(m.invFilter) { m.invFilter = .all }
            }
        }
    }

    private func invoicePage(_ e: GameEngine, _ co: Company, _ fmt: BankFmt, _ t: AcctInvoiceTab) -> some View {
        let kind: InvoiceKind = t == .invoices ? .customer : .supplier
        let items: [InvoiceItem]? = e.invoices(companyID: co.id, kind: kind, status: statusFilter, user: m.user)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if let items {
                    let valid: [AcctInvoiceFilter] = filters(for: t)
                    summary(items, fmt, kind).padding(.bottom, Theme.Space.s)
                    SegmentedPill(items: valid, title: { filterTitle($0, t) }, selection: $m.invFilter, identifier: { "acct-inv-" + $0.rawValue.lowercased() })
                    list(items, fmt, kind)
                } else {
                    AcctLocked(section: "Invoices")
                }
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xl)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
    }

    /// What is open leads (to collect, or to pay), with the overdue part under it.
    private func summary(_ items: [InvoiceItem], _ fmt: BankFmt, _ kind: InvoiceKind) -> some View {
        let open: Double = items.filter { $0.status == .sent || $0.status == .overdue }.reduce(0) { $0 + $1.gross }
        let late: Double = items.filter { $0.status == .overdue }.reduce(0) { $0 + $1.gross }
        let openLabel: String = kind == .customer ? "To collect" : "To pay"
        let context: String = late > 0.5 ? "\(fmt.short(late)) of it overdue" : "Nothing overdue"
        return MoneyHero(label: openLabel, value: fmt.full(open), context: context, contextTint: late > 0.5 ? P.loss : P.inkSoft)
    }

    @ViewBuilder private func list(_ items: [InvoiceItem], _ fmt: BankFmt, _ kind: InvoiceKind) -> some View {
        if items.isEmpty {
            let what: String = kind == .customer ? "customer invoices" : "supplier invoices"
            AcctNotice(glyph: Glyph.reports, title: "No \(what) here",
                       message: kind == .customer ? "Invoices appear when you sell to business customers on account." : "Supplier invoices appear when you buy on credit terms.")
        } else {
            AcctFlat {
                ForEach(Array(items.prefix(60).enumerated()), id: \.element.id) { n, inv in
                    VStack(spacing: 0) {
                        if n > 0 { AcctDivider() }
                        row(inv, fmt)
                    }
                }
            }
        }
    }

    private func row(_ inv: InvoiceItem, _ fmt: BankFmt) -> some View {
        let sub: String = "#" + inv.number + " \u{00B7} due " + inv.dueDateText
        return AcctLine(initials: AcctRow.initials(inv.counterparty), title: inv.counterparty, subtitle: sub, value: fmt.short(inv.gross),
                       pill: inv.status.label, pillTone: inv.status.tone, identifier: "acct-invoice-row") { m.push(.invoice(inv.id)) }
    }
}

struct AcctInvoiceDetail: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    @ObservedObject var m: AcctModel
    var invoiceID: String
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(m.companyID) {
            let fmt = BankFmt(store: store, company: co)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    if let all = e.invoices(companyID: co.id, user: m.user) {
                        if let inv = all.first(where: { $0.id == invoiceID }) {
                            header(inv, fmt)
                            lines(inv, fmt)
                            dates(inv)
                            actions(e, co, inv, fmt)
                        } else {
                            AcctNotice(glyph: Glyph.info, title: "This invoice is no longer listed", message: "Go back to the list.")
                        }
                    } else {
                        AcctLocked(section: "Invoices")
                    }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.l).padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
            .confirmAction($pending)
        }
    }

    private func header(_ inv: InvoiceItem, _ fmt: BankFmt) -> some View {
        AcctFlat(padding: 16) {
            HStack(spacing: 12) {
                Text(AcctRow.initials(inv.counterparty)).textStyle(.body, tint: P.onAccent, weight: .semibold)
                    .frame(width: 44, height: 44).background(Circle().fill(P.accent))
                VStack(alignment: .leading, spacing: 3) {
                    Text(inv.counterparty).textStyle(.headline).lineLimit(2)
                    Text("#" + inv.number + (inv.kind == .customer ? " \u{00B7} customer" : " \u{00B7} supplier")).textStyle(.caption, tint: P.inkFaint)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(fmt.full(inv.gross)).textStyle(.figure).minimumScaleFactor(0.6).lineLimit(1)
                    AcctPill(text: inv.status.label, tone: inv.status.tone)
                }
            }
        }
    }

    private func lines(_ inv: InvoiceItem, _ fmt: BankFmt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AcctCaps(text: "Line items")
            AcctFlat(padding: 14) {
                ForEach(Array(inv.lines.enumerated()), id: \.offset) { n, line in
                    FlatRow(label: line.description, value: fmt.full(line.net), sub: line.quantity != 1 ? "Quantity " + String(format: "%.0f", line.quantity) : "", rule: n > 0)
                }
                FlatRow(label: "Net", value: fmt.full(inv.net))
                FlatRow(label: "Tax", value: fmt.full(inv.tax))
                FlatRow(label: "Total", value: fmt.full(inv.gross), tint: P.ink)
            }
        }
    }

    private func dates(_ inv: InvoiceItem) -> some View {
        AcctFlat(padding: 14) {
            FlatRow(label: "Issued", value: inv.issuedDateText, rule: false)
            FlatRow(label: "Due", value: inv.dueDateText, tint: inv.status == .overdue ? P.loss : nil)
            if let paid = inv.paidDateText { FlatRow(label: "Paid", value: paid, tint: P.gain) }
        }
    }

    @ViewBuilder private func actions(_ e: GameEngine, _ co: Company, _ inv: InvoiceItem, _ fmt: BankFmt) -> some View {
        let canPay: Bool = e.canAccess(.payments, companyID: co.id, user: m.user)
        if inv.kind == .customer && inv.status == .draft {
            if canPay {
                AcctPrimaryButton(title: "Send invoice", identifier: "acct-invoice-send") { confirmSend(co, inv) }
                Text("A draft goes out with the next weekly run. Sending it now starts the payment terms today.").textStyle(.caption, tint: P.inkFaint).padding(.horizontal, 2)
            } else {
                AcctNotice(glyph: Glyph.lock, title: "Sending needs full bookkeeping access")
            }
        } else if inv.kind == .supplier && inv.canPayNow {
            if canPay {
                AcctPrimaryButton(title: "Pay now", identifier: "acct-invoice-pay") { confirmPay(co, inv, fmt) }
            } else {
                AcctNotice(glyph: Glyph.lock, title: "Paying needs full bookkeeping access")
            }
        } else if inv.kind == .customer && (inv.status == .sent || inv.status == .overdue) {
            AcctNotice(glyph: Glyph.clock, title: inv.status == .overdue ? "The customer is late" : "Waiting for the customer",
                       message: "The payment is recorded here, and in the company's account, on the day the customer pays.")
        } else if inv.status == .paid {
            AcctNotice(glyph: Glyph.check, title: "Settled", message: "This invoice is paid and booked.", tint: P.gain)
        }
    }

    private func confirmSend(_ co: Company, _ inv: InvoiceItem) {
        let id: Int = co.id
        let number: String = inv.number
        let user: String? = m.user
        let who: String = inv.counterparty
        pending = PendingAction(title: "Send invoice #\(number)?", message: "\(who) receives it today and its payment terms start now.", button: "Send", tone: .info, icon: "paperplane") {
            let ok: Bool = store.act({ (e: inout GameEngine) -> Bool in e.sendDraftInvoice(companyID: id, number: number, user: user) }) ?? false
            if ok { Haptics.success(); store.show("Invoice #\(number) sent to \(who).", tone: "good") }
            else { Haptics.warning(); store.show("The invoice could not be sent: it is no longer a draft, or you lack access.", tone: "warn") }
        }
    }

    private func confirmPay(_ co: Company, _ inv: InvoiceItem, _ fmt: BankFmt) {
        let id: Int = co.id
        let invoiceID: String = inv.id
        let user: String? = m.user
        let cur: Currency? = store.engine.map { $0.currency(for: co) }
        let balance: String = fmt.short(co.cash)
        let amount: String = fmt.short(inv.gross)
        let message: String = "\(amount) leaves the company account (\(balance) available) and \(inv.counterparty) is paid."
        pending = PendingAction(title: "Pay invoice #\(inv.number)?", message: message, button: "Pay \(amount)", amount: inv.gross, currency: cur, tone: .info, icon: "doc.text") {
            let outcome: EarlyPaymentOutcome? = store.act({ (e: inout GameEngine) -> EarlyPaymentOutcome in e.paySupplierInvoice(companyID: id, invoiceID: invoiceID, user: user) })
            switch outcome {
            case .paid(let paid)?:
                Haptics.success()
                store.show("\(fmt.short(paid)) paid to \(inv.counterparty).", tone: "good")
            case .refused(let why)?:
                Haptics.warning()
                store.show(why, tone: "warn")
            case nil:
                break
            }
        }
    }
}
