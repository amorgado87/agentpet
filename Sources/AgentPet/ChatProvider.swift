import Foundation

/// Claude chat (the Claude desktop app, not Claude Code) keeps no readable log of what it is doing.
/// What we can observe is the app's network traffic: while an answer streams in, the downloaded bytes
/// per second jump far above the idle trickle. This provider samples that and maps it to a pet.
/// It is a heuristic (it cannot tell what the answer is about), hence "Respondiendo…" only.
final class ClaudeChatProvider: AgentProvider {
    let id = "claude-chat"

    private let lock = NSLock()
    private var snapshot: AgentSnapshot?
    private var started = false
    private var netPID: Int?
    private var lastPIDCheck = Date.distantPast
    private var lastHigh = Date.distantPast
    private var highSince: Date?
    private var doneUntil = Date.distantPast
    private var wasActive = false
    private let q = DispatchQueue(label: "agentpet.chat", qos: .utility)

    /// bytes/s above which we consider the app to be streaming an answer
    static let threshold = 1500.0

    func poll() -> [AgentSnapshot] {
        if !started { started = true; loop() }
        lock.lock(); defer { lock.unlock() }
        return snapshot.map { [$0] } ?? []
    }

    private func loop() {
        q.async { [weak self] in
            guard let self else { return }
            if Prefs.claudeChat && !Power.saving { self.sample() } else { self.set(nil) }
            self.q.asyncAfter(deadline: .now() + (Prefs.claudeChat ? 2.0 : 3)) { [weak self] in self?.loop() }
        }
    }

    private func set(_ s: AgentSnapshot?) { lock.lock(); snapshot = s; lock.unlock() }

    private func findPID() -> Int? {
        if Date().timeIntervalSince(lastPIDCheck) < 5, let p = netPID { return p }
        lastPIDCheck = Date()
        let out = Shell.run("/bin/ps", ["-axo", "pid=,command="]) ?? ""
        for l in out.split(separator: "\n") where l.contains("Claude.app/") && l.contains("network.mojom.NetworkService") {
            if let pid = Int(l.split(separator: " ").first ?? "") { netPID = pid; return pid }
        }
        netPID = nil
        return nil
    }

    /// bytes received per second over ~1 s, from two consecutive nettop samples
    private func rate(pid: Int) -> Double? {
        guard let out = Shell.run("/usr/bin/nettop", ["-P", "-x", "-L", "2", "-s", "1", "-J", "bytes_in", "-p", "\(pid)"]) else { return nil }
        var vals: [Double] = []
        for l in out.split(separator: "\n") where !l.hasPrefix(",") {
            let cols = l.split(separator: ",")
            if cols.count >= 2, let v = Double(cols[1]) { vals.append(v) }
        }
        guard vals.count >= 2 else { return nil }
        return max(0, vals[vals.count - 1] - vals[vals.count - 2])
    }

    private func sample() {
        guard let pid = findPID() else {
            wasActive = false; highSince = nil
            set(nil)   // app closed: look again later
            Thread.sleep(forTimeInterval: 2)
            return
        }
        guard let r = rate(pid: pid) else { Thread.sleep(forTimeInterval: 1); return }
        let now = Date()
        if r > Self.threshold {
            lastHigh = now
            if highSince == nil { highSince = now }
        }
        let active = now.timeIntervalSince(lastHigh) < 3          // short gaps in the stream still count
        if !active { highSince = nil }
        if wasActive && !active { doneUntil = now.addingTimeInterval(4) }
        wasActive = active

        let state: AgentState
        let text: String
        if active {
            let for_ = now.timeIntervalSince(highSince ?? now)
            state = for_ < 2.5 ? .thinking : .responding
            text = for_ < 2.5 ? "Pensando…" : "Respondiendo…"
        } else if now < doneUntil {
            state = .done; text = "¡Listo! ✓"
        } else {
            state = .idle; text = "Esperando…"
        }
        set(AgentSnapshot(key: "chat:app", parentKey: nil, provider: "claude-chat", label: "Claude chat", state: state, text: text))
    }
}

enum Shell {
    static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
