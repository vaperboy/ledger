import Foundation
import GameCore
import Countries
import Finance

/// The days and the week of a trade that sells jobs in hours (plumber, electrician, construction, engineering office,
/// event agency). Originals: `projDay` and the `FAM.project.custom.around` step of features/sales/trades_in_hours.js,
/// the bookings of the event agency (tidier_screens_and_monthly_bills.js, section 10), and the awareness step of the same
/// file ("people who used you tell others").
///
/// Every day (after the shops and services have traded) each open project company works its day: requests come in, the
/// hours go to the oldest job first, finished jobs are paid. The week close books exactly what happened on the days.
public enum ProjectWeek {
    static let eventNames: [[String]] = [
        ["summer party", "Christmas party", "conference", "product launch", "staff kick-off", "anniversary dinner", "customer seminar"],
        ["summer concert", "club night", "outdoor festival", "charity concert", "album release show"],
        ["wedding", "wedding", "wedding", "silver wedding"],
    ]

    /// Every open project company works the day. Original: `day.after` step 'trades log their hours' (prio 90).
    public static func runDay(_ s: inout GameState, day d: Int, data: GameData) {
        for i in s.companies.indices {
            guard s.companies[i].status == .open, let bd = data.catalog[s.companies[i].type], ProjectModel.sellsHours(bd) else { continue }
            let fm0 = s.companies[i].value("fm")
            var log = (!fm0["d41"].isNull && fm0["d41"]["w"].int == s.week) ? ProjectModel.DayLog(json: fm0["d41"]) : ProjectModel.DayLog(week: s.week)
            workDay(&s, i, bd, &log, week: s.week, day: d, data: data)
            var fm = s.companies[i].value("fm")
            fm["d41"] = log.json
            s.companies[i].set("fm", fm)
        }
    }

    // MARK: One day of work

    static func workDay(_ s: inout GameState, _ i: Int, _ bd: Trade, _ L: inout ProjectModel.DayLog, week wk: Int, day d: Int, data: GameData) {
        if L.days.contains(d) { return }
        let spec = ProjectModel.specs[bd.id]!
        let isEvent = spec.isEvent
        let id = s.companies[i].id
        // Read-only view for the calculations; dropped before the state changes.
        let (dm, cp, hvl, vat, country, currency, tKnob, ttKnob): (DemandResult, CapacityResult, Double, Double, Country, Currency, Double, Double) = {
            let w = World(state: s, data: data)
            let co = s.companies[i]
            return (DemandModel.compute(co, bd, w), CapacityModel.compute(co, bd, w), ProjectModel.hourValue(co, bd, w), Vat.rate(co, bd, w), w.country(co), w.currency(co),
                    Knobs.effect(co, bd, "t", w), Knobs.effect(co, bd, "tt", w))
        }()
        let co0 = s.companies[i]
        let mixNow = ProjectModel.mix(co0, bd)
        let avgH = ProjectModel.averageHours(spec, mixNow)
        let Hw = ProjectModel.hoursPerWeek(bd, capacity: cp.capacity)
        let wd = DailyTrade.weekday(week: wk, day: d)
        let workShare: Double = wd < 5 ? 0.2 : 0
        let reqShare: Double = wd < 5 ? 0.18 : wd == 5 ? 0.07 : 0.03
        let js = Pricing.jobScale(co0)
        let Dh = dm.customers * js * bd.ticket * tKnob * ttKnob / spec.hv * spec.demandFactor
        L.requestedHours += Dh * reqShare
        L.hoursPerWeekSum += Hw / 7
        L.hoursAvailableToday += Hw * workShare

        var fm = co0.value("fm")
        var jobs = ProjectModel.jobs(fm)
        var won = fm["won"].double, doneCount = fm["done"].double
        for k in jobs.indices { ProjectModel.normalise(&jobs[k], bd, hourValue: hvl, week: s.week, random: &s.random) }
        let nowD = wk * 7 + d
        // The event agency's bookings: the month's counts and the clients who come back.
        var eventState = fm["ev30"].isNull ? JSONValue.object(["due": .array([]), "m": -1, "bm": 0, "dm": 0, "tot": 0]) : fm["ev30"]
        if isEvent {
            let mi = GameCalendar.monthIndex(week: wk)
            if eventState["m"].int != mi { eventState["m"] = .number(Double(mi)); eventState["bm"] = 0; eventState["dm"] = 0 }
        }
        let focus = co0.value("knob")["seg"].int
        let cur = currency

        func backlogHours() -> Double { jobs.reduce(0) { $0 + ($1.inHours ? $1.remainingHours : 0) } }

        /// A payment from the client. A milestone payment (`retain`) has the trade's retention held back: it is revenue now, but the client keeps
        /// that share until the job is complete and the defect period is over (it waits as a receivable, see `CompanyWeek.book`).
        func payJob(_ j: inout ProjectModel.Job, _ amount: Double, retain: Bool = false) -> Double {
            let amt = jsRound(min(amount, j.contractValue - j.paid))
            if amt <= 0 { return 0 }
            j.paid += amt
            L.rev += amt
            L.cogs += amt * j.costShare
            let held = retain ? jsRound(amt * (bd.trait("retention") ?? 0)) : 0
            if held > 0 { j.retained += held; L.held[j.id, default: 0] += held }
            let cash = jsRound((amt - held) * (1 + vat) * (1 - bd.businessShare))
            if cash != 0 { Payments.companyReceives(&s, companyID: id, amount: cash, category: nil, label: nil) }
            L.paid += cash
            return amt
        }

        func eventName(_ j: ProjectModel.Job) -> String {
            j.source == "rep" ? "\(j.client)’s \(j.what) again" : j.client + (j.what.contains("wedding") ? "’s " : " ") + j.what
        }

        /// Original: `EV.dress` — who books, what for, and the date.
        func dress(_ j: inout ProjectModel.Job, source src: String, from: String?) {
            j.source = src
            j.from = from ?? ""
            if src == "rep", let f = from, !f.isEmpty { j.client = f }
            else if focus == 2 {
                let first = country.firstNames, last = country.lastNames
                j.client = (first.isEmpty ? "Alex" : s.random.pick(first)) + " " + (last.isEmpty ? "Smith" : s.random.pick(last))
            } else {
                j.client = CompanySetup.generateName(country: country, family: focus == 1 ? "venue" : "svc", &s.random)
            }
            j.dueWeek = s.week + j.weeks
            let mo = GameCalendar.date(week: j.dueWeek).month
            let list = eventNames[min(2, max(0, focus))]
            let ok = list.filter { n in
                if n.contains("Christmas") { return mo >= 10 }
                if n.contains("summer") || n.contains("outdoor") { return mo >= 4 && mo <= 7 }
                return true
            }
            j.what = s.random.pick(ok.isEmpty ? eventNames[0] : ok)
        }

        func take(_ j0: ProjectModel.Job, source: String? = nil, from: String? = nil) -> Bool {
            var j = j0
            L.requests += 1
            if isEvent {
                // An event has a date: take it only if the team can prepare it, and everything due before it, in time.
                j.weeks = j.sizeClass == 2 ? s.random.int(6, 14) : j.sizeClass == 1 ? s.random.int(3, 8) : s.random.int(1, 4)
                dress(&j, source: source ?? "mkt", from: from)
                if j.sizeClass == 2 && source != "rep" {
                    let pool: [[String]] = [["conference", "product launch", "customer seminar"], ["outdoor festival", "summer concert"], ["wedding"]]
                    j.what = s.random.pick(pool[min(2, max(0, focus))])
                }
                j.dueWeek = wk + j.weeks
                j.dueDay = j.dueWeek * 7 + Int((s.random.next() * 7).rounded(.down))
                let before = jobs.filter { ($0.dueDay ?? 0) <= (j.dueDay ?? 0) }.reduce(0) { $0 + $1.remainingHours }
                if Hw <= 0 || before + j.hours > Double((j.dueDay ?? 0) - nowD) / 7 * Hw * 0.9 { L.lost += 1; return false }
            } else {
                let wait = Hw > 0 ? backlogHours() / Hw : 99
                if Hw <= 0 || wait > 3 { L.lost += 1; return false }
                if j.hours > Hw * 12 { L.lost += 1; L.tooBig += 1; return false }
            }
            won += 1
            L.took += 1
            if j.sizeClass == 2 { L.big += 1 }
            if isEvent {
                eventState["bm"] = .number(eventState["bm"].double + 1)
                _ = payJob(&j, j.contractValue * 0.3)
                jobs.append(j)
                let how = j.source == "ref" ? "Recommended by \(j.from)." : j.source == "rep" ? "\(j.client) was happy last time and books again." : "Came from people who know your name."
                s.addMessage(from: s.companies[i].name, title: "New booking: \(eventName(j))",
                             body: "\(cur.short(j.contractValue)), to deliver around \(GameCalendar.dateString(week: j.dueWeek)). \(how) 30% deposit now, the rest after the event.",
                             companyID: id, tone: "good", status: "done")
            } else {
                j.dueWeek = j.startWeek + j.weeks   // planned finish, recorded when the job is taken on (events carry their own date)
                jobs.append(j)
            }
            return true
        }

        // New requests
        let n = s.random.poisson(Dh * reqShare / max(1, avgH))
        for _ in 0..<n { let j = ProjectModel.newJob(&s, s.companies[i], bd, hourValue: hvl, country: country); _ = take(j) }
        // Happy clients recommend you and book again
        if isEvent {
            var keep: [JSONValue] = []
            for x in eventState["due"].array {
                if wk < x["w"].int { keep.append(x); continue }
                if s.companies[i].status == .open {
                    let j = ProjectModel.newJob(&s, s.companies[i], bd, hourValue: hvl, country: country)
                    _ = take(j, source: x["src"].string, from: x["from"].string)
                }
            }
            eventState["due"] = .array(keep)
        }

        // The day's work: the oldest job first; for events the nearest date first
        var left = Hw * workShare
        let order: [Int] = isEvent ? jobs.indices.sorted { (jobs[$0].dueDay ?? 0, $0) < (jobs[$1].dueDay ?? 0, $1) } : Array(jobs.indices)
        for k in order {
            if left <= 1e-6 { break }
            if jobs[k].delay > 0 {
                if workShare > 0 { jobs[k].delay = max(0, jobs[k].delay - 0.2) }
                continue
            }
            let use = min(left, jobs[k].remainingHours)
            if use <= 0 { continue }
            if jobs[k].milestones == nil { jobs[k].milestones = !isEvent && (jobs[k].sizeClass == 2 || jobs[k].hours > 2 * Hw) }
            if jobs[k].hoursDone == 0 && jobs[k].milestones == true {
                let dep = payJob(&jobs[k], jobs[k].contractValue * 0.3, retain: true)
                if dep > 0 && jobs[k].sizeClass == 2 {
                    s.note("Started: \(jobs[k].what.lowercased()) for \(jobs[k].client). Deposit paid: \(cur.short(dep)).", tone: "n", companyID: id)
                }
            }
            jobs[k].hoursDone += use
            left -= use
            L.used += use
            jobs[k].progress = min(1, jobs[k].hoursDone / jobs[k].hours)
            if jobs[k].milestones == true && jobs[k].progress >= 0.5 && jobs[k].paid < jobs[k].contractValue * 0.69 {
                _ = payJob(&jobs[k], jobs[k].contractValue * 0.7 - jobs[k].paid, retain: true)
            }
        }

        // Finished jobs; events happen on their day, ready or not
        let fin: [Int] = isEvent ? jobs.indices.filter { nowD >= (jobs[$0].dueDay ?? Int.max) } : jobs.indices.filter { jobs[$0].hoursDone >= jobs[$0].hours - 1e-6 }
        var finished3 = fm["fin41"].array.isEmpty ? [0.0, 0.0, 0.0] : (0..<3).map { fm["fin41"][$0].double }
        for k in fin {
            var j = jobs[k]
            let prep = min(1, j.hoursDone / j.hours)
            let last = payJob(&j, j.contractValue - j.paid)
            if j.retained > 0 { L.released.append(j.id) }   // complete: the defect period of the retention starts
            jobs[k] = j
            doneCount += 1
            L.units += 1
            L.finished[j.sizeClass] += 1
            finished3[j.sizeClass] += 1
            if j.sizeClass > 0 { L.names.append(j.what) }
            let q = s.companies[i].quality
            let dr = [0.08, 0.15, 0.35][j.sizeClass]
            let rep0 = s.companies[i].reputation
            if isEvent && prep < 0.9 { s.companies[i].reputation = clamp(rep0 - 1.5 * (1 - prep) * 3, 0, 100) }
            else { s.companies[i].reputation = clamp(rep0 + (q > 55 ? dr : q < 45 ? -dr * 0.6 : 0), 0, 100) }
            if isEvent {
                eventState["dm"] = .number(eventState["dm"].double + 1)
                eventState["tot"] = .number(eventState["tot"].double + 1)
                if prep >= 0.9 {
                    // Delivered: a happy client tells others and may book again.
                    let happy = s.random.chance(clamp(0.45 + (q - 55) / 80, 0.15, 0.92))
                    if happy {
                        let r1 = focus == 2 ? 0.6 : 0.45, r2 = focus == 2 ? 0.25 : 0.15, rep = focus == 0 ? 0.55 : focus == 1 ? 0.45 : 0.03
                        var due = eventState["due"].array
                        func add(_ weekAt: Int, _ src: String) { due.append(.object(["w": .number(Double(weekAt)), "src": .string(src), "from": .string(j.client)])) }
                        if s.random.chance(r1) { add(s.week + s.random.int(3, 14), "ref") }
                        if s.random.chance(r2) { add(s.week + s.random.int(6, 20), "ref") }
                        if s.random.chance(rep) { add(s.week + s.random.int(44, 56), "rep") }
                        eventState["due"] = .array(due)
                    }
                    s.addMessage(from: s.companies[i].name, title: "Delivered: \(eventName(j))",
                                 body: (happy ? "The client was delighted and will tell others about you." : "The client was not fully happy. Expect no recommendations from this one.") + " Final invoice sent.",
                                 companyID: id, tone: happy ? "good" : "n", status: "done")
                } else {
                    s.addMessage(from: s.companies[i].name, title: "Delivered in a rush: \(eventName(j))",
                                 body: "Only \(Int(jsRound(prep * 100)))% of the preparation was done in time. The client noticed; no recommendations from this one. Final invoice sent.",
                                 companyID: id, tone: "bad", status: "done")
                }
            } else if j.sizeClass == 2 {
                s.note("\(j.what.prefix(1).uppercased() + j.what.dropFirst()) for \(j.client) finished. Final payment \(cur.short(last)) (the whole job \(cur.short(j.contractValue))).", tone: "good", companyID: id)
            }
            // A finished job may get a review
            let pr = min(0.7, ProjectModel.reviewRate(bd) * [1, 1.4, 2][j.sizeClass])
            if s.random.next() < pr { ProjectModel.addReview(&s, i, bias: (j.hours > j.quotedHours * 1.25 ? -0.4 : 0) + (prep < 0.9 ? -1 : 0)) }
        }
        let finSet = Set(fin)
        jobs = jobs.enumerated().filter { !finSet.contains($0.offset) }.map { $0.element }

        let backlog = jobs.reduce(0) { $0 + ($1.contractValue - $1.paid) }
        let backH = backlogHours()
        fm["jobs"] = ProjectModel.jsonJobs(jobs)
        fm["won"] = .number(won); fm["done"] = .number(doneCount)
        fm["fin41"] = .array(finished3.map { .number($0) })
        fm["backlog"] = .number(jsRound(backlog))
        fm["backlogH"] = .number(jsRound(backH))
        fm["backlogWk"] = .number(Hw > 0 ? jsRound(backH) / Hw : 99)
        fm["hw41"] = .number(Hw); fm["avgH41"] = .number(avgH); fm["hvl41"] = .number(hvl)
        if isEvent { fm["ev30"] = eventState }
        s.companies[i].set("fm", fm)
        L.days.insert(d)
    }

    // MARK: The week close

    /// The figures the week's books take from the days that happened. Original: 'the week’s books take what happened on its days'.
    static func closeWeek(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) -> CompanyWeek.WeekContext {
        let wk = s.week - 1
        let fm0 = s.companies[i].value("fm")
        var L = (!fm0["d41"].isNull && fm0["d41"]["w"].int == wk) ? ProjectModel.DayLog(json: fm0["d41"]) : ProjectModel.DayLog(week: wk)
        // A week played without the days (or a company that opened during it): the missing days are worked now.
        for d in 0..<7 where !L.days.contains(d) { workDay(&s, i, bd, &L, week: wk, day: d, data: data) }
        var fm = s.companies[i].value("fm")
        let spec = ProjectModel.specs[bd.id]!
        let avgH = fm["avgH41"].double != 0 ? fm["avgH41"].double : ProjectModel.averageHours(spec, ProjectModel.mix(s.companies[i], bd))
        let hvl = fm["hvl41"].double
        var ctx = CompanyWeek.WeekContext(units: L.units, rev: L.rev, cogs: L.cogs, D: L.requestedHours / avgH, cap: L.hoursPerWeekSum / avgH,
                                          util: L.hoursPerWeekSum > 0 ? min(1, L.used / L.hoursPerWeekSum) : 0, price: avgH * hvl, paidDuringWeek: L.paid)
        ctx.retentionHeld = L.held
        ctx.retentionReleased = L.released
        fm["wk41"] = .object(["w": .number(Double(wk)), "req": .number(L.requests), "took": .number(L.took), "lost": .number(L.lost), "tooBig": .number(L.tooBig),
                              "big": .number(L.big), "used": .number(jsRound(L.used)), "H": .number(jsRound(L.hoursPerWeekSum)),
                              "fin": .array(L.finished.map { .number($0) }), "names": .array(L.names.prefix(4).map { .string($0) }), "rev": .number(jsRound(L.rev))])
        var lost = fm["lost41"].array
        lost.append(.number(L.lost))
        fm["lost41"] = .array(Array(lost.suffix(4)))
        fm["d41"] = .null
        s.companies[i].set("fm", fm)
        return ctx
    }

    // MARK: Being known

    /// People who used you tell others: a busy team becomes known in its area, not famous. Original: week.after 'trades_in_hours weekly'.
    static func afterWeek(_ s: inout GameState, _ i: Int, _ bd: Trade, data: GameData) {
        guard s.companies[i].status == .open else { return }
        var co = s.companies[i]
        let fm = co.value("fm")
        // The developer has no hours: what it sells is compared with what a normal one sells.
        let x = ProjectModel.sellsHours(bd) ? fm["wk41"]["used"].double / 30 : (bd.normalCapacity > 0 ? co.lastWeekUnits / (bd.normalCapacity * 0.6) : 0)
        var cu = co.value("cu41").array.map { $0.double }
        cu.append(min(4, x))
        cu = Array(cu.suffix(26))
        co.set("cu41", .array(cu.map { .number($0) }))
        let ratio = cu.reduce(0, +) / 26
        var qf = clamp(0.75 + (co.quality - 45) / 80, 0.6, 1.2)
        if co.int("rvN") >= 5 { let a = ProjectModel.averageRating(co); qf *= a >= 4.2 ? 1.1 : a >= 3 ? 1 : 0.9 }
        let w = World(state: s, data: data)
        qf *= clamp(1 + (1 - w.balance.priceMultiplier(level: co.priceLevel)) * 0.8, 0.75, 1.3)
        let floor = min(32, 28 * min(1.2, ratio).squareRoot() * qf)
        if co.awareness < floor { co.awareness = clamp(co.awareness + (floor - co.awareness) * 0.08, 0, 100) }
        s.companies[i] = co
    }
}
