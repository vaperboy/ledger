import Foundation
import GameCore

// The presidency. A cycle has a nomination period and a voting period of seven weeks each and fills a twelve-week term. Standing costs a very
// high, non-refundable fee that goes to the treasury. A candidate may state up to three promises, each checked against what the office can
// really do. One account, one vote (linked accounts share it); the ballot is kept apart from the voter and the count is shown only after
// voting closes. The result, the promises and every change the president makes wait for an administrator.

public struct GovCitizen: Equatable, Sendable {
    public var account: String
    /// Accounts of one owner share a key and so share one vote.
    public var linkKey: String
    public var country: String
    public var name: String
    public var ageWeeks: Int
    public var simulated = false
    public var barredFromVoting = false
    public var barredFromOffice = false

    public init(account: String, linkKey: String? = nil, country: String, name: String = "", ageWeeks: Int, simulated: Bool = false,
                barredFromVoting: Bool = false, barredFromOffice: Bool = false) {
        self.account = account; self.linkKey = linkKey ?? account; self.country = country; self.name = name.isEmpty ? account : name
        self.ageWeeks = ageWeeks; self.simulated = simulated; self.barredFromVoting = barredFromVoting; self.barredFromOffice = barredFromOffice
    }
}

public struct CampaignPromise: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case transferTax, gainsTax, priceSupport }
    public var kind: Kind
    /// The rate promised (transfer or gains tax) or the share of sales (price support).
    public var value: Double
    public var tradeID: String?
    public var kept = false

    public init(kind: Kind, value: Double, tradeID: String? = nil) { self.kind = kind; self.value = value; self.tradeID = tradeID }
}

public struct ElectionCandidate: Codable, Equatable, Sendable {
    public var account: String
    public var name: String
    public var manifesto: String
    public var promises: [CampaignPromise]
    public var promisesApproved = false
    public var nominatedWeek: Int
    public var feePaid: Double
}

public struct Election: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case nomination, voting, counted, closed }

    public var id: Int
    public var status: Status
    public var nominateUntil: Int
    public var votingUntil: Int
    public var candidates: [ElectionCandidate] = []
    /// Who has voted and the keys already used: no choice is stored here.
    public var voted: Set<String> = []
    public var usedKeys: Set<String> = []
    /// What was cast, as counts only: nothing ties a ballot to a person or a time.
    public var ballots: [String: Int] = [:]
    public var winner: String?
    public var confirmed = false
}

public enum Politics {
    public static let nominationWeeks = 7
    public static let votingWeeks = 7
    public static let cooldownWeeks = 2
    public static let voterMinAgeWeeks = 4
    public static let candidateMinAgeWeeks = 8
    public static let maxPromises = 3
    public static let manifestoLimit = 300
    /// Reference price of standing for president (scaled to the country's price level by the caller). Very high on purpose.
    public static let candidacyFeeReference = 500_000.0

    public static func mayVote(_ c: GovCitizen, country: String) -> Bool {
        c.country == country && !c.simulated && c.ageWeeks >= voterMinAgeWeeks && !c.barredFromVoting
    }
    public static func mayStand(_ c: GovCitizen, country: String) -> Bool {
        c.country == country && !c.simulated && c.ageWeeks >= candidateMinAgeWeeks && !c.barredFromOffice
    }

    /// Why a promise cannot be kept within one term (nil when it is realistic). A rate may move one point at a time and not more often
    /// than every seven weeks, so a twelve-week term allows two steps.
    public static func realismProblem(_ p: CampaignPromise, policy: GovPolicy, treasury: Double) -> String? {
        let reach = GovPolicy.step * Double((Government.termWeeks - 1) / GovPolicy.changeGapWeeks + 1)
        switch p.kind {
        case .transferTax:
            if !GovPolicy.transferRange.contains(p.value) { return "The transfer tax stays between 0% and 5%." }
            if abs(p.value - policy.transferTax) < 1e-9 { return "That is the rate already." }
            if abs(p.value - policy.transferTax) > reach + 1e-9 { return "Rates move at most two points in one term." }
        case .gainsTax:
            if !GovPolicy.gainsRange.contains(p.value) { return "The gains tax stays between 5% and 40%." }
            if abs(p.value - policy.gainsTax) < 1e-9 { return "That is the rate already." }
            if abs(p.value - policy.gainsTax) > reach + 1e-9 { return "Rates move at most two points in one term." }
        case .priceSupport:
            if (p.tradeID ?? "").isEmpty { return "Name the trade." }
            if !GovPriceSupport.percentRange.contains(p.value) { return "Support is 1% to 10% of sales." }
            if treasury <= 0 { return "The treasury is empty." }
        }
        return nil
    }
}

extension Government {
    public var electionRunning: Bool { election.map { $0.status != .closed } ?? false }

    // MARK: Standing

    /// Everything that must hold before a fee is taken. The caller checks this, takes the fee, then calls `stand`.
    public func validateStand(_ c: GovCitizen, promises: [CampaignPromise], week: Int) throws {
        guard let e = election, e.status == .nomination, week < e.nominateUntil else { throw GovError.notOpen }
        guard Politics.mayStand(c, country: country) else { throw GovError.notEligible("You cannot stand: you must live here, be at least 8 weeks old, and not be barred.") }
        guard !e.candidates.contains(where: { $0.account == c.account }) else { throw GovError.alreadyStanding }
        try validatePromises(promises)
    }

    func validatePromises(_ promises: [CampaignPromise]) throws {
        guard promises.count <= Politics.maxPromises else { throw GovError.overLimit("At most three promises.") }
        guard Set(promises.map { $0.kind }).count == promises.count else { throw GovError.unrealistic("One promise of each kind.") }
        for p in promises { if let why = Politics.realismProblem(p, policy: policy, treasury: treasury.balance) { throw GovError.unrealistic(why) } }
    }

    /// Enters the candidate. The fee has been taken from them and is credited to the treasury here; it is never given back.
    public mutating func stand(_ c: GovCitizen, manifesto: String, promises: [CampaignPromise], fee: Double, week: Int) throws {
        try validateStand(c, promises: promises, week: week)
        guard var e = election else { throw GovError.notOpen }
        let cand = ElectionCandidate(account: c.account, name: c.name, manifesto: String(manifesto.prefix(Politics.manifestoLimit)),
                                     promises: promises, promisesApproved: promises.isEmpty, nominatedWeek: week, feePaid: govRound(fee))
        e.candidates.append(cand)
        election = e
        receive(fee, kind: "candidacy_fee", ref: c.account, week: week)
        log(c.account, "stand", "candidate for president", week: week)
        if !promises.isEmpty {
            let p = GovPending(id: takeID(), kind: .promises, week: week, proposer: c.account, summary: "Promises of \(c.name)", electionID: e.id)
            pending.insert(p, at: 0)
        }
    }

    /// A candidate withdraws during nomination. The fee is not returned.
    public mutating func withdraw(account: String, week: Int) throws {
        guard var e = election, e.status == .nomination, week < e.nominateUntil else { throw GovError.notOpen }
        guard e.candidates.contains(where: { $0.account == account }) else { throw GovError.notFound }
        e.candidates.removeAll { $0.account == account }
        election = e
        for i in pending.indices where pending[i].kind == .promises && pending[i].status == .open && pending[i].proposer == account { pending[i].status = .rejected }
        log(account, "withdraw", "", week: week)
    }

    // MARK: Voting

    public mutating func castBallot(_ c: GovCitizen, for candidate: String, week: Int) throws {
        guard var e = election, e.status == .voting, week < e.votingUntil else { throw GovError.notOpen }
        guard Politics.mayVote(c, country: country) else { throw GovError.notEligible("You cannot vote here.") }
        guard e.candidates.contains(where: { $0.account == candidate }) else { throw GovError.notFound }
        guard !e.voted.contains(c.account), !e.usedKeys.contains(c.linkKey) else { throw GovError.alreadyVoted }
        e.voted.insert(c.account)
        e.usedKeys.insert(c.linkKey)
        e.ballots[candidate, default: 0] += 1
        election = e
    }

    public func hasVoted(_ account: String) -> Bool { election?.voted.contains(account) ?? false }

    /// The count, shown only once voting has closed.
    public func tally() -> [(account: String, votes: Int)]? {
        guard let e = election, e.status == .counted || e.status == .closed else { return nil }
        return e.candidates.map { (account: $0.account, votes: e.ballots[$0.account] ?? 0) }
    }

    // MARK: The weekly turn

    /// Moves the election forward, ends a finished term and opens a new cycle. `canStand` is asked again at the count: a candidate who has
    /// since been barred cannot win. `hasCitizens` is false for a country nobody lives in.
    public mutating func advance(week: Int, canStand: (String) -> Bool, hasCitizens: Bool = true) {
        expireSupports(week: week)
        if let o = office, week >= o.termEnd { endTerm(o, week: week) }
        if var e = election {
            if e.status == .nomination, week >= e.nominateUntil {
                if e.candidates.isEmpty { e.status = .closed; lastCycleClosedWeek = week; publish("No one stood for president. The office stays vacant.", week: week) }
                else { e.status = .voting; publish("Voting for president is open.", week: week) }
                election = e
            } else if e.status == .voting, week >= e.votingUntil {
                count(&e, week: week, canStand: canStand)
            }
        }
        if !electionRunning, office == nil, hasCitizens, week - (lastCycleClosedWeek ?? -1_000) >= Politics.cooldownWeeks {
            election = Election(id: takeID(), status: .nomination, nominateUntil: week + Politics.nominationWeeks,
                                votingUntil: week + Politics.nominationWeeks + Politics.votingWeeks)
            publish("Nominations for president are open.", week: week)
        }
    }

    /// Most votes wins; a tie goes to whoever was nominated first. No ballots, no winner. A winner waits for an administrator.
    private mutating func count(_ e: inout Election, week: Int, canStand: (String) -> Bool) {
        let ranked = e.candidates.filter { canStand($0.account) }.sorted {
            let a = e.ballots[$0.account] ?? 0, b = e.ballots[$1.account] ?? 0
            if a != b { return a > b }
            if $0.nominatedWeek != $1.nominatedWeek { return $0.nominatedWeek < $1.nominatedWeek }
            return $0.account < $1.account
        }
        let total = e.ballots.values.reduce(0, +)
        if let w = ranked.first, total > 0 {
            e.winner = w.account
            e.status = .counted
            election = e
            let p = GovPending(id: takeID(), kind: .electionResult, week: week, proposer: w.account, summary: "Election result: \(w.name) wins", electionID: e.id)
            pending.insert(p, at: 0)
        } else {
            e.status = .closed
            election = e
            lastCycleClosedWeek = week
            publish("The vote ended with no winner. The office stays vacant.", week: week)
        }
    }

    // MARK: Confirmation hooks (called from `confirm` and `reject`)

    mutating func installWinner(_ p: GovPending, week: Int) throws {
        guard var e = election, e.id == p.electionID, e.status == .counted, let w = e.winner,
              let cand = e.candidates.first(where: { $0.account == w }) else { throw GovError.wrongState }
        e.status = .closed
        e.confirmed = true
        election = e
        lastCycleClosedWeek = week
        office = GovOffice(holder: w, name: cand.name, termStart: week, termEnd: week + Self.termWeeks, promises: cand.promisesApproved ? cand.promises : [])
        publish("\(cand.name) is the new president for \(Self.termWeeks) weeks.", tone: "good", week: week)
    }

    mutating func rejectResult(_ p: GovPending, week: Int) {
        guard var e = election, e.id == p.electionID else { return }
        e.status = .closed
        e.winner = nil
        election = e
        lastCycleClosedWeek = week
        publish("The election result was not confirmed. The office stays vacant.", tone: "bad", week: week)
    }

    mutating func approvePromises(_ p: GovPending, week: Int) throws {
        guard var e = election, e.id == p.electionID, let i = e.candidates.firstIndex(where: { $0.account == p.proposer }) else { throw GovError.notFound }
        try validatePromises(e.candidates[i].promises)
        e.candidates[i].promisesApproved = true
        election = e
    }

    mutating func stripPromises(_ p: GovPending) {
        guard var e = election, let i = e.candidates.firstIndex(where: { $0.account == p.proposer }) else { return }
        e.candidates[i].promises = []
        e.candidates[i].promisesApproved = true
        election = e
    }

    // MARK: Keeping promises

    mutating func markKept(policyKinds: Bool, week: Int) {
        guard var o = office else { return }
        for i in o.promises.indices {
            switch o.promises[i].kind {
            case .transferTax: if abs(policy.transferTax - o.promises[i].value) < 1e-9 { o.promises[i].kept = true }
            case .gainsTax: if abs(policy.gainsTax - o.promises[i].value) < 1e-9 { o.promises[i].kept = true }
            case .priceSupport: break
            }
        }
        office = o
    }

    mutating func markKept(support s: GovPriceSupport, week: Int) {
        guard var o = office else { return }
        for i in o.promises.indices where o.promises[i].kind == .priceSupport && o.promises[i].tradeID == s.tradeID && s.percent >= o.promises[i].value - 1e-9 {
            o.promises[i].kept = true
        }
        office = o
    }

    /// The term has run out: the president leaves, with a public tally of promises. Open proposals from them lapse.
    mutating func endTerm(_ o: GovOffice, week: Int) {
        let kept = o.promises.filter { $0.kept }.count
        publish("\(o.name)'s term has ended" + (o.promises.isEmpty ? "." : ": \(kept) of \(o.promises.count) promises kept."), week: week)
        office = nil
        lapseProposals(of: o.holder, week: week)
        log("system", "term_end", o.holder, week: week)
    }

    /// A president who loses the right to hold office (a conviction) leaves at once.
    public mutating func removeFromOffice(account: String, reason: String, week: Int) {
        guard let o = office, o.holder == account else { return }
        publish("\(o.name) has been removed from office: \(reason)", tone: "bad", week: week)
        office = nil
        lapseProposals(of: account, week: week)
        log("system", "removed", "\(account): \(reason)", week: week)
    }

    private mutating func lapseProposals(of account: String, week: Int) {
        for i in pending.indices where pending[i].status == .open && pending[i].proposer == account && pending[i].kind != .promises {
            pending[i].status = .rejected
            pending[i].decidedBy = "system"
            pending[i].decidedWeek = week
            if pending[i].kind == .priceSupport, let k = supports.firstIndex(where: { $0.id == pending[i].supportID }) { supports[k].status = .rejected }
        }
        // Support the president started keeps running to its end; only proposals still waiting lapse.
    }
}
