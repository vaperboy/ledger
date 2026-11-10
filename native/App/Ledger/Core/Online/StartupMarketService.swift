import Foundation
import SwiftUI
import GameCore
import Countries
import Businesses
import Finance
import Events
import Simulation

typealias CrowdStartup = CrowdStartupRules.Startup
typealias CrowdHolding = CrowdStartupRules.Holding

struct StartupShareOffer: Identifiable, Equatable {
    var id: String
    var startupID: String
    var sellerID: String
    var sellerName: String
    var sellerLinkKey: String
    var holding: CrowdHolding
    var percent: Double
    var price: Double
}

struct StartupBuyer: Equatable {
    var id: String
    var name: String
    var linkKey: String
    var accountWeeks: Int
}

enum StartupMarketEvent: Equatable {
    case milestone(startupID: String, name: String, stage: Int, mine: Bool)
    case failed(startupID: String, name: String, mine: Bool, refunded: Double)
    case refund(startupID: String, name: String, amount: Double)
    case viral(startupID: String, name: String, mine: Bool)
}

protocol StartupMarketService: AnyObject {
    var onChange: (() -> Void)? { get set }
    var myLinkKeys: Set<String> { get }
    var hasActivity: Bool { get }

    func startups() -> [CrowdStartup]
    func startup(_ id: String) -> CrowdStartup?
    func myHoldings() -> [CrowdHolding]
    func offers(startupID: String) -> [StartupShareOffer]
    func buyer(startupID: String) -> StartupBuyer?

    func list(_ s: CrowdStartup)
    func commitInvestment(_ s: CrowdStartup, holding: CrowdHolding)
    func commitPurchase(offerID: String, startup: CrowdStartup, holding: CrowdHolding)
    func commitSale(startupID: String, remaining: CrowdHolding)
    func update(_ s: CrowdStartup)

    func advance(today: Int, scale: Double, own: [String: CrowdStartups.Progress]) -> [StartupMarketEvent]
}

@MainActor
final class StartupMarketStore: ObservableObject {
    static let shared = StartupMarketStore()
    static let storageKey = "startupMarket.v1"

    @Published private(set) var revision = 0
    var service: StartupMarketService {
        didSet { service.onChange = { [weak self] in self?.touch() }; touch() }
    }

    init(service: StartupMarketService = MockStartupMarketService()) {
        self.service = service
        service.onChange = { [weak self] in self?.touch() }
    }

    private func touch() { DispatchQueue.main.async { [weak self] in self?.revision += 1 } }

    func attach(_ mock: MockOnlineService) async {
        let data = await mock.extensionData(for: Self.storageKey)
        await MainActor.run {
            guard !service.hasActivity else { return }
            service = MockStartupMarketService(restoring: data, save: { d in Task { await mock.setExtensionData(d, for: StartupMarketStore.storageKey) } })
        }
    }

    static func accountWeeks(_ e: GameEngine) -> Int { e.state.week }
    static func today(_ e: GameEngine) -> Int { e.state.week * 7 + e.state.day }

    func gainsRate(_ e: GameEngine) -> Double { e.context.homeCountry(e.state).capitalGainsTax }

    func sync(_ store: GameStore) {
        guard let e = store.engine else { return }
        let scale: Double = max(0.05, e.homeCurrency.scaledPrice(100_000) / 100_000)
        var own: [String: CrowdStartups.Progress] = [:]
        for st in service.startups() where st.founderID == CrowdStartups.me {
            if let cid = st.companyID, let p = CrowdStartups.progress(e.state, companyID: cid) { own[st.id] = p }
        }
        let today = Self.today(e)
        let events = service.advance(today: today, scale: scale, own: own)
        applyOwn(store, own: own, today: today, cur: e.homeCurrency)
        for ev in events { tell(store, ev, e.homeCurrency) }
    }

    private func applyOwn(_ store: GameStore, own: [String: CrowdStartups.Progress], today: Int, cur: Currency) {
        for var st in service.startups() where st.founderID == CrowdStartups.me && (st.status == .raising || st.status == .live) {
            guard let p = own[st.id] else { continue }
            var changed = false
            if !p.alive {
                let back = CrowdStartupRules.fail(&st)
                service.update(st)
                store.tell("\(st.name) has closed", "The money still held in escrow, \(cur.tidyShort(back.reduce(0) { $0 + $1.amount })), goes back to the investors. What was already released is lost.", tone: "bad")
                continue
            }
            while st.milestones < p.milestones && st.milestones < 3 {
                let stage = st.milestones
                let released = store.act { (eng: inout GameEngine) -> Double in
                    var r = 0.0
                    eng.update { s, _, _ in r = CrowdStartups.reachMilestone(&s, startup: &st, today: today) }
                    return r
                } ?? 0
                changed = true
                store.tell(CrowdStartupRules.milestoneNames[stage],
                           released > 0 ? "\(cur.tidyShort(released)) of investors' money is released from escrow to \(st.name). Their shares are now on its cap table, so your share is smaller." : "No investor money was waiting for this stage.", tone: "good")
            }
            st.assets = p.assets
            if today % 7 == 0 || st.weeklyProfit.isEmpty { st.weeklyProfit.append(p.weeklyProfit) } else { st.weeklyProfit[st.weeklyProfit.count - 1] = p.weeklyProfit }
            st.weeklyProfit = Array(st.weeklyProfit.suffix(CrowdStartupRules.recentProfitWeeks))
            if changed || st != service.startup(st.id) { service.update(st) }
        }
    }

    private func tell(_ store: GameStore, _ ev: StartupMarketEvent, _ cur: Currency) {
        switch ev {
        case .milestone(_, let name, let stage, let mine):
            if !mine { store.tell("\(name): \(CrowdStartupRules.milestoneNames[stage].lowercased())", "The money held in escrow for this stage went to the founder.", tone: "good") }
        case .failed(_, let name, let mine, let refunded):
            if !mine { store.tell("\(name) has failed", refunded > 0 ? "\(cur.tidyShort(refunded)) still in escrow came back to you. What was already released is lost, and your shares are worth nothing." : "Your shares are worth nothing.", tone: "bad") }
        case .refund(_, let name, let amount):
            _ = store.act { $0.update { s, _, _ in CrowdStartups.settleRefunds(&s, [(CrowdStartups.me, amount)], startupName: name) } }
        case .viral(_, let name, let mine):
            if mine { store.tell("\(name) is going viral", "Many players invested in a short time, so more people see it. Visibility is all it brings: it adds no money and no extra value.", tone: "good") }
        }
    }
}
