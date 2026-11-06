import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

/// Turning a sole trader into a limited company, as a review and then ONE confirmed transaction. The preview is the engine's dry run
/// (`conversionPlan`): requirements, costs, who pays the fee (personal or company account, with balances and any shortfall), what changes in the
/// ownership and the books, and that the loan guarantees stay. The owner always pays the share capital personally. Cancelling changes nothing.
struct ConversionSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var companyID: Int
    @State private var payer: CompanyConversion.Payer = .personal
    @State private var accountantID: Int?
    @State private var pending: PendingAction?
    @State private var done: String?

    var body: some View {
        Group {
            Group {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    if let e = store.engine, let co = e.state.company(companyID) {
                        if let done {
                            resultCard(done)
                        } else if let plan = e.conversionPlan(companyID: companyID, payer: payer, accountantID: accountantID) {
                            if let why = plan.blocked { blockedCard(why) } else { review(e, co, plan) }
                        } else {
                            blockedCard(.unknownCountry)
                        }
                    } else {
                        Text("This company no longer exists.").popupText(.body)
                    }
                }
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
        }
        .confirmAction($pending)
    }

    // MARK: Review

    @ViewBuilder private func review(_ e: GameEngine, _ co: Company, _ plan: CompanyConversion.Plan) -> some View {
        let cur: Currency = e.currency(for: co)
        header(plan)
        costs(plan, cur)
        accountantChoice(co, plan, cur)
        payerChoice(plan, cur)
        changes(plan, cur)
        loans(plan, cur)
        figures(plan, cur)
        consequences(plan)
        decision(co, plan, cur)
    }

    private func header(_ plan: CompanyConversion.Plan) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 6) {
                Text("Convert").capsLabel()
                Text(plan.companyName).popupText(.figure).lineLimit(2)
                Text("From \(plan.currentFormName) to \(plan.newFormName). Nothing happens until you confirm.")
                    .popupText(.subtitle)
            }
        }
    }

    private func costs(_ plan: CompanyConversion.Plan, _ cur: Currency) -> some View {
        let total: Double = plan.fee + plan.shareCapital
        return PopupSection(title: "Costs") {
            FlatRow(label: "Conversion fee", value: cur.tidyDisplay(plan.fee), sub: "paid from the account you choose below", rule: false)
            FlatRow(label: "Share capital", value: cur.tidyDisplay(plan.shareCapital), sub: "paid by you personally; it becomes the company's capital")
            if plan.accountantRequired {
                FlatRow(label: "Accountant", value: cur.tidyShort(plan.accountantMonthlyFee) + " a month", sub: plan.accountantName + ": the legal form requires one")
            }
            FlatRow(label: "Total paid now", value: cur.tidyDisplay(total), tint: Theme.ivory)
        }
    }

    @ViewBuilder private func accountantChoice(_ co: Company, _ plan: CompanyConversion.Plan, _ cur: Currency) -> some View {
        if plan.accountantRequired { AccountantStep(countryCode: co.countryCode, currency: cur, accountantID: $accountantID) }
    }

    private func payerChoice(_ plan: CompanyConversion.Plan, _ cur: Currency) -> some View {
        PopupSection(title: "Who pays the fee") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.payerOptions) { (o: CompanyConversion.PayerOption) in
                    let title: String = o.payer == .personal ? "Your own account" : "The company's account"
                    let avail: String = o.accountName + ": " + cur.tidyDisplay(o.spendable) + " available"
                    let short: String = o.affordable ? "" : ", short by " + cur.tidyDisplay(o.shortfall)
                    let sub: String = avail + short
                    ChoiceCard(title: title, subtitle: sub, trailing: "needs " + cur.tidyShort(o.needed), selected: payer == o.payer) { payer = o.payer }
                        .accessibilityIdentifier("conversion-payer-" + o.payer.rawValue)
                }
                Text("The personal option also covers the share capital, so it needs both from your own account and savings.").popupText(.caption)
            }
        }
    }

    private func changes(_ plan: CompanyConversion.Plan, _ cur: Currency) -> some View {
        PopupSection(title: "What changes") {
            FlatRow(label: "Legal form", value: plan.newFormName, sub: "was " + plan.currentFormName, rule: false)
            if plan.nameAfter != plan.nameBefore { FlatRow(label: "Name", value: plan.nameAfter, sub: "was " + plan.nameBefore) }
            FlatRow(label: "Ownership", value: Currency.percent(plan.ownerSharePercent / 100, decimals: 0), sub: "you hold \(Int(plan.shareCount)) shares of " + cur.tidyShort(plan.shareNominal) + " each")
            if abs(plan.profitClosedIntoPersonalTax) > 0.5 {
                FlatRow(label: "Profit so far this year", value: cur.tidyShort(plan.profitClosedIntoPersonalTax), sub: "closed into your personal tax return; company tax starts from zero")
            }
            if plan.contributedCapitalCarried > 0.5 {
                FlatRow(label: "Capital you put in", value: cur.tidyShort(plan.contributedCapitalCarried), sub: "carried over, so dividends are taxed correctly")
            }
        }
    }

    @ViewBuilder private func loans(_ plan: CompanyConversion.Plan, _ cur: Currency) -> some View {
        if !plan.loans.isEmpty {
            PopupSection(title: "Loans") {
                VStack(spacing: 0) {
                    ForEach(Array(plan.loans.enumerated()), id: \.element.id) { n, l in
                        FlatRow(label: l.name, value: cur.tidyShort(l.balance), sub: l.personallyGuaranteed ? "your personal guarantee stays" : "company loan", rule: n > 0)
                    }
                    Text("Banks keep the personal guarantee; ask to release it in the Bank app, at a higher margin.")
                        .popupText(.caption).padding(.top, 6)
                }
            }
        }
    }

    private func figures(_ plan: CompanyConversion.Plan, _ cur: Currency) -> some View {
        PopupSection(title: "After the conversion") {
            KeyFigures(items: [
                .init(label: "Your account", value: cur.tidyShort(plan.personalBalanceAfter), tint: plan.personalBalanceAfter < 0 ? Theme.loss : Theme.ivory),
                .init(label: "Company account", value: cur.tidyShort(plan.companyBalanceAfter), tint: plan.companyBalanceAfter < 0 ? Theme.loss : Theme.ivory),
                .init(label: "Company value", value: cur.tidyShort(plan.valueAfter), sub: "was " + cur.tidyShort(plan.valueBefore)),
            ])
            Text("The value does not change by converting, and it is an estimate, not cash.").popupText(.caption)
        }
    }

    @ViewBuilder private func consequences(_ plan: CompanyConversion.Plan) -> some View {
        if !plan.consequences.isEmpty {
            PopupSection(title: "Consequences") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(plan.consequences.enumerated()), id: \.offset) { _, c in
                        Text(c.tidyText).popupText(.subtitle)
                    }
                }
            }
        }
    }

    /// The risk line stays in the body; Keep and Convert are pinned under it so they are always in reach.
    @ViewBuilder private func decision(_ co: Company, _ plan: CompanyConversion.Plan, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !plan.affordable {
                Text("The chosen account cannot cover this: pick the other or put money in. Nothing is charged.")
                    .popupText(.risk)
                    .accessibilityIdentifier("conversion-unaffordable")
            }
        }
        .popupFooter {
            PopupFooter(cancel: "Keep it as it is", action: "Convert to a limited company\u{2026}", onCancel: { dismiss() }, onAction: { confirm(co, plan, cur) },
                        actionEnabled: plan.affordable, cancelID: "conversion-keep", actionID: "conversion-confirm")
        }
    }

    // MARK: Confirm and result

    private func confirm(_ co: Company, _ plan: CompanyConversion.Plan, _ cur: Currency) {
        let id: Int = co.id
        let chosen: CompanyConversion.Payer = payer
        let accountant: Int? = accountantID
        let total: Double = plan.fee + plan.shareCapital
        var message: String = "Cost: \(cur.tidyDisplay(plan.fee)) fee from \(plan.accountToCharge) and \(cur.tidyDisplay(plan.shareCapital)) share capital from you, \(cur.tidyDisplay(total)) in all. "
        message += "Effect: \(plan.nameAfter) becomes a limited company; you hold \(Currency.percent(plan.ownerSharePercent / 100, decimals: 0)) of its shares; "
        message += plan.accountantRequired ? "\(plan.accountantName) is appointed at \(cur.tidyShort(plan.accountantMonthlyFee)) a month. " : "its accountant stays. "
        message += "Risk: it cannot be undone, and your personal guarantee on its loans stays."
        pending = PendingAction(title: "Convert \(plan.companyName) to a limited company?", message: message, button: "Convert", destructive: true) {
            run(id, chosen, accountant, plan, cur)
        }
    }

    private func run(_ id: Int, _ chosen: CompanyConversion.Payer, _ accountant: Int?, _ plan: CompanyConversion.Plan, _ cur: Currency) {
        let result: GameEngine.ConvertResult? = store.act({ (e: inout GameEngine) -> GameEngine.ConvertResult in e.convertToLimited(companyID: id, payer: chosen, accountantID: accountant) })
        switch result {
        case .ok?:
            Haptics.success()
            let from: String = plan.accountToCharge
            done = "\(plan.companyName) is now \(plan.nameAfter), a limited company. The \(cur.tidyDisplay(plan.fee)) fee was paid from \(from) and you paid \(cur.tidyDisplay(plan.shareCapital)) share capital."
            store.show("\(plan.nameAfter) is now a limited company.", tone: "good")
        case .notEnoughCash?:
            Haptics.warning()
            store.show("The chosen account cannot cover the conversion. Nothing was charged.", tone: "warn")
        case .alreadyLimited?:
            store.show("It is already a limited company.", tone: "n")
        case .notAllowed(let why)?:
            Haptics.warning()
            store.show(why.text, tone: "warn")
        case .unknown?:
            Haptics.warning()
            store.show("It cannot be converted now.", tone: "warn")
        case nil:
            break
        }
    }

    private func resultCard(_ text: String) -> some View {
        Group {
            HStack(alignment: .top, spacing: 12) {
                IconCircle(glyph: Glyph.check, tint: Theme.gain)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Converted").popupText(.rowValue)
                    Text(text.tidyText).popupText(.subtitle)
                    Text("Form, name and records are updated; see Accounting > Documents for the registration.")
                        .popupText(.caption)
                }
            }
        }
    }

    private func blockedCard(_ block: CompanyConversion.Block) -> some View {
        Group {
            HStack(alignment: .top, spacing: 12) {
                IconCircle(glyph: Glyph.info)
                Text(block.text).popupText(.body)
            }
        }
    }
}
