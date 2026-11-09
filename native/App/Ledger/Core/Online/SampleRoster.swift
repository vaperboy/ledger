import Foundation

/// The made-up players the stand-in server starts with. Everything is derived from the table and the player's name, so the same
/// roster appears on every launch and every device (no randomness).
enum SampleRoster {
    private struct Row {
        var name: String, country: String, level: Int, privacy: PrivacyLevel, computer = false, week: Int
        var fixed: [(name: String, trade: String, city: String)] = []
    }

    private static let rows: [Row] = [
        Row(name: "Ingrid Solheim", country: "NO", level: 14, privacy: .everyone, week: 212),
        Row(name: "Magnus Berg", country: "NO", level: 9, privacy: .friends, week: 140),
        Row(name: "Sofie Lund", country: "NO", level: 21, privacy: .everyone, week: 305),
        Row(name: "Henrik Dahl", country: "NO", level: 5, privacy: .onlyMe, week: 61),
        Row(name: "Kari Nordby", country: "NO", level: 11, privacy: .everyone, computer: true, week: 180),
        Row(name: "Oliver Whitfield", country: "UK", level: 17, privacy: .everyone, week: 250),
        Row(name: "Priya Shah", country: "UK", level: 12, privacy: .friends, week: 166),
        Row(name: "Callum Reid", country: "UK", level: 7, privacy: .everyone, week: 98),
        Row(name: "Eleanor Hughes", country: "UK", level: 23, privacy: .friends, week: 330),
        Row(name: "Tom Ashby", country: "UK", level: 4, privacy: .onlyMe, week: 44),
        Row(name: "Harriet Cole", country: "UK", level: 15, privacy: .everyone, computer: true, week: 201),
        Row(name: "Camille Laurent", country: "FR", level: 13, privacy: .everyone, week: 190),
        Row(name: "Julien Moreau", country: "FR", level: 8, privacy: .friends, week: 120),
        Row(name: "Manon Girard", country: "FR", level: 19, privacy: .everyone, week: 274),
        Row(name: "Hugo Bernard", country: "FR", level: 6, privacy: .onlyMe, week: 77),
        Row(name: "Louise Petit", country: "FR", level: 10, privacy: .everyone, computer: true, week: 150),
        Row(name: "Erik Lindqvist", country: "SE", level: 16, privacy: .everyone, week: 232),
        Row(name: "Astrid Holm", country: "SE", level: 9, privacy: .friends, week: 133),
        Row(name: "Mikkel Jensen", country: "DK", level: 12, privacy: .everyone, week: 171),
        Row(name: "Freja Sørensen", country: "DK", level: 20, privacy: .friends, week: 288),
        Row(name: "Eino Virtanen", country: "FI", level: 7, privacy: .everyone, week: 95),
        Row(name: "Aino Korhonen", country: "FI", level: 14, privacy: .everyone, computer: true, week: 205),
        Row(name: "Lukas Schneider", country: "DE", level: 18, privacy: .everyone, week: 260),
        Row(name: "Anna Fischer", country: "DE", level: 11, privacy: .friends, week: 158),
        Row(name: "Jonas Weber", country: "DE", level: 5, privacy: .onlyMe, week: 58),
        Row(name: "Sanne de Vries", country: "NL", level: 13, privacy: .everyone, week: 184),
        Row(name: "Daan Bakker", country: "NL", level: 8, privacy: .everyone, week: 116),
        Row(name: "Emma Carter", country: "US", level: 22, privacy: .everyone, week: 318),
        Row(name: "Marcus Bell", country: "US", level: 10, privacy: .friends, week: 147),
        Row(name: "Tyler Nguyen", country: "US", level: 6, privacy: .everyone, computer: true, week: 84),
        Row(name: "Chloe Tremblay", country: "CA", level: 15, privacy: .everyone, week: 218),
        Row(name: "Lucia Fernandez", country: "ES", level: 9, privacy: .everyone, week: 128),
        Row(name: "Marco Rossi", country: "IT", level: 12, privacy: .friends, week: 169),
        Row(name: "Kasia Nowak", country: "PL", level: 8, privacy: .everyone, week: 112),
        Row(name: "Aoife Brennan", country: "IE", level: 17, privacy: .everyone, week: 244),
        Row(name: "Haruto Sato", country: "JP", level: 19, privacy: .friends, week: 270),
        Row(name: "Beatriz Almeida", country: "BR", level: 7, privacy: .everyone, week: 101),
        Row(name: "Arjun Mehta", country: "IN", level: 11, privacy: .everyone, computer: true, week: 162),
        Row(name: "Noah Mitchell", country: "AU", level: 14, privacy: .everyone, week: 207),
        Row(name: "Thandi Dlamini", country: "ZA", level: 6, privacy: .onlyMe, week: 70),
        // Five computer players with fixed companies and friends-only profiles, for judging whether they stand out from the others.
        Row(name: "Nora Haugen", country: "NO", level: 13, privacy: .friends, computer: true, week: 196,
            fixed: [("Haugen Bakery", "Bakery and pastry", "Bergen"), ("Haugen Plumbing", "Plumbing firm", "Oslo")]),
        Row(name: "Daniel Brooks", country: "UK", level: 16, privacy: .friends, computer: true, week: 238,
            fixed: [("Brooks & Hale Plumbing", "Plumbing firm", "Manchester"), ("Brooks Physiotherapy", "Physiotherapy clinic", "Bristol")]),
        Row(name: "Lea Hoffmann", country: "DE", level: 10, privacy: .friends, computer: true, week: 149,
            fixed: [("Hoffmann Dental", "Dental clinic", "Hamburg")]),
        Row(name: "Sara Lindgren", country: "SE", level: 12, privacy: .friends, computer: true, week: 177,
            fixed: [("Café Lindgren", "Café", "Gothenburg"), ("Lindgren Cleaning", "Cleaning company", "Malmö")]),
        Row(name: "Pierre Dubois", country: "FR", level: 15, privacy: .friends, computer: true, week: 226,
            fixed: [("Dubois Auto", "Car repair workshop", "Lyon")]),
    ]

    /// The five test players (the last rows), so the stand-in can make them the owner's friends from the start.
    static let testPlayerIDs: [String] = (0..<5).map { String(format: "p%02d", rows.count - 5 + $0 + 1) }

    /// Whether a player is a computer player. Only the stand-in's own behaviour reads this; no screen shows it.
    static func isComputer(_ id: String) -> Bool {
        guard id.hasPrefix("p"), let n = Int(id.dropFirst()), n >= 1, n <= rows.count else { return false }
        return rows[n - 1].computer
    }

    static func countryCode(of id: String) -> String {
        guard id.hasPrefix("p"), let n = Int(id.dropFirst()), n >= 1, n <= rows.count else { return "" }
        return rows[n - 1].country
    }

    private static let cities: [String: [String]] = [
        "NO": ["Oslo", "Bergen", "Trondheim", "Stavanger"], "UK": ["London", "Manchester", "Birmingham", "Bristol"],
        "FR": ["Paris", "Lyon", "Marseille", "Toulouse"], "SE": ["Stockholm", "Gothenburg", "Malmö"], "DK": ["Copenhagen", "Aarhus", "Odense"],
        "FI": ["Helsinki", "Tampere", "Turku"], "DE": ["Berlin", "Hamburg", "Munich", "Cologne"], "NL": ["Amsterdam", "Rotterdam", "Utrecht"],
        "US": ["New York", "Chicago", "Houston", "Denver"], "CA": ["Toronto", "Vancouver", "Calgary"], "ES": ["Madrid", "Barcelona", "Valencia"],
        "IT": ["Rome", "Milan", "Turin"], "PL": ["Warsaw", "Kraków", "Gdańsk"], "IE": ["Dublin", "Cork", "Galway"],
        "JP": ["Tokyo", "Osaka", "Fukuoka"], "BR": ["São Paulo", "Rio de Janeiro", "Curitiba"], "IN": ["Pune", "Jaipur", "Kochi"],
        "AU": ["Sydney", "Melbourne", "Perth"], "ZA": ["Cape Town", "Durban", "Pretoria"],
    ]
    /// Trade names as the game's own trade list writes them, so a player's company can stand as a rival in the same trade.
    private static let trades: [String] = ["Bakery and pastry", "Café", "Dental clinic", "Physiotherapy clinic", "Hair salon", "Plumbing firm", "Gym",
                                           "Restaurant", "Convenience store", "Software and web agency", "Car repair workshop", "Cleaning company",
                                           "Clothing boutique", "Supermarket", "Photography and video", "Pet daycare and grooming"]
    /// How a trade reads inside a company name.
    private static let shortWords: [String: String] = [
        "Bakery and pastry": "Bakery", "Physiotherapy clinic": "Physio", "Hair salon": "Hair Studio", "Convenience store": "Corner Shop",
        "Software and web agency": "Web Studio", "Car repair workshop": "Auto", "Cleaning company": "Cleaning", "Clothing boutique": "Boutique",
        "Photography and video": "Photo", "Pet daycare and grooming": "Pet Care", "Plumbing firm": "Plumbing", "Dental clinic": "Dental",
    ]
    private static let health: [OnlineCompanyHealth] = [.thriving, .growing, .growing, .steady, .steady, .steady, .struggling, .new]
    private static let badges: [String] = ["Early player", "Cash positive", "Debt free", "Hired fifty", "Opened abroad", "Five-star shop", "Season one", "First profit", "Ten years in"]

    /// A repeatable pseudo-random stream from text (FNV-1a, not `hashValue`, which changes between launches).
    struct Stream {
        private var x: UInt64
        init(_ text: String) {
            var h: UInt64 = 0xcbf29ce484222325
            for b in text.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
            x = h == 0 ? 1 : h
        }
        mutating func next(_ n: Int) -> Int {
            x ^= x << 13; x ^= x >> 7; x ^= x << 17
            return Int(x % UInt64(max(n, 1)))
        }
    }

    /// The profile code: six characters without look-alikes, shown as "K7M-4PQ".
    static func code(for id: String) -> String {
        let alphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var s = Stream("code:" + id)
        let chars: [Character] = (0..<6).map { _ in alphabet[s.next(alphabet.count)] }
        return String(chars[0..<3]) + "-" + String(chars[3..<6])
    }

    static func players() -> [PlayerProfile] {
        rows.enumerated().map { (i: Int, row: Row) -> PlayerProfile in
            let id: String = String(format: "p%02d", i + 1)
            var s = Stream(row.name)
            let count: Int = row.fixed.isEmpty ? 1 + s.next(5) : row.fixed.count
            let cityList: [String] = cities[row.country] ?? ["Capital"]
            var usedTrades: Set<String> = []
            var companies: [OnlineCompany] = []
            for k in 0..<count {
                if !row.fixed.isEmpty {
                    let f = row.fixed[k]
                    companies.append(OnlineCompany(id: id + ".c\(k + 1)", name: f.name, trade: f.trade, city: f.city, countryCode: row.country, health: health[s.next(health.count)]))
                    continue
                }
                var trade: String = trades[s.next(trades.count)]
                while usedTrades.contains(trade) { trade = trades[s.next(trades.count)] }
                usedTrades.insert(trade)
                let city: String = cityList[s.next(cityList.count)]
                let family: String = row.name.split(separator: " ").last.map(String.init) ?? row.name
                let word: String = shortWords[trade] ?? trade
                let name: String = [city + " " + word, family + " " + word][s.next(2)]
                companies.append(OnlineCompany(id: id + ".c\(k + 1)", name: name, trade: trade, city: city, countryCode: row.country, health: health[s.next(health.count)]))
            }
            var picked: [String] = []
            for _ in 0..<min(1 + s.next(4), row.level / 3 + 1) { let b = badges[s.next(badges.count)]; if !picked.contains(b) { picked.append(b) } }
            return PlayerProfile(id: id, code: code(for: id), displayName: row.name, avatarColour: s.next(PlayerProfile.avatarColourCount), countryCode: row.country,
                                 level: row.level, badges: picked, privacy: row.privacy, companyCount: companies.count, companies: companies,
                                 gameWeek: row.week, tradesCompleted: row.level * 3 + s.next(12), relation: .none)
        }
    }
}
