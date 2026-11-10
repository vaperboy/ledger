import XCTest

/// Screenshots of every Team screen of a company: the Team tab, the roster, a worker profile, the contract discussion and a promise, perks,
/// goals, applicants, hiring (ad, agency, offer pages), management and its sheets, executive posts and paperwork signing.
/// Each screen is one attachment named "Team-<screen>"; a screen that cannot be reached is noted and the run goes on.
final class ShotsTeamTests: FeatureTourCase {
    /// One screenshot, kept in the result bundle, and one PASS line so the workflow counts the run.
    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "Team-\(name)"
        a.lifetime = .keepAlways
        add(a)
        log.record(.pass, "Team-\(name)", "")
    }

    func miss(_ name: String, _ why: String) {
        shot(name + "-missing")
        log.note("Team \(name): \(why)")
    }

    /// The Team tab of the café, scrolled to the top.
    func openTeam() -> Bool {
        toRoot()
        guard openCompany("Caf") else { return false }
        return tapID("company-tab-people", wait: 4)
    }

    /// A worker of the roster: a row with a person id, else a role group then its first person (older layout).
    func openWorker() -> Bool {
        guard openTeam() else { return false }
        if tapPrefix("team-worker-", wait: 3) { return true }
        guard let group = bringIn({ $0.type == .button && ($0.label.contains(" people") || $0.label.contains(" person")) && !$0.label.hasPrefix("Staff") }, wait: 3) else { return false }
        touch(group)
        return tapWhere(wait: 2) { $0.type == .button && $0.frame.minY >= group.frame.maxY - 2 && $0.frame.minY < group.frame.maxY + 90 && !$0.label.contains(" people") }
    }

    func openHiring() -> Bool {
        guard openTeam() else { return false }
        return tapID("team-hire-workers", wait: 4)
    }

    /// Plays days from Home (closing each report) until `until` holds.
    func playDays(_ days: Int, until: () -> Bool) -> Int {
        var played = 0
        while played < days {
            toRoot()
            guard goTab("Home"), tapID("next-day", wait: 3) else { break }
            played += 1
            var n = 0
            while n < 8 && popupUp(n == 0 ? 6 : 2) { closePopup(prefer: ["report-continue", "celebration-claim", "celebration-dismiss", "alert-continue"]); n += 1 }
            if until() { break }
        }
        return played
    }

    /// Scrolls the page down so rows under the tab bar can be tapped; always true, for use in a condition list.
    func scrolledDown() -> Bool {
        dragPage(-600)
        return true
    }

    func scrollShot(_ name: String) {
        dragPage(-420)
        shot(name)
    }

    func testShots() {
        testDeadline = Date().addingTimeInterval(3600)

        // Team tab
        if openTeam() {
            pause(0.8)
            shot("01-team")
            scrollShot("02-team-lower")
            scrollShot("03-team-bottom")
        } else { miss("01-team", "no café / Team tab") }

        // Roster and worker profile
        if openWorker() {
            pause(0.8)
            shot("04-worker-profile")
            scrollShot("05-worker-profile-lower")
            scrollShot("06-worker-profile-bottom")
            if tapID("worker-discuss", wait: 2) || tapText("Contract discussion", wait: 2) || tapText("Discuss", wait: 2) || tapText("Talk", wait: 2) {
                pause(0.8)
                shot("07-contract-discussion")
                if tapLabel("Hours", wait: 2) {
                    shot("08-contract-hours")
                    scrollShot("09-contract-hours-lower")
                }
                if tapID("hire-add-promise", wait: 2) {
                    shot("10-promise-maker")
                    closePopup()
                }
                var n = 0
                while popupUp() && n < 4 { closePopup(); n += 1 }
            } else { miss("07-contract-discussion", "no discuss button on the profile") }
        } else { miss("04-worker-profile", "no worker row") }

        // Perks
        if openTeam() {
            if tapID("team-perks", wait: 2) || tapLabel("Perks") {
                pause(0.8)
                shot("11-perks")
                closePopup()
            } else { miss("11-perks", "no Perks row") }
        }

        // Hiring: the ad page, a role picked, the agency, post the ad
        if openHiring() {
            pause(0.8)
            shot("15-hire")
            scrollShot("16-hire-lower")
            dragPage(900)
            if tapLabel("Agency", wait: 2) { shot("17-hire-agency"); _ = tapLabel("Job ad", wait: 2) || tapLabel("Ad", wait: 1) }
            // Post the ad waits for a role: pick one that is not filled yet.
            _ = tapText("Cook", wait: 2) || tapText("General helper", wait: 1) || tapText("Cleaner", wait: 1)
            if tapEnabled("hire-post-ad", wait: 3) {
                pause(0.8)
                shot("18-hire-post-confirm")
                if has("confirm-go", wait: 2) { _ = tapID("confirm-go") }
                pause(1)
                shot("19-hire-after-post")
            }
        } else { miss("15-hire", "no Hire button") }

        // An applicant: the terms page and the offer page
        if !(openHiring() && has("hire-talk-terms", wait: 2)) {
            _ = playDays(4) { openHiring() && has("hire-talk-terms", wait: 2) }
        }
        if openHiring() && tapID("hire-talk-terms", wait: 4) {
            pause(0.8)
            shot("20-offer-terms")
            scrollShot("21-offer-terms-lower")
            dragPage(900)
            if tapID("hire-next", wait: 3) {
                pause(0.6)
                shot("22-offer-pay")
                scrollShot("23-offer-pay-lower")
                if tapID("hire-add-promise", wait: 2) { shot("24-offer-promise"); closePopup() }
                if tapID("hire-make-offer", wait: 3) {
                    pause(0.6)
                    shot("25-offer-confirm")
                    closePopup(prefer: ["confirm-cancel"])
                }
                _ = tapID("hire-back", wait: 2)
            }
            _ = tapID("hire-walk-away", wait: 2)
        } else { miss("20-offer-terms", "no applicant after the ad") }

        // Applicants with someone waiting
        if openTeam() && tapID("open-applicants", wait: 3) {
            pause(0.8)
            shot("26-applicants-waiting")
        }

        // Management (Group > company > Management) and the manager / assistant sheets
        if openTeam(), scrolledDown(), tapID("team-open-management", wait: 4) {
            pause(1)
            shot("27-management")
            scrollShot("28-management-lower")
            dragPage(900)
            if tapID("mgmt-row-m", wait: 2) || tapWhere(wait: 2, { $0.type == .button && $0.label.localizedCaseInsensitiveContains("manager") && !$0.label.localizedCaseInsensitiveContains("assistant") && !$0.id.hasPrefix("tab-") && !$0.id.hasPrefix("group-") }) {
                pause(0.8)
                shot("29-manager-sheet")
                scrollShot("30-manager-sheet-lower")
                if tapID("manager-headcount", wait: 2) {
                    pause(0.8)
                    shot("30a-staffing-plan")
                    tapLabel("Back to the manager")
                }
                if tapLabel("Results") {
                    pause(0.6)
                    shot("30b-manager-results")
                }
                closePopup()
            } else { miss("29-manager-sheet", "no manager row") }
            if tapID("mgmt-row-a", wait: 2) || tapText("Assistant manager", wait: 2) {
                pause(0.8)
                shot("31-assistant-sheet")
                closePopup()
            }
            if tapPrefix("mgmt-row-s", wait: 2) {
                pause(0.8)
                shot("32-post-sheet")
                closePopup()
            }
        } else { miss("27-management", "no management link") }

        // Executive posts on the chain page (when the café is in a chain)
        if openCompany("Caf"), tapID("company-tab-overview", wait: 3), tapText("Open the chain", wait: 3) {
            pause(1)
            shot("33-chain")
            if bringIn({ $0.label.localizedCaseInsensitiveContains("Chain management") || $0.label.localizedCaseInsensitiveContains("executive") }, wait: 2) != nil { shot("34-executive-posts") }
        } else { log.note("Team: no chain to show executive posts") }

        // Paperwork: Manage > Licences > the signing form
        toRoot()
        if openCompany("Caf"), tapID("company-tab-overview", wait: 3), scrolledDown(), tapWhere(wait: 3, { $0.label.hasPrefix("Licences") && $0.type != .staticText }) {
            pause(0.8)
            shot("35-licences")
            if tapText("Fill in and apply", wait: 2) || tapText("Apply again", wait: 2) || tapText("Apply", wait: 2) {
                pause(0.8)
                shot("36-sign-sheet")
                closePopup(prefer: ["popup-close"])
            } else { miss("36-sign-sheet", "no licence to apply for") }
        } else { miss("35-licences", "no Licences row in Manage") }
    }
}
