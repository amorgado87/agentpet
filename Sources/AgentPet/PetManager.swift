import AppKit
import Combine

/// Owns every pet: reconciles them against the live agents, runs the 60 Hz simulation and moves the windows.
final class PetManager: ObservableObject {
    static let shared = PetManager()

    @Published private(set) var agents: [AgentSnapshot] = []
    private(set) var pets: [Pet] = []
    private let world = World()
    private let monitor = AgentMonitor()
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var tickCount = 0
    private var wasPaused = false
    private var nextMatch = 0.0
    private var shownLimits: (Double, Double) = (-1, -1)
    private var lastActive: [String: Double] = [:]   // agent key -> last time it was busy

    /// Drops agents that have been idle for a while so the desktop doesn't fill up with sleepy pets.
    private func dropIdle(_ snaps: [AgentSnapshot], now: Double) -> [AgentSnapshot] {
        let limit = Prefs.hideIdle
        for s in snaps {
            if s.state != .idle { lastActive[s.key] = now }
            else if lastActive[s.key] == nil { lastActive[s.key] = -1e9 }   // first seen already idle: don't show it
        }
        lastActive = lastActive.filter { k, _ in snaps.contains { $0.key == k } }
        guard limit > 0 else { return snaps }
        return snaps.filter { s in
            // keep the parent of a visible sub-agent
            s.state != .idle || now - (lastActive[s.key] ?? -1e9) < limit
                || snaps.contains { $0.parentKey == s.key && $0.state != .idle }
        }
    }

    func start() {
        monitor.onUpdate = { [weak self] snaps in
            DispatchQueue.main.async { self?.reconcile(snaps) }
        }
        monitor.start()
        setRate(30)
        reconcile([])
    }

    private var rate = 0.0

    /// The simulation only needs a high rate while something actually moves; resting pets tick slowly.
    private func setRate(_ hz: Double) {
        guard hz != rate else { return }
        rate = hz
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / hz, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 1.0 / hz * 0.25   // lets the system coalesce wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func isResting(_ p: Pet) -> Bool {
        guard p.dying == nil, p.grounded, !p.dragging, p.landTimer <= 0, p.heart <= 0, p.age > 0.5, abs(p.vx) < 1 else { return false }
        if case .none = p.social {} else { return false }
        return p.mode == .sleep || p.mode == .idle
    }

    // MARK: reconcile

    private func reconcile(_ incoming: [AgentSnapshot]) {
        let now = CACurrentMediaTime()
        // Keep parents before their children, honour the pet limit.
        var desired = dropIdle(incoming, now: now)
        desired.sort { ($0.parentKey == nil ? 0 : 1, $0.key) < ($1.parentKey == nil ? 0 : 1, $1.key) }
        desired = Array(desired.prefix(Prefs.maxPets))
        agents = desired

        let live = pets.filter { $0.dying == nil }
        let desiredKeys = Set(desired.map(\.key))
        // hand-added pets ("extra:") belong to the user, not to an agent: never treat them as leftovers
        var orphans = live.filter { !desiredKeys.contains($0.key) && !$0.key.hasPrefix("extra:") }

        // existing pets keep their agent, new agents adopt orphans (so "home" turns into the first agent)
        for snap in desired {
            if let p = live.first(where: { $0.key == snap.key }) {
                p.apply(snap, now: now)
                continue
            }
            if let o = orphans.first(where: { $0.key == "home" }) ?? orphans.first {
                orphans.removeAll { $0 === o }
                o.key = snap.key
                o.apply(snap, now: now)
            } else {
                let parent = snap.parentKey.flatMap { k in pets.first { $0.key == k } } ?? live.first
                let p = spawn(key: snap.key, near: parent)
                p.apply(snap, now: now)
            }
        }

        // leftovers
        var keepHome = desired.isEmpty && Prefs.alwaysShow
        for o in orphans {
            if keepHome && (o.key == "home" || orphans.first(where: { $0.key == "home" }) == nil) {
                o.key = "home"
                o.apply(nil, now: now)
                keepHome = false
            } else {
                o.dying = 0.0001
            }
        }
        if desired.isEmpty && Prefs.alwaysShow && !pets.contains(where: { $0.dying == nil }) {
            _ = spawn(key: "home", near: nil)
        }
        assignSlots()
    }

    private func assignSlots() {
        var taken = Set<Int>()
        for p in pets where p.dying == nil { taken.insert(p.slot) }
        var seen = Set<Int>()
        for p in pets where p.dying == nil {
            if seen.contains(p.slot) {
                var n = 0
                while taken.contains(n) { n += 1 }
                p.slot = n
                taken.insert(n)
            }
            seen.insert(p.slot)
        }
    }

    @discardableResult
    func spawn(key: String, near parent: Pet?) -> Pet {
        world.refresh(includeWindows: Prefs.useWindows)
        let u = world.union.isNull ? CGRect(x: 0, y: 0, width: 1440, height: 900) : world.union
        let pet: Pet
        if let parent {
            pet = Pet(key: key, x: parent.x, y: parent.y + 20)
            pet.vx = CGFloat.random(in: -420...420)
            pet.vy = 760
            pet.grounded = false
            pet.dir = pet.vx >= 0 ? 1 : -1
        } else {
            let x = CGFloat.random(in: (u.minX + 200)...(u.maxX - 200))
            pet = Pet(key: key, x: x, y: u.maxY - 200)
            pet.grounded = false
        }
        pet.slot = 0
        var n = 0
        let used = Set(pets.filter { $0.dying == nil }.map(\.slot))
        while used.contains(n) { n += 1 }
        pet.slot = n
        pets.append(pet)
        if !Prefs.paused { pet.panel.orderFrontRegardless() }
        return pet
    }

    /// Add a free-roaming pet by hand (menu bar → "Añadir mascota").
    func addPet() {
        guard pets.filter({ $0.dying == nil }).count < 12 else { return }
        spawn(key: "extra:\(UUID().uuidString.prefix(6))", near: pets.first { $0.dying == nil })
    }

    func removeExtras() {
        for p in pets where p.key.hasPrefix("extra:") { p.dying = 0.0001 }
    }

    // MARK: social life

    /// When two or more pets have nothing to do, now and then one goes over to the other.
    private func matchmake(now: Double) {
        nextMatch = now + Double.random(in: 2...5)
        let free = pets.filter { p in
            p.dying == nil && !p.dragging && p.grounded && p.agentState == .idle && p.mode != .sleep
                && { if case .none = p.social { return p.mode != .social } else { return false } }()
        }
        guard !Power.saving, free.count >= 2, Double.random(in: 0..<1) < 0.55 else { return }
        let a = free.randomElement()!
        let near = free.filter { $0 !== a && $0.surface == a.surface && abs($0.x - a.x) < 800 }
        guard let b = near.min(by: { abs($0.x - a.x) < abs($1.x - a.x) }) else { return }
        a.startVisit(b, now: now)
    }

    // MARK: usage limits

    /// Show the usage bars when a limit moved by at least `usageDelta` points since the last time they were shown.
    private func limitsChanged(now: Double) {
        let cur = (LimitsStore.value(LimitsStore.shared.five) ?? 0, LimitsStore.value(LimitsStore.shared.seven) ?? 0)
        defer { if shownLimits.0 < 0 { shownLimits = cur } }
        guard shownLimits.0 >= 0 else { return }   // first read only sets the baseline
        if abs(cur.0 - shownLimits.0) >= Prefs.usageDelta || abs(cur.1 - shownLimits.1) >= Prefs.usageDelta {
            shownLimits = cur
            let alive = pets.filter { $0.dying == nil }
            (alive.first { $0.agentState != .idle } ?? alive.first)?.showUsage(now: now)
        }
    }

    func showUsageNow() {
        let alive = pets.filter { $0.dying == nil }
        (alive.first { $0.agentState != .idle } ?? alive.first)?.showUsage(now: CACurrentMediaTime())
    }

    // MARK: tick

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        tickCount += 1

        let paused = Prefs.paused
        if paused != wasPaused {
            wasPaused = paused
            for p in pets { paused ? p.panel.orderOut(nil) : p.panel.orderFrontRegardless() }
        }
        let saving = Power.saving
        if paused { setRate(4); return }
        setRate(pets.allSatisfy(isResting) ? (saving ? 4 : 12) : (saving ? 20 : 30))

        // "always show" turned off while idle -> let the home pet go
        if !Prefs.alwaysShow, agents.isEmpty {
            for p in pets where p.key == "home" && p.dying == nil { p.dying = 0.0001 }
        } else if Prefs.alwaysShow, agents.isEmpty, !pets.contains(where: { $0.dying == nil }) {
            spawn(key: "home", near: nil)
        }

        // Asking the window server for every window is the costly part of a tick. Pets standing on a window or in
        // the air need fresh positions (10 Hz); pets walking on the floor only need to notice windows now and then.
        let busy = pets.contains { $0.dying == nil && (!$0.grounded || $0.dragging || $0.surface != .floor) }
        if tickCount % (saving ? (busy ? 4 : 12) : (busy ? 6 : 20)) == 0 || world.union.isNull { world.refresh(includeWindows: Prefs.useWindows) }

        if Prefs.usage, LimitsStore.shared.refresh(now: now) { limitsChanged(now: now) }

        if Prefs.social && now >= nextMatch { matchmake(now: now) }

        let mouse = NSEvent.mouseLocation
        for p in pets {
            p.step(dt: dt, now: now, world: world)
            p.syncWindow(now: now)

            // click-through except on the sprite itself
            let over = p.dragging || (p.dying == nil && p.hitRect.contains(mouse))
            if p.panel.ignoresMouseEvents == over { p.panel.ignoresMouseEvents = !over }
            // wake sleepers when the mouse comes close
            if p.mode == .sleep, hypot(mouse.x - p.x, mouse.y - p.y) < 90 {
                p.mode = .idle; p.modeUntil = now + 1
            }
        }

        // remove the ones whose poof finished
        for p in pets where (p.dying ?? 0) > 0.5 {
            p.panel.orderOut(nil)
            p.panel.contentView = nil
        }
        pets.removeAll { ($0.dying ?? 0) > 0.5 }
    }
}
