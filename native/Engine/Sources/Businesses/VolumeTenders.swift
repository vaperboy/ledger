import Foundation
import GameCore
import Countries
import Finance

/// Volume tenders: a buyer puts a weekly volume out to tender for two years (plus up to two one-year extensions). The services, shops, farms,
/// carriers and the salmon farm can win them; a won tender becomes a public (or large private) contract under the company's business
/// customers (`VolumeContracts`, marked with the tender's id), which warns, fines, extends or cancels. Bids, scoring and the award are the
/// job tenders' (`ProjectTenders`). Original: the 'vol' entries of `W`, `make`, `start` and the "new round" step of
/// features/sales/public_tenders.js. Not ported: the higher-quality promise's 3% extra cost of goods on the contract's units.
public enum VolumeTenders {
    /// What each trade can win by volume: title, kind of buyer, whether the work is local. Original: `W` (the 'vol' entries).
    public static let catalog: [String: [ProjectTenders.Offer]] = {
        func v(_ t: String, _ b: String, _ local: Bool) -> ProjectTenders.Offer { ProjectTenders.Offer(title: t, buyer: b, local: local, volume: true) }
        return [
            "cleaning": [v("Cleaning of schools and offices", "muni", true), v("Cleaning of the hospital wards", "health", true)],
            "webdev": [v("A booking system for the municipality", "muni", false), v("Maintenance of a state agency’s website", "state", false)],
            "cons": [v("Advisers for a state reorganisation", "state", false)],
            "mktg": [v("The health trust’s recruitment campaign", "health", false), v("A national brand’s campaign pitch", "priv", false)],
            "acctfirm": [v("Accounting for the municipal companies", "muni", true)],
            "law": [v("Legal framework agreement for the county", "county", false)],
            "staffing": [v("Temporary nurses for the health trust", "health", false), v("Temporary staff for the municipality", "muni", true)],
            "physio": [v("Physiotherapy in nursing homes", "muni", true)],
            "dental": [v("Dental care for the county’s children", "county", true)],
            "security": [v("Guarding of the municipal buildings", "muni", true), v("Security at the state offices", "state", false)],
            "carrental": [v("Pool cars for the municipality", "muni", true)],
            "restaurant": [v("Meals for the nursing homes", "muni", true)],
            "cafe": [v("Canteen for the town hall", "muni", true)],
            "foodtruck": [v("Lunch for the university campus", "uni", true)],
            "hotel": [v("Rooms for travelling state staff", "state", true), v("Conference rooms for the county", "county", true)],
            "bakery": [v("Bread for schools and nursing homes", "muni", true), v("A supermarket chain’s own bread", "priv", false)],
            "farm": [v("Produce for the municipal kitchens", "muni", false)],
            "salmon": [v("A supermarket chain’s fresh salmon", "priv", false)],
            "taxi": [v("Patient transport for the health trust", "health", true), v("School transport", "muni", true)],
            "courier": [v("Lab samples and internal mail", "health", true)],
            "trucking": [v("Gravel and road salt transport", "road", false), v("A manufacturer’s freight", "priv", false)],
            "shipping": [v("An exporter’s cargo", "priv", false)],
            "airline": [v("A subsidised regional route", "state", false)],
            "carrepair": [v("Service of the municipal vehicles", "muni", true)],
            "wh3pl": [v("Storage and distribution for the health trust", "health", false)],
            "skires": [v("Ski days for the schools", "muni", true)],
            "indoorski": [v("Training slots for the ski federation", "state", true)],
        ]
    }()

    /// What the company can deliver in a week. Original: `capU`.
    static func capacity(_ co: Company, data: GameData) -> Double {
        let cap = co.value("lastW")["cap"].double
        return max(0.5, cap > 0 ? cap : (data.catalog[co.type]?.normalCapacity ?? 1))
    }

    /// The volume part of a new tender: units a week, years, extensions and what it is worth. Original: `make` (kind 'vol').
    static func fillVolume(_ t: inout ProjectTenders.Tender, _ s: inout GameState, _ co: Company, data: GameData, home: Currency) {
        let w = World(state: s, data: data)
        guard let bd = data.catalog[co.type] else { return }
        let units = max(0.5, jsRound(capacity(co, data: data) * (0.1 + s.random.next() * 0.25) * 10) / 10)
        let val = jsRound(units * Pricing.ticket(co, bd, w) * 52 * 2)
        t.set("kind", "vol"); t.set("u", units); t.set("yrs", 2); t.set("ext", 2); t.set("val", val)
        t.set("cost", home.roundedStep(max(w.currency(co).scaledPrice(4000), val * 0.0015), about: 500))
    }

    /// The won tender becomes a contract on the company's list. Original: `start` (the volume branch).
    static func start(_ s: inout GameState, _ t: ProjectTenders.Tender, _ co: Company, bid: ProjectTenders.Bid?, priceFactor pf: Double) {
        let terms = VolumeContracts.Terms(name: t.title, customer: t.buyer, units: t.units, discount: 1 - pf, weeks: 1 + t.years * 52, paymentWeeks: 0,
                                          reliability: 1, isPublic: t.isPublicBuyer, tenderID: t.id, extensions: t.extensionsAllowed,
                                          higherQuality: bid?.higherQuality ?? false)
        VolumeContracts.sign(&s, companyID: co.id, terms: terms)
    }

    static func awardText(_ t: ProjectTenders.Tender) -> String {
        "The contract runs \(t.years) years, with up to \(t.extensionsAllowed) one-year extensions, from next week."
    }

    /// A tender contract that ends without an extension goes out to tender again, and the company can bid as the one who does it today.
    /// Original: the 'new round' branch of `contractsWeek`.
    static func newRound(_ s: inout GameState, companyID: Int, title: String, buyer: String, units: Double, data: GameData) {
        guard let co = s.company(companyID), let bd = data.catalog[co.type] else { return }
        var st = ProjectTenders.load(s)
        let w = World(state: s, data: data)
        var t = ProjectTenders.make(&s, co, data: data, home: w.currency(co))
        if let o = ProjectTenders.offers(for: co.type).first(where: { $0.title == title }) {
            t.set("bk", o.buyer); t.set("city", o.local ? .string(co.cityID) : .null)
        }
        t.set("title", title); t.set("buyer", buyer); t.set("kind", "vol"); t.set("yrs", 2); t.set("ext", 2)
        t.set("u", units); t.set("inc", companyID)
        t.set("val", jsRound(units * Pricing.ticket(co, bd, w) * 52 * 2))
        st.list.append(t)
        ProjectTenders.save(&s, st)
        s.addMessage(from: buyer, title: "New round: \(title)",
                     body: "The contract ends and the work goes out to tender again. \(co.name) can bid as the company that does it today.", companyID: companyID, tone: "n")
    }
}

extension ProjectTenders.Tender {
    public var isVolume: Bool { str("kind") == "vol" }
    /// Units a week of a volume tender.
    public var units: Double { num("u") }
    public var years: Int { int("yrs") }
    public var extensionsAllowed: Int { int("ext") }
    /// The company that delivers the work today, when the tender is a new round.
    public var incumbentCompanyID: Int? { value("inc").isNull ? nil : int("inc") }
}
