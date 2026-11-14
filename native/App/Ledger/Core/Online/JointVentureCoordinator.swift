import Foundation
import GameCore
import Events
import Simulation

// Keeps shared companies moving. Partners who are real players are handled by the game server; sample partners answer on this device.
@MainActor
final class JointVentureCoordinator {
    static let shared = JointVentureCoordinator()

    private(set) var service: any JointVentureService
    private(set) var board: (any VentureBoardService)?
    private var online: any OnlineService
    private var attachedTo: ObjectIdentifier?
    private var running = false
    private var realIDs: Set<String> = []
    private var warned: Set<String> = []

    private init() {
        online = OnlineBackend.shared
        service = MockJointVentureService(online: OnlineBackend.shared)
        board = OnlineBackend.shared as? any VentureBoardService
    }

    func attach(_ online: any OnlineService) {
        let id = ObjectIdentifier(online as AnyObject)
        guard attachedTo != id else { return }
        attachedTo = id
        self.online = online
        service = MockJointVentureService(online: online)
        board = online as? any VentureBoardService
    }

    /// Only real friends can be invited; with none, the sheet shows how to add one.
    func invitable() async -> [PlayerProfile] {
        guard let overview = try? await online.friends() else { return [] }
        if board != nil { realIDs.formUnion(overview.friends.map { (p: PlayerProfile) -> String in p.id }) }
        return overview.friends
    }

    func isReal(_ playerID: String) -> Bool { board != nil && realIDs.contains(playerID) }

    func offer(engine e: GameEngine, companyID: Int, inviteID: Int, friendName: String, friendID: String, pct: Double, price: Double) -> JVOffer? {
        guard let t = e.jvTerms(companyID: companyID, pct: pct, price: price) else { return nil }
        return JVOffer(companyID: companyID, inviteID: inviteID, companyName: t.companyName, friendID: friendID, friendName: friendName, pct: pct, price: price,
                       fair: t.fair, lines: t.lines, sentWeek: e.state.week)
    }

    func sync(_ store: GameStore) async {
        guard !running, store.engine != nil else { return }
        running = true
        defer { running = false }
        if let board { await followServer(store, board) }
        guard let start = store.engine else { return }
        for co in start.jointVentures {
            await answers(store, companyID: co.id)
            await buybacks(store, companyID: co.id)
            await calls(store, companyID: co.id)
            await votes(store, companyID: co.id)
        }
        settle(store)
    }

    // Takes back an offer for a partner's shares. An offer to a real player is taken back on the server first.
    func withdraw(_ store: GameStore, companyID: Int, offer: JointVenture.Buyback) async -> String? {
        if !offer.mock, let remote = offer.remoteID, let board {
            do {
                try await board.withdrawVentureBuyback(offerID: remote)
            } catch {
                await sync(store)
                return (error as? LocalizedError)?.errorDescription ?? "Could not withdraw the offer."
            }
        }
        let done: Bool = store.act { (g: inout GameEngine) -> Bool in g.jvWithdrawBuyBack(companyID: companyID, offerID: offer.id) } ?? false
        return done ? nil : "That offer is no longer open."
    }

    // MARK: Real players, through the server

    static func key(_ companyID: Int) -> String { "own.\(companyID)" }

    private static func needsServer(_ e: GameEngine, _ companyID: Int) -> Bool {
        guard let st = e.jointVenture(companyID: companyID) else { return false }
        return JointVenture.isRemote(st) || st.invites.contains { (i: JointVenture.Invite) -> Bool in !i.mock && i.status == "sent" }
    }

    // Nil when the server could not be reached, so the step is tried again later.
    private func refusal(_ error: Error) -> String? {
        guard let e = error as? OnlineError else { return nil }
        switch e {
        case .offline, .notSignedIn, .cancelled, .adultRequired: return nil
        default: return e.errorDescription ?? "The server did not accept it."
        }
    }

    private func followServer(_ store: GameStore, _ api: any VentureBoardService) async {
        guard !store.isAdvancing, let e = store.engine else { return }
        let ids: [Int] = e.jointVentures.map { (co: Company) -> Int in co.id }.filter { (id: Int) -> Bool in Self.needsServer(e, id) }
        guard !ids.isEmpty, let all = try? await api.ventures() else { return }
        var mine: [String: VentureInfo] = [:]
        for v in all where v.isChair { mine[v.companyKey] = v }
        for id in ids { await follow(store, api, companyID: id, known: mine[Self.key(id)]) }
    }

    private func follow(_ store: GameStore, _ api: any VentureBoardService, companyID id: Int, known: VentureInfo?) async {
        guard let venture = await record(store, api, companyID: id, known: known) else { return }
        await reportValue(store, api, id, venture)
        let sent: [VentureInviteRow]? = try? await api.ventureInvitesSent(ventureID: venture.id)
        await partners(store, api, id, venture, sent)
        if let sent { await invites(store, api, id, venture, sent) }
        await meetings(store, api, id, venture)
        await offers(store, api, id, venture)
        await policyDividend(store, api, id, venture)
    }

    private func refuseInvites(_ store: GameStore, _ id: Int, why: String) {
        guard let st = store.engine?.jointVenture(companyID: id) else { return }
        for inv in st.invites where inv.status == "sent" && !inv.mock {
            store.act { (g: inout GameEngine) -> Bool in g.jvDropInvite(companyID: id, inviteID: inv.id, status: "failed", why: why) }
        }
    }

    // The company's record on the server, made the first time a real player is invited.
    private func record(_ store: GameStore, _ api: any VentureBoardService, companyID id: Int, known: VentureInfo?) async -> VentureInfo? {
        guard let e = store.engine, let co = e.state.company(id), let st = e.jointVenture(companyID: id) else { return nil }
        if let known {
            if st.remoteID == known.id { return known }
            if st.remoteID == nil, known.partners.count <= 1 {
                store.act { (g: inout GameEngine) -> Void in g.jvSetRemote(companyID: id, ventureID: known.id) }
                return known
            }
            refuseInvites(store, id, why: "Another of your saved games already shares a company with real players in this place. Only one saved game can do that.")
            return nil
        }
        if st.remoteID != nil, JointVenture.isRemote(st) { return nil }
        guard let code = e.jvCurrencyCode(companyID: id) else { return nil }
        let value: Double = e.jvServerAmount(e.jvCompanyValue(companyID: id), companyID: id)
        do {
            let made: VentureInfo = try await api.createVenture(companyKey: Self.key(id), name: String(co.name.prefix(40)), value: value, currency: code)
            store.act { (g: inout GameEngine) -> Void in g.jvSetRemote(companyID: id, ventureID: made.id) }
            let policy: String = e.dividendPolicy(companyID: id)
            if policy != "none" {
                _ = try? await api.proposeVentureChange(ventureID: made.id, kind: "policy", params: .object(["policy": .string(policy)]), now: false, profitable: true, cashTight: false)
            }
            return made
        } catch {
            if let why = refusal(error) { refuseInvites(store, id, why: why) }
            return nil
        }
    }

    // The most a stake of this size can cost: the larger of this game's value and the server's, at the widest price band the server allows.
    private static func stakeCeiling(_ e: GameEngine, _ id: Int, _ venture: VentureInfo, pct: Double) -> Double {
        let value: Double = max(e.jvCompanyValue(companyID: id), e.jvGameAmount(venture.value, companyID: id))
        let p: Double = min(max(pct, 0), 49.5)
        return value * p / (100 - p) * 2.5 * 1.05
    }

    // A server figure outside the limits is not booked; the player hears about it once per session.
    private func outOfBounds(_ store: GameStore, key: String, title: String, text: String) {
        guard !warned.contains(key) else { return }
        warned.insert(key)
        store.tell(title, text, tone: "warn")
    }

    private func reportValue(_ store: GameStore, _ api: any VentureBoardService, _ id: Int, _ venture: VentureInfo) async {
        guard let e = store.engine else { return }
        let value: Double = e.jvServerAmount(e.jvCompanyValue(companyID: id), companyID: id)
        guard abs(value - venture.value) > max(1, venture.value * 0.005) else { return }
        try? await api.reportVentureValue(ventureID: venture.id, value: value)
    }

    // Brings the board here in line with who holds shares on the server: new partners are booked in, sold stakes are paid for.
    private func partners(_ store: GameStore, _ api: any VentureBoardService, _ id: Int, _ venture: VentureInfo, _ sent: [VentureInviteRow]?) async {
        guard let e = store.engine, let st = e.jointVenture(companyID: id) else { return }
        let onServer: [VenturePartner] = venture.partners.filter { (p: VenturePartner) -> Bool in p.memberID != venture.chairID }
        for p in onServer where !st.members.contains(where: { (m: JointVenture.Member) -> Bool in m.id == "p:" + p.memberID }) {
            let local: JointVenture.Invite? = st.invites.first { (i: JointVenture.Invite) -> Bool in i.playerID == p.memberID && i.status == "sent" }
            let row: VentureInviteRow? = sent?.first { (r: VentureInviteRow) -> Bool in r.inviteeID == p.memberID && r.status == "accepted" }
            guard local != nil || row != nil else { continue }
            let pct: Double = local?.pct ?? row?.pct ?? 0
            let price: Double = local?.price ?? e.jvGameAmount(row?.price ?? 0, companyID: id)
            if local == nil, !(price.isFinite && price >= 0 && price <= Self.stakeCeiling(e, id, venture, pct: pct)) {
                outOfBounds(store, key: "join:" + venture.id + ":" + p.memberID, title: "New partner not booked",
                            text: "The price the server gave for a new partner's shares was outside the limits, so it was not booked.")
                continue
            }
            let name: String = local?.name ?? p.name ?? "A partner"
            let lock: Double? = p.lockUntil?.timeIntervalSince1970
            store.act { (g: inout GameEngine) -> String? in g.jvRemoteJoin(companyID: id, playerID: p.memberID, name: name, pct: pct, price: price, lockAt: lock) }
        }
        let gone: [JointVenture.Member] = st.members.filter { (m: JointVenture.Member) -> Bool in
            !m.mock && m.id != JointVenture.Member.me && !onServer.contains { (p: VenturePartner) -> Bool in "p:" + p.memberID == m.id }
        }
        guard !gone.isEmpty, let sold = try? await api.ventureSharesSold(ventureID: venture.id) else { return }
        for m in gone {
            guard let now = store.engine else { return }
            let playerID: String = String(m.id.dropFirst(2))
            let row: VentureBuybackRow? = sold.first { (r: VentureBuybackRow) -> Bool in r.sellerID == playerID }
            let open: JointVenture.Buyback? = now.jvBuyBackOffers(companyID: id).first { (o: JointVenture.Buyback) -> Bool in o.memberID == m.id }
            var price: Double = now.jvGameAmount(row?.price ?? 0, companyID: id)
            var agreedHere = false
            if let open, let row, open.remoteID == row.id { price = open.price; agreedHere = true }
            let pct: Double = now.jvStakes(companyID: id).first { (x: JointVenture.Stake) -> Bool in x.id == m.id }?.pct ?? 0
            if !agreedHere, pct > 0, !(price.isFinite && price >= 0 && price <= Self.stakeCeiling(now, id, venture, pct: pct)) {
                outOfBounds(store, key: "left:" + venture.id + ":" + m.id, title: "Share sale not booked",
                            text: "The price the server gave for \(m.name)'s shares was outside the limits, so it was not paid.")
                continue
            }
            store.act { (g: inout GameEngine) -> String? in g.jvPartnerLeft(companyID: id, memberID: m.id, price: price) }
        }
    }

    // Sends invitations that have not gone out yet and picks up the answers to the ones that have.
    private func invites(_ store: GameStore, _ api: any VentureBoardService, _ id: Int, _ venture: VentureInfo, _ sent: [VentureInviteRow]) async {
        guard let st = store.engine?.jointVenture(companyID: id) else { return }
        for inv in st.invites where inv.status == "sent" && !inv.mock {
            guard let e = store.engine else { return }
            if let remote = inv.remoteID {
                guard let row = sent.first(where: { (r: VentureInviteRow) -> Bool in r.id == remote }) else { continue }
                if row.status == "declined" {
                    store.act { (g: inout GameEngine) -> String? in g.jvRespond(companyID: id, inviteID: inv.id, accept: false) }
                } else if row.status == "expired" {
                    store.act { (g: inout GameEngine) -> Bool in g.jvDropInvite(companyID: id, inviteID: inv.id, status: "expired") }
                }
                continue
            }
            if let waiting = sent.first(where: { (r: VentureInviteRow) -> Bool in r.inviteeID == inv.playerID && r.status == "pending" }) {
                store.act { (g: inout GameEngine) -> Void in g.jvLinkInvite(companyID: id, inviteID: inv.id, remoteID: waiting.id) }
                continue
            }
            do {
                let made: VentureCreated = try await api.inviteVenturePartner(ventureID: venture.id, friendID: inv.playerID, pct: inv.pct, price: e.jvServerAmount(inv.price, companyID: id))
                store.act { (g: inout GameEngine) -> Void in g.jvLinkInvite(companyID: id, inviteID: inv.id, remoteID: made.id) }
            } catch {
                if let why = refusal(error) {
                    store.act { (g: inout GameEngine) -> Bool in g.jvDropInvite(companyID: id, inviteID: inv.id, status: "failed", why: why) }
                }
            }
        }
    }

    private func settingKey(_ x: JointVenture.Setting) -> String {
        let name: String = x.rule == "knob" || x.rule == "knobFree" ? "knob." + x.text : x.rule
        let clean: String = ("c\(x.chainID)." + name).lowercased().filter { (c: Character) -> Bool in
            (c.isASCII && (c.isLetter || c.isNumber)) || c == "." || c == "_" || c == "-"
        }
        return String(clean.prefix(40))
    }

    // An agenda item as the server stores it. `ref` is this company's own number for it.
    private func wire(_ it: JointVenture.Item, _ e: GameEngine, companyID id: Int) -> JSONValue {
        var p: [String: JSONValue] = ["ref": .string("\(it.id)")]
        switch it.kind {
        case .dividend: p["amount"] = .number(e.jvServerAmount(it.amount, companyID: id))
        case .price: p["steps"] = .number(Double(it.steps))
        case .partner:
            p["invitee"] = .string(it.playerID)
            p["pct"] = .number(it.pct)
            p["price"] = .number(e.jvServerAmount(it.price, companyID: id))
        case .policy: p["policy"] = .string(it.policy ?? "none")
        case .setting:
            if let x = it.setting {
                p["key"] = .string(settingKey(x))
                if x.rule == "knobFree" { p["value"] = .string("free") }
                else if x.rule == "marketing" { p["value"] = .string(x.text) }
                else { p["value"] = .number(x.number) }
                p["label"] = .string(String(x.label.prefix(120)))
            }
        case .hire, .sell, .dissolve: break
        }
        return .object(p)
    }

    private func item(_ store: GameStore, _ id: Int, _ meetingID: Int, _ itemID: Int) -> JointVenture.Item? {
        store.engine?.jointVenture(companyID: id)?.meetings.first { (m: JointVenture.Meeting) -> Bool in m.id == meetingID }?
            .items.first { (i: JointVenture.Item) -> Bool in i.id == itemID }
    }

    private func meetings(_ store: GameStore, _ api: any VentureBoardService, _ id: Int, _ venture: VentureInfo) async {
        guard let e = store.engine, let co = e.state.company(id), let st = e.jointVenture(companyID: id), JointVenture.isRemote(st) else { return }
        let open: [JointVenture.Meeting] = st.meetings.filter { (m: JointVenture.Meeting) -> Bool in !m.closed }
        guard !open.isEmpty else { return }
        var cache: [String: VentureMeetingInfo] = [:]
        for mid in venture.openMeetings ?? [] {
            if let info = try? await api.ventureMeeting(id: mid) { cache[mid] = info }
        }
        let p3: Double = co.monthlyHistory.suffix(3).reduce(0) { $0 + $1.profit }
        let tight: Bool = co.cash < 0
        for m in open {
            for it in m.items where it.outcome == nil {
                cache = await followItem(store, api, id, venture, meetingID: m.id, urgent: m.urgent, item: it, profitable: p3 >= 0, cashTight: tight, cache: cache)
            }
        }
    }

    // One agenda item: put it to the server if it is not there, send the owner's vote, and take the count or the result back.
    private func followItem(_ store: GameStore, _ api: any VentureBoardService, _ id: Int, _ venture: VentureInfo, meetingID: Int, urgent: Bool, item it: JointVenture.Item,
                            profitable: Bool, cashTight: Bool, cache known: [String: VentureMeetingInfo]) async -> [String: VentureMeetingInfo] {
        var cache: [String: VentureMeetingInfo] = known
        let ref: String = "\(it.id)"
        var found: VentureMeetingInfo?
        if let linked = it.remoteMeeting {
            if cache[linked] == nil, let got = try? await api.ventureMeeting(id: linked) { cache[linked] = got }
            found = cache[linked]
        } else if let earlier = cache.values.first(where: { (m: VentureMeetingInfo) -> Bool in m.items.contains { (i: VentureMeetingItem) -> Bool in i.ref == ref } }) {
            found = earlier
        } else {
            guard let e = store.engine else { return cache }
            do {
                let r: VentureProposeResult = try await api.proposeVentureChange(ventureID: venture.id, kind: it.kind.rawValue, params: wire(it, e, companyID: id), now: urgent,
                                                                                 profitable: profitable, cashTight: cashTight)
                guard let remoteMeeting = r.meetingID else {
                    store.act { (g: inout GameEngine) -> Bool in g.jvRemoteResult(companyID: id, meetingID: meetingID, itemID: it.id, passed: r.applied) }
                    return cache
                }
                store.act { (g: inout GameEngine) -> Void in
                    g.jvLinkItem(companyID: id, meetingID: meetingID, itemID: it.id, remoteID: "", remoteMeeting: remoteMeeting, closesAt: r.deadline?.timeIntervalSince1970)
                }
                if let got = try? await api.ventureMeeting(id: remoteMeeting) { cache[remoteMeeting] = got }
                found = cache[remoteMeeting]
            } catch {
                if let why = refusal(error) {
                    store.act { (g: inout GameEngine) -> Bool in g.jvDropItem(companyID: id, meetingID: meetingID, itemID: it.id, why: why) }
                }
                return cache
            }
        }
        guard var info = found, var remote = info.items.first(where: { (i: VentureMeetingItem) -> Bool in i.ref == ref }) else { return cache }
        if it.remoteID != remote.id || it.remoteMeeting != info.id {
            let itemRemote: String = remote.id, meetingRemote: String = info.id, closes: Double = info.deadline.timeIntervalSince1970
            store.act { (g: inout GameEngine) -> Void in
                g.jvLinkItem(companyID: id, meetingID: meetingID, itemID: it.id, remoteID: itemRemote, remoteMeeting: meetingRemote, closesAt: closes)
            }
        }
        if remote.outcome == nil {
            var changed = false
            if Date() > info.deadline {
                changed = (try? await api.closeVentureMeeting(id: info.id)) != nil
            } else if let mine = item(store, id, meetingID, it.id)?.votes[JointVenture.Member.me], mine.rawValue != remote.myVote {
                changed = (try? await api.castVentureVote(itemID: remote.id, choice: mine.rawValue)) != nil
            }
            if changed, let got = try? await api.ventureMeeting(id: info.id) {
                cache[info.id] = got
                info = got
                if let again = got.items.first(where: { (i: VentureMeetingItem) -> Bool in i.ref == ref }) { remote = again }
            }
        }
        if let outcome = remote.outcome {
            var votes: [String: JVRules.Choice] = [:]
            for v in remote.votes ?? [] {
                guard let c = JVRules.Choice(rawValue: v.choice) else { continue }
                votes[v.memberID == venture.chairID ? JointVenture.Member.me : "p:" + v.memberID] = c
            }
            let passed: Bool = outcome == "passed"
            store.act { (g: inout GameEngine) -> Bool in g.jvRemoteResult(companyID: id, meetingID: meetingID, itemID: it.id, passed: passed, votes: votes) }
            return cache
        }
        let yes: Double = remote.yesShares ?? 0, no: Double = remote.noShares ?? 0, total: Double = info.totalShares ?? Double(venture.totalShares)
        if let now = item(store, id, meetingID, it.id), now.remoteYes != yes || now.remoteNo != no || now.remoteTotal != total {
            store.act { (g: inout GameEngine) -> Bool in g.jvRemoteStanding(companyID: id, meetingID: meetingID, itemID: it.id, yes: yes, no: no, total: total) }
        }
        return cache
    }

    // Offers for a real partner's shares: send the new ones, and close the ones the partner turned down or let run out.
    private func offers(_ store: GameStore, _ api: any VentureBoardService, _ id: Int, _ venture: VentureInfo) async {
        guard let start = store.engine else { return }
        let open: [JointVenture.Buyback] = start.jvBuyBackOffers(companyID: id).filter { (o: JointVenture.Buyback) -> Bool in !o.mock }
        guard !open.isEmpty else { return }
        var outgoing: [VentureBuyback]?
        for o in open {
            guard let e = store.engine else { return }
            if let remote = o.remoteID {
                if outgoing == nil { outgoing = (try? await api.ventureBuybacks())?.outgoing }
                guard let row = outgoing?.first(where: { (b: VentureBuyback) -> Bool in b.id == remote }) else { continue }
                if row.status == "declined" {
                    store.act { (g: inout GameEngine) -> Bool in g.jvCloseBuyBack(companyID: id, offerID: o.id, declined: true) }
                } else if row.status == "expired" || row.status == "withdrawn" {
                    store.act { (g: inout GameEngine) -> Bool in g.jvCloseBuyBack(companyID: id, offerID: o.id, declined: false) }
                }
                continue
            }
            do {
                let made: VentureCreated = try await api.offerVentureBuyback(ventureID: venture.id, partnerID: String(o.memberID.dropFirst(2)), price: e.jvServerAmount(o.price, companyID: id))
                store.act { (g: inout GameEngine) -> Void in g.jvLinkBuyBack(companyID: id, offerID: o.id, remoteID: made.id) }
            } catch {
                if let why = refusal(error) {
                    store.act { (g: inout GameEngine) -> Bool in g.jvWithdrawBuyBack(companyID: id, offerID: o.id) }
                    store.tell("Offer not sent", why, tone: "warn")
                }
            }
        }
    }

    // The quarterly dividend under the owners' policy is paid in this game; the server passes the partners' part on to them.
    private func policyDividend(_ store: GameStore, _ api: any VentureBoardService, _ id: Int, _ venture: VentureInfo) async {
        guard let e = store.engine, let st = e.jointVenture(companyID: id), JointVenture.isRemote(st) else { return }
        let last = e.lastDividendDecision(companyID: id)
        guard let sentWeek = st.remotePaidWeek else {
            let week: Int = last?.week ?? 0
            store.act { (g: inout GameEngine) -> Void in g.jvMarkDividendSent(companyID: id, week: week) }
            return
        }
        guard let last, last.week > sentWeek, last.paid > 0 else { return }
        let week: Int = last.week
        guard (try? await api.payVentureDividend(ventureID: venture.id, amount: e.jvServerAmount(last.paid, companyID: id), ref: "q\(week)")) != nil else { return }
        store.act { (g: inout GameEngine) -> Void in g.jvMarkDividendSent(companyID: id, week: week) }
    }

    // MARK: Sample partners, on this device

    // Counts what the clock has closed, when anything is open.
    private func settle(_ store: GameStore) {
        guard let e = store.engine else { return }
        let open: Bool = e.jointVentures.contains { (co: Company) -> Bool in
            guard let st = e.jointVenture(companyID: co.id) else { return false }
            if JointVenture.isRemote(st) { return !st.queue.isEmpty }
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
