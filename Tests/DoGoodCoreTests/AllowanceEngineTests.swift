import XCTest
@testable import DoGoodCore

final class AllowanceEngineTests: XCTestCase {
    func testSeedStateStartsAtThirteenFifty() {
        let snapshot = SeedData.snapshot()
        let summary = AllowanceEngine.summary(for: snapshot.ledger)

        XCTAssertEqual(summary.weeklyBaseCents, 1_500)
        XCTAssertEqual(summary.activeDeductionCents, 150)
        XCTAssertEqual(summary.bonusCents, 0)
        XCTAssertEqual(summary.currentTotalCents, 1_350)
    }

    func testSeedStateIncludesParentAndChildRoles() {
        let snapshot = SeedData.snapshot()

        XCTAssertTrue(snapshot.members.contains { $0.role == .parent && $0.displayName == "Daddy" })
        XCTAssertTrue(snapshot.members.contains { $0.role == .child && $0.displayName == "Zoe" })
        XCTAssertEqual(snapshot.childProfiles.first?.displayName, "Zoe")
    }

    func testChildInviteReportsExpiredWhenPastExpiration() {
        let now = Date()
        let invite = ChildInvite(
            familyId: SeedData.familyId,
            childProfileId: SeedData.childId,
            childName: "Zoe",
            createdByParentId: SeedData.parentId,
            token: "zoe-test",
            inviteURL: AppBrand.inviteURL(token: "zoe-test"),
            expiresAt: now.addingTimeInterval(-60)
        )

        XCTAssertEqual(invite.resolvedStatus(now: now), .expired)
    }

    func testCompletingAChoreDoesNotIncreaseAllowance() {
        let entries = [
            AllowanceEngine.weeklyBaseEntry(weekId: SeedData.weekId, amountCents: 1_500)
        ]

        XCTAssertEqual(AllowanceEngine.summary(for: entries).currentTotalCents, 1_500)
    }

    func testMissedChoreCreatesDeductionAndExcuseVoidsIt() throws {
        let occurrenceId = UUID()
        let entries = AllowanceEngine.addingDeductionIfNeeded(
            to: [AllowanceEngine.weeklyBaseEntry(weekId: SeedData.weekId, amountCents: 1_500)],
            weekId: SeedData.weekId,
            occurrenceId: occurrenceId,
            choreTitle: "Take dog out",
            amountCents: 50
        )

        XCTAssertEqual(AllowanceEngine.summary(for: entries).currentTotalCents, 1_450)

        let excused = AllowanceEngine.voidingDeduction(in: entries, for: occurrenceId)
        XCTAssertEqual(AllowanceEngine.summary(for: excused).currentTotalCents, 1_500)
    }

    func testDuplicateDeductionsAreIdempotent() {
        let occurrenceId = UUID()
        let base = [AllowanceEngine.weeklyBaseEntry(weekId: SeedData.weekId, amountCents: 1_500)]
        let once = AllowanceEngine.addingDeductionIfNeeded(
            to: base,
            weekId: SeedData.weekId,
            occurrenceId: occurrenceId,
            choreTitle: "Take dog out",
            amountCents: 50
        )
        let twice = AllowanceEngine.addingDeductionIfNeeded(
            to: once,
            weekId: SeedData.weekId,
            occurrenceId: occurrenceId,
            choreTitle: "Take dog out",
            amountCents: 50
        )

        XCTAssertEqual(once.count, twice.count)
        XCTAssertEqual(AllowanceEngine.summary(for: twice).activeDeductionCents, 50)
    }

    func testBonusCanRaiseTotalAboveBaseAllowance() {
        let entries = [
            AllowanceEngine.weeklyBaseEntry(weekId: SeedData.weekId, amountCents: 1_500),
            AllowanceEngine.bonusEntry(weekId: SeedData.weekId, title: "Extra help", amountCents: 200)
        ]

        XCTAssertEqual(AllowanceEngine.summary(for: entries).currentTotalCents, 1_700)
    }
}
