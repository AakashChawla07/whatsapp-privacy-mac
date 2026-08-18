import Foundation
import OSLog
import PrivacyCore

/// Every loggable fact. Payloads are enums and numbers only — there is intentionally no case that
/// accepts a `String`, so WhatsApp content cannot reach the logs (requirements §37).
public enum LogEvent: Sendable, Equatable {
    case appStarted
    case phaseChanged(from: ProtectionPhase.Tag, to: ProtectionPhase.Tag)
    case whatsAppLaunched
    case whatsAppTerminated
    case windowTracked
    case windowLost
    case layoutDetected(strategy: StrategyID, confidence: DetectionConfidence, rows: Int, durationMs: Int)
    case detectionFailed(DetectionFailure)
    case coverageApplied(tier: CoverageTier, regions: Int)
    case permission(trusted: Bool)
    case settingsLoaded(SettingsLoadResult)
    case settingsSaved
    case loginItemUpdateFailed
    case effectNotYetImplemented(Effect.Kind)
    case degradedModeEntered

    public enum Category: String, Sendable {
        case lifecycle, detection, overlay, permission, settings
    }

    public var category: Category {
        switch self {
        case .appStarted, .phaseChanged, .whatsAppLaunched, .whatsAppTerminated, .effectNotYetImplemented: .lifecycle
        case .windowTracked, .windowLost, .layoutDetected, .detectionFailed, .degradedModeEntered: .detection
        case .coverageApplied: .overlay
        case .permission: .permission
        case .settingsLoaded, .settingsSaved, .loginItemUpdateFailed: .settings
        }
    }

    public var defaultLevel: OSLogType {
        switch self {
        case .detectionFailed, .loginItemUpdateFailed, .degradedModeEntered: .error
        case .effectNotYetImplemented, .coverageApplied, .layoutDetected: .debug
        default: .info
        }
    }

    /// Built only from static text, enum raw values and numbers.
    public var message: String {
        switch self {
        case .appStarted: "App started."
        case .phaseChanged(let from, let to): "Phase \(from.rawValue) -> \(to.rawValue)."
        case .whatsAppLaunched: "WhatsApp launched."
        case .whatsAppTerminated: "WhatsApp terminated."
        case .windowTracked: "WhatsApp window detected."
        case .windowLost: "WhatsApp window lost."
        case .layoutDetected(let strategy, let confidence, let rows, let ms):
            "Sidebar bounds updated: strategy=\(strategy.rawValue) confidence=\(confidence) rows=\(rows) \(ms)ms."
        case .detectionFailed(let failure): "Layout detection failed: \(failure.rawValue)."
        case .coverageApplied(let tier, let regions): "Overlay regions: \(regions) (\(tier.rawValue))."
        case .permission(let trusted): "Accessibility trusted: \(trusted)."
        case .settingsLoaded(let result): "Settings loaded: \(result)."
        case .settingsSaved: "Settings saved."
        case .loginItemUpdateFailed: "Launch-at-login update failed."
        case .effectNotYetImplemented(let kind): "Effect not yet implemented: \(kind.rawValue)."
        case .degradedModeEntered: "Detection unreliable; safe fallback mode."
        }
    }
}

public enum PrivacyLog {
    public static let subsystem = "com.privacyblur.WhatsAppPrivacyBlur"

    /// Opt-in in-memory buffer for user-exported diagnostics. Never written to disk automatically.
    public static let diagnostics = DiagnosticsBuffer(capacity: 500)

    public static func record(_ event: LogEvent, level: OSLogType? = nil) {
        let logger = Logger(subsystem: subsystem, category: event.category.rawValue)
        let message = event.message
        logger.log(level: level ?? event.defaultLevel, "\(message, privacy: .public)")
        diagnostics.append(message)
    }
}

public final class DiagnosticsBuffer: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let date: Date
        public let message: String
    }

    private let lock = NSLock()
    private let capacity: Int
    private var entries: [Entry] = []
    private var enabled = false

    public init(capacity: Int) {
        self.capacity = capacity
    }

    public var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set {
            lock.withLock {
                enabled = newValue
                if !newValue { entries.removeAll() }
            }
        }
    }

    func append(_ message: String) {
        lock.withLock {
            guard enabled else { return }
            entries.append(Entry(date: Date(), message: message))
            if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        }
    }

    public func snapshot() -> [Entry] {
        lock.withLock { entries }
    }

    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot())
    }
}
