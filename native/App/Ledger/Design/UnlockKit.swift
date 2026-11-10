import SwiftUI
import GameCore
import Businesses
import Simulation

struct UnlockPrompt: Identifiable, Equatable {
    var id: String
    var companyID: Int
    var featureID: String
    var title: String
    var line: String
    var target: String
}

extension GameStore {
    func unlock(_ id: String, companyID: Int) -> UnlockItem? { engine?.unlockItem(id, companyID: companyID) }

    func isUnlocked(_ id: String, companyID: Int) -> Bool { unlock(id, companyID: companyID)?.unlocked ?? true }

    func queueUnlocks() {
        guard let e = engine else { return }
        for u in e.pendingUnlocks() {
            let pid: String = u.id
            if unlockQueue.contains(where: { (p: UnlockPrompt) -> Bool in p.id == pid }) { continue }
            let name: String = e.state.company(u.companyID)?.name ?? "This company"
            unlockQueue.append(UnlockPrompt(id: pid, companyID: u.companyID, featureID: u.id, title: u.title, line: Self.unlockLine(u.id, name), target: u.target))
        }
    }

    func queueNotices() {
        guard let e = engine else { return }
        for n in e.pendingNotices() where !unlockQueue.contains(where: { (p: UnlockPrompt) -> Bool in p.id == n.id }) {
            unlockQueue.append(UnlockPrompt(id: n.id, companyID: 0, featureID: n.id, title: n.title, line: n.line, target: hasNoticeTarget(n.target) ? n.target : ""))
        }
    }

    private func noticeApp(_ target: String) -> PhoneApp? {
        PhoneApp.launcher.first(where: { (a: PhoneApp) -> Bool in a.gate?.rawValue == target })
    }

    private func hasNoticeTarget(_ target: String) -> Bool {
        noticeApp(target) != nil || ["government", "politics", "chain", "franchise", "abroad"].contains(target)
    }

    private func openNoticeTarget(_ target: String) {
        if let app = noticeApp(target) { openApp(app); return }
        switch target {
        case "government", "politics": openApp(.world)
        default:
            guard let id = engine?.state.companies.first(where: { (c: Company) -> Bool in c.status.isLive && c.type != "hold" })?.id else { return }
            openGroupEntity(companyID: id, section: "expansion")
        }
    }

    private static func unlockLine(_ id: String, _ name: String) -> String {
        switch id {
        case "board": return "Someone could now take a seat on the board of \(name)."
        case "research": return "\(name) is old enough for its market to be researched."
        case "dividends": return "\(name) has retained profit it can pay out."
        default: return "\(name) can now use this."
        }
    }

    var unlockReady: UnlockPrompt? {
        guard !isAdvancing, reportSheet == nil, dailySheet == nil, celebrationQueue.isEmpty, !popupOpen else { return nil }
        return unlockQueue.first
    }

    func dismissUnlock(_ p: UnlockPrompt) {
        let cid: Int = p.companyID
        let fid: String = p.featureID
        if cid == 0 {
            act { (e: inout GameEngine) -> Bool in e.markNoticeSeen(id: fid); return true }
        } else {
            act { (e: inout GameEngine) -> Bool in e.markUnlockShown(id: fid, companyID: cid); return true }
        }
        unlockQueue.removeAll(where: { (x: UnlockPrompt) -> Bool in x.id == p.id })
    }

    func goToUnlock(_ p: UnlockPrompt) {
        dismissUnlock(p)
        if p.companyID == 0 { openNoticeTarget(p.target) } else { openUnlockTarget(p.target, companyID: p.companyID) }
    }

    func openUnlockTarget(_ target: String, companyID: Int) {
        switch target {
        case "research": openMarket(companyID: companyID)
        case "marketplace": openMarket(companyID: companyID)
        default: openGroupEntity(companyID: companyID, section: target)
        }
    }
}

struct UnlockPopup: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var prompt: UnlockPrompt
    @State private var shown = false

    var body: some View {
        VStack(spacing: PopupSpace.block) {
            ring.confettiBurst()
            Text("\(prompt.title) unlocked")
                .popupText(.figure, variant: .reward).multilineTextAlignment(.center)
                .opacity(shown || reduceMotion ? 1 : 0)
                .scaleEffect(shown || reduceMotion ? 1 : 0.9)
            Text(prompt.line)
                .popupText(.subtitle).multilineTextAlignment(.center)
            if let purpose = GatePurposes.purpose(prompt.featureID) {
                Text(purpose).textStyle(.caption, tint: Theme.inkSoft).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 6) {
                if prompt.target.isEmpty {
                    Button { Haptics.tap(); store.dismissUnlock(prompt) } label: {
                        Text("Got it").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true)).accessibilityIdentifier("unlock-skip")
                } else {
                    Button { Haptics.tap(); store.goToUnlock(prompt) } label: {
                        Text("Take me there").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true)).accessibilityIdentifier("unlock-go")
                    Button { store.dismissUnlock(prompt) } label: { Text("Skip") }
                        .buttonStyle(PlainTextButtonStyle()).accessibilityIdentifier("unlock-skip")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .centerSheetTitle(prompt.title)
        .centerSheetLocked()
        .onAppear {
            Motion.animate(Motion.moveAnimation) { shown = true }
            SoundCues.play(.unlock)
        }
    }

    private var ring: some View {
        let on: Bool = shown || reduceMotion
        return ZStack {
            Circle().fill(Theme.accentWash.opacity(on ? 1 : 0))
            LedgerGlyph(glyph: Glyph.achievements, size: Theme.Icon.large, tint: Theme.accent)
        }
        .frame(width: 84, height: 84)
        .scaleEffect(on ? 1 : 0.8)
        .accessibilityHidden(true)
    }
}

struct LockedBlock: View {
    var title: String
    var reason: String
    var progress: Double? = nil

    var body: some View {
        Card(padding: 12, radius: Theme.Radius.card) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.s) {
                    LedgerGlyph(glyph: Glyph.lock, size: Theme.Icon.small, tint: Theme.inkFaint).frame(width: 20)
                    Text(title).textStyle(.headline, tint: Theme.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                Text(reason).textStyle(.caption, tint: Theme.inkFaint).fixedSize(horizontal: false, vertical: true)
                if let progress { ProgressLine(fraction: progress) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), locked. \(reason)")
    }
}

struct ThinProgress: View {
    var fraction: Double
    var tint: Color = Theme.accent

    var body: some View { ProgressLine(fraction: fraction, tint: tint) }
}
