import SwiftUI
import GameCore
import Countries
import Finance
import Businesses
import Simulation

enum SupplyMarketWords {
    static func price(_ tier: Int) -> String { ["Cheaper", "Usual price", "Dearer"][min(2, max(0, tier))] }
    static func quality(_ tier: Int) -> String { SupplyMarketCatalogue.qualityTiers[min(2, max(0, tier))] + " quality" }
    static func lead(_ days: Int) -> String { days <= 0 ? "Continuous" : days == 1 ? "Next day" : "\(days) days lead" }
    static func percent(_ share: Double) -> String { "\(Int(saturating: (share * 100).rounded()))%" }
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
                    if let tag = FriendTies.tag(friend: listing.isFriend) { Chip(text: tag, tint: Theme.gold) }
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
