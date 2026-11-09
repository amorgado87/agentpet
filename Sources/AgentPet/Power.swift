import Foundation
import IOKit.ps

/// "Modo ahorro": when it applies, pets move less and everything polls more slowly.
enum Power {
    private static let lock = NSLock()
    private static var checked = Date.distantPast
    private static var autoSaving = false

    static var saving: Bool {
        switch Prefs.saver {
        case "always": return true
        case "off": return false
        default:
            lock.lock(); defer { lock.unlock() }
            if Date().timeIntervalSince(checked) > 10 {
                checked = Date()
                autoSaving = ProcessInfo.processInfo.isLowPowerModeEnabled || onBattery()
            }
            return autoSaving
        }
    }

    private static func onBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }
}
