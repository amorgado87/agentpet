import AppKit
import CoreGraphics

// MARK: - Pixel canvas

/// Logical size of the sprite canvas, in "pixels" (each one is `scale` screen points).
let canvasW = 24
let canvasH = 20

func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255,
            green: CGFloat((v >> 8) & 255) / 255,
            blue: CGFloat(v & 255) / 255,
            alpha: a)
}

enum Skin: String, CaseIterable {
    case claude, cat, robot, ghost, dog, poop, mouse, duck

    var name: String {
        switch self {
        case .claude: return "Claude pixelado"
        case .cat: return "Gato"
        case .robot: return "Robot"
        case .ghost: return "Fantasma"
        case .dog: return "Perro"
        case .poop: return "Caca"
        case .mouse: return "Ratón"
        case .duck: return "Pato"
        }
    }
    /// Natural colours (body, shade)
    var natural: (UInt32, UInt32) {
        switch self {
        case .claude: return (0xD97757, 0xB05A3C)
        case .cat: return (0x9A9AA6, 0x6F6F7C)
        case .robot: return (0x8FB4D9, 0x6489B0)
        case .ghost: return (0xF4F4FA, 0xC6C6D8)
        case .dog: return (0xC99A5E, 0x9C7240)
        case .poop: return (0x8B5A2B, 0x5E3A1A)
        case .mouse: return (0xB9B9C2, 0x8C8C97)
        case .duck: return (0xF3C93A, 0xD1A41C)
        }
    }
    static var current: Skin { Skin(rawValue: Prefs.skin) ?? .claude }
}

struct Palette {
    var body: CGColor
    var shade: CGColor
    var skin: Skin = .claude

    static let ink = hex(0x2A1B15)
    static let outline = hex(0x2A1B15, 0.92)

    /// id "auto" = the skin's natural colours
    static let tints: [(id: String, name: String, body: UInt32, shade: UInt32)] = [
        ("claude", "Naranja Claude", 0xD97757, 0xB05A3C),
        ("blue", "Azul", 0x5B8DEF, 0x3E67B8),
        ("green", "Verde", 0x5FB57A, 0x3F8A58),
        ("purple", "Violeta", 0x9B7BE0, 0x7456B8),
        ("pink", "Rosa", 0xE87AA8, 0xB8567F),
        ("yellow", "Amarillo", 0xE5B93C, 0xB8902A),
        ("gray", "Gris", 0xA7A7AD, 0x78787F),
    ]

    static func make(tint: String, variant: Int, skin: Skin = .current) -> Palette {
        if tint == "auto" && variant == 0 {
            return Palette(body: hex(skin.natural.0), shade: hex(skin.natural.1), skin: skin)
        }
        var idx = tints.firstIndex(where: { $0.id == tint }) ?? 0
        if variant > 0 { idx = (idx + variant) % tints.count }
        let t = tints[idx]
        return Palette(body: hex(t.body), shade: hex(t.shade), skin: skin)
    }
}

/// Drawing helper. All coordinates are in canvas pixels, y = 0 at the TOP of the canvas.
struct Px {
    let ctx: CGContext
    let s: CGFloat
    let ox: CGFloat
    let oy: CGFloat          // y of the canvas BOTTOM in ctx coordinates
    let outline: Bool
    var dx = 0
    var dy = 0

    func r(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: CGColor, a: CGFloat = 1) {
        let X = x + dx, Y = y + dy
        if outline {
            if a < 0.9 { return }
            ctx.setFillColor(Palette.outline)
            ctx.fill(rect(X - 1, Y - 1, w + 2, h + 2))
        } else {
            ctx.setFillColor(a < 1 ? (c.copy(alpha: a) ?? c) : c)
            ctx.fill(rect(X, Y, w, h))
        }
    }

    func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGRect {
        CGRect(x: ox + CGFloat(x) * s,
               y: oy + CGFloat(canvasH - y - h) * s,
               width: CGFloat(w) * s,
               height: CGFloat(h) * s)
    }

    func glyph(_ rows: [String], _ x: Int, _ y: Int, _ c: CGColor, a: CGFloat = 1) {
        for (j, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() where ch == "#" {
                r(x + i, y + j, 1, 1, c, a: a)
            }
        }
    }
}

enum Glyphs {
    static let z = ["###", "..#", ".#.", "#..", "###"]
    static let bang = ["##", "##", "##", "..", "##"]
    static let heart = ["##.##", "#####", ".###.", "..#.."]
    static let check = ["......#", ".....#.", "#...#..", ".#.#...", "..#...."]
    static let plus = [".#.", "###", ".#."]
    static let gearA = ["..#..", ".###.", "##.##", ".###.", "..#.."]
    static let gearB = ["#...#", ".###.", ".#.#.", ".###.", "#...#"]
}

// MARK: - Visual states

enum Visual: String, CaseIterable {
    case stand, walk, air, landing, drag, sleep, hop
    case thinking, coding, running, reading, searching, planning, delegating, responding, waiting, done, error

    var label: String {
        switch self {
        case .stand: return "Quieto"
        case .walk: return "Caminando"
        case .air: return "Saltando"
        case .landing: return "Aterrizando"
        case .drag: return "Agarrado"
        case .sleep: return "Durmiendo"
        case .hop: return "Contento"
        case .thinking: return "Pensando"
        case .coding: return "Programando"
        case .running: return "Ejecutando"
        case .reading: return "Leyendo"
        case .searching: return "Buscando"
        case .planning: return "Planificando"
        case .delegating: return "Delegando"
        case .responding: return "Respondiendo"
        case .waiting: return "Esperando permiso"
        case .done: return "¡Terminado!"
        case .error: return "Error"
        }
    }
}

enum EyeStyle { case open, closed, happy, surprised }

struct SpriteFX {
    var spawn: CGFloat = 1       // 0...1 pop-in
    var poof: CGFloat = 0        // 0...1 vanishing
    var heart: CGFloat = 0       // 0...1 heart floating
}

// MARK: - Renderer

/// Draws the pixel Claude mascot. `origin` is the bottom-left of the canvas in ctx coordinates.
func drawSprite(ctx: CGContext, scale s: CGFloat, origin: CGPoint,
                visual: Visual, t: Double, dir: Int, vy: CGFloat,
                palette pal: Palette, fx: SpriteFX = SpriteFX()) {
    ctx.saveGState()
    ctx.setShouldAntialias(false)
    ctx.interpolationQuality = .none

    let cx = origin.x + CGFloat(canvasW) * s / 2
    var drawBody = true

    if fx.poof > 0 {
        // "puf": the pet swells for a blink, vanishes and bursts into pixel confetti + smoke
        let p = fx.poof
        if p < 0.16 {
            let k = 1 + 0.3 * (p / 0.16)
            ctx.translateBy(x: cx, y: origin.y)
            ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: -cx, y: -origin.y)
        } else {
            drawBody = false
        }
    } else if fx.spawn < 1 {
        let k = max(0.05, fx.spawn)
        ctx.translateBy(x: cx, y: origin.y)
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: -cx, y: -origin.y)
    }

    if drawBody {
        for pass in (Prefs.borders ? 0 : 1)..<2 {
            let px = Px(ctx: ctx, s: s, ox: origin.x, oy: origin.y, outline: pass == 0)
            paint(px, visual: visual, t: t, dir: dir, vy: vy, pal: pal, fx: fx)
        }
    }
    ctx.restoreGState()

    // effects drawn in plain screen space
    ctx.saveGState()
    ctx.setShouldAntialias(false)
    let cy = origin.y + 9 * s
    func snap(_ v: CGFloat) -> CGFloat { (v / s).rounded() * s }

    if fx.poof >= 0.12 {
        let q = min(1, (fx.poof - 0.12) / 0.88)
        // confetti in the pet's own colours
        let cols = [pal.body, pal.shade, hex(0xF4EDE3), hex(0xFFE08A)]
        for i in 0..<16 {
            let ang = Double(i) / 16 * .pi * 2 + Double(i % 3) * 0.2
            let speed = CGFloat(6 + (i * 7) % 9)
            let dist = speed * (1 - (1 - q) * (1 - q)) * s * 1.3
            let size = max(1, (3 - 2.6 * q).rounded()) * s * (i % 2 == 0 ? 1 : 0.67)
            let x = cx + CGFloat(cos(ang)) * dist
            let y = cy + CGFloat(sin(ang)) * dist * 0.85 - q * q * 5 * s   // slight fall
            ctx.setFillColor(cols[i % cols.count].copy(alpha: max(0, 1 - q * q)) ?? cols[0])
            ctx.fill(CGRect(x: snap(x), y: snap(y), width: size, height: size))
        }
        // smoke ring
        for i in 0..<8 {
            let ang = Double(i) / 8 * .pi * 2 + 0.3
            let dist = (4 + 10 * q) * s
            let size = (4 - 2 * q).rounded() * s
            let x = cx + CGFloat(cos(ang)) * dist
            let y = cy + CGFloat(sin(ang)) * dist * 0.8
            ctx.setFillColor(hex(0xF2EEE8, max(0, 0.9 * (1 - q))))
            ctx.fill(CGRect(x: snap(x - size / 2), y: snap(y - size / 2), width: size, height: size))
        }
    } else if fx.spawn < 1 {
        let q = 1 - fx.spawn
        for i in 0..<8 {
            let ang = Double(i) / 8 * .pi * 2
            let dist = q * 11 * s
            let size = max(1, 3 - q * 2.4) * s
            ctx.setFillColor(hex(0xEDE6DC, max(0, 1 - q)))
            ctx.fill(CGRect(x: snap(cx + CGFloat(cos(ang)) * dist), y: snap(cy + CGFloat(sin(ang)) * dist * 0.8), width: size, height: size))
        }
    }
    ctx.restoreGState()
}

private func paint(_ p0: Px, visual: Visual, t: Double, dir: Int, vy: CGFloat, pal: Palette, fx: SpriteFX) {
    var p = p0
    let ink = Palette.ink
    let white = hex(0xFFFFFF)

    var eyes: EyeStyle = .open
    var lx = dir, ly = 0
    var bodyDY = 0, squash = 0
    var armL = 0, armR = 0
    var lift = [false, false, false, false]
    var showArms = true

    let blink = fmod(t, 3.8) < 0.12
    let beat = Int(t * 9)

    switch visual {
    case .stand:
        squash = (Int(t * 1.1) % 2 == 0) ? 0 : 1
        if blink { eyes = .closed }
        let ph = Int(t / 2.4) % 7
        if ph == 2 { lx = -1 } else if ph == 4 { lx = 1 }
    case .walk:
        let ph = Int(t * 9) % 4
        lift = [ph == 1, ph == 3, ph == 1, ph == 3]
        armL = ph == 1 ? -1 : (ph == 3 ? 1 : 0)
        armR = -armL
        if blink { eyes = .closed }
    case .air:
        bodyDY = -1
        lift = [true, true, true, true]
        if vy > 0 { armL = -2; armR = -2 } else { eyes = .surprised; armL = -3 + (beat % 2); armR = -3 + ((beat + 1) % 2) }
    case .landing:
        squash = 2
        armL = 1; armR = 1
    case .drag:
        eyes = .surprised
        let k = Int(t * 12) % 2
        lift = [k == 0, k == 1, k == 0, k == 1]
        armL = -3 + k; armR = -3 + (1 - k)
        bodyDY = -1
    case .sleep:
        bodyDY = 2; eyes = .closed; lx = 0
    case .hop:
        eyes = .happy; armL = -4; armR = -4
    case .thinking:
        lx = 1; ly = -1
        if blink { eyes = .closed }
    case .coding, .running, .reading, .planning:
        bodyDY = 2
        lx = 0
        if visual == .reading { lx = Int((sin(t * 3) * 1.4).rounded()); ly = 1 }
        else if visual == .planning { ly = 1 }
        else if blink { eyes = .closed }
        showArms = false
    case .searching:
        lx = 1; armR = -3
    case .delegating:
        armL = -4 + (beat % 2); armR = -4 + ((beat + 1) % 2)
        lx = Int((sin(t * 2.2) * 1.4).rounded())
    case .responding:
        armL = (beat % 4 < 2) ? -1 : 1
        armR = -armL
        lx = 0
    case .waiting:
        lx = 0
        armR = -3 + ((Int(t * 5) % 2) * 2 - 1)
        if blink { eyes = .closed }
    case .done:
        eyes = .happy
        armL = -4 + (beat % 2); armR = -4 + ((beat + 1) % 2)
    case .error:
        eyes = .surprised
        armL = -3; armR = -3
        p.dx = (Int(t * 22) % 2 == 0) ? -1 : 1
    }

    // whole-sprite vertical bounce for lively states
    switch visual {
    case .waiting:
        let c = fmod(t, 1.2)
        if c < 0.2 { p.dy = -Int((sin(c / 0.2 * .pi) * 2).rounded()) }
    case .done:
        p.dy = -Int((abs(sin(t * 6)) * 3).rounded())
    case .hop:
        p.dy = -Int((abs(sin(t * 8)) * 2).rounded())
    default: break
    }

    let body = pal.body, shade = pal.shade

    // legs
    let skin = pal.skin
    var bx = 5, bw = 14, sq = 0
    var legX = [6, 9, 13, 16]
    var legColor = shade
    if skin == .duck { legColor = hex(0xF28C28) }
    let bodyTop = 8 + bodyDY + squash + sq
    let bodyH = 9 - squash - sq
    let bodyBottom = 8 + bodyDY + 9
    let poopBase = min(20, bodyBottom + 3)        // the poop has no legs: it sits on the ground
    let ey = skin == .poop ? max(0, poopBase - 9 + ly) : max(bodyTop + 1, 10 + bodyDY + squash + sq + ly)
    let facing = dir >= 0 ? 1 : -1

    // things that live behind the body
    switch skin {
    case .cat:
        let sway = Int((sin(t * 3) * 1.5).rounded())
        p.r(19, bodyTop + 4, 2, 2, shade)
        p.r(21, bodyTop + 2 + (sway > 0 ? 0 : 1), 2, 4, shade)
    case .dog:
        let wag = Int(t * 8) % 2
        p.r(19, bodyTop + 3, 2, 2, shade)
        p.r(20 + wag, bodyTop, 2, 4, shade)
    case .mouse:
        let sway = Int((sin(t * 2.5) * 1.5).rounded())
        let tx = facing > 0 ? 1 : 20
        p.r(tx, bodyBottom - 2, 3, 1, hex(0xE9A0B0))
        p.r(tx + (facing > 0 ? -1 : 3), bodyBottom - 3 - (sway > 0 ? 1 : 0), 1, 2, hex(0xE9A0B0))
    case .duck:
        p.r(19, bodyTop + 2, 2, 2, shade)
    default: break
    }

    if skin == .ghost {
        // no legs: the body flows down into a wavy skirt
        let wave = Int(t * 5) % 2
        if bodyBottom < 19 { p.r(5, bodyBottom, 14, 19 - bodyBottom, body) }
        for i in 0..<7 where (i + wave) % 2 == 0 { p.r(5 + i * 2, 19, 2, 1, body) }
    } else if skin != .poop {
        for i in 0..<4 {
            let top = bodyBottom
            var bottom = lift[i] ? 19 : 20
            bottom = min(bottom, top + 3)
            if bottom > top {
                p.r(legX[i], top, 2, bottom - top, legColor)
                if skin == .duck { p.r(legX[i] - 1, bottom - 1, 4, 1, legColor) }   // webbed feet
            }
        }
    }

    // body
    if skin == .poop {
        let b = body, sh = shade
        let wob = (Int(t * 3) % 2 == 0) ? 0 : 1
        p.r(5, poopBase - 5, 14, 5, b)
        p.r(5, poopBase - 1, 14, 1, sh)
        p.r(7, poopBase - 9, 10, 4, b)
        p.r(7, poopBase - 6, 10, 1, sh)
        p.r(9, poopBase - 12, 6, 3, b)
        p.r(9, poopBase - 10, 6, 1, sh)
        p.r(11, poopBase - 14 + wob, 3, 2, b)
        p.r(12, poopBase - 15 + wob, 1, 1, b)
        p.r(6, poopBase - 4, 2, 1, hex(0xB5834A))      // shine
        p.r(8, poopBase - 8, 2, 1, hex(0xB5834A))
    } else {
        p.r(bx, bodyTop, bw, bodyH, body)
        p.r(bx, bodyTop + bodyH - 1, bw, 1, shade)
    }

    switch skin {
    case .claude, .poop: break
    case .cat:
        p.r(5, bodyTop - 2, 3, 2, body); p.r(5, bodyTop - 3, 1, 1, body)
        p.r(16, bodyTop - 2, 3, 2, body); p.r(18, bodyTop - 3, 1, 1, body)
        p.r(6, bodyTop - 1, 1, 1, hex(0xF2A7B8)); p.r(17, bodyTop - 1, 1, 1, hex(0xF2A7B8))
        p.r(9, bodyTop + bodyH - 3, 6, 2, hex(0xEDE6DC))
    case .robot:
        p.r(11, bodyTop - 3, 2, 3, shade)
        p.r(10, bodyTop - 5, 4, 2, (Int(t * 2) % 2 == 0) ? hex(0xFF6B6B) : hex(0x8A3A3A))
        p.r(5, bodyTop, 14, 1, hex(0xB7D0EA))
        p.r(6, bodyTop + bodyH - 3, 1, 1, shade); p.r(17, bodyTop + bodyH - 3, 1, 1, shade)
    case .ghost:
        p.r(5, bodyTop, 14, 1, hex(0xFFFFFF))
    case .dog:
        let ear = hex(0x6E4A28)
        p.r(3, bodyTop, 3, 5, ear); p.r(18, bodyTop, 3, 5, ear)          // floppy ears
        p.r(8, ey + 2, 8, 4, hex(0xE9CFA6))                              // muzzle
        p.r(5, bodyTop, 14, 1, hex(0xDDB57A))
    case .mouse:
        let pink = hex(0xF2B3C0)
        p.r(4, bodyTop - 3, 4, 3, body); p.r(16, bodyTop - 3, 4, 3, body)
        p.r(5, bodyTop - 2, 2, 2, pink); p.r(17, bodyTop - 2, 2, 2, pink)
        p.r(9, bodyTop + bodyH - 3, 6, 2, hex(0xE4E4EA))
    case .duck:
        p.r(11, bodyTop - 2, 1, 2, body); p.r(12, bodyTop - 3, 1, 2, body)   // tuft
        p.r(5, bodyTop, 14, 1, hex(0xFFE27A))
    }

    // eyes
    let ex1 = 8 + max(-1, min(1, lx)), ex2 = 14 + max(-1, min(1, lx))
    var eyeColor = ink
    if skin == .robot {
        p.r(7, ey - 1, 10, 5, hex(0x1B2733))          // visor
        eyeColor = hex(0x6FF3FF)
    }
    for ex in [ex1, ex2] {
        switch eyes {
        case .open: p.r(ex, ey, 2, 3, eyeColor)
        case .closed: p.r(ex, ey + 1, 2, 1, eyeColor)
        case .happy:
            p.r(ex - 1 + (ex == ex1 ? 0 : 1) , ey + 2, 1, 1, eyeColor)
            p.r(ex + (ex == ex1 ? 0 : 1), ey + 1, 1, 1, eyeColor)
            p.r(ex + 1 + (ex == ex1 ? 0 : 1), ey + 2, 1, 1, eyeColor)
        case .surprised:
            p.r(ex, ey - 1, 2, 4, eyeColor)
            p.r(ex, ey - 1, 1, 1, white)
        }
    }
    switch skin {
    case .cat:
        p.r(11, ey + 2, 2, 1, hex(0xF2A7B8))
        p.r(3, ey + 2, 2, 1, ink); p.r(19, ey + 2, 2, 1, ink)
    case .ghost:
        if eyes == .open { p.r(11, ey + 3, 2, 1, hex(0x9A9AB5)) }
    case .dog:
        p.r(11, ey + 2, 2, 2, ink)                                       // nose
        if eyes == .happy || visual == .done || visual == .hop { p.r(12, ey + 4, 2, 2, hex(0xF2788C)) }   // tongue
    case .mouse:
        p.r(11, ey + 2, 2, 1, hex(0xE9788F))
        p.r(2, ey + 2, 3, 1, hex(0x6F6F7A)); p.r(19, ey + 2, 3, 1, hex(0x6F6F7A))
    case .duck:
        let beak = hex(0xF28C28)
        p.r(8, ey + 2, 8, 2, beak)                                       // flat bill
        p.r(8, ey + 3, 8, 1, hex(0xD16F10))
    case .poop:
        p.r(10, ey + 3, 4, 1, ink)                                       // smile
        p.r(9, ey + 2, 1, 1, ink); p.r(14, ey + 2, 1, 1, ink)
        // stink lines
        for i in 0..<2 {
            let ph = fmod(t * 0.8 + Double(i) * 0.5, 1)
            p.r(4 + i * 14, poopBase - 8 - Int(ph * 6), 1, 2, hex(0x7FD66B), a: ph < 0.7 ? 1 : 0.5)
        }
    default: break
    }

    // arms
    if showArms && skin != .poop {
        let armCol = skin == .duck ? shade : body
        p.r(3, 11 + bodyDY + armL, 2, 3, armCol)
        p.r(19, 11 + bodyDY + armR, 2, 3, armCol)
    } else if skin == .poop && (armL < -1 || armR < -1) {
        p.r(3, poopBase - 9 + armL, 2, 3, body)
        p.r(19, poopBase - 9 + armR, 2, 3, body)
    }

    // MARK: props
    switch visual {
    case .coding:
        let lid = hex(0x3A3A42), rim = hex(0x6A6A75)
        p.r(6, 15, 12, 5, lid)
        p.r(6, 15, 12, 1, rim)
        p.r(11, 16, 2, 2, body)               // logo on the lid
        let k = beat % 2
        p.r(6, 13 + (k == 0 ? 0 : 1), 2, 2, shade)
        p.r(16, 13 + (k == 1 ? 0 : 1), 2, 2, shade)
        // floating code bits
        let cols: [UInt32] = [0x7EE787, 0x79C0FF, 0xFFA657, 0xD2A8FF, 0xFF7B72]
        for i in 0..<5 {
            let ph = fmod(t * 0.9 + Double(i) * 0.2, 1)
            let x = 5 + i * 3 + (i % 2)
            let y = 12 - Int(ph * 11)
            p.r(x, y, 1, 1, hex(cols[i]), a: ph < 0.7 ? 1 : 0.5)
        }
    case .running:
        let frame = hex(0x4A4A53), screen = hex(0x14161A), green = hex(0x7EE787)
        p.r(5, 15, 14, 5, frame)
        p.r(6, 16, 12, 3, screen)
        p.r(7, 15, 1, 1, hex(0xFF5F57)); p.r(9, 15, 1, 1, hex(0xFEBC2E)); p.r(11, 15, 1, 1, hex(0x28C840))
        let sc = Int(t * 3.5)
        for row in 0..<3 {
            let len = 3 + ((sc + row) * 5) % 7
            p.r(7, 16 + row, len, 1, row == 2 ? hex(0xE6EDF3) : green, a: 1)
        }
        if Int(t * 2) % 2 == 0 { p.r(7 + 3 + ((sc + 2) * 5) % 7 + 1, 18, 1, 1, green) }
        let k = beat % 2
        p.r(3, 14 + k, 2, 2, shade)
        p.r(19, 14 + (1 - k), 2, 2, shade)
    case .reading:
        let page = hex(0xF4EAD8), line = hex(0xB5A48A), spine = hex(0xC9B79C)
        p.r(6, 15, 12, 5, page)
        p.r(11, 15, 2, 5, spine)
        p.r(7, 16, 4, 1, line); p.r(7, 18, 3, 1, line)
        p.r(13, 16, 4, 1, line); p.r(13, 18, 3, 1, line)
        let hr = 16 + (Int(t * 1.6) % 2) * 2
        p.r(7, hr, 3, 1, body)
        p.r(4, 16, 2, 3, shade); p.r(18, 16, 2, 3, shade)
    case .planning:
        let board = hex(0x9A6B44), paper = hex(0xFFFDF7), green = hex(0x3FB950)
        p.r(7, 14, 10, 6, board)
        p.r(11, 13, 2, 1, hex(0x8A8A93))
        p.r(8, 15, 8, 4, paper)
        let n = Int(t * 1.4) % 4
        for i in 0..<2 {
            p.r(10, 16 + i * 2, 5, 1, hex(0xBBB5A8))
            if i < n { p.r(8 + (i == 0 ? 0 : 0), 16 + i * 2, 1, 1, green) }
        }
        if n >= 2 { p.r(15, 15, 1, 1, hex(0xFFC93C)) }
        p.r(4, 16, 3, 3, shade); p.r(17, 16, 3, 3, shade)
    case .searching:
        let glass = hex(0xDCE8FF), lens = hex(0xBFE3FF), wood = hex(0x8A5A3A)
        let lx0 = 19 + Int((sin(t * 2.0) * 1.2).rounded())
        let ly0 = 3 + Int((cos(t * 1.3) * 1.0).rounded())
        p.r(lx0 + 1, ly0, 3, 1, glass); p.r(lx0 + 1, ly0 + 4, 3, 1, glass)
        p.r(lx0, ly0 + 1, 1, 3, glass); p.r(lx0 + 4, ly0 + 1, 1, 3, glass)
        p.r(lx0 + 1, ly0 + 1, 3, 3, lens, a: 0.55)
        p.r(lx0 + 1, ly0 + 5, 1, 1, wood); p.r(lx0, ly0 + 6, 1, 1, wood)
    case .thinking:
        let n = Int(t * 2.2) % 4
        p.r(13, 6, 1, 1, white); p.r(14, 4, 1, 1, white)
        p.r(15, 0, 8, 4, white); p.r(14, 1, 10, 2, white)
        for i in 0..<min(n, 3) { p.r(16 + i * 2 + i, 1, 1, 2, ink) }
    case .delegating:
        p.glyph(Int(t * 3) % 2 == 0 ? Glyphs.gearA : Glyphs.gearB, 17, 1, hex(0xC9CCD4))
        p.glyph(Int(t * 3) % 2 == 0 ? Glyphs.gearB : Glyphs.gearA, 1, 3, hex(0xC9CCD4))
    case .responding:
        p.r(15, 0, 8, 4, white); p.r(14, 1, 10, 2, white)
        p.r(15, 4, 2, 1, white); p.r(14, 5, 1, 1, white)
        let len = 2 + Int(t * 5) % 5
        p.r(16, 1, len, 1, ink); p.r(16, 2, max(1, len - 2), 1, ink)
    case .waiting:
        if Int(t * 2.5) % 5 != 4 { p.glyph(Glyphs.bang, 11, 0, hex(0xFFC93C)) }
    case .done:
        p.glyph(Glyphs.check, 9, 0, hex(0x6EE7A0))
        let tw = Int(t * 4) % 3
        for (i, pos) in [(2, 3), (21, 5), (20, 0), (1, 10)].enumerated() where (i + tw) % 3 != 0 {
            p.glyph(Glyphs.plus, pos.0, pos.1, hex(0xFFE08A))
        }
    case .error:
        p.glyph(Glyphs.bang, 11, 0, hex(0xFF5F57))
        p.r(19, 9, 1, 2, hex(0x79C0FF))
    case .sleep:
        for i in 0..<2 {
            let ph = fmod(t * 0.45 + Double(i) * 0.5, 1)
            p.glyph(Glyphs.z, 17 + Int(ph * 3), 6 - Int(ph * 6), hex(0xCFE1FF), a: ph < 0.75 ? 1 : 0.5)
        }
    default: break
    }

    if fx.heart > 0 {
        p.glyph(Glyphs.heart, 10, 3 - Int((1 - fx.heart) * 3) , hex(0xFF5C7A))
    }
}

// MARK: - Sheet / icon export (used for verification and the app icon)

enum SpriteExport {
    static func bitmap(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(ctx)
        return ctx.makeImage()
    }

    static func writePNG(_ img: CGImage, to path: String) {
        let rep = NSBitmapImageRep(cgImage: img)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    static func sheet(to path: String, skin: Skin = .claude) {
        let cell = 5
        let cw = canvasW * cell + 16, ch = canvasH * cell + 28
        let all = Visual.allCases
        let cols = 6
        let rows = (all.count + cols - 1) / cols
        let img = bitmap(width: cw * cols, height: ch * rows) { ctx in
            ctx.setFillColor(hex(0xF3EEE6)); ctx.fill(CGRect(x: 0, y: 0, width: cw * cols, height: ch * rows))
            for (i, v) in all.enumerated() {
                let cx = (i % cols) * cw, cy = (rows - 1 - i / cols) * ch
                if (i % 2 == 0) { ctx.setFillColor(hex(0xFFFFFF, 0.5)); ctx.fill(CGRect(x: cx, y: cy, width: cw, height: ch)) }
                drawSprite(ctx: ctx, scale: CGFloat(cell), origin: CGPoint(x: cx + 8, y: cy + 8),
                           visual: v, t: 1.37, dir: 1, vy: -1, palette: Palette.make(tint: "auto", variant: 0, skin: skin))
                let str = NSAttributedString(string: v.rawValue, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold), .foregroundColor: NSColor.black])
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                str.draw(at: CGPoint(x: cx + 6, y: cy + canvasH * cell + 12))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        if let img { writePNG(img, to: path) }
    }

    static func icon(size: Int, to path: String) {
        let img = bitmap(width: size, height: size) { ctx in
            let S = CGFloat(size)
            let rr = CGPath(roundedRect: CGRect(x: S * 0.06, y: S * 0.06, width: S * 0.88, height: S * 0.88),
                            cornerWidth: S * 0.2, cornerHeight: S * 0.2, transform: nil)
            ctx.addPath(rr); ctx.clip()
            ctx.setFillColor(hex(0xF6EFE6)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
            ctx.setFillColor(hex(0xE9DFD1)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S * 0.2))
            let scale = floor(S * 0.88 * 0.84 / CGFloat(canvasW))
            let ox = (S - scale * CGFloat(canvasW)) / 2
            let oy = S * 0.2 - scale * 2
            drawSprite(ctx: ctx, scale: scale, origin: CGPoint(x: ox, y: oy), visual: .hop, t: 0.2, dir: 1, vy: 0,
                       palette: Palette.make(tint: "claude", variant: 0))
        }
        if let img { writePNG(img, to: path) }
    }
}
