import SwiftUI

enum Words {
    enum Scale { case quality, mood, condition }

    static func level(_ value: Double, scale: Scale, of most: Double = 100) -> String {
        let share: Double = most > 0 ? value / most : 0
        switch scale {
        case .quality:
            if share < 0.2 { return "Poor" }
            if share < 0.4 { return "Fair" }
            if share < 0.6 { return "Good" }
            if share < 0.8 { return "Strong" }
            return "Excellent"
        case .mood:
            if share < 0.3 { return "Unhappy" }
            if share < 0.5 { return "Uneasy" }
            if share < 0.75 { return "Content" }
            return "Happy"
        case .condition:
            if share < 0.25 { return "Worn out" }
            if share < 0.5 { return "Tired" }
            if share < 0.8 { return "Fair" }
            return "Good"
        }
    }

    static func move(_ from: Double, _ to: Double, scale: Scale) -> String {
        let a: String = level(from, scale: scale)
        let b: String = level(to, scale: scale)
        return a == b ? b : a + " to " + b
    }
}
