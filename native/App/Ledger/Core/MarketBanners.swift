import SwiftUI
import GameCore
import Businesses
import Simulation

/// Which worker's profile popup to open (the engine's types are not made Identifiable).
struct WorkerPopupRef: Identifiable, Equatable {
    var id: Int
    var companyID: Int
}

extension GameStore {
    /// The day's largest customer payment when it is big enough: at least 1.5 percent of net worth or 5 percent of that company's weekly takings.
    func bigPayment(_ e: GameEngine) -> (amount: Double, from: String, company: Company)? {
        guard let p = e.largestPaymentToday(companyID: nil), let co = e.state.company(p.companyID) else { return nil }
        let nw: Double = max(1, e.dayHistory.netWorth.last ?? 0)
        let weekly: Double = co.lastWeekRevenue
        let bigVsWorth: Bool = p.amount >= nw * 0.015
        let bigVsWeek: Bool = weekly > 0 && p.amount >= weekly * 0.05
        guard bigVsWorth || bigVsWeek else { return nil }
        return (p.amount, p.from, co)
    }

    private func marketSeverity(_ k: MarketEvent.Kind) -> Int {
        switch k {
        case .majorContract, .acquisitionOpportunity, .recognition: return 3
        default: return 1
        }
    }

    /// The worker a recognition event is about: its employee id, else the staff member whose name starts the title.
    private func workerFor(_ e: GameEngine, _ m: MarketEvent) -> WorkerPopupRef? {
        if let wid = m.employeeID {
            for co in e.state.companies where m.companyID == nil || m.companyID == co.id {
                if co.staff.contains(where: { $0.id == wid }) { return WorkerPopupRef(id: wid, companyID: co.id) }
            }
        }
        for co in e.state.companies where m.companyID == nil || m.companyID == co.id {
            for s in co.staff {
                guard let name = e.state.people[s.id]?.name, !name.isEmpty, m.title.hasPrefix(name) else { continue }
                return WorkerPopupRef(id: s.id, companyID: co.id)
            }
        }
        return nil
    }

    /// Banners for market events newer than `after`: at most two a day, the most important first.
    func postMarketBanners(_ e: GameEngine, after: Int) {
        let fresh: [MarketEvent] = e.marketEvents(limit: 20).filter { (m: MarketEvent) -> Bool in m.id > after }
        guard !fresh.isEmpty else { return }
        let ranked: [MarketEvent] = fresh.sorted { (a: MarketEvent, b: MarketEvent) -> Bool in
            let sa: Int = marketSeverity(a.kind)
            let sb: Int = marketSeverity(b.kind)
            return sa != sb ? sa > sb : a.id > b.id
        }
        for m in ranked.prefix(2) {
            var item = BannerItem(key: "mev-\(m.id)", source: "Market", title: m.title.tidyText, body: m.detail.tidyText, glyph: Glyph.stats)
            item.severity = marketSeverity(m.kind)
            let store: GameStore = self
            switch m.kind {
            case .majorContract, .acquisitionOpportunity:
                item.glyph = Glyph.ovCoin
                if let cid = m.companyID, let co = e.state.company(cid) {
                    item.target = .place(co.name, { store.openCompany(cid, section: .market) })
                }
            case .recognition:
                item.source = "Recognition"
                item.title = "Recognition"
                item.body = m.title.tidyText
                item.glyph = Glyph.achievements
                if let w = workerFor(e, m), let name = e.state.people[w.id]?.name {
                    item.target = .place(name, { store.workerPopup = w })
                }
            default:
                item.lifetime = 4
            }
            banners.post(item)
        }
    }
}
