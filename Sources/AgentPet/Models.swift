import Foundation

/// What an AI coding agent is doing right now. Providers (Claude Code, Codex, ...) map their own
/// events into this vocabulary, and the pets only know about this.
enum AgentState: String {
    case idle, thinking, coding, running, reading, searching, planning, delegating, responding, waiting, done, error

    var isWorking: Bool { self != .idle }

    var visual: Visual {
        switch self {
        case .idle: return .stand
        case .thinking: return .thinking
        case .coding: return .coding
        case .running: return .running
        case .reading: return .reading
        case .searching: return .searching
        case .planning: return .planning
        case .delegating: return .delegating
        case .responding: return .responding
        case .waiting: return .waiting
        case .done: return .done
        case .error: return .error
        }
    }
}

/// One live agent (or sub-agent) that deserves a pet on the desktop.
struct AgentSnapshot: Identifiable, Equatable {
    var key: String            // stable identity, e.g. "claude:1234" or "claude:1234:toolu_x"
    var parentKey: String?     // set for sub-agents so the new pet pops out of its parent
    var provider: String       // "claude", later "codex", ...
    var label: String          // short title, e.g. project folder
    var state: AgentState
    var text: String           // what it is doing
    var id: String { key }
}

func clip(_ s: String, _ n: Int) -> String {
    let one = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    return one.count > n ? String(one.prefix(n - 1)) + "…" : one
}
