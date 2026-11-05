import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The supplied art sheets, sliced into single pictures by `native/tools/slice_sheets.py` and bundled as the folder reference `cells/`
/// (`cells/<sheet>/<cell>.jpg` plus `cells/<sheet>/manifest.json`). This type only reads the manifests and maps game ids to cells; it holds
/// no game rules. Everything answers nil when a picture is missing so `ThumbnailView` can show its icon fallback.
enum ArtLibrary {
    /// The sheets that have been sliced (face sheets are handled elsewhere).
    enum Sheet: String, CaseIterable {
        case premises, luxury, cars, logos, trophies, items
    }

    // MARK: Manifests and pictures

    private final class Store {
        let lock = NSLock()
        var manifests: [Sheet: [String: [String: Any]]] = [:]
        #if canImport(UIKit)
        let cache = NSCache<NSString, UIImage>()
        #endif
    }
    private static let store = Store()

    private static var cellsRoot: String? { Bundle.main.resourcePath.map { $0 + "/cells" } }

    /// cell id -> manifest entry (`file`, `row`, `col`, `caption`, ...).
    static func manifest(_ sheet: Sheet) -> [String: [String: Any]] {
        store.lock.lock(); defer { store.lock.unlock() }
        if let m = store.manifests[sheet] { return m }
        var cells: [String: [String: Any]] = [:]
        if let root = cellsRoot,
           let data = FileManager.default.contents(atPath: root + "/" + sheet.rawValue + "/manifest.json"),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let c = obj["cells"] as? [String: [String: Any]] {
            cells = c
        }
        store.manifests[sheet] = cells
        return cells
    }

    static func hasCell(_ sheet: Sheet, _ cell: String) -> Bool { manifest(sheet)[cell] != nil }

    /// The caption printed under the cell on the sheet (cropped away from the picture).
    static func caption(_ sheet: Sheet, _ cell: String) -> String { (manifest(sheet)[cell]?["caption"] as? String) ?? "" }

    #if canImport(UIKit)
    static func image(_ sheet: Sheet, _ cell: String) -> UIImage? {
        guard let file = manifest(sheet)[cell]?["file"] as? String, let root = cellsRoot else { return nil }
        let key = (sheet.rawValue + "/" + cell) as NSString
        if let hit = store.cache.object(forKey: key) { return hit }
        guard let img = UIImage(contentsOfFile: root + "/" + file) else { return nil }
        store.cache.setObject(img, forKey: key)
        return img
    }
    #endif

    // MARK: Premises (kind x size band)

    /// Size bands of the premises sheet, by square metres: under 50 small, 50 to 150 medium, 150 to 500 large, 500 and more very large.
    static func premisesBand(squareMetres: Double) -> String {
        if squareMetres < 50 { return "small" }
        if squareMetres < 150 { return "medium" }
        if squareMetres < 500 { return "large" }
        return "xlarge"
    }

    private static let premisesKinds: Set<String> = ["home", "office", "shop", "kitchen", "industrial", "warehouse", "hotel", "clinic", "yard", "gym", "slope"]

    /// The cell id for a premises kind (the engine's `premisesKind`) and a floor area; a kind the sheet has no row for gives a key that
    /// matches no cell, so the slot shows its icon.
    static func premisesKey(kind: String?, squareMetres: Double?) -> String {
        let k = kind ?? "office"
        guard premisesKinds.contains(k) else { return "none-" + premisesBand(squareMetres: squareMetres ?? 0) }
        return k + "-" + premisesBand(squareMetres: squareMetres ?? 0)
    }

    // MARK: Luxury items

    /// Game luxury item id -> (sheet, cell). Cars come from the cars sheet, everything else from the luxury sheet; where the sheet has
    /// fewer pictures than the game has items a picture is used twice.
    static let luxuryCells: [String: (sheet: Sheet, cell: String)] = [
        // cars (cars-sheet, cell b<brand row>-<column>)
        "c15": (.cars, "b2-2"), "c1": (.cars, "b2-1"), "c11": (.cars, "b1-3"), "c10": (.cars, "b1-2"), "c7": (.cars, "b1-1"),
        "c8": (.cars, "b6-3"), "c9": (.cars, "b6-2"), "c2": (.cars, "b5-1"), "c4": (.cars, "b3-1"), "c3": (.cars, "b3-2"),
        "c14": (.cars, "b7-3"), "c13": (.cars, "b3-3"), "c12": (.cars, "b4-1"), "c5": (.cars, "b7-1"), "c6": (.cars, "b5-2"),
        // watches and jewellery
        "w2": (.luxury, "watches-1"), "w1": (.luxury, "watches-2"), "w5": (.luxury, "watches-3"), "w3": (.luxury, "jewellery-1"),
        "w4": (.luxury, "watches-4"), "w6": (.luxury, "watches-5"), "w7": (.luxury, "watches-6"), "w8": (.luxury, "watches-3"),
        // art and collectibles
        "a1": (.luxury, "art-1"), "a2": (.luxury, "art-4"), "a3": (.luxury, "art-5"), "a4": (.luxury, "art-2"), "a5": (.luxury, "art-1"),
        // yachts and jets
        "y1": (.luxury, "yachtjet-3"), "y2": (.luxury, "yachtjet-2"), "y3": (.luxury, "yachtjet-1"),
        "j1": (.luxury, "homes-1"), "j2": (.luxury, "yachtjet-6"), "j4": (.luxury, "yachtjet-5"), "j3": (.luxury, "yachtjet-4"), "j5": (.luxury, "yachtjet-4"),
        // homes and estates
        "h3": (.luxury, "homes-4"), "h4": (.luxury, "homes-2"), "h1": (.luxury, "homes-2"), "h2": (.luxury, "homes-2"),
        "e4": (.luxury, "homes-4"), "e3": (.luxury, "homes-5"), "e1": (.luxury, "homes-5"), "e5": (.luxury, "homes-5"), "e2": (.luxury, "homes-6"),
    ]

    #if canImport(UIKit)
    static func luxuryImage(itemID: String) -> UIImage? {
        guard let m = luxuryCells[itemID] else { return nil }
        return image(m.sheet, m.cell)
    }
    #endif

    // MARK: Item art (vehicles, premises, equipment, insurance cards, software)

    private static let vehicleFamilies: [String: [String]] = [
        "bus": ["bus", "bus_var", "bus_v2"], "minibus": ["minibus", "minibus_var", "minibus_v2"],
        "truck_s": ["truck_s", "truck_s_var", "truck_s_v2"], "truck_h": ["truck_h", "truck_h_var", "truck_h_v2"],
        "truck_ev": ["truck_ev", "truck_ev_var", "truck_ev_v2"], "van_box": ["van_box", "van_box_var", "van_box_v2"],
        "van_l": ["van_l", "van_l_var", "van_l_v2"], "ev_van": ["ev_van", "ev_van_var", "ev_van_v2", "delivery_van_ev"],
        "bike": ["bike", "bike_var", "bike_v2"], "scooter": ["scooter", "scooter_var", "scooter_v2"],
        "foodtruck": ["foodtruck", "foodtruck_var", "foodtruck_v2"], "taxi_xl": ["taxi_xl", "taxi_xl_var", "taxi_xl_v2"],
        "taxi_cmf": ["taxi_cmf", "taxi_cmf_var", "taxi_cmf_v2"], "taxi_prm": ["taxi_prm", "taxi_prm_var", "taxi_prm_v2"],
        "excav": ["excav", "excav_var", "excav_v2"], "crane": ["crane", "crane_var", "crane_v2"],
        "van_s": ["van_box", "van_box_var", "van_box_v2"], "pickup": ["pickup"], "car_s": ["car_compact", "car_estate"],
        "car_ev": ["car_suv"], "car_lux": ["car_luxury", "limousine"], "taxi_ev": ["car_estate", "taxi_cmf_var"],
        "car_compact": ["car_compact"], "car_suv": ["car_suv"], "car_estate": ["car_estate"], "car_luxury": ["car_luxury"],
        "minivan": ["minivan"], "limousine": ["limousine"], "ambulance": ["ambulance"], "tow_truck": ["tow_truck"],
        "forklift": ["forklift"], "tractor_road": ["tractor_road"], "dump_truck": ["dump_truck"], "concrete_mixer": ["concrete_mixer"],
        "motorbike_courier": ["motorbike_courier"], "trailer": ["trailer"], "delivery_van_ev": ["delivery_van_ev"],
    ]

    private static let premisesFamilies: [String: [String]] = [
        "kitchen": ["rest_kitchen", "rest_kitchen_var"], "industrial": ["industrial_hall", "ind_hall_var"],
        "warehouse": ["warehouse", "warehouse_var"], "clinic": ["clinic", "clinic_var"], "gym": ["gym_hall", "gym_hall_var"],
        "hotel": ["hotel_building", "hotel_bldg_var"], "yard": ["yard_lot", "yard_lot_var"],
        "slope": ["mountain_slope", "mtn_slope_var"], "home": ["home_building_hero"],
    ]

    /// Engine equipment ids (trades.json `eq`) -> pictures. Ids without a good match are left out and keep their glyph.
    private static let equipmentFamilies: [String: [String]] = [
        "tools": ["handyman_tool_kit", "plumber", "electrician"], "meas": ["electrician", "handyman_tool_kit"], "lad": ["construction", "handyman_tool_kit"],
        "scaf": ["construction"], "wash": ["car_cleaning_machine"], "steam": ["car_cleaning_machine"], "ceram": ["car_cleaning_machine"], "pol": ["car_cleaning_machine"],
        "scrub": ["cleaning_machine"], "vac": ["cleaning_machine"], "chem": ["cleaning_machine"],
        "cam": ["camera_and_lens"], "lens": ["camera_and_lens"], "drone": ["camera_and_lens"], "photo": ["camera_and_lens"], "studio": ["camera_and_lens"], "ed": ["camera_and_lens", "video_editing"],
        "lap": ["laptop"], "ws": ["developer_laptop", "laptop"], "kits": ["developer_laptop"], "tab": ["tutor_tablet"], "mat": ["tutor_tablet"], "room": ["marketing_screen"],
        "desk": ["desk_setup", "office_furniture"], "furn": ["office_furniture"], "show": ["office_furniture"], "web": ["marketing_screen"], "wrap": ["marketing_screen"],
        "oven": ["bakery_oven"], "mix": ["bakery_oven"], "proof": ["bakery_oven"], "bake": ["bakery_oven"],
        "brew": ["brewery_tanks"], "fer": ["brewery_tanks"], "tanks": ["brewery_tanks"], "bot": ["brewery_tanks"], "tap": ["brewery_tanks"], "bottle": ["brewery_tanks"], "press": ["brewery_tanks"], "cold": ["brewery_tanks", "grocery"],
        "tract": ["farm_tractor"], "harv": ["farm_tractor"], "barn": ["farm_tractor"], "fveh": ["pickup"],
        "boat": ["fishing_gear"], "feedb": ["fishing_gear"], "pens": ["fishing_gear"], "lice": ["fishing_gear"],
        "chair": ["hair_salon_chair"], "dry": ["hair_salon_chair"], "unit": ["dental_chair"], "xray": ["dental_chair"], "steril": ["dental_chair"],
        "shelf": ["kiosk_counter", "hardware"], "frz": ["grocery"], "cof": ["kiosk_counter"], "grill": ["restaurant"],
        "range": ["restaurant"], "hood": ["restaurant"], "kitch": ["restaurant"], "kit": ["restaurant"], "ikitch": ["restaurant"], "esp": ["kiosk_counter"], "dish": ["restaurant"],
        "seat": ["restaurant"], "cool": ["grocery", "restaurant"], "wine": ["restaurant"],
        "bar": ["nightclub"], "glass": ["nightclub"], "sound": ["nightclub"], "vip": ["nightclub"], "stage": ["nightclub"], "light": ["nightclub", "camera_and_lens"],
        "cardio": ["gym"], "str": ["gym"], "lock": ["gym"], "sauna": ["gym"], "rooms": ["hotel"], "laun": ["hotel"], "lobby": ["hotel"],
        "tables": ["casino"], "slots": ["casino"], "cage": ["casino"], "lounge": ["casino"], "vault": ["casino"],
        "gates": ["skires"], "snowm": ["skires"], "rent": ["skires"], "irent": ["skires"], "tbar": ["skires"], "igroom": ["skires"], "ilift": ["skires"], "hall": ["skires"],
        "grid": ["electrician"], "ev": ["electrician"], "gen": ["electrician"], "turb": ["electrician"],
        "alarm": ["security"], "cctv": ["security", "pets"], "radio": ["security"], "gate": ["security"],
        "net": ["webshop"], "scan": ["webshop"], "sort": ["webshop"], "pack": ["webshop"],
        "ref": ["grocery"], "tills": ["grocery"], "fridge": ["grocery"], "disp": ["grocery"],
        "saw": ["hardware"], "rack": ["hardware"], "prod": ["hardware"],
        "groom": ["pets"], "kennel": ["pets"], "bench": ["physio"], "shock": ["physio"], "ex": ["physio"],
        "robot": ["factory"], "cnc": ["factory"], "paint": ["factory"], "lab": ["factory"], "air": ["factory"],
        "dtruck": ["truck_h", "truck_h_var"], "dvan": ["van_l", "van_l_var"], "exc": ["excav", "excav_var"], "crane": ["crane", "crane_var"],
        "truck": ["foodtruck", "foodtruck_var"], "van": ["van_l", "van_box"], "vans": ["van_l", "van_box", "van_l_var"], "trail": ["trailer"],
        "fork": ["forklift"], "bike": ["bike", "scooter"], "cars": ["car_compact", "car_estate"], "car": ["car_compact"], "demo": ["car_suv", "car_luxury"],
        "lux": ["car_luxury", "limousine"], "rcar": ["car_compact", "car_suv"], "vcar": ["car_compact", "car_estate"],
        "tms": ["van_l"], "diag": ["laptop"], "plot": ["design_tablet"], "mocap": ["video_editing"],
    ]

    /// Engine software ids and the software product types of `SoftwareProducts` -> pictures.
    private static let softwareFamilies: [String: [String]] = [
        "crm": ["crm_dashboard"], "ats": ["crm_dashboard"], "dms": ["crm_dashboard"], "case": ["licence"], "lib": ["licence"], "lic": ["licence"], "ehr": ["licence"], "health": ["licence"],
        "cloud": ["cloud", "backup_drive"], "sw": ["subscription_box", "cloud"], "core": ["accounting_software"], "it": ["accounting_software"], "pay": ["accounting_software"], "acct": ["accounting_software"],
        "cyber": ["security_shield"], "risk": ["security_shield"], "sec": ["security_shield"],
        "erp": ["analytics_chart"], "ops": ["analytics_chart"], "term": ["analytics_chart"], "seis": ["analytics_chart"], "scada": ["analytics_chart"], "wms": ["analytics_chart"],
        "mdt": ["mobile_app_phone"], "book": ["mobile_app_phone"], "fleet": ["mobile_app_phone"], "nav": ["mobile_app_phone"], "pms": ["mobile_app_phone"],
        "pos": ["pos_terminal"], "shop": ["e_commerce_screen"], "cad": ["design_tablet"], "job": ["licence", "subscription_box"], "ticket": ["email_icon"],
        "support": ["helpdesk_headset"], "mail": ["email_icon"], "backup": ["backup_drive"],
    ]

    /// Atlas products (company policies `INSP` and the insurer's `INS_PRODS`).
    private static let insuranceFamilies: [String: [String]] = [
        "prop": ["business_property_card"], "bi": ["business_property_card"], "property": ["business_property_card"], "business": ["business_property_card"],
        "liab": ["liability_card"], "prof": ["liability_card"], "cyber": ["cyber_card"], "key": ["workers_card"], "life": ["workers_card"], "workers": ["workers_card"],
        "motor": ["car_insurance_card"], "home": ["home_building_hero"], "travel": ["travel_card"], "fleet": ["fleet_card"],
    ]

    /// The cells a family can show. Group is vehicle, premises, equipment, software or insurance; the family key is the engine id
    /// (vehicle model, premises kind, equipment id, software id or product id). Unknown family: empty.
    static func itemKeys(group: String, familyKey: String) -> [String] {
        switch group {
        case "vehicle": return vehicleFamilies[familyKey] ?? []
        case "premises": return premisesFamilies[familyKey] ?? []
        case "software": return softwareFamilies[familyKey] ?? equipmentFamilies[familyKey] ?? []
        case "insurance": return insuranceFamilies[familyKey] ?? []
        default: return equipmentFamilies[familyKey] ?? softwareFamilies[familyKey] ?? vehicleFamilies[familyKey] ?? []
        }
    }

    /// Picks one variant of the family by the seed. A seed ending in `#<number>` (a list index) picks consecutive variants for consecutive
    /// numbers, so two neighbouring listings of one family never show the same picture.
    static func itemKey(group: String, familyKey: String, seed: String) -> String? {
        let keys: [String] = itemKeys(group: group, familyKey: familyKey)
        if keys.isEmpty { return nil }
        var base: String = seed
        var step: UInt64 = 0
        if let at = seed.lastIndex(of: "#"), let n = UInt64(seed[seed.index(after: at)...]) {
            base = String(seed[seed.startIndex..<at])
            step = n
        }
        let pick: Int = Int((stableHash(base) &+ step) % UInt64(keys.count))
        return keys[pick]
    }

    #if canImport(UIKit)
    static func itemImage(group: String, familyKey: String, seed: String) -> UIImage? {
        guard let k = itemKey(group: group, familyKey: familyKey, seed: seed) else { return nil }
        return image(.items, k)
    }
    #endif

    // MARK: Trophies and awards

    /// Trophy engine id -> cell of the trophies sheet (t01 to t36, reading order). Ladders share a prefix (`nw5m` uses `nw`).
    private static let trophyExact: [String: String] = [
        "cust": "t02", "emp": "t31", "profit": "t30", "year": "t24", "mgr": "t05", "branch": "t13", "div": "t25", "abroad": "t12",
        "ten": "t31", "hundred": "t31", "million": "t07", "tenm": "t25", "hm": "t26", "bn": "t28", "bank": "t25",
        "fam": "t12", "hold": "t29", "oil": "t14", "club": "t35", "listed": "t08", "su1": "t02", "sux": "t08", "pe1": "t25", "pe2": "t30",
        "boty": "t03", "acq": "t06", "give": "t09", "g10": "t09", "stars": "t19", "st48": "t19", "tyall": "t01", "rd": "t17",
        "ten10": "t10", "mgr10": "t10", "hq5": "t24", "abr50": "t12", "lx1": "t28", "lxj": "t13", "lxy": "t15", "lxe": "t09", "lxi": "t01",
        "lxm": "t03", "lxw": "t30", "lxc5": "t27", "no1": "t01", "top10": "t11", "team56": "t29",
        "yr5": "t27", "yr10": "t10", "yr25": "t34", "yr50": "t34", "rk50": "t32", "rk3": "t11", "rk1": "t01",
        "nw5b": "t28", "nw10b": "t28", "nw50b": "t28",
    ]
    private static let trophyPrefix: [(String, String)] = [
        ("nw", "t25"), ("dv", "t30"), ("tx", "t33"), ("pf", "t26"), ("jb", "t31"), ("mg", "t05"), ("co", "t13"), ("ty", "t14"),
        ("cc", "t12"), ("aw", "t04"), ("n1", "t01"), ("ch", "t14"), ("fr", "t22"),
    ]
    private static let trophyGroup: [String: String] = [
        "first": "t02", "money": "t25", "people": "t31", "trades": "t14", "world": "t12", "legacy": "t29", "market": "t11",
    ]

    /// The trophies-sheet cell for a trophy (engine id and group): by meaning where known, else a generic cell for the group.
    static func trophyKey(id: String, group: String) -> String {
        if let c = trophyExact[id] { return c }
        for (p, c) in trophyPrefix where id.hasPrefix(p) { return c }
        return trophyGroup[group] ?? "t24"
    }

    /// The cell for a yearly business award kind (`Awards.categories` ids).
    static func awardKey(_ kind: String) -> String {
        switch kind {
        case "boty": return "t03"
        case "emp": return "t31"
        case "rated": return "t19"
        case "new": return "t02"
        case "grow": return "t04"
        case "ent": return "t01"
        default: return "t24"
        }
    }

    // MARK: Logos

    /// Cell ids of the logos sheet in reading order.
    static var logoCells: [String] { manifest(.logos).keys.sorted() }

    /// Gives each firm key (rival, rival group, named firm) its own logo: a stable hash picks the start, a taken logo moves on to the
    /// next free one, and when all are taken the key gets none (the slot then shows initials). Assignments are remembered on the device.
    private final class LogoBook {
        let lock = NSLock()
        var byKey: [String: Int] = [:]
        var taken: Set<Int> = []
        var loaded = false
        static let defaultsKey = "art.logo.assignments"
    }
    private static let logoBook = LogoBook()

    /// FNV-1a: the same on every launch (Swift's own hashing is seeded per run).
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    /// The logo cell id for a firm key such as `group|g12` or `rival|co4|7`; nil for an empty key or when every logo is taken.
    static func logoKey(for key: String) -> String? {
        guard !key.isEmpty else { return nil }
        let cells = logoCells
        guard !cells.isEmpty else { return nil }
        let book = logoBook
        book.lock.lock(); defer { book.lock.unlock() }
        if !book.loaded {
            book.loaded = true
            if let saved = UserDefaults.standard.dictionary(forKey: LogoBook.defaultsKey) as? [String: Int] {
                book.byKey = saved.filter { $0.value >= 0 && $0.value < cells.count }
                book.taken = Set(book.byKey.values)
            }
        }
        if let i = book.byKey[key] { return cells[i] }
        guard book.taken.count < cells.count else { return nil }
        var i = Int(stableHash(key) % UInt64(cells.count))
        while book.taken.contains(i) { i = (i + 1) % cells.count }
        book.taken.insert(i)
        book.byKey[key] = i
        UserDefaults.standard.set(book.byKey, forKey: LogoBook.defaultsKey)
        return cells[i]
    }

    /// Letters for the fallback when no logo is left: the first letters of the first two words.
    static func initials(_ name: String) -> String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first.map { String($0) } }
        return letters.joined().uppercased()
    }
}
