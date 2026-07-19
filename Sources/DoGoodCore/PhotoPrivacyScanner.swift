import Foundation
import Vision

public enum PhotoPrivacyScanner {
    public static func containsPerson(in imageData: Data) async throws -> Bool {
        try await Task.detached(priority: .userInitiated) {
            let faceRequest = VNDetectFaceRectanglesRequest()

            let upperBodyRequest = VNDetectHumanRectanglesRequest()
            upperBodyRequest.upperBodyOnly = true

            let fullBodyRequest = VNDetectHumanRectanglesRequest()
            fullBodyRequest.upperBodyOnly = false

            let handler = VNImageRequestHandler(
                data: imageData,
                orientation: .up,
                options: [:]
            )
            try handler.perform([faceRequest, upperBodyRequest, fullBodyRequest])

            return hasResults(faceRequest.results)
                || hasResults(upperBodyRequest.results)
                || hasResults(fullBodyRequest.results)
        }.value
    }

    private static func hasResults<T>(_ results: [T]?) -> Bool {
        results?.isEmpty == false
    }
}
