import XCTest
import GameCore
@testable import Simulation

final class CardCatalogTests: XCTestCase {
    private func game() throws -> GameEngine {
        try GameEngine.newGame(countryCode: "UK", playerName: "T", seed: 7, story: .fresh, tradeID: "cafe", companyName: "Test")
    }

    func testEveryKindAndRarityHasCardsAndOnlyTheRareOnesMove() {
        XCTAssertEqual(Set(CardCatalog.all.map(\.id)).count, CardCatalog.all.count)
        for kind in CardDef.Kind.allCases {
            for rarity in BoxRarity.allCases { XCTAssertFalse(CardCatalog.defs(kind, rarity).isEmpty, "\(kind) \(rarity)") }
        }
        for d in CardCatalog.all {
            XCTAssertGreaterThanOrEqual(d.colors.count, 2)
            if d.isAnimated { XCTAssertGreaterThanOrEqual(d.rarity, .epic, d.id) }
            if d.rarity == .legendary { XCTAssertTrue(d.isAnimated, d.id) }
            if d.kind == .company { XCTAssertFalse(d.logo.isEmpty, d.id) } else { XCTAssertTrue(d.logo.isEmpty, d.id) }
        }
        let animated: Int = CardCatalog.all.filter(\.isAnimated).count
        XCTAssertLessThanOrEqual(Double(animated) / Double(CardCatalog.all.count), 0.5)
        XCTAssertTrue(CardCatalog.defs(.profile, .common).allSatisfy { !$0.isAnimated })
    }

    func testCardPacksCostMoreAndRaiseTheChanceOfRareAndAnimatedCards() {
        let packs: [BoxKind] = [.cardBasic, .cardPremium, .cardElite]
        XCTAssertEqual(BoxKind.cardPacks, packs)
        for kind in packs {
            XCTAssertEqual(BoxOdds.rows(kind).reduce(0) { $0 + $1.weight }, BoxOdds.totalWeight, "\(kind)")
            XCTAssertTrue(BoxOdds.isFair(kind))
            XCTAssertEqual(BoxOdds.expectedGold(kind), 0)
            XCTAssertEqual(BoxOdds.moneyPercent(kind), 0)
            XCTAssertTrue(BoxOdds.disclosure(kind).allSatisfy { $0.title.contains("card") })
        }
        XCTAssertTrue(BoxKind.standard.allSatisfy { !$0.isCardPack })
        func epicUp(_ k: BoxKind) -> Double { BoxOdds.rarityPercent(k).filter { $0.rarity >= .epic }.reduce(0) { $0 + $1.percent } }
        func commons(_ k: BoxKind) -> Double { BoxOdds.rarityPercent(k).first { $0.rarity == .common }?.percent ?? 0 }
        XCTAssertLessThan(packs[0].price, packs[1].price)
        XCTAssertLessThan(packs[1].price, packs[2].price)
        XCTAssertLessThan(epicUp(.cardBasic), epicUp(.cardPremium))
        XCTAssertLessThan(epicUp(.cardPremium), epicUp(.cardElite))
        XCTAssertGreaterThan(commons(.cardBasic), commons(.cardPremium))
        XCTAssertGreaterThan(commons(.cardPremium), commons(.cardElite))
        XCTAssertLessThan(BoxOdds.animatedPercent(.cardBasic), BoxOdds.animatedPercent(.cardPremium))
        XCTAssertLessThan(BoxOdds.animatedPercent(.cardPremium), BoxOdds.animatedPercent(.cardElite))
        XCTAssertLessThan(BoxOdds.animatedPercent(.cardBasic), 10, "animated cards stay very rare in the cheap pack")
        XCTAssertEqual(BoxOdds.animatedPercent(.cabinet), 0)
    }

    func testOpeningACardPackIsRepeatableAndAlwaysGivesANumberedCard() {
        for kind in BoxKind.cardPacks {
            var counts: [BoxRarity: Int] = [:]
            let n = 4_000
            for i in 0..<n {
                let r = BoxOdds.open(kind, pity: BoxPity(), ownedCosmetics: [], seed: "k\(i)").result
                guard case .artifact(let item) = r.content, let d = CardCatalog.def(item.defID) else { return XCTFail("a card pack holds a card") }
                XCTAssertEqual(d.rarity, r.rarity)
                XCTAssertTrue((1...(ArtifactCatalog.def(item.defID)?.edition ?? 0)).contains(item.serial))
                if !r.guaranteed { counts[r.rarity, default: 0] += 1 }
            }
            for (rarity, percent) in BoxOdds.rarityPercent(kind) where percent >= 5 {
                let seen = Double(counts[rarity] ?? 0) / Double(n) * 100
                XCTAssertEqual(seen, percent, accuracy: max(2.0, percent * 0.2), "\(kind) \(rarity)")
            }
            XCTAssertEqual(BoxOdds.open(kind, pity: BoxPity(), ownedCosmetics: [], seed: "same").result, BoxOdds.open(kind, pity: BoxPity(), ownedCosmetics: [], seed: "same").result)
        }
    }

    func testACardIsAnArtifactTheCabinetAndTheAuctionCanHold() throws {
        let item = CardCatalog.item(CardCatalog.def("card.c.skyline")!, roll: 0.5)
        XCTAssertEqual(item.id, "card.c.skyline#\(item.serial)")
        XCTAssertEqual(ArtifactCatalog.def(item.defID)?.rarity, .legendary)
        XCTAssertEqual(ArtifactCatalog.label(item), "\(item.serial) of 100")
        XCTAssertEqual(CardCatalog.def(forItem: item.id)?.id, "card.c.skyline")
        var c = Cabinet()
        c.add(item)
        XCTAssertTrue(ArtifactCatalog.collections.allSatisfy { !$0.members.contains(item.defID) })
        var b = AuctionBook(me: "me")
        let a = try b.list(item.id, startPrice: 500, reserve: nil, duration: .sixHours, now: 1_000, cabinet: &c)
        XCTAssertFalse(c.contains(item.id))
        XCTAssertEqual(a.item, item)
        try b.cancel(a.id, cabinet: &c)
        XCTAssertTrue(c.contains(item.id))
        XCTAssertEqual(c.quickSell(item.id, priceLevel: 1), AuctionRules.quickSalePrice(.legendary, priceLevel: 1))
        XCTAssertFalse(c.contains(item.id))
    }

    func testBotAuctionsOfferCardsToo() {
        let players: [String] = (1...8).map { "p\($0)" }
        var b = AuctionBook(me: "me")
        var c = Cabinet()
        var now: Double = 50_000_000
        AuctionMarket.advance(&b, cash: 0, cabinet: &c, from: now - 1, to: now, players: players)
        for _ in 0..<48 {
            AuctionMarket.advance(&b, cash: 0, cabinet: &c, from: now, to: now + 3_600, players: players)
            now += 3_600
        }
        let cards: Int = b.auctions.filter { CardCatalog.def($0.item.defID) != nil }.count
        XCTAssertGreaterThan(cards, 0)
        XCTAssertLessThan(cards, b.auctions.count)
    }

    func testACompanyCardIsUsedByOneCompanyAtATime() throws {
        var e = try game()
        var s = e.state
        let first: Int = s.companies[0].id
        var other = s.companies[0]
        other.id = first + 1_000
        s.companies.append(other)
        let second: Int = other.id
        var c = Cabinet()
        let a = CardCatalog.item(CardCatalog.def("card.c.navy")!, roll: 0.1)
        let b = CardCatalog.item(CardCatalog.def("card.c.brass")!, roll: 0.2)
        c.add(a); c.add(b)
        XCTAssertNil(CompanyCards.apply(&s, itemID: a.id, companyID: first, cabinet: c))
        XCTAssertEqual(CompanyCards.itemID(for: first, in: s), a.id)
        XCTAssertNil(CompanyCards.apply(&s, itemID: a.id, companyID: second, cabinet: c))
        XCTAssertNil(CompanyCards.itemID(for: first, in: s), "applying it elsewhere moves it")
        XCTAssertEqual(CompanyCards.itemID(for: second, in: s), a.id)
        XCTAssertEqual(CompanyCards.companyUsing(a.id, in: s), second)
        XCTAssertNil(CompanyCards.apply(&s, itemID: b.id, companyID: first, cabinet: c))
        XCTAssertEqual(CompanyCards.assignments(s), [first: b.id, second: a.id])
        XCTAssertNil(CompanyCards.apply(&s, itemID: b.id, companyID: first, cabinet: c), "reapplying to the same company is harmless")
        XCTAssertEqual(CompanyCards.assignments(s).count, 2)
        XCTAssertEqual(CompanyCards.card(for: first, in: s, cabinet: c)?.id, "card.c.brass")
        XCTAssertEqual(CompanyCards.card(for: second, in: s, cabinet: c)?.id, "card.c.navy")
        _ = c.remove(b.id)
        XCTAssertNil(CompanyCards.card(for: first, in: s, cabinet: c), "a card that was sold stops showing")
        CompanyCards.clear(&s, companyID: second)
        XCTAssertNil(CompanyCards.itemID(for: second, in: s))
        let kept: GameState = s
        e.update { st, _, _ in st = kept }
        XCTAssertEqual(e.companyCardAssignments(), [first: b.id])
    }

    func testCompanyCardsRefuseWhatIsNotYoursOrNotACompanyCard() throws {
        var s = try game().state
        let id: Int = s.companies[0].id
        var c = Cabinet()
        let mine = CardCatalog.item(CardCatalog.def("card.c.forest")!, roll: 0.3)
        let profile = CardCatalog.item(CardCatalog.def("card.p.slate")!, roll: 0.3)
        c.add(profile)
        XCTAssertEqual(CompanyCards.apply(&s, itemID: mine.id, companyID: id, cabinet: c), .notOwned)
        c.add(mine)
        XCTAssertEqual(CompanyCards.apply(&s, itemID: profile.id, companyID: id, cabinet: c), .notACompanyCard)
        XCTAssertEqual(CompanyCards.apply(&s, itemID: mine.id, companyID: -5, cabinet: c), .noCompany)
        XCTAssertTrue(CompanyCards.assignments(s).isEmpty)
    }

    func testProfileCardIsWornOnlyWhileItIsOwned() {
        var p = SeasonPass(today: 0)
        var c = Cabinet()
        let item = CardCatalog.item(CardCatalog.def("card.p.aurora")!, roll: 0.9)
        let company = CardCatalog.item(CardCatalog.def("card.c.navy")!, roll: 0.9)
        c.add(item); c.add(company)
        p.equipProfileCard(company.id)
        XCTAssertNil(p.profileCard(cabinet: c), "a company card cannot be a profile card")
        p.equipProfileCard(item.id)
        XCTAssertEqual(p.profileCard(cabinet: c)?.id, "card.p.aurora")
        _ = c.remove(item.id)
        XCTAssertNil(p.profileCard(cabinet: c))
        p.equipProfileCard(nil)
        XCTAssertNil(p.equipped[SeasonPass.profileCardKey])
    }

    func testCardsComeFromThePassAndFromLevelling() {
        let rewards = SeasonRewards.all.filter { $0.kind == .profileCard || $0.kind == .companyCard }
        XCTAssertGreaterThanOrEqual(rewards.count, 6)
        XCTAssertTrue(rewards.contains { $0.premium } && rewards.contains { !$0.premium })
        for r in rewards {
            let d = CardCatalog.def(r.id)
            XCTAssertNotNil(d)
            XCTAssertEqual(r.kind, d?.kind == .company ? .companyCard : .profileCard)
            XCTAssertFalse(r.kind.isEquippable)
            XCTAssertTrue(r.premium || (d?.rarity ?? .legendary) <= .rare, "free cards are cheap ones")
        }
        XCTAssertTrue(CardCatalog.levelRewards.allSatisfy { (CardCatalog.def($0.defID)?.rarity ?? .legendary) <= .rare })
        XCTAssertEqual(CardCatalog.levelRewards.map(\.level), CardCatalog.levelRewards.map(\.level).sorted())
        XCTAssertEqual(CardCatalog.levelRewards(upTo: 4).map(\.defID), ["card.p.slate", "card.c.navy"])
        var p = SeasonPass(today: 0)
        p.xp = SeasonPass.tierCount * SeasonPass.xpPerTier
        let got = p.claimAll(isPlus: true).filter { $0.kind == .profileCard || $0.kind == .companyCard }
        // A pass hands out the cards of its own season; `rewards` above spans every season.
        let seasonCards = (p.seasonDef?.rewards ?? []).filter { $0.kind == .profileCard || $0.kind == .companyCard }
        XCTAssertFalse(seasonCards.isEmpty)
        XCTAssertEqual(got.count, seasonCards.count)
    }
}
