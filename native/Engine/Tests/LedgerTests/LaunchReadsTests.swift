import XCTest
import GameCore
@testable import Businesses
@testable import Simulation

final class LaunchReadsTests: XCTestCase {
    func testPlayersOldSaveFirstRenderReads() throws {
        let (data, events, marketing) = try GameEngine.loadResources()
        let s = try Golden.state("save_player_old")
        var e = GameEngine(state: s, data: data, events: events, marketing: marketing)
        if e.state.rest["dayHist"] == nil { e.recordDay() }
        _ = e.marketEvents(limit: 30)
        _ = e.bigWeatherWarnings()
        _ = e.news
        _ = e.payrollAlerts()
        _ = e.ownerDecisions.map { e.severityLevel(of: $0) }
        for co in e.state.companies where co.status.isLive {
            _ = e.marketplaceListings(forCompany: co.id)
            _ = e.companyDocuments(companyID: co.id, group: .applications)
            _ = e.companyHealth(co)
            _ = e.tradeName(co); _ = e.cityName(co)
            _ = e.decisionChain(companyID: co.id)
            _ = e.projectBoard(companyID: co.id)
            if co.status == .open { _ = e.rivalRows(co) }
            _ = e.financeOverview(companyID: co.id)
            _ = e.supplierInputs(companyID: co.id)
            if let k = e.boardKey(companyID: co.id) { _ = e.boardOpenDecisions(key: k); _ = e.boardSeats(key: k); _ = e.boardIsActive(key: k) }
            _ = e.brandValue(companyID: co.id)
            _ = e.reviewSummary(co)
        }
        for g in Gate.allCases { _ = Gates.visibility(g, e.state, data: e.data) }
        _ = Unlocks.unlockedFeatures(e.state)
        for co in e.state.companies { _ = e.unlockState(companyID: co.id) }
        _ = e.suggestions(limit: 8)
        _ = e.chainSummaries; _ = e.groupManagement(); _ = e.groupCash; _ = e.boardDecisionsWaiting
        _ = e.foundedStartups; _ = e.startupStakes; _ = e.startupPitchesOnOffer
        _ = e.privateEquityOffersOnTable; _ = e.privateEquityFunds; _ = e.bigMeetingOffer; _ = e.bigMeetingStakes; _ = e.groupStakes
        _ = e.rivalGroupsAround(); _ = e.delegationLines(); _ = e.holdingCompanies
        _ = e.financeOverview()
        _ = e.sinceYouLeft(lastSeenDay: e.lastSeenDay ?? 0)
        _ = e.careerStatus; _ = e.careerNextGoals; _ = e.careerCosmetics
        _ = e.dailyGoal()
        _ = e.takeCelebrations()
        _ = e.pendingUnlocks()
        _ = e.teamOverview()
        _ = e.projectTimelines()
        _ = e.homeShortcutIDs
        _ = e.delegatedSpendLimit()
        _ = e.cashIsTight
        _ = e.date
        _ = e.netWorth
        _ = e.netWorthSeries(days: 365)
        _ = e.dayHistory
        _ = e.structureTree()
        _ = e.unlockRoadmap()
    }
}
