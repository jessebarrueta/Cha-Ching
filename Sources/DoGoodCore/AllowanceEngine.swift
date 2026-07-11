import Foundation

public struct AllowanceSummary: Equatable {
    public var weeklyBaseCents: Int
    public var activeDeductionCents: Int
    public var bonusCents: Int
    public var adjustmentCents: Int
    public var currentTotalCents: Int

    public var progress: Double {
        guard weeklyBaseCents > 0 else { return 0 }
        return min(1, Double(currentTotalCents) / Double(weeklyBaseCents))
    }
}

public enum AllowanceEngine {
    public static func summary(for entries: [LedgerEntry]) -> AllowanceSummary {
        let active = entries.filter { !$0.isVoided }

        let base = active
            .filter { $0.type == .weeklyBase }
            .map(\.amountCents)
            .reduce(0, +)

        let deductions = active
            .filter { $0.type == .deduction }
            .map(\.amountCents)
            .reduce(0, +)

        let bonuses = active
            .filter { $0.type == .bonus }
            .map(\.amountCents)
            .reduce(0, +)

        let adjustments = active
            .filter { $0.type == .adjustment }
            .map(\.amountCents)
            .reduce(0, +)

        return AllowanceSummary(
            weeklyBaseCents: base,
            activeDeductionCents: deductions,
            bonusCents: bonuses,
            adjustmentCents: adjustments,
            currentTotalCents: max(0, base - deductions + bonuses + adjustments)
        )
    }

    public static func deductionExists(in entries: [LedgerEntry], for occurrenceId: UUID) -> Bool {
        entries.contains {
            !$0.isVoided &&
            $0.type == .deduction &&
            $0.relatedOccurrenceId == occurrenceId
        }
    }

    public static func deductionEntry(
        weekId: UUID,
        occurrenceId: UUID,
        choreTitle: String,
        amountCents: Int,
        createdAt: Date = Date()
    ) -> LedgerEntry {
        LedgerEntry(
            weekId: weekId,
            type: .deduction,
            title: "Missed: \(choreTitle)",
            amountCents: amountCents,
            relatedOccurrenceId: occurrenceId,
            createdAt: createdAt
        )
    }

    public static func addingDeductionIfNeeded(
        to entries: [LedgerEntry],
        weekId: UUID,
        occurrenceId: UUID,
        choreTitle: String,
        amountCents: Int,
        createdAt: Date = Date()
    ) -> [LedgerEntry] {
        guard !deductionExists(in: entries, for: occurrenceId) else {
            return entries
        }

        return entries + [
            deductionEntry(
                weekId: weekId,
                occurrenceId: occurrenceId,
                choreTitle: choreTitle,
                amountCents: amountCents,
                createdAt: createdAt
            )
        ]
    }

    public static func voidingDeduction(
        in entries: [LedgerEntry],
        for occurrenceId: UUID
    ) -> [LedgerEntry] {
        entries.map { entry in
            guard entry.type == .deduction, entry.relatedOccurrenceId == occurrenceId else {
                return entry
            }

            var updated = entry
            updated.isVoided = true
            return updated
        }
    }

    public static func weeklyBaseEntry(weekId: UUID, amountCents: Int, createdAt: Date = Date()) -> LedgerEntry {
        LedgerEntry(
            weekId: weekId,
            type: .weeklyBase,
            title: "Starting allowance",
            amountCents: amountCents,
            createdAt: createdAt
        )
    }

    public static func bonusEntry(
        weekId: UUID,
        title: String,
        amountCents: Int,
        note: String? = nil,
        createdAt: Date = Date()
    ) -> LedgerEntry {
        LedgerEntry(
            weekId: weekId,
            type: .bonus,
            title: title,
            amountCents: amountCents,
            note: note,
            createdAt: createdAt
        )
    }
}

