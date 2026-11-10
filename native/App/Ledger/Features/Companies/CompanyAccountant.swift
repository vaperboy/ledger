import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

struct CompanyAccountantScreen: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let cur: Currency = e.currency(for: co)
            let choices: [AdviserOption] = e.adviserChoices(companyID: companyID, kind: .accountant)
            let now: AdviserOption? = choices.first { (a: AdviserOption) -> Bool in a.isCurrent }
            PhonePageScroll(spacing: Theme.Space.l) {
                LedgerSection(title: "On offer", trailing: {
                    Text(now.map { (a: AdviserOption) -> String in "Now " + cur.tidyShort(a.monthlyFee) + " a month" } ?? "").textStyle(.caption)
                }, content: {
                    if choices.isEmpty { LoadingState(text: "Finding accountants") }
                    ForEach(choices) { (a: AdviserOption) in
                        LedgerRow(leading: .glyph(Glyph.reports), title: a.name, subtitle: subtitle(a, cur),
                                  value: "\u{2605} " + String(format: "%.1f", a.rating), pill: a.isCurrent ? "Yours" : nil, pillTone: .good,
                                  identifier: "accountant-\(a.id)") { ask(a, now, cur) }
                    }
                })
                Text("Keeps the books for \(co.name). The fee is paid monthly from company cash.")
                    .textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            .confirmAction($pending)
            .task { store.act { $0.prepareAdvisers(companyID: companyID) } }
            .appScreen(title: "Accountant", subtitle: co.name)
        } else {
            EmptyState(glyph: Glyph.home, title: "This company no longer exists").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }

    private func subtitle(_ a: AdviserOption, _ cur: Currency) -> String {
        var text: String = cur.tidyShort(a.monthlyFee) + " a month"
        if let err = a.errorRate { text += " \u{00B7} books wrong " + String(format: "%.0f", err * 100) + "% of the time" }
        if a.ownFirmID != nil { text += " \u{00B7} your own firm" }
        return text
    }

    private func ask(_ a: AdviserOption, _ now: AdviserOption?, _ cur: Currency) {
        if a.isCurrent { return }
        let id: Int = companyID
        let leaves: String = now.map { (n: AdviserOption) -> String in " " + n.name + " leaves." } ?? ""
        let message: String = cur.tidyShort(a.monthlyFee) + " a month from company cash." + leaves
        pending = PendingAction(title: "Appoint " + a.name + "?", message: message, button: "Appoint", amount: a.monthlyFee, currency: cur, tone: .info, icon: "person.text.rectangle") {
            apply(a, companyID: id)
        }
    }

    private func apply(_ a: AdviserOption, companyID id: Int) {
        if let firm = a.ownFirmID {
            let r: Advisers.Result? = store.act({ (e: inout GameEngine) -> Advisers.Result in e.chooseOwnAdviser(companyID: id, kind: .accountant, firmID: firm) })
            if r == .done { Haptics.success(); store.show(a.name + " is your accountant.", tone: "good") } else { Haptics.warning(); store.show("That firm is not available.", tone: "warn") }
            return
        }
        let r: SettingResult? = store.act({ (e: inout GameEngine) -> SettingResult in e.setAccountant(companyID: id, accountantID: a.id) })
        switch r {
        case .applied?:
            Haptics.success()
            store.show(a.name + " is your accountant.", tone: "good")
        case .refused(let why)?:
            Haptics.warning()
            store.show(why, tone: "warn")
        case .unchanged?, nil:
            break
        }
    }
}
