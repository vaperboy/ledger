import Foundation
import GameCore
import Countries
import Finance

/// The businesses that have a weekly model of their own: energy (power producer, oil and gas), the salmon farm, the holding company
/// and the football club. `CompanyWeek` asks this file whether it should hand the week over, and how the opening checklist, the
/// purchase of equipment and a few other places differ for them. The models themselves are in `EnergyModel`, `SalmonModel`,
/// `HoldingModel` and `FootballModel`. Originals: `FAM.energy`, `FAM.prod.custom` (salmon), `FAM.hold`, `FAM.club`.
public enum SpecialFamilies {
    /// Does this trade use one of the special weekly models?
    public static func handles(_ bd: Trade) -> Bool {
        bd.family == "energy" || bd.family == "hold" || bd.family == "club" || bd.id == "salmon"
    }

    /// Trades that are started from the trade menu. A holding and a football club have their own entry points
    /// (a holding takes the companies it holds, a club is bought or founded in a league).
    public static func isStartable(_ bd: Trade) -> Bool {
        CompanyWeek.isSupported(bd) && bd.family != "hold" && bd.family != "club"
    }

    /// The week of a company with a special model: returns what the common bookkeeping (`book`, `weekEnd`) needs.
    static func week(_ s: inout GameState, _ i: Int, _ bd: Trade, _ data: GameData) -> CompanyWeek.WeekContext {
        switch bd.family {
        case "hold": return HoldingModel.context(&s, i, data)
        case "club": return FootballModel.context(&s, i, bd, data)
        case "energy": return bd.hasTrait("power") ? EnergyModel.powerContext(&s, i, bd, data) : EnergyModel.oilContext(&s, i, bd, data)
        default: return SalmonModel.context(&s, i, bd, data)
        }
    }

    /// Extra things a company of this kind needs before it can open. Original: `FAM.*.checklist`.
    static func checklist(_ co: Company, _ bd: Trade, _ w: World) -> [OpeningChecklist.Item] {
        if bd.hasTrait("power") {
            let n = co.value("eq")["turb"]["n"].double
            return [OpeningChecklist.Item(id: "mw", title: "Order at least 1 MW of generation capacity (Equipment)", isDone: n >= 1, detail: "")]
        }
        if bd.id == "salmon" {
            let need = SalmonModel.firstStockingCash(bd)
            return [OpeningChecklist.Item(id: "cash", title: "Cash for first smolt stocking (about \(w.currency(co).short(jsRound(need))))", isDone: co.cash > need, detail: "")]
        }
        return []
    }

    /// Called after equipment was bought. Original: `FAM.*.afterBuy`.
    static func afterBuy(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, equipmentID: String, quantity: Double) {
        EnergyModel.afterBuy(&s, i, bd, equipmentID: equipmentID, quantity: quantity)
    }

    /// An event effect that only some businesses understand (salmon: `ill`). Original: `FAM.prod.fx`.
    public static func applyEventEffect(_ s: inout GameState, companyIndex i: Int, _ bd: Trade, fx: JSONValue) {
        if bd.id == "salmon" { SalmonModel.applyIllness(&s, companyIndex: i, amount: fx["ill"].double) }
    }

    /// Quality of a football club is the strength of its squad. Original: `qualityTarget`.
    static func qualityTarget(_ co: Company, _ bd: Trade) -> Double? {
        bd.family == "club" ? clamp(co.value("fm")["s"].isNull ? 50 : co.value("fm")["s"].double, 5, 99) : nil
    }

    /// What the start-up estimate adds for this trade (salmon: fifteen months without sales).
    static func extraStartupBuffer(_ bd: Trade, size: Double, country: Country) -> Double {
        bd.id == "salmon" ? SalmonModel.startupBuffer(bd, size: size, country: country) : 0
    }

    /// Steps run once a week after the companies, in the order of the original's 'week.after' steps.
    public static func weeklyAfter(_ s: inout GameState, data: GameData, context fc: FinanceContext) {
        EnergyModel.weeklyAfter(&s, data: data)
        HoldingModel.weekly(&s, data: data, context: fc)
    }

    // MARK: A blank company record (for companies that are bought, not started)

    /// A company in the same shape `CompanySetup.create` makes, without charging the owner for registration or share capital.
    /// Used for football clubs, which are bought or founded rather than started.
    static func blankCompany(_ s: inout GameState, tradeID: String, country: Country, cityID: String, name: String, size: Double, data: GameData) -> Int? {
        guard let bd = data.catalog[tradeID] else { return nil }
        let currency = Currency(country: country, rates: ExchangeRates(drift: s.exchangeRates.values))
        var co = Company(raw: [:])
        co.id = s.makeID()
        co.type = tradeID; co.countryCode = country.code
        co.name = name
        co.cityID = cityID; co.form = .limited; co.size = size; co.status = .setup
        co.foundedWeek = s.week; co.openedWeek = nil; co.cash = 0; co.ownership = 100
        co.set("holders", .array([])); co.set("docs", .object([:])); co.set("eq", .object([:])); co.set("veh", .array([])); co.set("lease", .object([:]))
        co.set("staff", .array([])); co.set("mgrWage", 0); co.set("mgrBonus", 0)
        co.set("auth", .object(["lvl": 0, "buy": .number(currency.scaledPrice(25000)), "hire": .number(currency.scaledPrice(8000)), "ad": .number(currency.scaledPrice(3000))]))
        co.set("region", 0); co.set("mkt", .object([:])); co.awareness = 25
        co.set("knob", .object([:]))
        co.priceLevel = 0; co.ownerHours = 0; co.reputation = 45; co.quality = 45; co.ownerSkill = 40; co.maintenance = 1
        co.set("stockPol", 1); co.set("bid", 1); co.set("prem", .null); co.set("recv", .array([]))
        co.set("pay", .object(["wages": 0, "other": 0, "tax": 0, "rent": 0])); co.vatBalance = 0; co.inventory = 0
        co.books = Books(); co.set("hist", .array([])); co.set("mods", .array([])); co.set("tx", .array([]))
        co.set("ins", .object([:])); co.set("flags", .object([:])); co.set("fm", .object([:]))
        co.set("lossCarry", 0); co.set("dist", 0); co.set("capital", 0); co.set("inj", 0); co.set("ownerSalary", 0)
        co.set("unitsW", 0); co.set("mgrQ", 0); co.set("eqc", 1); co.set("books", 0.5); co.set("group", 0)
        _ = bd
        s.companies.append(co)
        return co.id
    }
}
