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
            await calls(store, companyID: co.id)
            await votes(store, companyID: co.id)
        }
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

    private func calls(_ store: GameStore, companyID: Int) async {
        guard let e = store.engine, let co = e.state.company(companyID), let st = e.jointVenture(companyID: companyID) else { return }
        guard !st.meetings.contains(where: { !$0.closed }) else { return }
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
        store.act { (g: inout GameEngine) -> JointVenture.CallResult in g.jvCallUrgent(companyID: companyID, by: partner.id, reason: call.reason, items: [item]) }
    }

    private func votes(_ store: GameStore, companyID: Int) async {
        guard let e = store.engine, let co = e.state.company(companyID), let st = e.jointVenture(companyID: companyID) else { return }
        let week: Int = e.state.week
        let p3: Double = co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit }
        let tight: Bool = co.cash < 0
        for m in st.meetings where !m.closed && m.opened <= week && week <= m.deadline {
            let mocks: [JointVenture.Member] = st.members.filter { $0.mock && $0.id != JointVenture.Member.me }
            guard !mocks.isEmpty else { continue }
            let q = JVVoteQuery(companyID: companyID, meetingID: m.id, week: week, opened: m.opened, deadline: m.deadline, profitable: p3 >= 0, cashTight: tight,
                                items: m.items.map { JVVoteQuery.Item(id: $0.id, kind: $0.kind) },
                                partners: mocks.map { JVVoteQuery.Partner(memberID: $0.id, name: $0.name) })
            for v in await service.votes(q) {
                guard let now = store.engine?.jointVenture(companyID: companyID)?.meetings.first(where: { $0.id == m.id })?.items.first(where: { $0.id == v.itemID }), now.votes[v.memberID] == nil else { continue }
                store.act { (g: inout GameEngine) -> Bool in g.jvVote(companyID: companyID, meetingID: m.id, itemID: v.itemID, member: v.memberID, choice: v.choice) }
            }
        }
    }
}
