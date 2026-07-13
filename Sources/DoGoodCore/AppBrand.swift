import Foundation

public enum AppBrand {
    public static let fallbackDisplayName = "ChaChing"
    public static let fallbackInviteBaseURL = URL(string: "https://enormousbrain.com/cha-ching/invite")!

    public static var displayName: String {
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return bundleName?.isEmpty == false ? bundleName! : fallbackDisplayName
    }

    public static var inviteBaseURL: URL {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: "InviteBaseURL") as? String
        guard let rawValue, !rawValue.isEmpty, let url = URL(string: rawValue) else {
            return fallbackInviteBaseURL
        }

        return url
    }

    public static func inviteURL(token: String) -> URL {
        inviteBaseURL.appendingPathComponent(token)
    }
}
