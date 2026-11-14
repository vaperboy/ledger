import SwiftUI

struct ChartKey: View {
    var items: [(String, Color)]
    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(spacing: Theme.Space.xs) {
                    Capsule().fill(it.1).frame(width: 10, height: 2)
                    Text(it.0).textStyle(.caption, tint: Theme.inkFaint)
                }
            }
        }
    }
}
