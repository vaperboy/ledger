import Foundation

public struct SeasonReward: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case badge, theme, namePlate, backdrop, saveSlot, advisorLine, richListFlair, tradePlate
        case box, gold
        public var isEquippable: Bool { self == .theme || self == .namePlate || self == .backdrop || self == .richListFlair || self == .tradePlate }
        public var label: String {
            switch self {
            case .badge: return "Badge"
            case .theme: return "App theme"
            case .namePlate: return "Name plate"
            case .backdrop: return "Backdrop"
            case .saveSlot: return "Save slot"
            case .advisorLine: return "Advisor line"
            case .richListFlair: return "Rich-list flair"
            case .tradePlate: return "Trade-name plate"
            case .box: return "Box"
            case .gold: return "Gold"
            }
        }
    }
    public var id: String
    public var tier: Int
    public var premium: Bool
    public var kind: Kind
    public var title: String
    public var detail: String
    public var colors: [UInt32] = []
    public var amount: Int = 0
}

public enum SeasonRewards {
    public static let all: [SeasonReward] = free + premium

    public static func reward(_ track: SeasonPass.Track, tier: Int) -> SeasonReward? {
        all.first { $0.tier == tier && $0.premium == (track == .premium) }
    }

    private static func r(_ id: String, _ tier: Int, _ prem: Bool, _ kind: SeasonReward.Kind, _ title: String, _ detail: String, _ colors: [UInt32] = []) -> SeasonReward {
        SeasonReward(id: id, tier: tier, premium: prem, kind: kind, title: title, detail: detail, colors: colors)
    }

    private static func b(_ id: String, _ tier: Int, _ prem: Bool, _ count: Int) -> SeasonReward {
        SeasonReward(id: id, tier: tier, premium: prem, kind: .box, title: count == 1 ? "Season box" : "\(count) Season boxes",
                     detail: "Free to open in the Store; it holds a cosmetic, an artifact, a little gold or, rarely, cash. Odds are shown before you open it.", amount: count)
    }

    private static func g(_ id: String, _ tier: Int, _ prem: Bool, _ gold: Int) -> SeasonReward {
        SeasonReward(id: id, tier: tier, premium: prem, kind: .gold, title: "\(gold) gold",
                     detail: "Gold buys cosmetics, boxes and comfort in the Store. It never buys in-game money.", amount: gold)
    }

    static let free: [SeasonReward] = [
        r("badge.s1.first", 1, false, .badge, "First steps badge", "A small badge for starting the season."),
        r("plate.ledger", 3, false, .namePlate, "Ledger plate", "A plain name plate with a champagne rule.", [0xD6B889, 0x2A2A2C]),
        r("advisor.steady", 5, false, .advisorLine, "Advisor: steady hands", "\"Small sums, kept carefully, add up before you notice.\""),
        r("badge.s1.bronze", 7, false, .badge, "Bronze badge", "Awarded for reaching tier 7."),
        r("backdrop.slate", 9, false, .backdrop, "Slate backdrop", "A calm grey-blue backdrop.", [0x2C3644, 0x1E2530]),
        r("badge.s1.cash", 11, false, .badge, "Cash keeper badge", "For a season of steady play."),
        r("plate.brass", 13, false, .namePlate, "Brass plate", "A name plate in warm brass.", [0xB89B6A, 0x3A3022]),
        r("advisor.ledger", 15, false, .advisorLine, "Advisor: trust the books", "\"What is written down can be fixed. What is guessed cannot.\""),
        r("theme.dusk", 17, false, .theme, "Dusk theme", "A violet tint on the usual palette.", [0xA79BD6, 0x2A2640]),
        r("badge.s1.silver", 19, false, .badge, "Silver badge", "Awarded for reaching tier 19."),
        r("trade.plain", 21, false, .tradePlate, "Plain trade plate", "A clean plate for your trade names.", [0xD6B889, 0x2A2A2C]),
        r("backdrop.sand", 23, false, .backdrop, "Sand backdrop", "A warm sand backdrop.", [0x54452F, 0x3A3126]),
        r("badge.s1.steady", 25, false, .badge, "Steady badge", "For a season played week by week."),
        r("flair.pin", 27, false, .richListFlair, "Rich-list pin", "A small champagne pin beside your name on the rich list.", [0xD6B889]),
        r("badge.s1.gold", 29, false, .badge, "Gold badge", "Awarded for reaching tier 29."),
        r("badge.s1.complete", 30, false, .badge, "Season 1 finisher", "Every tier reached in season 1."),
        b("box.f4", 4, false, 1), g("gold.f8", 8, false, 10), b("box.f10", 10, false, 1), g("gold.f14", 14, false, 15),
        b("box.f16", 16, false, 1), g("gold.f22", 22, false, 20), b("box.f26", 26, false, 1)
    ]

    static let premium: [SeasonReward] = [
        r("theme.moss", 1, true, .theme, "Moss theme", "A green tint on the usual palette.", [0x8FBF9F, 0x1F2E26]),
        r("plate.walnut", 2, true, .namePlate, "Walnut plate", "A dark walnut name plate.", [0x7A5A3C, 0x3B2A1C]),
        r("advisor.patience", 3, true, .advisorLine, "Advisor: patience pays", "\"Most good deals are made by the one who can wait a week.\""),
        r("backdrop.dawn", 5, true, .backdrop, "Dawn backdrop", "A soft rose to amber backdrop.", [0x5A3F34, 0x3B2A33]),
        r("badge.s1.plus", 6, true, .badge, "Plus season badge", "A badge for Ledger Plus players."),
        r("trade.engraved", 9, true, .tradePlate, "Engraved trade plate", "An engraved plate for your trade names.", [0xD6B889, 0x4A3F2C]),
        r("theme.rose", 12, true, .theme, "Rose theme", "A rose tint on the usual palette.", [0xD99AA6, 0x35242A]),
        r("flair.crest", 15, true, .richListFlair, "Rich-list crest", "A fine crest beside your name on the rich list.", [0xE0BC5E, 0x7A5A1C]),
        r("advisor.horizon", 18, true, .advisorLine, "Advisor: look further", "\"The number on the screen is this week. Your plan is the next ten years.\""),
        r("slot.extra", 20, true, .saveSlot, "One extra save slot", "Room for one more saved game."),
        r("backdrop.harbour", 21, true, .backdrop, "Harbour backdrop", "A deep teal backdrop.", [0x2C4A4A, 0x1C3032]),
        r("plate.marble", 24, true, .namePlate, "Marble plate", "A pale marble name plate.", [0xE4DFD3, 0x4A4842]),
        r("theme.ocean", 27, true, .theme, "Ocean theme", "A blue tint on the usual palette.", [0x7FAAD6, 0x1D2A3B]),
        r("trade.gilded", 28, true, .tradePlate, "Gilded trade plate", "A gilded plate for your trade names.", [0xE0BC5E, 0x7A5A1C]),
        r("badge.s1.crown", 30, true, .badge, "Season 1 crown", "The premium finisher badge of season 1."),
        b("box.p4", 4, true, 1), g("gold.p7", 7, true, 20), b("box.p10", 10, true, 2), g("gold.p13", 13, true, 30),
        b("box.p16", 16, true, 2), g("gold.p19", 19, true, 40), b("box.p25", 25, true, 2), g("gold.p29", 29, true, 50)
    ]
}
