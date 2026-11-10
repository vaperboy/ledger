import Foundation
import GameCore

public struct EquipmentSpec: Equatable, Sendable {
    public var id: String
    public var name: String
    public var cost: Double
    public var lifeYears: Double
    public var standardCount: Double
    public var flags: String
    public var vehicleModels: [String]?
    public var personalRule: PersonalEquipment.Rule? = nil

    public var isRequired: Bool { flags.contains("r") }
    public var limitsCapacity: Bool { flags.contains("c") }
    public var opensTheTrade: Bool { isRequired || limitsCapacity }
    public var affectsQuality: Bool { flags.contains("q") }
    public var allowsOwnCar: Bool { flags.contains("o") }
}

public struct KnobOption: Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var effects: [String: Double]
    public var requiredDocs: [String]
}

public struct Knob: Equatable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var options: [KnobOption]
    public var defaultIndex: Int
    public var isMulti: Bool
}

public struct Trade: TradeFacts, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var family: String
    public var category: String
    public var vatCategory: String
    public var unit: String
    public var ticket: Double
    public var costOfSales: Double
    public var margin: Double
    public var explicitDemand: Double
    public var elasticity: Double
    public var seasonKey: String
    public var businessShare: Double
    public var paymentTermsWeeks: Int
    public var premisesKind: String?
    public var premisesM2: Double
    public var standardStaff: [(role: String, count: Double)]
    public var ownerFTE: Double
    public var equipment: [EquipmentSpec]
    public var foreignItems: [EquipmentSpec] = []
    public var allEquipment: [EquipmentSpec] { foreignItems.isEmpty ? equipment : equipment + foreignItems }
    public var documents: [String]
    public var managerType: String
    public var fixedWeekly: Double
    public var knobs: [Knob]
    public var eventIDs: [String]
    public var openingCost: Double
    public var blurb: String
    public var minSize: Double
    public var maxSize: Double
    public var audience: Double
    public var skillName: String
    public var ticketMultiplier: Double
    public var traits: [String: Double]
    public var traitText: [String: String]
    public var documentQuantities: [String: JSONValue]
    public var raw: JSONValue

    public var weeklyFixedCosts: Double = 0
    public var variableCostShare: Double = 0
    public var normalDemand: Double = 0
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
                          vehicleModels: e["vo"].isNull ? nil : e["vo"].array.map { $0.string },
                          personalRule: e["pe"].isNull ? nil : PersonalEquipment.Rule(roles: e["pe"]["roles"].array.map { $0.string }, peoplePerUnit: e["pe"]["per"].double, workWithout: e["pe"]["without"].double))
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
        minSize = j["minSize"].double
        maxSize = j["maxSize"].double
        audience = j["aud"].double
        skillName = j["skill"].string
        ticketMultiplier = j["rm"].isNull ? 1 : j["rm"].double
        traits = j["tw"].object.compactMapValues { $0.isNumber ? $0.double : nil }
        traitText = j["tw"].object.compactMapValues { if case .string(let s) = $0 { return s } else { return nil } }
        documentQuantities = j["dq"].object
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
