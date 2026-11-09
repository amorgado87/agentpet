import Foundation

/// Plan usage limits (the "Session 5hr" and "Weekly 7 day" bars of Claude's usage page).
/// Claude Code hands these to its status line script as `rate_limits`; `AgentPet --statusline` is such a
/// script: it stores them in `limits.json`, which this store reads. No network, no credentials involved.
final class LimitsStore {
    static let shared = LimitsStore()

    struct Window { var pct: Double; var resets: Date? }

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AgentPet/limits.json")
    }

    private(set) var five: Window?
    private(set) var seven: Window?
    private var mtime: Date?
    private var lastCheck = 0.0

    var available: Bool { five != nil || seven != nil }

    /// Cheap: looks at the file's modification date at most every 2 s. Returns true if the values changed.
    @discardableResult
    func refresh(now: Double, force: Bool = false) -> Bool {
        guard force || now - lastCheck > 2 else { return false }
        lastCheck = now
        let m = (try? FileManager.default.attributesOfItem(atPath: Self.fileURL.path))?[.modificationDate] as? Date
        guard let m, m != mtime else { return false }
        mtime = m
        guard let data = try? Data(contentsOf: Self.fileURL),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        func win(_ k: String) -> Window? {
            guard let d = o[k] as? [String: Any], let p = (d["pct"] as? NSNumber)?.doubleValue else { return nil }
            let r = (d["resets"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return Window(pct: p, resets: r)
        }
        let (f, s) = (win("five"), win("seven"))
        let changed = f?.pct != five?.pct || s?.pct != seven?.pct
        five = f; seven = s
        return changed
    }

    /// A window whose reset time has passed is back to zero.
    static func value(_ w: Window?) -> Double? {
        guard let w else { return nil }
        if let r = w.resets, r < Date() { return 0 }
        return max(0, min(100, w.pct))
    }

    var rows: [(String, Double)] {
        var out: [(String, Double)] = []
        if let v = Self.value(five) { out.append(("5h", v)) }
        if let v = Self.value(seven) { out.append(("7d", v)) }
        return out
    }

    // MARK: status line script

    /// `claude` runs this with a JSON document on stdin; we print a tiny status line and keep the limits.
    static func runStatusLine() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        guard let o = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any],
              let rl = o["rate_limits"] as? [String: Any] else { return }
        func norm(_ k: String) -> [String: Any]? {
            guard let d = rl[k] as? [String: Any], let p = (d["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
            var out: [String: Any] = ["pct": p]
            if let r = d["resets_at"] as? NSNumber {
                var t = r.doubleValue; if t > 1e11 { t /= 1000 }
                out["resets"] = t
            } else if let s = d["resets_at"] as? String, let dt = ISO8601DateFormatter().date(from: s) {
                out["resets"] = dt.timeIntervalSince1970
            }
            return out
        }
        var out: [String: Any] = [:]
        if let f = norm("five_hour") { out["five"] = f }
        if let s = norm("seven_day") { out["seven"] = s }
        guard !out.isEmpty else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: out) { try? d.write(to: fileURL, options: .atomic) }
        func pct(_ k: String) -> String { (out[k] as? [String: Any]).flatMap { ($0["pct"] as? Double).map { "\(Int($0.rounded()))%" } } ?? "–" }
        print("5h \(pct("five")) · 7d \(pct("seven"))")
    }
}
