import Foundation
import GameCore
import Countries

// Player companies that supply a line where no real player does. They carry the same facts as a real
// player's company (owner, code, city, logo, size, record) so the game shows them the same way.
public enum SupplyPlayers {
    public struct Supplier: Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var tradeID: String
        public var owner: String
        public var ownerCode: String
        public var city: String
        public var countryCode: String
        public var lineID: String
        public var tier: Int
        public var quality: Double
        public var reliability: Double
        public var capacityFactor: Double
        public var load: Double
        public var staff: Int
        public var weeksTrading: Int
        public var logoID: String
        public var isStandard: Bool { slot == 0 }
        public var slot: Int
    }

    public static let perLine = 4
    // The standard supplier of every line: market price, solid quality, dependable.
    public static let standardReliability = 0.985

    static let words: [String: [String]] = [
        "wholesale": ["Wholesale", "Trading", "Distribution", "Cash & Carry"], "fuelstation": ["Fuel", "Service Station", "Petrol", "Energy Stop"],
        "laundry": ["Laundry", "Linen Service", "Laundry Works", "Wash House"], "security": ["Security", "Guarding", "Protection", "Watch"],
        "handy": ["Property Care", "Handyman Service", "Fix-It", "Home Services"], "electrician": ["Electrical", "Electric", "Power Installations", "Wiring"],
        "plumber": ["Plumbing", "Pipe & Heating", "Plumbers", "Heating"], "factory": ["Industries", "Manufacturing", "Engineering", "Works"],
        "carrepair": ["Auto", "Motors", "Garage", "Car Service"], "carclean": ["Car Care", "Valeting", "Car Wash", "Shine"],
        "trucking": ["Haulage", "Freight", "Transport", "Trucking"], "courier": ["Couriers", "Express", "Delivery", "Parcel"],
        "wh3pl": ["Logistics", "Warehousing", "Fulfilment", "Storage"], "cleaning": ["Cleaning", "Cleaning Services", "Clean Team", "Facility Care"],
        "staffing": ["Staffing", "Recruitment", "Temps", "People"], "mktg": ["Media", "Marketing", "Creative", "Agency"],
        "farm": ["Farm", "Farms", "Growers", "Produce"], "bakery": ["Bakery", "Bakehouse", "Bakers", "Bread Co"],
        "brewery": ["Brewing", "Brewery", "Brew Co", "Ales"], "vineyard": ["Vineyards", "Wine Estate", "Winery", "Cellars"],
        "salmon": ["Seafood", "Salmon", "Aqua", "Fisheries"], "hardware": ["Building Supplies", "Builders Merchant", "Timber & Tools", "Trade Centre"],
        "furniture": ["Furniture", "Interiors", "Woodworks", "Design"], "oilgas": ["Energy", "Petroleum", "Oil", "Fuels"],
        "webdev": ["Digital", "Web", "Tech", "Studio"], "power": ["Power", "Energy", "Renewables", "Electric"],
    ]
    // Where the trade cannot be started, the line is supplied by importers.
    static let importWords: [String: [String]] = [
        "salmon": ["Seafood Import", "Fish Imports", "Seafood Trading", "Sea Imports"], "oilgas": ["Fuel Import", "Energy Imports", "Petroleum Trading", "Fuel Supply"],
        "casino": ["Gaming Supply", "Gaming Imports", "Leisure Trading", "Casino Supply"],
    ]
    static let logos = ["mark", "ring", "square", "triangle", "leaf", "wave", "spark", "anchor", "bridge", "gear", "arrow", "key", "shield", "tower", "compass", "crown", "fox", "owl", "bull", "stag", "falcon"]
    static let codeLetters: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func id(countryCode cc: String, line: String, trade: String, slot n: Int) -> String { "S-\(cc)-\(line)-\(trade)-\(n)" }

    static func parse(_ id: String) -> (cc: String, line: String, trade: String, slot: Int)? {
        let p = id.split(separator: "-").map(String.init)
        guard p.count == 5, p[0] == "S", let n = Int(p[4]), n >= 0 else { return nil }
        return (p[1], p[2], p[3], n)
    }

    public static func isSupplierID(_ id: String) -> Bool { parse(id) != nil }

    public static func make(seed: Int, countryCode cc: String, line: String, trade: String, slot n: Int, countries: CountryBook) -> Supplier {
        let key = id(countryCode: cc, line: line, trade: trade, slot: n)
        var r = HashedRandom("\(seed):sp:\(key)")
        let c = countries.resolve(cc, orHome: cc)
        func pick(_ a: [String], _ fallback: String) -> String { a.isEmpty ? fallback : a[min(a.count - 1, Int(r.next() * Double(a.count)))] }
        let first = pick(c.firstNames, "Alex"), last = pick(c.lastNames, "Berg")
        let cities = c.coreCities.isEmpty ? c.cities : c.coreCities
        let city = cities.isEmpty ? c.name : cities[min(cities.count - 1, Int(r.next() * Double(cities.count)))].name
        let imported: Bool = CompanySetup.banReason(trade, country: c) != nil
        let word = pick(imported ? (importWords[trade] ?? ["Imports", "Import and Trade", "Trading", "Supply"]) : (words[trade] ?? ["Supply"]), "Supply")
        let starts = c.companyNameStarts
        let name: String
        switch Int(r.next() * 3) {
        case 0: name = last + " " + word
        case 1: name = pick(starts, last) + " " + word
        default: name = city + " " + word
        }
        // Slot 0 is the standard supplier; the others spread around it: cheaper and patchier, or dearer and dependable.
        let tiers = [1, 0, 2, 1, 0, 2]
        let tier = tiers[n % tiers.count]
        let noise = r.next()
        let quality: Double = n == 0 ? 0 : jsRound(([-0.22, 0, 0.22][tier] + (noise - 0.5) * 0.12) * 100) / 100
        let reliability: Double = n == 0 ? standardReliability : jsRound(([0.89, 0.95, 0.982][tier] + (r.next() - 0.5) * 0.04) * 100) / 100
        let capacity: Double = n == 0 ? 4 : jsRound((0.9 + 5 * r.next()) * 100) / 100
        let load: Double = n == 0 ? 0.3 : jsRound((0.1 + 0.55 * r.next()) * 100) / 100
        var code = HashedRandom("code:" + key)
        let chars: [Character] = (0..<7).map { _ in codeLetters[min(codeLetters.count - 1, Int(code.next() * Double(codeLetters.count)))] }
        return Supplier(id: key, name: name, tradeID: trade, owner: first + " " + last, ownerCode: String(chars[0..<3]) + "-" + String(chars[3..<7]),
                        city: city, countryCode: cc, lineID: line, tier: tier, quality: quality, reliability: min(0.995, max(0.85, reliability)),
                        capacityFactor: capacity, load: load, staff: max(2, Int((capacity * 4 + r.next() * 12).rounded())),
                        weeksTrading: 20 + Int(r.next() * 400), logoID: logos[min(logos.count - 1, Int(r.next() * Double(logos.count)))], slot: n)
    }

    // The player companies that supply this line to a buyer in this country: slot 0 first.
    public static func list(seed: Int, countryCode cc: String, line: String, trades: [String], count: Int = perLine, countries: CountryBook) -> [Supplier] {
        guard !trades.isEmpty else { return [] }
        return (0..<max(1, count)).map { n in make(seed: seed, countryCode: cc, line: line, trade: trades[n % trades.count], slot: n, countries: countries) }
    }

    public static func supplier(seed: Int, id: String, countries: CountryBook) -> Supplier? {
        guard let p = parse(id) else { return nil }
        return make(seed: seed, countryCode: p.cc, line: p.line, trade: p.trade, slot: p.slot, countries: countries)
    }

    public static func sizeWord(_ s: Supplier) -> String { s.capacityFactor < 2 ? "Small" : s.capacityFactor < 4 ? "Mid-sized" : "Large" }

    // Room left for this buyer, in the buyer's own units of need.
    public static func free(_ s: Supplier, need: Double) -> Double { max(0, need * s.capacityFactor * (1 - s.load)) }

    // Rated the way a real player's record is rated.
    public static func record(_ s: Supplier) -> DeliveryRecord {
        let weeks = s.weeksTrading
        let orders = weeks * 3
        let promised = weeks * 40
        let delivered = Int((Double(promised) * s.reliability).rounded())
        let onTime = Int((Double(orders) * min(1, s.reliability + 0.01)).rounded())
        return DeliveryRecord(weeksTrading: weeks, ordersTotal: orders, ordersOnTime: onTime, unitsPromised: promised, unitsDelivered: delivered,
                              complaints: Int((Double(orders) * (1 - s.reliability) * 0.5).rounded()), cleanWeeks: 12, lifetimeUnits: delivered)
    }
}

// Whether a supplier can meet a buyer's need. Nothing to show when it can, with room to spare.
public enum SupplyFit: String, Equatable, Sendable {
    case fine, mayFallShort, cannot

    public static let spare = 1.2

    public var mark: String? {
        switch self {
        case .fine: return nil
        case .mayFallShort: return "May not supply enough"
        case .cannot: return "Cannot supply"
        }
    }

    public static func of(free: Double, need: Double, open: Bool = true) -> SupplyFit {
        guard open else { return .cannot }
        guard need > 0 else { return free > 0 ? .fine : .cannot }
        if free < need { return .cannot }
        return free < need * spare ? .mayFallShort : .fine
    }
}

// How much a line needs, in units a supplier counts its capacity in.
public enum SupplyNeed {
    // One unit is a reference amount of spend, scaled by the country's cost index.
    public static func unitValue(costIndex: Double) -> Double { 1000 * max(0.2, costIndex) }

    public static func units(weekly: Double, costIndex: Double) -> Int {
        guard weekly.isFinite, weekly > 0 else { return 1 }
        return max(1, Int(saturating: (weekly / unitValue(costIndex: costIndex)).rounded(.up)))
    }
}
