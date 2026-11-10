import XCTest
@testable import Ledger

@MainActor
final class NavigationStackTests: XCTestCase {

    func testLinkToTheSameSectionDoesNotStackACopy() {
        let old: [CompanyRoute] = [.companyAt(1, .operations)]
        XCTAssertEqual(GameStore.collapse(old, pushing: .companyAt(1, .operations)), old)
    }

    func testLinkToAnotherSectionOfTheCompanyAlreadyOpenReplacesItInsteadOfStacking() {
        let old: [CompanyRoute] = [.company(1)]
        XCTAssertEqual(GameStore.collapse(old, pushing: .companyAt(1, .staff)), [.companyAt(1, .staff)])
        XCTAssertEqual(GameStore.collapse([.companyAt(1, .staff)], pushing: .company(1)), [.company(1)])
    }

    func testAPageOfItsOwnIsPushedOnTopOfTheCompanyAndALinkToTheCompanyGoesBack() {
        let old: [CompanyRoute] = [.company(1), .companyAt(1, .marketing)]
        XCTAssertEqual(GameStore.collapse([.company(1)], pushing: .companyAt(1, .marketing)), old)
        XCTAssertEqual(GameStore.collapse(old, pushing: .companyAt(1, .operations)), [.companyAt(1, .operations)])
    }

    func testLinkToAnotherPartOfTheSectionAlreadyShownReplacesIt() {
        let old: [CompanyRoute] = [.companyAt(1, .finances)]
        XCTAssertEqual(GameStore.collapse(old, pushing: .companyPart(1, .finances, "Ownership")), [.companyPart(1, .finances, "Ownership")])
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
        store.setPath([.company(1)], for: .group)
        store.setPath([.company(1), .company(1)], for: .group)
        XCTAssertEqual(store.path(for: .group), [.company(1)])
    }

    func testALinkPushesOnTheOpenTabAndNeverChangesTab() {
        let store = GameStore()
        store.tab = .company
        store.push(.companyAt(2, .staff))
        store.push(.entity("co2", .management))
        XCTAssertEqual(store.tab, .company)
        XCTAssertEqual(store.path(for: .company), [.companyAt(2, .staff), .entity("co2", .management)])
        XCTAssertTrue(store.path(for: .group).isEmpty)
        store.setPath([.companyAt(2, .staff)], for: .company)
        XCTAssertEqual(store.tab, .company)
        XCTAssertEqual(store.depth(.company), 1)
    }

    func testAPhoneAppOpenedFromAnotherTabIsPushedThere() {
        let store = GameStore()
        store.tab = .group
        store.openApp(.bank)
        XCTAssertEqual(store.tab, .group)
        XCTAssertEqual(store.path(for: .group), [.app(.bank)])
        XCTAssertTrue(store.phonePath.isEmpty)
    }

    func testMarketRouteBecomesTheMarketAppOnTheSameStack() {
        let store = GameStore()
        store.tab = .group
        store.push(.market, on: .group)
        XCTAssertEqual(store.tab, .group)
        XCTAssertEqual(store.path(for: .group), [.app(.market)])
        XCTAssertEqual(store.takeMarketRequest(), 0, "no company chosen: all markets")
        store.openCompany(7, section: .market)
        XCTAssertEqual(store.path(for: .group), [.app(.market)], "already open: not stacked twice")
        XCTAssertEqual(store.takeMarketRequest(), 7)
        XCTAssertNil(store.takeMarketRequest(), "a request is taken once")
    }

    func testTheSwitcherSwapsTheTopScreenAndBackReturnsUnderIt() {
        let store = GameStore()
        store.tab = .group
        store.setPath([.entity("co1", .overview), .company(1)], for: .group)
        store.replaceTop(with: .company(2))
        XCTAssertEqual(store.path(for: .group), [.entity("co1", .overview), .company(2)])
        store.replaceTop(with: .companyAt(1, .operations))
        XCTAssertEqual(store.path(for: .group), [.entity("co1", .overview), .companyAt(1, .operations)])
        store.setPath([.company(3), .company(4)], for: .group)
        store.replaceTop(with: .company(3))
        XCTAssertEqual(store.path(for: .group), [.company(3)], "a company already under it is gone back to")
    }

    func testVenturesSwitchesTheProjectsRootAndIsPushedElsewhere() {
        let store = GameStore()
        store.tab = .projects
        store.openApp(.ventures)
        XCTAssertTrue(store.path(for: .projects).isEmpty)
        XCTAssertTrue(store.takeVenturesRequest())
        store.tab = .company
        store.openApp(.ventures)
        XCTAssertEqual(store.tab, .company)
        XCTAssertEqual(store.path(for: .company), [.app(.ventures)])
        XCTAssertFalse(store.takeVenturesRequest())
    }

    func testChoosingTheOpenTabPopsItToItsRoot() {
        let store = GameStore()
        store.push(.company(1), on: .company)
        store.push(.companyAt(1, .marketing), on: .company)
        XCTAssertEqual(store.depth(.company), 2)
        let token = store.rootToken(.company)
        store.selectTab(.company)
        XCTAssertEqual(store.depth(.company), 0)
        XCTAssertEqual(store.rootToken(.company), token + 1)
    }

    func testSectionsOfOneCompanyShareAKeyAndPagesOfTheirOwnDoNot() {
        XCTAssertEqual(CompanyRoute.companyAt(1, .finances).key, CompanyRoute.companyPart(1, .finances, "Ownership").key)
        XCTAssertEqual(CompanyRoute.company(1).key, CompanyRoute.companyAt(1, .overview).key)
        XCTAssertNotEqual(CompanyRoute.company(1).key, CompanyRoute.companyAt(1, .marketing).key)
        XCTAssertEqual(CompanyRoute.make(1, .properties, nil), .companyPart(1, .operations, "Premises"))
        XCTAssertEqual(NavRoute.entity("ch1", .overview).key, NavRoute.entity("ch1", .deals).key)
        XCTAssertNotEqual(NavRoute.entity("co1", .overview).key, NavRoute.company(1).key)
    }
}
