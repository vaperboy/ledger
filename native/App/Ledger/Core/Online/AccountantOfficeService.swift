import Foundation
import GameCore
import Simulation

/// Accountant offices run by other players, as the app sees them. The screens talk only to this protocol; `MockAccountantOfficeService`
/// stands in for the server until one exists. An office is billed through one of the country's engine accountants (`offerID`), so its fee,
/// rating and error rate are the ones the engine books.
struct AccountantOffice: Equatable, Identifiable {
    var id: String
    var officeName: String
    var ownerName: String
    var city: String
    /// The engine accountant the office is billed as.
    var offerID: Int
}

protocol AccountantOfficeService {
    /// The offices on offer next to the country's own accountants; `offers` are the engine accountants an office can be billed as.
    func offices(countryCode: String, offers: [AccountantOffer]) -> [AccountantOffice]
}

/// Local stand-in: a fixed set of made-up player offices, the same on every launch, each tied to one of the given offers.
struct MockAccountantOfficeService: AccountantOfficeService {
    private static let owners: [(owner: String, office: String, city: String)] = [
        ("Ana Holt", "Holt & Co Bookkeeping", "Leeds"),
        ("Ben Marsh", "Marsh Accounts", "Bristol"),
        ("Dara Okafor", "Okafor Tax and Books", "Glasgow"),
        ("Greta Lindqvist", "Lindqvist Ledgers", "Cardiff"),
        ("Hugo Varga", "Varga Accountancy", "Norwich"),
        ("Ines Bright", "Bright Books", "Exeter"),
    ]

    func offices(countryCode: String, offers: [AccountantOffer]) -> [AccountantOffice] {
        guard !offers.isEmpty else { return [] }
        return Self.owners.enumerated().map { (i: Int, o: (owner: String, office: String, city: String)) -> AccountantOffice in
            let pick: Int = Int(HashedRandom.first("acctoffice:\(countryCode):\(i)") * Double(offers.count)) % offers.count
            return AccountantOffice(id: "office\(i)", officeName: o.office, ownerName: o.owner, city: o.city, offerID: offers[pick].id)
        }
    }
}
