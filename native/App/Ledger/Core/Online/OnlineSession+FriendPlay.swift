import Foundation
import GameCore
import Finance
import Businesses
import Simulation

extension OnlineSession {
    func syncFriendPlay(store: GameStore) async {
        await receiveGifts(store: store)
        await receivePassNotices(store: store)
        await noteRichPass(store: store)
    }

    private func receiveGifts(store: GameStore) async {
        guard let gifts = try? await service.receivedGifts(), !gifts.isEmpty else { return }
        var done: [String] = []
        for g in gifts {
            await StoreSession.shared.receiveGift(ArtifactItem(defID: g.defID, serial: g.serial))
            let what: String = ArtifactCatalog.def(g.defID)?.name ?? "a piece"
            let text: String = GiftRules.arrivalText(from: g.fromName, item: what)
            _ = store.act { (e: inout GameEngine) -> Bool in
                e.update { (s: inout GameState, _: GameData, _: FinanceContext) in
                    s.addMessage(from: g.fromName, title: "A gift from \(g.fromName)", body: text, tone: "good")
                }
                return true
            }
            done.append(g.id)
        }
        try? await service.acknowledgeGifts(done)
    }

    private func receivePassNotices(store: GameStore) async {
        guard let list = try? await service.passNotices() else { return }
        for text in list { store.tell("Net worth board", text, tone: "n") }
    }

    private func noteRichPass(store: GameStore) async {
        guard let id = accountID, store.engine != nil else { return }
        let rows: [LeaderboardSubmission] = await LeaderboardBackend.make().submissions()
        guard !rows.isEmpty, let mine = store.engine?.leaderboardSubmission(playerID: id) else { return }
        let rivals: [RichRival] = rows.filter { (r: LeaderboardSubmission) -> Bool in r.playerID != id }.map { (r: LeaderboardSubmission) -> RichRival in
            RichRival(id: r.playerID, name: r.name, netWorth: r.netWorth, isReal: !SampleRoster.isComputer(r.playerID), visible: false)
        }
        guard let found = store.act({ (e: inout GameEngine) -> [RichRival] in e.notePassedPlayers(rivals, netWorth: mine.netWorth) }), !found.isEmpty else { return }
        var named: [RichRival] = []
        for r in found {
            var x: RichRival = r
            if let p = try? await service.profile(id: r.id) {
                x.visible = p.privacy == .everyone
                x.name = p.displayName
            }
            named.append(x)
        }
        if let text = RichPass.myNotice(named) { store.tell("Net worth board", text, tone: "good") }
        let visible: Bool = profile?.privacy == .everyone
        let text: String = RichPass.theirNotice(passer: profile?.displayName ?? "", visible: visible)
        try? await service.sendPassNotice(to: found.map { (r: RichRival) -> String in r.id }, text: text)
    }
}
