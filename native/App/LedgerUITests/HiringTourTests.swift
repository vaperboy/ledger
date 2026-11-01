import XCTest

/// Tours of the employment screens (Master spec Stage 3): the two-page hiring flow (page 1 contract terms, page 2 salary negotiation, Back to page 1),
/// the contract discussion with its consequences and a promise, the staff profile, and Company > Team > Promises. Pictures are numbered from 100.
/// Every part is its own short test (each stays well under 100 s) and every step is optional: a screen that is not reachable on this device is
/// noted, never failed. Nothing is hired, so the game is left as it was.
final class HiringTourTests: CompanyBatchTourCase {
    /// Opens the Team section of the first company and the hiring screen, runs a job-ad search and opens the first candidate's terms (page 1).
    @discardableResult
    func openFirstCandidateTerms() -> Bool {
        guard openFirstCompany() else { return false }
        guard tapID("company-tab-team") else { return false }
        guard tapContaining("Hire someone") || tapContaining("Find workers") else { return false }
        shot("100-hiring-search")
        guard tapContaining("Run the") else { return false }
        shot("100-hiring-candidates")
        return tapID("hire-talk-terms", wait: 5)
    }

    func testHiringTwoPages() {
        guard openFirstCandidateTerms() else { return }
        XCTAssertTrue(app.buttons["hire-next"].waitForExistence(timeout: 5), "page 1 has a Next button")
        shot("101-hire-page-1-terms")
        app.swipeUp(); sleep(1)
        shot("101-hire-page-1-lower")
        app.swipeDown(); app.swipeDown(); sleep(1)
        tapLabel("80 percent")
        shot("101-hire-page-1-80-percent")
        guard tapID("hire-next") else { return }
        shot("102-hire-page-2-salary")
        // Nothing is said about their ask until they have named it.
        XCTAssertFalse(app.buttons["hire-offer-ask"].exists, "Offer what they ask is not shown before they name an ask")
        if tapID("hire-hear-ask") {
            shot("102-hire-page-2-after-ask")
            XCTAssertTrue(app.buttons["hire-offer-ask"].waitForExistence(timeout: 3), "Offer what they ask appears once they have named it")
        }
        app.swipeUp(); sleep(1)
        shot("102-hire-page-2-cost")
        goBack()
        XCTAssertTrue(app.buttons["hire-next"].waitForExistence(timeout: 5), "Back from page 2 returns to page 1")
        shot("103-hire-back-on-page-1")
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
        app.swipeDown(); app.swipeDown(); sleep(1)
        if tapContaining("Promises") {
            shot("107-promises")
            app.swipeUp(); sleep(1)
            shot("107-promises-lower")
        }
    }
}
