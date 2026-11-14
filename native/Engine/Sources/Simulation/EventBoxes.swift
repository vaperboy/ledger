import Foundation
import GameCore

/// One event box of a set: a box slot (event1 to event6) with its own name and its exclusive epic and legendary items.
public struct EventBox: Equatable, Sendable, Identifiable {
    public var id: String
    public var slot: Int
    public var title: String
    public var setID: String
    public var setTitle: String
    /// The set's box picture (Content/art/<art>.png); drawn as a plain box until the file exists.
    public var art: String
    public var colors: [UInt32]
    public var items: [String]
    public var kind: BoxKind { BoxKind.event(slot) ?? .event1 }
}

public struct EventSet: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var art: String
    public var colors: [UInt32]
    public var boxes: [EventBox]
}

/// Six event boxes on sale together, changing every rotationDays days from the epoch (UTC days). The server picks the same set from the
/// same file; its answer wins when it has sent one.
public enum EventBoxes {
    private static let file: JSONValue = ContentFile.load("boxes", "events")

    public static let rotationDays: Int = max(1, file["rotationDays"].int)
    public static let epochDay: Int = SeasonCatalog.eraDay(file["epoch"].string) ?? 0

    public static let sets: [EventSet] = file["sets"].array.map { (s: JSONValue) -> EventSet in
        let setID: String = s["id"].string
        let boxes: [EventBox] = s["boxes"].array.map { (b: JSONValue) -> EventBox in
            EventBox(id: b["id"].string, slot: b["slot"].int, title: b["title"].string, setID: setID, setTitle: s["title"].string, art: s["art"].string,
                     colors: ContentFile.colors(b["colors"]), items: b["items"].array.map { (i: JSONValue) -> String in i["id"].string })
        }
        return EventSet(id: setID, title: s["title"].string, art: s["art"].string, colors: ContentFile.colors(s["colors"]), boxes: boxes)
    }

    /// Every event item as a cosmetic (source .event). Only event boxes give them.
    public static let cosmetics: [GoldCosmetic] = file["sets"].array.flatMap { (s: JSONValue) -> [GoldCosmetic] in
        s["boxes"].array.flatMap { (b: JSONValue) -> [GoldCosmetic] in
            b["items"].array.map { (e: JSONValue) -> GoldCosmetic in GoldCosmetics.parse(e, source: .event) }
        }
    }

    /// Today as a UTC era day on the trusted clock, the day the server rotates by.
    public static func utcDay() -> Int {
        var cal: Calendar = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? cal.timeZone
        return cal.ordinality(of: .day, in: .era, for: TrustedClock.now()) ?? 0
    }

    /// The rotation number of a day (0 at the epoch).
    public static func rotation(day: Int) -> Int {
        let d: Int = day - epochDay
        return d >= 0 ? d / rotationDays : -((-d + rotationDays - 1) / rotationDays)
    }

    /// The rotation shown now: the server's when it has answered, else the one of today.
    public static func currentRotation(day: Int? = nil) -> Int {
        if day == nil, let r = ServerPriceBook.shared.value("events", "rotation") { return r }
        return rotation(day: day ?? utcDay())
    }

    public static func set(rotation r: Int) -> EventSet? {
        guard !sets.isEmpty else { return nil }
        return sets[((r % sets.count) + sets.count) % sets.count]
    }

    public static func current(day: Int? = nil) -> [EventBox] { set(rotation: currentRotation(day: day))?.boxes ?? [] }

    public static func box(_ kind: BoxKind, day: Int? = nil) -> EventBox? {
        guard let slot = kind.eventSlot else { return nil }
        return current(day: day).first { $0.slot == slot }
    }

    /// The first UTC day of the next rotation.
    public static func nextChangeDay(day: Int? = nil) -> Int { epochDay + (currentRotation(day: day) + 1) * rotationDays }

    /// The event box an item belongs to, in any set.
    public static func home(of itemID: String) -> EventBox? {
        for s in sets { for b in s.boxes where b.items.contains(itemID) { return b } }
        return nil
    }

    /// Unowned exclusive items of one rarity in the box of a slot.
    public static func pool(_ kind: BoxKind, _ rarity: BoxRarity, owned: Set<String>, day: Int? = nil) -> [GoldCosmetic] {
        guard let b = box(kind, day: day) else { return [] }
        return cosmetics.filter { (c: GoldCosmetic) -> Bool in b.items.contains(c.id) && c.rarity == rarity && !owned.contains(c.id) }
    }
}
