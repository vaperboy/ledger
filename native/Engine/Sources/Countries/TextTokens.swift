import Foundation

/// Text in the game's data may contain tokens that depend on the country of the reader:
///  - `{auth:key}`  the name of a public body in that country (tax office, food authority ...)
///  - `{m:amount}`  an amount written at the reference price level, scaled to the country and shown in its currency
/// Original: `locText` (engine/core/text.js). Stored text keeps its tokens; they are resolved when text is shown.
public enum TextTokens {
    public static func resolve(_ text: String, country: Country, currency: Currency) -> String {
        guard text.contains("{") else { return text }
        var out = text
        out = replace(out, pattern: #"\{auth:(\w+)\}"#) { key in
            let name = country.pack["authorities"][key].string
            return name.isEmpty ? key : name
        }
        out = replace(out, pattern: #"\{m:(-?[\d.]+)\}"#) { number in
            currency.format(currency.scaledPrice(Double(number) ?? 0))
        }
        return out
    }

    private static func replace(_ text: String, pattern: String, _ make: (String) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = re.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
        for m in matches {
            guard let whole = Range(m.range, in: result), let key = Range(m.range(at: 1), in: text) else { continue }
            result.replaceSubrange(whole, with: make(String(text[key])))
        }
        return result
    }
}
