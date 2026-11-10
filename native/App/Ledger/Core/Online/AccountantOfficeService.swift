import Foundation
import GameCore
import Simulation

struct AccountantOffice: Equatable, Identifiable {
    var id: String
    var officeName: String
    var ownerName: String
    var city: String
    var offerID: Int
    var rating: Double? = nil
    var ratingCount: Int = 0
    var hireFee: Double = 0
    var currencyCode: String? = nil
}

protocol AccountantOfficeService {
    func offices(countryCode: String, offers: [AccountantOffer]) async -> [AccountantOffice]
    func hire(officeID: String, companyKey: String, currency: String) async throws
}

struct MockAccountantOfficeService: AccountantOfficeService {
    private static let owners: [(owner: String, office: String, city: String)] = [
        ("Ana Holt", "Holt & Co Bookkeeping", "Leeds"),
        ("Ben Marsh", "Marsh Accounts", "Bristol"),
        ("Dara Okafor", "Okafor Tax and Books", "Glasgow"),
        ("Greta Lindqvist", "Lindqvist Ledgers", "Cardiff"),
        ("Hugo Varga", "Varga Accountancy", "Norwich"),
        ("Ines Bright", "Bright Books", "Exeter"),
    ]

    func hire(officeID: String, companyKey: String, currency: String) async throws {}

    func offices(countryCode: String, offers: [AccountantOffer]) async -> [AccountantOffice] {
        guard !offers.isEmpty else { return [] }
        return Self.owners.enumerated().map { (i: Int, o: (owner: String, office: String, city: String)) -> AccountantOffice in
            let pick: Int = Int(HashedRandom.first("acctoffice:\(countryCode):\(i)") * Double(offers.count)) % offers.count
            return AccountantOffice(id: "office\(i)", officeName: o.office, ownerName: o.owner, city: o.city, offerID: offers[pick].id)
        }
    }
}
