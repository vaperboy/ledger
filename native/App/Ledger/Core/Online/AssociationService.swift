import Foundation
import GameCore
import Businesses
import Simulation

struct AssociationMemberRow: Identifiable, Equatable {
    var id: String
    var profile: PlayerProfile
    var line: String?
}

protocol AssociationService: AnyObject {
    func members(of club: AssociationClub) -> [AssociationMemberRow]
}

final class AssociationStore: ObservableObject {
    static let shared = AssociationStore()
    var service: AssociationService

    init(service: AssociationService = MockAssociationService()) { self.service = service }

    func pooledMembers(of club: AssociationClub, includingYou: Bool) -> Int {
        service.members(of: club).count + (includingYou ? 1 : 0)
    }
}

extension AssociationStore {
    @MainActor func syncMembers(_ store: GameStore) {
        guard let e = store.engine else { return }
        for co in e.state.companies where co.status.isLive {
            guard let m = TradeAssociations.membership(e.state, companyID: co.id) else { continue }
            let n: Int = pooledMembers(of: m.club, includingYou: true)
            guard n != m.members else { continue }
            let id: Int = co.id
            _ = store.act { (g: inout GameEngine) in g.update { s, _, _ in TradeAssociations.setMembers(&s, companyID: id, members: n) } }
        }
    }
}
