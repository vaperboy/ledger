import SwiftUI

/// One slim line per person: photo, name, role, pay and a single status mark.
struct SlimWorkerRow: View {
    @Environment(\.outsidePalette) private var P
    var name: String
    var role: String
    var wage: String
    var face: String?
    var roleKey: String
    var mood: String?
    var attention: Bool
    var onNotice: Bool

    private var mark: (text: String, tint: Color)? {
        if onNotice { return ("Leaving", P.loss) }
        if attention { return ("Needs you", P.caution) }
        switch mood ?? "" {
        case "Leaving": return ("Leaving", P.loss)
        case "Unhappy": return ("Unhappy", P.caution)
        case "Happy": return ("Happy", P.gain)
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ThumbnailView(kind: .person, key: roleKey, size: ThinPersonRow.portrait, initials: name, face: face)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(name.tidyText).textStyle(.headline).lineLimit(1)
                Text(role.tidyText).textStyle(.caption, tint: P.inkSoft).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.s)
            if let mark { StatusDot(text: mark.text, tint: mark.tint) }
            Text(wage).textStyle(.headline, numeric: true).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A small coloured dot with a word, so status is never colour alone.
struct StatusDot: View {
    var text: String
    var tint: Color

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(text).textStyle(.caption, tint: tint, weight: .medium).lineLimit(1)
        }
    }
}
