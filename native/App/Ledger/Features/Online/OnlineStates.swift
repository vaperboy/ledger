import SwiftUI

/// Short player wording for online problems, so system error text never reaches the screen.
enum OnlineWords {
    static let loadFailed = "Could not load this. Check your connection and try again."

    static func friendly(_ error: Error) -> String {
        if let e = error as? OnlineError, let text = e.errorDescription { return text }
        if error is URLError { return "Could not reach the server. Check your connection and try again." }
        return "That did not go through. Please try again."
    }
}

/// A spinner with one short line, for an online list that is still loading.
struct OnlineLoading: View {
    var text: String = "Loading"

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ProgressView()
            Text(text).textStyle(.body, tint: Theme.inkSoft)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Theme.Space.xl)
        .accessibilityElement(children: .combine)
    }
}

/// The loading, empty and failed states of an online list in one place. A failed load keeps a Try again button.
struct OnlineListState: View {
    enum Phase: Equatable { case loading, empty(String), failed(String) }
    var phase: Phase
    var retry: () -> Void = {}

    var body: some View {
        switch phase {
        case .loading:
            OnlineLoading()
        case .empty(let text):
            EmptyState(glyph: Glyph.info, title: text)
        case .failed(let text):
            EmptyState(glyph: Glyph.cloud, title: text, actionTitle: "Try again", action: retry)
        }
    }
}

/// A spinner that turns into a Try again prompt when nothing has arrived after a while.
struct OnlineWaiting: View {
    var seconds: Double = 12
    var retry: () -> Void
    @State private var late = false

    var body: some View {
        Group {
            if late {
                OnlineListState(phase: .failed(OnlineWords.loadFailed)) { late = false; retry() }
            } else {
                OnlineLoading()
            }
        }
        .task(id: late) {
            guard !late else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled { late = true }
        }
    }
}
