import Foundation

struct ChaChingWidgetSnapshot: Codable, Equatable {
    var updatedAt: Date
    var periodTitle: String
    var childName: String
    var currentCents: Int
    var baseCents: Int
    var rolloverDebtCents: Int
    var choresLeft: Int
    var nextChoreTitle: String
    var nextChoreTime: String

    var progress: Double {
        guard baseCents > 0 else { return 0 }
        return min(1, Double(currentCents) / Double(baseCents))
    }

    var hasRolloverDebt: Bool {
        rolloverDebtCents > 0
    }
}

enum ChaChingWidgetSharedState {
    static let appGroupIdentifier = "group.com.artofsullivan.chaching"
    static let snapshotKey = "chaching.widget.allowanceSnapshot"
    static let widgetKind = "ChaChingAllowanceWidget"

    static func loadSnapshot() -> ChaChingWidgetSnapshot? {
        guard let data = sharedDefaults?.data(forKey: snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(ChaChingWidgetSnapshot.self, from: data)
    }

    @discardableResult
    static func saveSnapshot(_ snapshot: ChaChingWidgetSnapshot) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot),
              let sharedDefaults else {
            return false
        }

        sharedDefaults.set(data, forKey: snapshotKey)
        return true
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}
