import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum SupplyMarketWords {
    static func price(_ tier: Int) -> String { ["Under market price", "Market price", "Above market price"][min(2, max(0, tier))] }
    static func quality(_ tier: Int) -> String { SupplyMarketCatalogue.qualityTiers[min(2, max(0, tier))] + " quality" }
    static func lead(_ days: Int) -> String { days <= 0 ? "Continuous" : days == 1 ? "Next day" : "\(days) days lead" }
    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
    static func place(_ l: SupplyListing) -> String { l.country.isEmpty ? l.city : "\(l.city), \(l.country)" }

    static func tint(_ w: DeliveryWord) -> Color {
        switch w {
        case .reliable: return Theme.gain
        case .mostlyReliable: return Theme.inkSoft
        case .unproven: return Theme.caution
        case .struggling: return Theme.loss
        }
    }
}

struct TrendArrow: View {
    var delta: Double?

    var body: some View {
        if let d = delta, abs(d) >= 0.5 {
            HStack(spacing: Theme.Space.xs) {
                StockArrow(up: d > 0, good: d > 0)
                Text("\(Int(abs(d).rounded())) pts").textStyle(.caption, tint: d > 0 ? Theme.gain : Theme.loss, numeric: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(d > 0 ? "Up \(Int(abs(d).rounded())) points" : "Down \(Int(abs(d).rounded())) points")
        }
    }
}

struct DeliveryRecordView: View {
    var record: DeliveryRecord

    var body: some View {
        let word: DeliveryWord = SupplyRecordRules.word(record)
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Chip(text: word.rawValue, tint: SupplyMarketWords.tint(word))
                Spacer(minLength: 0)
            }
            if word == .unproven {
                Text("Too little history to judge yet.").textStyle(.caption, tint: Theme.inkSoft)
            }
            line("Promised units delivered", record.ordersTotal == 0 ? "No orders yet" : SupplyMarketWords.percent(record.deliveredShare), record.deliveredTrend)
            line("Orders on time", record.ordersTotal == 0 ? "No orders yet" : SupplyMarketWords.percent(record.onTimeShare), record.onTimeTrend)
            line("Complaints", record.complaints == 0 ? "None" : "\(record.complaints)", nil)
            line("Disputes", record.disputes == 0 ? "None" : "\(record.disputes)", nil)
            line("Price changes after signing", record.priceChanges == 0 ? "None" : "\(record.priceChanges)", nil)
            line("Weeks trading", "\(record.weeksTrading)", nil)
        }
    }

    private func line(_ label: String, _ value: String, _ trend: Double?) -> some View {
        HStack(spacing: Theme.Space.s) {
            Text(label).textStyle(.caption, tint: Theme.inkSoft)
            Spacer(minLength: Theme.Space.s)
            TrendArrow(delta: trend)
            Text(value).textStyle(.caption, numeric: true)
        }
    }
}

struct SupplyListingCard: View {
    var listing: SupplyListing
    var known: Bool
    var availability: SupplyAvailability
    var landed: SupplyLanded.Row?
    var currency: Currency?
    var landedPriced = false
    var action: () -> Void

    init(listing: SupplyListing, known: Bool, availability: SupplyAvailability, landed: SupplyLanded.Row? = nil, currency: Currency? = nil, landedPriced: Bool = false,
         action: @escaping () -> Void) {
        self.listing = listing
        self.known = known
        self.availability = availability
        self.landed = landed
        self.currency = currency
        self.landedPriced = landedPriced
        self.action = action
    }

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(listing.ownerName).textStyle(.headline).lineLimit(1)
                    if known { Chip(text: "Known supplier", tint: Theme.gold) }
                    else if listing.isFriend { Chip(text: "Friend", tint: Theme.gold) }
                    Spacer(minLength: Theme.Space.s)
                    Chip(text: listing.word.rawValue, tint: SupplyMarketWords.tint(listing.word))
                }
                Text("\(listing.companyName) · \(listing.tradeName) · \(SupplyMarketWords.place(listing))").textStyle(.caption, tint: Theme.inkSoft).lineLimit(1)
                Text("\(listing.lineName) · \(SupplyMarketWords.price(listing.priceTier)) · \(SupplyMarketWords.quality(listing.qualityTier))")
                    .textStyle(.caption, tint: Theme.inkSoft).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                Text("\(SupplyGuards.effectiveCapacity(listing)) units/week · \(SupplyMarketWords.lead(listing.leadDays)) · minimum \(listing.minOrder)")
                    .textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                if let landed, let currency { LandedCostLines(row: landed, currency: currency, priced: landedPriced) }
                if let limit = SupplyGuards.limitText(listing) { Text(limit).textStyle(.caption, tint: Theme.caution) }
                if let why = availability.message, availability != .available {
                    Text(why).textStyle(.caption, tint: Theme.loss)
                }
            }
            .padding(.vertical, Theme.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

struct SupplySignBlock: View {
    @EnvironmentObject var store: GameStore
    @ObservedObject private var market: SupplyMarketStore = SupplyMarketStore.shared
    var companyID: Int
    var lineID: String
    var lineTitle: String
    var listing: SupplyListing
    var weeklyMarketSpend: Double
    var currency: Currency
    var onSigned: () -> Void
    @State private var units: Double = 0
    @State private var message: String?

    private var room: Int { max(0, SupplyGuards.effectiveCapacity(listing) - listing.committedUnits) }

    var body: some View {
        let today: Int = store.engine.map { SupplyMarketStore.today($0) } ?? 0
        let availability: SupplyAvailability = SupplyGuards.availability(listing, buyerLinkKeys: market.service.buyerLinkKeys, units: max(listing.minOrder, Int(units)), today: today)
        let wanted: Bool = store.engine?.playerSupplyAllowed(companyID: companyID, listing: listing) ?? false
        let landed: SupplyLanded.Row? = store.engine.flatMap { SupplyLandedBasis.rows($0, companyID: companyID, listings: [listing], weekly: weeklyMarketSpend, units: max(1, Int(units))).first }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if !wanted {
                Text("Your business has no use for this from \(listing.ownerName).").popupText(.risk)
            } else if room < listing.minOrder {
                Text("Fully booked this week.").popupText(.risk)
            } else if isBlocked(availability) {
                Text(availability.message ?? "").popupText(.risk)
            } else {
                HStack {
                    Text("Units a week").popupText(.rowLabel)
                    Spacer(minLength: Theme.Space.s)
                    Text("\(Int(units))").popupText(.rowValue)
                    StepperPill(value: $units, range: Double(listing.minOrder)...Double(max(listing.minOrder, room)), step: 5)
                }
                Text("If you do this").popupText(.rowLabel)
                if let landed { LandedCostLines(row: landed, currency: currency, priced: weeklyMarketSpend > 0, popup: true) }
                if weeklyMarketSpend > 0 {
                    let saving: Double = weeklyMarketSpend - weeklyMarketSpend * listing.priceFactor * (landed?.landedFactor ?? 1)
                    HStack(spacing: Theme.Space.s) {
                        Text("Against the market supplier").popupText(.caption)
                        Spacer(minLength: 0)
                        ArrowAmount(gain: saving, amount: abs(saving), format: { (v: Double) -> String in currency.tidyShort(v) + " a week" }, step: .caption)
                    }
                }
                if let message { Text(message).popupText(.risk) }
                PopupOptionButton(title: "Use \(listing.ownerName)", highlighted: true) { sign() }
                Text("If they stop supplying, \(lineTitle.lowercased()) goes back to a market supplier at market price.").popupText(.caption)
            }
        }
        .onAppear { if units < Double(listing.minOrder) { units = Double(min(max(listing.minOrder, 20), max(listing.minOrder, room))) } }
    }

    private func isBlocked(_ a: SupplyAvailability) -> Bool {
        if case .notOffered = a { return true }
        return a == .linkedAccount
    }

    private func sign() {
        let r: SupplySignResult = market.sign(store, companyID: companyID, lineID: lineID, listing: listing, units: Int(units), weeklyMarketSpend: weeklyMarketSpend)
        switch r {
        case .signed:
            Haptics.success()
            store.outcome(chosen: "\(listing.ownerName) for \(lineTitle)", result: "\(listing.ownerName) now supplies \(lineTitle.lowercased()), \(Int(units)) units a week. A market supplier is the backup.")
            onSigned()
        case .refused(let why):
            Haptics.warning()
            message = why
        }
    }
}
