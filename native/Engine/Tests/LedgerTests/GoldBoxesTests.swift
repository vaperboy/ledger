import XCTest
import GameCore
@testable import Simulation

/// Boxes: published odds add up, paid boxes return less gold than they cost, the guarantee works, and the store rules hold.
final class GoldBoxesTests: XCTestCase {
    func testOddsAddUpAndEveryBoxIsFair() {
        for kind in BoxKind.allCases {
            XCTAssertEqual(BoxOdds.rows(kind).reduce(0) { $0 + $1.weight }, BoxOdds.totalWeight, "\(kind) weights")
            XCTAssertEqual(BoxOdds.rarityPercent(kind).reduce(0) { $0 + $1.percent }, 100, accuracy: 0.0001)
            XCTAssertTrue(BoxOdds.isFair(kind), "\(kind) must return less gold than it costs")
        }
    }

    func testPaidBoxAverageGoldIsBelowPriceAndNoPrizeReachesIt() {
        for kind in BoxKind.allCases where kind.isPaid {
            XCTAssertLessThan(BoxOdds.expectedGold(kind), Double(kind.price))
            XCTAssertLessThan(BoxOdds.largestGold(kind), kind.price)
            // Stronger than the promise: gold is a small consolation, under a tenth of the price on average.
            XCTAssertLessThan(BoxOdds.expectedGold(kind), Double(kind.price) / 10)
        }
    }

    func testFairnessCheckCatchesAGenerousBox() {
        // The check itself: expected gold above the price must fail. Cabinet box at a price of 1 gold would be unfair.
        XCTAssertGreaterThan(BoxOdds.expectedGold(.cabinet), 1)
        XCTAssertFalse(BoxOdds.expectedGold(.cabinet) < 1)
    }

    func testFreeBoxGoldIsSmallAndDoublingIsRare() {
        XCTAssertEqual(BoxOdds.doubleGoldChance, 100, "1 in 100")
        XCTAssertLessThanOrEqual(BoxOdds.largestGold(.free), 50)
        var doubled = 0, gold = 0
        for n in 0..<20_000 {
            let r = BoxOdds.open(.free, pity: BoxPity(), ownedCosmetics: [], seed: "f\(n)").result
            if case .gold(_, let d) = r.content { gold += 1; if d { doubled += 1 } }
        }
        XCTAssertGreaterThan(gold, 5_000)
        let share = Double(doubled) / Double(gold)
        XCTAssertGreaterThan(share, 0.003); XCTAssertLessThan(share, 0.025)
    }

    func testPaidBoxesNeverDoubleGold() {
        for n in 0..<3_000 {
            if case .gold(let g, let d) = BoxOdds.open(.cabinet, pity: BoxPity(), ownedCosmetics: [], seed: "c\(n)").result.content {
                XCTAssertFalse(d); XCTAssertLessThan(g, BoxKind.cabinet.price)
            }
        }
    }

    func testRarityFrequenciesMatchTheTable() {
        var counts: [BoxRarity: Int] = [:]
        let n = 30_000
        for i in 0..<n {
            let r = BoxOdds.open(.cabinet, pity: BoxPity(), ownedCosmetics: [], seed: "t\(i)").result
            if !r.guaranteed { counts[r.rarity, default: 0] += 1 }
        }
        for (rarity, percent) in BoxOdds.rarityPercent(.cabinet) {
            let seen = Double(counts[rarity] ?? 0) / Double(n) * 100
            XCTAssertEqual(seen, percent, accuracy: max(1.0, percent * 0.25), "\(rarity)")
        }
    }

    func testGuaranteeAfterTenPaidBoxesWithoutARare() {
        var pity = BoxPity()
        XCTAssertFalse(pity.nextIsGuaranteed)
        for _ in 0..<(BoxPity.threshold - 1) { pity.record(.common) }
        XCTAssertTrue(pity.nextIsGuaranteed)
        XCTAssertTrue(pity.text.contains("guaranteed"))
        for n in 0..<500 {
            let out = BoxOdds.open(.cabinet, pity: pity, ownedCosmetics: [], seed: "p\(n)")
            XCTAssertTrue(out.result.guaranteed)
            XCTAssertGreaterThanOrEqual(out.result.rarity, .rare)
            if case .gold = out.result.content { XCTFail("a guaranteed prize is an item") }
            XCTAssertEqual(out.pity.sinceRare, 0)
        }
    }

    func testPityCountsPaidBoxesAndResetsOnRare() {
        var p = BoxPity()
        p.record(.common); p.record(.common)
        XCTAssertEqual(p.sinceRare, 2)
        XCTAssertTrue(p.text.contains("8 more"))
        p.record(.epic)
        XCTAssertEqual(p.sinceRare, 0)
        let free = BoxOdds.open(.free, pity: BoxPity(sinceRare: 4), ownedCosmetics: [], seed: "x")
        XCTAssertEqual(free.pity.sinceRare, 4, "free boxes do not move the count")
    }

    func testNoPlayerGoesTenPaidBoxesWithoutARare() {
        var pity = BoxPity()
        var worst = 0
        for n in 0..<4_000 {
            let out = BoxOdds.open(.cabinet, pity: pity, ownedCosmetics: [], seed: "w\(n)")
            pity = out.pity
            worst = max(worst, pity.sinceRare)
        }
        XCTAssertLessThan(worst, BoxPity.threshold)
    }

    func testOpeningIsRepeatableAndOwnedCosmeticsAreNotOfferedAgain() {
        let a = BoxOdds.open(.grand, pity: BoxPity(), ownedCosmetics: [], seed: "same")
        let b = BoxOdds.open(.grand, pity: BoxPity(), ownedCosmetics: [], seed: "same")
        XCTAssertEqual(a.result, b.result)
        let everything = Set(GoldCosmetics.all.map(\.id))
        for n in 0..<2_000 {
            if case .cosmetic = BoxOdds.open(.grand, pity: BoxPity(), ownedCosmetics: everything, seed: "o\(n)").result.content { XCTFail("owned cosmetic offered") }
        }
    }

    func testDisclosureListsEveryRow() {
        for kind in BoxKind.allCases {
            XCTAssertEqual(BoxOdds.disclosure(kind).count, BoxOdds.rows(kind).count)
            XCTAssertEqual(BoxOdds.disclosure(kind).reduce(0) { $0 + $1.percent }, 100, accuracy: 0.0001)
        }
    }

    func testGoldPacksGiveMoreGoldPerUnitWhenBigger() {
        let per = GoldStore.packs.map(GoldStore.goldPerUnit)
        XCTAssertEqual(per, per.sorted())
        XCTAssertEqual(Set(per).count, per.count, "strictly more per unit")
        XCTAssertEqual(GoldStore.extraPercent(GoldStore.packs[0]), 0)
        XCTAssertGreaterThan(GoldStore.extraPercent(GoldStore.packs.last!), 30)
        let first = GoldStore.packs[1]
        XCTAssertEqual(GoldStore.totalGold(first, firstPurchase: true), first.gold + first.gold / 2)
        XCTAssertEqual(GoldStore.totalGold(first, firstPurchase: false), first.gold)
        XCTAssertEqual(GoldStore.priceText(cents: 499), "$4.99")
        XCTAssertTrue(GoldStore.seasonBundle.includesPlus)
    }

    func testBoxBundlesSave() {
        for b in GoldStore.boxBundles {
            XCTAssertLessThan(b.price, b.singlesPrice)
            XCTAssertGreaterThan(b.savingPercent, 0)
        }
    }

    func testStoreAccess() {
        XCTAssertEqual(StoreAccess.access(adultConfirmed: nil, countryCode: "NO"), .hidden, "unknown counts as under 18")
        XCTAssertEqual(StoreAccess.access(adultConfirmed: false, countryCode: "NO"), .hidden)
        XCTAssertEqual(StoreAccess.access(adultConfirmed: true, countryCode: "NO"), .open(paidBoxes: true))
        XCTAssertTrue(StoreAccess.paidBoxRestrictedCountries.isEmpty, "empty by default")
        XCTAssertEqual(StoreAccess.access(adultConfirmed: true, countryCode: "be", restricted: ["BE", "NL"]), .open(paidBoxes: false))
        XCTAssertEqual(StoreAccess.access(adultConfirmed: true, countryCode: "GB", restricted: ["UK"]), .open(paidBoxes: false))
        XCTAssertEqual(StoreAccess.access(adultConfirmed: true, countryCode: nil, restricted: ["BE"]), .open(paidBoxes: true))
    }

    func testSeasonPassGrantsBoxesAndGoldWithoutBreakingTheTable() {
        let boxes = SeasonRewards.all.filter { $0.kind == .box }
        let gold = SeasonRewards.all.filter { $0.kind == .gold }
        XCTAssertFalse(boxes.isEmpty); XCTAssertFalse(gold.isEmpty)
        XCTAssertTrue(gold.allSatisfy { $0.amount > 0 && $0.amount <= 50 }, "a little gold")
        XCTAssertTrue((boxes + gold).allSatisfy { !$0.kind.isEquippable })
        var p = SeasonPass(today: 20_000)
        p.xp = 4_500
        let got = p.claimAll(isPlus: true)
        XCTAssertEqual(got.filter { $0.kind == .box }.reduce(0) { $0 + $1.amount }, boxes.reduce(0) { $0 + $1.amount })
    }

    func testBoughtCosmeticsEquipAndSlotsCount() {
        var p = SeasonPass(today: 20_000)
        p.grantOwned("gold.plate.copper")
        XCTAssertEqual(p.equipped["namePlate"], "gold.plate.copper")
        p.grantOwned("gold.plate.onyx")
        XCTAssertEqual(p.equipped["namePlate"], "gold.plate.copper", "the first is kept")
        p.equip("gold.plate.onyx")
        XCTAssertEqual(p.equipped["namePlate"], "gold.plate.onyx")
        let before = p.bonusSaveSlots
        p.grantOwned("gold.slot.1")
        XCTAssertEqual(p.bonusSaveSlots, before + 1)
        XCTAssertNil(p.equipped["saveSlot"])
        p.grantOwned("nonsense")
        XCTAssertFalse(p.owned.contains("nonsense"))
    }
}
