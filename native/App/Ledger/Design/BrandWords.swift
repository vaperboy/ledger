import SwiftUI

enum BrandWords {
    static func label(score: Double) -> String {
        if score < 10 { return "Unknown" }
        if score < 25 { return "Emerging" }
        if score < 40 { return "Known locally" }
        if score < 55 { return "Established" }
        if score < 70 { return "Respected" }
        if score < 85 { return "Trusted" }
        return "Iconic"
    }

    static func level(value: Double, of most: Double) -> String {
        let share: Double = most > 0 ? value / most : 0
        if share < 0.25 { return "Weak" }
        if share < 0.5 { return "Fair" }
        if share < 0.75 { return "Strong" }
        return "Excellent"
    }
}

struct BrandBar: View {
    var score: Double
    var body: some View {
        let frac: CGFloat = CGFloat(min(1, max(0, score / 100)))
        return GeometryReader { (g: GeometryProxy) in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(Theme.gold).frame(width: max(3, g.size.width * frac))
            }
        }
        .frame(width: 54, height: 3)
        .accessibilityHidden(true)
    }
}
