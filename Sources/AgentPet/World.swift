import AppKit

enum Surface: Equatable {
    case floor
    case window(Int)
}

struct Segment {
    var x0: CGFloat
    var x1: CGFloat
    var y: CGFloat
    var surface: Surface
}

/// Everything the pets can stand on: the bottom of each screen and the top edge of every visible window.
/// Coordinates are Cocoa global coordinates (origin bottom-left of the primary display).
final class World {
    private(set) var screens: [CGRect] = []        // visible frames (without menu bar / Dock)
    private(set) var union: CGRect = .zero
    private(set) var rects: [Int: CGRect] = [:]    // window id -> frame
    private(set) var windowSegments: [Segment] = []
    private var segmentsByWindow: [Int: [Segment]] = [:]
    private let myPID = ProcessInfo.processInfo.processIdentifier
    var injected: [CGRect]?   // only for the self-test: fake windows (Cocoa coords, front to back)

    func refresh(includeWindows: Bool) {
        screens = NSScreen.screens.map { $0.visibleFrame }
        union = screens.reduce(CGRect.null) { $0.union($1) }
        guard includeWindows else {
            rects = [:]; windowSegments = []; segmentsByWindow = [:]
            return
        }
        guard let primaryH = NSScreen.screens.first?.frame.height else { return }
        var entries: [(Int, CGRect)] = []
        if let inj = injected {
            for (i, r) in inj.enumerated() { entries.append((1000 + i, r)) }
        } else {
            let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            let list = (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]) ?? []
            for info in list {
                guard (info[kCGWindowLayer as String] as? Int) == 0,
                      let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != myPID,
                      let id = info[kCGWindowNumber as String] as? Int,
                      let bd = info[kCGWindowBounds as String] as? NSDictionary,
                      let b = CGRect(dictionaryRepresentation: bd) else { continue }
                if let a = info[kCGWindowAlpha as String] as? Double, a < 0.05 { continue }
                entries.append((id, CGRect(x: b.minX, y: primaryH - b.maxY, width: b.width, height: b.height)))
            }
        }

        var newRects: [Int: CGRect] = [:]
        var segs: [Segment] = []
        var byWin: [Int: [Segment]] = [:]
        var front: [CGRect] = []

        for (id, r) in entries {
            if r.width < 120 || r.height < 60 { continue }
            newRects[id] = r

            let top = r.maxY
            let floorHere = floorY(at: r.midX) ?? union.minY
            let ceiling = union.maxY - 70
            if top > floorHere + 28 && top < ceiling {
                // Remove the parts of the top edge hidden behind windows in front of this one.
                var spans: [(CGFloat, CGFloat)] = [(r.minX, r.maxX)]
                for f in front where f.minY < top && f.maxY >= top - 0.5 {
                    var next: [(CGFloat, CGFloat)] = []
                    for s in spans {
                        if f.maxX <= s.0 || f.minX >= s.1 { next.append(s); continue }
                        if f.minX > s.0 { next.append((s.0, f.minX)) }
                        if f.maxX < s.1 { next.append((f.maxX, s.1)) }
                    }
                    spans = next
                }
                for s in spans where s.1 - s.0 >= 60 {
                    let seg = Segment(x0: s.0, x1: s.1, y: top, surface: .window(id))
                    segs.append(seg)
                    byWin[id, default: []].append(seg)
                }
            }
            front.append(r)
        }
        rects = newRects
        windowSegments = segs
        segmentsByWindow = byWin
    }

    /// Y of the ground at a given x (bottom of the screen that contains x), nil if x is outside every screen.
    func floorY(at x: CGFloat) -> CGFloat? {
        var best: CGFloat?
        for s in screens where x >= s.minX && x <= s.maxX {
            best = min(best ?? .greatestFiniteMagnitude, s.minY)
        }
        return best
    }

    var floorSegments: [Segment] {
        screens.map { Segment(x0: $0.minX, x1: $0.maxX, y: $0.minY, surface: .floor) }
    }

    func segment(window id: Int, containing x: CGFloat, margin: CGFloat = 0) -> Segment? {
        segmentsByWindow[id]?.first { x >= $0.x0 + margin && x <= $0.x1 - margin }
    }

    func surfaceY(_ s: Surface, at x: CGFloat) -> CGFloat? {
        switch s {
        case .floor: return floorY(at: x)
        case .window(let id): return segment(window: id, containing: x)?.y
        }
    }

    /// Highest surface crossed while falling from prevY to y at x.
    func landing(x: CGFloat, prevY: CGFloat, y: CGFloat) -> (Surface, CGFloat)? {
        var best: (Surface, CGFloat)?
        for s in windowSegments where x >= s.x0 + 3 && x <= s.x1 - 3 && prevY >= s.y - 1 && y <= s.y {
            if best == nil || s.y > best!.1 { best = (s.surface, s.y) }
        }
        if let fy = floorY(at: x), y <= fy {
            if best == nil || fy > best!.1 { best = (.floor, fy) }
        }
        return best
    }
}
