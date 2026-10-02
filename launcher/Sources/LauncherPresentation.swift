import Foundation

enum LauncherFailureOrigin: Equatable {
    case installation
    case launch
    case runtime
    case reset
    case validation
}

enum LauncherRecoveryAction: Equatable {
    case retryInstallation
    case tryLaunchAgain
    case restartGame
    case repairInstallation
    case none
}

struct LauncherFailure: Equatable {
    let origin: LauncherFailureOrigin
    let technicalDetails: String

    var recoveryAction: LauncherRecoveryAction {
        LauncherFailurePresentation.recoveryAction(for: origin)
    }
}

enum LauncherFailurePresentation {
    static func recoveryAction(for origin: LauncherFailureOrigin) -> LauncherRecoveryAction {
        switch origin {
        case .installation:
            return .retryInstallation
        case .launch:
            return .tryLaunchAgain
        case .runtime:
            return .restartGame
        case .validation:
            return .repairInstallation
        case .reset:
            return .none
        }
    }
}

enum InstallerCompletionPresentation {
    static func isUserCancellation(requested: Bool, error: Error) -> Bool {
        if requested { return true }
        return error as? LauncherError == .cancelled
    }
}

enum LauncherHotkeyStatus: Equatable {
    case permissionRequired
    case ready
    case active
    case unavailable
}

struct LauncherHotkeyFacts: Equatable {
    let accessibilityTrusted: Bool
    let eventTapActive: Bool
    let eventTapAttemptFailed: Bool
}

enum LauncherHotkeyPresentation {
    static func status(for facts: LauncherHotkeyFacts) -> LauncherHotkeyStatus {
        if facts.eventTapActive { return .active }
        guard facts.accessibilityTrusted else { return .permissionRequired }
        if facts.eventTapAttemptFailed { return .unavailable }
        return .ready
    }
}

struct LaunchConfigurationSnapshot: Equatable {
    let languageTitle: String
    let resolution: String
    let effectsQualityTitle: String
    let uiScalePercent: Int
    let memoryMB: Int
    let cpuCores: Int

    var compactSummary: String {
        "\(resolution) \u{00b7} \(effectsQualityTitle) \u{00b7} UI \(uiScalePercent)%"
    }

    var fullSummary: String {
        "\(compactSummary) \u{00b7} \(memoryMB / 1024) GB \u{00b7} \(cpuCores) vCPU"
    }
}

enum LauncherMetadata {
    static func gameDisplayVersion(from version: String) -> String {
        String(version.split(separator: "-", maxSplits: 1).first ?? Substring(version))
    }

    static func totalDownloadBytes(in manifest: ReleaseManifest) -> Int64 {
        manifest.components.reduce(Int64(0)) { $0 + $1.size }
    }

    static func resolution(width: Int, height: Int) -> String {
        "\(width) \u{00d7} \(height)"
    }

    static func androidAPILevel(in manifest: ReleaseManifest) -> String? {
        guard let component = manifest.components.first(where: { $0.id == "system-image" }) else {
            return nil
        }
        for part in component.installPath.split(separator: "/") where part.hasPrefix("android-") {
            return String(part.dropFirst("android-".count))
        }
        return nil
    }

    static func componentVersion(_ id: String, in manifest: ReleaseManifest) -> String? {
        manifest.components.first(where: { $0.id == id })?.version
    }

    static func byteCount(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: value)
    }
}

enum GameUpdateStatus: Equatable {
    case unchecked
    case checking
    case upToDate
    case available(version: String)
    case failed

    init(isChecking: Bool, availableVersion: String?, hasError: Bool, hasChecked: Bool) {
        if isChecking {
            self = .checking
        } else if let availableVersion {
            self = .available(version: availableVersion)
        } else if hasError {
            self = .failed
        } else if hasChecked {
            self = .upToDate
        } else {
            self = .unchecked
        }
    }
}

enum GameUpdateCheckPolicy {
    static let interval: TimeInterval = 30 * 60
    static let activationInterval: TimeInterval = 5 * 60

    static func isDue(lastChecked: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= interval
    }
}

enum LauncherL10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
}

enum LauncherBuildInfo {
    static var display: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
        return "v\(version) \u{00b7} build \(build)"
    }
}
