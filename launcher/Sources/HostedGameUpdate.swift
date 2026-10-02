import CryptoKit
import Foundation

struct HostedGameFeedEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let payload: String
    let signature: String
}

struct HostedGameFeed: Codable, Equatable {
    let schemaVersion: Int
    let publishedAt: String
    let release: GameRelease

    func validate(for edition: GameEdition = .global) throws {
        guard schemaVersion == 1,
              ISO8601DateFormatter().date(from: publishedAt) != nil,
              let versionCode = release.versionCode,
              versionCode > 0 else {
            throw LauncherError.invalidManifest("Invalid hosted TFT feed")
        }
        try release.validate(for: edition)
        for apk in release.apks {
            guard let url = apk.url,
                  url.scheme == "https",
                  url.host == MacticianIdentity.gameUpdateURL.host,
                  url.port == nil || url.port == 443,
                  url.user == nil,
                  url.password == nil,
                  url.query == nil,
                  url.fragment == nil,
                  url.path == "\(edition.updatePath)/releases/\(release.baseSHA256)/\(apk.name)" else {
                throw LauncherError.invalidManifest("APK \(apk.name) uses an untrusted URL")
            }
        }
    }
}

enum HostedGameUpdate {
    static func isNewer(_ release: GameRelease, than state: InstalledGameState) -> Bool {
        if let remoteVersionCode = release.versionCode,
           let installedVersionCode = state.gameVersionCode {
            return remoteVersionCode > installedVersionCode
        }
        return release.version != state.gameVersion
    }

    static func decodeAndVerify(
        _ envelopeData: Data,
        edition: GameEdition = .global,
        publicKeyBase64: String? = nil
    ) throws -> HostedGameFeed {
        let envelope = try JSONDecoder().decode(HostedGameFeedEnvelope.self, from: envelopeData)
        guard envelope.schemaVersion == 1,
              let payload = Data(base64Encoded: envelope.payload),
              let signature = Data(base64Encoded: envelope.signature) else {
            throw LauncherError.invalidManifest("Invalid hosted TFT feed envelope")
        }
        // An explicit key (tests) is the only trusted key. Otherwise the pinned
        // key is trusted, plus the development key in development builds.
        let trustedKeys = publicKeyBase64.map { [$0] }
            ?? [MacticianIdentity.gameUpdatePublicKeyBase64] + (DevGameFeed.publicKeyBase64.map { [$0] } ?? [])
        var signatureIsValid = false
        for keyBase64 in trustedKeys {
            guard let publicKeyData = Data(base64Encoded: keyBase64) else {
                throw LauncherError.invalidManifest("Invalid hosted TFT feed envelope")
            }
            let publicKey: Curve25519.Signing.PublicKey
            do {
                publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
            } catch {
                throw LauncherError.integrity("The TFT feed public key is invalid")
            }
            if publicKey.isValidSignature(signature, for: payload) {
                signatureIsValid = true
                break
            }
        }
        guard signatureIsValid else {
            throw LauncherError.integrity("The TFT feed signature is invalid")
        }
        let feed = try JSONDecoder().decode(HostedGameFeed.self, from: payload)
        try feed.validate(for: edition)
        return feed
    }

    static func loadVerifiedFeed(from url: URL, edition: GameEdition = .global) throws -> HostedGameFeed {
        try decodeAndVerify(Data(contentsOf: url), edition: edition)
    }

    static func installedRelease(
        for edition: GameEdition,
        state: InstallState,
        paths: LauncherPaths,
        manifest: ReleaseManifest
    ) -> GameRelease? {
        let cached = try? loadVerifiedFeed(from: paths.hostedGameFeed(for: edition), edition: edition).release
        let bundled: GameRelease? = edition == .global ? manifest.game : nil
        let candidates = [cached, bundled].compactMap { $0 }
        if let installed = state.games[edition.id],
           let matching = candidates.first(where: { installed.matches($0) }) {
            return matching
        }
        return candidates.max { ($0.versionCode ?? 0) < ($1.versionCode ?? 0) }
    }
}
