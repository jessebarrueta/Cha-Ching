import Foundation

public enum Money {
    public static func dollars(_ cents: Int, signed: Bool = false) -> String {
        let sign: String
        if signed {
            sign = cents > 0 ? "+" : cents < 0 ? "-" : ""
        } else {
            sign = cents < 0 ? "-" : ""
        }

        let absolute = abs(cents)
        return "\(sign)$\(absolute / 100).\(String(format: "%02d", absolute % 100))"
    }

    public static func cents(fromDollarString string: String) -> Int? {
        let cleaned = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")

        guard let decimal = Decimal(string: cleaned), decimal >= 0 else {
            return nil
        }

        let cents = decimal * Decimal(100)
        return NSDecimalNumber(decimal: cents).rounding(accordingToBehavior: nil).intValue
    }
}

