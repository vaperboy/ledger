import Foundation
import GameCore
import Countries
import Finance
import Businesses

public struct BankPaymentDetails: Equatable, Sendable {
    public var holder: String
    public var accountName: String
    public var accountNumber: String
    public var bankName: String

    public init(holder: String, accountName: String, accountNumber: String, bankName: String) {
        self.holder = holder
        self.accountName = accountName
        self.accountNumber = accountNumber
        self.bankName = bankName
    }
}

public struct InsuranceOutcome: Equatable, Sendable {
    public var result: Advisers.Result
    public var number: String
    public var startText: String
    public var yearlyCost: Double
}

public extension GameEngine {

    func placeOffers() -> [PlaceMarket.Offer] { PlaceMarket.offers(state, data: data) }
    func placeCandidates(for offer: PlaceMarket.Offer) -> [PlaceMarket.Candidate] { PlaceMarket.candidates(state, offer: offer, data: data) }
    func rentedPlaces() -> [PlaceMarket.Rented] { PlaceMarket.rented(state, data: data) }

    @discardableResult
    mutating func takePlace(companyID: Int, offer: PlaceMarket.Offer, buy: Bool, receiptCompanyID: Int) -> PlaceMarket.RentOutcome {
        var r = PlaceMarket.RentOutcome(result: .bad, reference: "")
        update { s, d, _ in r = PlaceMarket.take(&s, companyID: companyID, offer: offer, buy: buy, receiptCompanyID: receiptCompanyID, data: d) }
        return r
    }

    @discardableResult
    mutating func reassignPlace(from: Int, to: Int) -> PlaceMarket.MoveResult {
        var r = PlaceMarket.MoveResult.notPossible
        update { s, d, _ in r = PlaceMarket.reassign(&s, from: from, to: to, data: d) }
        return r
    }

    func placeTargets(from companyID: Int) -> [PlaceMarket.Candidate] { PlaceMarket.targets(state, from: companyID, data: data) }

    func storeShipping() -> StoreOrders.ShippingOptions { StoreOrders.shippingOptions(state, data: data) }

    func storeQuote(companyID: Int, lines: [StoreOrders.Line], delivery: StoreOrders.Delivery) -> StoreOrders.Quote? {
        StoreOrders.quote(state, companyID: companyID, lines: lines, delivery: delivery, data: data)
    }

    @discardableResult
    mutating func placeStoreOrder(companyID: Int, lines: [StoreOrders.Line], delivery: StoreOrders.Delivery, receiptCompanyID: Int) -> StoreOrders.PlaceOutcome {
        var r = StoreOrders.PlaceOutcome.notPossible
        update { s, d, _ in r = StoreOrders.place(&s, companyID: companyID, lines: lines, delivery: delivery, receiptCompanyID: receiptCompanyID, data: d) }
        return r
    }

    func storeOrders(companyID: Int) -> [StoreOrders.Record] { state.company(companyID).map { StoreOrders.records($0) } ?? [] }

    func receipts(companyID: Int) -> [Receipts.Row] { state.company(companyID).map { Receipts.rows($0) } ?? [] }

    func bankPaymentDetails(companyID: Int) -> BankPaymentDetails? {
        guard let co = state.company(companyID), co.status.isLive else { return nil }
        var r = HashedRandom("\(state.seed):account:\(co.id)")
        let a: String = (0..<4).map { _ in String(Int(saturating: (r.next() * 10).rounded(.down))) }.joined()
        let b: String = (0..<4).map { _ in String(Int(saturating: (r.next() * 10).rounded(.down))) }.joined()
        let bank = RivalAbsorb.ownBank(state)?.name ?? "Ledger Business Bank"
        return BankPaymentDetails(holder: co.name, accountName: "Company account \u{00B7} " + co.name, accountNumber: a + " " + b, bankName: bank)
    }

    @discardableResult
    mutating func buyInsurance(companyID: Int, product: String, receiptCompanyID: Int) -> InsuranceOutcome {
        var out = InsuranceOutcome(result: .unknown, number: "", startText: "", yearlyCost: 0)
        guard let cover = coverageOverview(companyID: companyID), let row = cover.policies.first(where: { $0.id == product }), !row.isOn else { return out }
        let yearly = row.weeklyPremium * 52
        out.yearlyCost = yearly
        update { s, _, _ in
            out.result = Advisers.togglePolicy(&s, companyID: companyID, product: product)
            guard out.result == .done, let ci = s.companyIndex(companyID) else { return }
            let co = s.companies[ci]
            out.number = Advisers.policyRecord(co, product: product)?.number ?? ""
            out.startText = GameCalendar.dateString(week: s.week, dayOffset: s.day)
            Receipts.add(&s, receiptCompanyID: receiptCompanyID, number: out.number, kind: "policy", title: row.name + " policy",
                         detail: co.name + " \u{00B7} paid weekly from the company account", amount: yearly, payer: co.name)
        }
        return out
    }

    func policyRecord(companyID: Int, product: String) -> (number: String, startText: String)? {
        guard let co = state.company(companyID), let r = Advisers.policyRecord(co, product: product) else { return nil }
        return (r.number, GameCalendar.dateString(week: r.week, dayOffset: r.day))
    }
}
