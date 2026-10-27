import SwiftUI
import GameCore
import Countries
import Simulation

/// The loan application, three steps (BankLoan.dc style): 1 how much, for how long; 2 papers and agreement; 3 summary and apply.
/// Every figure comes from `GameEngine.loanApplicationQuote` and the agreement from `loanAgreement`; the answer to the documents form is
/// checked by `applyForLoan`, which may refuse with a reason. The views hold only what the player typed.
struct BankLoanApplyFlow: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var account: BankAccountID
    @State private var step = 1
    @State private var amount = 0.0
    @State private var term = 36
    @State private var name = ""
    @State private var proof: LoanDocuments.IncomeProof = .none
    @State private var papers: LoanDocuments.CompanyPapers = .none
    @State private var agreed = false
    @State private var refusal: String?
    @State private var approved: LoanApplicationOutcome?

    private var kind: String { account.companyID == nil ? "cons" : "biz" }

    var body: some View {
        if let e = store.engine {
            let cur: Currency = account.companyID.flatMap { e.state.company($0) }.map { e.currency(for: $0) } ?? e.homeCurrency
            let q = e.loanApplicationQuote(kind: kind, amount: amount, termMonths: term, companyID: account.companyID)
            VStack(spacing: 0) {
                AppHeader(title: titleText, subtitle: subtitleText, onBack: { back() }, backLabel: step == 1 ? "Close" : "Back")
                    .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
                StepDots(step: step, count: 3).padding(.bottom, 8)
                ScrollView {
                    stepContent(e, q, cur)
                        .padding(.horizontal, 18).padding(.bottom, 40)
                        .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .ledgerBackground()
            .onAppear { if name.isEmpty { name = e.state.player.name } }
        }
    }

    private var titleText: String { step == 1 ? "Need a loan?" : step == 2 ? "Papers and agreement" : "Loan summary" }
    private var subtitleText: String {
        step == 1 ? "Choose the amount and how long you want to take" : step == 2 ? "The bank checks your papers. Read the terms carefully" : "Review everything before you apply"
    }

    private func back() {
        if approved != nil || step == 1 { dismiss() } else { withAnimation(.snappy(duration: 0.2)) { step -= 1 }; refusal = nil }
    }

    @ViewBuilder private func stepContent(_ e: GameEngine, _ q: LoanApplicationQuote, _ cur: Currency) -> some View {
        switch step {
        case 1: LoanStepAmount(q: q, cur: cur, amount: $amount, term: $term, isCompany: account.companyID != nil) { step = 2 }
        case 2:
            LoanStepPapers(q: q, cur: cur, clauses: e.loanAgreement(kind: kind, amount: amount, termMonths: term, companyID: account.companyID),
                           name: $name, proof: $proof, papers: $papers, agreed: $agreed) { step = 3 }
        default:
            LoanStepSummary(q: q, cur: cur, refusal: refusal, approved: approved, onApply: { apply(cur) }, onDone: { dismiss() })
        }
    }

    private func apply(_ cur: Currency) {
        let docs = LoanDocuments(fullName: name, incomeProof: proof, companyPapers: papers)
        let result = store.act { $0.applyForLoan(kind: kind, amount: amount, termMonths: term, companyID: account.companyID, documents: docs, agreed: agreed) }
        switch result {
        case .approved(_, _, let disbursed)?:
            Haptics.success()
            approved = result
            refusal = nil
            store.show("\(cur.tidyShort(disbursed)) is in the account.", tone: "good")
        case .refused(let why)?:
            Haptics.warning(); refusal = why
        case nil:
            Haptics.warning(); refusal = "The bank could not be reached."
        }
    }
}

/// Three dots under the header: where the player is in the application.
private struct StepDots: View {
    @Environment(\.outsidePalette) private var P
    var step: Int
    var count: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...count, id: \.self) { n in
                Capsule().fill(n <= step ? P.accent : P.lineStrong).frame(width: n == step ? 26 : 10, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step) of \(count)")
    }
}

// MARK: Step 1

private struct LoanStepAmount: View {
    @Environment(\.outsidePalette) private var P
    var q: LoanApplicationQuote
    var cur: Currency
    @Binding var amount: Double
    @Binding var term: Int
    var isCompany: Bool
    var next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            amountCard
            termCard
            dayCard
            figures
            if amount > 0, let r = q.refusal {
                Text(r).font(.system(size: 12.5)).foregroundStyle(P.caution).fixedSize(horizontal: false, vertical: true)
            }
            QuietButton(title: "Continue", fullWidth: true, action: next)
                .disabled(amount <= 0 || q.refusal != nil).opacity(amount <= 0 || q.refusal != nil ? 0.4 : 1)
        }
    }

    private var amountCard: some View {
        Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(isCompany ? "BUSINESS LOAN" : "PERSONAL LOAN").capsLabel()
                    Spacer()
                    Text("up to \(cur.tidyShort(q.maximum))").font(.system(size: 11.5)).foregroundStyle(P.inkFaint)
                }
                AmountField(title: "Amount", currency: cur, amount: $amount)
                Text("Smallest loan \(cur.tidyShort(q.minimum)). What the bank lends depends on your credit (band \(q.creditBand)), income and what you already owe.")
                    .font(.system(size: 11.5)).foregroundStyle(P.inkFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var termCard: some View {
        let lo = Double(q.minTermMonths), hi = Double(q.maxTermMonths)
        let value = Binding<Double>(get: { Double(term) }, set: { term = Int($0.rounded()) })
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                Text("LOAN TERM (MONTHS)").capsLabel()
                HStack(spacing: 14) {
                    VStack(spacing: 2) {
                        Slider(value: value, in: lo...hi, step: 1).tint(P.accent)
                        HStack {
                            Text("\(q.minTermMonths)").font(.system(size: 10.5)).foregroundStyle(P.inkFaint)
                            Spacer()
                            Text("\(q.maxTermMonths)").font(.system(size: 10.5)).foregroundStyle(P.inkFaint)
                        }
                    }
                    Text("\(q.termMonths)").font(.system(size: 22, design: .serif).monospacedDigit()).foregroundStyle(P.ink)
                        .frame(width: 64, height: 46)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
                }
            }
        }
    }

    private var dayCard: some View {
        Card(padding: 14, radius: Theme.Radius.card) {
            HStack(spacing: 12) {
                IconCircle(glyph: BankGlyph.bill, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Payment day").font(.system(size: 12)).foregroundStyle(P.inkFaint)
                    Text(q.paymentDayText).font(.system(size: 14.5, weight: .medium)).foregroundStyle(P.ink)
                }
                Spacer(minLength: 8)
                Text("set by the bank").font(.system(size: 11)).foregroundStyle(P.inkFaint)
            }
        }
    }

    @ViewBuilder private var figures: some View {
        let has: Bool = amount > 0
        StatStrip(cells: [
            .init(label: "Rate a year", value: Currency.percent(q.yearlyRate, decimals: 2)),
            .init(label: "Each month", value: has ? cur.tidyShort(q.monthlyPayment) : "-"),
            .init(label: "Fee", value: has ? cur.tidyShort(q.fee) : "-"),
        ], ruled: false)
        .padding(.vertical, 10).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(P.line, lineWidth: 1))
    }
}

// MARK: Step 2

private struct LoanStepPapers: View {
    @Environment(\.outsidePalette) private var P
    var q: LoanApplicationQuote
    var cur: Currency
    var clauses: [LoanClause]
    @Binding var name: String
    @Binding var proof: LoanDocuments.IncomeProof
    @Binding var papers: LoanDocuments.CompanyPapers
    @Binding var agreed: Bool
    var next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            formCard
            agreementCard
            checkbox
            QuietButton(title: "Proceed to loan summary", fullWidth: true, action: next)
                .disabled(!agreed).opacity(agreed ? 1 : 0.4)
        }
    }

    private var formCard: some View {
        Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR PAPERS").capsLabel()
                Text("Full name").font(.system(size: 11.5)).foregroundStyle(P.inkFaint)
                TextField("Full name", text: $name)
                    .textContentType(.name).autocorrectionDisabled()
                    .font(.system(size: 15)).foregroundStyle(P.ink)
                    .padding(.horizontal, 12).padding(.vertical, 11)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.table, style: .continuous).strokeBorder(P.lineStrong, lineWidth: 1))
                if q.needsIncomeProof { proofChoices }
                if q.needsCompanyPapers { paperChoices }
                Text("The bank checks these against its records and may turn the application down.").font(.system(size: 11.5)).foregroundStyle(P.inkFaint)
            }
        }
    }

    private var proofChoices: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Proof of income").font(.system(size: 11.5)).foregroundStyle(P.inkFaint).padding(.top, 4)
            ForEach(LoanDocuments.IncomeProof.allCases, id: \.rawValue) { p in
                ChoiceCard(title: Self.label(p), selected: proof == p) { proof = p }
            }
        }
    }

    private var paperChoices: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Company papers").font(.system(size: 11.5)).foregroundStyle(P.inkFaint).padding(.top, 4)
            ForEach(LoanDocuments.CompanyPapers.allCases, id: \.rawValue) { p in
                ChoiceCard(title: Self.label(p), selected: papers == p) { papers = p }
            }
        }
    }

    private var agreementCard: some View {
        Card(padding: 14, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                Text("LOAN AGREEMENT").capsLabel()
                ForEach(clauses) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.title).font(.system(size: 13, weight: .medium)).foregroundStyle(P.ink)
                        Text(c.body.tidyText).font(.system(size: 12.5)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var checkbox: some View {
        Button { agreed.toggle(); Haptics.choose() } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(agreed ? P.accent : P.lineStrong, lineWidth: 1.5)
                    if agreed { GlyphView(glyph: "M5 12 L10 17 L19 7", size: 14, weight: 2, tint: P.accent) }
                }
                .frame(width: 22, height: 22)
                Text("I have read and agree to the terms of this loan agreement. I understand my obligations as a borrower and what happens if I miss a payment.")
                    .font(.system(size: 12)).foregroundStyle(P.inkSoft).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(agreed ? .isSelected : [])
    }

    private static func label(_ p: LoanDocuments.IncomeProof) -> String {
        switch p {
        case .none: return "None"
        case .payslips: return "Payslips"
        case .taxReturn: return "Last tax return"
        case .bankStatements: return "Bank statements"
        }
    }

    private static func label(_ p: LoanDocuments.CompanyPapers) -> String {
        switch p {
        case .none: return "None"
        case .registration: return "Registration certificate"
        case .accounts: return "Company accounts"
        }
    }
}

// MARK: Step 3

private struct LoanStepSummary: View {
    @Environment(\.outsidePalette) private var P
    var q: LoanApplicationQuote
    var cur: Currency
    var refusal: String?
    var approved: LoanApplicationOutcome?
    var onApply: () -> Void
    var onDone: () -> Void
    @State private var showSchedule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if approved != nil { approvedBanner }
            loanCard
            repayCard
            if let refusal { refusedCard(refusal) }
            scheduleLink
            if approved == nil { QuietButton(title: "Apply for the loan", fullWidth: true, action: onApply) }
            else { QuietButton(title: "Done", fullWidth: true, action: onDone) }
        }
    }

    private var approvedBanner: some View {
        HStack(spacing: 10) {
            GlyphView(glyph: "M5 12 L10 17 L19 7", size: 18, weight: 2, tint: P.gain)
            Text("Approved. \(cur.tidyDisplay(q.disbursal)) has been paid into the account.").font(.system(size: 13)).foregroundStyle(P.ink)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(P.gain.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(P.gain.opacity(0.45), lineWidth: 1))
    }

    private func refusedCard(_ why: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            GlyphView(glyph: Glyph.warning, size: 18, weight: 1.6, tint: P.caution)
            VStack(alignment: .leading, spacing: 2) {
                Text("The bank turned the application down").font(.system(size: 13, weight: .medium)).foregroundStyle(P.ink)
                Text(why.tidyText).font(.system(size: 12.5)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(P.caution.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(P.caution.opacity(0.45), lineWidth: 1))
    }

    private var loanCard: some View {
        Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(spacing: 0) {
                line("Loan amount", cur.tidyDisplay(q.amount))
                line("Loan term", "\(q.termMonths) months")
                line("Arrangement fee (\(Currency.percent(q.feeRate, decimals: 2)))", q.fee > 0 ? "\u{2212}" + cur.tidyDisplay(q.fee) : cur.tidyDisplay(0), tint: q.fee > 0 ? P.loss : P.ink)
                Hairline().padding(.vertical, 6)
                line("Disbursal amount", cur.tidyDisplay(q.disbursal), tint: P.gain, strong: true)
            }
        }
    }

    private var repayCard: some View {
        Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(spacing: 0) {
                line("Repayment amount", cur.tidyDisplay(q.totalRepaid))
                line("Interest in total", cur.tidyDisplay(q.totalInterest))
                line("Interest rate a year", Currency.percent(q.yearlyRate, decimals: 2))
                line("First payment due", q.firstPaymentText)
                Hairline().padding(.vertical, 6)
                line("Monthly instalment", cur.tidyDisplay(q.monthlyPayment), tint: P.gain, strong: true)
            }
        }
    }

    private func line(_ label: String, _ value: String, tint: Color = P.ink, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13.5)).foregroundStyle(strong ? P.ink : P.inkSoft)
            Spacer(minLength: 8)
            Text(value).font(.system(size: strong ? 16 : 14, weight: strong ? .medium : .regular).monospacedDigit()).foregroundStyle(tint)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder private var scheduleLink: some View {
        Button { showSchedule.toggle(); Haptics.choose() } label: {
            HStack {
                Text(showSchedule ? "Hide repayment schedule" : "View repayment schedule").font(.system(size: 13.5)).foregroundStyle(P.accent).underline()
                Spacer()
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
        if showSchedule { schedule }
    }

    private var schedule: some View {
        let columns: [TableColumn] = [TableColumn(title: "Date"), TableColumn(title: "Pay", width: 78), TableColumn(title: "Left", width: 78)]
        return SharpTable {
            TableHeader(columns: columns)
            ForEach(q.schedule) { r in
                TableRow(columns: columns, title: r.dateText, note: "Payment \(r.number)", values: [cur.tidyShort(r.payment), cur.tidyShort(r.balance)])
            }
        }
    }
}
