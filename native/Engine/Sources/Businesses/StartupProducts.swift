import Foundation
import GameCore

/// The nine sectors a startup of yours can build in, and what a finished product does for your own companies when they use it.
/// Original: features/player/startup_sectors.js (`CAT`, `fxFor`, `fxNow` and the 'demand', 'capacity' steps).
/// Startups live in `state.rest["founded"]`; the product is `sw16` = { cat, prod, model, devs, selfH, prog, phase (build, beta, live), cust, revW, int, use: [company ids] }.
///
/// Not ported: the better marketing (`aw`) that a social app gives your companies.
public enum StartupProducts {
    public struct Sector: Identifiable, Equatable {
        public var id: String
        public var name: String
        /// How capital-hungry it is, 1...4 (investors look at this).
        public var capitalNeed: Int
        /// Seed money for one unit of seed, in the game's base prices.
        public var seed: Double
        /// Work needed (builder-weeks) before the product is ready.
        public var work: Double
        public var canBuildYourself: Bool
        public var builders: String
        /// Revenue per customer and year, and how fast customers come.
        public var arpu: Double
        public var growth: Double
        public var countsUsers: Bool
        public var products: [(id: String, name: String)]
        public var models: [(id: String, name: String)]
        public static func == (a: Sector, b: Sector) -> Bool { a.id == b.id }
    }

    public static let sectors: [Sector] = [
        Sector(id: "saas", name: "SaaS / Software", capitalNeed: 1, seed: 250_000, work: 30, canBuildYourself: true, builders: "coders", arpu: 1200, growth: 1, countsUsers: false,
               products: [("crm", "CRM and sales"), ("book", "Booking and scheduling"), ("acct", "Accounting and payroll"), ("shop", "Shop and payments"), ("job", "Job and quoting"),
                          ("fleet", "Fleet and routing"), ("cad", "Design and CAD"), ("health", "Patient journals"), ("ticket", "Ticketing and events"), ("erp", "ERP and planning")],
               models: [("once", "One-time purchase"), ("sub", "Subscription"), ("both", "Setup fee + subscription")]),
        Sector(id: "fintech", name: "FinTech", capitalNeed: 2, seed: 1_500_000, work: 48, canBuildYourself: true, builders: "coders", arpu: 1800, growth: 0.8, countsUsers: false,
               products: [("pay", "Payments and card terminals"), ("bankapp", "Banking app"), ("invest", "Investing app"), ("ins", "Insurance platform"), ("lend", "Lending platform")],
               models: [("fee", "Fee per transaction"), ("sub", "Subscription"), ("both", "Subscription + fees")]),
        Sector(id: "ecom", name: "E-commerce", capitalNeed: 1, seed: 400_000, work: 30, canBuildYourself: true, builders: "coders", arpu: 900, growth: 1.1, countsUsers: false,
               products: [("store", "Online store builder"), ("mkt", "Marketplace for shops"), ("check", "Checkout and shipping")],
               models: [("sub", "Subscription"), ("fee", "Share of each sale"), ("both", "Subscription + share")]),
        Sector(id: "ai", name: "AI / Machine Learning", capitalNeed: 2, seed: 800_000, work: 40, canBuildYourself: true, builders: "coders", arpu: 1500, growth: 1.2, countsUsers: false,
               products: [("code", "AI coding assistant"), ("create", "AI design and content"), ("agent", "AI agents for office work"), ("auto", "Process automation")],
               models: [("sub", "Subscription"), ("use", "Pay per use")]),
        Sector(id: "health", name: "HealthTech", capitalNeed: 3, seed: 3_000_000, work: 60, canBuildYourself: true, builders: "developers and clinicians", arpu: 2500, growth: 0.5, countsUsers: false,
               products: [("diag", "Diagnostics"), ("clinic", "Clinic software"), ("well", "Wellness and training app"), ("tele", "Video consultations")],
               models: [("sub", "Subscription"), ("lic", "Licence per clinic")]),
        Sector(id: "edtech", name: "EdTech", capitalNeed: 1, seed: 300_000, work: 30, canBuildYourself: true, builders: "coders", arpu: 600, growth: 1.1, countsUsers: false,
               products: [("plat", "Learning platform"), ("tutor", "Tutoring app"), ("drive", "Driving theory app"), ("corp", "Staff training")],
               models: [("sub", "Subscription"), ("once", "One-time purchase")]),
        Sector(id: "market", name: "Marketplace / Platform", capitalNeed: 2, seed: 600_000, work: 38, canBuildYourself: true, builders: "coders", arpu: 800, growth: 1.3, countsUsers: false,
               products: [("svc", "Booking platform for local services"), ("ride", "Ride and delivery app"), ("food", "Food delivery app"), ("b2b", "Supplier marketplace for businesses")],
               models: [("fee", "Commission per booking"), ("sub", "Subscription for sellers")]),
        Sector(id: "consumer", name: "Consumer Apps", capitalNeed: 1, seed: 400_000, work: 32, canBuildYourself: true, builders: "coders", arpu: 2000, growth: 2.5, countsUsers: true,
               products: [("social", "Social media app"), ("ent", "Entertainment app"), ("prod", "Productivity app"), ("life", "Lifestyle app")],
               models: [("ads", "Free with ads"), ("freemium", "Free + premium"), ("paid", "Paid app")]),
        Sector(id: "clean", name: "CleanTech / ClimateTech", capitalNeed: 4, seed: 15_000_000, work: 80, canBuildYourself: false, builders: "engineers", arpu: 6000, growth: 0.3, countsUsers: false,
               products: [("solar", "Solar and storage"), ("ev", "EV charging and fleets"), ("eff", "Energy efficiency"), ("recy", "Recycling")],
               models: [("sale", "Sell the hardware"), ("lease", "Lease / service contract")]),
    ]
    public static func sector(_ id: String) -> Sector? { sectors.first { $0.id == id } }
    public static func productName(sector id: String, product: String) -> String { sector(id)?.products.first { $0.id == product }?.name ?? "" }

    /// What the product does for a company of this trade: d = more customers, k = more capacity, aw = better marketing (not used), c = lower running costs.
    public struct Effect: Equatable {
        public var d = 0.0, k = 0.0, aw = 0.0, c = 0.0
        public var text: String
        public var summary: String {
            [d > 0 ? "+\(Int((d * 100).rounded()))% customers" : "", k > 0 ? "+\(Int((k * 100).rounded()))% capacity" : "",
             aw > 0 ? "marketing +\(Int((aw * 100).rounded()))%" : "", c > 0 ? "-\(Int((c * 100).rounded()))% running costs" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// Original: `fxFor(cat, prod, bd)`.
    public static func effect(sector cat: String, product prod: String, trade bd: Trade) -> Effect? {
        func has(_ list: String) -> Bool { list.split(separator: " ").contains { String($0) == bd.id } }
        let fam = bd.family
        func F(d: Double = 0, k: Double = 0, aw: Double = 0, c: Double = 0, _ t: String) -> Effect { Effect(d: d, k: k, aw: aw, c: c, text: t) }
        let consumer = bd.audience < 0.6 && !["fin", "energy", "hold", "club", "rent"].contains(fam)
        switch cat {
        case "fintech":
            if fam == "fin" { return F(d: 0.12, "Own app: easier to use, more customers") }
            if prod == "pay" && (fam == "retail" || fam == "venue") { return F(d: 0.03, "Faster checkout") }
            return nil
        case "ecom":
            return fam == "retail" || has("bakery brewery furniture") ? F(d: 0.08, "Sells online through your platform") : nil
        case "ai":
            if prod == "code" { return has("webdev") ? F(k: 0.15, "Coders work faster") : nil }
            if prod == "create" { return has("mktg photo event engcons furniture") ? F(k: 0.12, "Faster creative work") : nil }
            if prod == "agent" { return has("cons acctfirm law staffing estate mktg") ? F(k: 0.1, "Less office work") : nil }
            return fam == "prod" || fam == "logi" ? F(k: 0.08, "Automated planning") : nil
        case "health":
            if prod == "well" { return has("gym physio") ? F(d: 0.07, "Members train in your app") : nil }
            return has("physio") ? F(d: 0.05, k: 0.06, "Faster patient work") : nil
        case "edtech":
            if prod == "drive" { return has("drivsk") ? F(d: 0.08, k: 0.05, "Students pass faster") : nil }
            if prod == "corp" { return bd.standardStaff.reduce(0, { $0 + $1.count }) >= 8 ? F(k: 0.03, "Staff learn faster") : nil }
            return has("tutor") ? F(d: 0.04, k: 0.12, "Lessons on your own platform") : nil
        case "market":
            if prod == "ride" { return has("taxi courier") ? F(d: 0.1, "Rides booked in your app") : nil }
            if prod == "food" { return has("restaurant foodtruck cafe bakery") ? F(d: 0.07, "Orders through your delivery app") : nil }
            if prod == "b2b" { return fam == "prod" || has("hardware") ? F(d: 0.05, "Business buyers find you") : nil }
            return has("handy cleaning pets carclean barber photo tutor") ? F(d: 0.07, "Bookings from your platform") : nil
        case "consumer":
            if prod == "social" { return consumer ? F(aw: 0.3, "Your own social media") : nil }
            if prod == "ent" { return fam == "venue" ? F(d: 0.03, aw: 0.15, "Promoted in your app") : nil }
            if prod == "life" { return has("gym cafe boutique barber restaurant") ? F(aw: 0.15, "Featured in your app") : nil }
            return fam == "svc" ? F(k: 0.03, "Staff organise better") : nil
        case "clean":
            if prod == "ev" { return fam == "logi" ? F(c: 0.1, "Cheaper fuel and charging") : nil }
            if prod == "recy" { return fam == "prod" ? F(c: 0.04, "Waste becomes income") : nil }
            if bd.id == "power" { return F(d: 0.05, "Your own solar tech") }
            return fam == "prod" || has("hotel grocery gym") ? F(c: 0.06, "Lower energy costs") : nil
        default: return nil
        }
    }

    /// The total effect on one company right now from the products it uses. Original: `fxNow`.
    public static func effectNow(_ co: Company, _ s: GameState, trade: Trade) -> Effect {
        var out = Effect(text: "")
        guard let list = s.rest["founded"]?.array, !list.isEmpty else { return out }
        for f in list {
            let w = f["sw16"]
            guard !w.isNull, f["st"].string == "live", ["beta", "live"].contains(w["phase"].string), w["use"].array.contains(where: { $0.int == co.id }) else { continue }
            if !co.value("gl16")[String(f["id"].int)].isNull, co.value("gl16")[String(f["id"].int)].int == s.week { continue }
            guard let x = effect(sector: w["cat"].string, product: w["prod"].string, trade: trade) else { continue }
            let k = (w["phase"].string == "live" ? 1.0 : 0.6) * (0.6 + (f["q"].isNull ? 0.5 : f["q"].double) * 0.6)
            out.d += x.d * k; out.k += x.k * k; out.aw += x.aw * k; out.c += x.c * k
        }
        return out
    }
}
