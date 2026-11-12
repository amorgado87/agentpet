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

    struct Row { var name: String; var value: Double; var percent: Bool; var fraction: Double }

    var available: Bool { !rows.isEmpty }

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

    /// Real plan percentages when Claude Code has handed them over; otherwise the tokens used in the last 5 h / 7 days,
    /// counted from the local transcripts (works for the desktop app too).
    var rows: [Row] {
        var out: [Row] = []
        if let v = Self.value(five) { out.append(Row(name: "5h", value: v, percent: true, fraction: v / 100)) }
        if let v = Self.value(seven) { out.append(Row(name: "7d", value: v, percent: true, fraction: v / 100)) }
        if !out.isEmpty { return out }
        let t = UsageMonitor.shared.totals
        if t.week > 0 {
            out = [Row(name: "5h", value: Double(t.five), percent: false, fraction: 0),
                   Row(name: "7d", value: Double(t.week), percent: false, fraction: 0)]
        }
        return out
    }

    // MARK: status line script

    /// `claude` runs this with a JSON document on stdin; we print a tiny status line and keep the limits.
    static func runStatusLine() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let obj = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
        // diagnostics: when did Claude Code last call us and did it include rate_limits? (no conversation data is stored)
        let diag: [String: Any] = ["at": Date().timeIntervalSince1970, "keys": (obj?.keys.sorted() ?? []),
                                   "rate_limits": obj?["rate_limits"] ?? NSNull()]
        if let d = try? JSONSerialization.data(withJSONObject: diag) { try? d.write(to: dir.appendingPathComponent("statusline-last.json"), options: .atomic) }
        guard let o = obj, let rl = o["rate_limits"] as? [String: Any] else { return }
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
