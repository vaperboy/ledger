import XCTest

/// Tours of the employment screens: the hiring flow (terms, then Next: pay with the offer and Back to terms),
/// the contract discussion with its consequences and a promise, and the staff profile. Pictures are numbered from 100.
/// Every part is its own short test (each stays well under 100 s) and every step is optional: a screen that is not reachable on this device is
/// noted, never failed. Nothing is hired, so the game is left as it was.
final class HiringTourTests: CompanyBatchTourCase {
    /// Opens the Team section of the first company and the hiring screen, runs a job-ad search and opens the first candidate's terms (page 1).
    @discardableResult
    func openFirstCandidateTerms() -> Bool {
        guard openFirstCompany() else { return false }
        guard tapID("company-tab-team") else { return false }
        guard tapID("team-hire-workers") else { return false }
        shot("100-hiring-workers")
        // Applicants answer an ad over days: with none on the list there is nothing to talk to, and the tour notes that.
        return tapID("hire-talk-terms", wait: 5)
    }

    func testHiringTwoPages() {
        guard openFirstCandidateTerms() else { return }
        XCTAssertTrue(app.buttons["hire-quick-offer"].waitForExistence(timeout: 5), "page 1 has Offer the going rate")
        shot("101-hire-page-1-going-rate")
        guard tapID("hire-next") else { return }
        shot("102-hire-page-2-offer")
        XCTAssertTrue(app.buttons["hire-make-offer"].waitForExistence(timeout: 5), "page 2 has Make the offer")
        tapLabel("80 percent")
        if tapID("hire-offer-market") { shot("102-hire-page-2-market") }
        app.swipeUp(); sleep(1)
        shot("102-hire-page-2-cost")
        if tapID("hire-back") {
            XCTAssertTrue(app.buttons["hire-quick-offer"].waitForExistence(timeout: 5), "Back returns to page 1")
            shot("103-hire-back-on-page-1")
            tapID("hire-next")
            tapID("hire-walk-away")
        } else {
            tapID("hire-walk-away")
        }
    }

    /// Opens the first staff member's profile on the Team section.
    @discardableResult
    func openFirstStaffProfile() -> Bool {
        guard openFirstCompany() else { return false }
        guard tapID("company-tab-team") else { return false }
        app.swipeUp(); sleep(1)
        let person = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'a month' AND label CONTAINS[c] 'company'")).firstMatch
        guard person.waitForExistence(timeout: 5), person.isHittable else { note("no staff member on the Team section"); return false }
        person.tap(); sleep(1)
        return true
    }

    func testContractDiscussionAndPromises() {
        guard openFirstStaffProfile() else { return }
        shot("104-staff-profile")
        app.swipeUp(); sleep(1)
        shot("104-staff-profile-lower")
        guard tapContaining("Contract discussion") || tapContaining("Discuss") else { return }
        shot("105-contract-discussion")
        if tapLabel("Hours") {
            shot("105-contract-hours-consequences")
            app.swipeUp(); sleep(1)
            shot("105-contract-hours-lower")
        }
        if tapID("hire-add-promise") {
            shot("106-contract-promise-maker")
            tapID("promise-confirm")
        }
        tapLabel("Done")
        goBack()
    }
}
