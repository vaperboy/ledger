import Foundation
import GameCore
import Businesses
import Events

/// The local stand-in for the players' deal server: seeds other players' franchise offers and companies for sale, answers offers on those companies with the
/// seller's rules (`PlayerDeals.reply`), and sends applicants and buyers to the player's own offers as weeks pass. Nothing is saved: the market is drawn
/// again, the same, on each launch, with offers that last a few days to a month from the first day it is looked at.
final class MockPlayerDealsService: PlayerDealsService {
    var onChange: (() -> Void)?
    let buyerLinkKeys: Set<String> = ["me"]

    private var anchor: Int?
    private var franchises: [PlayerDeals.FranchiseListing] = []
    private var companies: [PlayerDeals.CompanyListing] = []
    private var sold: Set<String> = []
    private var ownFranchises: [Int: PlayerDeals.FranchiseListing] = [:]
    private var ownCompanies: [Int: PlayerDeals.CompanyListing] = [:]
    private var processedWeek: Int?

    private func roll(_ key: String) -> Double { HashedRandom.first("dealsmock:" + key) }

    /// A whole number from 0 to `n - 1`, the same for the same key.
    private func pick(_ key: String, _ n: Int) -> Int { min(n - 1, Int(roll(key) * Double(n))) }

    private static let first = ["Ana", "Ben", "Chidi", "Dara", "Elif", "Farid", "Greta", "Hugo", "Ines", "Jonas", "Kira", "Leo", "Mira", "Nils", "Olga", "Pavel"]
    private static let last = ["Holt", "Marsh", "Okafor", "Lindqvist", "Varga", "Bright", "Castell", "Dunmore", "Esposito", "Fairweather", "Gallagher", "Hartmann"]
    private static let brandWords = ["Corner", "Harbour", "Daily", "Northern", "Golden", "Fresh", "Urban", "Local"]
    private static let franchiseTrades = ["cafe", "restaurant", "gym", "grocery", "carclean", "foodtruck", "bakery", "kiosk"]
    private static let saleTrades = ["cafe", "restaurant", "grocery", "gym", "hardware", "bakery", "carclean", "handy", "boutique", "plumber"]
    private static let tradeTitles: [String: String] = ["cafe": "Cafe", "restaurant": "Restaurant", "gym": "Gym", "grocery": "Grocer", "carclean": "Car wash", "foodtruck": "Food truck",
                                                        "bakery": "Bakery", "kiosk": "Kiosk", "hardware": "Hardware store", "handy": "Handyman", "boutique": "Boutique", "plumber": "Plumber"]

    private func person(_ i: Int) -> (name: String, code: String) {
        (Self.first[i % Self.first.count] + " " + Self.last[(i * 5 + 2) % Self.last.count], String(format: "P%05d", 52_100 + i * 41))
    }

    /// Draws the market on first use, with the offers' last days counted from `today`.
    private func seed(_ today: Int) {
        guard anchor == nil else { return }
        anchor = today
        let lengths: [Int] = PlayerDeals.offerDays
        for i in 0..<8 {
            let p = person(i)
            let trade: String = Self.franchiseTrades[i % Self.franchiseTrades.count]
            let name: String = Self.brandWords[(i * 3) % Self.brandWords.count] + " " + (Self.tradeTitles[trade] ?? trade.capitalized)
            let fee: Double = 25_000 + Double(pick("fee\(i)", 8)) * 15_000
            let royalty: Double = 0.04 + Double(pick("roy\(i)", 5)) * 0.01
            let terms: [Int] = [5, 10, 10, 15]
            let strength: Double = 15 + roll("str\(i)") * 55
            let standard: Double = 55 + roll("std\(i)") * 15
            let ends: Int = today + lengths[1 + pick("len\(i)", 4)]
            franchises.append(PlayerDeals.FranchiseListing(
                id: "FM\(i)", ownerID: "owner\(i)", ownerName: p.name, profileCode: p.code, linkKey: "key\(i)", isFriend: i % 5 == 1, brandName: name, tradeID: trade, countryCode: "",
                baseFee: fee, royalty: royalty, marketingFund: 0.02, support: pick("sup\(i)", 3), termYears: terms[pick("term\(i)", 4)], units: 2 + pick("un\(i)", 30),
                strength: strength, standard: standard, expiresDay: ends))
        }
        for i in 0..<7 {
            let p = person(i + 8)
            let trade: String = Self.saleTrades[i % Self.saleTrades.count]
            let revenue: Double = 120_000 + roll("rev\(i)") * 900_000
            let margin: Double = 0.04 + roll("mar\(i)") * 0.18
            let owner: String = Self.last[(i * 7 + 1) % Self.last.count]
            let title: String = Self.tradeTitles[trade] ?? trade.capitalized
            let link: String = i == 5 ? "me" : "key\(i + 8)"
            let size: Double = 1 + Double(pick("sz\(i)", 3))
            let reputation: Double = 35 + roll("rep\(i)") * 55
            let ends: Int = today + lengths[pick("cl\(i)", 5)] + 1
            var l = PlayerDeals.CompanyListing(
                id: "CM\(i)", ownerID: "owner\(i + 8)", ownerName: p.name, profileCode: p.code, linkKey: link, isFriend: i % 4 == 3, companyName: owner + " " + title,
                tradeID: trade, cityID: "", countryCode: "", size: size, yearlyRevenue: revenue.rounded(), yearlyProfit: (revenue * margin).rounded(), staff: 2 + pick("st\(i)", 14),
                reputation: reputation, weeksTrading: 20 + pick("wk\(i)", 200), askPrice: 0, expiresDay: ends)
            let markup: Double = 1.0 + roll("ask\(i)") * 0.35
            l.askPrice = max(1000, (PlayerDeals.value(l) * markup / 1000).rounded() * 1000)
            companies.append(l)
        }
    }

    // MARK: What other players offer

    func franchiseOffers(today: Int) -> [PlayerDeals.FranchiseListing] {
        seed(today)
        return franchises.filter { $0.isOpen(today: today) }
    }

    func companyOffers(today: Int) -> [PlayerDeals.CompanyListing] {
        seed(today)
        return companies.filter { $0.isOpen(today: today) && !sold.contains($0.id) }
    }

    func makeOffer(listingID: String, price: Double, round: Int, today: Int) -> PlayerDeals.Reply {
        guard let l = companies.first(where: { $0.id == listingID }), l.isOpen(today: today), !sold.contains(listingID) else { return .refuse }
        return PlayerDeals.reply(to: price, on: l, round: round)
    }

    func soldToPlayer(listingID: String) {
        sold.insert(listingID)
        onChange?()
    }

    // MARK: What the player offers

    func publish(franchise l: PlayerDeals.FranchiseListing) {
        guard let id = Int(l.id.dropFirst()), ownFranchises[id] != l else { return }
        ownFranchises[id] = l
        onChange?()
    }

    func withdrawFranchise(companyID: Int) {
        if ownFranchises.removeValue(forKey: companyID) != nil { onChange?() }
    }

    func publish(company l: PlayerDeals.CompanyListing) {
        guard let id = Int(l.id.dropFirst()), ownCompanies[id] != l else { return }
        ownCompanies[id] = l
        onChange?()
    }

    func withdrawCompany(companyID: Int) {
        if ownCompanies.removeValue(forKey: companyID) != nil { onChange?() }
    }

    // MARK: Time

    func advance(today: Int) -> [PlayerDealsEvent] {
        seed(today)
        let week: Int = today / 7
        guard let last = processedWeek else { processedWeek = week; return [] }
        guard week > last else { return [] }
        var events: [PlayerDealsEvent] = []
        for w in (last + 1)...min(week, last + 4) {
            for (id, f) in ownFranchises.sorted(by: { $0.key < $1.key }) where f.isOpen(today: w * 7) {
                // The stronger the brand, the likelier a player applies in a week.
                guard roll("app\(id):\(w)") < 0.25 + f.strength / 200 else { continue }
                let p = person(pick("who\(id):\(w)", 1000))
                let capital: Double = (40_000 + roll("cap\(id):\(w)") * 220_000).rounded()
                let skill: Double = 40 + roll("sk\(id):\(w)") * 45
                let a = PlayerDeals.PlayerApplicant(name: p.name, profileCode: p.code, cityID: "", capital: capital, skill: skill,
                                                    experience: pick("ex\(id):\(w)", 8), age: 24 + pick("ag\(id):\(w)", 25))
                events.append(.applicant(companyID: id, a))
            }
            for (id, l) in ownCompanies.sorted(by: { $0.key < $1.key }) where l.isOpen(today: w * 7) {
                guard roll("buy\(id):\(w)") < 0.5 else { continue }
                let p = person(pick("by\(id):\(w)", 1000))
                let share: Double = 0.78 + roll("bp\(id):\(w)") * 0.24
                let price: Double = (l.askPrice * share / 1000).rounded() * 1000
                events.append(.buyerOffer(companyID: id, buyer: CompanySale.PlayerBuyer(name: p.name, profileCode: p.code), price: max(1000, price)))
            }
        }
        processedWeek = week
        return events
    }
}
