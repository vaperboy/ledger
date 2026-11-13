import SwiftUI
import GameCore
import Events
import Simulation

// The player's side of companies run by other players: offers to join, shares held, votes to cast, and offers for those shares.
@MainActor
final class PartnerSharesModel: ObservableObject {
    static let shared = PartnerSharesModel()

    @Published private(set) var offers: [VentureOffer] = []
    @Published private(set) var held: [VentureInfo] = []
    @Published private(set) var meetings: [VentureMeetingInfo] = []
    @Published private(set) var buybacks: VentureBuybacks = .empty
    @Published var busy = false
    @Published private(set) var loadFailed = false

    private static let seenKey = "jv.partner.seenOffers"
    private var api: (any VentureBoardService)? { JointVentureCoordinator.shared.board }

    var asked: [VentureBuyback] { buybacks.outgoing.filter { (b: VentureBuyback) -> Bool in b.status == "pending" && b.proposedBy == b.sellerID } }
    var isEmpty: Bool { offers.isEmpty && held.isEmpty && buybacks.incoming.isEmpty }
    var waiting: Int {
        offers.count + buybacks.incoming.count + meetings.filter { (m: VentureMeetingInfo) -> Bool in m.items.contains { (i: VentureMeetingItem) -> Bool in i.myVote == nil } }.count
    }

    func venture(_ id: String) -> VentureInfo? { held.first { (v: VentureInfo) -> Bool in v.id == id } }

    func refresh(_ online: OnlineSession) async {
        guard let api, online.isSignedIn else {
            if !isEmpty || !meetings.isEmpty { offers = []; held = []; meetings = []; buybacks = .empty }
            loadFailed = false
            return
        }
        var failed = false
        do { let o = try await api.ventureOffers(); if o != offers { offers = o } } catch { failed = true }
        do {
            let all = try await api.ventures()
            let mine: [VentureInfo] = all.filter { (v: VentureInfo) -> Bool in !v.isChair }
            var open: [VentureMeetingInfo] = []
            for v in mine {
                for id in v.openMeetings ?? [] {
                    if let m = try? await api.ventureMeeting(id: id), m.closedAt == nil, m.deadline > Date() { open.append(m) }
                }
            }
            open.sort { (a: VentureMeetingInfo, b: VentureMeetingInfo) -> Bool in a.deadline < b.deadline }
            if mine != held { held = mine }
            if open != meetings { meetings = open }
        } catch { failed = true }
        do { let b = try await api.ventureBuybacks(); if b != buybacks { buybacks = b } } catch { failed = true }
        if failed != loadFailed { loadFailed = failed }
    }

    // Offers that arrived since the player last heard of them, each reported once.
    func unseenOffers() -> [VentureOffer] {
        var seen: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
        let fresh: [VentureOffer] = offers.filter { (o: VentureOffer) -> Bool in !seen.contains(o.id) }
        guard !fresh.isEmpty else { return [] }
        seen.formUnion(fresh.map { (o: VentureOffer) -> String in o.id })
        UserDefaults.standard.set(Array(seen.suffix(200)), forKey: Self.seenKey)
        return fresh
    }

    private func text(_ error: Error) -> String { OnlineWords.friendly(error) }

    // Books what the server settled, then reads the lists again.
    private func finish(_ store: GameStore, _ online: OnlineSession) async {
        await online.syncWorld(store: store)
        await refresh(online)
    }

    func answer(_ o: VentureOffer, accept: Bool, store: GameStore, online: OnlineSession) async -> String? {
        guard let api else { return "Sign in to use this." }
        if accept, let e = store.engine, e.state.cash < e.internalAmount(o.price, currency: o.currency) { return "You do not have the cash for this." }
        busy = true
        defer { busy = false }
        do {
            try await api.replyToVentureOffer(inviteID: o.id, accept: accept, currency: o.currency)
            await finish(store, online)
            return nil
        } catch { return text(error) }
    }

    func vote(_ picks: [String: String], store: GameStore, online: OnlineSession) async -> String? {
        guard let api else { return "Sign in to use this." }
        busy = true
        defer { busy = false }
        do {
            for (item, choice) in picks.sorted(by: { (a: (key: String, value: String), b: (key: String, value: String)) -> Bool in a.key < b.key }) {
                try await api.castVentureVote(itemID: item, choice: choice)
            }
            await finish(store, online)
            return nil
        } catch {
            await refresh(online)
            return text(error)
        }
    }

    func answer(_ b: VentureBuyback, accept: Bool, store: GameStore, online: OnlineSession) async -> String? {
        guard let api else { return "Sign in to use this." }
        let buying: Bool = b.buyerID == online.accountID
        if accept, buying, let e = store.engine, e.state.cash < e.internalAmount(b.price, currency: b.currency) { return "You do not have the cash for this." }
        busy = true
        defer { busy = false }
        do {
            try await api.replyToVentureBuyback(offerID: b.id, accept: accept)
            await finish(store, online)
            return nil
        } catch { return text(error) }
    }

    func askExit(_ v: VentureInfo, price: Double, store: GameStore, online: OnlineSession) async -> String? {
        guard let api else { return "Sign in to use this." }
        busy = true
        defer { busy = false }
        do {
            _ = try await api.requestVentureExit(ventureID: v.id, price: price)
            await refresh(online)
            return nil
        } catch { return text(error) }
    }

    func withdraw(_ b: VentureBuyback, online: OnlineSession) async -> String? {
        guard let api else { return "Sign in to use this." }
        busy = true
        defer { busy = false }
        do {
            try await api.withdrawVentureBuyback(offerID: b.id)
            await refresh(online)
            return nil
        } catch {
            await refresh(online)
            return text(error)
        }
    }
}

enum PartnerShareText {
    static func money(_ v: Double, _ code: String) -> String { ListingFormat.money(v, code) }
    static func percent(_ p: Double) -> String { String(format: p < 10 && p != p.rounded() ? "%.1f%%" : "%.0f%%", p) }

    static func countdown(to end: Date, from now: Date = Date()) -> String {
        let left: Int = Int(end.timeIntervalSince(now))
        if left <= 0 { return "Voting has closed" }
        let hours: Int = left / 3600, minutes: Int = (left % 3600) / 60
        if hours >= 48 { return "Closes in \(hours / 24) days" }
        if hours >= 1 { return "Closes in \(hours) h \(minutes) min" }
        return "Closes in \(max(1, minutes)) min"
    }

    static func policy(_ p: String?) -> String {
        switch p {
        case "low": return "25% of profit is paid out"
        case "mid": return "50% of profit is paid out"
        case "high": return "80% of profit is paid out"
        default: return "Profit stays in the company"
        }
    }

    // What an agenda item does, in the words a partner needs before voting.
    static func effect(_ it: VentureMeetingItem, venture v: VentureInfo?, share pct: Double) -> String {
        let code: String = v?.currency ?? ""
        let amount: Double = it.params["amount"].double
        switch it.kind {
        case "dividend": return "\(money(amount, code)) is paid out to all owners by their shares. Your part is about \(money(amount * pct / 100, code))."
        case "capital": return "The owners put \(money(amount, code)) into the company by their shares. Your part, about \(money(amount * pct / 100, code)), is taken from your cash."
        case "price": return it.params["steps"].double < 0 ? "Prices go down one step: more customers, less money on each sale." : "Prices go up one step: fewer customers, more money on each sale."
        case "hire": return "A manager is hired and runs the company day to day. Their pay comes out of the company."
        case "sell": return "The company is put up for sale."
        case "partner": return "A new partner is invited for \(percent(it.params["pct"].double)) of the company, paying \(money(it.params["price"].double, code)). Every owner's share becomes a little smaller."
        case "dissolve": return "The company is closed and its value is paid out to the owners by their shares. Your part is about \(money((v?.value ?? 0) * pct / 100, code))."
        case "policy": return "From then on that share of the profit is paid each quarter to all owners by their shares."
        case "setting": return "It then holds for every store in the group."
        default: return ""
        }
    }
}

enum PartnerSheet: Identifiable, Equatable {
    case offer(String), holding(String), meeting(String), buyback(String)
    var id: String {
        switch self {
        case .offer(let s): return "offer-" + s
        case .holding(let s): return "holding-" + s
        case .meeting(let s): return "meeting-" + s
        case .buyback(let s): return "buyback-" + s
        }
    }
}

// The one place a player sees and answers everything about shares in other players' companies.
struct PartnerSharesSection: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @ObservedObject private var model = PartnerSharesModel.shared
    @State private var sheet: PartnerSheet?

    var body: some View {
        if !model.isEmpty {
            LedgerSection("Shares in other players' companies") {
                VStack(alignment: .leading, spacing: 0) {
                    if model.loadFailed {
                        Text("Some of this could not be refreshed. It will try again by itself.").textStyle(.caption, tint: Theme.inkFaint).padding(.bottom, Theme.Space.s)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { item in
                        if item.offset > 0 { Hairline() }
                        item.element.view
                    }
                }
            }
            .centerSheet(item: $sheet, title: "", category: .medium, tone: .investment) { (s: PartnerSheet) in
                content(s).environmentObject(store).environment(online)
            }
        } else if model.loadFailed {
            LedgerSection("Shares in other players' companies") {
                EmptyState(glyph: Glyph.cloud, title: "Your shares could not be loaded.", actionTitle: "Try again", action: { Task { await model.refresh(online) } }, centered: false)
            }
        }
    }

    private struct Row: Identifiable {
        var id: String
        var view: LedgerRow
    }

    private var rows: [Row] {
        var out: [Row] = []
        let me: String? = online.accountID
        for o in model.offers {
            out.append(Row(id: "o" + o.id, view: LedgerRow(leading: .symbol("envelope"), title: "\(PartnerShareText.percent(o.pct)) of \(o.companyName)",
                                                           subtitle: "\(o.chairName ?? "A player") invites you \u{00B7} answer by \(JVClock.text(o.expiresAt))",
                                                           value: PartnerShareText.money(o.price, o.currency), pill: "Offer", pillTone: .good,
                                                           identifier: "partner-offer") { sheet = .offer(o.id) }))
        }
        for b in model.buybacks.incoming {
            let selling: Bool = b.sellerID == me
            let title: String = selling ? "\(b.buyerName ?? "The owner") offers to buy your shares in \(b.companyName)" : "\(b.sellerName ?? "A partner") asks you to buy their shares in \(b.companyName)"
            out.append(Row(id: "b" + b.id, view: LedgerRow(leading: .symbol("arrow.left.arrow.right"), title: title, subtitle: "Answer by \(JVClock.text(b.expiresAt))",
                                                           value: PartnerShareText.money(b.price, b.currency), pill: "Answer", pillTone: .warn,
                                                           identifier: "partner-buyback") { sheet = .buyback(b.id) }))
        }
        for m in model.meetings {
            let name: String = model.venture(m.ventureID)?.name ?? "the company"
            let open: Bool = m.items.contains { (i: VentureMeetingItem) -> Bool in i.myVote == nil }
            out.append(Row(id: "m" + m.id, view: LedgerRow(leading: .symbol("calendar"), title: m.planned ? "Board meeting of \(name)" : "Emergency vote at \(name)",
                                                           subtitle: "\(m.items.count == 1 ? "1 item" : "\(m.items.count) items") \u{00B7} \(PartnerShareText.countdown(to: m.deadline))",
                                                           pill: open ? "Vote" : "Voted", pillTone: open ? .warn : .neutral,
                                                           identifier: "partner-meeting") { sheet = .meeting(m.id) }))
        }
        for v in model.held {
            let pct: Double = v.partner(me)?.percent ?? 0
            out.append(Row(id: "v" + v.id, view: LedgerRow(leading: .symbol("person.2"), title: v.name,
                                                           subtitle: "Run by \(v.chairName ?? "a player") \u{00B7} you hold \(PartnerShareText.percent(pct))",
                                                           value: PartnerShareText.money(v.value * pct / 100, v.currency), valueNote: "your share",
                                                           identifier: "partner-holding") { sheet = .holding(v.id) }))
        }
        return out
    }

    @ViewBuilder private func content(_ s: PartnerSheet) -> some View {
        switch s {
        case .offer(let id): PartnerOfferSheet(offerID: id)
        case .holding(let id): PartnerHoldingSheet(ventureID: id)
        case .meeting(let id): PartnerMeetingSheet(meetingID: id)
        case .buyback(let id): PartnerBuybackSheet(offerID: id)
        }
    }
}

// Decline on the left, accept on the right, "Later" below: the same layout as every decision.
private struct PartnerAnswerFooter: View {
    var accept: String
    var busy: Bool
    var onAccept: () -> Void
    var onDecline: () -> Void
    var onLater: () -> Void

    var body: some View {
        DecisionChoices(labels: [accept, "Decline"], identifier: { (i: Int) -> String in i == 0 ? "partner-accept" : "partner-decline" },
                        later: onLater, laterIdentifier: "confirm-cancel",
                        pick: { (i: Int) in if i == 0 { onAccept() } else { onDecline() } })
            .disabled(busy)
            .padding(.top, 8)
    }
}

struct PartnerOfferSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    @ObservedObject private var model = PartnerSharesModel.shared
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var offerID: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let o = model.offers.first(where: { (x: VentureOffer) -> Bool in x.id == offerID }) {
                let price: String = PartnerShareText.money(o.price, o.currency)
                let lockEnd: Date = Date().addingTimeInterval(Double(o.lockWeeks ?? JVRules.lockUpWeeks) * 86400)
                Text("\(o.chairName ?? "A player") invites you into \(o.companyName)").popupText(.title)
                FigureCard(items: [
                    .init(label: "Your share", value: PartnerShareText.percent(o.pct)),
                    .init(label: "Price", value: price),
                    .init(label: "Fair value", value: PartnerShareText.money(o.fair, o.currency)),
                ])
                line("You pay \(price) from your cash when you accept. The money goes into the company.")
                line(o.price < o.fair ? "The price is below what this share is worth today." : o.price > o.fair ? "The price is above what this share is worth today." : "The price is what this share is worth today.")
                line("You cannot sell or leave before \(JVClock.text(lockEnd)). After that you can ask the owner to buy your shares.")
                line("You vote at its board meetings. A proposal passes with yes votes from more than half of all shares.")
                line("Dividends are paid to all owners by their shares.")
                Text("The offer is open until \(JVClock.text(o.expiresAt)).").popupText(.caption)
                Color.clear.frame(height: 0)
                    .popupFooter {
                        PartnerAnswerFooter(accept: "Accept and pay \(price)", busy: model.busy, onAccept: { reply(o, true) }, onDecline: { reply(o, false) }, onLater: { dismiss() })
                    }
            } else {
                Text("This offer is no longer open.").popupText(.body)
            }
        }
    }

    private func line(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 7)
            Text(text).popupText(.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reply(_ o: VentureOffer, _ accept: Bool) {
        Task { @MainActor in
            if let why = await model.answer(o, accept: accept, store: store, online: online) {
                Haptics.warning()
                store.tell(accept ? "Not accepted" : "Not declined", why, tone: "warn")
                return
            }
            Haptics.success()
            dismiss()
            if accept {
                store.tell("You are a partner in \(o.companyName)", "You hold \(PartnerShareText.percent(o.pct)) and paid \(PartnerShareText.money(o.price, o.currency)). Board votes and dividends show under Ventures.", tone: "good")
            } else {
                store.tell("Offer declined", "\(o.chairName ?? "The owner") is told you said no. Nothing was paid.")
            }
        }
    }
}

struct PartnerBuybackSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    @ObservedObject private var model = PartnerSharesModel.shared
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var offerID: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let b = model.buybacks.incoming.first(where: { (x: VentureBuyback) -> Bool in x.id == offerID }) {
                let selling: Bool = b.sellerID == online.accountID
                let price: String = PartnerShareText.money(b.price, b.currency)
                let share: String = PartnerShareText.percent(b.percent ?? 0)
                Text(selling ? "\(b.buyerName ?? "The owner") wants to buy your shares" : "\(b.sellerName ?? "A partner") wants to sell to you").popupText(.title)
                FigureCard(items: [
                    .init(label: "Shares", value: share),
                    .init(label: "Price", value: price),
                    .init(label: "Fair value", value: PartnerShareText.money(b.fair, b.currency)),
                ])
                if selling {
                    Text("If you accept, you are paid \(price) at once and leave the board of \(b.companyName). If you decline, nothing changes and you keep your shares.").popupText(.body)
                } else {
                    Text("If you accept, you pay \(price) from your cash and their \(share) of \(b.companyName) becomes yours. If you decline, they stay a partner.").popupText(.body)
                }
                Text("Open until \(JVClock.text(b.expiresAt)).").popupText(.caption)
                Color.clear.frame(height: 0)
                    .popupFooter {
                        PartnerAnswerFooter(accept: selling ? "Sell for \(price)" : "Buy for \(price)", busy: model.busy, onAccept: { reply(b, true) }, onDecline: { reply(b, false) }, onLater: { dismiss() })
                    }
            } else {
                Text("This offer is no longer open.").popupText(.body)
            }
        }
    }

    private func reply(_ b: VentureBuyback, _ accept: Bool) {
        let selling: Bool = b.sellerID == online.accountID
        Task { @MainActor in
            if let why = await model.answer(b, accept: accept, store: store, online: online) {
                Haptics.warning()
                store.tell("Not done", why, tone: "warn")
                return
            }
            Haptics.success()
            dismiss()
            if !accept { store.tell("Offer declined", "Nothing has changed.") }
            else if selling { store.tell("Shares sold", "\(PartnerShareText.money(b.price, b.currency)) is in your account and you have left \(b.companyName).", tone: "good") }
            else { store.tell("Shares bought", "\(b.sellerName ?? "Your partner") has left \(b.companyName). Their shares are yours.", tone: "good") }
        }
    }
}

struct PartnerMeetingSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    @ObservedObject private var model = PartnerSharesModel.shared
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var meetingID: String
    @State private var picks: [String: String] = [:]

    private static let titles: [String] = ["Against", "For", "Abstain"]
    private func choice(_ title: String) -> String { title == "For" ? "yes" : title == "Against" ? "no" : "abstain" }
    private func title(_ choice: String?) -> String { choice == "yes" ? "For" : choice == "no" ? "Against" : "Abstain" }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let m = model.meetings.first(where: { (x: VentureMeetingInfo) -> Bool in x.id == meetingID }) {
                let v: VentureInfo? = model.venture(m.ventureID)
                let pct: Double = v?.partner(online.accountID)?.percent ?? 0
                Text(m.planned ? "Weekly board meeting of \(v?.name ?? "the company")" : "\(m.calledBy ?? "A co-owner") called an emergency vote at \(v?.name ?? "the company")")
                    .popupText(.title).fixedSize(horizontal: false, vertical: true)
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    Text("\(PartnerShareText.countdown(to: m.deadline, from: context.date)) \u{00B7} \(JVClock.text(m.deadline))").popupText(.risk)
                }
                Text("You vote with \(PartnerShareText.percent(pct)) of the shares. An item passes only with yes votes from more than half of all shares; a vote you do not cast counts as an abstention.")
                    .popupText(.caption)
                ForEach(m.items) { (it: VentureMeetingItem) in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(it.title ?? "A proposal").popupText(.body)
                        Text("If this passes: \(PartnerShareText.effect(it, venture: v, share: pct))").popupText(.caption)
                        Text(standing(it, total: m.totalShares ?? Double(v?.totalShares ?? 0), by: it.proposedBy)).popupText(.caption)
                        SegmentedPill(items: Self.titles, title: { $0 }, selection: Binding(
                            get: { title(picks[it.id] ?? it.myVote) },
                            set: { picks[it.id] = choice($0) }))
                    }
                    .padding(.vertical, 4)
                }
                Color.clear.frame(height: 0)
                    .popupFooter {
                        PopupFooter(cancel: "Later", action: "Cast my votes", onCancel: { dismiss() }, onAction: { cast(m) }, actionEnabled: !model.busy, actionID: "partner-cast")
                    }
            } else {
                Text("This meeting is over. What it decided is in your messages.").popupText(.body)
            }
        }
    }

    private func standing(_ it: VentureMeetingItem, total: Double, by: String?) -> String {
        let yes: Int = total > 0 ? Int(((it.yesShares ?? 0) / total * 100).rounded()) : 0
        let no: Int = total > 0 ? Int(((it.noShares ?? 0) / total * 100).rounded()) : 0
        return (by.map { "Put by \($0). " } ?? "") + "Of all shares so far: for \(yes)% \u{00B7} against \(no)%."
    }

    private func cast(_ m: VentureMeetingInfo) {
        var all: [String: String] = [:]
        for it in m.items { all[it.id] = picks[it.id] ?? it.myVote ?? "abstain" }
        Task { @MainActor in
            if let why = await model.vote(all, store: store, online: online) {
                Haptics.warning()
                store.tell("Votes not recorded", why, tone: "warn")
                return
            }
            Haptics.success()
            dismiss()
            store.tell("Votes recorded", "You can change them until voting closes. What the owners decide is carried out by the game.", tone: "good")
        }
    }
}

struct PartnerHoldingSheet: View {
    @EnvironmentObject var store: GameStore
    @Environment(OnlineSession.self) private var online
    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.popupClose) private var popupClose
    @ObservedObject private var model = PartnerSharesModel.shared
    private func dismiss() { if let close = popupClose { close() } else { systemDismiss() } }
    var ventureID: String
    @State private var factor: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let v = model.venture(ventureID), let me = v.partner(online.accountID) {
                let pct: Double = me.percent ?? 0
                let fair: Double = v.totalShares > 0 ? (v.value * Double(me.shares) / Double(v.totalShares) * 100).rounded() / 100 : 0
                Text(v.name).popupText(.title)
                Text("Run by \(v.chairName ?? "a player"). \(PartnerShareText.policy(v.dividendPolicy)).").popupText(.caption)
                FigureCard(items: [
                    .init(label: "Your share", value: PartnerShareText.percent(pct)),
                    .init(label: "Worth now", value: PartnerShareText.money(fair, v.currency)),
                    .init(label: "Company", value: PartnerShareText.money(v.value, v.currency)),
                ])
                ForEach(v.partners, id: \.memberID) { (p: VenturePartner) in
                    ListRow(symbol: p.memberID == me.memberID ? "person.fill" : "person", tint: p.memberID == me.memberID ? Theme.accent : Theme.inkSoft,
                            title: p.memberID == me.memberID ? "You" : (p.name ?? "A partner"), subtitle: p.memberID == v.chairID ? "Owner, runs the company" : "Partner",
                            trailing: PartnerShareText.percent(p.percent ?? 0))
                }
                if let next = v.nextMeetingAt { Text("Next board meeting: \(JVClock.text(next)).").popupText(.caption) }
                selling(v, me, fair: fair)
            } else {
                Text("You no longer hold shares in this company.").popupText(.body)
            }
        }
    }

    @ViewBuilder private func selling(_ v: VentureInfo, _ me: VenturePartner, fair: Double) -> some View {
        let band: ClosedRange<Double> = store.engine?.state.worldRules.ventureBand ?? JVRules.priceBand
        let price: Double = min(max((fair * factor * 100).rounded() / 100, (fair * band.lowerBound * 100).rounded(.up) / 100), (fair * band.upperBound * 100).rounded(.down) / 100)
        Text("Selling your shares").capsLabel()
        if let asked = model.asked.first(where: { (b: VentureBuyback) -> Bool in b.ventureID == v.id }) {
            Text("You asked \(v.chairName ?? "the owner") to buy your shares for \(PartnerShareText.money(asked.price, asked.currency)). They can accept or decline until \(JVClock.text(asked.expiresAt)).")
                .popupText(.body)
            Button { withdraw(asked) } label: { Text("Take the request back") }
                .buttonStyle(TertiaryButtonStyle(tint: Theme.inkSoft))
                .disabled(model.busy)
                .accessibilityIdentifier("partner-exit-withdraw")
        } else if let lock = me.lockUntil, lock > Date() {
            Text("You cannot sell or leave before \(JVClock.text(lock)).").popupText(.caption)
        } else if fair <= 0 {
            Text("The company is worth nothing right now, so its shares cannot be priced.").popupText(.caption)
        } else {
            Text("Ask \(v.chairName ?? "the owner") to buy your shares. You set the price; they accept or decline. Nothing moves until they accept.").popupText(.caption)
            LedgerSlider(value: $factor, in: band, step: 0.05, valueText: PartnerShareText.money(price, v.currency))
            Button { ask(v, price) } label: { Text("Ask for \(PartnerShareText.money(price, v.currency))").frame(maxWidth: .infinity) }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                .disabled(model.busy)
                .accessibilityIdentifier("partner-exit-ask")
        }
    }

    private func ask(_ v: VentureInfo, _ price: Double) {
        Haptics.tap()
        Task { @MainActor in
            if let why = await model.askExit(v, price: price, store: store, online: online) {
                Haptics.warning()
                store.tell("Not sent", why, tone: "warn")
                return
            }
            Haptics.success()
            store.tell("Request sent", "\(v.chairName ?? "The owner") has your request. Nothing moves until they accept; they may also decline.", tone: "good")
        }
    }

    private func withdraw(_ b: VentureBuyback) {
        Haptics.tap()
        Task { @MainActor in
            if let why = await model.withdraw(b, online: online) { store.tell("Not taken back", why, tone: "warn") }
            else { store.tell("Request taken back", "You keep your shares. Nothing has changed.") }
        }
    }
}
