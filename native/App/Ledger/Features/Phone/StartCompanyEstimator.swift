import SwiftUI
import GameCore
import Finance
import Simulation

@MainActor final class StartEstimator: ObservableObject {
    @Published private(set) var done: [String: StartEstimate] = [:]
    private var running: [String: Task<StartEstimate?, Never>] = [:]
    private var warmTask: Task<Void, Never>?
    private var warmedKey = ""

    static func key(_ e: GameEngine, _ tradeID: String, _ cityID: String) -> String {
        "\(tradeID)|\(cityID)|\(e.state.week)|\(Int(Payments.liquid(e.state)))"
    }

    func cached(_ e: GameEngine, _ tradeID: String, _ cityID: String) -> StartEstimate? {
        done[Self.key(e, tradeID, cityID)]
    }

    func estimate(_ e: GameEngine, tradeID: String, cityID: String) async -> StartEstimate? {
        let k = Self.key(e, tradeID, cityID)
        if let v = done[k] { return v }
        if let t = running[k] { return await t.value }
        let t = Task<StartEstimate?, Never> {
            guard let facts = e.startFacts(tradeID: tradeID, cityID: cityID) else { return nil }
            let job = e.startJob(facts)
            let runs = await Task.detached(priority: .utility) { job.run() }.value
            let est = StartEstimate(facts: facts, runs: runs)
            self.done[k] = est
            return est
        }
        running[k] = t
        let v = await t.value
        running[k] = nil
        return v
    }

    func warm(_ e: GameEngine, cityID: String) {
        let k = "\(cityID)|\(e.state.week)|\(Int(Payments.liquid(e.state)))"
        if k == warmedKey { return }
        warmedKey = k
        warmTask?.cancel()
        let ids: [String] = e.startableRows(cityID: cityID).filter { $0.isFunded }.map { $0.tradeID }
        warmTask = Task { [weak self] in
            for id in ids {
                if Task.isCancelled { break }
                guard let self else { break }
                _ = await self.estimate(e, tradeID: id, cityID: cityID)
            }
        }
    }
}

enum StartText {
    static func weeks(_ low: Int?, _ high: Int?) -> String {
        guard let low, let high else { return "not reached in the trial runs" }
        return low == high ? "about \(high) weeks" : "\(low) to \(high) weeks"
    }

    static func payback(_ est: StartEstimate) -> String {
        let base = weeks(est.paybackLow, est.paybackHigh)
        return est.someNeverPayBack && est.paybackLow != nil ? base + ", some runs never" : base
    }
}
