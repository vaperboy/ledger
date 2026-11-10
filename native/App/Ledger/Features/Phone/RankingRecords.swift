import SwiftUI
import GameCore
import Events
import Businesses
import Simulation

struct RankingRecords: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        if let e = store.engine {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                career(e)
                retired(e)
            }
            .accessibilityIdentifier("rankings-records")
        }
    }

    private func career(_ e: GameEngine) -> some View {
        let status: Career.RankStatus = e.careerStatus
        return LedgerSection("Hall of Fame") {
            LedgerRow(leading: .glyph(Glyph.achievements), title: status.rank.title,
                      subtitle: e.inHallOfFame ? "You are in the Hall of Fame" : "Not in the Hall of Fame yet", density: .compact)
        }
    }

    @ViewBuilder private func retired(_ e: GameEngine) -> some View {
        let list: [(name: String, text: String, week: Int)] = Array(e.retirementHall.suffix(3).reversed())
        if !list.isEmpty {
            LedgerSection("Retired from your companies") {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { (i: Int, p: (name: String, text: String, week: Int)) in
                        if i > 0 { Hairline() }
                        LedgerRow(title: p.name, value: GameCalendar.dateString(week: p.week), density: .compact)
                    }
                }
            }
        }
    }
}
