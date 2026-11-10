import Foundation

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

    public func records<R: JSONRecord>(_ key: String, as: R.Type = R.self) -> [R] {
        value(key).array.map { R(raw: $0.object) }
    }
    public mutating func setRecords<R: JSONRecord>(_ key: String, _ list: [R]) {
        raw[key] = .array(list.map { .object($0.raw) })
    }
}
