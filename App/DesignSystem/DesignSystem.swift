import SwiftUI
import UIKit

extension Color {
    static let brandBlack = Color(hex: "050505")
    static let brandWhite = Color(hex: "F8F7F2")
    static let inkBlack = Color(lightHex: "050505", darkHex: "F5F5F2")
    static let paperWhite = Color(lightHex: "F8F7F2", darkHex: "10110F")
    static let surface = Color(lightHex: "FFFFFF", darkHex: "1C1D1A")
    static let warmOrange = Color(hex: "FF5A1F")
    static let sunYellow = Color(hex: "FFCC00")
    static let electricBlue = Color(hex: "1D20FF")
    static let hotPink = Color(hex: "FF168F")
    static let acidLime = Color(hex: "A8E600")
    static let softGray = Color(lightHex: "E9E9E5", darkHex: "363731")
    static let mutedGray = Color(lightHex: "777770", darkHex: "B6B6AE")

    init(lightHex: String, darkHex: String) {
        let light = UIColor(hex: lightHex)
        let dark = UIColor(hex: darkHex)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    init(hex: String) {
        let scanner = Scanner(string: hex)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let scanner = Scanner(string: hex)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)

        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(Color.brandWhite)
            .background(Color.brandBlack, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct SecondaryActionButton: View {
    var title: String
    var systemImage: String
    var tint: Color
    var foregroundColor: Color = .brandBlack
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(foregroundColor)
            .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AllowanceCard: View {
    var summary: AllowanceSummary
    var periodTitle: String = "This Week"
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            Text(periodTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandWhite.opacity(0.8))

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Money.dollars(summary.currentTotalCents))
                    .font(.system(size: compact ? 34 : 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.brandWhite)
                    .contentTransition(.numericText())
                Text("/ \(Money.dollars(summary.weeklyBaseCents))")
                    .font(.headline)
                    .foregroundStyle(Color.brandWhite.opacity(0.75))
            }

            CapsuleProgress(value: summary.progress)

            Text(summary.hasRolloverDebt ? "Next period starts reduced by \(Money.dollars(summary.rolloverDebtCents))" : "You started this period with \(Money.dollars(summary.weeklyBaseCents))")
                .font(.caption)
                .foregroundStyle(Color.brandWhite.opacity(0.75))
        }
        .padding(compact ? 18 : 24)
        .background(Color.brandBlack, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(periodTitle) \(Money.dollars(summary.currentTotalCents)) of \(Money.dollars(summary.weeklyBaseCents)) kept")
    }

}

struct CapsuleProgress: View {
    var value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.brandWhite.opacity(0.16))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.sunYellow, .acidLime],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(12, proxy.size.width * value))
            }
        }
        .frame(height: 14)
    }
}

struct MascotCluster: View {
    var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            BlueTriangle()
                .fill(Color.electricBlue)
                .frame(width: 112 * scale, height: 92 * scale)
                .overlay(alignment: .center) {
                    MascotFace(scale: scale * 0.75)
                        .offset(x: 8 * scale, y: -8 * scale)
                }
                .offset(x: 36 * scale, y: 4 * scale)

            OrangeBlob()
                .fill(Color.warmOrange)
                .frame(width: 94 * scale, height: 78 * scale)
                .overlay(alignment: .center) {
                    MascotFace(scale: scale * 0.72)
                        .offset(x: -16 * scale, y: -8 * scale)
                }
                .offset(x: -42 * scale, y: 0)

            PinkDome()
                .fill(Color.hotPink)
                .frame(width: 72 * scale, height: 54 * scale)
                .overlay(alignment: .center) {
                    MascotFace(scale: scale * 0.55)
                        .offset(x: 2 * scale, y: -4 * scale)
                }
                .offset(x: 76 * scale, y: 5 * scale)
        }
        .frame(width: 220 * scale, height: 118 * scale)
        .accessibilityHidden(true)
    }
}

struct LimeMascot: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color.acidLime.opacity(0.78))
                .rotationEffect(.degrees(12))
                .frame(width: 94, height: 110)

            Circle()
                .fill(Color.acidLime)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(Color.brandBlack.opacity(0.35))
                }
                .offset(x: 25, y: -44)

            MascotFace(scale: 0.8)
                .offset(y: 10)
        }
        .frame(width: 128, height: 136)
        .accessibilityHidden(true)
    }
}

struct MascotFace: View {
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 5 * scale) {
            HStack(spacing: 12 * scale) {
                Circle()
                    .fill(Color.brandBlack)
                    .frame(width: 4.5 * scale, height: 4.5 * scale)
                Circle()
                    .fill(Color.brandBlack)
                    .frame(width: 4.5 * scale, height: 4.5 * scale)
            }
            ArcSmile()
                .stroke(Color.brandBlack, style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
                .frame(width: 18 * scale, height: 9 * scale)
        }
    }
}

struct OrangeBlob: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY * 0.78))
        path.addCurve(
            to: CGPoint(x: rect.midX * 0.95, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + 8),
            control2: CGPoint(x: rect.midX * 0.55, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX * 0.66, y: rect.maxY * 0.72),
            control1: CGPoint(x: rect.maxX * 0.78, y: rect.minY),
            control2: CGPoint(x: rect.maxX * 0.66, y: rect.maxY * 0.36)
        )
        path.addLine(to: CGPoint(x: rect.maxX * 0.94, y: rect.maxY * 0.72))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX * 0.98, y: rect.maxY * 0.72),
            control2: CGPoint(x: rect.maxX, y: rect.maxY * 0.82)
        )
        path.closeSubpath()
        return path
    }
}

struct BlueTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct PinkDome: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

struct ArcSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY),
            radius: rect.width / 2,
            startAngle: .degrees(30),
            endAngle: .degrees(150),
            clockwise: false
        )
        return path
    }
}

extension Date {
    var shortTime: String {
        formatted(date: .omitted, time: .shortened)
    }
}

extension View {
    func cardSurface() -> some View {
        padding(18)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.softGray, lineWidth: 1)
            )
    }
}
