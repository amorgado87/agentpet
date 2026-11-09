import AppKit

struct Bubble {
    var header: String?
    var text: String
    var until: Double?      // nil = stays while the agent is busy
    var start: Double
}

struct PetLayout {
    let scale: CGFloat
    let width: CGFloat
    let foot: CGFloat        // distance from window bottom to the feet
    let height: CGFloat
    static var current: PetLayout {
        let s = Prefs.scale
        let foot = s + 2
        return PetLayout(scale: s, width: 320, foot: foot, height: foot + CGFloat(canvasH) * s + 10 + 104 + 5 * s)
    }
}

final class Pet {
    var key: String
    var slot = 0

    // physics (Cocoa global coordinates, x = centre, y = feet)
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var grounded = false
    var surface: Surface = .floor
    var lastWinMinX: CGFloat = 0
    var dir: CGFloat = 1
    var landTimer = 0.0

    // behaviour
    enum Mode { case idle, walk, sleep, approach, stay, social }
    var mode: Mode = .idle
    var modeUntil = 0.0
    var dropAtEdge = false
    var target: Surface = .floor
    var targetX: CGFloat = 0

    // pet-to-pet interaction
    enum Social {
        case none
        case approaching(Pet)                  // walking over to say hi
        case waiting(Pet, Double)              // being visited
        case greet(Pet, Double)
        case play(Pet, Double, Bool)           // Bool: hops on even beats
        case chase(Pet, Double, Bool)          // Bool: true = runner
    }
    var social: Social = .none
    var nextBeat = 0.0

    // agent
    var agent: AgentSnapshot?
    var agentState: AgentState = .idle
    var bubble: Bubble?

    // life cycle / fx
    var t = Double.random(in: 0..<50)
    var age = 0.0
    var dying: Double?
    var heart = 0.0
    var usageStart = 0.0
    var usageUntil = 0.0

    // dragging
    var dragging = false
    var dragMoved: CGFloat = 0
    var dragStart = 0.0
    var samples: [(CGPoint, Double)] = []

    let panel: PetPanel
    let view: PetView

    init(key: String, x: CGFloat, y: CGFloat) {
        self.key = key
        self.x = x
        self.y = y
        let L = PetLayout.current
        panel = PetPanel(size: NSSize(width: L.width, height: L.height))
        view = PetView(frame: NSRect(x: 0, y: 0, width: L.width, height: L.height))
        view.pet = self
        panel.contentView = view
    }

    // MARK: - Derived

    var spriteH: CGFloat { CGFloat(canvasH) * Prefs.scale }
    var halfWidth: CGFloat { 8 * Prefs.scale }

    /// Area of the screen that reacts to the mouse (the sprite, not the bubble).
    var hitRect: CGRect {
        let s = Prefs.scale
        return CGRect(x: x - 10 * s, y: y - 2, width: 20 * s, height: 16 * s + 6)
    }

    var visual: Visual {
        if dragging { return .drag }
        if !grounded { return .air }
        if landTimer > 0 { return .landing }
        if agentState != .idle { return agentState.visual }
        if heart > 0 { return .hop }
        switch mode {
        case .sleep: return .sleep
        case .walk, .approach: return .walk
        case .social:
            switch social {
            case .approaching, .chase: return .walk
            default: return .stand
            }
        default: return .stand
        }
    }

    // MARK: - Agent binding

    func apply(_ snap: AgentSnapshot?, now: Double) {
        let old = agentState
        agent = snap
        agentState = snap?.state ?? .idle
        if (agentState == .idle && old != .idle) || (agentState == .done && old != .done) { showUsage(now: now) }

        if let s = snap, agentState != .idle {
            let header = Prefs.bubbleProject ? s.label : nil
            if bubble?.text != s.text || bubble?.header != header || bubble?.until != nil {
                bubble = Bubble(header: header, text: s.text, until: nil, start: bubble?.until == nil ? (bubble?.start ?? now) : now)
            }
            if mode == .sleep { mode = .idle }
            if agentState == .done && old != .done { hop(1.0) }
            if agentState == .waiting && old != .waiting { hop(0.6) }
        } else {
            if old != .idle, let s = snap, Prefs.idleBubble {
                bubble = Bubble(header: Prefs.bubbleProject ? s.label : nil, text: "Esperando órdenes…", until: now + 5, start: now)
            } else if bubble?.until == nil {
                bubble = nil
            }
        }
    }

    /// Briefly add the plan-usage bars to this pet's bubble.
    func showUsage(now: Double) {
        guard Prefs.usage else { return }
        LimitsStore.shared.refresh(now: now, force: true)   // pick up the freshest file
        guard LimitsStore.shared.available else { return }
        usageStart = now
        usageUntil = now + 7
    }

    func say(_ text: String, seconds: Double, now: Double) {
        bubble = Bubble(header: nil, text: text, until: now + seconds, start: now)
    }

    // MARK: - Physics + behaviour

    private var gravityPx: CGFloat { 2600 * Prefs.gravity }
    private var walkSpeed: CGFloat { 18 * Prefs.scale * Prefs.speed }

    func hop(_ power: CGFloat = 1) {
        guard grounded else { return }
        let h = spriteH * 0.7 * power
        vy = sqrt(2 * gravityPx * h)
        grounded = false
    }

    func step(dt: Double, now: Double, world: World) {
        t += dt
        age += dt
        if landTimer > 0 { landTimer -= dt }
        if heart > 0 { heart -= dt * 0.9 }
        if let d = dying { dying = d + dt; return }
        if dragging { return }

        if let b = bubble, let u = b.until, now > u { bubble = nil }

        let hw = halfWidth

        if grounded {
            // ride whatever we're standing on
            switch surface {
            case .floor:
                if let fy = world.floorY(at: x) { y = fy } else { clampToWorld(world) }
            case .window(let id):
                if let r = world.rects[id] {
                    x += r.minX - lastWinMinX
                    lastWinMinX = r.minX
                    y = r.maxY
                    if world.segment(window: id, containing: x, margin: -hw * 0.3) == nil { startFall() }
                } else {
                    startFall()
                }
            }
            if grounded { behave(dt: dt, now: now, world: world) }
        }

        if !grounded { fly(dt: dt, now: now, world: world) }
    }

    private func clampToWorld(_ world: World) {
        guard !world.union.isNull else { return }
        x = min(max(x, world.union.minX + halfWidth), world.union.maxX - halfWidth)
        if let fy = world.floorY(at: x) { y = fy }
    }

    private func startFall() {
        grounded = false
        vy = 0
    }

    private func fly(dt: Double, now: Double, world: World) {
        guard !world.union.isNull else { return }
        let hw = halfWidth
        vy -= gravityPx * CGFloat(dt)
        let prevY = y
        x += vx * CGFloat(dt)
        y += vy * CGFloat(dt)

        if x < world.union.minX + hw { x = world.union.minX + hw; vx = abs(vx) * 0.5 }
        if x > world.union.maxX - hw { x = world.union.maxX - hw; vx = -abs(vx) * 0.5 }
        let ceiling = world.union.maxY - spriteH
        if y > ceiling { y = ceiling; vy = min(vy, 0) }

        if vy <= 0, let (s, sy) = world.landing(x: x, prevY: prevY, y: y) {
            let impact = -vy
            y = sy
            if impact > 950 {                     // thrown hard: bounce once
                vy = impact * 0.32
                vx *= 0.7
                landTimer = 0.12
                surface = s
                return
            }
            grounded = true
            surface = s
            vy = 0
            vx = 0
            if case .window(let id) = s { lastWinMinX = world.rects[id]?.minX ?? 0 }
            if impact > 500 { landTimer = 0.18 }
            if mode == .social { /* keep playing */ }
            else if mode != .approach { mode = .idle; modeUntil = now + Double.random(in: 0.3...1.2) }
            else { mode = .idle; modeUntil = now + Double.random(in: 1...3) }
        }
    }

    private func behave(dt: Double, now: Double, world: World) {
        if agentState.isWorking {
            mode = .stay
            social = .none
            return
        }
        if mode == .stay { mode = .idle; modeUntil = now + 1.5 }

        switch mode {
        case .stay: break
        case .idle:
            if now >= modeUntil { pickNext(now: now, world: world) }
        case .sleep:
            if now >= modeUntil { mode = .idle; modeUntil = now + 1 }
        case .walk:
            walk(dx: dir * walkSpeed * CGFloat(dt), world: world, now: now)
            if now >= modeUntil { mode = .idle; modeUntil = now + Double.random(in: 1.2...4) / Prefs.energy }
        case .approach:
            approach(dt: dt, now: now, world: world)
        case .social:
            socialStep(dt: dt, now: now, world: world)
        }
    }

    // MARK: - Pets meeting each other

    private func friendOK(_ f: Pet) -> Bool {
        f.dying == nil && !f.dragging && f.agentState == .idle && f.mode == .social
    }

    private func endSocial(_ now: Double) {
        social = .none
        mode = .idle
        modeUntil = now + Double.random(in: 1...3)
    }

    /// Called by the manager: this pet decides to go and meet `friend`.
    func startVisit(_ friend: Pet, now: Double) {
        mode = .social; modeUntil = now + 9
        social = .approaching(friend)
        friend.mode = .social
        friend.social = .waiting(self, now + 9)
        friend.vx = 0
    }

    private func startInteraction(with f: Pet, now: Double) {
        let kind = Int.random(in: 0..<4)
        dir = f.x >= x ? 1 : -1
        f.dir = -dir
        switch kind {
        case 0:   // greet
            let until = now + 2.6
            social = .greet(f, until); f.social = .greet(self, until)
            heart = 1; f.heart = 1
            say("¡Hola!", seconds: 2, now: now); f.say(["¡Hey!", "¡Buenas!"].randomElement()!, seconds: 2, now: now)
            nextBeat = now + 0.15; f.nextBeat = now + 0.5
        case 1:   // play: alternate hops
            let until = now + 3.5
            social = .play(f, until, true); f.social = .play(self, until, false)
            say("¡Juguemos!", seconds: 2, now: now)
            nextBeat = now; f.nextBeat = now + 0.35
        case 2:   // tag: the visited one runs away
            let until = now + 3.2
            social = .chase(f, until, false); f.social = .chase(self, until, true)
            say("¡Te pillo!", seconds: 1.6, now: now); f.say("¡No!", seconds: 1.2, now: now)
        default:  // nap together
            let dur = Double.random(in: 10...20)
            say("Zzz…", seconds: 2, now: now)
            for pet in [self, f] { pet.social = .none; pet.mode = .sleep; pet.modeUntil = now + dur }
        }
    }

    private func socialStep(dt: Double, now: Double, world: World) {
        switch social {
        case .none:
            endSocial(now)
        case .approaching(let f):
            guard friendOK(f), f.grounded, f.surface == surface, now < modeUntil else { endSocial(now); f.endSocialIfWaiting(now); return }
            dir = f.x >= x ? 1 : -1
            if abs(f.x - x) < 12 * Prefs.scale { startInteraction(with: f, now: now) }
            else { walk(dx: dir * walkSpeed * 1.4 * CGFloat(dt), world: world, now: now) }
        case .waiting(let f, let until):
            guard friendOK(f) || f.mode == .social, now < until + 2, f.dying == nil else { endSocial(now); return }
            dir = f.x >= x ? 1 : -1
        case .greet(let f, let until):
            guard f.dying == nil, now < until else { endSocial(now); return }
            if now >= nextBeat { hop(0.5); nextBeat = now + 0.9 }
        case .play(let f, let until, _):
            guard f.dying == nil, now < until else { endSocial(now); return }
            if now >= nextBeat { hop(0.75); nextBeat = now + 0.7 }
        case .chase(let f, let until, let runner):
            guard f.dying == nil, now < until else { endSocial(now); return }
            let away: CGFloat = f.x >= x ? -1 : 1
            if runner {
                dir = away
                walk(dx: dir * walkSpeed * 2.2 * CGFloat(dt), world: world, now: now)
            } else {
                dir = f.x >= x ? 1 : -1
                if abs(f.x - x) > 6 * Prefs.scale { walk(dx: dir * walkSpeed * 2.3 * CGFloat(dt), world: world, now: now) }
            }
        }
    }

    fileprivate func endSocialIfWaiting(_ now: Double) {
        if case .waiting = social { endSocial(now) }
    }

    private func walk(dx: CGFloat, world: World, now: Double) {
        let nx = x + dx
        let hw = halfWidth
        switch surface {
        case .floor:
            let probe = nx + (dx > 0 ? hw * 0.5 : -hw * 0.5)
            if world.floorY(at: probe) == nil { dir = -dir } else { x = nx }
        case .window(let id):
            guard let seg = world.segment(window: id, containing: x, margin: -hw) else { return }
            let e = 2 * Prefs.scale
            if nx < seg.x0 + e || nx > seg.x1 - e {
                if dropAtEdge {
                    x = nx
                    if nx < seg.x0 - hw * 0.1 || nx > seg.x1 + hw * 0.1 {
                        vx = dir * walkSpeed
                        startFall()
                    }
                } else {
                    dir = -dir
                }
            } else {
                x = nx
            }
        }
    }

    private func pickNext(now: Double, world: World) {
        let e = Prefs.energy
        let r = Double.random(in: 0..<1)
        if Power.saving && agentState == .idle {
            // saving energy: nobody wanders, they just nap (agents that are working keep their animation)
            mode = .sleep
            modeUntil = now + Double.random(in: 40...90)
            return
        }
        if Prefs.sleepy && r < 0.07 {
            mode = .sleep
            modeUntil = now + Double.random(in: 12...30)
            return
        }
        if r < 0.45 {
            startWalk(now: now, world: world)
        } else if r < 0.62 {
            mode = .idle
            modeUntil = now + Double.random(in: 1.5...4) / e
        } else if r < 0.74 {
            dir = Bool.random() ? 1 : -1
            vx = dir * walkSpeed * 1.4
            hop(0.8)
            mode = .idle
            modeUntil = now + 1.2
        } else {
            if !startApproach(now: now, world: world) { startWalk(now: now, world: world) }
        }
    }

    private func startWalk(now: Double, world: World) {
        mode = .walk
        modeUntil = now + Double.random(in: 2...6)
        // prefer walking away from the nearest wall
        if !world.union.isNull {
            let mid = world.union.midX
            dir = Double.random(in: 0..<1) < 0.7 ? (x < mid ? 1 : -1) : (Bool.random() ? 1 : -1)
        } else {
            dir = Bool.random() ? 1 : -1
        }
        if case .window = surface { dropAtEdge = Prefs.jumpWindows && Double.random(in: 0..<1) < 0.5 } else { dropAtEdge = false }
    }

    private func startApproach(now: Double, world: World) -> Bool {
        guard Prefs.useWindows && Prefs.jumpWindows else { return false }
        let maxRise = spriteH * 3
        let hw = halfWidth
        var cands: [Segment] = []
        for seg in world.windowSegments + world.floorSegments {
            if seg.surface == surface && seg.surface == .floor { continue }
            if seg.surface == surface, seg.surface != .floor { continue }
            if seg.y - y > maxRise { continue }
            if seg.x1 - seg.x0 < 2 * hw + 24 { continue }
            let gap = max(seg.x0 - x, x - seg.x1, 0)
            if gap > 460 { continue }
            if seg.surface == .floor && seg.y > y - 40 { continue }   // only "drop" to floor, never hop onto it level
            cands.append(seg)
        }
        guard let seg = cands.randomElement() else { return false }
        let lo = seg.x0 + hw + 12, hi = seg.x1 - hw - 12
        guard hi > lo else { return false }
        let jitter = CGFloat.random(in: -140...140)
        targetX = min(max(x + jitter, lo), hi)
        target = seg.surface
        mode = .approach
        modeUntil = now + 7
        return true
    }

    private func flight(dy: CGFloat) -> (vy0: CGFloat, time: CGFloat) {
        let g = gravityPx
        let apex = max(dy, 0) + spriteH * 0.4
        let vy0 = sqrt(2 * g * apex)
        let time = vy0 / g + sqrt(2 * max(apex - dy, 1) / g)
        return (vy0, time)
    }

    private func approach(dt: Double, now: Double, world: World) {
        guard now < modeUntil, let ty = world.surfaceY(target, at: targetX) else {
            mode = .idle; modeUntil = now + 1; return
        }
        let (vy0, time) = flight(dy: ty - y)
        let maxVx = 160 * Prefs.scale
        let reach = maxVx * time * 0.8
        let dist = targetX - x
        if abs(dist) <= reach {
            vx = max(-maxVx, min(maxVx, dist / max(time, 0.2)))
            vy = vy0
            dir = dist >= 0 ? 1 : -1
            grounded = false
            // keep `.approach` so landing uses the shorter idle
        } else {
            dir = dist >= 0 ? 1 : -1
            dropAtEdge = false
            let before = x
            walk(dx: dir * walkSpeed * 1.5 * CGFloat(dt), world: world, now: now)
            if x == before { mode = .idle; modeUntil = now + 1 }   // blocked
        }
    }

    // MARK: - Dragging

    func beginDrag(mouse: CGPoint, now: Double) {
        dragging = true
        grounded = false
        vx = 0; vy = 0
        dragMoved = 0
        dragStart = now
        samples = [(mouse, now)]
        mode = .idle
        social = .none
    }

    func drag(to mouse: CGPoint, now: Double) {
        if let l = samples.last { dragMoved += abs(mouse.x - l.0.x) + abs(mouse.y - l.0.y) }
        x = mouse.x
        y = mouse.y - 14 * Prefs.scale
        samples.append((mouse, now))
        if samples.count > 8 { samples.removeFirst() }
    }

    func endDrag(now: Double) {
        dragging = false
        if dragMoved < 5 && now - dragStart < 0.4 {
            // it was a click
            heart = 1
            samples = []
            vy = 0
            grounded = false
            hop(0.7)
            if bubble == nil { say(["¡Hola!", "¿Qué tal?", "¡Cosquillas!", "Estoy aquí 👋"].randomElement()!, seconds: 2, now: now) }
            return
        }
        if let first = samples.first(where: { now - $0.1 < 0.12 }), let last = samples.last, last.1 > first.1 + 0.01 {
            let d = last.1 - first.1
            vx = max(-2600, min(2600, (last.0.x - first.0.x) / CGFloat(d)))
            vy = max(-2600, min(2600, (last.0.y - first.0.y) / CGFloat(d)))
        }
        samples = []
        modeUntil = now + 1
    }

    // MARK: - Window sync

    func syncWindow(now: Double) {
        let L = PetLayout.current
        let frame = NSRect(x: (x - L.width / 2).rounded(), y: (y - L.foot).rounded(), width: L.width, height: L.height)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        view.refresh(now: now)
    }
}
