import Foundation
import GameCore
import Countries

/// The chain as its own thing: a brand with a head office that owns the name, the standards and the shared services, above locations that only
/// trade under it. Read-only: the data is the chain's record (`Chains`), its papers, its executives and its locations.
public enum ChainIdentity {
    public struct Service: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var detail: String
        public var active: Bool
    }

    public struct HeadOffice: Equatable, Sendable {
        public var chainID: Int
        public var brand: String
        /// "Khan Shop head office"
        public var title: String
        public var tradeID: String
        public var locations: Int
        public var cities: Int
        /// 0 to 100, how much the name is worth.
        public var brandScore: Double
        public var ceoName: String?
        public var chainManagerName: String?
        public var services: [Service]
    }

    public static func headOffice(_ s: GameState, chainID: Int, data: GameData) -> HeadOffice? {
        guard let ch = Chains.chain(s, id: chainID) else { return nil }
        let L = Chains.stores(s, ch)
        guard let first = L.first else { return nil }
        let reach = Chains.reach(s, first, data: data)
        let ceo = ch["ceo56"].isNull ? nil : s.people[ch["ceo56"]["npc"].int]?.name
        let cm = ManagerModel.regionals(s).first { $0["scope"].string == "chain:\(chainID)" }.flatMap { s.people[$0["npc"].int]?.name }
        let std = ch["rules"]["knob"].object.count
        let papers = ["trademark", "ops_manual"].allSatisfy { first.value("docs")[$0]["st"].string == "ok" }
        let services = [
            Service(id: "brand", title: "Brand and trademark", detail: papers ? "One registered name and one operations manual for every location." : "Trademark or operations manual missing.", active: papers),
            Service(id: "standards", title: "Standards", detail: std == 0 ? "Each location decides how it sells." : "\(std) way\(std == 1 ? "" : "s") of selling fixed for every location.", active: std > 0),
            Service(id: "buying", title: "Shared buying", detail: reach.rebate > 0 ? "Suppliers give about \(Int((reach.rebate * 100).rounded()))% back on what the chain buys together." : "Buying power grows with the number of locations.", active: reach.rebate > 0),
            Service(id: "cash", title: "Shared cash", detail: L.count >= 2 ? "A location short of cash is covered by the others." : "From two locations the chain shares its cash.", active: L.count >= 2),
            Service(id: "management", title: "Chain management", detail: ceo != nil || cm != nil ? "Appoints and backs the managers of the locations." : "Hire a chain manager or CEO to run the locations for you.", active: ceo != nil || cm != nil),
        ]
        return HeadOffice(chainID: chainID, brand: ch["name"].string, title: "\(ch["name"].string) head office", tradeID: ch["type"].string, locations: L.count,
                          cities: Set(L.map { $0.cityID }).count, brandScore: BrandValues.company(s, first).score, ceoName: ceo, chainManagerName: cm, services: services)
    }
}
