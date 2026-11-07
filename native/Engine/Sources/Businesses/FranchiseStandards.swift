import Foundation
import GameCore

/// What a franchise brand dictates to its franchisees about how they sell and how they may market locally. The rules come from
/// `Resources/franchise_brands.json` (authored by brand tier and trade); the choices are written into the franchise agreement
/// (`franchise.knobStd`, `franchise.localMkt`) when the franchise is granted, so they stay what was agreed. Without those keys
/// (an old save, an independent) nothing is fixed.
public enum FranchiseStandards {
    struct Table {
        var knobs: [String: [(knob: String, fromTier: Int)]] = [:]
        var channels: [Int: [String]] = [:]    // a tier absent here leaves every channel open
        var requiredShare: [Int: Double] = [:]
    }

    static let table: Table = {
        var t = Table()
        guard let url = Bundle.module.url(forResource: "franchise_brands", withExtension: "json", subdirectory: "Resources"),
              let raw = try? Data(contentsOf: url), let j = try? JSONDecoder().decode(JSONValue.self, from: raw) else { return t }
        for (trade, list) in j["knobStandards"].object { t.knobs[trade] = list.array.map { (knob: $0["knob"].string, fromTier: $0["fromTier"].int) } }
        for (tier, v) in j["localMkt"].object {
            guard let n = Int(tier) else { continue }
            if v["channels"].string != "all" { t.channels[n] = v["channels"].array.map { $0.string } }
            t.requiredShare[n] = v["requiredShare"].double
        }
        return t
    }()

    /// The choices this brand fixes for a unit of `trade`: knob id to option index. The option is the brand's own, picked from its
    /// identity (the same brand always dictates the same format) among the options that need no licence.
    static func knobStandards(brand b: FranchiseBrands.Brand, trade: Trade) -> [String: Int] {
        var out: [String: Int] = [:]
        for rule in table.knobs[trade.id] ?? [] where b.tier >= rule.fromTier {
            guard let k = trade.knobs.first(where: { $0.id == rule.knob && !$0.isMulti }) else { continue }
            let ok = k.options.indices.filter { k.options[$0].requiredDocs.isEmpty }
            guard !ok.isEmpty else { continue }
            var r = FranchiseBrands.BrandRandom("fbstd:\(b.id):\(rule.knob)")
            out[rule.knob] = ok[Int(r.next() * Double(ok.count)) % ok.count]
        }
        return out
    }

    /// The local marketing record for the agreement, or nil when the brand leaves local marketing entirely free.
    static func localMarketing(brand b: FranchiseBrands.Brand) -> JSONValue? {
        let share = table.requiredShare[b.tier] ?? 0
        let channels = table.channels[b.tier]
        guard channels != nil || share > 0 else { return nil }
        var o: [String: JSONValue] = [:]
        if let c = channels { o["ch"] = .array(c.map { .string($0) }) }
        if share > 0 { o["req"] = .number(share) }
        return .object(o)
    }

    /// Why this franchisee may not run a local campaign on `channel`, or nil when it may.
    public static func campaignRefusal(_ co: Company, channel: String) -> String? {
        let f = co.value("franchise")
        guard f["fran"].bool, !f["localMkt"]["ch"].isNull else { return nil }
        let allowed = f["localMkt"]["ch"].array.map { $0.string }
        guard !allowed.contains(channel) else { return nil }
        let brand = f["brandName"].isNull ? "the franchisor" : f["brandName"].string
        return allowed.isEmpty ? "your franchise agreement with \(brand) reserves local marketing to the brand" : "your franchise agreement with \(brand) does not allow local campaigns on this channel"
    }

    /// Share of sales the agreement obliges the franchisee to spend on local marketing (0 = none).
    public static func requiredShare(_ co: Company) -> Double {
        let f = co.value("franchise")
        return f["fran"].bool ? f["localMkt"]["req"].double : 0
    }
}
