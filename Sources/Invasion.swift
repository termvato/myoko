import AppKit
import SwiftUI

private enum Timing {
    static let peek = 3.0       // the warning: Moko peeks up from the bottom edge...
    static let darken = 8.0     // ...grows while you keep working, and the screen dims from here
    static let land = 9.5       // full size: it stomps, and input locks at this point
    static let intro = 10.0     // the countdown starts once the shake is over
    static let doneBeat = 1.5
    static let bailHold = 3.0
    static let watchdogGrace = 10.0
    static let frame = 0.125    // 8 fps
}

private let escKeyCode: UInt16 = 53

final class InvasionModel: ObservableObject {
    let kind: BreakKind
    let duration: Double
    let canSnooze: Bool
    var onSnooze: () -> Void = {}
    var start = Date()
    @Published var escProgress: Double = 0

    init(kind: BreakKind, duration: Double, canSnooze: Bool) {
        self.kind = kind
        self.duration = duration
        self.canSnooze = canSnooze
    }

    var total: Double { Timing.intro + duration + Timing.doneBeat }
    func isDone(at t: Double) -> Bool { t >= Timing.intro + duration }
    func secondsLeft(at t: Double) -> Int {
        max(0, Int(ceil(duration - max(0, t - Timing.intro))))
    }

    func mood(at t: Double) -> Mood {
        if t < Timing.land { return .idle }
        if t < Timing.intro { return .alert }
        if isDone(at: t) { return .happy }
        return kind == .eyes ? .lookFar : .walk
    }

    var title: String { kind == .eyes ? "look far." : "go walk." }
    func warning(at t: Double) -> String {
        let seconds = max(1, Int(ceil(Timing.land - t)))
        return (kind == .eyes ? "look far in \(seconds)" : "walk in \(seconds)") + " · hold esc to skip"
    }
    var subtitle: String {
        kind == .eyes ? "pick something far away, 6 m or more." : "get up. a few minutes is enough."
    }
}

/// Where everything sits on a screen, in y-down points.
private struct InvasionLayout {
    let size: CGSize
    let topInset: CGFloat
    let scale: CGFloat
    let landY: CGFloat

    init(size: CGSize, topInset: CGFloat, primary: Bool) {
        self.size = size
        self.topInset = topInset
        let share: CGFloat = primary ? 0.45 : 0.2
        scale = max(2, floor(size.height * share / CGFloat(Sprite.height)))
        let height = CGFloat(Sprite.height) * scale
        landY = primary ? floor(size.height * 0.10) : floor((size.height - height) / 2)
    }

    var spriteWidth: CGFloat { CGFloat(Sprite.width) * scale }
    var spriteHeight: CGFloat { CGFloat(Sprite.height) * scale }
    var spriteX: CGFloat { floor((size.width - spriteWidth) / 2) }
    var ground: CGFloat { landY + spriteHeight }
    var peekScale: CGFloat { max(2, floor(scale / 3)) }
}

private enum InvasionArt {
    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }

    private static let glyphs: [Character: [String]] = [
        "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", "###", "..#", "###"],
        "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
        "6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
        "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
        ":": ["...", ".#.", "...", ".#.", "..."],
    ]

    /// Stepped, so the screen darkens in hard bands: a light tint during the warning so you can
    /// still work, then most of the way to black during the fall.
    static func dimAlpha(at t: Double) -> CGFloat {
        if t < Timing.darken {
            return max(0.02, floor(t / Timing.darken * 4) / 4 * 0.2)
        }
        let steps = floor(min((t - Timing.darken) / (Timing.land - Timing.darken), 1) * 5) / 5
        return 0.2 + CGFloat(steps) * 0.74
    }

    static func shake(at t: Double) -> CGSize {
        guard t >= Timing.land, t < Timing.intro else { return .zero }
        let offsets: [CGSize] = [
            CGSize(width: -16, height: 12), CGSize(width: 12, height: -8),
            CGSize(width: -8, height: 6), CGSize(width: 4, height: -2),
        ]
        return offsets[min(offsets.count - 1, Int((t - Timing.land) / Timing.frame))]
    }

    static func draw(in c: CGContext, model: InvasionModel, layout l: InvasionLayout, primary: Bool, t: Double) {
        c.saveGState()
        defer { c.restoreGState() }
        c.setShouldAntialias(false)

        c.setFillColor(rgb(0x0B0C10, dimAlpha(at: t)))
        c.fill(CGRect(origin: .zero, size: l.size))

        let shake = shake(at: t)
        c.translateBy(x: shake.width, y: shake.height)
        let mood = model.mood(at: t)
        if t < Timing.land {
            // Peeks up from the bottom edge with its eye showing, then grows in
            // whole-pixel steps, slowly at first, until its feet reach the ground.
            let small = l.peekScale
            let peekHeight = CGFloat(Sprite.height) * small
            var scale = small
            var feet: CGFloat
            if t < Timing.peek {
                let q = CGFloat(min(t / (Timing.peek * 0.6), 1))
                feet = l.size.height + peekHeight * (1 - 0.72 * q)
            } else {
                let p = CGFloat((t - Timing.peek) / (Timing.land - Timing.peek))
                let eased = p * p
                scale = floor(small + (l.scale - small) * eased)
                let peeking = l.size.height + peekHeight * 0.28
                feet = peeking + (l.ground - peeking) * eased
            }
            feet = floor(feet)
            let x = floor((l.size.width - CGFloat(Sprite.width) * scale) / 2)
            Sprite.draw(in: c, x: x, y: feet - CGFloat(Sprite.height) * scale, scale: scale, mood: mood, t: t)
        } else {
            drawGround(c, layout: l)
            if t < Timing.intro { drawDust(c, layout: l, t: t) }
            Sprite.draw(in: c, x: l.spriteX, y: l.landY, scale: l.scale, mood: mood, t: t)
            if primary, !model.isDone(at: t) {
                drawCountdown(c, seconds: model.secondsLeft(at: t), layout: l)
            }
        }
    }

    private static func drawGround(_ c: CGContext, layout l: InvasionLayout) {
        c.setFillColor(rgb(0x454D5C))
        c.fill(CGRect(x: -40, y: l.ground, width: l.size.width + 80, height: max(4, floor(l.scale / 3))))
    }

    private static func drawDust(_ c: CGContext, layout l: InvasionLayout, t: Double) {
        let frame = CGFloat(Int((t - Timing.land) / Timing.frame) + 1)
        let size = max(4, floor(l.scale / 2))
        c.setFillColor(rgb(0xB8BEC8))
        for i in 0..<10 {
            let side: CGFloat = i % 2 == 0 ? -1 : 1
            let speed = CGFloat(1 + i % 3)
            let x = l.size.width / 2 + side * (l.spriteWidth / 2 + frame * speed * l.scale * 1.5)
            let y = l.ground - size - frame * CGFloat(i % 4) * size
            c.fill(CGRect(x: floor(x), y: floor(y), width: size, height: size))
        }
    }

    private static func drawCountdown(_ c: CGContext, seconds: Int, layout l: InvasionLayout) {
        let text = seconds >= 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : String(seconds)
        let pixel = max(6, floor(l.size.height / 45))
        var x = l.spriteX + l.spriteWidth + pixel * 3
        let y = floor(l.landY + l.spriteHeight * 0.30)
        c.setFillColor(rgb(0xFFFFFF))
        for ch in text {
            for (row, line) in (glyphs[ch] ?? []).enumerated() {
                for (col, px) in line.enumerated() where px == "#" {
                    c.fill(CGRect(x: x + CGFloat(col) * pixel, y: y + CGFloat(row) * pixel, width: pixel, height: pixel))
                }
            }
            x += pixel * 4
        }
    }
}

/// One frame of the takeover for one screen, as a pure function of `t`.
struct InvasionFrame: View {
    @ObservedObject var model: InvasionModel
    let primary: Bool
    let size: CGSize
    let topInset: CGFloat
    let t: Double

    private let text = Color(red: 0.93, green: 0.91, blue: 0.85)
    private let line = Color(red: 0.05, green: 0.05, blue: 0.07)
    private let orange = Color(red: 0.88, green: 0.40, blue: 0.18)
    private let amber = Color(red: 1.0, green: 0.76, blue: 0.12)

    var body: some View {
        let layout = InvasionLayout(size: size, topInset: topInset, primary: primary)
        let done = model.isDone(at: t)
        let shake = InvasionArt.shake(at: t)

        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                ctx.withCGContext { cg in
                    InvasionArt.draw(in: cg, model: model, layout: layout, primary: primary, t: t)
                }
            }
            .frame(width: size.width, height: size.height)

            if primary, t >= Timing.land {
                VStack(spacing: 12) {
                    Text(done ? "done." : model.title)
                        .font(.system(size: 44, weight: .heavy, design: .monospaced))
                        .foregroundColor(text)
                    Text(done ? "back to it." : model.subtitle)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundColor(text.opacity(0.75))
                    if model.canSnooze, !done {
                        Button("later") { model.onSnooze() }
                            .buttonStyle(PixelButtonStyle(fill: orange))
                            .padding(.top, 8)
                    }
                }
                .frame(width: size.width)
                .offset(x: shake.width, y: layout.ground + 26 + shake.height)
            }

            if primary, t < Timing.land {
                Text(model.warning(at: t))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(line)
                    .frame(width: size.width)
                    .offset(y: topInset + 10)
            }

            if t >= Timing.land || model.escProgress > 0 {
                bailHint
                    .frame(width: size.width)
                    .offset(y: size.height - 64)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var bailHint: some View {
        VStack(spacing: 8) {
            Text("hold esc to bail")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(text.opacity(0.85))
            ZStack(alignment: .leading) {
                Rectangle().fill(line)
                Rectangle().fill(amber).frame(width: 232 * CGFloat(min(1, model.escProgress)))
            }
            .frame(width: 232, height: 8)
            .padding(4)
            .overlay(Rectangle().stroke(text.opacity(0.85), lineWidth: 2))
        }
    }
}

private struct InvasionRoot: View {
    @ObservedObject var model: InvasionModel
    let primary: Bool
    let size: CGSize
    let topInset: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: Timing.frame)) { timeline in
            InvasionFrame(model: model, primary: primary, size: size, topInset: topInset,
                          t: timeline.date.timeIntervalSince(model.start))
        }
        .ignoresSafeArea()
    }
}

private final class InvasionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Moko takes over every screen until the break is over.
///
/// The first stretch is only a warning: clicks and keys still reach your apps. Input locks when
/// Moko lands.
///
/// Ways out, none of which depend on SwiftUI: hold Esc for 3 seconds, or the watchdog at
/// duration + 10s. Cmd-Opt-Esc is deliberately left working. The caller must keep a strong
/// reference only if it wants to call `stop()`; the watchdog keeps this object alive until then.
final class Invasion {
    /// How long the warning runs before the break itself starts.
    static var warningSeconds: Double { Timing.intro }

    private let model: InvasionModel
    private let onFinished: () -> Void
    private let onBail: () -> Void
    private let onSnooze: (() -> Void)?

    private var windows: [NSWindow] = []
    private var tickTimer: Timer?
    private var watchdog: Timer?
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var previousApp: NSRunningApplication?
    private var previousOptions: NSApplication.PresentationOptions = []
    private var started = false
    private var blocking = false
    private var stopped = false
    private var outcomeFired = false
    private var escFlag = false
    private var escSince: Date?

    init(kind: BreakKind, duration: Double, onFinished: @escaping () -> Void,
         onBail: @escaping () -> Void, onSnooze: (() -> Void)?) {
        model = InvasionModel(kind: kind, duration: duration, canSnooze: onSnooze != nil)
        self.onFinished = onFinished
        self.onBail = onBail
        self.onSnooze = onSnooze
    }

    func start() {
        guard !started, !stopped else { return }
        started = true

        // Armed first, so nothing that goes wrong below can trap anyone.
        let limit = Timing.intro + model.duration + Timing.watchdogGrace
        let dog = Timer(timeInterval: limit, repeats: false) { _ in
            // Strong self on purpose: this must fire even if the owner dropped us.
            self.stop()
            self.fire(self.onFinished)
        }
        RunLoop.main.add(dog, forMode: .common)
        watchdog = dog

        model.start = Date()
        model.onSnooze = { [weak self] in self?.snooze() }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            if event.keyCode == escKeyCode { self?.escFlag = event.type == .keyDown }
            return nil // swallow every key while invading
        }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                               object: nil, queue: .main) { [weak self] _ in self?.buildWindows() },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in self?.takeFocus() },
            // Deliberately no re-activation here: fighting for focus could get in the way
            // of the Force Quit window.
            center.addObserver(forName: NSApplication.didResignActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in self?.escFlag = false },
        ]

        buildWindows()

        let tick = Timer(timeInterval: Timing.frame, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick
    }

    /// Idempotent. Tears everything down and gives focus back. Fires no callback.
    func stop() {
        guard !stopped else { return }
        stopped = true

        tickTimer?.invalidate()
        tickTimer = nil
        watchdog?.invalidate()
        watchdog = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        windows.forEach { $0.orderOut(nil) }
        windows = []

        guard blocking else { return } // bailed during the warning: focus was never taken
        NSApp.presentationOptions = previousOptions
        previousApp?.activate(options: [])
        previousApp = nil
    }

    /// The warning is over: start swallowing input. Remembers whichever app you ended up in.
    private func lockInput() {
        guard !blocking, !stopped else { return }
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        previousOptions = NSApp.presentationOptions
        blocking = true
        windows.forEach { $0.ignoresMouseEvents = false }
        NSApp.activate(ignoringOtherApps: true)
        takeFocus()
    }

    private func takeFocus() {
        guard !stopped, blocking else { return }
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching]
        windows.first?.makeKeyAndOrderFront(nil)
    }

    private func buildWindows() {
        guard !stopped else { return }
        windows.forEach { $0.orderOut(nil) }
        let screens = NSScreen.screens // the first one holds the menu bar
        windows = screens.enumerated().map { index, screen in
            let window = InvasionWindow(contentRect: screen.frame, styleMask: [.borderless],
                                        backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            // A hint of alpha: once locked, fully clear pixels would let clicks fall through.
            window.backgroundColor = NSColor(white: 0, alpha: 0.02)
            window.hasShadow = false
            window.ignoresMouseEvents = !blocking
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

            let root = InvasionRoot(model: model, primary: index == 0, size: screen.frame.size,
                                    topInset: screen.safeAreaInsets.top)
            let host = FirstClickHostingView(rootView: root)
            host.sizingOptions = []
            host.frame = NSRect(origin: .zero, size: screen.frame.size)
            window.contentView = host
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            return window
        }
        takeFocus()
    }

    private func tick() {
        guard !stopped else { return }
        let now = Date()

        // The key state also covers the case where the app never got keyboard focus.
        let held = escFlag || CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(escKeyCode))
        if held {
            let since = escSince ?? now
            escSince = since
            let progress = now.timeIntervalSince(since) / Timing.bailHold
            if model.escProgress != progress { model.escProgress = progress }
            if progress >= 1 {
                finish(with: onBail)
                return
            }
        } else if escSince != nil {
            escSince = nil
            model.escProgress = 0
        }

        let elapsed = now.timeIntervalSince(model.start)
        if elapsed >= Timing.land { lockInput() }
        if elapsed >= model.total {
            finish(with: onFinished)
        }
    }

    private func snooze() {
        guard let onSnooze else { return }
        finish(with: onSnooze)
    }

    private func finish(with callback: () -> Void) {
        fire(callback)
        stop()
    }

    /// Only one outcome ever reaches the caller.
    private func fire(_ callback: () -> Void) {
        guard !outcomeFired else { return }
        outcomeFired = true
        callback()
    }
}
