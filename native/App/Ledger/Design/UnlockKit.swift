import SwiftUI
import GameCore
import Businesses
import Simulation

// Progressive unlocks in the app (engine: Businesses/Unlocks.swift): the announcement popup, the queue the store
// holds, and the locked block a screen shows in place of a feature that is not open yet (dimmed, a lock, one line saying what opens it).

/// One announcement waiting to be shown (the engine's items are not Identifiable, so this wraps one).
struct UnlockPrompt: Identifiable, Equatable {
    var id: String
    var companyID: Int
    var featureID: String
    var title: String
    var line: String
    var target: String
}

extension GameStore {
    /// One registry item of one company, nil when the game has no such company.
    func unlock(_ id: String, companyID: Int) -> UnlockItem? { engine?.unlockItem(id, companyID: companyID) }

    /// True when the feature is open (or unknown: a missing item never hides anything).
    func isUnlocked(_ id: String, companyID: Int) -> Bool { unlock(id, companyID: companyID)?.unlocked ?? true }

    /// Takes what the weekly sweep announced and has not been shown yet into the queue.
    func queueUnlocks() {
        guard let e = engine else { return }
        for u in e.pendingUnlocks() {
            let pid: String = "\(u.companyID):\(u.id)"
            if unlockQueue.contains(where: { (p: UnlockPrompt) -> Bool in p.id == pid }) { continue }
            let name: String = e.state.company(u.companyID)?.name ?? "This company"
            unlockQueue.append(UnlockPrompt(id: pid, companyID: u.companyID, featureID: u.id, title: u.title, line: Self.unlockLine(u.id, name), target: u.target))
        }
    }

    private static func unlockLine(_ id: String, _ name: String) -> String {
        switch id {
        case "board": return "Someone could now take a seat on the board of \(name)."
        case "chain": return "\(name) has traded long enough to be turned into a chain."
        case "franchise": return "\(name) has a proven concept: others can now open units under its name."
        case "abroad": return "A profitable year makes a subsidiary abroad possible for \(name)."
        case "research": return "\(name) is old enough for its market to be researched."
        case "dividends": return "\(name) has retained profit it can pay out."
        default: return "\(name) can now use this."
        }
    }

    /// The announcement to show now: the first in the queue, once the day's reports, rewards and notices have been read.
    var unlockReady: UnlockPrompt? {
        guard !isAdvancing, reportSheet == nil, dailySheet == nil, !ambitionPrompt, celebrationQueue.isEmpty, !popupOpen else { return nil }
        return unlockQueue.first
    }

    /// The announcement has been seen (Skip, or the close button): it is marked shown and the next one may follow.
    func dismissUnlock(_ p: UnlockPrompt) {
        let cid: Int = p.companyID
        let fid: String = p.featureID
        act { (e: inout GameEngine) -> Bool in e.markUnlockShown(id: fid, companyID: cid); return true }
        unlockQueue.removeAll(where: { (x: UnlockPrompt) -> Bool in x.id == p.id })
    }

    /// "Take me there": the announcement is closed and the exact page opens.
    func goToUnlock(_ p: UnlockPrompt) {
        dismissUnlock(p)
        openUnlockTarget(p.target, companyID: p.companyID)
    }

    /// Opens where a feature lives: a Group entity section, or the company's market.
    func openUnlockTarget(_ target: String, companyID: Int) {
        switch target {
        case "research": openMarket(companyID: companyID)
        case "marketplace": openMarket(companyID: companyID)
        default: openGroupEntity(companyID: companyID, section: target)
        }
    }
}

/// The centred announcement: a gold ring that scales in with a soft glow, "<Feature> unlocked!", why, and two buttons (Take me there is the
/// highlighted one, Skip is quiet). Locked: a tap outside does not close it. One light haptic, none of the motion under Reduce Motion.
struct UnlockPopup: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var prompt: UnlockPrompt
    @State private var shown = false

    var body: some View {
        VStack(spacing: PopupSpace.block) {
            ring
            Text("\(prompt.title) unlocked")
                .popupText(.figure, variant: .reward).multilineTextAlignment(.center)
                .opacity(shown || reduceMotion ? 1 : 0)
                .scaleEffect(shown || reduceMotion ? 1 : 0.9)
            Text(prompt.line)
                .popupText(.subtitle).multilineTextAlignment(.center)
            VStack(spacing: 6) {
                Button { Haptics.tap(); store.goToUnlock(prompt) } label: {
                    Text("Take me there").frame(maxWidth: .infinity)
                }
                .buttonStyle(ImportantButtonStyle()).accessibilityIdentifier("unlock-go")
                Button { store.dismissUnlock(prompt) } label: {
                    Text("Skip").popupText(.rowLabel).frame(maxWidth: .infinity, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle()).accessibilityIdentifier("unlock-skip")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .centerSheetTitle(prompt.title)
        .centerSheetLocked()
        .onAppear {
            Haptics.tap()
            Motion.animate(Motion.moveAnimation) { shown = true }
        }
    }

    private var ring: some View {
        let on: Bool = shown || reduceMotion
        return ZStack {
            Circle().fill(Theme.gold.opacity(on ? 0.10 : 0))
            Circle().strokeBorder(Theme.gold, lineWidth: 3)
            GlyphView(glyph: Glyph.achievements, size: 30, weight: 1.6, tint: Theme.gold)
        }
        .frame(width: 84, height: 84)
        .shadow(color: Theme.gold.opacity(on ? 0.45 : 0), radius: 16)
        .scaleEffect(on ? 1 : 0.8)
        .accessibilityHidden(true)
    }
}

/// What a screen shows in place of a feature that is not open yet: a lock, the feature's name and one line that says what opens it, dimmed.
/// With a progress fraction a thin line shows how far along it is.
struct LockedBlock: View {
    var title: String
    var reason: String
    var progress: Double? = nil

    var body: some View {
        Card(padding: 12, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    GlyphView(glyph: Glyph.lock, size: 15, weight: 1.6, tint: Theme.ivoryFaint).frame(width: 20)
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ivoryMuted).lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(reason).font(.system(size: 12.5)).foregroundStyle(Theme.ivoryFaint).fixedSize(horizontal: false, vertical: true)
                if let progress { ThinProgress(fraction: progress, tint: Theme.gold) }
            }
        }
        .opacity(0.78)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), locked. \(reason)")
    }
}

/// A thin progress line (no label, no number): used where "how far" is shown as a shape, not a figure.
struct ThinProgress: View {
    var fraction: Double
    var tint: Color = Theme.gold

    var body: some View {
        GeometryReader { (g: GeometryProxy) in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(tint).frame(width: max(3, g.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 3)
    }
}
