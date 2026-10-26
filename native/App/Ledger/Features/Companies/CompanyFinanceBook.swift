import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// The book of an insurance company, bank or investment fund: policies, loans and deposits, or assets under management.
/// Flat rows between hairlines, no boxes.
struct CompanyFinanceBook: View {
    @EnvironmentObject var store: GameStore
    var engine: GameEngine
    var company: Company
    @State private var pending: PendingAction?

    var body: some View {
        let cur = engine.currency(for: company)
        if let b = engine.financeBook(companyID: company.id) {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if b.underRegulator { regulator(b) }
                switch b.kind {
                case .insurer: insurer(b, cur)
                case .bank: bank(b, cur)
                case .fund: fund(b, cur)
                }
            }
            .confirmAction($pending)
        } else {
            LedgerSection("Book") { Text("This company has no book of business to show yet.").font(.bodyText).foregroundStyle(Theme.ivoryMuted) }
        }
    }

    private func regulator(_ b: FinanceBook) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "exclamationmark.shield.fill").font(.system(size: 15)).foregroundStyle(Theme.loss).padding(.top, 2)
            Text(b.kind == .insurer ? "The regulator restricts the company: solvency is too low, so new business is cut in half. Put capital into the company under Finances."
                                    : "The regulator warns about the capital ratio. Put equity into the company under Finances, or lend less.")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivory).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    // MARK: Insurance

    private func insurer(_ b: FinanceBook, _ cur: Currency) -> some View {
        let products = engine.insuranceProducts(companyID: company.id)
        let sellers = engine.salespeople(companyID: company.id)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            KeyFigures(items: [
                .init(label: "Policies", value: String(Int(b.policies.rounded()))),
                .init(label: "Premiums a week", value: cur.tidyShort(b.weeklyPremium), sub: cur.tidyShort(b.weeklyPremium * 52) + " a year"),
                .init(label: "Claims vs premiums", value: Currency.percent(b.lossRatio, decimals: 0), tint: b.lossRatio > 0.9 ? Theme.loss : Theme.ivory, sub: "loss ratio"),
                .init(label: "Solvency", value: String(format: "%.2f", b.solvency), tint: b.solvency < 1 ? Theme.loss : Theme.ivory, sub: "needs 1.0"),
                .init(label: "Storm claims", value: cur.tidyShort(b.claimsPaidByStorms), sub: "so far"),
            ])
            LedgerSection("Products") {
                VStack(spacing: 0) {
                    ForEach(Array(products.enumerated()), id: \.element.id) { n, p in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.system(size: 14.5)).foregroundStyle(Theme.ivory)
                                Text(p.status + (p.isOffered ? " · verified sellers \(String(format: "%.1f", p.verifiedSellers))" : " · approval " + cur.tidyShort(p.approvalFee)))
                                    .font(.caption).foregroundStyle(p.status == "Live" ? Theme.gain : Theme.ivoryFaint)
                            }
                            Spacer(minLength: 8)
                            Button(p.isOffered ? "Stop selling" : "Offer…") { confirmToggle(p, cur) }
                                .buttonStyle(QuietButtonStyle(tint: p.isOffered ? Theme.loss : Theme.gold))
                        }
                        .padding(.vertical, 9)
                        if n < products.count - 1 { Hairline() }
                    }
                }
                Text("Each product needs the regulator's approval, and each salesperson must be verified for it before they sell it. Big storms can hit many policies at once; premiums minus claims is your profit. Your other companies can buy insurance here.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
            if sellers.isEmpty {
                LedgerSection("Salespeople") {
                    Text("No salespeople yet. Hire agents under Team; each is verified per product before they sell it.").font(.bodyText).foregroundStyle(Theme.ivoryMuted)
                }
            } else {
                LedgerSection("Salespeople") {
                    VStack(spacing: 0) {
                        ForEach(Array(sellers.enumerated()), id: \.element.id) { n, s in
                            HStack(alignment: .firstTextBaseline) {
                                Text(s.name).font(.system(size: 14.5)).foregroundStyle(Theme.ivory)
                                Spacer(minLength: 8)
                                Menu {
                                    ForEach(products.filter { $0.isOffered }) { p in
                                        Button(p.name + (s.verified[p.id] != nil ? " (verified or in progress)" : "")) { verify(s.id, p) }
                                    }
                                } label: {
                                    Text("Verify for…  ⌄").font(.system(.subheadline).weight(.semibold)).foregroundStyle(Theme.gold)
                                        .padding(.horizontal, 14).padding(.vertical, 8).overlay(Capsule().strokeBorder(Theme.gold.opacity(0.45), lineWidth: 0.75))
                                }
                                .disabled(products.allSatisfy { !$0.isOffered })
                            }
                            .padding(.vertical, 9)
                            if n < sellers.count - 1 { Hairline() }
                        }
                    }
                }
            }
        }
    }

    // MARK: Bank

    private func bank(_ b: FinanceBook, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            KeyFigures(items: [
                .init(label: "Deposits", value: cur.tidyShort(b.deposits), sub: "owed to savers"),
                .init(label: "Loans to customers", value: cur.tidyShort(b.loans)),
                .init(label: "Loans to your group", value: cur.tidyShort(b.groupLoans)),
                .init(label: "Capital ratio", value: Currency.percent(b.capitalRatio, decimals: 1), tint: b.capitalRatio < b.requiredRatio ? Theme.loss : Theme.ivory, sub: "minimum " + Currency.percent(b.requiredRatio, decimals: 0)),
                .init(label: "Equity", value: cur.tidyShort(b.equity), tint: b.equity < 0 ? Theme.loss : Theme.ivory),
                .init(label: "Central bank", value: cur.tidyShort(b.centralBankLoan), tint: b.centralBankLoan > 0 ? Theme.caution : Theme.ivory, sub: "liquidity loan"),
            ])
            LedgerSection("How the bank earns") {
                Meter(label: "Capital", value: min(1, b.requiredRatio > 0 ? b.capitalRatio / (b.requiredRatio * 2) : 0))
                Text("The bank earns the gap between what borrowers pay and what savers are paid. Bad loans reduce capital, and rumours can start a run on deposits: a solvent bank short of cash borrows from the central bank and repays as deposits come back. Choose the loan book and funding under Operations. Your other companies borrow cheaper here.")
                    .font(.caption2).foregroundStyle(Theme.ivoryFaint)
            }
        }
    }

    // MARK: Fund

    private func fund(_ b: FinanceBook, _ cur: Currency) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            KeyFigures(items: [
                .init(label: "Assets managed", value: cur.tidyShort(b.assetsUnderManagement), sub: "investors' money"),
                .init(label: "Fee income", value: cur.tidyShort(b.assetsUnderManagement * b.managementFee / 52), sub: "a week, " + Currency.percent(b.managementFee, decimals: 1) + " a year"),
                .init(label: "Unit value", value: String(format: "%.3f", b.unitValue), tint: Theme.change(b.unitValue - 1)),
                .init(label: "High-water mark", value: String(format: "%.3f", b.highWaterMark), sub: b.unitValue > b.highWaterMark * 1.04 ? "fee due at year end" : "fee above +4%"),
                .init(label: "Performance fee", value: Currency.percent(b.performanceFee, decimals: 0), sub: "of gains above the mark"),
            ])
            Text("You earn a fee on the assets every week and a performance fee at year end when the fund has beaten its high-water mark by 4%. Money flows in when returns are good and out when they are poor; the strategy and fee class under Operations decide how much risk you take and how many investors you attract.")
                .font(.caption2).foregroundStyle(Theme.ivoryFaint)
        }
    }

    // MARK: Actions

    private func confirmToggle(_ p: ProductRow, _ cur: Currency) {
        if p.isOffered {
            pending = PendingAction(title: "Stop selling \(p.name)?", message: "Existing policies run on, but no new ones are written. Selling again needs the regulator's approval and its fee again.", button: "Stop selling", destructive: true) { toggle(p) }
        } else {
            pending = PendingAction(title: "Offer \(p.name)?", message: "Costs the approval fee of \(cur.tidyDisplay(p.approvalFee)) from company cash. Sales start once the regulator approves and your salespeople are verified for it.", button: "Apply for \(cur.tidyShort(p.approvalFee))", amount: p.approvalFee, currency: cur) { toggle(p) }
        }
    }

    private func toggle(_ p: ProductRow) {
        switch store.act({ $0.setInsuranceProduct(companyID: company.id, product: p.id, offered: !p.isOffered) }) {
        case .ok?: Haptics.success(); store.show(p.isOffered ? "\(p.name): no longer sold." : "\(p.name): applied for approval.", tone: "good")
        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash for the approval fee.", tone: "warn")
        default: Haptics.warning(); store.show("That product cannot be changed now.", tone: "warn")
        }
    }

    private func verify(_ personID: Int, _ p: ProductRow) {
        switch store.act({ $0.verifySalesperson(companyID: company.id, personID: personID, product: p.id) }) {
        case .ok?: Haptics.success(); store.show("Verification for \(p.name) started: a few weeks.", tone: "good")
        case .notEnoughCash?: Haptics.warning(); store.show("Not enough cash for the verification.", tone: "warn")
        default: Haptics.warning(); store.show("That salesperson cannot be verified for this product.", tone: "warn")
        }
    }
}
