import XCTest
import GameCore
@testable import Simulation

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
            XCTAssertLessThan(BoxOdds.expectedGold(kind), Double(kind.price) / 10)
        }
    }

    func testFairnessCheckCatchesAGenerousBox() {
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
            if case .money = out.result.content { XCTFail("a guaranteed prize is an item") }
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
        XCTAssertEqual(StoreAccess.access(adultConfirmed: nil, countryCode: "NO"), .hidden, "no confirmation hides the store")
        XCTAssertEqual(StoreAccess.access(adultConfirmed: false, countryCode: "NO"), .hidden)
        XCTAssertEqual(StoreAccess.access(adultConfirmed: true, countryCode: "NO"), .open(paidBoxes: true))
        XCTAssertTrue(StoreAccess.paidBoxRestrictedCountries.isEmpty, "empty by default")
        XCTAssertEqual(StoreAccess.access(adultConfirmed: true, countryCode: "be", restricted: ["BE", "NL"]), .open(paidBoxes: false))
        XCTAssertEqual(StoreAccess.access(adultConfirmed: true, countryCode: "uk", restricted: ["UK"]), .open(paidBoxes: false))
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

    func testPaidBoxesAlsoHoldCashInTheRareTiers() {
        for kind in BoxKind.allCases where kind.isPaid {
            XCTAssertGreaterThan(BoxOdds.moneyPercent(kind), 0)
            XCTAssertLessThanOrEqual(BoxOdds.moneyPercent(kind), 5)
            var cash = 0
            for n in 0..<20_000 {
                let r = BoxOdds.open(kind, pity: BoxPity(), ownedCosmetics: [], seed: "m\(n)").result
                if case .money(let m) = r.content {
                    cash += 1
                    XCTAssertGreaterThanOrEqual(r.rarity, .rare)
                    XCTAssertLessThanOrEqual(m, BoxOdds.moneyCap)
                }
            }
            XCTAssertGreaterThan(cash, 20, "\(kind) pays cash now and then")
        }
    }

    func testOpeningTenIsRepeatableTracksPityAndNeverRepeatsACosmetic() {
        let a = BoxOdds.openMany(.grand, count: 10, pity: BoxPity(), ownedCosmetics: [], seed: "ten")
        let b = BoxOdds.openMany(.grand, count: 10, pity: BoxPity(), ownedCosmetics: [], seed: "ten")
        XCTAssertEqual(a.results, b.results)
        XCTAssertEqual(a.results.count, 10)
        XCTAssertLessThan(a.pity.sinceRare, BoxPity.threshold)
        XCTAssertTrue(a.results.contains { $0.rarity >= .rare }, "ten paid boxes always hold a rare or better")
        XCTAssertTrue(BoxOdds.openMany(.free, count: 0, pity: BoxPity(), ownedCosmetics: [], seed: "none").results.isEmpty)
        for n in 0..<200 {
            let out = BoxOdds.openMany(.grand, count: 10, pity: BoxPity(), ownedCosmetics: [], seed: "u\(n)")
            let ids: [String] = out.results.compactMap { r in if case .cosmetic(let id) = r.content { return id } else { return nil } }
            XCTAssertEqual(Set(ids).count, ids.count, "a cosmetic won in the batch is not offered again in it")
        }
    }

    func testTheHaulAddsUpWhatTenBoxesHeld() {
        let rs: [BoxResult] = [
            BoxResult(rarity: .common, content: .gold(20, doubled: false), guaranteed: false),
            BoxResult(rarity: .rare, content: .gold(40, doubled: false), guaranteed: false),
            BoxResult(rarity: .rare, content: .money(1_000), guaranteed: false),
            BoxResult(rarity: .epic, content: .money(2_000), guaranteed: false),
            BoxResult(rarity: .common, content: .cosmetic("gold.plate.copper"), guaranteed: false),
            BoxResult(rarity: .common, content: .artifact(ArtifactItem(defID: "abacus", serial: 3)), guaranteed: false)
        ]
        let h = BoxHaul(rs)
        XCTAssertEqual(h.gold, 60)
        XCTAssertEqual(h.money, 3_000)
        XCTAssertEqual(h.cosmetics, ["gold.plate.copper"])
        XCTAssertEqual(h.artifacts.map(\.id), ["abacus#3"])
    }

    func testTheWalletSaysWhenGoldRunsShortAndWhichPackClosesTheGap() throws {
        let w = GoldWallet(balance: 150)
        XCTAssertNil(w.shortfall(for: BoxKind.cabinet.price, purpose: .box), "120 gold is there")
        let short = try XCTUnwrap(w.shortfall(for: 220, purpose: .box))
        XCTAssertEqual(short.available, 150)
        XCTAssertEqual(short.missing, 70)
        XCTAssertTrue(short.text.contains("70 gold short"))
        XCTAssertEqual(short.suggestedPack(firstPurchase: false)?.id, GoldStore.packs[0].id)
        let big = try XCTUnwrap(GoldWallet(balance: 0).shortfall(for: 1_300, purpose: .cosmetic))
        let pack = try XCTUnwrap(big.suggestedPack(firstPurchase: false))
        XCTAssertGreaterThanOrEqual(pack.gold, 1_300)
        XCTAssertNotNil(big.suggestedPack(firstPurchase: true))
        XCTAssertLessThanOrEqual(try XCTUnwrap(big.suggestedPack(firstPurchase: true)).priceCents, pack.priceCents, "the bonus can only make a smaller pack enough")
        XCTAssertNil(GoldWallet(balance: 0).shortfall(for: 1_000_000, purpose: .box)?.suggestedPack(firstPurchase: true), "no pack covers a huge gap")
    }
}
