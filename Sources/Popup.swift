import AppKit
import SwiftUI

enum BreakKind { case eyes, walk }

final class PopupModel: ObservableObject {
    @Published var kind: BreakKind = .eyes
    @Published var done = false
    @Published var title = ""
    @Published var subtitle = ""
    @Published var pointerX: CGFloat = 160
    var start = Date()
    var duration: Double = 20
}

private let panelFill = Color(red: 0.14, green: 0.15, blue: 0.19)
private let line = Color(red: 0.05, green: 0.05, blue: 0.07)
private let textColor = Color(red: 0.93, green: 0.91, blue: 0.85)
private let slate = Color(red: 0.27, green: 0.30, blue: 0.36)
private let orange = Color(red: 0.88, green: 0.40, blue: 0.18)
private let green = Color(red: 0.30, green: 0.58, blue: 0.33)

/// A rectangle with stepped pixel corners.
struct PixelBox: Shape {
    var step: CGFloat = 4
    func path(in r: CGRect) -> Path {
        let s = step
        var p = Path()
        p.addLines([
            CGPoint(x: r.minX + s, y: r.minY), CGPoint(x: r.maxX - s, y: r.minY),
            CGPoint(x: r.maxX - s, y: r.minY + s), CGPoint(x: r.maxX, y: r.minY + s),
            CGPoint(x: r.maxX, y: r.maxY - s), CGPoint(x: r.maxX - s, y: r.maxY - s),
            CGPoint(x: r.maxX - s, y: r.maxY), CGPoint(x: r.minX + s, y: r.maxY),
            CGPoint(x: r.minX + s, y: r.maxY - s), CGPoint(x: r.minX, y: r.maxY - s),
            CGPoint(x: r.minX, y: r.minY + s), CGPoint(x: r.minX + s, y: r.minY + s),
        ])
        p.closeSubpath()
        return p
    }
}

struct PixelButtonStyle: ButtonStyle {
    var fill: Color
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(PixelBox(step: 2).fill(fill))
            .overlay(PixelBox(step: 2).stroke(line, lineWidth: 2))
            .background(PixelBox(step: 2).fill(line).offset(x: pressed ? 0 : 2, y: pressed ? 0 : 3))
            .offset(x: pressed ? 2 : 0, y: pressed ? 3 : 0)
    }
}

struct PopupView: View {
    @ObservedObject var model: PopupModel
    var onSkip: () -> Void
    var onSnooze: () -> Void
    var onWalking: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Stepped pointer aimed at Moko in the menu bar.
            Canvas { ctx, size in
                let x = model.pointerX - 2
                for row in 0..<3 {
                    let w = CGFloat(row) * 8 + 4
                    let rect = CGRect(x: x - CGFloat(row) * 4, y: CGFloat(row) * 3, width: w, height: 3)
                    ctx.fill(Path(rect), with: .color(line))
                }
            }
            .frame(height: 9)

            VStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 0.125)) { timeline in
                    Canvas { ctx, size in
                        let t = timeline.date.timeIntervalSince(model.start)
                        ctx.withCGContext { cg in
                            Scene.draw(in: cg, kind: model.kind, done: model.done, t: t, duration: model.duration)
                        }
                    }
                }
                .frame(width: Scene.width, height: Scene.height)
                .overlay(Rectangle().stroke(line, lineWidth: 2))

                Text(model.title)
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundColor(textColor)
                Text(model.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(textColor.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if !model.done {
                    HStack(spacing: 10) {
                        Button("skip", action: onSkip).buttonStyle(PixelButtonStyle(fill: slate))
                        if model.kind == .walk {
                            Button("in 10 min", action: onSnooze).buttonStyle(PixelButtonStyle(fill: orange))
                            Button("walking", action: onWalking).buttonStyle(PixelButtonStyle(fill: green))
                        } else {
                            Button("in 5 min", action: onSnooze).buttonStyle(PixelButtonStyle(fill: orange))
                        }
                    }
                    .padding(.bottom, 3)
                }
            }
            .padding(12)
            .background(PixelBox().fill(panelFill))
            .overlay(PixelBox().stroke(line, lineWidth: 3))
        }
        .frame(width: 320)
    }
}

/// The pixel scene inside the popup: 72x28 chunky cells at dusk.
enum Scene {
    static let cell: CGFloat = 4
    static let cols = 72
    static let rows = 28
    static var width: CGFloat { CGFloat(cols) * cell }
    static var height: CGFloat { CGFloat(rows) * cell }

    /// Moko stands taller than the scenery's pixels so it reads as the main character.
    private static let spriteScale: CGFloat = 5

    private static func rgb(_ hex: UInt32) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    private static let digits: [[String]] = [
        ["###", "#.#", "#.#", "#.#", "###"], [".#.", "##.", ".#.", ".#.", "###"],
        ["###", "..#", "###", "#..", "###"], ["###", "..#", "###", "..#", "###"],
        ["#.#", "#.#", "###", "..#", "..#"], ["###", "#..", "###", "..#", "###"],
        ["###", "#..", "###", "#.#", "###"], ["###", "..#", ".#.", ".#.", ".#."],
        ["###", "#.#", "###", "#.#", "###"], ["###", "#.#", "###", "..#", "###"],
    ]

    static func draw(in c: CGContext, kind: BreakKind, done: Bool, t: Double, duration: Double) {
        c.saveGState()
        defer { c.restoreGState() }
        c.setShouldAntialias(false)

        func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: CGColor) {
            c.setFillColor(color)
            c.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: CGFloat(w) * cell, height: CGFloat(h) * cell))
        }
        func cloud(_ x: Int, _ y: Int) {
            let color = rgb(0x8FA6C2)
            fill(x + 2, y, 6, 1, color)
            fill(x, y + 1, 12, 2, color)
        }
        func wrap(_ v: Int, _ m: Int) -> Int { ((v % m) + m) % m }
        let spriteHeight = CGFloat(Sprite.height) * spriteScale
        let spriteY = 26 * cell - spriteHeight

        switch kind {
        case .eyes:
            fill(0, 0, cols, rows, rgb(0x41628C))
            fill(0, 12, cols, 12, rgb(0x6F8FB0))
            // Sun low on the horizon.
            fill(60, 2, 4, 6, rgb(0xF2A03D))
            fill(59, 3, 6, 4, rgb(0xF2A03D))
            cloud(wrap(Int(t * 1.5) + 8, cols + 12) - 12, 3)
            cloud(wrap(Int(t * 0.8) + 44, cols + 12) - 12, 8)
            // Faraway mountains, with snowy tips.
            for x in 0..<cols {
                let peaks: [(Int, Int)] = [(30, 9), (48, 14), (67, 8)]
                let h = peaks.map { $0.1 - abs(x - $0.0) }.max() ?? 0
                guard h > 0 else { continue }
                fill(x, 24 - h, 1, h, rgb(0x2E3B57))
                if h > 9 { fill(x, 24 - h, 1, h - 9, rgb(0xE9EEF2)) }
            }
            fill(0, 24, cols, 4, rgb(0x3F6B46))
            fill(0, 24, cols, 1, rgb(0x305538))
            Sprite.draw(in: c, x: 2 * cell, y: spriteY, scale: spriteScale, mood: done ? .happy : .lookFar, t: t)

            if !done {
                // Countdown digits and a progress bar on the ground.
                let left = max(0, Int(ceil(duration - t)))
                let digitColor = rgb(0xFFFFFF)
                for (i, ch) in String(left).enumerated() {
                    let glyph = digits[ch.wholeNumberValue ?? 0]
                    for (row, line) in glyph.enumerated() {
                        for (col, px) in line.enumerated() where px == "#" {
                            fill(27 + i * 8 + col * 2, 2 + row * 2, 2, 2, digitColor)
                        }
                    }
                }
                let total = 44
                let filled = min(total, Int(Double(total) * max(0, t) / duration))
                fill(25, 25, total, 2, rgb(0x1B1C22))
                fill(25, 25, filled, 2, rgb(0xFFC21F))
            }

        case .walk:
            fill(0, 0, cols, rows, rgb(0x41628C))
            fill(0, 10, cols, 11, rgb(0x6F8FB0))
            cloud(wrap(Int(t * 1.5) + 10, cols + 12) - 12, 3)
            cloud(wrap(Int(t * 1.0) + 50, cols + 12) - 12, 7)
            // Pines drift by slower than the rocks, for a bit of depth.
            let treeScroll = Int(t * 4)
            for i in 0..<3 {
                let x = wrap(i * 30 + 6 - treeScroll, 90) - 8
                let pine = rgb(0x24503A)
                fill(x + 3, 18, 2, 4, rgb(0x4A3426))
                fill(x + 3, 6, 2, 3, pine)
                fill(x + 2, 9, 4, 3, pine)
                fill(x + 1, 12, 6, 3, pine)
                fill(x, 15, 8, 3, pine)
            }
            fill(0, 21, cols, 7, rgb(0x3F6B46))
            fill(0, 21, cols, 1, rgb(0x305538))
            fill(0, 25, cols, 3, rgb(0x8A7050))
            let scroll = Int(t * 8)
            for i in 0..<6 {
                let x = wrap(i * 15 + 3 - scroll, 90) - 4
                fill(x, 23 + (i % 2), 3, 1, rgb(0x9AA1AB))
                fill(x + 1, 22 + (i % 2), 1, 1, rgb(0xC3C8CF))
            }
            Sprite.draw(in: c, x: 26 * cell, y: spriteY, scale: spriteScale, mood: done ? .happy : .walk, t: t)
        }
    }
}

/// Clicks register right away, without activating the app or stealing your typing focus.
final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
