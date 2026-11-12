import Foundation

/// A provider turns "what is running on this Mac" into agent snapshots.
/// Today only Claude Code exists; Codex & friends will implement the same protocol.
protocol AgentProvider {
    var id: String { get }
    func poll() -> [AgentSnapshot]
}

/// Polls every provider on a background queue and publishes the merged result.
final class AgentMonitor {
    var onUpdate: (([AgentSnapshot]) -> Void)?
    private let queue = DispatchQueue(label: "agentpet.monitor", qos: .utility)
    private var running = false
    private let claude = ClaudeCodeProvider()
    private let demo = DemoProvider()
    private let chat = ClaudeChatProvider()

    func start() {
        guard !running else { return }
        running = true
        loop()
    }

    private func loop() {
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.running else { return }
            var out: [AgentSnapshot] = []
            if Prefs.demo {
                out = self.demo.poll()
            } else if Prefs.claudeEnabled {
                out += self.claude.poll()
                if Prefs.claudeChat { out += self.chat.poll() }
            }
            self.onUpdate?(out)
            self.queue.asyncAfter(deadline: .now() + Prefs.pollSeconds * (Power.saving ? 2 : 1)) { [weak self] in self?.loop() }
        }
    }
}

// MARK: - Demo

/// Fake agents so you can see the pets without running anything (Settings → Agentes → Modo demo).
final class DemoProvider: AgentProvider {
    let id = "demo"
    private let names = ["api-server", "web-app", "docs", "mobile", "infra", "cli-tool", "data-lab", "game"]
    private let script: [(AgentState, String)] = [
        (.thinking, "Pensando…"),
        (.reading, "Leyendo auth.swift"),
        (.searching, "Buscando “handleLogin”"),
        (.coding, "Editando Router.swift"),
        (.running, "Ejecutando: npm test"),
        (.planning, "Actualizando el plan"),
        (.responding, "Escribiendo respuesta…"),
        (.waiting, "Necesita tu permiso: Bash"),
        (.delegating, "Lanzando 2 subagentes"),
        (.done, "¡Listo! ✓"),
        (.idle, "Esperando órdenes…"),
    ]

    func poll() -> [AgentSnapshot] {
        let now = Date().timeIntervalSince1970
        return (0..<Prefs.demoCount).map { i in
            let step = (Int(now / 5) + i * 3) % script.count
            let (state, text) = script[step]
            return AgentSnapshot(key: "demo:\(i)", parentKey: i == 0 ? nil : "demo:0", provider: "demo",
                                 label: names[i % names.count], state: state, text: text)
        }
    }
}

// MARK: - Claude Code

/// Detects running `claude` processes and reads the tail of their session transcripts
/// (`~/.claude/projects/<cwd>/<session>.jsonl`) to figure out what each one is doing.
final class ClaudeCodeProvider: AgentProvider {
    let id = "claude"
    private var cwdCache: [Int: String] = [:]
    private let home = FileManager.default.homeDirectoryForCurrentUser.path
    private let myPID = Int(ProcessInfo.processInfo.processIdentifier)
    /// Parsing 400 KB of JSON every poll is the expensive part; reuse it until the transcript actually changes.
    private var tailCache: [String: (mtime: Date, size: UInt64, entries: [[String: Any]])] = [:]

    private func cachedTail(path: String, mtime: Date) -> [[String: Any]]? {
        let size = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.uint64Value ?? 0
        if let c = tailCache[path], c.mtime == mtime, c.size == size { return c.entries }
        guard let t = Self.readTail(path: path) else { return nil }
        tailCache[path] = (mtime, size, t)
        if tailCache.count > 24 { tailCache = tailCache.filter { $0.key == path } }
        return t
    }

    struct Proc { var pid: Int; var ppid: Int; var command: String }

    func poll() -> [AgentSnapshot] {
        let procs = Self.processList()
        let claudeProcs = procs.filter { isClaude($0) && $0.pid != myPID }
        // Wrappers (e.g. the desktop app's `disclaimer`) also contain "claude" in their command line:
        // keep only the innermost process, the one that really runs the agent.
        let parents = Set(claudeProcs.map(\.ppid))
        let roots = claudeProcs.filter { !parents.contains($0.pid) }
        guard !roots.isEmpty else { cwdCache = [:]; return [] }

        let cwds = resolveCwds(pids: roots.map(\.pid))
        // sessions per cwd, newest first, handed out to processes in pid order
        var used: [String: Int] = [:]
        var out: [AgentSnapshot] = []

        for proc in roots.sorted(by: { $0.pid < $1.pid }) {
            let cwd = cwds[proc.pid] ?? home
            let project = (cwd as NSString).lastPathComponent
            let label = project.isEmpty ? "claude" : project
            let hasShellChild = procs.contains { $0.ppid == proc.pid && Self.isShell($0.command) }

            let idx = used[cwd, default: 0]
            used[cwd] = idx + 1
            let key = "claude:\(proc.pid)"

            guard let file = transcript(forCwd: cwd, index: idx),
                  let tail = cachedTail(path: file.path, mtime: file.mtime) else {
                out.append(AgentSnapshot(key: key, parentKey: nil, provider: id, label: label, state: .idle, text: "Esperando órdenes…"))
                continue
            }
            let r = Self.analyze(entries: tail, mtime: file.mtime, now: Date(), hasShellChild: hasShellChild)
            out.append(AgentSnapshot(key: key, parentKey: nil, provider: id, label: label, state: r.state, text: r.text))
            for sub in r.subagents {
                out.append(AgentSnapshot(key: "\(key):\(sub.id)", parentKey: key, provider: id,
                                         label: sub.kind, state: sub.state, text: sub.text))
            }
        }
        return out
    }

    // MARK: process discovery

    private func isClaude(_ p: Proc) -> Bool {
        let c = p.command
        if c.contains("ps -axo") || c.contains("AgentPet") { return false }
        if c.contains("@anthropic-ai/claude-code") { return true }
        if c.contains("/claude/versions/") { return true }
        if c.range(of: #"/claude( |$)"#, options: .regularExpression) != nil { return true }
        if c.hasPrefix("claude ") || c == "claude" { return true }
        return false
    }

    static func isShell(_ command: String) -> Bool {
        let first = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
        let base = (first as NSString).lastPathComponent
        return ["zsh", "bash", "sh", "fish", "-zsh", "-bash"].contains(base)
    }

    static func processList() -> [Proc] {
        guard let text = run("/bin/ps", ["-axo", "pid=,ppid=,command="]) else { return [] }
        var out: [Proc] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int(parts[0]), let ppid = Int(parts[1]) else { continue }
            out.append(Proc(pid: pid, ppid: ppid, command: String(parts[2])))
        }
        return out
    }

    private func resolveCwds(pids: [Int]) -> [Int: String] {
        let missing = pids.filter { cwdCache[$0] == nil }
        if !missing.isEmpty,
           let text = Self.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fpn", "-p", missing.map(String.init).joined(separator: ",")]) {
            var cur: Int?
            for line in text.split(separator: "\n") {
                if line.hasPrefix("p") { cur = Int(line.dropFirst()) }
                else if line.hasPrefix("n"), let c = cur { cwdCache[c] = String(line.dropFirst()) }
            }
        }
        let alive = Set(pids)
        cwdCache = cwdCache.filter { alive.contains($0.key) }
        return cwdCache
    }

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

    // MARK: transcripts

    private func transcript(forCwd cwd: String, index: Int) -> (path: String, mtime: Date)? {
        let fm = FileManager.default
        let root = home + "/.claude/projects"
        let encoded = String(cwd.map { ($0.isLetter || $0.isNumber) && $0.isASCII ? $0 : "-" })
        var dir = root + "/" + encoded
        if !fm.fileExists(atPath: dir) {
            // fall back to a loose, case-insensitive match
            let names = (try? fm.contentsOfDirectory(atPath: root)) ?? []
            guard let m = names.first(where: { $0.lowercased() == encoded.lowercased() }) else { return nil }
            dir = root + "/" + m
        }
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return nil }
        let jsonl = files.filter { $0.hasSuffix(".jsonl") }.compactMap { name -> (String, Date)? in
            let p = dir + "/" + name
            guard let attrs = try? fm.attributesOfItem(atPath: p), let m = attrs[.modificationDate] as? Date else { return nil }
            return (p, m)
        }.sorted { $0.1 > $1.1 }
        guard !jsonl.isEmpty else { return nil }
        let pick = jsonl[min(index, jsonl.count - 1)]
        return (pick.0, pick.1)
    }

    static func readTail(path: String, bytes: Int = 400_000) -> [[String: Any]]? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd(), !data.isEmpty else { return nil }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }       // partial first line
        var out: [[String: Any]] = []
        for l in lines {
            if let obj = try? JSONSerialization.jsonObject(with: Data(l)) as? [String: Any] { out.append(obj) }
        }
        return out
    }

    // MARK: analysis

    struct SubAgent { var id: String; var kind: String; var state: AgentState; var text: String }
    struct Result { var state: AgentState; var text: String; var subagents: [SubAgent] }

    static func analyze(entries: [[String: Any]], mtime: Date, now: Date, hasShellChild: Bool) -> Result {
        var pending: [String: (kind: String, desc: String)] = [:]
        var last: [String: Any]?

        for e in entries {
            guard let type = e["type"] as? String, type == "assistant" || type == "user" else { continue }
            if (e["isSidechain"] as? Bool) == true || (e["isMeta"] as? Bool) == true { continue }
            guard let msg = e["message"] as? [String: Any] else { continue }
            if let blocks = msg["content"] as? [[String: Any]] {
                for b in blocks {
                    switch b["type"] as? String {
                    case "tool_use":
                        let name = b["name"] as? String ?? ""
                        if name == "Task" || name == "Agent", let id = b["id"] as? String {
                            let input = b["input"] as? [String: Any] ?? [:]
                            pending[id] = ((input["subagent_type"] as? String) ?? "agente",
                                           (input["description"] as? String) ?? "Subagente")
                        }
                    case "tool_result":
                        if let id = b["tool_use_id"] as? String { pending.removeValue(forKey: id) }
                    default: break
                    }
                }
            }
            last = e
        }

        let subs: [SubAgent] = pending.sorted { $0.key < $1.key }.map { id, v in
            let k = v.kind.lowercased()
            let st: AgentState = k.contains("explor") || k.contains("search") ? .searching
                : k.contains("plan") ? .planning
                : k.contains("review") ? .reading
                : k.contains("test") ? .running
                : .coding
            return SubAgent(id: String(id.suffix(8)), kind: v.kind, state: st, text: clip(v.desc, 46))
        }

        let age = now.timeIntervalSince(mtime)
        func idle() -> Result { Result(state: .idle, text: "Esperando órdenes…", subagents: subs) }
        func thinking() -> Result {
            age < 120 ? Result(state: .thinking, text: "Pensando…", subagents: subs) : idle()
        }

        guard let last, let type = last["type"] as? String,
              let msg = last["message"] as? [String: Any] else { return idle() }

        if type == "user" { return thinking() }

        let blocks = msg["content"] as? [[String: Any]] ?? []
        guard let lb = blocks.last else { return thinking() }

        switch lb["type"] as? String {
        case "thinking":
            return thinking()
        case "text":
            let stop = msg["stop_reason"] as? String
            if stop == "end_turn" || stop == "stop_sequence" {
                if !subs.isEmpty { return Result(state: .delegating, text: "Esperando a \(subs.count) subagente\(subs.count == 1 ? "" : "s")", subagents: subs) }
                return age < 8 ? Result(state: .done, text: "¡Listo! ✓", subagents: subs) : idle()
            }
            if age < 10 { return Result(state: .responding, text: "Escribiendo respuesta…", subagents: subs) }
            return thinking()
        case "tool_use":
            let name = lb["name"] as? String ?? ""
            let input = lb["input"] as? [String: Any] ?? [:]
            if name == "Task" || name == "Agent" {
                return Result(state: .delegating, text: "Lanzando \(max(1, subs.count)) subagente\(subs.count > 1 ? "s" : "")", subagents: subs)
            }
            var (state, text) = describe(tool: name, input: input)
            let needsApproval = ["Bash", "Edit", "Write", "MultiEdit", "NotebookEdit"].contains(name)
                || name.hasPrefix("mcp__") || name == "WebFetch"
            if age > 6 && needsApproval {
                if name == "Bash" && hasShellChild {
                    // a long command is running: stay in "running"
                } else if age < 3600 {
                    state = .waiting
                    text = "Necesita tu permiso: " + text
                }
            }
            if age > 3600 { return idle() }
            return Result(state: state, text: clip(text, 70), subagents: subs)
        default:
            return thinking()
        }
    }

    private static func describe(tool name: String, input: [String: Any]) -> (AgentState, String) {
        func base(_ key: String = "file_path") -> String {
            let p = (input[key] as? String) ?? (input["path"] as? String) ?? ""
            return p.isEmpty ? "archivo" : (p as NSString).lastPathComponent
        }
        switch name {
        case "Edit", "MultiEdit": return (.coding, "Editando \(base())")
        case "Write": return (.coding, "Escribiendo \(base())")
        case "NotebookEdit": return (.coding, "Editando notebook \(base("notebook_path"))")
        case "Bash":
            if let d = input["description"] as? String, !d.isEmpty { return (.running, "Ejecutando: " + d) }
            return (.running, "$ " + ((input["command"] as? String) ?? ""))
        case "Read": return (.reading, "Leyendo \(base())")
        case "Grep": return (.searching, "Buscando “\((input["pattern"] as? String) ?? "")”")
        case "Glob": return (.searching, "Buscando \((input["pattern"] as? String) ?? "archivos")")
        case "LS": return (.reading, "Listando \(base("path"))")
        case "WebFetch":
            let host = URL(string: (input["url"] as? String) ?? "")?.host ?? "la web"
            return (.searching, "Leyendo \(host)")
        case "WebSearch": return (.searching, "Buscando en la web: \((input["query"] as? String) ?? "")")
        case "TodoWrite": return (.planning, "Actualizando el plan")
        case "ExitPlanMode": return (.planning, "Presentando el plan")
        default:
            if name.hasPrefix("mcp__") {
                let parts = name.split(separator: "_", omittingEmptySubsequences: true).map(String.init)
                return (.coding, "Usando \(parts.dropFirst().joined(separator: "/"))")
            }
            return (.coding, "Usando \(name)")
        }
    }
}
