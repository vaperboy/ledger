import Foundation
import GameCore
import Simulation

/// Accountant offices run by other players, as the app sees them. The screens talk only to this protocol; `MockAccountantOfficeService`
/// stands in when there is no server, `SupabaseAccountantOfficeService` (SupabaseBoards.swift) is the real one. An office is billed through one of the country's engine accountants (`offerID`), so its fee,
/// rating and error rate are the ones the engine books.
struct AccountantOffice: Equatable, Identifiable {
    var id: String
    var officeName: String
    var ownerName: String
    var city: String
    /// The engine accountant the office is billed as.
    var offerID: Int
    /// What the office's clients have really rated it (nil until three have), how many did, and its one-time hiring fee in its own currency.
    var rating: Double? = nil
    var ratingCount: Int = 0
    var hireFee: Double = 0
    var currencyCode: String? = nil
}

protocol AccountantOfficeService {
    /// The offices on offer next to the country's own accountants; `offers` are the engine accountants an office can be billed as.
    func offices(countryCode: String, offers: [AccountantOffer]) async -> [AccountantOffice]
    /// Hires an office for a company; the server books the hiring fee into both ledgers through settlements. The creation flows call this
    /// once they know the new company's key (the picker only chooses the office).
    func hire(officeID: String, companyKey: String, currency: String) async throws
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

    func hire(officeID: String, companyKey: String, currency: String) async throws {}

    func offices(countryCode: String, offers: [AccountantOffer]) async -> [AccountantOffice] {
        guard !offers.isEmpty else { return [] }
        return Self.owners.enumerated().map { (i: Int, o: (owner: String, office: String, city: String)) -> AccountantOffice in
            let pick: Int = Int(HashedRandom.first("acctoffice:\(countryCode):\(i)") * Double(offers.count)) % offers.count
            return AccountantOffice(id: "office\(i)", officeName: o.office, ownerName: o.owner, city: o.city, offerID: offers[pick].id)
        }
    }
}
