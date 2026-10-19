import Foundation

/// Any JSON value. The game state is stored as JSON values underneath (see `JSONRecord`), which means a save
/// from the original HTML game loads without losing a single field, even for features that are not yet
/// rewritten in Swift: unknown fields are kept and written back untouched.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            // Whole numbers are written without ".0", like the original game's JSON.
            if n.isFinite, n == n.rounded(), abs(n) < 9_007_199_254_740_992 { try c.encode(Int64(n)) }
            else if n.isFinite { try c.encode(n) }
            else { try c.encodeNil() }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // MARK: Convenient reading (lenient, like JavaScript: a missing value is 0 / "" / false)

    public var double: Double {
        switch self {
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return Double(s) ?? 0
        default: return 0
        }
    }
    public var int: Int { Int(double.finiteOrZero) }
    public var string: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return ""
        }
    }
    public var bool: Bool {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        case .null: return false
        }
    }
    public var isNull: Bool { if case .null = self { return true } else { return false } }
    public var array: [JSONValue] { if case .array(let a) = self { return a } else { return [] } }
    public var object: [String: JSONValue] { if case .object(let o) = self { return o } else { return [:] } }

    public subscript(key: String) -> JSONValue {
        get { if case .object(let o) = self { return o[key] ?? .null } else { return .null } }
        set {
            var o = object
            o[key] = newValue
            self = .object(o)
        }
    }
    public subscript(index: Int) -> JSONValue {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return .null
    }

    // MARK: Building

    public init(_ v: Double) { self = .number(v) }
    public init(_ v: Int) { self = .number(Double(v)) }
    public init(_ v: String) { self = .string(v) }
    public init(_ v: Bool) { self = .bool(v) }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(nilLiteral: ()) { self = .null }
}
