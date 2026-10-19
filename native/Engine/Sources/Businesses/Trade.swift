import Foundation
import GameCore

/// A piece of equipment or a vehicle type a business uses. Original: `bd.eq` entries.
public struct EquipmentSpec: Equatable, Sendable {
    public var id: String
    public var name: String
    /// Price new, at the reference cost level
    public var cost: Double
    public var lifeYears: Double
    /// Standard number needed at size 1
    public var standardCount: Double
    /// Flags: r = required to open, c = sets capacity, q = affects quality, u = can be bought used
    public var flags: String
    /// Vehicle model ids this equipment is bought as, if it is a vehicle: [model]
    public var vehicleModels: [String]?

    public var isRequired: Bool { flags.contains("r") }
    public var limitsCapacity: Bool { flags.contains("c") }
    public var affectsQuality: Bool { flags.contains("q") }
}

/// One option of a business choice ("knob"). Original: knob options with `fx`.
public struct KnobOption: Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    /// Effects: t = ticket (price) multiplier, d = demand multiplier, k = capacity multiplier, c = cost-of-sales
    /// change (added), q = quality (added), w = extra weekly fixed cost (added), ota = commission share ...
    public var effects: [String: Double]
    /// Documents that must be held for the option to work
    public var requiredDocs: [String]
}

public struct Knob: Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var options: [KnobOption]
    public var defaultIndex: Int
    /// A group of add-ons: several options can be on at once (bit mask).
    public var isMulti: Bool
}

/// A type of business: the data that makes a café different from a gym. Loaded from `trades.json`.
/// Original: `BD[id]`. To add or tune a business, edit the JSON; see docs/ADDING_CONTENT.md.
public struct Trade: TradeFacts, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var family: String
    public var category: String
    /// VAT category: "std", "food", "low" or "zero"
    public var vatCategory: String
    /// What one sale is called ("order", "billable hour", "room-night" ...)
    public var unit: String
    /// Typical price of one sale at the reference price level
    public var ticket: Double
    /// Cost of sales as a share of revenue
    public var costOfSales: Double
    public var margin: Double
    /// Explicit weekly demand, 0 = derived from costs. Original: `D`.
    public var explicitDemand: Double
    /// Price elasticity of demand
    public var elasticity: Double
    public var seasonKey: String
    /// Share of sales to business customers who pay later
    public var businessShare: Double
    public var paymentTermsWeeks: Int
    public var premisesKind: String?
    public var premisesM2: Double
    public var standardStaff: [(role: String, count: Double)]
    /// How many full-time equivalents the owner can supply at size 1
    public var ownerFTE: Double
    public var equipment: [EquipmentSpec]
    public var documents: [String]
    public var managerType: String
    public var fixedWeekly: Double
    public var knobs: [Knob]
    public var eventIDs: [String]
    public var openingCost: Double
    public var blurb: String
    public var needsLimitedCompany: Bool
    public var minSize: Double
    public var maxSize: Double
    /// 0 = consumers, 1 = business customers
    public var audience: Double
    public var skillName: String
    /// Price multiplier applied to the ticket. Original: `rm` (default 1).
    public var ticketMultiplier: Double
    /// Trade-specific parameters (stock weeks, perishables, fuel ...). Original: `tw`.
    public var traits: [String: Double]
    public var traitText: [String: String]
    public var documentQuantities: [String: JSONValue]
    /// Everything in the data file, kept whole.
    public var raw: JSONValue

    // Derived by `TradeCatalog` (calibration). Original: `calib(bd)`.
    public var weeklyFixedCosts: Double = 0
    public var variableCostShare: Double = 0
    /// Customers per week at a normal level. Original: `Dc`.
    public var normalDemand: Double = 0
    /// Customers per week a normally staffed business can serve. Original: `capD`.
    public var normalCapacity: Double = 0
    var hasStoredCalibration = false

    public var margin_: Double { margin }

    public static func == (a: Trade, b: Trade) -> Bool { a.id == b.id && a.raw == b.raw }

    public func trait(_ k: String) -> Double? { traits[k] }
    public func hasTrait(_ k: String) -> Bool { (traits[k] ?? 0) != 0 }

    public init(json j: JSONValue) {
        raw = j
        id = j["id"].string
        name = j["n"].string
        family = j["fam"].string
        category = j["cat"].string
        vatCategory = j["vat"].string
        unit = j["unit"].string
        ticket = j["ticket"].double
        costOfSales = j["cogs"].double
        margin = j["m"].double
        explicitDemand = j["D"].double
        elasticity = j["ela"].double
        seasonKey = j["seas"].string
        businessShare = j["b2b"].double
        paymentTermsWeeks = j["terms"].int
        premisesKind = j["prem"].isNull ? nil : j["prem"][0].string
        premisesM2 = j["prem"].isNull ? 0 : j["prem"][1].double
        standardStaff = j["std"].array.map { ($0[0].string, $0[1].double) }
        ownerFTE = j["own"].double
        equipment = j["eq"].array.map { e in
            EquipmentSpec(id: e["id"].string, name: e["n"].string, cost: e["cost"].double, lifeYears: e["life"].double,
                          standardCount: e["std"].double, flags: e["fl"].string,
                          vehicleModels: e["vo"].isNull ? nil : e["vo"].array.map { $0.string })
        }
        documents = j["docs"].array.map { $0.string }
        managerType = j["mgr"].string
        fixedWeekly = j["fixed"].double
        knobs = j["knobs"].array.map { k in
            Knob(id: k["id"].string, name: k["n"].string, detail: k["d"].string,
                 options: k["opts"].array.map { o in
                     KnobOption(id: o["id"].string, name: o["n"].string, detail: o["d"].string,
                                effects: o["fx"].object.compactMapValues { $0.isNumber ? $0.double : nil },
                                requiredDocs: o["fx"]["req"].array.map { $0.string })
                 },
                 defaultIndex: k["def"].int, isMulti: k["multi"].bool)
        }
        eventIDs = j["ev"].array.map { $0.string }
        openingCost = j["open"].double
        blurb = j["blurb"].string
        needsLimitedCompany = j["needAS"].bool
        minSize = j["minSize"].double
        maxSize = j["maxSize"].double
        audience = j["aud"].double
        skillName = j["skill"].string
        ticketMultiplier = j["rm"].isNull ? 1 : j["rm"].double
        traits = j["tw"].object.compactMapValues { $0.isNumber ? $0.double : nil }
        traitText = j["tw"].object.compactMapValues { if case .string(let s) = $0 { return s } else { return nil } }
        documentQuantities = j["dq"].object
        // Derived numbers are stored with the data: they were fixed when the original game last calibrated the trade
        // (some predate later wage-table changes), and the game's balance depends on them. See docs/AUDIT.md.
        weeklyFixedCosts = j["F"].double
        variableCostShare = j["vc"].double
        normalDemand = j["Dc"].double
        normalCapacity = j["capD"].double
        hasStoredCalibration = !j["Dc"].isNull
    }
}

extension JSONValue {
    var isNumber: Bool { if case .number = self { return true } else { return false } }
}
