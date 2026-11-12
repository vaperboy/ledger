import Foundation
import GameCore
import Events
import Simulation

@MainActor
final class JointVentureCoordinator {
    static let shared = JointVentureCoordinator()

    private(set) var service: any JointVentureService
    private var attachedTo: ObjectIdentifier?
    private var running = false

    private init() { service = MockJointVentureService(online: OnlineBackend.shared) }

    func attach(_ online: any OnlineService) {
        let id = ObjectIdentifier(online as AnyObject)
        guard attachedTo != id else { return }
        attachedTo = id
        service = MockJointVentureService(online: online)
    }

    func offer(engine e: GameEngine, companyID: Int, inviteID: Int, friendName: String, friendID: String, pct: Double, price: Double) -> JVOffer? {
        guard let t = e.jvTerms(companyID: companyID, pct: pct, price: price) else { return nil }
        return JVOffer(companyID: companyID, inviteID: inviteID, companyName: t.companyName, friendID: friendID, friendName: friendName, pct: pct, price: price,
                       fair: t.fair, lines: t.lines, sentWeek: e.state.week)
    }

    func sync(_ store: GameStore) async {
        guard !running, store.engine != nil else { return }
        running = true
        defer { running = false }
        guard let start = store.engine else { return }
        for co in start.jointVentures {
            await answers(store, companyID: co.id)
            await buybacks(store, companyID: co.id)
            await calls(store, companyID: co.id)
            await votes(store, companyID: co.id)
        }
        settle(store)
    }

    // Counts what the clock has closed, when anything is open.
    private func settle(_ store: GameStore) {
        guard let e = store.engine else { return }
        let open: Bool = e.jointVentures.contains { (co: Company) -> Bool in
            guard let st = e.jointVenture(companyID: co.id) else { return false }
            return st.meetings.contains { !$0.closed } || !JointVenture.buyBackOffers(st).isEmpty || !st.queue.isEmpty
        }
        guard open else { return }
        store.act { (g: inout GameEngine) -> Void in g.jvSettle(now: Date()) }
    }

    private func answers(_ store: GameStore, companyID: Int) async {
        guard let e = store.engine, let st = e.jointVenture(companyID: companyID) else { return }
        for inv in st.invites where inv.status == "sent" && inv.mock {
            guard let offer = offer(engine: e, companyID: companyID, inviteID: inv.id, friendName: inv.name, friendID: inv.playerID, pct: inv.pct, price: inv.price) else { continue }
            var sent = offer
            sent.sentWeek = inv.sent
            guard let reply = await service.reply(to: sent, week: e.state.week) else { continue }
            let name: String = inv.name
            let company: String = e.state.company(companyID)?.name ?? "the company"
            let problem: String? = store.act { (g: inout GameEngine) -> String? in g.jvRespond(companyID: companyID, inviteID: inv.id, accept: reply == .accepted) } ?? nil
            if let problem { store.tell("\(name) could not join", problem, tone: "warn"); continue }
            if reply == .accepted { store.tell("\(name) joined \(company)", "\(name) paid and now owns \(String(format: "%.1f", inv.pct))% of \(company). They cannot sell before the lock-up ends.", tone: "good") }
            else { store.tell("\(name) said no", "\(name) turned down the offer to join \(company).") }
        }
    }

    private func buybacks(_ store: GameStore, companyID: Int) async {
        guard let e = store.engine else { return }
        let now: Double = Date().timeIntervalSince1970
        for o in e.jvBuyBackOffers(companyID: companyID) where o.mock {
            let q = JVBuybackQuery(companyID: companyID, offerID: o.id, memberID: o.memberID, price: o.price, fair: o.fair, sentAt: o.sentAt, now: now)
            guard let reply = await service.buybackReply(q) else { continue }
            let name: String = o.name
            let company: String = e.state.company(companyID)?.name ?? "the company"
            let problem: String? = store.act { (g: inout GameEngine) -> String? in g.jvAnswerBuyBack(companyID: companyID, offerID: o.id, accept: reply == .accepted) } ?? nil
            if let problem { store.tell("\(name) said yes, but it fell through", problem, tone: "warn"); continue }
            if reply == .accepted { store.tell("\(name) accepted your offer", "\(name) sold you their shares in \(company) and left the board.", tone: "good") }
            else { store.tell("\(name) said no", "\(name) keeps their shares in \(company). Nothing has changed; you can make another offer.") }
        }
    }

    private func calls(_ store: GameStore, companyID: Int) async {
        guard let e = store.engine, let co = e.state.company(companyID), let st = e.jointVenture(companyID: companyID) else { return }
        guard !st.meetings.contains(where: { !$0.closed && $0.urgent }) else { return }
        let mocks: [JVVoteQuery.Partner] = st.members.filter { $0.mock && $0.id != JointVenture.Member.me }.map { JVVoteQuery.Partner(memberID: $0.id, name: $0.name) }
        let p3: Double = co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit }
        guard let call = await service.emergency(companyID: companyID, week: e.state.week, profitable: p3 >= 0, cashTight: co.cash < 0, partners: mocks),
              let partner = st.members.first(where: { $0.id == call.memberID }) else { return }
        let made = store.act { (g: inout GameEngine) -> (item: JointVenture.Item?, problem: String?) in
            switch call.kind {
            case .dividend: return g.jvMakeItem(companyID: companyID, kind: .dividend, by: partner.name, amount: (g.maximumDividend(companyID: companyID) * 0.5).rounded(.down))
            default: return g.jvMakeItem(companyID: companyID, kind: call.kind, by: partner.name, steps: -1)
            }
        }
        guard let item = made?.item else { return }
        store.act { (g: inout GameEngine) -> JointVenture.CallResult in g.jvCallUrgent(companyID: companyID, by: partner.id, reason: call.reason, items: [item], now: Date()) }
    }

    private func raises(_ it: JointVenture.Item, current: String) -> Bool {
        guard let p = it.policy else { return true }
        return (Shareholders.policies.firstIndex(of: p) ?? 0) > (Shareholders.policies.firstIndex(of: current) ?? 0)
    }

    private func votes(_ store: GameStore, companyID: Int) async {
        guard let e = store.engine, let co = e.state.company(companyID), let st = e.jointVenture(companyID: companyID) else { return }
        let now: Double = Date().timeIntervalSince1970
        let p3: Double = co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit }
        let tight: Bool = co.cash < 0
        let policy: String = e.dividendPolicy(companyID: companyID)
        let mocks: [JointVenture.Member] = st.members.filter { $0.mock && $0.id != JointVenture.Member.me }
        guard !mocks.isEmpty else { return }
        for m in st.meetings where !m.closed {
            guard let opened = m.opensAt, let closes = m.closesAt, now < closes else { continue }
            let q = JVVoteQuery(companyID: companyID, meetingID: m.id, now: now, opened: opened, closes: closes, profitable: p3 >= 0, cashTight: tight,
                                items: m.items.map { (it: JointVenture.Item) -> JVVoteQuery.Item in JVVoteQuery.Item(id: it.id, kind: it.kind, raises: raises(it, current: policy)) },
                                partners: mocks.map { JVVoteQuery.Partner(memberID: $0.id, name: $0.name) })
            for v in await service.votes(q) {
                guard let item = store.engine?.jointVenture(companyID: companyID)?.meetings.first(where: { $0.id == m.id && !$0.closed })?.items.first(where: { $0.id == v.itemID }),
                      item.votes[v.memberID] == nil else { continue }
                store.act { (g: inout GameEngine) -> Bool in g.jvVote(companyID: companyID, meetingID: m.id, itemID: v.itemID, member: v.memberID, choice: v.choice, now: Date()) }
            }
        }
    }
}
