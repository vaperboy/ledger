import Foundation
import GameCore
import SaveSystem

/// Writes saves on a background queue. Quick repeated saves collapse into the latest state after a short pause.
/// Every method is called from the main thread; only the file writes run elsewhere.
final class SaveWriter {
    private struct Job {
        var generation: Int
        var state: GameState
        var summary: SaveSummary
        var backup: Bool
    }

    private let store: SaveStore
    private let queue = DispatchQueue(label: "ledger.save", qos: .utility)
    private let delay: TimeInterval
    private var latest: Job?
    private var timer: DispatchWorkItem?
    private var generation = 0
    /// Called on the main thread with a short message when a write fails.
    var onFailure: ((String) -> Void)?

    init(store: SaveStore, delay: TimeInterval = 0.5) {
        self.store = store
        self.delay = delay
    }

    func schedule(_ state: GameState, summary: SaveSummary, backup: Bool) {
        generation += 1
        let keepBackup: Bool = backup || (latest?.backup ?? false)
        let job = Job(generation: generation, state: state, summary: summary, backup: keepBackup)
        latest = job
        timer?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.write(job) }
        timer = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Writes anything still waiting and returns once the file is on disk. Call before moving or reading save files.
    func flush() {
        timer?.cancel()
        timer = nil
        guard let job = latest else { queue.sync {}; return }
        latest = nil
        queue.sync { write(job) }
    }

    private func write(_ job: Job) {
        do {
            try store.save(job.state, summary: job.summary)
            if job.backup { try store.backup(job.state, summary: job.summary) }
        } catch {
            DispatchQueue.main.async { [weak self] in self?.onFailure?("Saving failed: \(error)") }
        }
        DispatchQueue.main.async { [weak self] in
            if let self, self.latest?.generation == job.generation { self.latest = nil }
        }
    }
}
