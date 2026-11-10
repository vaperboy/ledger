import Foundation

public enum GatePurposes {
    public static let table: [String: String] = [
        "hiring": "Hire people to serve more customers than you can alone.",
        "marketing": "Spend on advertising to bring in more customers.",
        "reviews": "See what customers say about you and your rivals, and how it moves your sales.",
        "ownerMoney": "Choose how much of the company's money you pay yourself.",
        "bank": "Keep your money, borrow for growth and save for later.",
        "newCompany": "Start another business so one bad week cannot sink you.",
        "management": "Let a manager run a company day to day while you work on the next one.",
        "accounting": "Keep the books, run payroll and stay on the right side of the tax office.",
        "techpro": "Buy software, equipment and vehicles that make a company work better.",
        "insurance": "Pay a small amount each month so a fire or lawsuit does not cost you everything.",
        "weather": "See the forecast: storms and heat waves change how many customers come.",
        "suppliers": "Choose who sells you stock: cheaper goods leave more profit, better ones keep customers.",
        "marketplace": "Buy used items from private sellers, and haggle for a better price.",
        "property": "Rent or buy the premises a company works from.",
        "rivals": "Watch the competition in your market and learn how you compare.",
        "airstay": "Find offices, shops and storage to rent.",
        "group": "See all your companies together as one group, with the money moving between them.",
        "atlas": "Cover your companies against the risks that could close them.",
        "ventures": "Back start-ups and funds with your spare money for a share of what they earn.",
        "venturesFeed": "Follow the start-ups and funds you could back.",
        "luxury": "Spend your wealth on cars, art, yachts and homes that show how far you have come.",
        "ownerHours": "Your own working hours: the time you give a company each week.",
        "board": "A board of directors can steer a large company and takes decisions off your desk.",
        "research": "Study a market to learn what customers want before you spend on it.",
        "dividends": "Pay profit out of a company to yourself instead of leaving it in the business.",
    ]

    public static func purpose(_ id: String) -> String? { table[id] }
}
