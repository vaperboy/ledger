import Foundation
import Businesses

/// Trade associations as the app sees them: who the members of a club are. The rules (standards, fee, discount, the weekly saving) live in the
/// engine (`TradeAssociations`); this protocol is only the online side. `MockAssociationService` stands in for the server.

/// One member in a club's list, as the viewer may see them (a Private player is never listed).
struct AssociationMemberRow: Identifiable, Equatable {
    var id: String
    var profile: PlayerProfile
    /// What the member runs in this trade, in words ("Bakery in Leeds"); nil when the member keeps it from this viewer.
    var line: String?
}

protocol AssociationService: AnyObject {
    /// The players in a club, from their public profiles.
    func members(of club: AssociationClub) -> [AssociationMemberRow]
}

/// Observable holder the screens watch, so they do not depend on which service stands behind it.
final class AssociationStore: ObservableObject {
    static let shared = AssociationStore()
    var service: AssociationService

    init(service: AssociationService = MockAssociationService()) { self.service = service }

    /// Members the discount counts: the listed players plus the player's own company when it belongs.
    func pooledMembers(of club: AssociationClub, includingYou: Bool) -> Int {
        service.members(of: club).count + (includingYou ? 1 : 0)
    }
}
