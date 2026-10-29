import SwiftUI

/// The one place that turns a `CompanyRoute` into a screen. Company, Team and Group each keep their own navigation stack
/// (so Back returns to the tab you came from) but share these destinations, so a company opens the same way everywhere.
struct CompanyRouteDestination: View {
    var route: CompanyRoute

    var body: some View {
        Group {
            switch route {
            case .company(let id): CompanyDetailView(companyID: id)
            case .companyAt(let id, let sec): CompanyDetailView(companyID: id, initialSection: sec)
            case .newCompany: NewCompanyView()
            case .market: MarketView()
            }
        }
        // A fresh view per route: replacing the path with another company (or the same company on another section) must not
        // keep the previous screen's state, such as its selected section.
        .id(route)
    }
}

extension View {
    /// Adds the shared company destinations to the navigation stack this view is in.
    func companyRouteDestinations() -> some View {
        navigationDestination(for: CompanyRoute.self) { route in CompanyRouteDestination(route: route) }
    }
}
