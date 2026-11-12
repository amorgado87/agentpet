import Foundation

/// Reads Claude Code transcripts (~/.claude/projects/**/*.jsonl) incrementally and keeps tokens per hour.
/// Works for the terminal and for the desktop app alike, since both write the same transcripts.
final class UsageMonitor {
    static let shared = UsageMonitor()

    private let q = DispatchQueue(label: "agentpet.usage", qos: .background)
    private let lock = NSLock()
    private var offsets: [String: UInt64] = [:]
    private var seen: [String: (hour: Int, tokens: Int)] = [:]   // message id -> counted tokens
    private var hourly: [Int: Int] = [:]                          // hour index -> input + output + cache creation
    private var started = false
    private var five = 0, week = 0
    private(set) var version = 0
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private let isoPlain = ISO8601DateFormatter()

    /// Rolling totals: the last ~5 hours and the last 7 days.
    var totals: (five: Int, week: Int) { lock.lock(); defer { lock.unlock() }; return (five, week) }
    var hasData: Bool { let t = totals; return t.week > 0 }

    func start() {
        guard !started else { return }
        started = true
        loop()
    }

    private func loop() {
        q.async { [weak self] in
            guard let self else { return }
            if Prefs.usage { self.scan() }
            self.q.asyncAfter(deadline: .now() + (Power.saving ? 30 : 10)) { [weak self] in self?.loop() }
        }
    }

    // MARK: scanning

    private func scan() {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let cutoff = Date().addingTimeInterval(-8 * 86400)
        guard let en = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]) else { return }
        var changed = false
        for case let url as URL in en where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let m = v.contentModificationDate, m >= cutoff, let size = v.fileSize else { continue }
            var off = offsets[url.path] ?? 0
            if UInt64(size) < off { off = 0 }
            if UInt64(size) == off { continue }
            if consume(url: url, from: off, cutoff: cutoff) { changed = true }
        }
        recompute()
        if changed { lock.lock(); version += 1; lock.unlock() }
    }

    private func recompute() {
        let k = Int(Date().timeIntervalSince1970 / 3600)
        lock.lock(); defer { lock.unlock() }
        five = (0..<5).reduce(0) { $0 + (hourly[k - $1] ?? 0) }
        week = (0..<168).reduce(0) { $0 + (hourly[k - $1] ?? 0) }
    }

    private func consume(url: URL, from start: UInt64, cutoff: Date) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        var off = start
        var changed = false
        let needle = Data("\"usage\"".utf8)
        let chunkSize = 16 << 20
        while true {
            do { try fh.seek(toOffset: off) } catch { break }
            guard let chunk = try? fh.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            guard let lastNL = chunk.lastIndex(of: 0x0A) else {
                if chunk.count < chunkSize { break }   // incomplete line still being written
                off += UInt64(chunk.count); continue
            }
            let usable = chunk[chunk.startIndex...lastNL]
            var s = usable.startIndex
            while s < usable.endIndex {
                let e = usable[s...].firstIndex(of: 0x0A) ?? usable.endIndex
                let line = usable[s..<e]
                s = usable.index(after: e)
                guard line.count > 20, line.range(of: needle) != nil else { continue }
                if record(Data(line), cutoff: cutoff) { changed = true }
            }
            off += UInt64(usable.count)
            if chunk.count < chunkSize { break }
        }
        offsets[url.path] = off
        return changed
    }

    private func record(_ line: Data, cutoff: Date) -> Bool {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let msg = o["message"] as? [String: Any],
              let id = msg["id"] as? String,
              let u = msg["usage"] as? [String: Any],
              let ts = o["timestamp"] as? String,
              let date = iso.date(from: ts) ?? isoPlain.date(from: ts), date >= cutoff else { return false }
        if (msg["model"] as? String) == "<synthetic>" { return false }
        func n(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
        let c = n("input_tokens") + n("output_tokens") + n("cache_creation_input_tokens")
        if c == 0 { return false }
        let hour = Int(date.timeIntervalSince1970 / 3600)
        lock.lock(); defer { lock.unlock() }
        if let old = seen[id] {
            // streamed messages repeat with growing counts: keep the largest
            if c <= old.tokens { return false }
            hourly[old.hour, default: 0] -= old.tokens
        }
        seen[id] = (hour, c)
        hourly[hour, default: 0] += c
        return true
    }
}
