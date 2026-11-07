import CoreGraphics
import Foundation

/// What the character is up to. Picks the sprite frames.
enum Mood {
    case idle, alert, lookFar, walk, happy, sleep
}

enum Mascot: String, CaseIterable {
    case eyeball, onion
}

/// A 16x17 pixel character: a hand-drawn base plus per-mood overlays.
enum Sprite {
    static let width = 16
    static let height = 17

    /// Who is on screen. Set from the menu.
    static var mascot: Mascot = .eyeball
    /// 0 is a fresh eye, 1 is overdue for a break. Only the eyeball shows it.
    static var strain: Double = 0

    private static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255,
                alpha: 1)
    }

    private static let shared: [Character: CGColor] = [
        "Y": rgb(0xFFC21F), // exclamation, star
        "Z": rgb(0x6FB4F2), // sleepy z
        "W": rgb(0xFFFFFF),
    ]

    private static let palettes: [Mascot: [Character: CGColor]] = [
        .eyeball: shared.merging([
            "K": rgb(0x24232B), // outline
            "I": rgb(0x3F8FD9), // iris
            "J": rgb(0x2A63A8), // iris rim
            "F": rgb(0xFFD6D0), // tired sclera
            "G": rgb(0xFFB0A8), // very tired sclera
            "R": rgb(0xD8222E), // veins
            "S": rgb(0xE8B48A), // eyelid
            "T": rgb(0xE8B48A), // legs
            "H": rgb(0x3A3946), // top hat
            "A": rgb(0x5E5C70), // top hat shine
            "B": rgb(0xD8222E), // top hat band
        ]) { $1 },
        .onion: shared.merging([
            "K": rgb(0x4A2F2B), // outline
            "O": rgb(0xE9B872), // skin
            "P": rgb(0xC98A45), // skin lines
            "L": rgb(0x7BDB6E), // leaf
            "D": rgb(0x3E9E4F), // stem
            "C": rgb(0xFF8FA0), // cheeks
            "T": rgb(0xE9B872), // legs
        ]) { $1 },
    ]

    /// Rows above the eye are empty because the top hat lives there.
    private static let eyeball: [String] = [
        "................",
        "................",
        "................",
        "................",
        "................",
        "...KWWWWWWWWK...",
        "..KWWWWWWWWWWK..",
        ".KWWWWWWWWWWWWK.",
        ".KWWWWWWWWWWWWK.",
        ".KWWWWWWWWWWWWK.",
        ".KWWWWWWWWWWWWK.",
        "..KWWWWWWWWWWK..",
        "...KKWWWWWWKK...",
        ".....KKKKKK.....",
    ]

    private static let onion: [String] = [
        ".....LL..LL.....",
        "......LLLL......",
        ".......DD.......",
        "......KKKK......",
        "....KKOOOOKK....",
        "...KOOOOOOOOK...",
        "..KOOPOOOOPOOK..",
        ".KOOPOOOOOOPOOK.",
        ".KOOPOOOOOOPOOK.",
        ".KOOPOOOOOOPOOK.",
        ".KOOPOOOOOOPOOK.",
        "..KOOPOOOOPOOK..",
        "...KOOOOOOOOK...",
        "....KKKKKKKK....",
    ]

    /// Veins creep in from the edges in this order as strain rises.
    private static let veins: [(Int, Int)] = [
        (2, 8), (3, 8), (4, 9), (5, 9), (13, 9), (12, 9), (11, 8), (10, 8),
        (3, 6), (4, 7), (12, 6), (11, 7), (2, 10), (3, 10), (4, 10), (13, 7),
        (12, 7), (3, 11), (5, 5), (5, 6), (10, 5), (10, 6), (9, 12), (6, 12),
    ]

    private static let feetStill = ["....KTK..KTK....", "....KKK..KKK...."]
    private static let feetWide = ["...KTK....KTK...", "...KKK....KKK..."]
    private static let feetNarrow = [".....KTKKTK.....", ".....KKKKKK....."]

    /// The grid for this mood at time `t`.
    static func grid(mood: Mood, t: Double) -> [[Character]] {
        let beat = { (rate: Double) in Int(t * rate) % 2 == 1 }
        var hop = false
        var feet = feetStill
        var extras: [(Int, Int, Character)] = []

        switch mood {
        case .alert:
            hop = beat(4)
            if beat(2) { for y in [0, 1, 2] { extras.append((15, y, "Y")) } }
        case .walk:
            hop = beat(4)
            feet = beat(4) ? feetWide : feetNarrow
        case .happy:
            hop = beat(4)
            if beat(2) {
                for (dx, dy) in [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)] { extras.append((13 + dx, dy, "Y")) }
            }
        case .sleep:
            for (dx, dy) in [(0, 0), (1, 0), (2, 0), (2, 1), (1, 2), (0, 3), (1, 3), (2, 3)] {
                extras.append((13 + dx, dy, "Z"))
            }
        default:
            break
        }

        let body = mascot == .eyeball ? eyeballBody(mood: mood, t: t) : onionBody(mood: mood, t: t)

        // Assemble: a hop lifts the body one pixel while the feet stay planted.
        var out = [[Character]](repeating: [Character](repeating: ".", count: width), count: height)
        let offset = hop ? 0 : 1
        for (y, row) in body.enumerated() { out[y + offset] = row }
        if hop { out[14] = Array(feet[0]) }
        out[15] = Array(feet[0])
        out[16] = Array(feet[1])

        // Past the limit the eye starts to bleed a little.
        if mascot == .eyeball, strain > 0.9, mood != .happy {
            out[15 + Int(t * 2) % 2][7] = "R"
        }
        for (x, y, c) in extras { out[y][x] = c }
        return out
    }

    private static let topHat: [String] = [
        "....HHHHHHHH....",
        ".....HAHHHH.....",
        ".....HAHHHH.....",
        ".....BBBBBB.....",
        "..HHHHHHHHHHHH..",
    ]

    /// The hat goes on last so blinks and squints never wipe it.
    private static func eyeballBody(mood: Mood, t: Double) -> [[Character]] {
        var g = bareEye(mood: mood, t: t)
        for (y, row) in topHat.enumerated() {
            for (x, cell) in row.enumerated() where cell != "." { g[y][x] = cell }
        }
        return g
    }

    private static func bareEye(mood: Mood, t: Double) -> [[Character]] {
        var g = eyeball.map(Array.init)

        if strain > 0.6 {
            let tired: Character = strain > 0.85 ? "G" : "F"
            g = g.map { $0.map { $0 == "W" ? tired : $0 } }
        }
        for (x, y) in veins.prefix(Int((strain * Double(veins.count)).rounded())) where g[y][x] != "K" {
            g[y][x] = "R"
        }

        let blinking = mood == .sleep || (mood != .alert && t.truncatingRemainder(dividingBy: 4.3) < 0.25)
        if blinking {
            for y in 1..<13 { g[y] = g[y].map { $0 == "K" || $0 == "." ? $0 : "S" } }
            for x in 2...13 { g[8][x] = "K" }
            return g
        }

        // Iris and pupil, sliding towards whatever the eye is looking at.
        let dx = mood == .lookFar ? 2 : (mood == .walk ? 1 : 0)
        let dy = mood == .lookFar ? -1 : 0
        let cx = 5 + dx, cy = 6 + dy
        for y in 0..<6 {
            for x in 0..<6 where !((x == 0 || x == 5) && (y == 0 || y == 5)) {
                g[cy + y][cx + x] = (x == 0 || x == 5 || y == 0 || y == 5) ? "J" : "I"
            }
        }
        if mood == .alert {
            g[cy + 2][cx + 2] = "K"   // a shocked pinprick
        } else {
            for y in 2...3 { for x in 2...3 { g[cy + y][cx + x] = "K" } }
        }
        g[cy + 1][cx + 1] = "W"

        // Happy: the lower lid pushes up into a squint.
        if mood == .happy {
            for y in 9..<13 { g[y] = g[y].map { $0 == "K" || $0 == "." ? $0 : "S" } }
            for x in 2...13 where g[9][x] != "K" { g[9][x] = "K" }
        }
        return g
    }

    private static func onionBody(mood: Mood, t: Double) -> [[Character]] {
        var g = onion.map(Array.init)
        func set(_ x: Int, _ y: Int, _ c: Character) { g[y][x] = c }

        let shift = (mood == .lookFar || mood == .walk) ? 1 : 0
        let left = 5 + shift, right = 9 + shift
        let blinking = mood == .sleep || (mood != .alert && mood != .happy && t.truncatingRemainder(dividingBy: 4.3) < 0.25)

        for x in [left, right] {
            if blinking {
                set(x, 9, "K"); set(x + 1, 9, "K")
            } else if mood == .happy {
                set(x, 9, "K"); set(x + 1, 8, "K")
            } else {
                set(x, 8, "W"); set(x + 1, 8, "K")
                set(x, 9, "K"); set(x + 1, 9, "K")
            }
        }
        set(3, 10, "C"); set(12, 10, "C")
        set(7, 11, "K"); set(8, 11, "K")
        if mood == .alert { set(7, 12, "K"); set(8, 12, "K") }

        // Leaves sway by shifting the top two rows sideways.
        let sway = mood == .walk ? (beat2(t) ? 1 : -1) : Int(t * 0.8) % 2
        if sway != 0 {
            for y in 0...1 {
                let row = g[y]
                g[y] = (0..<width).map { x in
                    let from = x - sway
                    return from >= 0 && from < width ? row[from] : "."
                }
            }
        }
        return g
    }

    private static func beat2(_ t: Double) -> Bool { Int(t * 4) % 2 == 1 }

    /// Draws at the given scale with hard edges. The context must be y-down.
    static func draw(in c: CGContext, x: CGFloat, y: CGFloat, scale: CGFloat, mood: Mood, t: Double) {
        let palette = palettes[mascot] ?? [:]
        c.saveGState()
        c.setShouldAntialias(false)
        for (row, cells) in grid(mood: mood, t: t).enumerated() {
            for (col, cell) in cells.enumerated() {
                guard let color = palette[cell] else { continue }
                c.setFillColor(color)
                c.fill(CGRect(x: x + CGFloat(col) * scale, y: y + CGFloat(row) * scale, width: scale, height: scale))
            }
        }
        c.restoreGState()
    }
}
