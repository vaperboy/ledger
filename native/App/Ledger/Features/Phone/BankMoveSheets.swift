import SwiftUI
import GameCore
import Countries
import Finance
import Simulation

@MainActor
enum BankPay {
    static func early(_ store: GameStore, _ o: Obligation) {
        guard let outcome = store.act({ $0.payObligationNow(o) }) else { return }
        let cur: Currency? = store.engine.flatMap { e in e.state.company(o.companyID).map { e.currency(for: $0) } }
        switch outcome {
        case .paid(let amount):
            let text: String = cur?.tidyShort(amount) ?? store.short(amount)
            store.settle(.applied, "\(text) paid: \(o.title.tidyText). Nothing more is taken on its date.", tone: "good")
            Haptics.success()
        case .refused(let why):
            store.settle(.refused(why), "")
        }
    }

    static func instalment(_ store: GameStore, loanID: Int) {
        guard let e = store.engine, let l = e.state.loans.first(where: { $0.id == loanID }) else { store.show("That loan is already paid off.", tone: "n"); return }
        let cur: Currency = l.companyID == 0 ? e.homeCurrency : (e.state.company(l.companyID).map { e.currency(for: $0) } ?? e.homeCurrency)
        let result: Banking.EarlyInstalment? = store.act({ (g: inout GameEngine) -> Banking.EarlyInstalment in g.payLoanInstalmentNow(loanID: loanID) })
        switch result {
        case .paid(let amount)?:
            Haptics.success(); store.show("\(cur.tidyShort(amount)) paid on \(l.name). It is not taken again at month end.", tone: "good")
        case .alreadySettled?:
            store.show("This month's instalment of \(l.name) is already paid.", tone: "n")
        case .notEnoughMoney?:
            Haptics.warning(); store.show("Not enough money to pay that instalment now.", tone: "warn")
        case .noLoan?:
            store.show("That loan is already paid off.", tone: "n")
        case nil:
            break
        }
    }
}
