import Foundation

/// A tiny calculator for numbers written in data files, such as an event's cost: `-max(15000, wk * 0.15)`.
/// Supports + - * / ( ), numbers, names (looked up in `variables`), and max(a, b) / min(a, b).
/// Keeping these formulas as text lets event costs be edited without touching code.
public struct Formula: Sendable {
    public let text: String
    private let tokens: [Token]

    enum Token: Equatable, Sendable { case number(Double), name(String), op(Character), comma }

    public init(_ text: String) {
        self.text = text
        var out: [Token] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " { i += 1; continue }
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var j = i
                while j < chars.count, chars[j].isNumber || chars[j] == "." { j += 1 }
                out.append(.number(Double(String(chars[i..<j])) ?? 0)); i = j; continue
            }
            if c.isLetter || c == "_" {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" || chars[j] == "." { j += 1 }
                out.append(.name(String(chars[i..<j]))); i = j; continue
            }
            if c == "," { out.append(.comma) } else { out.append(.op(c)) }
            i += 1
        }
        tokens = out
    }

    public func evaluate(_ variables: [String: Double]) -> Double {
        var pos = 0
        func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }
        func parseSum() -> Double {
            var v = parseProduct()
            while let t = peek(), case .op(let o) = t, o == "+" || o == "-" {
                pos += 1
                let r = parseProduct()
                v = o == "+" ? v + r : v - r
            }
            return v
        }
        func parseProduct() -> Double {
            var v = parseUnary()
            while let t = peek(), case .op(let o) = t, o == "*" || o == "/" {
                pos += 1
                let r = parseUnary()
                v = o == "*" ? v * r : (r == 0 ? 0 : v / r)
            }
            return v
        }
        func parseUnary() -> Double {
            if let t = peek(), case .op(let o) = t, o == "-" || o == "+" {
                pos += 1
                let v = parseUnary()
                return o == "-" ? -v : v
            }
            return parseAtom()
        }
        func parseAtom() -> Double {
            guard let t = peek() else { return 0 }
            pos += 1
            switch t {
            case .number(let n): return n
            case .name(let name):
                if let n = peek(), case .op(let o) = n, o == "(" {
                    pos += 1
                    var args: [Double] = [parseSum()]
                    while let n2 = peek(), n2 == .comma { pos += 1; args.append(parseSum()) }
                    if let n3 = peek(), case .op(let o3) = n3, o3 == ")" { pos += 1 }
                    switch name {
                    case "max": return args.max() ?? 0
                    case "min": return args.min() ?? 0
                    default: return args.first ?? 0
                    }
                }
                return variables[name] ?? 0
            case .op(let o) where o == "(":
                let v = parseSum()
                if let n = peek(), case .op(let c) = n, c == ")" { pos += 1 }
                return v
            default: return 0
            }
        }
        return parseSum()
    }
}
