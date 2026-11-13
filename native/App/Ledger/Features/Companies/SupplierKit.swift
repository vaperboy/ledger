import SwiftUI
import Countries
import Businesses
import Simulation

// Yellow when a supplier may not cover what the company needs, red when it cannot; nothing when it can.
struct FitMark: View {
    var fit: SupplyFit

    var body: some View {
        if let text = fit.mark {
            AcctPill(text: text, tone: fit == .cannot ? .bad : .warn)
                .accessibilityLabel(text)
        }
    }
}

// The facts every supplier company shows, whoever runs it.
struct SupplierCompany: Equatable {
    var name: String
    var trade: String = ""
    var city: String = ""
    var logoID: String = ""
    var owner: String = ""
    var ownerCode: String = ""
    var size: String = ""
    var staff: Int = 0
    var weeksTrading: Int = 0
    var reliability: Double? = nil
    var priceLevel: String = ""
    var isOwn: Bool = false

    var ownerRef: SupplierOwnerRef { SupplierOwnerRef(code: ownerCode, name: owner, company: name, trade: trade, city: city) }

    var tradeLine: String { [trade, city].filter { (s: String) -> Bool in !s.isEmpty }.joined(separator: " \u{00B7} ") }

    static func tradeName(_ e: GameEngine?, _ id: String) -> String { e?.data.catalog[id]?.name ?? "" }

    static func from(_ o: SupplyOfferRow, engine e: GameEngine?) -> SupplierCompany {
        SupplierCompany(name: o.name, trade: tradeName(e, o.tradeID), city: o.city, logoID: o.logoID, owner: o.isOwn ? "" : o.owner, ownerCode: o.ownerCode,
                        size: o.size, staff: o.staff, weeksTrading: o.weeksTrading, reliability: o.trust, priceLevel: o.priceLevel, isOwn: o.isOwn)
    }

    static func from(_ l: SupplyListing, engine e: GameEngine?) -> SupplierCompany {
        let cap: Int = SupplyGuards.effectiveCapacity(l)
        return SupplierCompany(name: l.companyName.isEmpty ? l.ownerName : l.companyName, trade: l.tradeName.isEmpty ? tradeName(e, l.tradeID) : l.tradeName,
                               city: SupplyMarketWords.place(l), logoID: l.logoID, owner: l.ownerName, ownerCode: l.profileCode,
                               size: cap < 80 ? "Small" : cap < 240 ? "Mid-sized" : "Large", weeksTrading: l.record.weeksTrading,
                               reliability: l.record.ordersTotal == 0 ? nil : l.record.deliveredShare, priceLevel: SupplyMarketWords.price(l.priceTier))
    }

    static func from(_ s: ItemModels.SupplyLine, engine e: GameEngine?) -> SupplierCompany {
        SupplierCompany(name: s.vendorName, trade: tradeName(e, s.tradeID), city: s.city, logoID: s.logoID, owner: s.owner, ownerCode: s.ownerCode,
                        reliability: s.reliability, priceLevel: s.discount > 0.0001 ? Currency.percent(s.discount, decimals: 0) + " below list" : "List price")
    }
}

// A quiet mark for the player's own companies.
struct YoursMark: View {
    @Environment(\.outsidePalette) private var P

    var body: some View {
        Text("Yours")
            .textStyle(.caption, tint: P.accent, weight: .medium)
            .padding(.horizontal, Theme.Space.xs).padding(.vertical, 1)
            .overlay(Capsule().stroke(P.accent.opacity(0.35), lineWidth: 1))
            .accessibilityLabel("Your own company")
    }
}

// One supplier section (Stock, Upkeep, Transport, Services): a clear header and the rows under it.
// The company screen and the group screen both use it, so both read the same.
struct SupplySection<Rows: View>: View {
    @Environment(\.outsidePalette) private var P
    var title: String
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).textStyle(.headline, tint: P.ink).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { rows() }
                .padding(.horizontal, Theme.Space.m)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(P.card))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Who owns a supplier company, enough to open their player card.
struct SupplierOwnerRef: Hashable {
    var code: String
    var name: String
    var company: String
    var trade: String
    var city: String
}

// The owner's player card. A known player opens their profile; otherwise the card is built from the supplier company.
struct SupplierOwnerProfile: View {
    var ref: SupplierOwnerRef

    var body: some View {
        if let p = OnlineDirectoryCache.players.first(where: { (q: PlayerProfile) -> Bool in q.code == ref.code }) {
            PlayerProfileView(playerID: p.id)
        } else {
            PlayerProfileView(playerID: "supplier:" + ref.code, preset: Self.profile(ref))
        }
    }

    static func profile(_ r: SupplierOwnerRef) -> PlayerProfile {
        let h: Int = EmblemCatalog.hash("owner" + r.code + r.name)
        let pool: [String] = ["Early player", "Cash positive", "Debt free", "Hired fifty", "Five-star shop", "Season one", "First profit"]
        let badges: [String] = Array(Set([pool[h % pool.count], pool[(h / 7) % pool.count]])).sorted()
        let health: [OnlineCompanyHealth] = [.steady, .growing, .thriving]
        let company = OnlineCompany(id: "supplier:" + r.code, name: r.company, trade: r.trade, city: r.city, countryCode: "", health: health[h % health.count])
        let raw = PlayerProfile(id: "supplier:" + r.code, code: r.code, displayName: r.name, avatarColour: AvatarCatalog.colour(for: r.name), countryCode: "",
                                level: 4 + h % 24, badges: badges, privacy: .everyone, companyCount: 1 + (h / 11) % 4, companies: [company],
                                gameWeek: nil, tradesCompleted: nil, relation: .none, avatarIcon: AvatarCatalog.simulatedIcon(for: r.name))
        return ProfileVisibility.apply(raw, relation: .none)
    }
}

// A supplier's company card: who runs it, how big it is, how reliably it delivers and what it charges.
struct SupplierCompanyCard: View {
    @Environment(\.outsidePalette) private var P
    var company: SupplierCompany
    var onOpenOwner: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center, spacing: Theme.Space.m) {
                SupplierLogo(logoID: company.logoID, name: company.name, size: 48)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(company.name.tidyText).textStyle(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    if !company.tradeLine.isEmpty { Text(company.tradeLine.tidyText).textStyle(.caption, tint: P.inkSoft).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            if company.isOwn {
                YoursMark()
            } else if !company.owner.isEmpty {
                SupplierOwnerLine(name: company.owner, onOpen: company.ownerCode.isEmpty ? nil : onOpenOwner)
            }
            VStack(spacing: Theme.Space.xxs) {
                if !company.size.isEmpty { SupplierFact(label: "Size", value: company.staff > 0 ? "\(company.size), \(company.staff) staff" : company.size) }
                if company.weeksTrading > 0 { SupplierFact(label: "Trading for", value: Self.age(company.weeksTrading)) }
                SupplierFact(label: "Reliability", value: company.reliability.map { (r: Double) -> String in "\(Int(saturating: (r * 100).rounded()))% delivered" } ?? "Not tested yet",
                             tint: (company.reliability ?? 1) < 0.9 ? P.caution : nil)
                if !company.priceLevel.isEmpty { SupplierFact(label: "Price level", value: company.priceLevel) }
            }
        }
        .accessibilityElement(children: .contain)
    }

    static func age(_ weeks: Int) -> String { weeks < 104 ? "\(weeks) weeks" : "\(weeks / 52) years" }
}

struct SupplierLogo: View {
    var logoID: String = ""
    var name: String
    var size: CGFloat = 64

    var body: some View {
        if !logoID.isEmpty && LogoCatalogue.logo(logoID) != nil {
            LogoBadge(logoID: logoID, size: size, glyph: Glyph.suppliers)
        } else {
            ThumbnailView(kind: .logo, key: name, size: size, shape: .square, glyph: Glyph.suppliers, initials: name)
        }
    }
}

struct SupplierOwnerLine: View {
    @Environment(\.outsidePalette) private var P
    var name: String
    var onOpen: (() -> Void)? = nil

    var body: some View {
        if let onOpen {
            Button {
                Haptics.tap()
                onOpen()
            } label: { line(chevron: true) }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Owner " + name + ", open profile")
        } else {
            line(chevron: false)
        }
    }

    private func line(chevron: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            PlayerAvatar(name: name, isYou: false, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text("Owner").textStyle(.caption, tint: P.inkFaint)
                Text(name.tidyText).textStyle(.body, tint: chevron ? P.accent : nil).lineLimit(1)
            }
            if chevron { LedgerGlyph(glyph: Glyph.chevron, size: Theme.Icon.small, tint: P.inkFaint) }
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SupplierFact: View {
    @Environment(\.outsidePalette) private var P
    var label: String
    var value: String
    var tint: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Text(label).textStyle(.caption, tint: P.inkFaint)
            Spacer(minLength: Theme.Space.s)
            Text(value.tidyText).textStyle(.body, tint: tint, numeric: true).multilineTextAlignment(.trailing).lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}
