import XCTest
import SwiftUI
@testable import Ledger

/// The claim logic of nested hosts (a `.sheet` with `.popupHost()`), the order of arrival, the step-back rule of a tall popup with its own
/// pages, and the popup role of a negotiation answer.
final class PopupHostTests: XCTestCase {

    private func put(_ host: PopupHost, _ key: String, _ priority: PopupPriority = .panel) {
        host.upsert(key: key, priority: priority, draw: .raw, content: { AnyView(EmptyView()) }, onClose: {})
    }

    private func keys(_ entries: [PopupEntry]) -> Set<String> {
        Set(entries.map { (e: PopupEntry) -> String in e.key })
    }

    private func visible(_ entries: [PopupEntry]) -> String? {
        let items: [PopupQueue.Item] = entries.map { (e: PopupEntry) -> PopupQueue.Item in e.item }
        return PopupQueue.visible(items)
    }

    // MARK: Order of arrival

    func testEntriesGetIncreasingArrivalNumbers() {
        let host = PopupHost()
        put(host, "a")
        put(host, "b")
        XCTAssertLessThan(host.entries["a"]?.seq ?? Int.max, host.entries["b"]?.seq ?? 0)
    }

    func testRegisteringTheSameKeyAgainKeepsItsPlaceInTheQueue() {
        let host = PopupHost()
        put(host, "n1", .notice)
        put(host, "n2", .notice)
        let first: Int = host.entries["n1"]?.seq ?? -1
        put(host, "n1", .notice)
        XCTAssertEqual(host.entries["n1"]?.seq, first)
        XCTAssertEqual(visible(host.drawnEntries()), "n1")
    }

    func testRemovedAndRaisedAgainGoesToTheBackOfTheQueue() {
        let host = PopupHost()
        put(host, "n1", .notice)
        put(host, "n2", .notice)
        host.remove("n1")
        put(host, "n1", .notice)
        XCTAssertEqual(visible(host.drawnEntries()), "n2")
    }

    func testAPopupRaisedWhileAnotherIsOpenWaitsByPriority() {
        let host = PopupHost()
        put(host, "panel", .panel)
        put(host, "notice", .notice)
        XCTAssertEqual(visible(host.drawnEntries()), "notice")
        host.remove("notice")
        XCTAssertEqual(visible(host.drawnEntries()), "panel")
    }

    func testAConfirmRaisedFromAPanelShowsAboveItAndThePanelComesBack() {
        let host = PopupHost()
        put(host, "panel", .panel)
        put(host, "confirm", .confirm)
        XCTAssertEqual(visible(host.drawnEntries()), "confirm")
        host.remove("confirm")
        XCTAssertEqual(visible(host.drawnEntries()), "panel")
    }

    func testTwoPanelsAreAStackAndTheOlderOneStaysRegistered() {
        let host = PopupHost()
        put(host, "profile", .panel)
        put(host, "discussion", .panel)
        XCTAssertEqual(visible(host.drawnEntries()), "discussion")
        XCTAssertEqual(keys(host.drawnEntries()), ["profile", "discussion"])
    }

    // MARK: Nested hosts

    func testANestedHostClaimsTheHostAboveAndDrawsItsPopupsOnce() {
        let root = PopupHost()
        let sheet = PopupHost()
        put(root, "notice", .notice)
        put(sheet, "form", .panel)
        XCTAssertEqual(keys(root.drawnEntries()), ["notice"])
        sheet.attach(to: root)
        XCTAssertEqual(root.claims, 1)
        XCTAssertTrue(root.drawnEntries().isEmpty, "the root layer draws nothing while a sheet is open")
        XCTAssertEqual(keys(sheet.drawnEntries()), ["notice", "form"], "the sheet's layer draws its own and the root's")
        XCTAssertEqual(visible(sheet.drawnEntries()), "notice")
    }

    func testClosingTheSheetGivesTheRootItsPopupsBack() {
        let root = PopupHost()
        let sheet = PopupHost()
        put(root, "notice", .notice)
        sheet.attach(to: root)
        sheet.detach()
        XCTAssertEqual(root.claims, 0)
        XCTAssertEqual(keys(root.drawnEntries()), ["notice"])
        XCTAssertEqual(keys(sheet.drawnEntries()), [])
    }

    func testAttachingTwiceClaimsOnceAndDetachingTwiceReleasesOnce() {
        let root = PopupHost()
        let sheet = PopupHost()
        sheet.attach(to: root)
        sheet.attach(to: root)
        XCTAssertEqual(root.claims, 1)
        sheet.detach()
        sheet.detach()
        XCTAssertEqual(root.claims, 0)
    }

    func testTwoSheetsKeepTheClaimUntilBothAreClosed() {
        let root = PopupHost()
        let a = PopupHost()
        let b = PopupHost()
        a.attach(to: root)
        b.attach(to: root)
        XCTAssertEqual(root.claims, 2)
        a.detach()
        XCTAssertTrue(root.drawnEntries().isEmpty)
        b.detach()
        put(root, "x")
        XCTAssertEqual(keys(root.drawnEntries()), ["x"])
    }

    func testASheetInsideASheetStillDrawsTheRootPopupsOnce() {
        let root = PopupHost()
        let outer = PopupHost()
        let inner = PopupHost()
        put(root, "notice", .notice)
        put(outer, "outerForm")
        outer.attach(to: root)
        inner.attach(to: outer)
        XCTAssertTrue(root.drawnEntries().isEmpty)
        XCTAssertTrue(outer.drawnEntries().isEmpty)
        XCTAssertEqual(keys(inner.drawnEntries()), ["notice", "outerForm"])
    }

    func testASheetThatVanishesWithoutOnDisappearGivesTheClaimBack() {
        let root = PopupHost()
        var sheet: PopupHost? = PopupHost()
        sheet?.attach(to: root)
        XCTAssertEqual(root.claims, 1)
        sheet = nil
        let settled = expectation(description: "claim released")
        DispatchQueue.main.async { DispatchQueue.main.async { settled.fulfill() } }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(root.claims, 0)
        XCTAssertNil(sheet)
    }

    func testAHostCannotClaimItself() {
        let host = PopupHost()
        host.attach(to: host)
        XCTAssertEqual(host.claims, 0)
    }

    // MARK: Step back in a tall popup

    func testCloseInATallPopupPopsOnePageFirstAndClosesAtTheRoot() {
        XCTAssertEqual(PopupStep.forClose(pagesPushed: 2), .popPage)
        XCTAssertEqual(PopupStep.forClose(pagesPushed: 1), .popPage)
        XCTAssertEqual(PopupStep.forClose(pagesPushed: 0), .closePopup)
    }

    // MARK: Negotiation answers

    func testOnlyAnAgreementIsAnEffectLine() {
        XCTAssertEqual(HireFeedback.hired("ok").popupRole, .effect)
        XCTAssertEqual(HireFeedback.declined("no").popupRole, .risk)
        XCTAssertEqual(HireFeedback.unavailable("gone").popupRole, .risk)
        XCTAssertEqual(HireFeedback.countered(1, "maybe").popupRole, .risk)
    }
}
