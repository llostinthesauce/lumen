import Foundation

struct TelemetrySettings {
    static var shared = TelemetrySettings()
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let hudEnabled = "telemetry.hud.enabled"
        static let samplingSeconds = "telemetry.sampling.seconds"
    }
    
    var hudEnabled: Bool {
        get { defaults.object(forKey: Keys.hudEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.hudEnabled) }
    }
    
    var samplingSeconds: TimeInterval {
        get {
            let val = defaults.double(forKey: Keys.samplingSeconds)
            return val > 0 ? val : 1.0
        }
        set {
            defaults.set(max(0.25, newValue), forKey: Keys.samplingSeconds)
        }
    }
}
