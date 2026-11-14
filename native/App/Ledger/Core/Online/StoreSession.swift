import Foundation
import Observation
import Simulation

struct AuctionPurse {
    var cash: Int
    var priceLevel: Double
    var format: (Int) -> String
}

/// One item on today's cosmetics shelf, at its shelf price.
struct ShelfPick: Identifiable, Equatable {
    var item: GoldCosmetic
    var price: Int
    var id: String { item.id }
}

/// Mission gold the server has not confirmed yet; sent again until it answers.
private struct OwedMissionGold: Codable, Equatable {
    var id: String
    var period: String
    var gold: Int
}

@MainActor @Observable
final class StoreSession {
    static let shared = StoreSession()

    private(set) var state = StoreState()
    private(set) var auctions: AuctionsSnapshot?
    private(set) var loaded = false
    /// What the server keeps for the account; nil without the online server or before its first answer.
    private(set) var server: ServerStoreInfo?
    /// True while the server wallet cannot be reached: the last known wallet is shown and nothing can be spent.
    private(set) var readOnly = false
    var problem: String?
    private(set) var notes: [String] = []
    private(set) var pendingOpening: BoxOpening?
    @ObservationIgnored private var opening = false

    @ObservationIgnored var moneyPrizeHandler: ((Int, String) -> Void)?
    /// Pays a money pack (pack id, claim id) into the open game's account; returns the game money paid.
    @ObservationIgnored var moneyPackHandler: ((String, String) -> Double?)?
    @ObservationIgnored var purse: (() -> AuctionPurse?)?
    @ObservationIgnored var cashHandler: ((Int, String, String) -> Void)?
    /// Told whether the account is an administrator each time the server answers, so the game can open every level gate.
    @ObservationIgnored var adminHandler: ((Bool) -> Void)?
    /// Told the cosmetic id when a mission claim also found a clothing item.
    @ObservationIgnored var lootHandler: ((String) -> Void)?
    @ObservationIgnored private let store: any StoreService
    @ObservationIgnored private let market: any AuctionService
    @ObservationIgnored private let remote: ServerStore?
    @ObservationIgnored private let vault: GoldVault
    @ObservationIgnored private var settledAccount: String?
    @ObservationIgnored private var levelAsked = 0
    @ObservationIgnored private var loading = false

    init() {
        let backend = StoreBackend.make()
        store = backend.store
        market = backend.auctions
        remote = backend.server
        vault = backend.vault
        TrustedClock.remember(lastServerTime: ServerStoreCache.lastServerTime)
        if remote != nil, let cached = ServerStoreCache.load() {
            state = cached.state
            server = cached.info
            readOnly = true
            applyPrices(cached.info)
        }
    }

    var isServerBacked: Bool { remote != nil }
    /// Gold can be spent and rewards claimed: always with the local vault, only while the server answers otherwise.
    var canSpend: Bool { remote == nil || (!readOnly && server != nil) }

    var gold: Int { state.wallet.balance }
    var available: Int { state.wallet.available }
    var cash: Int { purse?()?.cash ?? 0 }
    var heldCash: Int { AuctionRules.held(by: GoldVault.meID, in: auctions?.auctions ?? []) }
    var spendableCash: Int { max(0, cash - heldCash) }
    var priceLevel: Double { purse?()?.priceLevel ?? 1 }
    func money(_ n: Int) -> String { purse?()?.format(n) ?? n.formatted() }

    func load() async {
        guard remote != nil else {
            state = await store.state()
            let refund: Int = SeasonModel.shared.refundRetired()
            if refund > 0 { state = await store.grantFromSeason(boxes: 0, gold: refund) }
            loaded = true
            return
        }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        await refreshServer()
        loaded = true
    }

    private func message(_ error: Error) -> String { (error as? LocalizedError)?.errorDescription ?? "That did not work. Try again." }

    private var offlineText: String { StoreError.offline.errorDescription ?? "You are offline." }

    // MARK: Server wallet

    private func refreshServer() async {
        guard let remote else { return }
        do {
            adopt(try await remote.state())
            await settleAccount()
        } catch {
            readOnly = true
        }
    }

    /// Takes the server's answer as the truth and mirrors it into the pass and look models.
    private func adopt(_ snap: ServerStoreSnapshot) {
        state = snap.state
        server = snap.info
        readOnly = false
        applyPrices(snap.info)
        TrustedClock.sync(serverTime: snap.info.serverTime)
        ServerStoreCache.save(snap)
        SeasonModel.shared.syncServer(snap.info, replace: snap.info.imported || UserDefaults.standard.bool(forKey: Self.importedKey))
        for id in snap.info.cosmetics where AvatarCatalog.def(id) != nil { AvatarModel.shared.grant(id) }
        adminHandler?(snap.info.isAdmin ?? false)
    }

    /// The server's prices and event rotation win over the content tables everywhere the app shows a price.
    private func applyPrices(_ info: ServerStoreInfo) {
        var groups: [String: [String: Int]] = info.prices ?? [:]
        if let ev = info.events { groups["events"] = ["rotation": ev.rotation, "nextDay": ev.nextDay] }
        guard groups != appliedPrices else { return }
        appliedPrices = groups
        ServerPriceBook.shared.replace(groups)
        priceVersion += 1
    }

    @ObservationIgnored private var appliedPrices: [String: [String: Int]] = [:]
    /// Bumped whenever the prices or the event rotation change, so price rows redraw.
    private(set) var priceVersion = 0

    private func run<T>(_ call: () async throws -> T) async -> T? {
        problem = nil
        guard canSpend else {
            await refreshServer()
            guard canSpend else { problem = offlineText; return nil }
            return await runOnce(call)
        }
        return await runOnce(call)
    }

    private func runOnce<T>(_ call: () async throws -> T) async -> T? {
        do { return try await call() } catch OnlineError.offline {
            readOnly = true
            problem = offlineText
            return nil
        } catch OnlineError.notSignedIn {
            readOnly = true
            problem = offlineText
            return nil
        } catch {
            problem = message(error)
            return nil
        }
    }

    /// Once per account and launch: move the phone's old wallet over, pay retired-item refunds and owed game money.
    private func settleAccount() async {
        guard let remote, let info = server else { return }
        if settledAccount != info.account {
            settledAccount = info.account
            await importLocal(remote, info: info)
            let retired: Set<String> = Set(RetiredCosmetics.refunds.map(\.id))
            if !(server?.cosmetics ?? []).filter({ (id: String) -> Bool in retired.contains(id) }).isEmpty,
               let data = try? await remote.online.storeClaimRefunds(), let snap = try? remote.snapshot(data) {
                adopt(snap)
            }
        }
        await payOwedMoney()
        if UserDefaults.standard.string(forKey: Self.adClaimKey) != nil { _ = await claimAdGold() }
        await payMissionGold()
        if levelAsked > (server?.levelGoldPaid ?? 0) { await claimLevel(levelAsked) }
    }

    private static let importedKey = "ledger.store.importedLocal"

    private func importLocal(_ remote: ServerStore, info: ServerStoreInfo) async {
        guard !info.imported, !UserDefaults.standard.bool(forKey: Self.importedKey) else { return }
        let local: StoreState = await vault.state()
        let export: LocalStoreExport = LocalStoreImport.export(local)
        if export.isEmpty { UserDefaults.standard.set(true, forKey: Self.importedKey); return }
        guard let payload = try? JSONEncoder().encode(export) else { return }
        guard let data = try? await remote.online.storeImport(device: DeviceIdentity.current, payload: payload),
              let out = try? remote.body(ServerImport.self, data) else { return }
        if out.imported || out.reason == "device" {
            UserDefaults.standard.set(true, forKey: Self.importedKey)
            await vault.wipeAfterImport()
        }
        if let snap = try? remote.snapshot(data) { adopt(snap) }
    }

    /// Money the server sold or rolled but the game has not booked yet; each claim id pays once per save.
    private func payOwedMoney() async {
        guard let remote, canSellForCash, let owed = server?.unpaidMoney, !owed.isEmpty else { return }
        var paid: [String] = []
        for m in owed {
            switch m.kind {
            case "prize":
                moneyPrizeHandler?(m.amount, m.id)
                paid.append(m.id)
            default:
                _ = moneyPackHandler?(m.pack ?? MoneyPacks.free.id, m.id)
                paid.append(m.id)
            }
        }
        _ = try? await remote.online.storeConfirmMoney(paid)
        server?.unpaidMoney.removeAll { (m: ServerStoreInfo.UnpaidMoney) -> Bool in paid.contains(m.id) }
    }

    private func confirmMoney(_ ids: [String]) async {
        guard let remote, !ids.isEmpty else { return }
        _ = try? await remote.online.storeConfirmMoney(ids)
        server?.unpaidMoney.removeAll { (m: ServerStoreInfo.UnpaidMoney) -> Bool in ids.contains(m.id) }
    }

    /// The signed-in account as a UUID, given to StoreKit so a purchase can only be delivered to it.
    func accountToken() async -> UUID? {
        guard let remote, let id = await remote.account() else { return nil }
        return UUID(uuidString: id)
    }

    // MARK: Purchases

    func deliver(_ item: PurchaseItem, receipt: PurchaseReceipt) async -> PurchaseDeliveryResult? {
        problem = nil
        guard let remote else {
            do {
                let result: PurchaseDeliveryResult = try await store.deliver(item, transactionID: receipt.transactionID)
                state = result.state
                return result
            } catch { problem = message(error); return nil }
        }
        guard let data = await runOnce({ try await remote.online.storePurchase(jws: receipt.jws) }),
              let out = try? remote.body(ServerPurchase.self, data) else { return nil }
        if let snap = try? remote.snapshot(data) { adopt(snap) }
        let granted: Bool = out.granted ?? false
        return PurchaseDeliveryResult(state: state, delivered: granted, gold: granted ? (out.gold ?? 0) : 0, passTiers: granted ? (out.passTiers ?? 0) : 0)
    }

    /// Apple refunded or revoked a purchase: the server takes back what is unspent and records the rest as owed.
    @discardableResult
    func revoke(_ receipt: PurchaseReceipt) async -> Bool {
        guard let remote else {
            state = await store.revoke(transactionID: receipt.transactionID)
            return true
        }
        guard let data = await runOnce({ try await remote.online.storePurchase(jws: receipt.jws) }) else { return false }
        if let snap = try? remote.snapshot(data) { adopt(snap) }
        return true
    }

    // MARK: Spending

    private static let serviceIDs: [String] = ["usernameChange", "companyNameSkip"]

    private func serviceID(price: Int) -> String {
        Self.serviceIDs.first { (id: String) -> Bool in GoldPrices.service(id) == price } ?? Self.serviceIDs[0]
    }

    @discardableResult
    func buy(_ good: GoldGood, paidBoxesAllowed: Bool) async -> Bool {
        problem = nil
        guard isAdmin || available >= good.price else { problem = StoreError.notEnoughGold(missing: good.price - available).errorDescription; return false }
        if let remote { return await buyOnServer(good, remote: remote, paidBoxesAllowed: paidBoxesAllowed) }
        do {
            switch good {
            case .boxBundle(let b):
                state = try await store.buyBoxBundle(b.id, paidBoxesAllowed: paidBoxesAllowed)
            case .cosmetic(let c):
                state = try await store.buyCosmetic(c.id, owned: SeasonModel.shared.pass.owned)
                SeasonModel.shared.grantOwned(c.id)
            case .avatar(let d):
                state = try await store.buyAvatar(d.id, owned: AvatarModel.shared.owned)
                AvatarModel.shared.grant(d.id)
            case .service(_, let price):
                state = try await store.spendGold(price)
            case .username(let price):
                state = try await store.spendGold(price)
            case .moneyPack(let pack):
                guard canSellForCash else { problem = "Open a game to buy money."; return false }
                state = try await store.spendGold(pack.gold)
                guard moneyPackHandler?(pack.id, UUID().uuidString) != nil else {
                    state = await store.grantFromSeason(boxes: 0, gold: pack.gold)
                    problem = "The money could not be paid, so your gold was returned."
                    return false
                }
            }
            return true
        } catch { problem = message(error); return false }
    }

    private func buyOnServer(_ good: GoldGood, remote: ServerStore, paidBoxesAllowed: Bool) async -> Bool {
        let request: String = UUID().uuidString
        let kind: String
        let id: String
        switch good {
        case .boxBundle(let b):
            guard paidBoxesAllowed else { problem = StoreError.paidBoxesUnavailable.errorDescription; return false }
            kind = "bundle"; id = b.id
        case .cosmetic(let c): kind = "cosmetic"; id = c.id
        case .avatar(let d): kind = "avatar"; id = d.id
        case .service(_, let price): kind = "service"; id = serviceID(price: price)
        case .username: kind = "service"; id = "usernameChange"
        case .moneyPack(let pack):
            guard canSellForCash else { problem = "Open a game to buy money."; return false }
            let used: Int = server?.moneyWeek.used ?? 0
            guard isAdmin || MoneyPacks.fitsThisWeek(pack, used: used) else {
                let room: Int = MoneyPacks.weeklyRoom(used: used)
                problem = room == 0 ? "You have bought all the money allowed this week. Try again in a few days."
                    : "This week you can spend \(room) more gold on money."
                return false
            }
            kind = "money"; id = pack.id
        }
        guard let data = await run({ try await remote.online.storeBuy(kind: kind, id: id, request: request) }) else { return false }
        if let snap = try? remote.snapshot(data) { adopt(snap) }
        switch good {
        case .cosmetic(let c): SeasonModel.shared.grantOwned(c.id)
        case .avatar(let d): AvatarModel.shared.grant(d.id)
        case .moneyPack(let pack):
            let claim: String = (try? remote.body(ServerSpend.self, data))?.claimID ?? request
            if moneyPackHandler?(pack.id, claim) != nil { await confirmMoney([claim]) }
        default: break
        }
        return true
    }

    /// The free money pack: no gold is taken. The caller has already shown the ad (when one is due).
    @discardableResult
    func claimFreeMoney() async -> Bool {
        problem = nil
        guard canSellForCash else { problem = "Open a game to get money."; return false }
        guard let remote else { return moneyPackHandler?(MoneyPacks.free.id, UUID().uuidString) != nil }
        let request: String = UUID().uuidString
        guard let data = await run({ try await remote.online.storeFreeMoney(request: request) }) else { return false }
        if let snap = try? remote.snapshot(data) { adopt(snap) }
        let claim: String = (try? remote.body(ServerSpend.self, data))?.claimID ?? request
        guard moneyPackHandler?(MoneyPacks.free.id, claim) != nil else { return false }
        await confirmMoney([claim])
        return true
    }

    func openBoxes(_ kind: BoxKind, count: Int, paidBoxesAllowed: Bool) async -> BoxOpening? {
        guard !opening, pendingOpening == nil else { return nil }
        opening = true
        defer { opening = false }
        problem = nil
        if let remote { return await openOnServer(kind, count: count, paidBoxesAllowed: paidBoxesAllowed, remote: remote) }
        do {
            let out = try await store.openBoxes(kind, count: count, owned: SeasonModel.shared.pass.owned, paidBoxesAllowed: paidBoxesAllowed)
            state = out.state
            for r in out.results {
                if case .cosmetic(let id) = r.content { SeasonModel.shared.grantOwned(id) }
                if case .money(let amount) = r.content { moneyPrizeHandler?(amount, UUID().uuidString) }
            }
            grantCollections(out.completed)
            pendingOpening = out
            return out
        } catch { problem = message(error); return nil }
    }

    private func openOnServer(_ kind: BoxKind, count: Int, paidBoxesAllowed: Bool, remote: ServerStore) async -> BoxOpening? {
        if kind.isPaid && !paidBoxesAllowed { problem = StoreError.paidBoxesUnavailable.errorDescription; return nil }
        let request: String = UUID().uuidString
        let n: Int = min(10, max(1, count))
        guard let data = await run({ try await remote.online.storeOpen(kind: kind.rawValue, count: n, request: request) }),
              let rolled = try? remote.body(ServerBoxOpening.self, data) else { return nil }
        if let snap = try? remote.snapshot(data) { adopt(snap) }
        var paid: [String] = []
        for roll in rolled.results {
            if case .cosmetic(let id) = roll.result.content { SeasonModel.shared.grantOwned(id) }
            if roll.content.type == "money", let claim = roll.content.claimID, canSellForCash {
                moneyPrizeHandler?(roll.content.amount ?? 0, claim)
                paid.append(claim)
            }
        }
        await confirmMoney(paid)
        let completed: [ArtifactCollection] = rolled.completed.compactMap { (id: String) -> ArtifactCollection? in ArtifactCatalog.collection(id) }
        grantCollections(completed)
        let out = BoxOpening(kind: kind, results: rolled.results.map(\.result), state: state, completed: completed)
        pendingOpening = out
        return out
    }

    var canSellForCash: Bool { purse?() != nil }

    func quickPrice(_ item: ArtifactItem) -> Int {
        AuctionRules.quickSalePrice(ArtifactCatalog.def(item.defID)?.rarity ?? .common, priceLevel: priceLevel)
    }

    @discardableResult
    func quickSell(_ items: [ArtifactItem]) async -> Int? {
        problem = nil
        guard canSellForCash else { problem = "Open a game to sell for cash."; return nil }
        if let remote {
            let request: String = UUID().uuidString
            let pieces: [ServerPiece] = items.map { (i: ArtifactItem) -> ServerPiece in ServerPiece(defID: i.defID, serial: i.serial) }
            guard let data = await run({ try await remote.online.storeQuickSell(pieces, request: request) }),
                  let out = try? remote.body(ServerQuickSale.self, data) else { return nil }
            if let snap = try? remote.snapshot(data) { adopt(snap) }
            let cash: Int = out.sold.reduce(0) { (sum: Int, s: ServerQuickSale.Sold) -> Int in
                sum + AuctionRules.quickSalePrice(BoxRarity(rawValue: s.rarity ?? "") ?? .common, priceLevel: priceLevel)
            }
            let what: String = out.sold.count == 1 ? (ArtifactCatalog.def(out.sold[0].defID)?.name ?? "artifact") : "\(out.sold.count) artifacts"
            cashHandler?(cash, "quick|" + request, "Quick sale: " + what)
            return cash
        }
        do {
            let out = try await store.quickSell(itemIDs: items.map(\.id), priceLevel: priceLevel)
            state = out.state
            let what: String = out.sold.count == 1 ? (ArtifactCatalog.def(out.sold[0].defID)?.name ?? "artifact") : "\(out.sold.count) artifacts"
            cashHandler?(out.cash, "quick|" + UUID().uuidString, "Quick sale: " + what)
            return out.cash
        } catch { problem = message(error); return nil }
    }

    func acknowledgeOpening() { pendingOpening = nil }

    // MARK: Rewards

    /// Gold and boxes earned on the phone; with the server these come from its own claim calls instead.
    func receiveDaily(boxes: Int, gold: Int) {
        guard remote == nil else { return }
        Task { state = await store.grantFromSeason(boxes: boxes, gold: gold) }
    }

    /// The daily login streak, counted on server days. Nil when the server cannot be reached.
    func claimLoginDay() async -> ServerLoginDay? {
        guard let remote else { return nil }
        if server == nil || readOnly { await load() }
        guard canSpend, let data = await runOnce({ try await remote.online.storeClaimLogin() }),
              let out = try? remote.body(ServerLoginDay.self, data) else { return nil }
        if let snap = try? remote.snapshot(data) { adopt(snap) }
        return out
    }

    /// Friend race gold for a finished week. Returns the gold paid and whether the week is settled.
    func claimRaceGold(week: Int) async -> (gold: Int, settled: Bool) {
        guard let remote else { return (0, false) }
        guard canSpend else { problem = offlineText; return (0, false) }
        do {
            let data: Data = try await remote.online.storeClaimRace(week: week)
            if let snap = try? remote.snapshot(data) { adopt(snap) }
            return ((try? remote.body(ServerGold.self, data))?.gold ?? 0, true)
        } catch OnlineError.rejected(let why) {
            problem = why
            return (0, why == StoreWireText.alreadyClaimed || why == StoreWireText.noReward)
        } catch {
            problem = offlineText
            return (0, false)
        }
    }

    @discardableResult
    func giveAway(_ item: ArtifactItem) async -> Bool {
        problem = nil
        guard remote != nil else {
            do { state = try await store.giveAway(itemID: item.id); return true } catch { problem = message(error); return false }
        }
        // The server moves the piece when the gift is sent; here it only leaves the shown cabinet.
        guard canSpend else { problem = offlineText; return false }
        guard state.cabinet.contains(item.id), TradeRules.isSellable(item) else { problem = "That piece cannot be sent."; return false }
        var s: StoreState = state
        s.cabinet.remove(item.id)
        state = s
        return true
    }

    func receiveGift(_ item: ArtifactItem) async {
        guard remote != nil else {
            let out = await store.receiveGift(item)
            state = out.state
            grantCollections(out.completed)
            return
        }
        // Shown now; the server adds it to the account when the gift is accepted.
        var s: StoreState = state
        let done: [ArtifactCollection] = s.cabinet.addAcquired(item)
        state = s
        grantCollections(done)
    }

    /// A Season Pass tier the pass has marked claimed; with the server the reward is paid there.
    func receiveSeason(_ r: SeasonReward, track: SeasonPass.Track = .free, tier: Int = 0) {
        if let remote {
            guard tier > 0 else { return }
            let season: Int = SeasonModel.shared.pass.seasonNumber
            Task { await claimPassOnServer(remote, season: season, track: track, tier: tier) }
            return
        }
        if r.kind == .profileCard || r.kind == .companyCard || r.kind == .artifact {
            let roll: Double = CardCatalog.roll("season|\(SeasonModel.shared.pass.season)|" + r.id)
            Task { state = await store.grantCard(defID: r.id, roll: roll) }
            return
        }
        guard r.kind == .box || r.kind == .gold else { return }
        Task { state = await store.grantFromSeason(boxes: r.kind == .box ? r.amount : 0, gold: r.kind == .gold ? r.amount : 0) }
    }

    private func claimPassOnServer(_ remote: ServerStore, season: Int, track: SeasonPass.Track, tier: Int) async {
        do {
            let data: Data = try await remote.online.storeClaimPass(season: season, track: track.rawValue, tier: tier)
            if let snap = try? remote.snapshot(data) { adopt(snap) }
            if let out = try? remote.body(ServerPassClaim.self, data) {
                grantCollections(out.completed.compactMap { (id: String) -> ArtifactCollection? in ArtifactCatalog.collection(id) })
            }
            SeasonModel.shared.serverClaimDone(track, tier: tier, kept: true)
        } catch OnlineError.rejected(let why) {
            let already: Bool = why == StoreWireText.alreadyClaimed
            SeasonModel.shared.serverClaimDone(track, tier: tier, kept: already)
            if !already { problem = why }
        } catch {
            readOnly = true
            problem = offlineText
            SeasonModel.shared.serverClaimDone(track, tier: tier, kept: false)
        }
    }

    private static let levelCardsKey = "ledger.cards.levelGranted"

    private static let levelGoldKey = "ledger.level.goldPaid"

    private func receiveLevelGold(_ level: Int) {
        let paid: Int = UserDefaults.standard.integer(forKey: Self.levelGoldKey)
        guard level > paid else { return }
        let gold: Int = LevelRewards.due(from: paid, to: level).reduce(0) { (sum: Int, r: LevelRewards.Reward) -> Int in sum + r.gold }
        UserDefaults.standard.set(level, forKey: Self.levelGoldKey)
        guard gold > 0 else { return }
        Task { state = await store.grantFromSeason(boxes: 0, gold: gold) }
    }

    func receiveLevel(_ level: Int) {
        if remote != nil {
            guard level > levelAsked else { return }
            levelAsked = level
            if let paid = server?.levelGoldPaid, level <= paid { return }
            Task { await claimLevel(level) }
            return
        }
        receiveLevelGold(level)
        let done: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Self.levelCardsKey) ?? [])
        let due: [CardCatalog.LevelReward] = CardCatalog.levelRewards(upTo: level).filter { (r: CardCatalog.LevelReward) -> Bool in !done.contains(r.defID) }
        guard !due.isEmpty else { return }
        UserDefaults.standard.set(Array(done.union(due.map(\.defID))), forKey: Self.levelCardsKey)
        Task {
            for r in due { state = await store.grantCard(defID: r.defID, roll: CardCatalog.roll("level|" + r.defID)) }
        }
    }

    private func claimLevel(_ level: Int) async {
        guard let remote, canSpend, let data = try? await remote.online.storeClaimLevel(level) else { return }
        if let snap = try? remote.snapshot(data) { adopt(snap) }
        if let out = try? remote.body(ServerLevelClaim.self, data) {
            grantCollections(out.completed.compactMap { (id: String) -> ArtifactCollection? in ArtifactCatalog.collection(id) })
        }
    }

    private func grantCollections(_ done: [ArtifactCollection]) {
        for c in done { SeasonModel.shared.grantOwned(c.rewardID) }
    }

    // MARK: Store extras

    /// An administrator account: gold never runs out, every cosmetic, the full pass, Pro and Plus, every level gate open.
    var isAdmin: Bool { server?.isAdmin ?? false }
    /// Bought something with real money or watched enough ads: a badge, more gold per ad and a shorter wait. Nothing else.
    var isSupporter: Bool { server?.supporter ?? false }
    var adTerms: ServerStoreInfo.AdTerms? { server?.ads }
    var betaRedeemed: Bool { server?.betaRedeemed ?? false }

    /// Today's cosmetics shelf: the server's pick, or the phone's own pick without the server.
    var shelf: [ShelfPick] {
        guard remote != nil else {
            return StoreRotation.pick(day: SeasonCatalog.today()).compactMap { (c: GoldCosmetic) -> ShelfPick? in
                StoreRotation.price(c).map { (p: Int) -> ShelfPick in ShelfPick(item: c, price: p) }
            }
        }
        return (server?.shelf?.items ?? []).compactMap { (i: ServerStoreInfo.Shelf.Item) -> ShelfPick? in
            GoldCosmetics.cosmetic(i.id).map { (c: GoldCosmetic) -> ShelfPick in ShelfPick(item: c, price: i.price) }
        }
    }

    // MARK: Event boxes and prices

    /// The six event boxes on sale now (the server's rotation once it has answered).
    var eventBoxes: [EventBox] {
        _ = priceVersion
        return EventBoxes.current()
    }

    /// When the event boxes change, as the start of that server day.
    var eventsEnd: Date {
        _ = priceVersion
        let left: Int = max(0, EventBoxes.nextChangeDay() - EventBoxes.utcDay())
        var cal: Calendar = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
        return cal.date(byAdding: .day, value: left, to: cal.startOfDay(for: TrustedClock.now())) ?? TrustedClock.now()
    }

    /// Administrator only: sets a store price for every player (nil goes back to the catalogue price). Other players see it on
    /// their next store refresh.
    @discardableResult
    func setPrice(kind: String, id: String, price: Int?) async -> Bool {
        guard let remote, isAdmin else { return false }
        guard let data = await run({ try await remote.online.storeSetPrice(kind: kind, id: id, price: price) }) else { return false }
        if let snap = try? remote.snapshot(data) { adopt(snap) }
        return true
    }

    enum CodeResult: Equatable { case admin, beta(Int), gift(ServerGiftReward), alreadyAdmin, betaUsed, giftUsed, expired, owned, invalid, locked, offline }

    /// Spends a typed code: an administrator code, a beta key or a gift code. Only the server can check it.
    func redeemCode(_ code: String) async -> CodeResult {
        problem = nil
        guard let remote else { return .offline }
        guard let data = await run({ try await remote.online.storeRedeem(code: code) }),
              let out = try? remote.body(ServerRedeem.self, data) else { return .offline }
        if let snap = try? remote.snapshot(data) { adopt(snap) }
        switch out.reason {
        case "granted":
            if out.kind == "admin" { return .admin }
            if out.kind == "gift" { return .gift(out.reward ?? ServerGiftReward(gold: out.gold ?? 0, items: [], boxes: [:])) }
            return .beta(out.gold ?? 0)
        case "already_admin": return .alreadyAdmin
        case "beta_used": return .betaUsed
        case "gift_used": return .giftUsed
        case "expired": return .expired
        case "owned": return .owned
        case "locked": return .locked
        default: return .invalid
        }
    }

    enum AdGold: Equatable { case paid(Int), wait(Int), doneToday, failed }

    private static let adClaimKey = "ledger.store.adClaim"

    /// Gold for an ad that has been watched. The claim id is kept until the server answers, so a retry never pays twice.
    func claimAdGold() async -> AdGold {
        let claim: String = UserDefaults.standard.string(forKey: Self.adClaimKey) ?? UUID().uuidString
        UserDefaults.standard.set(claim, forKey: Self.adClaimKey)
        guard let remote else {
            UserDefaults.standard.removeObject(forKey: Self.adClaimKey)
            state = await store.grantFromSeason(boxes: 0, gold: 1)
            return .paid(1)
        }
        guard let data = await run({ try await remote.online.storeClaimAd(claim: claim) }),
              let out = try? remote.body(ServerGoldClaim.self, data) else { return .failed }
        UserDefaults.standard.removeObject(forKey: Self.adClaimKey)
        if let snap = try? remote.snapshot(data) { adopt(snap) }
        if out.ok { return .paid(out.gold ?? 0) }
        if out.reason == "cooldown" { return .wait(max(1, out.wait ?? 60)) }
        return .doneToday
    }

    private static let missionKey = "ledger.store.missionGold"

    private var owedMissions: [OwedMissionGold] {
        get {
            guard let d = UserDefaults.standard.data(forKey: Self.missionKey) else { return [] }
            return (try? JSONDecoder().decode([OwedMissionGold].self, from: d)) ?? []
        }
        set {
            if newValue.isEmpty { UserDefaults.standard.removeObject(forKey: Self.missionKey) }
            else if let d = try? JSONEncoder().encode(Array(newValue.suffix(40))) { UserDefaults.standard.set(d, forKey: Self.missionKey) }
        }
    }

    /// Gold from a claimed mission. With the server it is paid there, once per mission and period, within daily and weekly caps.
    func receiveMission(id: String, period: String, gold: Int) {
        guard gold > 0 else { return }
        guard remote != nil else { receiveDaily(boxes: 0, gold: gold); return }
        var owed: [OwedMissionGold] = owedMissions
        let entry = OwedMissionGold(id: id, period: period, gold: gold)
        if !owed.contains(entry) { owed.append(entry) }
        owedMissions = owed
        Task { await payMissionGold() }
    }

    private func payMissionGold() async {
        guard let remote, canSpend else { return }
        for m in owedMissions {
            do {
                let data: Data = try await remote.online.storeClaimMission(id: m.id, period: m.period, gold: m.gold)
                if let snap = try? remote.snapshot(data) { adopt(snap) }
                if let found = (try? remote.body(ServerGoldClaim.self, data))?.cosmetic, !found.isEmpty {
                    SeasonModel.shared.grantOwned(found)
                    lootHandler?(found)
                }
            } catch OnlineError.rejected(_) {
                // A refused claim is never paid; it is dropped.
            } catch {
                return
            }
            owedMissions = owedMissions.filter { (o: OwedMissionGold) -> Bool in o != m }
        }
    }

    // MARK: Auctions

    func refreshAuctions() async {
        guard let p = purse?() else { return }
        apply(await market.refresh(cash: p.cash, priceLevel: p.priceLevel))
    }

    private func apply(_ snap: AuctionsSnapshot) {
        auctions = snap
        if remote == nil { state = snap.state }
        for s in snap.settled {
            grantCollections(s.completed)
            if s.cash != 0 { cashHandler?(s.cash, s.auctionID + "|" + s.status.rawValue, cashLabel(for: s)) }
            notes.append(note(for: s))
        }
    }

    private func pieceName(_ s: AuctionSettlement) -> String {
        (ArtifactCatalog.def(s.item.defID)?.name ?? "Piece") + ", " + ArtifactCatalog.label(s.item)
    }

    private func cashLabel(for s: AuctionSettlement) -> String {
        (s.seller == GoldVault.meID ? "Auction sale: " : "Auction purchase: ") + (ArtifactCatalog.def(s.item.defID)?.name ?? "artifact")
    }

    private func note(for s: AuctionSettlement) -> String {
        let piece: String = pieceName(s)
        let youSold: Bool = s.seller == GoldVault.meID
        switch s.status {
        case .sold where youSold:
            return "Sold: \(piece) for \(money(s.price)). After the \(money(s.fee)) fee you received \(money(s.price - s.fee))."
        case .sold:
            return "Won: \(piece) for \(money(s.price)). It is in your cabinet."
        case .unsold where youSold:
            return "Not sold: \(piece). It is back in your cabinet."
        default:
            return "Ended: \(piece)."
        }
    }

    func clearNotes() { notes = [] }

    @discardableResult
    func bid(_ auctionID: String, amount: Int) async -> Bool {
        problem = nil
        guard let p = purse?() else { problem = "Open a game to bid."; return false }
        do { apply(try await market.placeBid(auctionID: auctionID, amount: amount, cash: p.cash)); return true } catch { problem = message(error); return false }
    }

    @discardableResult
    func buyNow(_ auctionID: String) async -> Bool {
        problem = nil
        guard let p = purse?() else { problem = "Open a game to buy."; return false }
        do { apply(try await market.buyNow(auctionID: auctionID, cash: p.cash)); return true } catch { problem = message(error); return false }
    }

    @discardableResult
    func list(itemID: String, startPrice: Int, reserve: Int?, buyNow: Int?, duration: AuctionDuration) async -> Bool {
        problem = nil
        do { apply(try await market.list(itemID: itemID, startPrice: startPrice, reserve: reserve, buyNow: buyNow, duration: duration)); return true } catch { problem = message(error); return false }
    }

    @discardableResult
    func cancel(_ auctionID: String) async -> Bool {
        problem = nil
        do { apply(try await market.cancel(auctionID: auctionID)); return true } catch { problem = message(error); return false }
    }

    func name(of playerID: String) -> String { auctions?.names[playerID] ?? "A player" }
}

/// Reads the phone's wallet, pass and look from before the server kept them, for the one-time move.
@MainActor enum LocalStoreImport {
    static func export(_ local: StoreState) -> LocalStoreExport {
        let pass: SeasonPass = SeasonModel.shared.pass
        let premium: Int = SeasonModel.shared.premiumSeason == pass.season ? pass.seasonNumber : 0
        let streak: LoginStreak = StreakModel.shared.streak
        return LocalStoreExport(
            gold: local.wallet.balance,
            boxes: local.boxes,
            pity: local.pity.sinceRare,
            firstPurchaseDone: local.firstPurchaseDone,
            items: local.cabinet.items,
            cosmetics: Array(pass.owned.union(AvatarModel.shared.owned)).sorted(),
            passClaims: Array(pass.claimed).sorted(),
            premiumSeason: premium,
            levelGoldPaid: UserDefaults.standard.integer(forKey: "ledger.level.goldPaid"),
            levelCards: UserDefaults.standard.stringArray(forKey: "ledger.cards.levelGranted") ?? [],
            refunded: Array(pass.refunded ?? []).sorted(),
            streak: streak.count,
            streakBest: streak.best,
            streakOpenedToday: StreakModel.shared.openedToday)
    }
}
