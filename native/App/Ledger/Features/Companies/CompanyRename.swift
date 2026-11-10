import SwiftUI
import GameCore
import Businesses
import Countries
import Simulation

struct CompanyRenameHost: ViewModifier {
    var companyID: Int
    @Binding var isPresented: Bool
    @EnvironmentObject var store: GameStore
    @State private var name = ""
    @State private var pending: PendingAction?
    @State private var shortOfGold = false
    @State private var shortNeed = 0
    @State private var showPacks = false

    static var skipPrice: Int { GoldPrices.service("companyNameSkip") }

    func body(content: Content) -> some View {
        content
            .confirmAction($pending)
            .centerSheet(isPresented: $isPresented, title: "Company name") { card }
            .centerSheet(isPresented: $shortOfGold, title: "Not enough gold") { ShortOfGoldCard(needed: shortNeed, onPacks: { shortOfGold = false; showPacks = true }) }
            .navigationDestination(isPresented: $showPacks) { StoreApp() }
            .onChange(of: isPresented) { _, now in if now { name = "" } }
    }

    @ViewBuilder private var card: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            let left: Int = e.renameCooldownLeft(companyID: co.id)
            let cur = e.currency(for: co)
            let cost: Double = e.renameCost(companyID: co.id)
            let clean: String = name.trimmingCharacters(in: .whitespaces)
            if e.chainOf(companyID: co.id) != nil {
                Text("This store carries its chain's name. Rebranding the whole chain is done from the chain.").textStyle(.body, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true)
            } else {
                RenameCard(placeholder: co.name,
                           text: $name,
                           note: left > 0 ? "The name can change again in \(left) \(left == 1 ? "week" : "weeks"). Costs \(cur.tidyDisplay(cost))."
                                          : "Costs \(cur.tidyDisplay(cost)); about a third of customers lose track of you. Then you wait \(GameEngine.renameCooldownWeeks) weeks.",
                           buttonTitle: left > 0 ? "Change now \u{00B7} \(StoreText.gold(Self.skipPrice))" : "Change name",
                           enabled: clean.count >= 2, capitalization: .words, identifier: "company-name",
                           onSubmit: { if left > 0 { skipAndRename(clean) } else { confirmRename(clean, cost, cur) } }) { EmptyView() }
            }
        }
    }

    private func confirmRename(_ name: String, _ cost: Double, _ cur: Currency) {
        isPresented = false
        StorePurchase.afterPopup {
            pending = PendingAction(title: "Rename to \u{201C}\(name)\u{201D}?", message: "Costs \(cur.tidyDisplay(cost)) and some awareness: customers have to learn the new name.", button: "Rename", amount: cost, currency: cur, tone: .info, icon: "pencil") {
                rename(name, skip: false)
            }
        }
    }

    private func skipAndRename(_ name: String) {
        isPresented = false
        StorePurchase.afterPopup {
            StorePurchase.ask(.service("Skip the name wait", Self.skipPrice), pending: $pending, onShort: { (price: Int) in shortNeed = price; shortOfGold = true }, then: { (done: Bool) in
                if done { rename(name, skip: true) }
            })
        }
    }

    private func rename(_ name: String, skip: Bool) {
        let id: Int = companyID
        switch store.act({ $0.renameCompany(companyID: id, to: name, skipCooldown: skip) }) {
        case .ok?: Haptics.success(); store.show("Now called \(name).", tone: "good")
        case .tooShort?: Haptics.warning(); store.show("Choose a different name of at least two letters.", tone: "warn")
        case .nameTaken?: Haptics.warning(); store.show("Another company already has that name.", tone: "warn")
        case .notEnoughCash?: Haptics.warning(); store.show("The company does not have the cash for new signs.", tone: "warn")
        case .partOfChain?: Haptics.warning(); store.show("A chain store carries the chain's name.", tone: "warn")
        case .cooldown?: Haptics.warning(); store.show("The name cannot change yet.", tone: "warn")
        case nil: break
        default: Haptics.warning(); store.show("It cannot be renamed now.", tone: "warn")
        }
    }
}

extension View {
    func companyRename(companyID: Int, isPresented: Binding<Bool>) -> some View {
        modifier(CompanyRenameHost(companyID: companyID, isPresented: isPresented))
    }
}
