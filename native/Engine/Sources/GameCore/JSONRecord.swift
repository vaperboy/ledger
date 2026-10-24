import Foundation

/// A game object (company, staff member, loan ...) stored as JSON values, with typed properties on top.
///
/// Why: the original game has about 120 fields on a company, many belonging to features that are rewritten
/// in Swift step by step. Keeping the raw JSON guarantees that nothing in an imported save is ever lost, and
/// that a save written by the Swift game can still be understood by the old one. Properties that the Swift
/// game uses are declared on each type in one line each (`var cash: Double { get { num("cash") } set { set("cash", newValue) } }`).
public protocol JSONRecord: Codable, Equatable, Sendable {
    var raw: [String: JSONValue] { get set }
    init(raw: [String: JSONValue])
}

extension JSONRecord {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.init(raw: try c.decode([String: JSONValue].self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }

    public func value(_ key: String) -> JSONValue { raw[key] ?? .null }
    public func num(_ key: String, _ fallback: Double = 0) -> Double {
        guard let v = raw[key], !v.isNull else { return fallback }
        return v.double.finiteOrZero
    }
    public func int(_ key: String, _ fallback: Int = 0) -> Int {
        guard let v = raw[key], !v.isNull else { return fallback }
        return v.int
    }
    public func str(_ key: String, _ fallback: String = "") -> String {
        guard let v = raw[key], !v.isNull else { return fallback }
        return v.string
    }
    public func flag(_ key: String) -> Bool { raw[key]?.bool ?? false }

    public mutating func set(_ key: String, _ v: Double) { raw[key] = .number(v) }
    public mutating func set(_ key: String, _ v: Int) { raw[key] = .number(Double(v)) }
    public mutating func set(_ key: String, _ v: String) { raw[key] = .string(v) }
    public mutating func set(_ key: String, _ v: Bool) { raw[key] = .bool(v) }
    public mutating func set(_ key: String, _ v: JSONValue) { raw[key] = v }
    public mutating func add(_ key: String, _ delta: Double) { set(key, num(key) + delta) }

    /// Read a list of records stored under `key` (staff, loans ...).
    public func records<R: JSONRecord>(_ key: String, as: R.Type = R.self) -> [R] {
        value(key).array.map { R(raw: $0.object) }
    }
    public mutating func setRecords<R: JSONRecord>(_ key: String, _ list: [R]) {
        raw[key] = .array(list.map { .object($0.raw) })
    }
}
