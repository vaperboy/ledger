import XCTest
import GameCore
@testable import Simulation

final class PassExclusivityTests: XCTestCase {
    private var seasons: [SeasonDef] { SeasonCatalog.all }

    /// Reward ids that are single cosmetics (not boxes, gold, XP, cards or artifacts).
    private func passCosmetics(_ d: SeasonDef) -> [SeasonReward] {
        d.rewards.filter { ![SeasonReward.Kind.box, .gold, .xp, .profileCard, .companyCard, .artifact].contains($0.kind) }
    }

    private var lastDay: Int { (SeasonCatalog.startDay(of: seasons.count) ?? 0) + 1 }

    func testThereAreThreeSeasonsOfFiftyTiers() {
        XCTAssertGreaterThanOrEqual(seasons.count, 3)
        for d in seasons {
            let free: [Int] = d.rewards.filter { !$0.premium }.map(\.tier)
            let premium: [Int] = d.rewards.filter { $0.premium }.map(\.tier)
            XCTAssertEqual(d.rewards.map(\.tier).max(), 50, "season \(d.number) runs to tier 50")
            XCTAssertTrue(premium.contains(50) && free.contains(50), "season \(d.number) has a final reward on both tracks")
            XCTAssertGreaterThanOrEqual(passCosmetics(d).filter { $0.kind == .outfit }.count, 17, "season \(d.number) holds plenty of outfits")
        }
    }

    func testPassExclusiveItemsNeverReachStoreBoxesCollectionsOrLevels() {
        let day: Int = lastDay
        let pass: Set<String> = Set(seasons.flatMap { passCosmetics($0) }.map(\.id))
        XCTAssertFalse(pass.isEmpty)
        XCTAssertTrue(pass.isDisjoint(with: Set(GoldCosmetics.everything.map(\.id))), "not in the gold catalogue (store, box, level, rank, goal, collection)")
        XCTAssertTrue(pass.isDisjoint(with: Set(GoldCosmetics.retired.map(\.id))))
        XCTAssertTrue(pass.isDisjoint(with: Set(GoldCosmetics.storeItems.map(\.id))), "not sold for gold")
        for rarity in BoxRarity.allCases {
            XCTAssertTrue(pass.isDisjoint(with: Set(GoldCosmetics.boxPool(rarity, owned: [], today: day).map(\.id))), "not in the \(rarity) box pool")
        }
        XCTAssertTrue(pass.isDisjoint(with: Set(ArtifactCatalog.everyCollection.map(\.rewardID))), "not a collection reward")
        for c in GoldCosmetics.everything where c.source == .level { XCTAssertFalse(pass.contains(c.id)) }
        XCTAssertTrue(pass.allSatisfy { GoldPrices.item($0) == nil }, "no gold price")
    }

    func testTheCatalogueSourceLabelsPassItemsAsPassOnly() {
        for d in seasons {
            for r in passCosmetics(d) {
                let entry: CatalogEntry? = CosmeticCatalog.entries(today: lastDay).first { $0.id == r.id }
                XCTAssertNotNil(entry, r.id)
                XCTAssertTrue(entry?.drop.contains("Season \(d.number) pass") == true, "\(r.id): \(entry?.drop ?? "")")
            }
        }
    }

    func testEverySeasonStaysHiddenUntilItsStartDay() {
        for d in seasons where d.number >= 2 {
            guard let start = SeasonCatalog.startDay(of: d.number) else { return XCTFail("start") }
            let before: Int = start - 1
            let ids: Set<String> = Set(d.rewards.map(\.id))
            XCTAssertFalse(SeasonCatalog.isLive(d.number, today: before))
            XCTAssertTrue(SeasonCatalog.isLive(d.number, today: start))
            XCTAssertTrue(SeasonRewards.visible(today: before).allSatisfy { $0.season != d.number })
            XCTAssertNil(SeasonRewards.reward(.free, tier: 1, season: d.number, today: before))
            XCTAssertNotNil(SeasonRewards.reward(.free, tier: 1, season: d.number, today: start))
            XCTAssertTrue(CosmeticCatalog.entries(today: before).allSatisfy { !ids.contains($0.id) }, "season \(d.number) items in the catalogue early")
            XCTAssertFalse(SeasonCatalog.isVisible(theme: d.theme, today: before))
            XCTAssertTrue(GoldCosmetics.visible(today: before).allSatisfy { $0.item.theme != d.theme })
            for rarity in BoxRarity.allCases {
                XCTAssertTrue(GoldCosmetics.boxPool(rarity, owned: [], today: before).allSatisfy { !ids.contains($0.id) && $0.item.theme != d.theme })
            }
        }
    }

    func testSeasonThreeIsRivieraAndStartsHalfAYearAfterSeasonTwo() throws {
        let s3: SeasonDef = try XCTUnwrap(SeasonCatalog.def(3))
        XCTAssertEqual(s3.name, "Riviera Summer")
        XCTAssertEqual(s3.theme, "riviera")
        XCTAssertFalse(s3.founderEdition)
        XCTAssertTrue(ItemThemes.isKnown("riviera"))
        let s2: Int = try XCTUnwrap(SeasonCatalog.startDay(of: 2))
        XCTAssertEqual(SeasonCatalog.startDay(of: 3), s2 + SeasonPass.seasonDays)
        XCTAssertEqual(Set(s3.rewards.filter { $0.premium }.map(\.tier)), Set(1...50), "a premium reward on every tier")
    }

    func testTheNewSeasonOpensByDateAndTheOldPassCloses() throws {
        let start1: Int = try XCTUnwrap(SeasonCatalog.firstSeasonStart)
        let start3: Int = try XCTUnwrap(SeasonCatalog.startDay(of: 3))
        var p = SeasonPass(today: start1)
        p.align(firstDay: start1, today: start1)
        XCTAssertEqual(p.seasonNumber, 1)
        p.xp = 10 * SeasonPass.xpPerTier
        XCTAssertGreaterThan(p.claimableCount(isPlus: false), 0)
        let open: Int = p.unclaimedFree
        XCTAssertGreaterThan(open, 0)
        var q = p
        XCTAssertTrue(q.rollover(today: start3))
        XCTAssertEqual(q.seasonNumber, 3, "the season follows the calendar, with no action from the player")
        XCTAssertEqual(q.seasonDef?.number, 3)
        XCTAssertEqual(q.xp, 0)
        XCTAssertTrue(q.claimed.isEmpty)
        XCTAssertEqual(q.missedFree, open, "the leftover free rewards of the closed pass are counted and told to the player")
        XCTAssertEqual(q.startDay, start3)
        XCTAssertEqual(q.reward(.free, tier: 1, today: start3)?.id, "outfit.s3.deckpolo")
        q.xp = SeasonPass.xpPerTier
        guard case .claimed(let r) = q.claim(.free, tier: 1, isPlus: false, today: start3) else { return XCTFail("tier 1 of season 3 claims") }
        XCTAssertEqual(r.season, 3)
        XCTAssertTrue(p.owned.isDisjoint(with: q.owned))
    }

    func testEveryLegendaryItemAndBoxHasAnAnimationSlot() {
        let legendary: [SeasonReward] = GoldCosmetics.everything.filter { $0.rarity == .legendary }.map(\.item)
            + seasons.flatMap { $0.rewards }.filter { $0.rarity == .legendary && ![SeasonReward.Kind.artifact, .profileCard, .companyCard].contains($0.kind) }
        XCTAssertGreaterThanOrEqual(legendary.count, 25)
        for r in legendary {
            XCTAssertTrue(r.animated, "\(r.id) is legendary and must be animated")
            XCTAssertFalse(r.anim.isEmpty, r.id)
            XCTAssertTrue(["neon", "cool"].contains(r.animStyle), "\(r.id) style \(r.animStyle)")
        }
        XCTAssertTrue(legendary.contains { $0.animStyle == "neon" } && legendary.contains { $0.animStyle == "cool" })
    }

    func testTheStorePoolGrewWithOutfitsBackdropsAndFlairs() {
        let pool: [GoldCosmetic] = GoldCosmetics.everything.filter { $0.source == .store || $0.source == .box }
        for kind in [SeasonReward.Kind.outfit, .backdrop, .richListFlair] {
            for rarity in [BoxRarity.rare, .epic, .legendary] {
                XCTAssertFalse(pool.filter { $0.item.kind == kind && $0.rarity == rarity }.isEmpty, "\(kind) \(rarity)")
            }
        }
        XCTAssertGreaterThanOrEqual(pool.filter { $0.item.kind == .outfit && $0.rarity != .common }.count, 25)
    }
}
