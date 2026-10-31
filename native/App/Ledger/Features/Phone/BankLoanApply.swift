import SwiftUI
import GameCore
import Countries
import Simulation

/// The loan application in two stages (Master spec 2F, mockup banking_app.png): 1 Apply and the bank's assessment (Apply, Offer), then 2 the final
/// agreement (Choose, Agreement, Confirm). The assessment shows the MAXIMUM the bank approves with its rate, period and instalment; the player then
/// chooses any amount up to it (never forced to take the maximum), reads and accepts the agreement, and confirms where the money is paid.
/// Every figure comes from `loanAssessment`, `loanApplicationQuote` and `loanAgreement`; `applyForLoan` re-checks everything and may refuse with a reason.
struct BankLoanApplyFlow: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    var account: BankAccountID
    @State private var step = 1
    @State private var amount = 0.0
    @State private var term = 36
    @State private var payInto: LoanPayout = .current
    @State private var name = ""
    @State private var proof: LoanDocuments.IncomeProof = .none
    @State private var papers: LoanDocuments.CompanyPapers = .none
    @State private var agreed = false
    @State private var refusal: String?
    @State private var approved: LoanApplicationOutcome?
    @State private var pending: PendingAction?

    private var kind: String { account.companyID == nil ? "cons" : "biz" }
    private static let stepCount = 5

    var body: some View {
        if let e = store.engine {
            let cur: Currency = account.companyID.flatMap { e.state.company($0) }.map { e.currency(for: $0) } ?? e.homeCurrency
            let a: LoanAssessment = e.loanAssessment(kind: kind, companyID: account.companyID)
            let q: LoanApplicationQuote = e.loanApplicationQuote(kind: kind, amount: amount, termMonths: term, companyID: account.companyID)
            VStack(spacing: 0) {
                AppHeader(title: titleText, subtitle: subtitleText, onBack: { back() }, backLabel: step == 1 ? "Close" : "Back")
                    .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
                StepDots(step: step, count: Self.stepCount, labels: ["Apply", "Offer", "Choose", "Agreement", "Confirm"]).padding(.bottom, 8)
                ScrollView {
                    stepContent(e, a, q, cur)
                        .padding(.horizontal, 18).padding(.bottom, 40)
                        .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .ledgerBackground()
            .confirmAction($pending)
            .onAppear { if name.isEmpty { name = e.state.player.name } }
        }
    }

    private var titleText: String {
        switch step {
        case 1: return "Loan application"
        case 2: return "Loan offer"
        case 3: return "Choose your loan"
        case 4: return "Papers and agreement"
        default: return "Confirm the loan"
        }
    }
    private var subtitleText: String {
        switch step {
        case 1: return "Get the financing you need"
        case 2: return "Here is what the bank can offer you"
        case 3: return "Borrow what you need, up to the maximum"
        case 4: return "The bank checks your papers. Read the terms carefully"
        default: return "Review everything before you confirm"
        }
    }

    private func back() {
        if approved != nil || step == 1 { dismiss() } else { withAnimation(.snappy(duration: 0.2)) { step -= 1 }; refusal = nil }
    }

    @ViewBuilder private func stepContent(_ e: GameEngine, _ a: LoanAssessment, _ q: LoanApplicationQuote, _ cur: Currency) -> some View {
        switch step {
        case 1:
            LoanStepApply(a: a, cur: cur, isCompany: account.companyID != nil) { step = 2 }
        case 2:
            LoanStepOffer(a: a, cur: cur, choose: { startChoosing(a) })
        case 3:
            LoanStepChoose(a: a, q: q, cur: cur, amount: $amount, term: $term, payInto: $payInto) { step = 4 }
        case 4:
            LoanStepPapers(q: q, cur: cur, clauses: e.loanAgreement(kind: kind, amount: amount, termMonths: term, companyID: account.companyID),
                           name: $name, proof: $proof, papers: $papers, agreed: $agreed) { step = 5 }
        default:
            LoanStepSummary(q: q, cur: cur, payIntoName: payIntoName(a), personalGuarantee: a.personalGuarantee, refusal: refusal, approved: approved,
                            onApply: { confirmApply(a, q, cur) }, onDone: { dismiss() })
        }
    }

    /// From the offer to the choice: start below the maximum (the player is never pushed to the top) and on the bank's usual term.
    private func startChoosing(_ a: LoanAssessment) {
        let step100: Double = max(1, (a.maximum / 100).rounded())
        let suggested: Double = (a.maximum * 0.6 / step100).rounded() * step100
        amount = min(a.maximum, max(a.minimum, suggested))
        term = a.defaultTermMonths
        payInto = a.payoutAccounts.first?.id ?? .current
        step = 3
    }

    private func payIntoName(_ a: LoanAssessment) -> String {
        a.payoutAccounts.first(where: { $0.id == payInto })?.name ?? "the account"
    }

    /// The final confirmation: cost, effect and risk first. Nothing is booked until the player confirms here and the bank accepts.
    private func confirmApply(_ a: LoanAssessment, _ q: LoanApplicationQuote, _ cur: Currency) {
        let into: String = payIntoName(a)
        var message: String = "You borrow \(cur.tidyDisplay(q.amount)) for \(q.termMonths) months at \(Currency.percent(q.yearlyRate, decimals: 2)) a year. "
        message += "\(cur.tidyDisplay(q.disbursal)) is paid into \(into) after the \(cur.tidyDisplay(q.fee)) arrangement fee; you owe the full amount, \(cur.tidyDisplay(q.monthlyPayment)) a month. "
        message += a.personalGuarantee ? "You are personally liable for it. " : ""
        message += "A missed instalment adds a penalty and lowers your credit."
        pending = PendingAction(title: "Take this loan?", message: message, button: "Confirm and pay into \(into)") { apply(cur) }
    }

    private func apply(_ cur: Currency) {
        let docs = LoanDocuments(fullName: name, incomeProof: proof, companyPapers: papers)
        let result: LoanApplicationOutcome? = store.act({ (e: inout GameEngine) -> LoanApplicationOutcome in
            e.applyForLoan(kind: kind, amount: amount, termMonths: term, companyID: account.companyID, documents: docs, agreed: agreed, payInto: payInto)
        })
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

/// Dots under the header: where the player is in the application.
private struct StepDots: View {
    @Environment(\.outsidePalette) private var P
    var step: Int
    var count: Int
    var labels: [String] = []
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(1...count, id: \.self) { n in
                    Capsule().fill(n <= step ? P.accent : P.lineStrong).frame(width: n == step ? 26 : 10, height: 4)
                }
            }
            if step >= 1 && step <= labels.count {
                Text(labels[step - 1]).font(.system(size: 11)).foregroundStyle(P.inkFaint)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step) of \(count)")
    }
}

// MARK: Stage 1: Apply

private struct LoanStepApply: View {
    @Environment(\.outsidePalette) private var P
    var a: LoanAssessment
    var cur: Currency
    var isCompany: Bool
    var next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            IvoryPanel {
                LoanApplyPanel(borrower: a.borrowerName, isCompany: isCompany)
            }
            NoteCard(text: "Applying only asks the bank. Nothing is borrowed and nothing is charged until you have seen the offer, chosen an amount and confirmed.", glyph: Glyph.info)
            QuietButton(title: "Ask the bank", fullWidth: true, action: next)
                .accessibilityIdentifier("bank-loan-start")
        }
    }
}

private struct LoanApplyPanel: View {
    @Environment(\.outsidePalette) private var P
    var borrower: String
    var isCompany: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How much can you borrow?").font(.serifTitle(20)).foregroundStyle(P.ink)
            Text("The bank looks at your financial position, your existing debt and \(isCompany ? "the company's performance" : "your income") and tells you the most it would lend.")
                .font(.system(size: 13)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            FlatRow(label: isCompany ? "Business loan for" : "Personal loan for", value: borrower, rule: true)
        }
    }
}

// MARK: Stage 1: Offer

private struct LoanStepOffer: View {
    @Environment(\.outsidePalette) private var P
    var a: LoanAssessment
    var cur: Currency
    var choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if a.approved {
                IvoryPanel { LoanOfferPanel(a: a, cur: cur) }
                conditions
                QuietButton(title: "Choose an amount", fullWidth: true, action: choose)
                    .accessibilityIdentifier("bank-loan-choose")
            } else {
                refused
            }
        }
    }

    private var refused: some View {
        HStack(alignment: .top, spacing: 10) {
            GlyphView(glyph: Glyph.warning, size: 18, weight: 1.6, tint: P.caution)
            VStack(alignment: .leading, spacing: 2) {
                Text("The bank would not lend now").font(.system(size: 13.5, weight: .medium)).foregroundStyle(P.ink)
                Text((a.refusal ?? "The bank would not lend to you at the moment.").tidyText).font(.system(size: 12.5)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(P.caution.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(P.caution.opacity(0.45), lineWidth: 1))
        .accessibilityIdentifier("bank-loan-refused")
    }

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONDITIONS").capsLabel()
            ForEach(Array(a.conditions.enumerated()), id: \.offset) { _, c in
                Text(c.tidyText).font(.system(size: 12.5)).foregroundStyle(P.inkSoft).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 2)
    }
}

/// The offer on ivory: the maximum approved amount first, then rate, period and the instalment at the maximum.
private struct LoanOfferPanel: View {
    @Environment(\.outsidePalette) private var P
    var a: LoanAssessment
    var cur: Currency

    var body: some View {
        let minTerm: Int = a.termOptions.min() ?? a.defaultTermMonths
        let maxTerm: Int = a.termOptions.max() ?? a.defaultTermMonths
        let example: LoanExample? = a.examplesAtMaximum.first(where: { $0.termMonths == a.defaultTermMonths }) ?? a.examplesAtMaximum.first
        let period: String = minTerm == maxTerm ? "\(minTerm) months" : "\(minTerm) to \(maxTerm) months"
        let instalment: String = example.map { cur.tidyDisplay($0.monthlyPayment) } ?? "\u{2013}"
        let instalmentNote: String = example.map { "over \($0.termMonths) months" } ?? ""
        VStack(alignment: .leading, spacing: 0) {
            Text("Maximum approved amount").font(.system(size: 12.5)).foregroundStyle(P.inkSoft)
            Text(cur.tidyDisplay(a.maximum)).font(.hero(36)).foregroundStyle(P.ink).minimumScaleFactor(0.6).lineLimit(1)
                .accessibilityIdentifier("bank-loan-maximum")
            FlatRow(label: "Interest rate", value: Currency.percent(a.yearlyRate, decimals: 2) + " a year", rule: true)
            FlatRow(label: "Repayment period", value: period)
            FlatRow(label: "Monthly instalment at the maximum", value: instalment, sub: instalmentNote)
            FlatRow(label: "Arrangement fee", value: Currency.percent(a.feeRate, decimals: 2), sub: "taken when the money is paid out")
            FlatRow(label: "Your credit band", value: a.creditBand)
            if a.personalGuarantee { FlatRow(label: "Guarantee", value: "You are personally liable") }
        }
    }
}

// MARK: Stage 2: Choose

private struct LoanStepChoose: View {
    @Environment(\.outsidePalette) private var P
    var a: LoanAssessment
    var q: LoanApplicationQuote
    var cur: Currency
    @Binding var amount: Double
    @Binding var term: Int
    @Binding var payInto: LoanPayout
    var next: () -> Void

    private var valid: Bool { amount >= a.minimum && amount <= a.maximum + 0.5 && q.refusal == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            amountPanel
            termCard
            if a.payoutAccounts.count > 1 { payoutCard }
            figures
            if !valid, let r = q.refusal {
                Text(r.tidyText).font(.system(size: 12.5)).foregroundStyle(P.caution).fixedSize(horizontal: false, vertical: true)
            }
            QuietButton(title: "Continue", fullWidth: true, action: next)
                .disabled(!valid).opacity(valid ? 1 : 0.4)
                .accessibilityIdentifier("bank-loan-continue")
        }
    }

    private var amountPanel: some View {
        let step: Double = max(1, (a.maximum / 100).rounded())
        let slider = Binding<Double>(
            get: { amount },
            set: { v in amount = min(a.maximum, max(a.minimum, (v / step).rounded() * step)) })
        return IvoryPanel {
            LoanAmountPanel(cur: cur, amount: amount, minimum: a.minimum, maximum: a.maximum, slider: slider, setFraction: { f in
                amount = min(a.maximum, max(a.minimum, f >= 1 ? a.maximum : (a.maximum * f / step).rounded() * step))
            })
        }
    }

    private var termCard: some View {
        let lo = Double(q.minTermMonths), hi = Double(q.maxTermMonths)
        let value = Binding<Double>(get: { Double(term) }, set: { term = Int($0.rounded()) })
        return Card(padding: 16, radius: Theme.Radius.hero) {
            VStack(alignment: .leading, spacing: 10) {
                Text("REPAYMENT PERIOD (MONTHS)").capsLabel()
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

    private var payoutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAY THE LOAN INTO").capsLabel()
            ForEach(a.payoutAccounts) { (acc: LoanPayoutAccount) in
                ChoiceCard(title: acc.name, subtitle: "Balance " + cur.tidyShort(acc.balance), selected: payInto == acc.id) { payInto = acc.id }
            }
        }
    }

    @ViewBuilder private var figures: some View {
        StatStrip(cells: [
            .init(label: "Each month", value: cur.tidyShort(q.monthlyPayment)),
            .init(label: "Interest in all", value: cur.tidyShort(q.totalInterest)),
            .init(label: "Paid out", value: cur.tidyShort(q.disbursal), tint: P.gain),
        ], ruled: false)
        .padding(.vertical, 10).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(P.line, lineWidth: 1))
    }
}

/// The amount on ivory: the figure, a slider from the smallest loan to the maximum, and quick choices (25%, 50%, 75%, Maximum).
private struct LoanAmountPanel: View {
    @Environment(\.outsidePalette) private var P
    var cur: Currency
    var amount: Double
    var minimum: Double
    var maximum: Double
    var slider: Binding<Double>
    var setFraction: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose amount").font(.system(size: 12.5)).foregroundStyle(P.inkSoft)
            Text(cur.tidyDisplay(amount)).font(.hero(34)).foregroundStyle(P.ink).minimumScaleFactor(0.6).lineLimit(1)
                .accessibilityIdentifier("bank-loan-amount")
            if maximum > minimum {
                Slider(value: slider, in: minimum...maximum).tint(P.accent)
                    .accessibilityIdentifier("bank-loan-slider")
                HStack {
                    Text(cur.tidyShort(minimum)).font(.system(size: 11)).foregroundStyle(P.inkFaint)
                    Spacer()
                    Text(cur.tidyShort(maximum)).font(.system(size: 11)).foregroundStyle(P.inkFaint)
                }
            }
            HStack(spacing: 8) {
                chip("25%", 0.25)
                chip("50%", 0.5)
                chip("75%", 0.75)
                chip("Maximum", 1)
            }
            Text("The bank approved up to " + cur.tidyDisplay(maximum) + ". You can borrow less.").font(.system(size: 11.5)).foregroundStyle(P.inkFaint)
        }
    }

    private func chip(_ title: String, _ fraction: Double) -> some View {
        Button {
            Haptics.choose()
            setFraction(fraction)
        } label: {
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(P.accent).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 34)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(P.accent, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bank-loan-chip-" + title.lowercased())
    }
}

// MARK: Stage 2: Agreement (papers)

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
            QuietButton(title: "Continue to confirmation", fullWidth: true, action: next)
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

// MARK: Stage 2: Confirm

private struct LoanStepSummary: View {
    @Environment(\.outsidePalette) private var P
    var q: LoanApplicationQuote
    var cur: Currency
    var payIntoName: String
    var personalGuarantee: Bool
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
            if approved == nil {
                QuietButton(title: "Confirm and pay into " + payIntoName, fullWidth: true, action: onApply)
                    .accessibilityIdentifier("bank-loan-confirm")
            } else {
                QuietButton(title: "Done", fullWidth: true, action: onDone)
                    .accessibilityIdentifier("bank-loan-done")
            }
        }
    }

    private var approvedBanner: some View {
        HStack(spacing: 10) {
            GlyphView(glyph: "M5 12 L10 17 L19 7", size: 18, weight: 2, tint: P.gain)
            Text("Approved. \(cur.tidyDisplay(q.disbursal)) has been paid into \(payIntoName).").font(.system(size: 13)).foregroundStyle(P.ink)
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
                line("Paid into", payIntoName)
                line("Disbursal amount", cur.tidyDisplay(q.disbursal), tint: P.gain, strong: true)
                if personalGuarantee { line("Guarantee", "You are personally liable") }
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

    private func line(_ label: String, _ value: String, tint: Color? = nil, strong: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 13.5)).foregroundStyle(strong ? P.ink : P.inkSoft)
            Spacer(minLength: 8)
            Text(value).font(.system(size: strong ? 16 : 14, weight: strong ? .medium : .regular).monospacedDigit()).foregroundStyle(tint ?? P.ink)
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
