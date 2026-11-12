import Foundation
import CoreGraphics

/// Central place for user preferences. SwiftUI binds to the same keys with @AppStorage.
enum Prefs {
    static let d = UserDefaults.standard

    static func register() {
        d.register(defaults: [
            "scale": 4.0, "speed": 1.0, "gravity": 1.0, "energy": 1.0,
            "useWindows": true, "jumpWindows": true, "sleepy": true,
            "bubbles": true, "bubbleProject": true, "bubbleFont": 12.0, "idleBubble": true,
            "maxPets": 6, "borders": true, "social": true, "hideIdle": 20.0, "alwaysShow": true, "claudeEnabled": true, "claudeChat": false, "saver": "auto", "usage": true, "usageDelta": 5.0,
            "demo": false, "demoCount": 3,
            "tint": "auto", "skin": "robot", "variants": true,
            "dockIcon": false, "paused": false, "pollSeconds": 3.0,
        ])
    }

    static var scale: CGFloat { CGFloat(min(8, max(2, d.double(forKey: "scale").rounded()))) }
    static var speed: CGFloat { CGFloat(d.double(forKey: "speed")) }
    static var gravity: CGFloat { CGFloat(max(0.3, d.double(forKey: "gravity"))) }
    static var energy: Double { max(0.2, d.double(forKey: "energy")) }
    static var useWindows: Bool { d.bool(forKey: "useWindows") }
    static var jumpWindows: Bool { d.bool(forKey: "jumpWindows") }
    static var sleepy: Bool { d.bool(forKey: "sleepy") }
    static var bubbles: Bool { d.bool(forKey: "bubbles") }
    static var bubbleProject: Bool { d.bool(forKey: "bubbleProject") }
    static var bubbleFont: CGFloat { CGFloat(d.double(forKey: "bubbleFont")) }
    static var idleBubble: Bool { d.bool(forKey: "idleBubble") }
    static var hideIdle: Double { d.double(forKey: "hideIdle") }
    static var social: Bool { d.bool(forKey: "social") }
    static var borders: Bool { d.bool(forKey: "borders") }
    static var maxPets: Int { max(1, d.integer(forKey: "maxPets")) }
    static var alwaysShow: Bool { d.bool(forKey: "alwaysShow") }
    static var claudeEnabled: Bool { d.bool(forKey: "claudeEnabled") }
    static var claudeChat: Bool { d.bool(forKey: "claudeChat") }
    static var saver: String { d.string(forKey: "saver") ?? "auto" }
    static var usage: Bool { d.bool(forKey: "usage") }
    static var usageDelta: Double { max(1, d.double(forKey: "usageDelta")) }
    static var demo: Bool { d.bool(forKey: "demo") }
    static var demoCount: Int { max(1, d.integer(forKey: "demoCount")) }
    static var skin: String { d.string(forKey: "skin") ?? "robot" }
    static var tint: String { d.string(forKey: "tint") ?? "auto" }
    static var variants: Bool { d.bool(forKey: "variants") }
    static var dockIcon: Bool { d.bool(forKey: "dockIcon") }
    static var paused: Bool { d.bool(forKey: "paused") }
    static var pollSeconds: Double { max(0.5, d.double(forKey: "pollSeconds")) }
}
