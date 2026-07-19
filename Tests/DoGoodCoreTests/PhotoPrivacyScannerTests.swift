import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DoGoodCore

final class PhotoPrivacyScannerTests: XCTestCase {
    func testFindsNoPeopleInBlankImage() async throws {
        let imageData = try blankJPEGData()

        let containsPerson = try await PhotoPrivacyScanner.containsPerson(in: imageData)

        XCTAssertFalse(containsPerson)
    }

    func testRejectsInvalidImageData() async {
        do {
            _ = try await PhotoPrivacyScanner.containsPerson(in: Data("not-an-image".utf8))
            XCTFail("Expected invalid image data to fail the privacy scan")
        } catch {
            return
        }
    }

    private func blankJPEGData() throws -> Data {
        let width = 640
        let height = 480
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
