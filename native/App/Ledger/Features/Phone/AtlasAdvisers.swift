import SwiftUI
import GameCore
import Countries
import Businesses
import Simulation

/// Atlas > the company's accountant: who keeps the books now and the others on offer (name, fee, rating). The accountant also runs payroll, so the
/// choice shows in Accounting > Payroll and Settings. A switch is confirmed with the monthly fee first.
struct AtlasAccountantSection: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.outsidePalette) private var P
    var companyID: Int
    @State private var pending: PendingAction?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let cur: Currency = e.currency(for: co)
            let choices: [AdviserOption] = e.adviserChoices(companyID: companyID, kind: .accountant)
            let now: AdviserOption? = choices.first { (a: AdviserOption) -> Bool in a.isCurrent }
            ShopSection(title: "On offer", trailing: now.map { (a: AdviserOption) -> String in "Now " + cur.tidyShort(a.monthlyFee) + " a month" } ?? "") {
                if choices.isEmpty { LoadingState(text: "Finding accountants") }
                ForEach(choices) { (a: AdviserOption) in
                    ShopChoiceRow(title: a.name, subtitle: subtitle(a, cur), trailing: "\u{2605} " + String(format: "%.1f", a.rating), selected: a.isCurrent,
                                  identifier: "atlas-accountant-\(a.id)") { ask(a, now, cur) }
                }
            }
            .confirmAction($pending)
            .task { store.act { $0.prepareAdvisers(companyID: companyID) } }
        }
    }

    private func subtitle(_ a: AdviserOption, _ cur: Currency) -> String {
        var text: String = cur.tidyShort(a.monthlyFee) + " a month"
        if let err = a.errorRate { text += " \u{00B7} books wrong " + String(format: "%.0f", err * 100) + "% of the time" }
        if a.ownFirmID != nil { text += " \u{00B7} your own firm" }
        if a.isCurrent { text = "Yours \u{00B7} " + text }
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
