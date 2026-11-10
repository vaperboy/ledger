import Foundation

enum RuleGroup: String, Codable, CaseIterable, Sendable {
    case printing, taxes, bands, electricity, funding

    var title: String {
        switch self {
        case .printing: return "Printing money"
        case .taxes: return "Tax changes"
        case .bands: return "Price bands"
        case .electricity: return "Electricity price"
        case .funding: return "Price support funding"
        }
    }
    var blurb: String {
        switch self {
        case .printing: return "How much a government may print, and how fast."
        case .taxes: return "How far and how often a president may move the transfer and gains tax."
        case .bands: return "How far from its value a shared deal may be priced."
        case .electricity: return "The range the world electricity price index stays inside."
        case .funding: return "How the treasury may fund price support for a trade, electricity included."
        }
    }
    var glyph: String {
        switch self {
        case .printing: return Glyph.invest
        case .taxes: return Glyph.reports
        case .bands: return Glyph.market
        case .electricity: return Glyph.world
        case .funding: return Glyph.bank
        }
    }
}

enum RuleUnit: String, Codable, Sendable { case share, weeks, count, factor }

struct WorldRule: Codable, Identifiable, Hashable, Sendable {
    var key: String
    var group: RuleGroup
    var label: String
    var unit: RuleUnit
    var value: Double
    var defaultValue: Double
    var minimum: Double
    var maximum: Double
    var id: String { key }
    enum CodingKeys: String, CodingKey { case key, group, label, unit, value, defaultValue = "default", minimum = "min", maximum = "max" }

    var isDefault: Bool { abs(value - defaultValue) < 1e-9 }

    var step: Double {
        switch unit {
        case .share: return maximum <= 0.12 ? 0.005 : 0.01
        case .weeks, .count: return 1
        case .factor: return 0.05
        }
    }

    func text(_ v: Double) -> String {
        switch unit {
        case .share: return String(format: v < 0.1 ? "%.1f%%" : "%.0f%%", v * 100)
        case .weeks: return Int(v.rounded()) == 1 ? "1 week" : "\(Int(v.rounded())) weeks"
        case .count: return "\(Int(v.rounded()))"
        case .factor: return String(format: "%.2f\u{00D7}", v)
        }
    }
    var valueText: String { text(value) }
    var rangeText: String { text(minimum) + " to " + text(maximum) }
}

enum ConfirmationKind: String, Codable, Sendable {
    case policy, priceSupport = "price_support", promises, electionResult = "election_result"

    var title: String {
        switch self {
        case .policy: return "Tax change"
        case .priceSupport: return "Price support"
        case .promises: return "Campaign promises"
        case .electionResult: return "Election result"
        }
    }
    var onConfirm: String {
        switch self {
        case .policy: return "the new tax rates take effect in that country."
        case .priceSupport: return "the support is recorded as approved."
        case .promises: return "the promises are recorded as approved."
        case .electionResult: return "the winner takes the presidency for a twelve-week term."
        }
    }
    var onReject: String {
        switch self {
        case .policy: return "the rates stay as they are and the president can propose again."
        case .priceSupport: return "no support is paid."
        case .promises: return "the promises are dropped."
        case .electionResult: return "the office stays vacant and a new election opens in due course."
        }
    }
}

struct PendingConfirmation: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var kind: ConfirmationKind
    var country: String
    var proposer: String
    var summary: String
    var at: Date
}

struct AuditEntry: Codable, Identifiable, Hashable, Sendable {
    var id: Int
    var at: Date
    var actor: String
    var action: String
    var target: String
    var before: String?
    var after: String?
    var reason: String

    var title: String {
        switch action {
        case "rule_change": return "Rule changed"
        case "confirm": return "Change confirmed"
        case "reject": return "Change rejected"
        case "admin_granted": return "Administrator added"
        default: return action.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct AdminSnapshot: Codable, Sendable {
    var rules: [WorldRule]
    var confirmations: [PendingConfirmation]
    var audit: [AuditEntry]
}

enum AdminCodeResult: Equatable, Sendable { case granted, alreadyAdmin, invalid, locked }

protocol AdminService: Sendable {
    func redeemAdminCode(_ code: String) async throws -> AdminCodeResult
    func adminSnapshot() async throws -> AdminSnapshot
    func adminSetRule(key: String, value: Double, reason: String) async throws
    func adminDecide(id: String, approve: Bool, reason: String) async throws
    func adminAudit(before: Int?, limit: Int) async throws -> [AuditEntry]
    func adminRemoveFakePlayers(reason: String) async throws
}
