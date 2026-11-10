import Foundation
import Businesses
import Simulation

protocol LeaderboardService: Sendable {
    func publish(_ mine: LeaderboardSubmission) async
    func submissions() async -> [LeaderboardSubmission]
}

struct OfflineLeaderboardService: LeaderboardService {
    func publish(_ mine: LeaderboardSubmission) async {}
    func submissions() async -> [LeaderboardSubmission] { [] }
}

enum LeaderboardBackend {
    static func make() -> any LeaderboardService { online() }
}

enum BoardRivals {
    static let target = 60

    private static let first: [String] = [
        "Ingrid", "Magnus", "Sofie", "Henrik", "Kari", "Oliver", "Priya", "Callum", "Eleanor", "Harriet", "Camille", "Julien", "Manon", "Hugo", "Louise",
        "Erik", "Astrid", "Mikkel", "Freja", "Eino", "Aino", "Lukas", "Anna", "Jonas", "Sanne", "Daan", "Emma", "Marcus", "Tyler", "Chloe", "Lucia",
        "Marco", "Kasia", "Aoife", "Haruto", "Beatriz", "Arjun", "Noah", "Thandi", "Rasa", "Tomas", "Egle", "Mantas", "Ugne", "Linas", "Greta",
        "Sindre", "Marit", "Jakob", "Nora", "Felix", "Ida", "Isak", "Maja", "Ola", "Silje", "Matteo", "Elena", "Pablo", "Carmen",
    ]
    private static let last: [String] = [
        "Solheim", "Berg", "Lund", "Dahl", "Nordby", "Whitfield", "Shah", "Reid", "Hughes", "Cole", "Laurent", "Moreau", "Girard", "Bernard", "Petit",
        "Lindqvist", "Holm", "Jensen", "Sorensen", "Virtanen", "Korhonen", "Schneider", "Fischer", "Weber", "de Vries", "Bakker", "Carter", "Bell",
        "Nguyen", "Tremblay", "Fernandez", "Rossi", "Nowak", "Brennan", "Sato", "Almeida", "Mehta", "Mitchell", "Dlamini", "Kazlauskas", "Petrauskas",
        "Jankauskas", "Vaitkus", "Stankevicius", "Haugen", "Eriksen", "Halvorsen", "Johansen", "Moen", "Strand", "Bakke", "Aas", "Ruud", "Hagen",
        "Ferrari", "Conti", "Navarro", "Ortega", "Santos",
    ]

    static func fill(template: LeaderboardSubmission, real: [LeaderboardSubmission], scale: Double, week: Int, seed: Int, taken: Set<String>) -> [LeaderboardSubmission] {
        let need: Int = max(0, target - real.count)
        if need == 0 { return [] }
        var stream = SampleRoster.Stream("board:\(seed)")
        var used: Set<String> = taken
        for r in real { used.insert(r.name) }
        var out: [LeaderboardSubmission] = []
        var i = 0
        while out.count < need && i < need * 4 {
            defer { i += 1 }
            let name: String = first[stream.next(first.count)] + " " + last[stream.next(last.count)]
            if used.contains(name) { continue }
            used.insert(name)
            let k: Int = out.count
            let u: Double = (Double(k) + 0.5) / Double(need)
            let base: Double = max(1, scale) * (0.12 + 5.5 * pow(1 - u, 2.4))
            var own = SampleRoster.Stream("board:\(seed):\(name)")
            let drift: Double = 1 + Double(min(week, 1_040)) * 0.0035
            let wobble: Double = 0.9 + Double(own.next(200)) / 1000
            let worth: Double = (base * drift * wobble).rounded()
            let tradingShare: Double = (Double(own.next(1000)) / 1000 - 0.28) * 0.22
            var rival: LeaderboardSubmission = template
            rival.playerID = "rival-\(name)"
            rival.name = name
            rival.week = week
            rival.netWorth = worth
            rival.tradingResult = (worth * tradingShare).rounded()
            out.append(rival)
        }
        return out
    }
}
