import Foundation

struct SupabaseConfiguration: Sendable {
    let projectURL: URL
    let publishableKey: String

    static func load(from bundle: Bundle = .main) -> SupabaseConfiguration? {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "SupabaseProjectURL") as? String,
              let rawKey = bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String,
              !rawURL.isEmpty,
              !rawKey.isEmpty,
              !rawURL.contains("$("),
              !rawKey.contains("$("),
              let url = URL(string: rawURL),
              url.scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return SupabaseConfiguration(projectURL: url, publishableKey: rawKey)
    }
}
