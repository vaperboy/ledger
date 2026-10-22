import Foundation
import GameCore
import Countries
import Finance

/// Volume tenders: services, shops and carriers bid for a volume every week for two years (with up to two one-year extensions).
/// Original: the 'vol' entries of `W` and the `start`, `contractsWeek` and 'modProd' steps in features/sales/public_tenders.js.
///
/// A volume tender is an ordinary `ProjectTenders.Tender` (kind "vol", with `u` units a week, `yrs`, `ext`): it is made, bid for and
/// awarded by `ProjectTenders`. What is different is the end: a won tender becomes a contract under `VolumeContracts` (so the units
/// are part of the week's demand, the discount comes off revenue, the buyer pays after a delay, a shop that cannot deliver gets
/// warnings, penalties and in the end loses the contract), and when the term and its extensions run out the work goes out to
/// tender again with the company as the incumbent.
///
/// A higher-quality promise costs about 3 % more to deliver, in proportion to the units it covers (`qualityUplift`, read by
/// `DemandModel.modifier` as part of "cogsup").
///
/// Not ported: farm tenders (the original's own list of ways to sell has no farm, so the contract would add no demand), and the
/// job-kind tenders of factories and furniture makers (the original starts nothing for them).
public enum VolumeTenders {
    /// What each trade can win as a volume contract: title, kind of buyer, whether the work is local. Original: `W` (kind 'vol').
    static let offers: [String: [ProjectTenders.Offer]] = [
        "cleaning": [vol("Cleaning of schools and offices", "muni", true), vol("Cleaning of the hospital wards", "health", true)],
        "webdev": [vol("A booking system for the municipality", "muni", false), vol("Maintenance of a state agency’s website", "state", false)],
        "mktg": [vol("The health trust’s recruitment campaign", "health", false), vol("A national brand’s campaign pitch", "priv", false)],
        "acctfirm": [vol("Accounting for the municipal companies", "muni", true)],
        "law": [vol("Legal framework agreement for the county", "county", false)],
        "staffing": [vol("Temporary nurses for the health trust", "health", false), vol("Temporary staff for the municipality", "muni", true)],
        "physio": [vol("Physiotherapy in nursing homes", "muni", true)],
        "dental": [vol("Dental care for the county’s children", "county", true)],
        "security": [vol("Guarding of the municipal buildings", "muni", true), vol("Security at the state offices", "state", false)],
        "carrental": [vol("Pool cars for the municipality", "muni", true)],
        "restaurant": [vol("Meals for the nursing homes", "muni", true)],
        "cafe": [vol("Canteen for the town hall", "muni", true)],
        "foodtruck": [vol("Lunch for the university campus", "uni", true)],
        "hotel": [vol("Rooms for travelling state staff", "state", true), vol("Conference rooms for the county", "county", true)],
        "bakery": [vol("Bread for schools and nursing homes", "muni", true), vol("A supermarket chain’s own bread", "priv", false)],
        "salmon": [vol("A supermarket chain’s fresh salmon", "priv", false)],
        "taxi": [vol("Patient transport for the health trust", "health", true), vol("School transport", "muni", true)],
        "courier": [vol("Lab samples and internal mail", "health", true)],
        "trucking": [vol("Gravel and road salt transport", "road", false), vol("A manufacturer’s freight", "priv", false)],
        "shipping": [vol("An exporter’s cargo", "priv", false)],
        "airline": [vol("A subsidised regional route", "state", false)],
        "carrepair": [vol("Service of the municipal vehicles", "muni", true)],
        "wh3pl": [vol("Storage and distribution for the health trust", "health", false)],
        "skires": [vol("Ski days for the schools", "muni", true)],
        "indoorski": [vol("Training slots for the ski federation", "state", true)],
    ]

    static func vol(_ title: String, _ buyer: String, _ local: Bool) -> ProjectTenders.Offer {
        ProjectTenders.Offer(title: title, buyer: buyer, local: local, volume: true)
    }

    /// Weeks a public buyer takes to pay (30 days); a private one a little longer.
    static func paymentWeeks(_ t: ProjectTenders.Tender) -> Int { t.isPublicBuyer ? 4 : 6 }

    /// Units a week the company can serve. Original: `capU`.
    static func capacity(_ co: Company, _ bd: Trade) -> Double {
        let cap = co.value("lastW")["cap"].double
        return max(0.5, cap > 0 ? cap : (bd.normalDemand == 0 ? 1 : bd.normalDemand))
    }

    /// Size a freshly made volume tender: a tenth to a third of the company's capacity, two years, two extensions, and the cost of
    /// writing the bid. Original: `make`.
    static func size(_ t: inout ProjectTenders.Tender, _ s: inout GameState, _ co: Company, _ bd: Trade, _ w: World, home: Currency) {
        let tk = Pricing.ticket(co, bd, w)
        let u = max(0.5, jsRound(capacity(co, bd) * (0.1 + s.random.next() * 0.25) * 10) / 10)
        let val = jsRound(u * tk * 52 * 2)
        t.set("u", u); t.set("yrs", 2); t.set("ext", 2); t.set("val", val)
        t.set("cost", home.roundedStep(max(w.currency(co).scaledPrice(4000), val * 0.0015), about: 500))
    }

    /// A manager does not bid for more than the company has room for. Original: `t.u > capU(c) * room`.
    static func noRoom(_ t: ProjectTenders.Tender, _ c: Company) -> Bool {
        guard t.isVolume else { return false }
        let room = 1 - c.value("lastW")["util"].double
        let cap = max(0.5, c.value("lastW")["cap"].double > 0 ? c.value("lastW")["cap"].double : 1)
        return t.unitsPerWeek > cap * room
    }

    static func startText(_ t: ProjectTenders.Tender) -> String {
        "The contract runs \(t.years) years, with up to \(t.extensions) one-year extensions, from next week."
    }

    /// The won tender goes on the company's list of contracts. Original: `start`.
    static func startContract(_ s: inout GameState, _ t: ProjectTenders.Tender, _ co: Company, priceFactor pf: Double, higherQuality: Bool) {
        let terms = VolumeContracts.Terms(name: t.title, customer: t.buyer, units: t.unitsPerWeek, discount: 1 - pf, weeks: 1 + t.years * 52,
                                          paymentWeeks: paymentWeeks(t), reliability: t.isPublicBuyer ? 1 : 0.85, isPublic: t.isPublicBuyer,
                                          tenderID: t.id, extensions: t.extensions, higherQuality: higherQuality)
        guard VolumeContracts.sign(&s, companyID: co.id, terms: terms) != nil else { return }
        s.note("Won \(t.title.lowercased()): \(jsRound(t.unitsPerWeek * 10) / 10) a week for \(t.years) years.", tone: "good", companyID: co.id)
    }

    /// The contract ended without an extension: the work goes out to tender again and the company can bid as the one who does it today.
    /// Original: the end of `contractsWeek`.
    static func newRound(_ s: inout GameState, contract c: JSONValue, companyID: Int, data: GameData) {
        guard let co = s.company(companyID), ProjectTenders.catalog[co.type] != nil, let bd = data.catalog[co.type] else { return }
        let w = World(state: s, data: data)
        let home = w.currency(co)
        var t = ProjectTenders.make(&s, co, data: data, home: home)
        t.set("kind", "vol")
        size(&t, &s, co, bd, w, home: home)
        let u = c["u"].double
        t.set("title", c["n"].string); t.set("buyer", c["who"].string); t.set("bk", c["pub"].bool ? "muni" : "priv"); t.set("inc", companyID)
        t.set("u", u); t.set("val", jsRound(u * Pricing.ticket(co, bd, w) * 52 * 2))
        var st = ProjectTenders.load(s)
        st.list.append(t)
        ProjectTenders.save(&s, st)
        s.addMessage(from: c["who"].string, title: "New round: \(c["n"].string)",
                     body: "The contract ends and the work goes out to tender again. \(co.name) can bid as the company that does it today.", companyID: companyID, tone: "n")
    }

    /// Extra cost of delivering a promise of higher quality: 3 % on the share of the units it covers. Original: 'modProd' 'cogsup'.
    static func qualityUplift(_ co: Company) -> Double {
        let list = co.value("sw33")["ct"].array
        if list.isEmpty { return 1 }
        let u = list.filter { !$0["tnd"].isNull && $0["q"].bool }.reduce(0) { $0 + $1["u"].double }
        let all = max(u, co.value("lastW")["units"].double)
        return u > 0 && all > 0 ? 1 + 0.03 * u / all : 1
    }
}

extension ProjectTenders.Tender {
    public var isVolume: Bool { str("kind") == "vol" }
    /// Units a week the buyer takes (a volume tender).
    public var unitsPerWeek: Double { num("u") }
    public var years: Int { int("yrs") }
    public var extensions: Int { int("ext") }
    /// The company that delivers the work today (a tender for a new round), or 0.
    public var incumbentCompanyID: Int { int("inc") }
}
