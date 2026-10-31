import XCTest
@testable import Ledger

/// The navigation rules of stage 1, on the store that owns every tab's stack (no engine needed): a link to a record already on a stack
/// never stacks a copy, Back from a cross-tab link returns to its origin and leaves nothing behind, choosing the open tab pops to root.
@MainActor
final class NavigationStackTests: XCTestCase {

    func testLinkToTheSameScreenDoesNotStackACopy() {
        let old: [CompanyRoute] = [.company(1), .companyAt(1, .operations)]
        XCTAssertEqual(GameStore.collapse(old, pushing: .companyAt(1, .operations)), old)
    }

    func testLinkToTheCompanyHubFromInsideItGoesBackToTheHub() {
        let old: [CompanyRoute] = [.company(1), .companyAt(1, .operations)]
        XCTAssertEqual(GameStore.collapse(old, pushing: .company(1)), [.company(1)])
    }

    func testLinkToAnotherScreenOfTheSameCompanyIsOneStepOnTop() {
        let old: [CompanyRoute] = [.company(1), .companyAt(1, .operations)]
        XCTAssertEqual(GameStore.collapse(old, pushing: .companyAt(1, .staff)), old + [.companyAt(1, .staff)])
    }

    func testLinkToAnotherPartOfTheScreenAlreadyShownReplacesIt() {
        let old: [CompanyRoute] = [.company(1), .companyAt(1, .finances)]
        XCTAssertEqual(GameStore.collapse(old, pushing: .companyPart(1, .finances, "Ownership")), [.company(1), .companyPart(1, .finances, "Ownership")])
    }

    func testLinkToAnotherCompanyIsPushed() {
        let old: [CompanyRoute] = [.company(1)]
        XCTAssertEqual(GameStore.collapse(old, pushing: .company(2)), [.company(1), .company(2)])
    }

    func testFinishedNewCompanyFormIsNotKeptBehindAPush() {
        XCTAssertEqual(GameStore.collapse([.newCompany], pushing: .company(3)), [.company(3)])
    }

    func testNavigationLinkAppendingASecondCopyIsCollapsed() {
        let store = GameStore()
        store.setPath([.company(1)], for: .team)
        store.setPath([.company(1), .company(1)], for: .team)
        XCTAssertEqual(store.path(for: .team), [.company(1)])
    }

    func testBackFromACrossTabLinkReturnsToTheOriginAndLeavesNothingBehind() {
        let store = GameStore()
        store.tab = .company
        store.open(.companyAt(2, .staff), on: .team)
        XCTAssertEqual(store.tab, .team)
        XCTAssertEqual(store.path(for: .team), [.companyAt(2, .staff)])
        XCTAssertEqual(store.returnTab, .company)
        // The player presses Back: the Team stack shrinks to what it held before the link.
        store.setPath([], for: .team)
        XCTAssertEqual(store.tab, .company)
        XCTAssertTrue(store.path(for: .team).isEmpty)
        XCTAssertNil(store.returnTab)
    }

    func testPhoneAppOpenedFromAnotherTabLeavesNoAppBehind() {
        let store = GameStore()
        store.openApp(.bank)
        XCTAssertEqual(store.tab, .phone)
        XCTAssertEqual(store.phonePath, [.app(.bank)])
        store.setPhonePath([])
        XCTAssertEqual(store.tab, .company)
        XCTAssertTrue(store.phonePath.isEmpty)
    }

    func testLeavingALinkedTabByHandRemovesTheLinkedScreen() {
        let store = GameStore()
        store.open(.companyAt(2, .staff), on: .team)
        store.selectTab(.group)
        XCTAssertTrue(store.path(for: .team).isEmpty)
        XCTAssertNil(store.returnTab)
    }

    func testChoosingTheOpenTabPopsItToItsRoot() {
        let store = GameStore()
        store.push(.company(1), on: .company)
        store.push(.companyAt(1, .operations), on: .company)
        XCTAssertEqual(store.depth(.company), 2)
        let token = store.rootToken(.company)
        store.selectTab(.company)
        XCTAssertEqual(store.depth(.company), 0)
        XCTAssertEqual(store.rootToken(.company), token + 1)
    }

    func testRoutesOfOneRecordShareAKeyAndDifferentScreensDoNot() {
        XCTAssertEqual(CompanyRoute.companyAt(1, .finances).key, CompanyRoute.companyPart(1, .finances, "Statements").key)
        XCTAssertNotEqual(CompanyRoute.company(1).key, CompanyRoute.companyAt(1, .overview).key)
        XCTAssertEqual(CompanyRoute.make(1, .properties, nil), .companyPart(1, .operations, "Premises"))
    }
}
