import SwiftUI
import GameCore
import Businesses
import Simulation

extension CompanySourcing {
    /// Whether this company has any input to source or sells to a company of yours (the same test the section uses to show itself).
    static func isAvailable(engine: GameEngine, company: Company) -> Bool {
        guard company.status.isLive else { return false }
        let hasInputs: Bool = !engine.supplierInputs(companyID: company.id).isEmpty
        let sells: Bool = engine.supplyLinks().contains { $0.supplierID == company.id }
        return hasInputs || sells
    }
}

/// The supplier comparison of one company as a screen of its own (opened from "Compare suppliers" and from More).
struct CompanySuppliersScreen: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            ScrollView {
                CompanySourcing(engine: e, company: co)
                    .padding(.horizontal, Theme.Space.margin).padding(.top, Theme.Space.s).padding(.bottom, 40)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: "Suppliers", subtitle: co.name, tab: .company)
        } else {
            Text("This company no longer exists.").foregroundStyle(Theme.ivoryMuted).frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }
}
