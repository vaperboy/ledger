import SwiftUI
import Simulation

@MainActor
final class UsernameChecker: ObservableObject {
    enum Verdict: Equatable {
        case idle, unchanged, bad(String), checking, free, taken, localOnly
    }

    @Published private(set) var verdict: Verdict = .idle
    private var task: Task<Void, Never>?

    var canUse: Bool { verdict == .free || verdict == .localOnly }

    var line: (text: String, good: Bool)? {
        switch verdict {
        case .idle, .unchanged: return nil
        case .bad(let why): return (why, false)
        case .checking: return ("Checking the name", true)
        case .free: return ("Available", true)
        case .taken: return ("Already taken", false)
        case .localOnly: return ("Saved on this device. It is checked when you go online.", true)
        }
    }

    func check(_ raw: String, current: String, online: OnlineSession) {
        task?.cancel()
        let name: String = ProfileRules.clean(raw)
        if name.isEmpty { verdict = .idle; return }
        if name == current { verdict = .unchanged; return }
        if let why = ProfileRules.problem(with: name) { verdict = .bad(why); return }
        guard online.isSignedIn else { verdict = .localOnly; return }
        verdict = .checking
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let result: UsernameResult? = await online.usernameAvailable(name)
            if Task.isCancelled { return }
            switch result {
            case .ok?: verdict = .free
            case .taken?: verdict = .taken
            case .invalid?: verdict = .bad("That name is not allowed.")
            case nil: verdict = .localOnly
            }
        }
    }

    func reset() { task?.cancel(); verdict = .idle }
}

struct UsernameStatusLine: View {
    @ObservedObject var checker: UsernameChecker
    var goodTint: Color = Theme.gain
    var badTint: Color = Theme.loss

    var body: some View {
        if let l = checker.line {
            Text(l.text).textStyle(.caption, tint: l.good ? goodTint : badTint)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("username-status")
        }
    }
}

enum UsernameCost {
    static var change: Int { GoldPrices.service("usernameChange") }
}
