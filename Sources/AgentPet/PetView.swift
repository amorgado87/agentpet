import AppKit
import QuartzCore

final class PetPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Let the pet hang partly off-screen (e.g. at the screen edge).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class PetView: NSView {
    weak var pet: Pet?
    private var lastSignature = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // 8-bit backing store: the default wide-colour (16-bit float) layer costs several times more to composite
        layer?.contentsFormat = CALayerContentsFormat(rawValue: "RGBA8Uncompressed")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: redraw policy

    func refresh(now: Double) {
        guard let pet else { return }
        let sig = signature(pet, now: now)
        if sig != lastSignature {
            lastSignature = sig
            needsDisplay = true
        }
    }

    private func bubbleAlpha(_ pet: Pet, now: Double) -> CGFloat {
        guard Prefs.bubbles, let b = pet.bubble else { return 0 }
        var a = min(1, (now - b.start) / 0.2)
        if let u = b.until { a = min(a, max(0, (u - now) / 0.4)) }
        if let d = pet.dying { a = min(a, max(0, 1 - d / 0.2)) }
        return CGFloat(max(0, a))
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1e6) }
        if n >= 10_000 { return String(format: "%.0fk", Double(n) / 1e3) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1e3) }
        return "\(n)"
    }

    private func usageAlpha(_ pet: Pet, now: Double) -> CGFloat {
        guard Prefs.usage, now < pet.usageUntil, LimitsStore.shared.available else { return 0 }
        var a = min(1, (now - pet.usageStart) / 0.2)
        a = min(a, max(0, (pet.usageUntil - now) / 0.4))
        if let d = pet.dying { a = min(a, max(0, 1 - d / 0.2)) }
        return CGFloat(max(0, a))
    }

    private func signature(_ pet: Pet, now: Double) -> String {
        // animation frames per second: sleeping pets barely change, and saving energy halves the rest
        let fps = pet.visual == .sleep ? 3.0 : (Power.saving ? 6.0 : 15.0)
        let frame = Int(pet.t * fps)
        let a = Int(bubbleAlpha(pet, now: now) * 8) * 100 + Int(usageAlpha(pet, now: now) * 8)
        let lim = LimitsStore.shared.rows.map { Int($0.value) }
        let fxs = Int(spawnValue(pet) * 12) * 100 + Int((pet.dying ?? 0) * 20)
        return "\(pet.visual.rawValue)|\(frame)|\(pet.dir)|\(pet.vy > 0)|\(a)|\(pet.bubble?.text ?? "")|\(pet.bubble?.header ?? "")|\(Prefs.scale)|\(Prefs.bubbleFont)|\(pet.slot)|\(Prefs.tint)|\(Prefs.borders)|\(Prefs.variants)|\(fxs)|\(Int(pet.heart * 10))|\(lim)"
    }

    private func spawnValue(_ pet: Pet) -> CGFloat { CGFloat(min(1, pet.age / 0.35)) }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let pet, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let L = PetLayout.current
        let s = L.scale
        let ox = ((bounds.width - CGFloat(canvasW) * s) / 2).rounded()
        let oy = L.foot

        var fx = SpriteFX()
        fx.spawn = spawnValue(pet)
        if let d = pet.dying { fx.poof = CGFloat(min(1, d / 0.45)) }
        fx.heart = CGFloat(max(0, min(1, pet.heart)))

        let pal = Palette.make(tint: Prefs.tint, variant: Prefs.variants ? pet.slot : 0)
        drawSprite(ctx: ctx, scale: s, origin: CGPoint(x: ox, y: oy), visual: pet.visual,
                   t: pet.t, dir: pet.dir >= 0 ? 1 : -1, vy: pet.vy, palette: pal, fx: fx)

        let now = CACurrentMediaTime()
        let alpha = bubbleAlpha(pet, now: now)
        let ua = usageAlpha(pet, now: now)
        if alpha > 0 || ua > 0 {
            let b = (alpha > 0 ? pet.bubble : nil) ?? Bubble(header: nil, text: "", until: nil, start: 0)
            drawBubble(b, alpha: alpha, usage: ua > 0 ? LimitsStore.shared.rows : [], usageAlpha: ua,
                       anchorX: bounds.midX, bottom: oy + CGFloat(canvasH) * s + 4, ctx: ctx)
        }
    }

    private func drawBubble(_ b: Bubble, alpha textAlpha: CGFloat, usage: [LimitsStore.Row], usageAlpha: CGFloat, anchorX: CGFloat, bottom: CGFloat, ctx: CGContext) {
        let fontSize = Prefs.bubbleFont
        let bodyFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let headFont = NSFont.monospacedSystemFont(ofSize: max(9, fontSize - 2.5), weight: .bold)
        let ink = NSColor(srgbRed: 0.165, green: 0.106, blue: 0.082, alpha: 1)
        let accent = NSColor(srgbRed: 0.72, green: 0.36, blue: 0.24, alpha: 1)

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: ink, .paragraphStyle: para]
        let headAttrs: [NSAttributedString.Key: Any] = [.font: headFont, .foregroundColor: accent, .paragraphStyle: para]

        let alpha = max(textAlpha, usageAlpha)
        let hasText = textAlpha > 0 && !b.text.isEmpty
        let maxW: CGFloat = min(bounds.width - 28, 250)
        let body = NSAttributedString(string: b.text, attributes: bodyAttrs)
        let wrap = NSMutableParagraphStyle(); wrap.lineBreakMode = .byWordWrapping
        let wrapAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .paragraphStyle: wrap]
        let measured = (b.text as NSString).boundingRect(with: CGSize(width: maxW, height: 1000),
                                                         options: [.usesLineFragmentOrigin], attributes: wrapAttrs)
        let lineH = ceil(bodyFont.boundingRectForFont.height)
        let lines = min(2, max(1, Int(ceil(measured.height / lineH))))
        let textW = hasText ? min(maxW, ceil(measured.width) + 2) : 0
        let bodyH = hasText ? CGFloat(lines) * lineH : 0
        let rowH: CGFloat = 11
        let rowsH: CGFloat = usage.isEmpty ? 0 : CGFloat(usage.count) * rowH + (hasText ? 3 : 0)

        var headH: CGFloat = 0
        var headW: CGFloat = 0
        var head: NSAttributedString?
        if hasText, let h = b.header, !h.isEmpty {
            let a = NSAttributedString(string: h.uppercased(), attributes: headAttrs)
            head = a
            headH = ceil(headFont.boundingRectForFont.height) + 1
            headW = min(maxW, ceil(a.size().width) + 2)
        }

        // border thickness = one sprite pixel, so bubble and pet share the same outline weight
        let bd = Prefs.scale
        let padX: CGFloat = bd + 6, padY: CGFloat = bd + 3
        let w = max(textW, headW, usage.isEmpty ? 0 : 112, 40) + padX * 2
        let h = bodyH + headH + rowsH + padY * 2
        var bx = (anchorX - w / 2).rounded()
        bx = max(4, min(bounds.width - w - 4, bx))
        let by = bottom + bd * 2
        let rect = CGRect(x: bx, y: by, width: w, height: h)

        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.setShouldAntialias(false)
        let dark = CGColor(srgbRed: 0.165, green: 0.106, blue: 0.082, alpha: 1)
        let light = CGColor(srgbRed: 1.0, green: 0.973, blue: 0.94, alpha: 1)

        func stepped(_ r: CGRect, _ c: CGColor, cut: CGFloat) {
            ctx.setFillColor(c)
            ctx.fill(r.insetBy(dx: cut, dy: 0))
            ctx.fill(r.insetBy(dx: 0, dy: cut))
        }
        let borders = Prefs.borders
        if borders {
            stepped(rect, dark, cut: bd)
            stepped(rect.insetBy(dx: bd, dy: bd), light, cut: bd)
        } else {
            // borderless: a soft shadow keeps the bubble readable on any background
            ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: CGColor(gray: 0, alpha: 0.28))
            stepped(rect, light, cut: bd)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }

        // tail: three stepped rows pointing at the pet
        let cx = max(rect.minX + 4 * bd, min(rect.maxX - 4 * bd, anchorX)).rounded()
        if borders {
            for i in 0..<3 {
                let wDark = CGFloat(6 - 2 * i) * bd
                ctx.setFillColor(dark)
                ctx.fill(CGRect(x: cx - wDark / 2, y: by - CGFloat(i + 1) * bd, width: wDark, height: bd))
            }
            for i in 0..<2 {
                let wLight = CGFloat(4 - 2 * i) * bd
                ctx.setFillColor(light)
                ctx.fill(CGRect(x: cx - wLight / 2, y: by - CGFloat(i + 1) * bd, width: wLight, height: i == 0 ? 2 * bd : bd))
            }
        } else {
            for i in 0..<3 {
                let w = CGFloat(5 - 2 * i) * bd
                ctx.setFillColor(light)
                ctx.fill(CGRect(x: cx - w / 2, y: by - CGFloat(i + 1) * bd + (i == 0 ? 0 : 0), width: w, height: i == 0 ? 2 * bd : bd))
            }
        }
        ctx.restoreGState()

        // text (anti-aliased)
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.setShouldAntialias(true)
        var ty = rect.maxY - padY
        if let head {
            ty -= headH
            head.draw(with: CGRect(x: bx + padX, y: ty, width: w - padX * 2, height: headH), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        ty -= bodyH
        if hasText {
            ctx.setAlpha(textAlpha)
            body.draw(with: CGRect(x: bx + padX, y: ty, width: w - padX * 2, height: bodyH), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        ctx.restoreGState()

        // plan usage: two tiny rows, "5h ▮▮▮▯▯ 53%"
        if !usage.isEmpty {
            ctx.saveGState()
            ctx.setAlpha(usageAlpha)
            if hasText { ty -= 3 }
            let small = NSFont.monospacedSystemFont(ofSize: max(8, fontSize - 3.5), weight: .bold)
            let la: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: accent]
            let pa: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: ink]
            let x0 = bx + padX, x1 = bx + w - padX
            let labelW: CGFloat = 19, pctW: CGFloat = 28
            let track = CGColor(srgbRed: 0.90, green: 0.84, blue: 0.77, alpha: 1)
            for row in usage {
                ty -= rowH
                ctx.setShouldAntialias(true)
                (row.name as NSString).draw(at: CGPoint(x: x0, y: ty), withAttributes: la)
                let txt = row.percent ? "\(Int(row.value.rounded()))%" : Self.compact(Int(row.value))
                let tw = (txt as NSString).size(withAttributes: pa).width
                (txt as NSString).draw(at: CGPoint(x: x1 - tw, y: ty), withAttributes: pa)
                guard row.percent else { continue }       // token counts have no limit to fill a bar against
                let v = row.value
                ctx.setShouldAntialias(false)
                let bx0 = x0 + labelW, bw = x1 - pctW - bx0, bh: CGFloat = 4
                let by0 = ty + (rowH - bh) / 2 + 1
                ctx.setFillColor(track)
                ctx.fill(CGRect(x: bx0, y: by0, width: bw, height: bh))
                ctx.setFillColor(v >= 80 ? CGColor(srgbRed: 0.78, green: 0.22, blue: 0.18, alpha: 1) : accent.cgColor)
                ctx.fill(CGRect(x: bx0, y: by0, width: (bw * CGFloat(v / 100)).rounded(), height: bh))
            }
            ctx.restoreGState()
        }
    }

    // MARK: mouse (drag, throw, click, context menu)

    override func mouseDown(with event: NSEvent) {
        pet?.beginDrag(mouse: NSEvent.mouseLocation, now: CACurrentMediaTime())
    }

    override func mouseDragged(with event: NSEvent) {
        pet?.drag(to: NSEvent.mouseLocation, now: CACurrentMediaTime())
    }

    override func mouseUp(with event: NSEvent) {
        pet?.endDrag(now: CACurrentMediaTime())
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        if let a = pet?.agent {
            let item = NSMenuItem(title: "\(a.label) — \(a.text)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }
        let usage = menu.addItem(withTitle: Prefs.usage ? "Ocultar límites de uso" : "Mostrar límites de uso", action: #selector(AppDelegate.toggleUsage), keyEquivalent: "")
        usage.target = NSApp.delegate
        if Prefs.usage {
            let now = menu.addItem(withTitle: "Ver uso ahora", action: #selector(AppDelegate.showUsageNow), keyEquivalent: "")
            now.target = NSApp.delegate
        }
        menu.addItem(withTitle: "Ajustes…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        let pause = menu.addItem(withTitle: Prefs.paused ? "Reanudar mascotas" : "Pausar mascotas", action: #selector(AppDelegate.togglePause), keyEquivalent: "")
        pause.target = NSApp.delegate
        menu.items.first(where: { $0.action == #selector(AppDelegate.openSettings) })?.target = NSApp.delegate
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Salir de AgentPet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
