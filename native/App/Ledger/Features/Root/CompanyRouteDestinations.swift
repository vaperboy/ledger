import SwiftUI

/// The one place that turns a `CompanyRoute` into a screen. Company, Team and Group each keep their own navigation stack
/// (so Back returns to the tab you came from) but share these destinations, so a company opens the same way everywhere.
struct CompanyRouteDestination: View {
    var route: CompanyRoute

    var body: some View {
        Group {
            switch route {
            case .company(let id): CompanyDetailView(companyID: id)
            case .companyAt(let id, let sec): CompanyPage(companyID: id, section: sec, part: nil)
            case .companyPart(let id, let sec, let part): CompanyPage(companyID: id, section: sec, part: part)
            case .newCompany: NewCompanyView()
            case .market: MarketView()
            }
        }
        // A fresh view per route: a link that changes the part of a screen already on the stack must not keep that screen's old state.
        .id(route)
    }
}

extension View {
    /// Adds the shared company destinations to the navigation stack this view is in.
    func companyRouteDestinations() -> some View {
        navigationDestination(for: CompanyRoute.self) { route in CompanyRouteDestination(route: route) }
    }
}

/// A link to one page of a company: a section of the company screen opens it on that section; a page of its own (Marketing, Customers,
/// Setup, Plant ...) is pushed; a page this company does not have opens its Overview.
struct CompanyPage: View {
    @EnvironmentObject var store: GameStore
    var companyID: Int
    var section: CompanySection
    var part: String?

    var body: some View {
        if let e = store.engine, let co = e.state.company(companyID) {
            if let tab = CompanyDetailView.tab(for: section, co, e) {
                CompanyDetailView(companyID: companyID, initial: tab, part: part)
            } else if CompanyDetailView.availableSections(co, e).contains(section) {
                CompanySectionScreen(companyID: companyID, section: section)
            } else {
                CompanyDetailView(companyID: companyID)
            }
        } else {
            CompanyDetailView(companyID: companyID)
        }
    }
}
