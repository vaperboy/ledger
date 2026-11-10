import Foundation
import GameCore
import Businesses

public enum LegacyIds {
    static let documents: [String: String] = [
        "acctr": "accountant_agreement",
        "aif": "fund_manager",
        "aml": "aml_programme",
        "aoc": "air_operator",
        "aqua": "aquaculture_licence",
        "bank": "banking_licence",
        "bemanning": "staffing_registration",
        "brygg": "brewery_licence",
        "buslic": "bus_licence",
        "bygg": "building_permit",
        "casino": "casino_licence",
        "ce": "product_certification",
        "chain": "chain_registration",
        "child": "police_certificate",
        "drone": "drone_registration",
        "eh": "ecommerce_terms",
        "elvirk": "electrical_contractor",
        "event": "event_permit",
        "fabrik": "environmental_permit",
        "fishq": "fish_health",
        "forb": "liability_insurance",
        "forreg": "foreign_entity",
        "forsik": "insurance_licence",
        "fran": "franchise_disclosure",
        "fran_op": "franchise_agreement",
        "garanti": "warranty_policy",
        "gdpr": "data_protection",
        "goods": "goods_transport",
        "grid": "grid_connection",
        "haccp": "food_safety_plan",
        "helse": "health_authorisation",
        "hms": "workplace_safety",
        "hpr": "clinic_approval",
        "ins_bil": "ins_motor",
        "ins_hjem": "ins_home",
        "ins_naring": "ins_business",
        "ins_reise": "ins_travel",
        "ins_skade": "ins_property",
        "kunnsk": "competence_certificate",
        "landb": "farm_registration",
        "lawyer": "lawyer_licence",
        "lift": "ski_lift_approval",
        "mattil": "food_registration",
        "megler": "estate_agency",
        "mfinans": "credit_notification",
        "mva": "vat",
        "mva_na": "vat_not_applicable",
        "nve": "power_licence",
        "nveLite": "solar_notification",
        "oil": "oil_licence",
        "oilsafe": "oil_safety",
        "org": "registration",
        "ped": "pet_registration",
        "regplan": "zoning_plan",
        "renhold": "cleaning_approval",
        "rev": "accounting_approval",
        "safety": "site_safety",
        "salg": "alcohol_retail",
        "skip": "ship_registration",
        "skjenk": "alcohol_serving",
        "skog": "forestry_plan",
        "stat": "lease_agreement",
        "taxi": "taxi_licence",
        "tgodk": "building_contractor",
        "tobak": "tobacco_sales",
        "torg": "street_trading",
        "trafikk": "driving_school",
        "vakt": "security_licence",
        "verk": "workshop_approval",
        "vik": "fire_safety",
        "vinm": "alcohol_wholesale",
        "vinn": "used_goods",
        "vvs": "plumbing_approval",
        "xray": "xray_registration",
        "ysk": "driver_certificate",
        "zone": "slope_zoning",
    ]
    static let stocks: [String: String] = ["NRDK": "ENRG", "FJSF": "FOOD", "HVBK": "BANK", "STVK": "INDU", "TLNR": "TELE", "SKOG": "MATL", "SHIP": "TRAN", "EIEN": "PROP"]
    static let crypto: [String: String] = ["NRC": "ALT"]

    private static func renameKeys(_ v: JSONValue, _ map: [String: String]) -> JSONValue {
        guard !v.isNull else { return v }
        var o: [String: JSONValue] = [:]
        for (k, x) in v.object { o[map[k] ?? k] = x }
        return .object(o)
    }

    public static func migrate(_ root: inout [String: JSONValue]) {
        var companies = root["cos"]?.array ?? []
        for i in companies.indices {
            let docs = companies[i]["docs"]
            if !docs.isNull {
                var renamed: [String: JSONValue] = [:]
                for (k, v) in docs.object { renamed[documents[k] ?? k] = v }
                companies[i]["docs"] = .object(renamed)
            }
        }
        if !companies.isEmpty { root["cos"] = .array(companies) }
        RentalFinance.migrateLegacy(&root)
        if let s = root["stocks"] { root["stocks"] = renameKeys(s, stocks) }
        if let c = root["crypto"] { root["crypto"] = renameKeys(c, crypto) }
        if var inv = root["inv"], !inv.isNull {
            if !inv["crypto"].isNull { inv["crypto"] = renameKeys(inv["crypto"], crypto) }
            root["inv"] = inv
        }
    }
}
