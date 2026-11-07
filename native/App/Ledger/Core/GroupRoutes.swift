import SwiftUI

/// A request to show one company's entity page on the Group tab (section: "expansion" for chain and franchise, or any section key the
/// Group tab understands). The Group tab reads `GroupRouteBox.shared.request` (observe the box), shows the page and calls `take()`.
@MainActor
final class GroupRouteBox: ObservableObject {
    static let shared = GroupRouteBox()
    struct Request: Equatable {
        var companyID: Int
        var section: String
    }
    @Published private(set) var request: Request?

    func set(_ r: Request) { request = r }

    /// Returns the waiting request and clears it.
    func take() -> Request? {
        let r: Request? = request
        request = nil
        return r
    }
}

extension GameStore {
    /// The waiting request to open a company's entity page on the Group tab, if any.
    var groupEntityRequest: (companyID: Int, section: String)? {
        guard let r = GroupRouteBox.shared.request else { return nil }
        return (r.companyID, r.section)
    }

    /// Takes the Group tab to the entity page of a company (section "expansion" is chain and franchise).
    func openGroupEntity(companyID: Int, section: String = "expansion") {
        GroupRouteBox.shared.set(GroupRouteBox.Request(companyID: companyID, section: section))
        selectTab(.group, resetRoot: false)
    }
}
