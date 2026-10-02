import Foundation

/// Local development game feed.
///
/// Compiled in only when the launcher is built with `-D MACTICIAN_DEV_FEED`
/// (see `MACTICIAN_EXTRA_SWIFT_FLAGS` in `scripts/build-mactician.command`).
/// Release builds contain none of it: they always use the pinned HTTPS feed
/// and the pinned signing key.
///
/// When enabled, two `UserDefaults` keys redirect the feed:
/// - `devGameFeedDirectory`: a folder laid out like the hosted update tree
///   (`game/manifest.json`, `game/vietnam/releases/<sha>/base.apk`, ...). A
///   hosted URL under `/mactician/updates/` is read from that folder instead.
/// - `devGameFeedPublicKey`: an additional Ed25519 key that may sign the feed.
///   The pinned key stays trusted, so feeds cached from the hosted channel
///   still verify.
enum DevGameFeed {
    static let hostedPathPrefix = "/mactician/updates/"

    #if MACTICIAN_DEV_FEED
    static var directory: URL? {
        guard let path = UserDefaults.standard.string(forKey: "devGameFeedDirectory"),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static var publicKeyBase64: String? {
        UserDefaults.standard.string(forKey: "devGameFeedPublicKey").flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The local file for a hosted update URL, or nil when the URL is not
    /// served from the development folder.
    static func localURL(for url: URL) -> URL? {
        guard let directory,
              url.host == MacticianIdentity.gameUpdateURL.host,
              url.path.hasPrefix(hostedPathPrefix) else { return nil }
        let relative = String(url.path.dropFirst(hostedPathPrefix.count))
        guard !relative.isEmpty,
              !relative.split(separator: "/").contains("..") else { return nil }
        return directory.appendingPathComponent(relative)
    }
    #else
    static var publicKeyBase64: String? { nil }

    static func localURL(for url: URL) -> URL? { nil }
    #endif

    static func curlArguments(source: URL, destination: URL) -> [String] {
        ["-fL", source.absoluteString, "-o", destination.path]
    }
}
