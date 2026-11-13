import XCTest
import GameCore
import Businesses
import Countries
@testable import Simulation

final class CosmeticCatalogTests: XCTestCase {
    private static let native: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private var start2: Int { SeasonCatalog.startDay(of: 2) ?? 0 }

    private func count(_ kind: SeasonReward.Kind, today: Int = SeasonCatalog.today()) -> Int {
        CosmeticCatalog.entries(today: today).filter { $0.kind == kind }.count
    }

    // MARK: catalogue size and shape

    func testTheCatalogueIsBigEnough() {
        let today: Int = start2
        XCTAssertGreaterThanOrEqual(count(.outfit, today: today), 40)
        XCTAssertGreaterThanOrEqual(count(.face, today: today), 12)
        XCTAssertGreaterThanOrEqual(count(.hair, today: today), 16)
        XCTAssertTrue((6...8).contains(count(.skin, today: today)), "six to eight skin tones")
        XCTAssertGreaterThanOrEqual(count(.backdrop, today: today), 30)
        XCTAssertEqual(count(.namePlate, today: today), 0, "name plates are no longer given out")
        XCTAssertGreaterThanOrEqual(count(.richListFlair, today: today), 20)
    }

    func testEveryEntryHasANameRarityArtSlotAndDescription() {
        let all: [CatalogEntry] = CosmeticCatalog.entries(today: start2)
        var seen: Set<String> = []
        for e in all {
            XCTAssertTrue(seen.insert(e.id).inserted, "\(e.id) is listed twice")
            XCTAssertFalse(e.title.isEmpty, e.id)
            XCTAssertFalse(e.detail.isEmpty, e.id)
            XCTAssertFalse(e.drop.isEmpty, e.id)
            if e.kind != .saveSlot && e.kind != .advisorLine { XCTAssertFalse(e.art.isEmpty, "\(e.id) needs an art slot id") }
        }
    }

    func testNoNamePlateIsSoldDroppedOrGivenAsAReward() {
        for c in GoldCosmetics.everything { XCTAssertNotEqual(c.item.kind, .namePlate, c.id) }
        for r in SeasonRewards.everything { XCTAssertNotEqual(r.kind, .namePlate, r.id) }
        for rarity in BoxRarity.allCases {
            XCTAssertFalse(GoldCosmetics.boxPool(rarity, owned: []).contains { $0.item.kind == .namePlate })
        }
        XCTAssertFalse(GoldCosmetics.storeItems.contains { $0.item.kind == .namePlate })
        for col in ArtifactCatalog.everyCollection {
            XCTAssertNotEqual(GoldCosmetics.cosmetic(col.rewardID)?.item.kind, .namePlate, "\(col.id) rewards a plate")
        }
        for r in LevelRewards.all { XCTAssertFalse(r.outfit.map { GoldCosmetics.cosmetic($0)?.item.kind == .namePlate } ?? false, "level \(r.level)") }
        for id in SharedGoalRules.rewards { XCTAssertNotEqual(GoldCosmetics.cosmetic(id)?.item.kind, .namePlate, id) }
    }

    func testOwnedPlatesStayKnownSoSavesStillLoad() {
        for id in ["gold.plate.pewter", "gold.plate.onyx", "gold.plate.leaf", "gold.coll.counting", "plate.ledger", "plate.walnut", "plate.marble", "plate.egg", "plate.marble.s2"] {
            XCTAssertEqual(SeasonRewards.item(id)?.kind, .namePlate, id)
            XCTAssertTrue(GoldCosmetics.retired.contains { $0.id == id }, id)
        }
        var p = SeasonPass(today: 20_000)
        p.owned = ["plate.marble", "gold.plate.copper"]
        XCTAssertEqual(p.equip("plate.marble"), .equipped, "an owned plate can still be worn")
    }

    func testNoBadgeIconOrFrameIsGivenOutAnyMore() {
        for c in GoldCosmetics.everything { XCTAssertTrue(c.item.kind != .badge && c.item.kind != .theme, "\(c.id) is a \(c.item.kind)") }
        for r in SeasonRewards.everything { XCTAssertTrue(r.kind != .badge && r.kind != .theme, "\(r.id) is a \(r.kind)") }
        for e in CosmeticCatalog.entries(today: start2) { XCTAssertTrue(e.kind != .badge && e.kind != .theme, e.id) }
        for r in Career.defs where !r.cosmetic.isEmpty { XCTAssertTrue(r.cosmetic.hasPrefix("outfit."), "\(r.id) hands out \(r.cosmetic)") }
        for rarity in BoxRarity.allCases {
            XCTAssertTrue(GoldCosmetics.boxPool(rarity, owned: [], today: start2).allSatisfy { $0.item.kind != .badge && $0.item.kind != .theme })
        }
    }

    func testEveryRewardOutfitResolvesAndWearsAnArtSlot() {
        for id in LevelRewards.outfitIDs { XCTAssertEqual(GoldCosmetics.cosmetic(id)?.item.kind, .outfit, id) }
        for r in Career.defs where r.cosmetic.hasPrefix("outfit.") {
            let c: GoldCosmetic? = GoldCosmetics.cosmetic(r.cosmetic)
            XCTAssertEqual(c?.source, .goal, r.id)
            XCTAssertEqual(c?.value, r.id, r.id)
        }
        for c in GoldCosmetics.everything where c.item.kind == .outfit { XCTAssertTrue(c.art.hasPrefix("avatar.body."), c.id) }
    }

    func testEarnedOutfitsFollowLevelRankAndGoals() {
        XCTAssertTrue(CosmeticCatalog.earned(level: 1, bestRank: 0, goalRewards: []).allSatisfy { GoldCosmetics.cosmetic($0)?.source == .free })
        let l5: Set<String> = CosmeticCatalog.earned(level: 5, bestRank: 0, goalRewards: [])
        XCTAssertTrue(l5.contains("outfit.intern") && l5.contains("outfit.suit") && !l5.contains("outfit.courier"))
        XCTAssertTrue(CosmeticCatalog.earned(level: 1, bestRank: 0, goalRewards: ["outfit.goal.regulars"]).contains("outfit.goal.regulars"))
    }

    // MARK: boxes

    func testBoxOddsStayValidAndEveryRarityHasCosmeticsToDrop() {
        for kind in BoxKind.allCases {
            XCTAssertEqual(BoxOdds.rows(kind).reduce(0) { $0 + $1.weight }, BoxOdds.totalWeight, "\(kind)")
            XCTAssertEqual(BoxOdds.disclosure(kind).reduce(0) { $0 + $1.percent }, 100, accuracy: 0.0001)
            XCTAssertTrue(BoxOdds.isFair(kind), "\(kind)")
        }
        for rarity in BoxRarity.allCases {
            let pool: [GoldCosmetic] = GoldCosmetics.boxPool(rarity, owned: [])
            XCTAssertGreaterThanOrEqual(pool.count, 8, "\(rarity) needs a real pool")
            XCTAssertTrue(pool.allSatisfy { $0.rarity == rarity && ($0.source == .box || $0.source == .store) && $0.item.kind != .saveSlot })
        }
    }

    func testOutfitsFacesAndHairDropFromBoxes() {
        let kinds: Set<SeasonReward.Kind> = Set(BoxRarity.allCases.flatMap { GoldCosmetics.boxPool($0, owned: []).map(\.item.kind) })
        for k in [SeasonReward.Kind.outfit, .face, .hair] { XCTAssertTrue(kinds.contains(k), "boxes drop \(k.label)") }
        XCTAssertTrue(kinds.contains(.backdrop) && kinds.contains(.richListFlair))
        XCTAssertFalse(kinds.contains(.namePlate))
    }

    func testLegendariesAndEarnedItemsAreNeverSoldForGold() {
        for c in GoldCosmetics.everything {
            if c.rarity == .legendary { XCTAssertNotEqual(c.source, .store, "\(c.id) is box-only") }
            if [.level, .rank, .goal, .plan, .free].contains(c.source) {
                XCTAssertNil(c.price, c.id)
                XCTAssertFalse(GoldCosmetics.boxPool(c.rarity, owned: []).contains { $0.id == c.id }, "\(c.id) is earned, not dropped")
            }
        }
    }

    func testOpeningBoxesOnlyHandsOutRealVisibleCosmeticsOfTheRolledRarity() {
        let visible: Set<String> = Set(GoldCosmetics.visible().map(\.id))
        var pity = BoxPity()
        var owned: Set<String> = []
        var cosmetics = 0
        for n in 0..<400 {
            let out = BoxOdds.open(.grand, pity: pity, ownedCosmetics: owned, seed: "cat\(n)")
            pity = out.pity
            guard case .cosmetic(let id) = out.result.content else { continue }
            cosmetics += 1
            XCTAssertTrue(visible.contains(id), "\(id) is not visible today")
            XCTAssertEqual(GoldCosmetics.cosmetic(id)?.rarity, out.result.rarity, id)
            owned.insert(id)
        }
        XCTAssertGreaterThan(cosmetics, 20)
    }

    func testTheTenBoxGuaranteeStillGivesARareOrBetterItem() {
        var pity = BoxPity()
        for _ in 0..<(BoxPity.threshold - 1) { pity.record(.common) }
        for n in 0..<300 {
            let out = BoxOdds.open(.cabinet, pity: pity, ownedCosmetics: [], seed: "g\(n)")
            XCTAssertTrue(out.result.guaranteed)
            XCTAssertGreaterThanOrEqual(out.result.rarity, .rare)
            if case .cosmetic(let id) = out.result.content { XCTAssertNotNil(GoldCosmetics.cosmetic(id)) }
        }
    }

    // MARK: pass tiers

    func testSeasonOnePassTiersHoldOutfitsNotBadgesOrThemes() throws {
        let s1: SeasonDef = try XCTUnwrap(SeasonCatalog.def(1))
        let outfits: [String: (Int, Bool)] = Dictionary(uniqueKeysWithValues: s1.rewards.filter { $0.kind == .outfit }.map { ($0.id, ($0.tier, $0.premium)) })
        XCTAssertEqual(outfits.count, 11)
        XCTAssertEqual(outfits["outfit.s1.pennant"]?.0, 1)
        XCTAssertEqual(outfits["outfit.s1.pennant"]?.1, false)
        XCTAssertEqual(outfits["outfit.s1.finisher"]?.0, 30)
        XCTAssertEqual(outfits["outfit.s1.finisher"]?.1, false)
        XCTAssertEqual(outfits["outfit.s1.crown"]?.0, 30)
        XCTAssertEqual(outfits["outfit.s1.crown"]?.1, true)
        XCTAssertEqual(s1.rewards.first { $0.id == "outfit.s1.crown" }?.rarity, .legendary)
        for id in ["outfit.s1.moss", "outfit.s1.plus", "outfit.s1.cash", "outfit.s1.rose", "outfit.s1.dusk", "outfit.s1.ocean"] {
            XCTAssertEqual(outfits[id]?.1, true, "\(id) is a premium reward")
        }
        XCTAssertEqual(outfits["outfit.s1.walnut"]?.0, 2)
        XCTAssertEqual(outfits["outfit.s1.walnut"]?.1, true)
        XCTAssertEqual(outfits["outfit.s1.brass"]?.0, 13)
        XCTAssertEqual(outfits["outfit.s1.brass"]?.1, false)
        XCTAssertFalse(s1.rewards.contains { $0.kind == .badge || $0.kind == .theme })
        for r in s1.rewards where r.kind == .outfit { XCTAssertTrue(r.art.hasPrefix("avatar.body."), r.id) }
    }

    func testSeasonTwoPassTiersHoldOutfitsToo() throws {
        let s2: SeasonDef = try XCTUnwrap(SeasonCatalog.def(2))
        XCTAssertEqual(s2.rewards.filter { $0.kind == .outfit }.map(\.id).sorted(),
                       ["outfit.s2.crown", "outfit.s2.egg", "outfit.s2.fairday", "outfit.s2.lilac", "outfit.s2.mint", "outfit.s2.plus", "outfit.s2.sprout"])
        XCTAssertFalse(s2.rewards.contains { $0.kind == .badge || $0.kind == .theme })
    }

    func testClaimingAnOutfitOwnsIt() {
        var p = SeasonPass(today: 20_000)
        p.xp = SeasonPass.xpPerTier
        guard case .claimed(let r) = p.claim(.free, tier: 1, isPlus: false) else { return XCTFail("tier 1 should claim") }
        XCTAssertEqual(r.kind, .outfit)
        XCTAssertTrue(p.owned.contains("outfit.s1.pennant"))
    }

    // MARK: hidden future seasons

    func testASeasonThatHasNotStartedShowsNowhere() {
        let before: Int = start2 - 1
        XCTAssertFalse(SeasonCatalog.isLive(2, today: before))
        XCTAssertTrue(SeasonCatalog.isLive(1, today: before))
        XCTAssertTrue(SeasonCatalog.hiddenThemes(today: before).contains("spring"))
        XCTAssertFalse(SeasonCatalog.isVisible(theme: "spring", today: before))
        XCTAssertTrue(SeasonCatalog.isVisible(theme: ItemThemes.founderID, today: before))

        XCTAssertTrue(SeasonRewards.visible(today: before).allSatisfy { $0.season != 2 })
        XCTAssertNil(SeasonRewards.reward(.free, tier: 1, season: 2, today: before))
        XCTAssertNotNil(SeasonRewards.reward(.free, tier: 1, season: 1, today: before))
        XCTAssertFalse(GoldCosmetics.visible(today: before).contains { $0.id == "gold.coll.spring" })
        XCTAssertTrue(CardCatalog.visible(today: before).allSatisfy { $0.theme != "spring" })
        for kind in [CardDef.Kind.profile, .company] {
            for rarity in BoxRarity.allCases { XCTAssertFalse(CardCatalog.defs(kind, rarity, today: before).isEmpty, "\(kind) \(rarity)") }
        }
        XCTAssertTrue(ArtifactCatalog.visibleCollections(today: before).allSatisfy { $0.id != "spring" })
        for rarity in BoxRarity.allCases {
            XCTAssertFalse(ArtifactCatalog.defs(of: rarity, today: before).isEmpty, "\(rarity)")
            XCTAssertTrue(ArtifactCatalog.defs(of: rarity, today: before).allSatisfy { $0.theme != "spring" })
        }
        let hiddenIDs: Set<String> = Set(SeasonCatalog.def(2)?.rewards.map(\.id) ?? [])
        XCTAssertFalse(hiddenIDs.isEmpty)
        XCTAssertTrue(CosmeticCatalog.entries(today: before).allSatisfy { !hiddenIDs.contains($0.id) })
        for rarity in BoxRarity.allCases { XCTAssertTrue(GoldCosmetics.boxPool(rarity, owned: [], today: before).allSatisfy { !hiddenIDs.contains($0.id) && $0.item.theme != "spring" }) }
    }

    func testTheSeasonAppearsEverywhereOnItsStartDay() {
        let live: Int = start2
        XCTAssertTrue(SeasonCatalog.isLive(2, today: live))
        XCTAssertFalse(SeasonCatalog.hiddenThemes(today: live).contains("spring"))
        XCTAssertTrue(SeasonRewards.visible(today: live).contains { $0.season == 2 })
        XCTAssertEqual(SeasonRewards.reward(.free, tier: 1, season: 2, today: live)?.id, "outfit.s2.sprout")
        XCTAssertTrue(GoldCosmetics.visible(today: live).contains { $0.id == "gold.coll.spring" })
        XCTAssertTrue(CardCatalog.visible(today: live).contains { $0.theme == "spring" })
        XCTAssertTrue(ArtifactCatalog.visibleCollections(today: live).contains { $0.id == "spring" })
        XCTAssertTrue(CosmeticCatalog.entries(today: live).contains { $0.id == "outfit.s2.sprout" })
    }

    func testRawListsKeepEverySeasonSoOwnedIdsAlwaysResolve() {
        XCTAssertNotNil(SeasonRewards.item("outfit.s2.sprout"))
        XCTAssertNotNil(GoldCosmetics.cosmetic("gold.coll.spring"))
        XCTAssertNotNil(ArtifactCatalog.collection("spring"))
        XCTAssertNotNil(CardCatalog.def("card.p.blossom"))
    }

    // MARK: retired frames and the gold refund

    func testRetiredItemsStillDecodeAndResolve() throws {
        XCTAssertFalse(RetiredCosmetics.refunds.isEmpty)
        XCTAssertNotNil(GoldCosmetics.cosmetic("badge.s1.first"))
        for r in RetiredCosmetics.refunds where r.id.hasPrefix("gold.") { XCTAssertNotNil(GoldCosmetics.cosmetic(r.id), r.id) }
        XCTAssertTrue(GoldCosmetics.retired.allSatisfy { c in !GoldCosmetics.everything.contains { $0.id == c.id } }, "a retired item is not also current")
        for c in GoldCosmetics.retired { XCTAssertFalse(GoldCosmetics.boxPool(c.rarity, owned: []).contains { $0.id == c.id }, c.id) }
        let old = Data(#"{"firstDay":5,"season":0,"xp":0,"claimed":[],"owned":["badge.s1.first","gold.theme.sage","theme.moss"],"equipped":{"theme":"theme.moss"},"xpDay":5,"xpToday":0,"cashStreak":0}"#.utf8)
        let p: SeasonPass = try JSONDecoder().decode(SeasonPass.self, from: old)
        XCTAssertTrue(p.owned.contains("gold.theme.sage"))
        XCTAssertNil(p.refunded, "a save from before the refund has paid nothing")
    }

    func testRetiredFramesRefundTheirGoldOnceAndOnlyOnce() throws {
        let sage: Int = try XCTUnwrap(RetiredCosmetics.refunds.first { $0.id == "gold.theme.sage" }?.gold)
        let indigo: Int = try XCTUnwrap(RetiredCosmetics.refunds.first { $0.id == "gold.theme.indigo" }?.gold)
        var p = SeasonPass(today: 20_000)
        XCTAssertEqual(p.refundRetired(), 0, "nothing owned, nothing owed")
        p.owned = ["gold.theme.sage", "gold.theme.indigo", "plate.walnut"]
        XCTAssertEqual(p.refundRetired(), sage + indigo)
        XCTAssertEqual(p.refundRetired(), 0, "paid once")
        XCTAssertEqual(p.refunded, ["gold.theme.sage", "gold.theme.indigo"])
        p.owned.insert("gold.theme.amber")
        XCTAssertEqual(p.refundRetired(), RetiredCosmetics.refunds.first { $0.id == "gold.theme.amber" }?.gold, "a newly found frame pays once too")
        XCTAssertEqual(p.refundRetired(), 0)
    }

    func testRetiredPlatesBoughtWithGoldRefundOnceAndPrizesDoNot() throws {
        let price: [BoxRarity: Int] = [.common: 15, .rare: 35, .epic: 80]
        var owed = 0
        var p = SeasonPass(today: 20_000)
        for c in GoldCosmetics.retired where c.item.kind == .namePlate && c.id.hasPrefix("gold.plate.") && c.rarity != .legendary {
            let refund: Int = try XCTUnwrap(RetiredCosmetics.refunds.first { $0.id == c.id }?.gold, c.id)
            XCTAssertEqual(refund, price[c.rarity], c.id)
            p.owned.insert(c.id)
            owed += refund
        }
        XCTAssertEqual(owed, 5 * 15 + 4 * 35 + 4 * 80)
        p.owned.formUnion(["gold.plate.leaf", "gold.coll.counting", "plate.marble"])
        XCTAssertEqual(p.refundRetired(), owed, "box prizes, collection and pass plates are not refunded")
        XCTAssertEqual(p.refundRetired(), 0, "paid once")
    }

    func testTheRefundSurvivesASaveAndCountsProfileIcons() throws {
        let diamond: Int = try XCTUnwrap(RetiredCosmetics.refunds.first { $0.id == "av.diamond" }?.gold)
        var p = SeasonPass(today: 20_000)
        XCTAssertEqual(p.refundRetired(alsoOwned: ["av.diamond", "av.briefcase"]), diamond, "kept icons are not refunded")
        var back: SeasonPass = try JSONDecoder().decode(SeasonPass.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.refundRetired(alsoOwned: ["av.diamond"]), 0, "a reloaded save does not pay again")
    }

    func testRefundsArePositiveAndNeverCoverCurrentItems() {
        for r in RetiredCosmetics.refunds { XCTAssertGreaterThan(r.gold, 0, r.id) }
        XCTAssertFalse(RetiredCosmetics.refunds.contains { $0.id.hasPrefix("outfit.") }, "current items are never refunded")
    }

    // MARK: vehicles

    func testEveryVehicleModelNameBelongsToExactlyOnePicture() {
        let keys: [String] = VehicleCatalog.allArtKeys
        XCTAssertFalse(keys.isEmpty)
        let names: [String] = keys.compactMap { VehicleCatalog.modelName(artKey: $0) }
        XCTAssertEqual(names.count, keys.count)
        XCTAssertEqual(Set(names).count, names.count, "no two pictures share a model name")
        for id in VehicleCatalog.allModelIDs {
            let used: [String] = VehicleCatalog.artKeys(id)
            XCTAssertFalse(used.isEmpty, id)
            XCTAssertTrue(used.allSatisfy { VehicleCatalog.modelName(artKey: $0) != nil }, id)
        }
    }

    func testEveryFleetVehicleModelHasPictures() throws {
        let url: URL = Self.native.appendingPathComponent("Engine/Sources/Businesses/Resources/tables.json")
        let tables: JSONValue = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        for id in tables["VEH"].object.keys { XCTAssertFalse(VehicleCatalog.artKeys(id).isEmpty, "\(id) has no picture") }
    }

    func testFleetOffersCarryTheirPictureAndItsName() throws {
        let countries: CountryBook = try CountryBook.bundled()
        for id in VehicleCatalog.allModelIDs {
            let offers: [EquipmentMarket.VehicleOffer] = EquipmentMarket.vehicleOffers(model: id, modelName: id, countryCode: "UK", seed: 3, countries: countries)
            XCTAssertEqual(offers.count, 2, id)
            for o in offers {
                let want = VehicleCatalog.variant(modelID: id, index: o.index)
                XCTAssertEqual(o.art, want?.art, id)
                XCTAssertEqual(o.model, want?.model, id)
                XCTAssertEqual(VehicleCatalog.modelName(artKey: o.art), o.model, "\(o.art) always shows \(o.model)")
            }
        }
    }

    func testTheSameModelNeverChangesItsPictureBetweenSeedsOrCountries() throws {
        let countries: CountryBook = try CountryBook.bundled()
        let a = EquipmentMarket.vehicleOffers(model: "bus", modelName: "Bus", countryCode: "UK", seed: 1, countries: countries)
        let b = EquipmentMarket.vehicleOffers(model: "bus", modelName: "Bus", countryCode: "NO", seed: 99, countries: countries)
        XCTAssertEqual(a.map(\.art), b.map(\.art))
        XCTAssertEqual(a.map(\.model), b.map(\.model))
    }

    func testPlaceholderSlotsAreOnlyForModelsWithoutAPicture() {
        let placeholders: [String] = VehicleCatalog.allArtKeys.filter { VehicleCatalog.isPlaceholder($0) }
        XCTAssertEqual(Set(placeholders), ["vehicle.ship_s", "vehicle.ship_l", "vehicle.ferry", "vehicle.plane_s"])
    }

    func testEveryLuxuryCarYachtAndJetHasItsOwnPicture() throws {
        var used: [String: String] = [:]
        for cat in Luxury.categories where Luxury.pictureCategories.contains(cat.id) {
            for it in cat.items where !it.art.isEmpty {
                XCTAssertNil(used[it.art], "\(it.id) and \(used[it.art] ?? "") share \(it.art)")
                used[it.art] = it.id
            }
        }
        let empty: [String] = Luxury.categories.filter { Luxury.pictureCategories.contains($0.id) }.flatMap { $0.items }.filter { $0.art.isEmpty }.map(\.id)
        XCTAssertEqual(empty, ["j5"], "only the jet with no picture yet is empty")
        for (art, id) in used {
            let parts: [String] = art.split(separator: "/").map { String($0) }
            XCTAssertEqual(parts.count, 2, id)
            let url: URL = Self.native.appendingPathComponent("App/Ledger/Resources/art/cells/\(parts[0])/manifest.json")
            let manifest: JSONValue = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
            XCTAssertFalse(manifest["cells"][parts[1]].isNull, "\(id) points at \(art), which is not in the sheet")
        }
    }

    func testVehicleArtKeysAreCellsOfTheItemsSheet() throws {
        let url: URL = Self.native.appendingPathComponent("App/Ledger/Resources/art/cells/items/manifest.json")
        let manifest: JSONValue = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        for k in VehicleCatalog.allArtKeys where !VehicleCatalog.isPlaceholder(k) { XCTAssertFalse(manifest["cells"][k].isNull, "\(k) is not a cell of the items sheet") }
    }
}
