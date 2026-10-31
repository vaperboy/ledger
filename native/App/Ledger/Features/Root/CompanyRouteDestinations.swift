import SwiftUI

/// The one place that turns a `CompanyRoute` into a screen. Company, Team and Group each keep their own navigation stack
/// (so Back returns to the tab you came from) but share these destinations, so a company opens the same way everywhere.
struct CompanyRouteDestination: View {
    var route: CompanyRoute

    var body: some View {
        Group {
            switch route {
            case .company(let id): CompanyDetailView(companyID: id)
            case .companyAt(let id, let sec): CompanySectionScreen(companyID: id, section: sec)
            case .companyPart(let id, let sec, let part): CompanySectionScreen(companyID: id, section: sec, part: part)
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
