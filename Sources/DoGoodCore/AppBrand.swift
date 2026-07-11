import Foundation

public enum AppBrand {
    public static let fallbackDisplayName = "Do Good"

    public static var displayName: String {
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return bundleName?.isEmpty == false ? bundleName! : fallbackDisplayName
    }
}

