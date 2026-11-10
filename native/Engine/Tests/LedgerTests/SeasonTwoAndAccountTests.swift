import XCTest
import GameCore
@testable import Simulation

final class SeasonTwoAndAccountTests: XCTestCase {
    private let t0: Double = 1_000_000
    private let me = "me"

    private var start1: Int { SeasonCatalog.firstSeasonStart ?? 0 }

    func testSeasonTwoIsServedAndNotFounder() throws {
        let s2: SeasonDef = try XCTUnwrap(SeasonCatalog.def(2))
        XCTAssertEqual(s2.name, "Spring Market")
        XCTAssertEqual(s2.theme, "spring")
        XCTAssertFalse(s2.founderEdition)
        XCTAssertTrue(ItemThemes.isKnown("spring"))
        XCTAssertEqual(SeasonCatalog.active(2)?.number, 2, "season 2 no longer falls back to season 1")
        XCTAssertEqual(SeasonCatalog.active(1)?.number, 1)
        XCTAssertEqual(SeasonRewards.reward(.free, tier: 1, season: 2)?.id, "badge.s2.sprout")
        XCTAssertEqual(SeasonRewards.reward(.free, tier: 1, season: 1)?.id, "badge.s1.first")
        XCTAssertNotNil(SeasonRewards.reward(.free, tier: 30, season: 2))
        XCTAssertNotNil(SeasonRewards.reward(.premium, tier: 30, season: 2))
        XCTAssertTrue(s2.rewards.allSatisfy { !$0.founderEdition && !$0.accountBound })
    }

    func testSeasonTwoRewardsAreUniqueMixedAndResolvable() throws {
        let s2: SeasonDef = try XCTUnwrap(SeasonCatalog.def(2))
        let others: Set<String> = Set(SeasonRewards.all.filter { $0.season != 2 }.map(\.id))
        let ids: [String] = s2.rewards.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(Set(ids).isDisjoint(with: others), "reward ids are unique across seasons")
        XCTAssertTrue(Set(ids).isDisjoint(with: Set(GoldCosmetics.all.map(\.id))))
        var slots: Set<String> = []
        for r in s2.rewards { XCTAssertTrue(slots.insert("\(r.premium)\(r.tier)").inserted, r.id) }
        let kinds: Set<SeasonReward.Kind> = Set(s2.rewards.map(\.kind))
        for k in [SeasonReward.Kind.artifact, .xp, .gold, .box, .profileCard, .companyCard, .theme, .namePlate, .backdrop, .badge] {
            XCTAssertTrue(kinds.contains(k), "season 2 should hold a \(k.label)")
        }
        let rarities: Set<BoxRarity> = Set(s2.rewards.compactMap(\.rarity))
        XCTAssertEqual(rarities, Set(BoxRarity.allCases), "rewards come in every rarity")
        let companyLogos: Set<String> = Set(s2.rewards.filter { $0.kind == .companyCard }.compactMap { CardCatalog.def($0.id)?.logo })
        XCTAssertTrue(companyLogos.contains("car.fill") && companyLogos.contains("sailboat.fill"), "a car and a boat")
        for r in s2.rewards where r.kind == .artifact {
            XCTAssertNotNil(ArtifactCatalog.defs.first { $0.id == r.id }, r.id)
            XCTAssertEqual(r.rarity, ArtifactCatalog.def(r.id)?.rarity)
            XCTAssertEqual(r.theme, "spring")
        }
        for r in s2.rewards where r.kind == .profileCard || r.kind == .companyCard {
            XCTAssertNotNil(CardCatalog.def(r.id), r.id)
            XCTAssertEqual(r.theme, "spring")
        }
        let spring: ArtifactCollection? = ArtifactCatalog.collection("spring")
        XCTAssertEqual(spring?.members.count, 4)
        XCTAssertNotNil(GoldCosmetics.cosmetic(spring?.rewardID ?? ""))
    }

    func testSeasonTwoStartsHalfAYearAfterSeasonOneAroundEaster() throws {
        XCTAssertNotNil(SeasonCatalog.firstSeasonStart)
        XCTAssertEqual(SeasonCatalog.startDay(of: 2), start1 + SeasonPass.seasonDays)
        let s2: Int = try XCTUnwrap(SeasonCatalog.startDay(of: 2))
        let easter2027: Int = SeasonCatalog.eraDay(year: 2027, month: 3, day: 28)
        XCTAssertLessThanOrEqual(abs(s2 - easter2027), 7, "season 2 opens within a week of Easter 2027")
        XCTAssertEqual(SeasonCatalog.number(onDay: s2 - 1), 1)
        XCTAssertEqual(SeasonCatalog.number(onDay: s2), 2)
        XCTAssertEqual(SeasonCatalog.number(onDay: start1 - 30), 1)
    }

    func testAPassAlignedToTheCalendarMovesToSeasonTwoWithTheCalendar() throws {
        var p = SeasonPass(today: start1 + 40)
        p.align(firstDay: start1, today: start1 + 40)
        XCTAssertEqual(p.seasonNumber, 1)
        XCTAssertEqual(p.firstDay, start1)
        p.xp = 300
        XCTAssertFalse(p.rollover(today: start1 + SeasonPass.seasonDays - 1))
        XCTAssertTrue(p.rollover(today: start1 + SeasonPass.seasonDays))
        XCTAssertEqual(p.seasonNumber, 2)
        XCTAssertEqual(p.seasonDef?.name, "Spring Market")
        XCTAssertEqual(p.reward(.free, tier: 1)?.id, "badge.s2.sprout")
        var q = SeasonPass(today: start1 + SeasonPass.seasonDays + 3)
        q.xp = 600
        q.align(firstDay: start1, today: start1 + SeasonPass.seasonDays + 3)
        XCTAssertEqual(q.seasonNumber, 2)
        XCTAssertEqual(q.xp, 0, "a pass moved into a new season starts it fresh")
        q.align(firstDay: start1, today: start1 + SeasonPass.seasonDays + 3)
        q.xp = 50
        q.align(firstDay: start1, today: start1 + SeasonPass.seasonDays + 4)
        XCTAssertEqual(q.xp, 50, "aligning again changes nothing")
    }

    func testXPRewardAndArtifactRewardClaim() {
        var p = SeasonPass(today: 1)
        p.season = 1
        p.xp = SeasonPass.xpPerTier * 2
        guard case .claimed(let r) = p.claim(.free, tier: 2, isPlus: false) else { return XCTFail("tier 2 xp boost") }
        XCTAssertEqual(r.kind, .xp)
        XCTAssertEqual(p.xp, SeasonPass.xpPerTier * 2 + 60)
        XCTAssertFalse(TradeRules.isSellable(reward: r))
        let art: SeasonReward? = SeasonRewards.reward(.free, tier: 7, season: 2)
        XCTAssertEqual(art?.kind, .artifact)
        XCTAssertEqual(art?.title, "Painted egg")
        XCTAssertTrue(art.map { TradeRules.isSellable(reward: $0) } ?? false)
    }

    func testFirstOwnerIsRecordedAndPersisted() throws {
        let found = ArtifactItem(defID: "abacus", serial: 14)
        XCTAssertTrue(found.isFirstOwner)
        var c = Cabinet()
        c.add(found)
        let back: Cabinet = try JSONDecoder().decode(Cabinet.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
        XCTAssertTrue(back.items[0].isFirstOwner)

        let legacy = Data(#"{"items":[{"defID":"abacus","serial":3}],"rewarded":[]}"#.utf8)
        let old: Cabinet = try JSONDecoder().decode(Cabinet.self, from: legacy)
        XCTAssertTrue(old.items[0].isFirstOwner, "a piece saved before the mark existed counts as found")

        var b = AuctionBook(me: me)
        b.auctions.append(Auction(id: "A1", item: found, seller: "seller", startPrice: 100, reserve: nil, buyNow: nil, startsAt: t0, endsAt: t0 + 3_600, duration: .oneHour))
        _ = try b.place("A1", bidder: me, amount: 100, now: t0 + 10, cash: 500)
        var mine = Cabinet()
        let done = b.settleDue(now: t0 + 4_000, cash: 500, cabinet: &mine)
        XCTAssertEqual(done.first?.status, .sold)
        XCTAssertEqual(mine.items.first?.origin, .acquired)
        XCTAssertFalse(mine.items[0].isFirstOwner, "an auction win is not a first-owner piece")
        let saved: Cabinet = try JSONDecoder().decode(Cabinet.self, from: JSONEncoder().encode(mine))
        XCTAssertEqual(saved.items.first?.origin, .acquired)
        XCTAssertFalse(saved.items[0].isFirstOwner)

        var gifted = Cabinet()
        gifted.addAcquired(ArtifactItem(defID: "scales", serial: 2))
        XCTAssertFalse(gifted.items[0].isFirstOwner)

        var again = AuctionBook(me: me)
        var seller = Cabinet()
        seller.add(found)
        let listed: Auction = try again.list(found.id, startPrice: 50, reserve: nil, duration: .oneHour, now: t0, cabinet: &seller)
        XCTAssertEqual(listed.item.origin, .found, "listing keeps the mark; only the new owner is marked acquired")
        try again.cancel(listed.id, cabinet: &seller)
        XCTAssertTrue(seller.items[0].isFirstOwner, "a returned piece stays first-owner")
    }

    func testStoreBoughtPiecesAreAccountBoundAndNeverTraded() throws {
        var c = Cabinet()
        let item = ArtifactItem(defID: "abacus", serial: 9)
        c.addBought(item)
        let bought: ArtifactItem = try XCTUnwrap(c.items.first)
        XCTAssertEqual(bought.origin, .bought)
        XCTAssertTrue(bought.isFirstOwner)
        XCTAssertTrue(bought.isBound)
        XCTAssertFalse(TradeRules.isSellable(bought))
        XCTAssertNil(c.quickSell(bought.id, priceLevel: 1))
        XCTAssertTrue(c.contains(bought.id))
        var book = AuctionBook(me: me)
        do {
            _ = try book.list(bought.id, startPrice: 10, reserve: nil, duration: .oneHour, now: t0, cabinet: &c)
            XCTFail("a store buy must not be listed")
        } catch {
            XCTAssertEqual(error as? AuctionError, .accountBound)
        }
        XCTAssertTrue(book.auctions.isEmpty)
        let back: Cabinet = try JSONDecoder().decode(Cabinet.self, from: JSONEncoder().encode(c))
        XCTAssertFalse(TradeRules.isSellable(back.items[0]), "the lock survives a save")
        let plain = ArtifactItem(defID: "abacus", serial: 10)
        XCTAssertTrue(TradeRules.isSellable(plain))
        XCTAssertFalse(plain.isBound)
    }

    func testEveryStoreShelfCosmeticIsBound() {
        let shelf: [GoldCosmetic] = GoldCosmetics.all.filter { $0.source == .store }
        XCTAssertFalse(shelf.isEmpty)
        for c in shelf {
            XCTAssertTrue(c.item.accountBound, c.id)
            XCTAssertTrue(TradeRules.isAccountBound(c.id), c.id)
            XCTAssertFalse(TradeRules.isSellable(ArtifactItem(defID: c.id, serial: 1)), c.id)
        }
        for c in GoldCosmetics.all where c.source != .store && c.source != .plan { XCTAssertEqual(c.item.accountBound, false, c.id) }
        for c in GoldCosmetics.all where c.source == .plan { XCTAssertTrue(c.item.accountBound, c.id); XCTAssertNil(c.price, c.id) }
    }

    private func ownedPass() -> SeasonPass {
        var p = SeasonPass(today: 100)
        p.owned = ["theme.ocean", "plate.walnut"]
        return p
    }

    func testCosmeticsAreAccountLevelAndSurviveSaveChanges() throws {
        var p = ownedPass()
        p.activate(save: "s1")
        p.equip("theme.ocean")
        XCTAssertEqual(p.equipped["theme"], "theme.ocean")
        p.succeed(save: "s1", with: "s2")
        p.activate(save: "s2")
        XCTAssertEqual(p.equipped["theme"], "theme.ocean", "a new game after bankruptcy keeps the look")
        XCTAssertTrue(p.owned.contains("theme.ocean") && p.owned.contains("plate.walnut"))
        let back: SeasonPass = try JSONDecoder().decode(SeasonPass.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.owned, p.owned)
        XCTAssertEqual(back.currentSave, "s2")

        let old = Data(#"{"firstDay":5,"season":0,"xp":0,"claimed":[],"owned":["theme.ocean"],"equipped":{"theme":"theme.ocean"},"xpDay":5,"xpToday":0,"cashStreak":0}"#.utf8)
        var legacy: SeasonPass = try JSONDecoder().decode(SeasonPass.self, from: old)
        XCTAssertEqual(legacy.currentSave, "current")
        legacy.activate(save: "s9")
        XCTAssertEqual(legacy.equipped["theme"], "theme.ocean", "the first save to open adopts the old look")
        XCTAssertNil(legacy.wornElsewhere("theme.ocean"))
    }

    func testTwoSavesCannotWearTheSameItemAtOnce() {
        var p = ownedPass()
        p.activate(save: "A")
        XCTAssertEqual(p.equip("theme.ocean"), .equipped)
        p.activate(save: "B")
        XCTAssertNil(p.equipped["theme"])
        XCTAssertEqual(p.wornElsewhere("theme.ocean"), "A")
        XCTAssertEqual(p.equip("theme.ocean"), .wornElsewhere(save: "A"), "refused until the player agrees to move it")
        XCTAssertNil(p.equipped["theme"])
        XCTAssertEqual(p.equip("plate.walnut"), .equipped, "another item is free")
        XCTAssertEqual(p.equip("theme.ocean", replacing: true), .equipped)
        XCTAssertEqual(p.equipped["theme"], "theme.ocean")
        XCTAssertNil(p.wornElsewhere("theme.ocean"))
        p.activate(save: "A")
        XCTAssertNil(p.equipped["theme"], "the first save lost it when it was moved")
        XCTAssertEqual(p.wornElsewhere("theme.ocean"), "B")
        p.activate(save: "B")
        XCTAssertEqual(p.equipped["theme"], "theme.ocean")
        XCTAssertEqual(p.equipped["namePlate"], "plate.walnut")
        p.unequip(.theme)
        XCTAssertNil(p.equipped["theme"])
        p.activate(save: "A")
        XCTAssertEqual(p.equip("theme.ocean"), .equipped, "free again once the other save took it off")
    }

    func testAProfileCardIsClaimedByOneSaveToo() {
        var p = SeasonPass(today: 1)
        let item = ArtifactItem(defID: "card.p.slate", serial: 5)
        p.activate(save: "A")
        XCTAssertEqual(p.equipProfileCard(item.id), .equipped)
        p.activate(save: "B")
        XCTAssertEqual(p.equipProfileCard(item.id), .wornElsewhere(save: "A"))
        XCTAssertNil(p.equipped[SeasonPass.profileCardKey])
        XCTAssertEqual(p.equipProfileCard(item.id, replacing: true), .equipped)
        p.activate(save: "A")
        XCTAssertNil(p.equipped[SeasonPass.profileCardKey])
    }

    func testRetiringASaveFreesItsItems() {
        var p = ownedPass()
        p.activate(save: "A")
        p.equip("theme.ocean")
        p.activate(save: "B")
        XCTAssertEqual(p.wornElsewhere("theme.ocean"), "A")
        p.retire(save: "A")
        XCTAssertNil(p.wornElsewhere("theme.ocean"))
        XCTAssertEqual(p.equip("theme.ocean"), .equipped)
    }
}
