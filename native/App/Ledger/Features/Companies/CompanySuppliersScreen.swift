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

    @ViewBuilder private func suppliersBody(_ e: GameEngine, _ co: Company) -> some View {
        if CompanySourcing.isAvailable(engine: e, company: co) {
            CompanySourcing(engine: e, company: co)
        } else {
            EmptyState(glyph: Glyph.suppliers, title: "No suppliers yet", message: "They show here once the business is open.")
        }
    }

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            ScrollView {
                suppliersBody(e, co)
                    .padding(.horizontal, Theme.Space.page).padding(.top, Theme.Space.s).padding(.bottom, Theme.Space.l)
                    .frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .appScreen(title: "Suppliers", subtitle: co.name, tab: .company)
        } else {
            EmptyState(glyph: Glyph.home, title: "This company no longer exists").frame(maxWidth: .infinity, maxHeight: .infinity).ledgerBackground()
        }
    }
}
