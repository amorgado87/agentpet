import AppKit

// Developer helpers: `AgentPet --sheet out.png` renders every animation; `--icon size out.png` renders the app icon.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--sheet"), args.count > i + 1 {
    let skin = args.firstIndex(of: "--skin").flatMap { Skin(rawValue: args[$0 + 1]) } ?? .claude
    SpriteExport.sheet(to: args[i + 1], skin: skin)
    exit(0)
}
if let i = args.firstIndex(of: "--icon"), args.count > i + 2, let size = Int(args[i + 1]) {
    SpriteExport.icon(size: size, to: args[i + 2])
    exit(0)
}

if let i = args.firstIndex(of: "--poof"), args.count > i + 1 {
    let cell = 5, cw = canvasW * cell + 16, ch = canvasH * cell + 16, n = 7
    let img = SpriteExport.bitmap(width: cw * n, height: ch) { ctx in
        ctx.setFillColor(hex(0xF3EEE6)); ctx.fill(CGRect(x: 0, y: 0, width: cw * n, height: ch))
        for k in 0..<n {
            var fx = SpriteFX(); fx.poof = CGFloat(k) / CGFloat(n - 1) * 0.95 + 0.02
            drawSprite(ctx: ctx, scale: CGFloat(cell), origin: CGPoint(x: k * cw + 8, y: 8), visual: .stand, t: 1, dir: 1, vy: 0,
                       palette: Palette.make(tint: "auto", variant: 0, skin: .claude), fx: fx)
        }
    }
    if let img { SpriteExport.writePNG(img, to: args[i + 1]) }
    exit(0)
}

if args.contains("--statusline") {
    LimitsStore.runStatusLine()
    exit(0)
}

if let i = args.firstIndex(of: "--bubble"), args.count > i + 1 {
    _ = NSApplication.shared
    Prefs.register()
    let pet = Pet(key: "t", x: 100, y: 100)
    pet.age = 1; pet.grounded = true
    let now = CACurrentMediaTime()
    pet.bubble = Bubble(header: "mascota", text: args.contains("--notext") ? "" : "Editando Router.swift", until: nil, start: now - 5)
    if args.contains("--notext") { pet.bubble = nil }
    LimitsStore.shared.refresh(now: 0, force: true)
    pet.usageStart = now - 1; pet.usageUntil = now + 5
    let v = pet.view
    if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
    }
    exit(0)
}

if let i = args.firstIndex(of: "--menubar"), args.count > i + 1 {
    _ = NSApplication.shared
    let img = AppDelegate.menuBarIcon()
    if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        // preview on a light and a dark menu bar, 8x
        let k = 8, w = cg.width, h = cg.height
        let out = SpriteExport.bitmap(width: w * k * 2 + 40, height: h * k + 20) { ctx in
            for (n, bg, fg) in [(0, 0xEDEDED, 0x000000), (1, 0x2B2B2B, 0xFFFFFF)] as [(Int, UInt32, UInt32)] {
                let x0 = CGFloat(n * (w * k + 20)) + 10
                ctx.setFillColor(hex(bg)); ctx.fill(CGRect(x: x0 - 10, y: 0, width: CGFloat(w * k + 20), height: CGFloat(h * k + 20)))
                ctx.saveGState(); ctx.interpolationQuality = .none
                ctx.clip(to: CGRect(x: x0, y: 10, width: CGFloat(w * k), height: CGFloat(h * k)), mask: cg)
                ctx.setFillColor(hex(fg)); ctx.fill(CGRect(x: x0, y: 10, width: CGFloat(w * k), height: CGFloat(h * k)))
                ctx.restoreGState()
            }
        }
        if let out { SpriteExport.writePNG(out, to: args[i + 1]) }
    }
    exit(0)
}

if args.contains("--agents") {
    Prefs.register()
    let procs = ClaudeCodeProvider.processList()
    print("processes:", procs.count)
    for a in ClaudeCodeProvider().poll() { print(a) }
    if let i = args.firstIndex(of: "--analyze"), args.count > i + 1, let tail = ClaudeCodeProvider.readTail(path: args[i + 1]) {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: args[i + 1]))?[.modificationDate] as? Date ?? Date()
        print("entries:", tail.count, ClaudeCodeProvider.analyze(entries: tail, mtime: mtime, now: Date(), hasShellChild: false))
    }
    exit(0)
}

if args.contains("--social") {
    _ = NSApplication.shared
    Prefs.register()
    let world = World(); world.refresh(includeWindows: false)
    let a = Pet(key: "a", x: 300, y: 0), b = Pet(key: "b", x: 900, y: 0)
    a.grounded = true; b.grounded = true
    var now = 0.0
    var log: [String] = []
    for i in 0..<(60 * 40) {
        now += 1.0 / 60
        if i == 60 { a.startVisit(b, now: now) }
        a.step(dt: 1.0 / 60, now: now, world: world); b.step(dt: 1.0 / 60, now: now, world: world)
        if i % 60 == 0 { log.append(String(format: "t=%2.0f a=%4.0f %@ | b=%4.0f %@", now, a.x, "\(a.social)".prefix(14) as CVarArg, b.x, "\(b.social)".prefix(14) as CVarArg)) }
    }
    print(log.joined(separator: "\n"))
    exit(0)
}

if args.contains("--selftest") {
    _ = NSApplication.shared
    Prefs.register()
    let world = World()
    world.injected = [CGRect(x: 300, y: 200, width: 500, height: 300), CGRect(x: 900, y: 150, width: 400, height: 380)]
    world.refresh(includeWindows: true)
    print("screens:", world.screens.map { "\($0)" })
    print("window platforms:", world.windowSegments.count)
    for s in world.windowSegments.prefix(6) { print("  ", s) }
    let pet = Pet(key: "t", x: world.union.midX, y: world.union.maxY - 200)
    var now = 0.0
    var visited = Set<String>()
    var jumps = 0
    var wasGrounded = false
    for i in 0..<(60 * 90) {
        now += 1.0 / 60
        if i % 2 == 0 { world.refresh(includeWindows: true) }
        pet.step(dt: 1.0 / 60, now: now, world: world)
        if pet.grounded { visited.insert("\(pet.surface)") }
        if wasGrounded && !pet.grounded { jumps += 1 }
        wasGrounded = pet.grounded
        if i % 300 == 0 { print(String(format: "t=%.0f x=%.0f y=%.0f grounded=%@ surface=%@ mode=%@", now, pet.x, pet.y, "\(pet.grounded)", "\(pet.surface)", "\(pet.mode)")) }
    }
    print("surfaces visited:", visited.count, visited.sorted().prefix(5), "takeoffs:", jumps)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
