import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        applyDockPolicy()
        buildMainMenu()
        buildStatusItem()
        PetManager.shared.start()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applyDockPolicy()
        }
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    // MARK: dock / menus

    private func applyDockPolicy() {
        let want: NSApplication.ActivationPolicy = Prefs.dockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != want { NSApp.setActivationPolicy(want) }
    }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu(); appItem.submenu = app
        app.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Salir de AgentPet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = main
    }

    /// Menu bar icons are monochrome templates: the sprite as a solid silhouette with the dark parts (eyes, outline) cut out,
    /// so macOS tints it for light/dark menu bars like every other app.
    static func menuBarIcon() -> NSImage {
        let k = 2                                   // pixels per sprite pixel (retina)
        let w = canvasW * k, h = canvasH * k
        let pal = Palette.make(tint: "claude", variant: 0, skin: .claude)
        guard let src = SpriteExport.bitmap(width: w, height: h, draw: { ctx in
            drawSprite(ctx: ctx, scale: CGFloat(k), origin: .zero, visual: .stand, t: 0, dir: 1, vy: 0, palette: pal)
        }), let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              true else { return NSImage() }
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        if let d = ctx.data?.assumingMemoryBound(to: UInt8.self) {
            for i in 0..<(w * h) {
                let a = Int(d[i * 4 + 3])
                // premultiplied: brightness relative to alpha
                let lum = a == 0 ? 0 : (Int(d[i * 4]) * 3 + Int(d[i * 4 + 1]) * 6 + Int(d[i * 4 + 2])) / 10 * 255 / a
                let solid = a > 128 && lum > 70
                d[i * 4] = 0; d[i * 4 + 1] = 0; d[i * 4 + 2] = 0; d[i * 4 + 3] = solid ? 255 : 0
            }
        }
        guard let out = ctx.makeImage() else { return NSImage() }
        let img = NSImage(cgImage: out, size: NSSize(width: CGFloat(canvasW) * 0.85, height: CGFloat(canvasH) * 0.85))
        img.isTemplate = true
        return img
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = Self.menuBarIcon()
        statusItem.button?.image = img
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let n = PetManager.shared.agents.filter { $0.parentKey == nil }.count
        let header = NSMenuItem(title: n == 0 ? "Sin agentes en marcha" : "\(n) agente\(n == 1 ? "" : "s") en marcha", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for a in PetManager.shared.agents {
            let item = NSMenuItem(title: "   \(a.label): \(a.text)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(item("Añadir una mascota", #selector(addPet)))
        menu.addItem(item(Prefs.paused ? "Reanudar mascotas" : "Pausar mascotas", #selector(togglePause)))
        let demo = item("Modo demo (agentes simulados)", #selector(toggleDemo))
        demo.state = Prefs.demo ? .on : .off
        menu.addItem(demo)
        menu.addItem(.separator())
        menu.addItem(item("Ajustes…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir de AgentPet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    // MARK: actions

    @objc func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: host)
            w.title = "Ajustes de AgentPet"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func togglePause() { UserDefaults.standard.set(!Prefs.paused, forKey: "paused") }
    @objc func showUsageNow() { PetManager.shared.showUsageNow() }
    @objc func toggleUsage() { UserDefaults.standard.set(!Prefs.usage, forKey: "usage") }
    @objc func toggleDemo() { UserDefaults.standard.set(!Prefs.demo, forKey: "demo") }
    @objc func addPet() { PetManager.shared.addPet() }
}
